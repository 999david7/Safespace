// Disk, clipboard and window access. Inside the app this calls the Rust commands in
// src-tauri/src/main.rs; opened in a plain browser (for UI work) it falls back to localStorage.
// Vault files are bytes (Uint8Array) on this side.

const tauri = globalThis.__TAURI__;

/** Tauri sends and receives byte buffers as arrays of numbers. */
const fromWire = (array) => Uint8Array.from(array);
const toWire = (bytes) => Array.from(bytes);

function browserFallback() {
  const KEY = "safespace.dev-vault";
  // localStorage holds strings, so the preview keeps the vault as base64.
  const load = (key) => {
    const stored = localStorage.getItem(key);
    return stored === null ? null : Uint8Array.from(atob(stored), (c) => c.charCodeAt(0));
  };
  const save = (key, bytes) => {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    localStorage.setItem(key, btoa(binary));
  };
  let clearTimer;
  return {
    isApp: false,
    vaultLocation: async () => "(browser preview) localStorage",
    vaultExists: async () => localStorage.getItem(KEY) !== null,
    readVault: async () => load(KEY),
    writeVault: async (contents) => save(KEY, contents),
    adoptVault: async (contents) => {
      if (localStorage.getItem(KEY) !== null) throw new Error("A vault already exists on this PC.");
      save(KEY, contents);
    },
    readVaultFallbacks: async () => {
      const backup = load(KEY + ".bak");
      return backup ? [["vault.dat.bak", backup]] : [];
    },
    restoreVault: async (contents) => {
      const current = localStorage.getItem(KEY);
      if (current !== null) localStorage.setItem(KEY + ".unreadable", current);
      save(KEY, contents);
    },
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
    readVault: async () => fromWire(await invoke("read_vault")),
    writeVault: (contents) => invoke("write_vault", { contents: toWire(contents) }),
    adoptVault: (contents) => invoke("adopt_vault", { contents: toWire(contents) }),
    readVaultFallbacks: async () => (await invoke("read_vault_fallbacks")).map(([name, contents]) => [name, fromWire(contents)]),
    restoreVault: (contents) => invoke("restore_vault", { contents: toWire(contents) }),
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

/** Lets the user pick a vault file (vault.dat, or vault.safespace from older versions) and reads its bytes. */
export function pickVaultFile() {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".dat,.safespace,.bak,application/octet-stream,application/json";
    input.addEventListener("change", async () => {
      const file = input.files?.[0];
      resolve(file ? { name: file.name, data: new Uint8Array(await file.arrayBuffer()) } : null);
    });
    input.addEventListener("cancel", () => resolve(null));
    input.click();
  });
}
