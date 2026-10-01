// Disk, clipboard and window access. Inside the app this calls the Rust commands in
// src-tauri/src/main.rs; opened in a plain browser (for UI work) it falls back to localStorage.

const tauri = globalThis.__TAURI__;

function browserFallback() {
  const KEY = "safespace.dev-vault";
  let clearTimer;
  return {
    isApp: false,
    vaultLocation: async () => "(browser preview) localStorage",
    vaultExists: async () => localStorage.getItem(KEY) !== null,
    readVault: async () => localStorage.getItem(KEY),
    writeVault: async (contents) => localStorage.setItem(KEY, contents),
    revealVault: async () => {},
    copyText: async (text, clearAfter) => {
      await navigator.clipboard?.writeText(text).catch(() => {});
      clearTimeout(clearTimer);
      if (clearAfter > 0) clearTimer = setTimeout(() => navigator.clipboard?.writeText("").catch(() => {}), clearAfter * 1000);
    },
    clearClipboard: async () => {},
    openURL: async (url) => window.open(url, "_blank", "noopener"),
    minimize: async () => {},
    toggleMaximize: async () => {},
    close: async () => window.close(),
  };
}

function appBridge() {
  const { invoke } = tauri.core;
  const win = () => tauri.window.getCurrentWindow();
  return {
    isApp: true,
    vaultLocation: () => invoke("vault_location"),
    vaultExists: () => invoke("vault_exists"),
    readVault: () => invoke("read_vault"),
    writeVault: (contents) => invoke("write_vault", { contents }),
    revealVault: () => invoke("reveal_vault"),
    copyText: (text, clearAfter) => invoke("copy_text", { text, clearAfter }),
    clearClipboard: () => invoke("clear_clipboard"),
    openURL: (url) => invoke("plugin:opener|open_url", { url }),
    minimize: () => win().minimize(),
    toggleMaximize: () => win().toggleMaximize(),
    close: () => win().close(),
  };
}

export const platform = tauri ? appBridge() : browserFallback();
