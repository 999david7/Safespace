// Safespace for Windows: the vault desk, lock screens, editor, generator and settings.
// A port of Sources/Safespace (SwiftUI) to plain DOM, with the same behaviour and look.

import * as core from "./core.js";
import { platform } from "./platform.js";

// MARK: - Helpers

const $ = (selector, root = document) => root.querySelector(selector);
const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const hex = (color) => "#" + (color & 0xffffff).toString(16).padStart(6, "0");
const plural = (n, one, many = one + "s") => `${n} ${n === 1 ? one : many}`;

/** Readable text color for labels drawn on a group's color. */
function onTint(color) {
  const r = (color >> 16) & 0xff, g = (color >> 8) & 0xff, b = color & 0xff;
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.62 ? "#0a0a0b" : "#ffffff";
}
const tintStyle = (group) => (group ? `--tint:${hex(group.color)};--on-tint:${onTint(group.color)}` : "");
const groupName = (group) => (group.name ? group.name : "Untitled group");

const ICONS = {
  wand: '<path d="M15 4V2M15 16v-2M8 9h2M20 9h2M17.8 11.8 19 13M17.8 6.2 19 5M3 21l9-9M12.2 6.2 11 5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="1.5"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  star: '<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z"/>',
  starFill: '<path fill="currentColor" d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="1.5"/><path d="M5 15V5.5A1.5 1.5 0 0 1 6.5 4H15"/>',
  eye: '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  eyeOff: '<path d="M10.6 5.1A10 10 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-2.6 3.4M6.6 6.6A17 17 0 0 0 2 12s3.6 7 10 7a9.7 9.7 0 0 0 5.4-1.6M3 3l18 18M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
  external: '<path d="M7 17 17 7M8 7h9v9"/>',
  refresh: '<path d="M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-1-1.5 1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.5-1 1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  chevrons: '<path d="m8 9 4-4 4 4M8 15l4 4 4-4"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  moon: '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>',
  winMin: '<path d="M1 6h10"/>',
  winMax: '<rect x="1.5" y="1.5" width="9" height="9"/>',
  winClose: '<path d="m1.5 1.5 9 9M10.5 1.5l-9 9"/>',
};

function icon(name, size = 13, stroke = 1.8) {
  const viewBox = name.startsWith("win") ? "0 0 12 12" : "0 0 24 24";
  return `<svg width="${size}" height="${size}" viewBox="${viewBox}" fill="none" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]}</svg>`;
}

/** Password with digits and symbols tinted so characters are easy to read out. */
function coloredPassword(value) {
  return Array.from(value, (c) => {
    if (/\p{N}/u.test(c)) return `<span class="digit">${esc(c)}</span>`;
    if (!/\p{L}/u.test(c)) return `<span class="symbol">${esc(c)}</span>`;
    return esc(c);
  }).join("");
}

function strengthMeter(entropy, { showBits = true, dim = false } = {}) {
  const level = core.strengthLevel(entropy);
  const { label, tone } = core.STRENGTH[level];
  return `<div class="meter" style="opacity:${dim ? 0.4 : 1}">
    <div class="head"><span class="eyebrow">Strength</span>
      ${showBits ? `<span class="eyebrow tone-mute" style="letter-spacing:1px">${Math.round(entropy)} bits</span>` : ""}
      <span class="status tone-${tone}">${label}</span></div>
    <div class="level ${tone}"><div style="width:${((level + 1) / 5) * 100}%"></div></div>
  </div>`;
}

const toggleHTML = (key, on, label, hint) =>
  `<button class="toggle ${on ? "on" : ""}" data-toggle="${key}" role="checkbox" aria-checked="${on}">
    <span class="box">${on ? icon("check", 9, 3) : ""}</span>
    <span><span class="label">${esc(label)}</span>${hint ? `<span class="hint">${esc(hint)}</span>` : ""}</span>
  </button>`;

// MARK: - Preferences (per-PC settings, not secret)

const PREF_DEFAULTS = {
  autoLockMinutes: 5,
  lockOnSleep: true,
  clipboardClearSeconds: 30,
  appearance: "light",
  "gen.mode": "password",
  "gen.length": 20,
  "gen.uppercase": true,
  "gen.lowercase": true,
  "gen.digits": true,
  "gen.symbols": true,
  "gen.symbolSet": core.DEFAULT_SYMBOLS,
  "gen.excludeAmbiguous": false,
  "gen.requireEveryType": true,
  "gen.words": 5,
  "gen.separator": "-",
  "gen.capitalize": true,
  "gen.includeNumber": true,
};

const prefs = {
  get(key) {
    try {
      const raw = localStorage.getItem("pref." + key);
      return raw === null ? PREF_DEFAULTS[key] : JSON.parse(raw);
    } catch {
      return PREF_DEFAULTS[key];
    }
  },
  set(key, value) {
    try {
      localStorage.setItem("pref." + key, JSON.stringify(value));
    } catch {}
  },
};

const darkQuery = matchMedia("(prefers-color-scheme: dark)");
function applyAppearance() {
  const mode = prefs.get("appearance");
  const dark = mode === "dark" || (mode === "system" && darkQuery.matches);
  document.documentElement.dataset.theme = dark ? "dark" : "light";
}
darkQuery.addEventListener("change", applyAppearance);

// MARK: - Store

const state = {
  screen: "loading", // setup | locked | unlocked
  vault: null,
  entries: [],
  groups: [],
  busy: false,
  // Desk
  filter: "all",
  search: "",
  groupFilter: null,
  selection: null,
  editing: null, // { draft, original, isNew, reveal }
  revealed: false,
};

let writeQueue = Promise.resolve();

/** Writes to disk first and only then updates memory, so the UI never shows unsaved data. */
function persist(entries, groups = state.groups) {
  const vault = state.vault;
  const job = writeQueue.then(async () => {
    if (!vault || state.vault !== vault) return false;
    await platform.writeVault(await core.encryptVault(entries, groups, vault));
    state.entries = entries;
    state.groups = groups;
    return true;
  });
  writeQueue = job.catch(() => {});
  return job.catch((error) => {
    showToast("Couldn't save");
    console.error(error);
    throw error;
  });
}

function openVault({ vault, entries, groups }) {
  state.vault = vault;
  state.entries = entries;
  state.groups = groups;
  state.screen = "unlocked";
  state.filter = "all";
  state.search = "";
  state.groupFilter = null;
  state.selection = null;
  state.editing = null;
  lastActivity = Date.now();
  render();
}

function lock() {
  if (state.screen !== "unlocked") return;
  state.vault = null;
  state.entries = [];
  state.groups = [];
  state.editing = null;
  state.selection = null;
  closeOverlay();
  closeMenu();
  platform.clearClipboard().catch(() => {});
  state.screen = "locked";
  render();
}

const groupFor = (entry) => (entry.groupID ? state.groups.find((g) => g.id === entry.groupID) ?? null : null);

async function saveEntry(entry) {
  const updated = { ...entry, updatedAt: core.nowStamp() };
  const exists = state.entries.some((e) => e.id === entry.id);
  await persist(exists ? state.entries.map((e) => (e.id === entry.id ? updated : e)) : [...state.entries, updated]);
  return updated;
}

const updateEntry = (entry, changes) => persist(state.entries.map((e) => (e.id === entry.id ? { ...e, ...changes } : e)));

async function saveGroup(group) {
  const clean = { ...group, name: group.name.trim() };
  const exists = state.groups.some((g) => g.id === group.id);
  await persist(state.entries, exists ? state.groups.map((g) => (g.id === group.id ? clean : g)) : [...state.groups, clean]);
  return clean;
}

async function deleteGroup(group) {
  const entries = state.entries.map((e) => (e.groupID === group.id ? { ...e, groupID: null } : e));
  await persist(entries, state.groups.filter((g) => g.id !== group.id));
  if (state.groupFilter === group.id) state.groupFilter = null;
}

async function deleteEntry(entry) {
  await persist(state.entries.filter((e) => e.id !== entry.id));
  if (state.selection === entry.id) state.selection = null;
  if (state.editing?.draft.id === entry.id) state.editing = null;
}

function copy(value, label) {
  const seconds = prefs.get("clipboardClearSeconds");
  platform
    .copyText(value, seconds)
    .then(() => showToast(seconds > 0 ? `${label} copied · clears in ${seconds}s` : `${label} copied`))
    .catch(() => showToast("Couldn't copy"));
}

