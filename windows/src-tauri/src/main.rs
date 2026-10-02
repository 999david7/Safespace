// Safespace for Windows. The UI and all cryptography live in the WebView (src/); this side only
// touches the disk and the clipboard. The vault key never crosses into Rust.

// No console window behind the app in release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use tauri::{Manager, RunEvent};

/// The vault lives at `%APPDATA%\Safespace\vault.dat`, next to `vault.dat.bak`.
fn vault_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let base = app.path().data_dir().map_err(|e| e.to_string())?;
    Ok(base.join("Safespace").join("vault.dat"))
}

/// Safespace 1.1 called the vault `vault.safespace`; rename it (and its backup) once.
fn migrate_legacy_vault(app: &tauri::AppHandle) {
    let Ok(path) = vault_path(app) else { return };
    let legacy = path.with_file_name("vault.safespace");
    if path.exists() || !legacy.is_file() {
        return;
    }
    if fs::rename(&legacy, &path).is_ok() {
        let legacy_backup = backup_path(&legacy);
        let backup = backup_path(&path);
        if legacy_backup.is_file() && !backup.exists() {
            let _ = fs::rename(legacy_backup, backup);
        }
    }
}

fn backup_path(vault: &PathBuf) -> PathBuf {
    let mut name = vault.as_os_str().to_owned();
    name.push(".bak");
    PathBuf::from(name)
}

#[tauri::command]
fn vault_location(app: tauri::AppHandle) -> Result<String, String> {
    Ok(vault_path(&app)?.display().to_string())
}

#[tauri::command]
fn vault_exists(app: tauri::AppHandle) -> Result<bool, String> {
    Ok(vault_path(&app)?.is_file())
}

#[tauri::command]
fn read_vault(app: tauri::AppHandle) -> Result<String, String> {
    fs::read_to_string(vault_path(&app)?).map_err(|e| format!("Couldn't read the vault: {e}"))
}

/// Older copies that may open when `vault.dat` doesn't: its backup and anything left by 1.1.
/// Returns `[file name, contents]` pairs, newest first.
#[tauri::command]
fn read_vault_fallbacks(app: tauri::AppHandle) -> Result<Vec<(String, String)>, String> {
    let path = vault_path(&app)?;
    let legacy = path.with_file_name("vault.safespace");
    let mut candidates: Vec<(PathBuf, std::time::SystemTime)> = [backup_path(&path), legacy.clone(), backup_path(&legacy)]
        .into_iter()
        .filter_map(|p| {
            let modified = fs::metadata(&p).ok()?.modified().ok()?;
            Some((p, modified))
        })
        .collect();
    candidates.sort_by(|a, b| b.1.cmp(&a.1));
    Ok(candidates
        .into_iter()
        .filter_map(|(p, _)| {
            let name = p.file_name()?.to_string_lossy().into_owned();
            Some((name, fs::read_to_string(&p).ok()?))
        })
        .collect())
}

/// Moves `vault.dat` aside as `vault.dat.unreadable-<seconds>` (never deleted) and makes
/// `contents` the vault. Used when an older copy opened but the current file didn't.
#[tauri::command]
fn restore_vault(app: tauri::AppHandle, contents: String) -> Result<(), String> {
    let path = vault_path(&app)?;
    if path.exists() {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let aside = path.with_file_name(format!("vault.dat.unreadable-{stamp}"));
        fs::rename(&path, aside).map_err(|e| format!("Couldn't restore the vault: {e}"))?;
    }
    write_vault(app, contents)
}

/// Keeps the previous version as `.bak`, then writes atomically (temp file + rename).
#[tauri::command]
fn write_vault(app: tauri::AppHandle, contents: String) -> Result<(), String> {
    let path = vault_path(&app)?;
    let fail = |e: std::io::Error| format!("Couldn't save the vault: {e}");
    fs::create_dir_all(path.parent().expect("vault path has a parent")).map_err(fail)?;
    if path.is_file() {
        let _ = fs::copy(&path, backup_path(&path));
    }
    let mut temp = path.as_os_str().to_owned();
    temp.push(".tmp");
    let temp = PathBuf::from(temp);
    {
        let mut file = fs::File::create(&temp).map_err(fail)?;
        file.write_all(contents.as_bytes()).map_err(fail)?;
        file.sync_all().map_err(fail)?;
    }
    fs::rename(&temp, &path).map_err(fail)
}

/// First run: makes an existing vault file (already checked by the UI) the vault here.
/// Never replaces a vault that exists.
#[tauri::command]
fn adopt_vault(app: tauri::AppHandle, contents: String) -> Result<(), String> {
    if vault_path(&app)?.exists() {
        return Err("A vault already exists on this PC.".into());
    }
    write_vault(app, contents)
}

#[tauri::command]
fn reveal_vault(app: tauri::AppHandle) -> Result<(), String> {
    let path = vault_path(&app)?;
    #[cfg(windows)]
    {
        std::process::Command::new("explorer")
            .arg(format!("/select,{}", path.display()))
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(not(windows))]
    {
        let _ = path;
    }
    Ok(())
}

// MARK: - Clipboard

/// What we last put on the clipboard, so we only ever clear our own copy.
struct ClipboardState {
    owned: Mutex<Option<String>>,
    generation: AtomicU64,
}

fn set_clipboard(text: &str) -> Result<(), arboard::Error> {
    let mut clipboard = arboard::Clipboard::new()?;
    #[cfg(windows)]
    {
        // Keep passwords out of Win+V history, cloud clipboard and clipboard monitors.
        use arboard::SetExtWindows;
        clipboard
            .set()
            .exclude_from_history()
            .exclude_from_cloud()
            .exclude_from_monitoring()
            .text(text)
    }
    #[cfg(not(windows))]
    {
        clipboard.set_text(text)
    }
}

fn clear_if_owned(state: &ClipboardState) {
    let mut owned = state.owned.lock().unwrap();
    if let Some(value) = owned.take() {
        if let Ok(mut clipboard) = arboard::Clipboard::new() {
            if clipboard.get_text().map(|current| current == value).unwrap_or(false) {
                let _ = clipboard.clear();
            }
        }
    }
}

#[tauri::command]
fn copy_text(app: tauri::AppHandle, text: String, clear_after: u64) -> Result<(), String> {
    set_clipboard(&text).map_err(|e| format!("Couldn't copy: {e}"))?;
    let state = app.state::<ClipboardState>();
    *state.owned.lock().unwrap() = Some(text);
    let generation = state.generation.fetch_add(1, Ordering::SeqCst) + 1;
    if clear_after > 0 {
        let app = app.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_secs(clear_after));
            let state = app.state::<ClipboardState>();
            // A newer copy restarts the timer.
            if state.generation.load(Ordering::SeqCst) == generation {
                clear_if_owned(&state);
            }
        });
    }
    Ok(())
}

#[tauri::command]
fn clear_clipboard(app: tauri::AppHandle) {
    clear_if_owned(&app.state::<ClipboardState>());
}

fn main() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(ClipboardState { owned: Mutex::new(None), generation: AtomicU64::new(0) })
        .setup(|app| {
            migrate_legacy_vault(app.handle());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            vault_location,
            vault_exists,
            read_vault,
            write_vault,
            adopt_vault,
            read_vault_fallbacks,
            restore_vault,
            reveal_vault,
            copy_text,
            clear_clipboard,
        ])
        .build(tauri::generate_context!())
        .expect("error while building Safespace");

    app.run(|handle, event| {
        if let RunEvent::Exit = event {
            clear_if_owned(&handle.state::<ClipboardState>());
        }
    });
}
