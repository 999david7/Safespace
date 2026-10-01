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

/// The vault lives at `%APPDATA%\Safespace\vault.safespace`, next to `vault.safespace.bak`.
fn vault_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let base = app.path().data_dir().map_err(|e| e.to_string())?;
    Ok(base.join("Safespace").join("vault.safespace"))
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
        .invoke_handler(tauri::generate_handler![
            vault_location,
            vault_exists,
            read_vault,
            write_vault,
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