let toastTimer;
function showToast(message) {
  const toast = $("#toast");
  toast.textContent = message;
  toast.hidden = false;
  toast.style.animation = "none";
  void toast.offsetWidth;
  toast.style.animation = "";
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (toast.hidden = true), 2200);
}

// MARK: - Auto-lock

let lastActivity = Date.now();
let lastTick = Date.now();
for (const type of ["keydown", "mousedown", "mousemove", "wheel"]) {
  addEventListener(type, () => (lastActivity = Date.now()), { passive: true, capture: true });
}
setInterval(() => {
  const now = Date.now();
  // Timers stop while Windows sleeps, so a long gap between ticks means the PC was asleep.
  const slept = now - lastTick > 30_000;
  lastTick = now;
  if (state.screen !== "unlocked") return;
  if (slept && prefs.get("lockOnSleep")) return lock();
  const minutes = prefs.get("autoLockMinutes");
  if (minutes > 0 && now - lastActivity >= minutes * 60_000) lock();
}, 5_000);

addEventListener("beforeunload", () => platform.clearClipboard().catch(() => {}));

// MARK: - Rendering

function render() {
  closeMenu();
  renderChrome();
  const screen = $("#screen");
  if (state.screen === "setup") screen.innerHTML = setupHTML();
  else if (state.screen === "locked") screen.innerHTML = unlockHTML();
  else if (state.screen === "unlocked") {
    screen.innerHTML = deskHTML();
    renderList();
    renderPanel();
    renderHealth();
    mountGenerator($("#side-generator"), {});
  } else screen.innerHTML = "";
  const autofocus = $("[data-autofocus]", screen);
  autofocus?.focus();
}

function renderChrome() {
  const actions = $("#topbar-actions");
  if (state.screen === "unlocked") {
    actions.innerHTML = `
      <span class="status tone-green" style="margin-right:8px">Unlocked</span>
      <button class="square" style="width:28px;height:28px" data-action="generator" title="Password generator (Ctrl+Shift+G)">${icon("wand")}</button>
      <button class="square" style="width:28px;height:28px" data-action="new-entry" title="New login (Ctrl+N)">${icon("plus")}</button>
      <button class="square" style="width:28px;height:28px" data-action="settings" title="Settings (Ctrl+,)">${icon("gear")}</button>
      <button class="square" style="width:28px;height:28px" data-action="lock" title="Lock vault (Ctrl+L)">${icon("lock")}</button>`;
  } else {
    actions.innerHTML = `<button class="square" style="width:28px;height:28px" data-action="settings" title="Settings (Ctrl+,)">${icon("gear")}</button>`;
  }
  $("#window-controls").innerHTML = platform.isApp
    ? `<button data-action="win-min" title="Minimize">${icon("winMin", 10, 1)}</button>
       <button data-action="win-max" title="Maximize">${icon("winMax", 10, 1)}</button>
       <button class="close" data-action="win-close" title="Close">${icon("winClose", 10, 1)}</button>`
    : "";
}

// MARK: Auth screens

const authFoot = `<div class="card-foot"><span class="eyebrow">AES-256-GCM · PBKDF2 ${core.DEFAULT_ITERATIONS.toLocaleString("en-US")} rounds · Local only</span></div>`;

function authCard({ eyebrow, title, status, tone, body, footer }) {
  return `<div class="auth"><div class="card">
    <div class="card-header"><div class="titles"><span class="eyebrow">${eyebrow}</span><span class="card-title">${title}</span></div>
      <span class="status tone-${tone}">${status}</span></div>
    <div class="body">${body}</div>
    ${footer}
    ${authFoot}
  </div></div>`;
}

const MIN_LENGTH = 8;

function setupHTML() {
  return authCard({
    eyebrow: "New vault",
    title: "Create your vault",
    status: "No vault",
    tone: "whisper",
    body: `
      <div class="field"><span class="eyebrow">Master password</span>
        <input class="input" type="password" id="setup-password" placeholder="At least ${MIN_LENGTH} characters" data-autofocus></div>
      <div class="field" style="margin-top:14px"><span class="eyebrow">Confirm</span>
        <input class="input" type="password" id="setup-confirm" placeholder="Repeat password"></div>
      <div id="setup-meter" style="margin-top:18px">${strengthMeter(0, { showBits: false, dim: true })}</div>
      <div class="message" id="setup-message">There is no password recovery. Keep it somewhere safe.</div>`,
    footer: `<div class="cells top"><button class="cell prominent h44" data-action="create-vault" id="setup-create" disabled>Create vault</button></div>`,
  });
}

function setupValidation() {
  const password = $("#setup-password").value;
  const confirmation = $("#setup-confirm").value;
  const length = Array.from(password).length;
  let hint = null;
  if (!password) hint = "There is no password recovery. Keep it somewhere safe.";
  else if (length < MIN_LENGTH) hint = `Use at least ${MIN_LENGTH} characters.`;
  else if (confirmation && password !== confirmation) hint = "Passwords don't match.";
  $("#setup-meter").innerHTML = strengthMeter(core.estimateEntropy(password), { showBits: false, dim: !password });
  const message = $("#setup-message");
  message.className = "message";
  message.textContent = hint ?? " ";
  const valid = length >= MIN_LENGTH && password === confirmation;
  $("#setup-create").disabled = !valid || state.busy;
  return valid;
}

async function createVault() {
  if (!setupValidation() || state.busy) return;
  const password = $("#setup-password").value;
  state.busy = true;
  $("#setup-create").textContent = "Creating vault";
  $("#setup-create").disabled = true;
  try {
    const vault = await core.createVault(password);
    await platform.writeVault(await core.encryptVault([], [], vault));
    state.busy = false;
    openVault({ vault, entries: [], groups: [] });
  } catch (error) {
    state.busy = false;
    $("#setup-create").textContent = "Create vault";
    const message = $("#setup-message");
    message.className = "message error";
    message.textContent = error.message;
    setupValidation();
  }
}

function unlockHTML() {
  return authCard({
    eyebrow: "This PC",
    title: "Vault locked",
    status: "Locked",
    tone: "red",
    body: `
      <div class="field"><span class="eyebrow">Master password</span>
        <input class="input" type="password" id="unlock-password" placeholder="Enter password" data-autofocus></div>
      <div class="message" id="unlock-message" style="margin-top:10px">Password only.</div>`,
    footer: `<div class="cells top"><button class="cell prominent h44" data-action="unlock" id="unlock-button" disabled>Unlock vault</button></div>`,
  });
}

async function unlock() {
  const input = $("#unlock-password");
  const password = input.value;
  if (!password || state.busy) return;
  state.busy = true;
  input.disabled = true;
  $("#unlock-button").disabled = true;
  $("#unlock-button").textContent = "Unlocking";
  try {
    const text = await platform.readVault();
    const opened = await core.decryptVault(text, password);
    state.busy = false;
    openVault(opened);
  } catch (error) {
    state.busy = false;
    input.disabled = false;
    input.value = "";
    input.focus();
    input.classList.remove("shake");
    void input.offsetWidth;
    input.classList.add("shake");
    $("#unlock-button").textContent = "Unlock vault";
    const message = $("#unlock-message");
    message.className = "message error";
    message.textContent = error.message || "Couldn't open the vault.";
  }
}

// MARK: Desk

const FILTERS = {
  all: { title: "All logins", short: "All", tile: "Logins" },
  favorites: { title: "Favorites", short: "Fav", tile: "Favorites" },
  weak: { title: "Weak passwords", short: "Weak", tile: "Weak" },
  reused: { title: "Reused passwords", short: "Reused", tile: "Reused" },
};

const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

function derived() {
  const { weak, reused } = core.vaultHealth(state.entries);
  const counts = {
    all: state.entries.length,
    favorites: state.entries.filter((e) => e.favorite).length,
    weak: weak.size,
    reused: reused.size,
  };
  return { weak, reused, counts };
}

