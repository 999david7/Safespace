// Disk, clipboard and window access. Inside the app this calls the Rust commands in
// src-tauri/src/main.rs; opened in a plain browser (for UI work) it falls back to localStorage.

const tauri = globalThis.__TAURI__;

function browserFallback() {
  const KEY = "safespace.dev-vault";
  // localStorage holds text; a binary vault from the original SafeSpace is kept as base64.
  const BINARY = "base64:";
  const toBytes = (stored) =>
    stored.startsWith(BINARY) ? Uint8Array.from(atob(stored.slice(BINARY.length)), (c) => c.charCodeAt(0)) : new TextEncoder().encode(stored);
  const toStored = (bytes) => (bytes[0] === 0x7b /* { */ ? new TextDecoder().decode(bytes) : BINARY + btoa(String.fromCharCode(...bytes)));
  let clearTimer;
  return {
    isApp: false,
    vaultLocation: async () => "(browser preview) localStorage",
    vaultExists: async () => localStorage.getItem(KEY) !== null,
    readVault: async () => localStorage.getItem(KEY),
    readVaultBytes: async () => toBytes(localStorage.getItem(KEY) ?? ""),
    writeVault: async (contents) => localStorage.setItem(KEY, contents),
    upgradeClassicVault: async (contents) => {
      if (localStorage.getItem(KEY + ".classic") === null) localStorage.setItem(KEY + ".classic", localStorage.getItem(KEY) ?? "");
      localStorage.setItem(KEY, contents);
    },
    adoptVault: async (bytes) => {
      if (localStorage.getItem(KEY) !== null) throw new Error("A vault already exists on this PC.");
      localStorage.setItem(KEY, toStored(bytes));
    },
    readVaultFallbacks: async () => {
      const backup = localStorage.getItem(KEY + ".bak");
      return backup ? [["vault.dat.bak", backup]] : [];
    },
    restoreVault: async (contents) => {
      const current = localStorage.getItem(KEY);
      if (current !== null) localStorage.setItem(KEY + ".unreadable", current);
      localStorage.setItem(KEY, contents);
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
    readVault: () => invoke("read_vault"),
    readVaultBytes: async () => new Uint8Array(await invoke("read_vault_bytes")),
    writeVault: (contents) => invoke("write_vault", { contents }),
    upgradeClassicVault: (contents) => invoke("upgrade_classic_vault", { contents }),
    adoptVault: (bytes) => invoke("adopt_vault", { contents: Array.from(bytes) }),
    readVaultFallbacks: () => invoke("read_vault_fallbacks"),
    restoreVault: (contents) => invoke("restore_vault", { contents }),
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

/**
 * Lets the user pick a vault file (vault.dat, including one from the original SafeSpace, or
 * vault.safespace from older versions) and reads it as both bytes and text.
 */
export function pickVaultFile() {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".dat,.safespace,.bak,application/json";
    input.addEventListener("change", async () => {
      const file = input.files?.[0];
      if (!file) return resolve(null);
      const bytes = new Uint8Array(await file.arrayBuffer());
      resolve({ name: file.name, bytes, text: new TextDecoder().decode(bytes) });
    });
    input.addEventListener("cancel", () => resolve(null));
    input.click();
  });
}