function filteredEntries({ weak, reused }) {
  const query = state.search.trim().toLocaleLowerCase();
  const has = (text) => (text ?? "").toLocaleLowerCase().includes(query);
  return state.entries
    .filter((e) => !state.groupFilter || e.groupID === state.groupFilter)
    .filter((e) => {
      switch (state.filter) {
        case "favorites": return e.favorite;
        case "weak": return weak.has(e.id);
        case "reused": return reused.has(e.id);
        default: return true;
      }
    })
    .filter((e) => !query || has(e.title) || has(e.username) || has(e.url) || has(groupFor(e)?.name))
    .sort((a, b) => collator.compare(a.title, b.title));
}

function deskHTML() {
  return `<div class="desk">
    <section class="card list-card">
      <div class="card-header"><div class="titles"><span class="eyebrow" id="list-eyebrow"></span><span class="card-title" id="list-title"></span></div>
        <span class="eyebrow tone-mute" style="letter-spacing:1.3px" id="list-count"></span></div>
      <label class="search">${icon("search", 12)}
        <input id="search" placeholder="Search logins" spellcheck="false" value="${esc(state.search)}">
        <span id="search-trailing"></span></label>
      <div class="cells bottom" id="filters"></div>
      <div class="groups"><div class="chips" id="group-chips"></div>
        <button class="square xs" data-action="new-group" title="New group">${icon("plus", 11)}</button></div>
      <div class="scroll" id="entry-list" tabindex="-1"></div>
      <div class="cells top"><button class="cell h40" data-action="new-entry">${icon("plus", 10, 2.2)} New login</button></div>
    </section>
    <div class="panel" id="panel"></div>
    <div class="side">
      <section class="card" id="health"></section>
      <section class="card generator" id="side-generator"></section>
    </div>
  </div>`;
}

function renderList() {
  const info = derived();
  const entries = filteredEntries(info);
  const activeGroup = state.groups.find((g) => g.id === state.groupFilter);
  $("#list-eyebrow").textContent = activeGroup ? `Group · ${groupName(activeGroup)}` : "Vault";
  $("#list-title").textContent = FILTERS[state.filter].title;
  $("#list-count").textContent = plural(entries.length, "login");
  $("#search-trailing").innerHTML = state.search
    ? `<button data-action="clear-search" title="Clear">${icon("x", 10, 2.4)}</button>`
    : `<span class="eyebrow">Ctrl F</span>`;

  $("#filters").innerHTML = Object.entries(FILTERS)
    .map(([key, f]) => `<button class="cell h34 ${state.filter === key ? "selected" : ""}" data-filter="${key}">${f.short} ${info.counts[key]}</button>`)
    .join("");

  $("#group-chips").innerHTML = state.groups.length
    ? state.groups
        .map((g) => {
          const count = state.entries.filter((e) => e.groupID === g.id).length;
          return `<button class="chip ${state.groupFilter === g.id ? "selected" : ""}" style="${tintStyle(g)}" data-group="${esc(g.id)}" title="Right-click to edit">
            <span class="sw"></span>${esc(groupName(g))}<span class="count">${count}</span></button>`;
        })
        .join("")
    : `<span class="eyebrow" style="letter-spacing:1.3px;align-self:center">No groups yet</span>`;

  const list = $("#entry-list");
  list.innerHTML = entries.length
    ? entries
        .map((e) => {
          const group = groupFor(e);
          const selected = e.id === state.selection && !state.editing;
          const flagged = info.weak.has(e.id) || info.reused.has(e.id);
          const sub = e.username || core.hostOf(e.url) || "No username";
          return `<button class="entry-row ${selected ? "selected" : ""}" data-entry="${esc(e.id)}" style="${tintStyle(group)}" ${group ? `title="Group: ${esc(groupName(group))}"` : ""}>
            ${group ? '<span class="stripe"></span>' : ""}
            <span class="monogram ${group ? "tinted" : ""}">${esc((Array.from(e.title)[0] ?? "?").toUpperCase())}</span>
            <span class="texts"><span class="title">${esc(e.title || "Untitled")}</span><span class="sub">${esc(sub)}</span></span>
            <span class="marks">${e.favorite ? '<span class="mark-fav"></span>' : ""}${flagged ? '<span class="mark-flag"></span>' : ""}</span>
          </button>`;
        })
        .join("")
    : `<div class="empty">${state.entries.length ? "Nothing matches." : "No logins yet.\nPress Ctrl+N to add one."}</div>`;
  return entries;
}

function renderHealth() {
  const card = $("#health");
  if (!card) return;
  const { weak, reused, counts } = derived();
  const flagged = new Set([...weak, ...reused]).size;
  const total = state.entries.length;
  const health = total === 0 ? 1 : 1 - flagged / total;
  const tone = flagged === 0 ? "green" : health >= 0.7 ? "amber" : "red";
  const tile = (key, value, alert = false) =>
    `<button class="tile" data-filter="${key}">
      <span class="eyebrow">${FILTERS[key].tile}</span>
      <span class="value ${alert ? "red" : ""}">${value}</span>
      ${state.filter === key ? '<span class="pin"></span>' : ""}
    </button>`;
  card.innerHTML = `
    <div class="card-header"><div class="titles"><span class="eyebrow">Security</span><span class="card-title">Vault health</span></div>
      <span class="status tone-${tone}">${flagged === 0 ? "Healthy" : `${flagged} to fix`}</span></div>
    <div class="tiles">${tile("all", counts.all)}${tile("favorites", counts.favorites)}${tile("weak", counts.weak, counts.weak > 0)}${tile("reused", counts.reused, counts.reused > 0)}</div>
    <div class="score"><div class="head"><span class="eyebrow">Score</span><span class="eyebrow tone-mute" style="letter-spacing:1px">${Math.round(health * 100)}%</span></div>
      <div class="level ${tone}"><div style="width:${health * 100}%"></div></div></div>`;
}

function refreshDesk() {
  if (state.screen !== "unlocked") return;
  renderList();
  renderPanel();
  renderHealth();
}

// MARK: Panel: detail / editor / empty

function renderPanel() {
  const panel = $("#panel");
  if (!panel) return;
  if (state.editing) return renderEditor(panel);
  const entry = state.entries.find((e) => e.id === state.selection);
  if (!entry) {
    panel.innerHTML = `<section class="card">
      <div class="card-header"><div class="titles"><span class="eyebrow">Login</span><span class="card-title">Nothing selected</span></div></div>
      <div class="empty center">Pick a login from the list,\nor add a new one.</div></section>`;
    return;
  }
  renderDetail(panel, entry);
}

const dateFormat = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short", year: "numeric" });
const relativeFormat = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
function relative(date) {
  const seconds = (date.getTime() - Date.now()) / 1000;
  if (Math.abs(seconds) < 60) return "now";
  const units = [["year", 31536000], ["month", 2592000], ["week", 604800], ["day", 86400], ["hour", 3600], ["minute", 60]];
  for (const [unit, size] of units) {
    if (Math.abs(seconds) >= size) return relativeFormat.format(Math.round(seconds / size), unit);
  }
  return "now";
}

function renderDetail(panel, entry) {
  const { weak } = derived();
  const reuseCount = entry.password ? state.entries.filter((e) => e.id !== entry.id && e.password === entry.password).length : 0;
  const warnings = [];
  if (weak.has(entry.id)) warnings.push("This password is weak and easy to guess.");
  if (reuseCount > 0) warnings.push(`Also used by ${plural(reuseCount, "other login", "other logins")}. One breach exposes them all.`);
  const host = core.hostOf(entry.url);
  const group = groupFor(entry);
  const entropy = core.estimateEntropy(entry.password);
  const level = core.strengthLevel(entropy);
  const { label, tone } = core.STRENGTH[level];
  const revealed = state.revealed;

  panel.innerHTML = `<section class="card">
    <div class="card-header"><div class="titles"><span class="eyebrow">${esc(host ?? "No website")}</span><span class="card-title">${esc(entry.title || "Untitled")}</span></div>
      <div class="trailing">
        ${group ? `<span class="group-tag" style="${tintStyle(group)}">${esc(groupName(group))}</span>` : ""}
        <button class="square sm" data-action="toggle-favorite" title="${entry.favorite ? "Remove from favorites" : "Add to favorites"}">${icon(entry.favorite ? "starFill" : "star")}</button>
        <button class="square sm" data-action="close-detail" title="Close">${icon("x")}</button>
      </div></div>
    ${warnings.map((w) => `<div class="warning">${esc(w)}</div>`).join("")}
    <div class="scroll">
      <div class="tiles">
        <div class="tile value-tile"><span class="eyebrow">Username</span><span class="text selectable">${esc(entry.username || "—")}</span>
          <div class="actions">${entry.username ? `<button class="square sm" data-action="copy-username" title="Copy username">${icon("copy")}</button>` : ""}</div></div>
        <div class="tile value-tile"><span class="eyebrow">Website</span><span class="text selectable">${esc(host ?? (entry.url || "—"))}</span>
          <div class="actions">${core.websiteURL(entry.url) ? `<button class="square sm" data-action="open-website" title="Open website">${icon("external")}</button>` : ""}</div></div>
        <div class="tile value-tile"><span class="eyebrow">Password</span>
          <span class="text mono ${revealed ? "pw selectable" : "tone-mute"}">${!entry.password ? "—" : revealed ? coloredPassword(entry.password) : "•".repeat(12)}</span>
          <div class="actions">${entry.password ? `
            <button class="square sm" data-action="toggle-reveal" title="${revealed ? "Hide" : "Show"}">${icon(revealed ? "eyeOff" : "eye")}</button>
            <button class="square sm" data-action="copy-password" title="Copy password">${icon("copy")}</button>` : ""}</div></div>
        <div class="tile value-tile"><span class="eyebrow">Strength</span>
          <span class="value">${entry.password ? Math.round(entropy) : "—"}</span>
          <span class="sub">${entry.password ? `bits · ${label.toLowerCase()}` : "No password"}</span>
          <div class="level ${tone}" style="margin-top:4px"><div style="width:${entry.password ? ((level + 1) / 5) * 100 : 0}%"></div></div></div>
      </div>
      ${entry.notes.trim() ? `<div class="notes"><span class="eyebrow">Notes</span><div class="text selectable">${esc(entry.notes)}</div></div>` : ""}
    </div>
    <div class="card-foot"><span class="eyebrow">Created ${dateFormat.format(core.stampToDate(entry.createdAt))} · Edited ${relative(core.stampToDate(entry.updatedAt))}</span></div>
    <div class="cells top">
      ${entry.password ? `<button class="cell prominent h42" data-action="copy-password">Copy password</button>` : ""}
      <button class="cell h42" data-action="edit-entry" title="Ctrl+E">Edit</button>
      <button class="cell destructive h42" data-action="delete-entry">Delete</button>
    </div>
  </section>`;
}

function startNewEntry() {
  if (state.screen !== "unlocked") return;
  state.selection = null;
  const draft = core.makeEntry({ groupID: state.groupFilter });
  state.editing = { draft, original: JSON.stringify(draft), isNew: true, reveal: false };
  renderList();
  renderPanel();
}

function startEditing(entry) {
  state.editing = { draft: { ...entry }, original: JSON.stringify(entry), isNew: false, reveal: false };
  renderList();
  renderPanel();
}

function renderEditor(panel) {
  const { draft, isNew, reveal } = state.editing;
  const group = groupFor(draft);
  panel.innerHTML = `<section class="card">
    <div class="card-header"><div class="titles"><span class="eyebrow">${isNew ? "New login" : "Editing"}</span>
        <input class="card-title" id="edit-title" placeholder="Untitled" value="${esc(draft.title)}" spellcheck="false" ${isNew ? "data-autofocus" : ""}></div>
      <span class="status" id="edit-status"></span></div>
    <div class="scroll"><div style="padding:17px">
      <div class="field"><span class="eyebrow">Username</span>
        <input class="input" id="edit-username" placeholder="name@example.com" value="${esc(draft.username)}" spellcheck="false" autocomplete="off"></div>
      <div class="field"><span class="eyebrow">Website</span>
        <input class="input" id="edit-url" placeholder="example.com" value="${esc(draft.url)}" spellcheck="false" autocomplete="off"></div>
      <div class="field"><span class="eyebrow">Group</span>
        <div class="select-wrap" style="${tintStyle(group)}">
          <span class="swatch" style="background:${group ? "var(--tint)" : "var(--line-strong)"}"></span>
          <select class="input" id="edit-group">
            <option value="">No group</option>
            ${state.groups.map((g) => `<option value="${esc(g.id)}" ${g.id === draft.groupID ? "selected" : ""}>${esc(groupName(g))}</option>`).join("")}
            <option value="__new">New group…</option>
          </select>
          <span class="chev">${icon("chevrons", 11, 2)}</span></div></div>
      <div class="field"><span class="eyebrow">Password</span>
        <div class="row">
          <input class="input mono" id="edit-password" type="${reveal ? "text" : "password"}" placeholder="Required" value="${esc(draft.password)}" spellcheck="false" autocomplete="off">
          <button class="square lg" data-action="toggle-edit-reveal" title="${reveal ? "Hide" : "Show"}">${icon(reveal ? "eyeOff" : "eye")}</button>
          <button class="square lg" data-action="editor-generator" title="Generate a password">${icon("wand")}</button>
        </div></div>
      <div id="edit-meter" style="margin-top:16px"></div>
      <div class="field"><span class="eyebrow">Notes</span>
        <textarea class="input" id="edit-notes" spellcheck="false">${esc(draft.notes)}</textarea></div>
      <div style="margin-top:18px" id="edit-favorite">${toggleHTML("edit-favorite", draft.favorite, "Pin to favorites")}</div>
      <div class="form-message error" id="edit-error"></div>
    </div></div>
    <div class="cells top">
      <button class="cell h42" data-action="cancel-edit">Cancel</button>
      <button class="cell prominent h42" data-action="save-entry" id="edit-save">${isNew ? "Add login" : "Save changes"}</button>
    </div>
  </section>`;
  updateEditorStatus();
  $("[data-autofocus]", panel)?.focus();
}

function updateEditorStatus() {
  if (!state.editing) return;
  const { draft, original, isNew } = state.editing;
  const unchanged = JSON.stringify(draft) === original;
  const status = $("#edit-status");
  status.textContent = isNew ? "Draft" : unchanged ? "No changes" : "Unsaved";
  status.className = `status ${unchanged && !isNew ? "tone-whisper" : "tone-amber"}`;
  $("#edit-meter").innerHTML = strengthMeter(core.estimateEntropy(draft.password), { dim: !draft.password });
  $("#edit-save").disabled = !draft.title.trim();
}

async function saveEditing() {
  if (!state.editing) return;
  const { draft } = state.editing;
  if (!draft.title.trim()) return;
  const entry = { ...draft, title: draft.title.trim(), username: draft.username.trim(), url: draft.url.trim() };
  try {
    const saved = await saveEntry(entry);
    state.editing = null;
    state.selection = saved.id;
    state.revealed = false;
    refreshDesk();
  } catch (error) {
    $("#edit-error").textContent = String(error.message ?? error);
  }
}

function cancelEditing() {
  state.editing = null;
  refreshDesk();
}

// MARK: Generator

const SEPARATORS = [["-", "-"], [".", "."], ["_", "_"], [" ", "␣"], ["", "None"]];

function generatorOptions() {
  return {
    password: {
      length: prefs.get("gen.length"),
      uppercase: prefs.get("gen.uppercase"),
      lowercase: prefs.get("gen.lowercase"),
      digits: prefs.get("gen.digits"),
      symbols: prefs.get("gen.symbols"),
      symbolSet: prefs.get("gen.symbolSet"),
      excludeAmbiguous: prefs.get("gen.excludeAmbiguous"),
      requireEveryType: prefs.get("gen.requireEveryType"),
    },
    passphrase: {
      wordCount: prefs.get("gen.words"),
      separator: prefs.get("gen.separator"),
      capitalize: prefs.get("gen.capitalize"),
      includeNumber: prefs.get("gen.includeNumber"),
    },
  };
}

/** Renders a generator card into `root`. `onUse` adds a "Use" button (e.g. in the editor). */
function mountGenerator(root, { plain = false, onUse = null }) {
  let output = "";
  const mode = () => prefs.get("gen.mode");

  root.classList.toggle("plain", plain);
  root.innerHTML = `
    <div class="card-header"><div class="titles"><span class="eyebrow">Generator</span><span class="card-title" data-g="title"></span></div>
      <span class="eyebrow tone-mute" style="letter-spacing:1.3px" data-g="pool"></span></div>
    <div class="cells bottom" data-g="modes"></div>
    <div class="gen-output">
      <div class="row"><div class="pw" data-g="output"></div>
        <button class="square" style="width:28px;height:28px" data-g="regenerate" title="Generate again">${icon("refresh")}</button></div>
      <div data-g="meter"></div>
    </div>
    <div class="scroll"><div class="gen-controls" data-g="controls"></div></div>
    <div class="cells top">
      <button class="cell h40 ${onUse ? "" : "prominent"}" data-g="copy">Copy</button>
      ${onUse ? `<button class="cell prominent h40" data-g="use"></button>` : ""}
    </div>`;
  const part = (name) => root.querySelector(`[data-g="${name}"]`);

  function regenerate() {
    const options = generatorOptions();
    output = mode() === "password" ? core.generatePassword(options.password) : core.generatePassphrase(options.passphrase);
    updateOutput();
  }

  function updateOutput() {
    const options = generatorOptions();
    const isPassword = mode() === "password";
    const entropy = isPassword ? core.passwordEntropy(options.password) : core.passphraseEntropy(options.passphrase);
    const pool = core.characterSets(options.password).reduce((sum, set) => sum + set.length, 0);
    part("title").textContent = isPassword ? "Password" : "Passphrase";
    part("pool").textContent = isPassword ? `${pool} chars` : `${core.WORD_COUNT} words`;
    part("output").innerHTML = output ? coloredPassword(output) : "—";
    part("meter").innerHTML = strengthMeter(entropy);
    part("copy").disabled = !output;
    if (onUse) {
      part("use").textContent = `Use ${isPassword ? "password" : "passphrase"}`;
      part("use").disabled = !output;
    }
  }

  function slider(key, min, max, label) {
    const value = prefs.get(key);
    const pct = ((value - min) / (max - min)) * 100;
    return `<div class="value-slider"><div class="head"><span class="eyebrow">${label}</span><span class="num" data-num="${key}">${value}</span></div>
      <div class="slider" tabindex="0" role="slider" aria-valuemin="${min}" aria-valuemax="${max}" aria-valuenow="${value}" data-slider="${key}" data-min="${min}" data-max="${max}">
        <div class="track"></div><div class="fill" style="width:max(${pct}%, 6px)"></div><div class="knob" style="left:${pct}%"></div></div></div>`;
  }

  function renderControls() {
    const isPassword = mode() === "password";
    part("modes").innerHTML = `
      <button class="cell h32 ${isPassword ? "selected" : ""}" data-mode="password">Password</button>
      <button class="cell h32 ${!isPassword ? "selected" : ""}" data-mode="passphrase">Passphrase</button>`;
    const controls = part("controls");
    if (isPassword) {
      const sets = [["gen.uppercase", "A–Z"], ["gen.lowercase", "a–z"], ["gen.digits", "0–9"], ["gen.symbols", "#$&"]];
      const enabled = sets.filter(([key]) => prefs.get(key)).length;
      const symbolSet = prefs.get("gen.symbolSet");
      controls.innerHTML = `
        ${slider("gen.length", 4, 128, "Length")}
        <div class="stack"><span class="eyebrow">Characters</span>
          <div class="cells boxed">${sets
            .map(([key, label]) => {
              const on = prefs.get(key);
              return `<button class="cell h32 keep-case ${on ? "selected" : ""}" data-set="${key}" ${on && enabled === 1 ? "disabled" : ""}>${label}</button>`;
            })
            .join("")}</div></div>
        <div class="stack gap12">
          ${toggleHTML("gen.excludeAmbiguous", prefs.get("gen.excludeAmbiguous"), "Avoid look-alikes", "Skips I, l, 1, O and 0")}
          ${toggleHTML("gen.requireEveryType", prefs.get("gen.requireEveryType"), "Use every set", "At least one character from each")}
        </div>
        ${prefs.get("gen.symbols") ? `<div class="stack"><div class="row" style="justify-content:space-between"><span class="eyebrow">Symbol set</span>
            ${symbolSet !== core.DEFAULT_SYMBOLS ? `<button class="link-button" data-g="reset-symbols">Reset</button>` : ""}</div>
          <input class="input mono h34" data-g="symbols" value="${esc(symbolSet)}" spellcheck="false"></div>` : ""}`;
    } else {
      const separator = prefs.get("gen.separator");
      controls.innerHTML = `
        ${slider("gen.words", 3, 12, "Words")}
        <div class="stack"><span class="eyebrow">Separator</span>
          <div class="cells boxed">${SEPARATORS.map(([value, label]) => `<button class="cell h32 ${separator === value ? "selected" : ""}" data-separator="${esc(value)}">${esc(label)}</button>`).join("")}</div></div>
        <div class="stack gap12">
          ${toggleHTML("gen.capitalize", prefs.get("gen.capitalize"), "Capitalize words")}
          ${toggleHTML("gen.includeNumber", prefs.get("gen.includeNumber"), "Include a number")}
        </div>`;
    }
  }

  function setSlider(el, value) {
    const key = el.dataset.slider;
    const min = Number(el.dataset.min), max = Number(el.dataset.max);
    value = Math.min(max, Math.max(min, Math.round(value)));
    if (value === prefs.get(key)) return;
    prefs.set(key, value);
    const pct = ((value - min) / (max - min)) * 100;
    el.querySelector(".fill").style.width = `max(${pct}%, 6px)`;
    el.querySelector(".knob").style.left = `${pct}%`;
    el.setAttribute("aria-valuenow", value);
    root.querySelector(`[data-num="${key}"]`).textContent = value;
    regenerate();
  }

  root.addEventListener("click", (event) => {
    const target = event.target.closest("button");
    if (!target || !root.contains(target)) return;
    if (target.dataset.mode) {
      prefs.set("gen.mode", target.dataset.mode);
      renderControls();
      regenerate();
    } else if (target.dataset.set) {
      prefs.set(target.dataset.set, !prefs.get(target.dataset.set));
      renderControls();
      regenerate();
    } else if (target.dataset.toggle?.startsWith("gen.")) {
      prefs.set(target.dataset.toggle, !prefs.get(target.dataset.toggle));
      renderControls();
      regenerate();
    } else if (target.dataset.separator !== undefined) {
      prefs.set("gen.separator", target.dataset.separator);
      renderControls();
      regenerate();
    } else if (target.dataset.g === "regenerate") regenerate();
    else if (target.dataset.g === "reset-symbols") {
      prefs.set("gen.symbolSet", core.DEFAULT_SYMBOLS);
      renderControls();
      regenerate();
    } else if (target.dataset.g === "copy" && output) copy(output, mode() === "password" ? "Password" : "Passphrase");
    else if (target.dataset.g === "use" && output) onUse(output);
  });

  root.addEventListener("input", (event) => {
    if (event.target.dataset.g === "symbols") {
      prefs.set("gen.symbolSet", event.target.value);
      regenerate();
    }
  });
  root.addEventListener("change", (event) => {
    if (event.target.dataset.g === "symbols") renderControls();
  });

  root.addEventListener("pointerdown", (event) => {
    const el = event.target.closest("[data-slider]");
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const min = Number(el.dataset.min), max = Number(el.dataset.max);
    const move = (e) => setSlider(el, min + Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width)) * (max - min));
    move(event);
    el.setPointerCapture(event.pointerId);
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", () => el.removeEventListener("pointermove", move), { once: true });
  });
  root.addEventListener("keydown", (event) => {
    const el = event.target.closest?.("[data-slider]");
    if (!el) return;
    const step = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1 }[event.key];
    if (step) {
      event.preventDefault();
      setSlider(el, prefs.get(el.dataset.slider) + step);
    }
  });

  renderControls();
  regenerate();
}

// MARK: - Overlays

function closeOverlay() {
  $("#overlay").innerHTML = "";
}

function openSheet(className, html) {
  const overlay = $("#overlay");
  overlay.innerHTML = `<div class="sheet ${className}">${html}</div>`;
  return overlay.firstElementChild;
}

function confirmDialog({ title, text, action, onConfirm }) {
  const sheet = openSheet("confirm", `
    <div class="body"><div class="title">${esc(title)}</div><div class="text">${esc(text)}</div></div>
    <div class="cells top"><button class="cell h42" data-close>Cancel</button><button class="cell destructive h42" data-confirm>${esc(action)}</button></div>`);
  $("[data-confirm]", sheet).focus();
  $("[data-confirm]", sheet).addEventListener("click", async () => {
    closeOverlay();
    await onConfirm();
  });
}

function openGeneratorSheet(onUse = null) {
  const sheet = openSheet("generator-sheet card plain", "");
  mountGenerator(sheet, { plain: true, onUse });
}

function openGroupEditor(group, isNew, onSaved) {
  const draft = { ...group };
  const sheet = openSheet("group-sheet", "");
  function draw() {
    sheet.innerHTML = `
      <div class="card-header"><div class="titles"><span class="eyebrow">${isNew ? "New group" : "Edit group"}</span>
          <input class="card-title" id="group-name" placeholder="Group name" value="${esc(draft.name)}" spellcheck="false"></div>
        <span class="chip selected" style="${tintStyle(draft)}" id="group-preview"><span class="sw"></span>${esc(groupName(draft))}</span></div>
      <div style="padding:17px;display:flex;flex-direction:column;gap:10px">
        <span class="eyebrow">Color</span>
        <div class="swatches">
          ${core.GROUP_PALETTE.map((c) => `<button class="swatch-btn ${draft.color === c ? "selected" : ""}" style="--tint:${hex(c)};--on-tint:${onTint(c)}" data-color="${c}">${draft.color === c ? icon("check", 10, 3) : ""}</button>`).join("")}
          <label class="swatch-btn custom ${core.GROUP_PALETTE.includes(draft.color) ? "" : "selected"}" title="Custom color"><input type="color" id="group-custom" value="${hex(draft.color)}"></label>
        </div>
        <div class="form-message error" id="group-error"></div>
      </div>
      <div class="cells top"><button class="cell h42" data-close>Cancel</button>
        <button class="cell prominent h42" id="group-save" ${draft.name.trim() ? "" : "disabled"}>${isNew ? "Add group" : "Save group"}</button></div>`;
  }
  draw();
  const nameInput = () => $("#group-name", sheet);
  nameInput().focus();
  const save = async () => {
    if (!draft.name.trim()) return;
    try {
      const saved = await saveGroup(draft);
      closeOverlay();
      onSaved?.(saved);
      refreshDesk();
    } catch (error) {
      $("#group-error", sheet).textContent = String(error.message ?? error);
    }
  };
  sheet.addEventListener("input", (event) => {
    if (event.target.id === "group-name") {
      draft.name = event.target.value;
      $("#group-save", sheet).disabled = !draft.name.trim();
      const preview = $("#group-preview", sheet);
      preview.innerHTML = `<span class="sw"></span>${esc(groupName(draft))}`;
    } else if (event.target.id === "group-custom") {
      draft.color = parseInt(event.target.value.slice(1), 16);
      const caret = nameInput().selectionStart;
      draw();
      nameInput().focus();
      nameInput().setSelectionRange(caret, caret);
    }
  });
  sheet.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && event.target.id === "group-name") save();
  });
  sheet.addEventListener("click", (event) => {
    const swatch = event.target.closest("[data-color]");
    if (swatch) {
      draft.color = Number(swatch.dataset.color);
      draw();
      nameInput().focus();
    } else if (event.target.closest("#group-save")) save();
  });
}

function newGroup(onSaved) {
  const group = { id: core.newID(), name: "", color: core.suggestedGroupColor(state.groups) };
  openGroupEditor(group, true, onSaved);
}

// MARK: Settings

const LOCK_OPTIONS = [[1, "1 minute"], [5, "5 minutes"], [15, "15 minutes"], [30, "30 minutes"], [60, "1 hour"], [0, "Never"]];
const CLEAR_OPTIONS = [[10, "10 seconds"], [30, "30 seconds"], [60, "1 minute"], [120, "2 minutes"], [0, "Never"]];
const APPEARANCE_OPTIONS = [["light", "Light"], ["dark", "Dark"], ["system", "Match Windows"]];

function openSettings(tab = "general") {
  const sheet = openSheet("settings-sheet", "");
  const select = (key, options) =>
    `<div class="select-wrap"><select class="input" data-pref="${key}">${options
      .map(([value, label]) => `<option value="${value}" ${prefs.get(key) === value ? "selected" : ""}>${label}</option>`)
      .join("")}</select><span class="chev">${icon("chevrons", 11, 2)}</span></div>`;

  async function draw() {
    const location = await platform.vaultLocation().catch(() => "");
    const body =
      tab === "general"
        ? `<div class="settings-body">
            <div class="setting"><div class="name">Appearance</div>${select("appearance", APPEARANCE_OPTIONS)}</div>
            <div class="setting"><div class="name">Lock after inactivity</div>${select("autoLockMinutes", LOCK_OPTIONS)}</div>
            <div class="setting">${toggleHTML("lockOnSleep", prefs.get("lockOnSleep"), "Lock when this PC sleeps")}</div>
            <div class="setting"><div class="name">Clear copied passwords after</div>${select("clipboardClearSeconds", CLEAR_OPTIONS)}</div>
            <div class="setting"><div><div class="name">Vault file</div><div class="hint selectable">${esc(location)}</div>
                <div class="hint">Fully encrypted. Copy it somewhere safe to back it up.</div></div>
              <button class="cell h32" style="flex:0 0 140px;border:1px solid var(--line-strong);border-radius:2px" data-action="reveal-vault">Show in Explorer</button></div>
          </div>`
        : `<div class="settings-body">
            <div class="settings-section"><span class="eyebrow">Master password</span>
              ${state.screen === "unlocked" ? `
                <div class="field" style="margin-top:8px"><input class="input" type="password" id="cp-current" placeholder="Current password"></div>
                <div class="field" style="margin-top:8px"><input class="input" type="password" id="cp-new" placeholder="New password"></div>
                <div class="field" style="margin-top:8px"><input class="input" type="password" id="cp-confirm" placeholder="Confirm new password"></div>
                <div id="cp-meter" style="margin-top:14px"></div>
                <div class="row" style="justify-content:space-between;margin-top:6px">
                  <div class="form-message" id="cp-message" style="margin-top:0"></div>
                  <button class="cell prominent h34" style="flex:0 0 160px" id="cp-submit" disabled>Change password</button></div>`
                : `<div class="hint" style="padding:10px 0;font-size:12px;color:var(--mute)">Unlock your vault to change the master password.</div>`}
            </div>
            <div class="settings-section"><span class="eyebrow">About your vault</span>
              <div class="kv"><span>Encryption</span><span>AES-256-GCM</span></div>
              <div class="kv"><span>Key derivation</span><span>PBKDF2-SHA256 · ${core.DEFAULT_ITERATIONS.toLocaleString("en-US")} rounds</span></div>
              <div class="kv"><span>Storage</span><span>Local only</span></div>
              <div class="kv"><span>Compatible with</span><span>Safespace for Mac</span></div>
            </div>
          </div>`;
    sheet.innerHTML = `
      <div class="card-header"><div class="titles"><span class="eyebrow">Safespace</span><span class="card-title">Settings</span></div>
        <button class="square sm" data-close title="Close">${icon("x")}</button></div>
      <div class="cells bottom"><button class="cell h34 ${tab === "general" ? "selected" : ""}" data-tab="general">General</button>
        <button class="cell h34 ${tab === "security" ? "selected" : ""}" data-tab="security">Security</button></div>
      <div class="scroll">${body}</div>`;
  }

  function validateChange() {
    const current = $("#cp-current", sheet).value;
    const next = $("#cp-new", sheet).value;
    const confirmation = $("#cp-confirm", sheet).value;
    const message = $("#cp-message", sheet);
    $("#cp-meter", sheet).innerHTML = next ? strengthMeter(core.estimateEntropy(next), { showBits: false }) : "";
    message.className = "form-message";
    message.textContent =
      confirmation && next !== confirmation ? "Passwords don't match." : next && Array.from(next).length < MIN_LENGTH ? `Use at least ${MIN_LENGTH} characters.` : "";
    const valid = current && Array.from(next).length >= MIN_LENGTH && next === confirmation && !state.busy;
    $("#cp-submit", sheet).disabled = !valid;
    return valid;
  }

  async function changePassword() {
    if (!validateChange()) return;
    const message = $("#cp-message", sheet);
    state.busy = true;
    $("#cp-submit", sheet).disabled = true;
    try {
      const text = await platform.readVault();
      await core.decryptVault(text, $("#cp-current", sheet).value);
      const vault = await core.createVault($("#cp-new", sheet).value);
      const entries = state.entries, groups = state.groups;
      await (writeQueue = writeQueue.then(async () => platform.writeVault(await core.encryptVault(entries, groups, vault))));
      state.vault = vault;
      for (const id of ["cp-current", "cp-new", "cp-confirm"]) $("#" + id, sheet).value = "";
      $("#cp-meter", sheet).innerHTML = "";
      message.className = "form-message ok";
      message.textContent = "Master password changed.";
    } catch (error) {
      message.className = "form-message error";
      message.textContent = error.code === "wrongPassword" ? "Current password is incorrect." : String(error.message ?? error);
    } finally {
      state.busy = false;
    }
  }

  sheet.addEventListener("click", (event) => {
    const target = event.target.closest("button");
    if (!target) return;
    if (target.dataset.tab) {
      tab = target.dataset.tab;
      draw();
    } else if (target.dataset.toggle === "lockOnSleep") {
      prefs.set("lockOnSleep", !prefs.get("lockOnSleep"));
      target.outerHTML = toggleHTML("lockOnSleep", prefs.get("lockOnSleep"), "Lock when this PC sleeps");
    } else if (target.id === "cp-submit") changePassword();
  });
  sheet.addEventListener("change", (event) => {
    const key = event.target.dataset.pref;
    if (!key) return;
    const raw = event.target.value;
    prefs.set(key, typeof PREF_DEFAULTS[key] === "number" ? Number(raw) : raw);
    if (key === "appearance") applyAppearance();
  });
  sheet.addEventListener("input", (event) => {
    if (event.target.id?.startsWith("cp-")) validateChange();
  });
  sheet.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && event.target.id?.startsWith("cp-")) changePassword();
  });
  draw();
}

// MARK: Context menu

function closeMenu() {
  const menu = $("#menu");
  menu.hidden = true;
  menu.innerHTML = "";
}

function openMenu(x, y, items) {
  const menu = $("#menu");
  menu.innerHTML = items
    .map((item) => {
      if (item === "-") return "<hr>";
      if (item.label) return `<div class="eyebrow menu-label">${esc(item.label)}</div>`;
      return `<button data-index="${items.indexOf(item)}" class="${item.destructive ? "destructive" : ""}" ${item.disabled ? "disabled" : ""} style="${item.tint ?? ""}">
        ${item.swatch ? '<span class="sw"></span>' : ""}${esc(item.title)}${item.checked ? `<span class="check">${icon("check", 11, 2.4)}</span>` : ""}</button>`;
    })
    .join("");
  menu.hidden = false;
  const { width, height } = menu.getBoundingClientRect();
  menu.style.left = `${Math.min(x, innerWidth - width - 8)}px`;
  menu.style.top = `${Math.min(y, innerHeight - height - 8)}px`;
  menu.onclick = (event) => {
    const button = event.target.closest("button[data-index]");
    if (!button) return;
    closeMenu();
    items[Number(button.dataset.index)].run();
  };
}

function entryMenu(entry, x, y) {
  const items = [];
  if (entry.username) items.push({ title: "Copy username", run: () => copy(entry.username, "Username") });
  if (entry.password) items.push({ title: "Copy password", run: () => copy(entry.password, "Password") });
  const url = core.websiteURL(entry.url);
  if (url) items.push({ title: "Open website", run: () => platform.openURL(url.href) });
  if (items.length) items.push("-");
  items.push({ title: entry.favorite ? "Remove from favorites" : "Add to favorites", run: () => updateEntry(entry, { favorite: !entry.favorite }).then(refreshDesk) });
  items.push("-", { label: "Move to group" });
  for (const group of state.groups) {
    items.push({
      title: groupName(group),
      swatch: true,
      tint: tintStyle(group),
      checked: entry.groupID === group.id,
      run: () => updateEntry(entry, { groupID: entry.groupID === group.id ? null : group.id }).then(refreshDesk),
    });
  }
  items.push({ title: "No group", disabled: !entry.groupID, run: () => updateEntry(entry, { groupID: null }).then(refreshDesk) });
  items.push({ title: "New group…", run: () => newGroup((saved) => updateEntry(entry, { groupID: saved.id }).then(refreshDesk)) });
  items.push("-", { title: "Edit…", run: () => ((state.selection = entry.id), startEditing(entry)) });
  items.push("-", { title: "Delete…", destructive: true, run: () => confirmDeleteEntry(entry) });
  openMenu(x, y, items);
}

function confirmDeleteEntry(entry) {
  confirmDialog({
    title: `Delete “${entry.title || "Untitled"}”?`,
    text: "This can't be undone.",
    action: "Delete",
    onConfirm: () => deleteEntry(entry).then(refreshDesk),
  });
}

function confirmDeleteGroup(group) {
  const count = state.entries.filter((e) => e.groupID === group.id).length;
  confirmDialog({
    title: `Delete group “${groupName(group)}”?`,
    text: count === 0 ? "The group is empty." : `Its ${count} ${count === 1 ? "login stays" : "logins stay"} in your vault, just ungrouped.`,
    action: "Delete group",
    onConfirm: () => deleteGroup(group).then(refreshDesk),
  });
}

// MARK: - Events

const currentEntry = () => state.entries.find((e) => e.id === state.selection);

function select(id) {
  if (state.selection !== id) state.revealed = false;
  state.editing = null;
  state.selection = id;
  renderList();
  renderPanel();
  document.querySelector(`[data-entry="${CSS.escape(id)}"]`)?.scrollIntoView({ block: "nearest" });
}

function moveSelection(delta) {
  if (state.editing) return;
  const entries = filteredEntries(derived());
  if (!entries.length) return;
  const index = entries.findIndex((e) => e.id === state.selection);
  const current = index === -1 ? (delta > 0 ? -1 : entries.length) : index;
  select(entries[Math.min(Math.max(current + delta, 0), entries.length - 1)].id);
}

const actions = {
  "create-vault": createVault,
  unlock,
  lock,
  settings: () => openSettings(),
  generator: () => openGeneratorSheet(),
  "new-entry": startNewEntry,
  "new-group": () => newGroup(),
  "clear-search": () => {
    state.search = "";
    $("#search").value = "";
    renderList();
    $("#search").focus();
  },
  "toggle-favorite": () => {
    const entry = currentEntry();
    if (entry) updateEntry(entry, { favorite: !entry.favorite }).then(refreshDesk);
  },
  "close-detail": () => {
    state.selection = null;
    renderList();
    renderPanel();
  },
  "copy-username": () => currentEntry() && copy(currentEntry().username, "Username"),
  "copy-password": () => currentEntry() && copy(currentEntry().password, "Password"),
  "open-website": () => {
    const url = core.websiteURL(currentEntry()?.url);
    if (url) platform.openURL(url.href);
  },
  "toggle-reveal": () => {
    state.revealed = !state.revealed;
    renderPanel();
  },
  "edit-entry": () => currentEntry() && startEditing(currentEntry()),
  "delete-entry": () => currentEntry() && confirmDeleteEntry(currentEntry()),
  "cancel-edit": cancelEditing,
  "save-entry": saveEditing,
  "toggle-edit-reveal": () => {
    state.editing.reveal = !state.editing.reveal;
    const input = $("#edit-password");
    input.type = state.editing.reveal ? "text" : "password";
    const button = $('[data-action="toggle-edit-reveal"]');
    button.innerHTML = icon(state.editing.reveal ? "eyeOff" : "eye");
    button.title = state.editing.reveal ? "Hide" : "Show";
  },
  "editor-generator": () =>
    openGeneratorSheet((generated) => {
      closeOverlay();
      if (!state.editing) return;
      state.editing.draft.password = generated;
      state.editing.reveal = true;
      const input = $("#edit-password");
      input.value = generated;
      input.type = "text";
      $('[data-action="toggle-edit-reveal"]').innerHTML = icon("eyeOff");
      updateEditorStatus();
    }),
  "reveal-vault": () => platform.revealVault(),
  "win-min": () => platform.minimize(),
  "win-max": () => platform.toggleMaximize(),
  "win-close": () => platform.close(),
};

document.addEventListener("click", (event) => {
  if (!event.target.closest("#menu")) closeMenu();
  const overlay = $("#overlay");
  if (event.target === overlay || event.target.closest("[data-close]")) return closeOverlay();

  const actionButton = event.target.closest("[data-action]");
  if (actionButton && !actionButton.disabled) return actions[actionButton.dataset.action]?.();

  if (state.screen !== "unlocked" || overlay.contains(event.target)) return;
  const row = event.target.closest("[data-entry]");
  if (row) return select(row.dataset.entry);
  const filter = event.target.closest("[data-filter]");
  if (filter) {
    state.filter = filter.dataset.filter;
    renderList();
    renderHealth();
    return;
  }
  const chip = event.target.closest("[data-group]");
  if (chip) {
    state.groupFilter = state.groupFilter === chip.dataset.group ? null : chip.dataset.group;
    renderList();
    return;
  }
  const toggle = event.target.closest('[data-toggle="edit-favorite"]');
  if (toggle && state.editing) {
    state.editing.draft.favorite = !state.editing.draft.favorite;
    $("#edit-favorite").innerHTML = toggleHTML("edit-favorite", state.editing.draft.favorite, "Pin to favorites");
    updateEditorStatus();
  }
});

document.addEventListener("contextmenu", (event) => {
  // No browser menu anywhere, except to copy/paste inside text fields.
  if (!event.target.closest("input, textarea, .selectable")) event.preventDefault();
  if (state.screen !== "unlocked") return;
  const row = event.target.closest("[data-entry]");
  const chip = event.target.closest("[data-group]");
  if (row) {
    const entry = state.entries.find((e) => e.id === row.dataset.entry);
    if (entry) entryMenu(entry, event.clientX, event.clientY);
  } else if (chip) {
    const group = state.groups.find((g) => g.id === chip.dataset.group);
    if (group)
      openMenu(event.clientX, event.clientY, [
        { title: "Edit group…", run: () => openGroupEditor(group, false) },
        { title: "Delete group…", destructive: true, run: () => confirmDeleteGroup(group) },
      ]);
  }
});

const EDITOR_FIELDS = { "edit-title": "title", "edit-username": "username", "edit-url": "url", "edit-password": "password", "edit-notes": "notes" };

document.addEventListener("input", (event) => {
  const id = event.target.id;
  if (id === "setup-password" || id === "setup-confirm") setupValidation();
  else if (id === "unlock-password") {
    $("#unlock-button").disabled = !event.target.value || state.busy;
  } else if (id === "search") {
    state.search = event.target.value;
    renderList();
  } else if (EDITOR_FIELDS[id] && state.editing) {
    state.editing.draft[EDITOR_FIELDS[id]] = event.target.value;
    updateEditorStatus();
  }
});

document.addEventListener("change", (event) => {
  if (event.target.id !== "edit-group" || !state.editing) return;
  const value = event.target.value;
  if (value === "__new") {
    event.target.value = state.editing.draft.groupID ?? "";
    newGroup((saved) => {
      if (!state.editing) return;
      state.editing.draft.groupID = saved.id;
      renderPanel();
    });
    return;
  }
  state.editing.draft.groupID = value || null;
  // Redraw for the swatch color while keeping what was typed (it lives in the draft).
  renderEditor($("#panel"));
});

document.addEventListener("keydown", (event) => {
  const ctrl = event.ctrlKey || event.metaKey;
  const key = event.key.toLowerCase();
  const typing = event.target.closest?.("input, textarea, select");
  const overlayOpen = $("#overlay").childElementCount > 0;

  if (event.key === "Escape") {
    if (!$("#menu").hidden) return closeMenu();
    if (overlayOpen) return closeOverlay();
    if (state.editing) return cancelEditing();
    if (event.target.id === "search" && state.search) return actions["clear-search"]();
    return;
  }

  if (event.key === "Enter" && !event.shiftKey) {
    if (event.target.id === "setup-password") return $("#setup-confirm").focus();
    if (event.target.id === "setup-confirm") return createVault();
    if (event.target.id === "unlock-password") return unlock();
    if (state.editing && !overlayOpen && (ctrl || (typing && event.target.tagName === "INPUT"))) {
      event.preventDefault();
      return saveEditing();
    }
  }

  if (ctrl && key === ",") {
    event.preventDefault();
    return openSettings();
  }
  // Block browser shortcuts that make no sense here (reload, print, find, zoom…).
  if (ctrl && ["r", "p", "j", "u", "s", "o", "+", "-", "=", "0"].includes(key)) event.preventDefault();
  if (event.key === "F5") event.preventDefault();

  if (state.screen !== "unlocked" || overlayOpen) return;
  if (ctrl && event.shiftKey && key === "g") {
    event.preventDefault();
    return openGeneratorSheet();
  }
  if (ctrl && key === "n") {
    event.preventDefault();
    return startNewEntry();
  }
  if (ctrl && key === "l") {
    event.preventDefault();
    return lock();
  }
  if (ctrl && key === "f") {
    event.preventDefault();
    return $("#search")?.focus();
  }
  if (ctrl && key === "e" && !state.editing && currentEntry()) {
    event.preventDefault();
    return startEditing(currentEntry());
  }
  if (ctrl && key === "c" && !typing && !getSelection()?.toString() && currentEntry()?.password && !state.editing) {
    event.preventDefault();
    return copy(currentEntry().password, "Password");
  }
  if (!typing || event.target.id === "search") {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      moveSelection(event.key === "ArrowDown" ? 1 : -1);
    }
  }
});

addEventListener("resize", closeMenu);

// MARK: - Boot

async function boot() {
  applyAppearance();
  const demo = !platform.isApp && new URLSearchParams(location.search).get("demo");
  if (demo) return bootDemo(demo);
  try {
    state.screen = (await platform.vaultExists()) ? "locked" : "setup";
  } catch {
    state.screen = "setup";
  }
  render();
}

/** Browser-only preview with sample data (`index.html?demo=vault|editor|locked|setup`). */
async function bootDemo(screen) {
  const work = { id: core.newID(), name: "Work", color: 0x3b7dd8 };
  const finance = { id: core.newID(), name: "Finance", color: 0x0b8f57 };
  const streaming = { id: core.newID(), name: "Streaming", color: 0xe06c9f };
  const entries = [
    core.makeEntry({ title: "GitHub", username: "jane.doe@example.com", password: "tmfEzEgKeHwpBD9BUJff", url: "github.com", notes: "Recovery codes are in the safe.", favorite: true, groupID: work.id }),
    core.makeEntry({ title: "Google", username: "jane.doe@example.org", password: "Velvet-Comet-Ladder4-Prism", url: "accounts.google.com", favorite: true }),
    core.makeEntry({ title: "Microsoft", username: "jane@example.net", password: "9XvjsN8T3w", url: "account.microsoft.com" }),
    core.makeEntry({ title: "Netflix", username: "jane.doe@example.com", password: "password1", url: "netflix.com", groupID: streaming.id }),
    core.makeEntry({ title: "Figma", username: "jdoe", password: "vCSwwq!7U0aI", url: "figma.com", groupID: work.id }),
    core.makeEntry({ title: "Amazon Web Services", username: "demo-admin", password: "8%ETUM3REV8zJmO5x1nN", url: "console.aws.amazon.com", favorite: true, groupID: work.id }),
    core.makeEntry({ title: "Spotify", username: "janedoe", password: "summer2024", url: "spotify.com", groupID: streaming.id }),
    core.makeEntry({ title: "Notion", username: "jane.doe@example.com", password: "Harbor.Tulip.Engine.8", url: "notion.so", groupID: work.id }),
    core.makeEntry({ title: "Chase Bank", username: "jdoe-demo", password: "!EN&yx0!TN#5", url: "chase.com", groupID: finance.id }),
  ];
  const vault = await core.createVault("demo", 1_000);
  await platform.writeVault(await core.encryptVault(entries, [work, finance, streaming], vault));
  if (screen === "setup") {
    localStorage.removeItem("safespace.dev-vault");
    state.screen = "setup";
    return render();
  }
  if (screen === "locked") {
    state.screen = "locked";
    return render();
  }
  openVault({ vault, entries, groups: [work, finance, streaming] });
  select(entries[0].id);
  if (screen === "editor") startEditing(entries[0]);
  if (screen === "settings") openSettings();
  if (screen === "generator") openGeneratorSheet();
}

boot();
