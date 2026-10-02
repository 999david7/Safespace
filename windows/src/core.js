// Vault format, password generator and strength estimate. A port of Sources/SafespaceCore, kept
// byte-compatible with the Mac app so the same vault file opens on both.
// UI-free: runs in the app's WebView and under `node --test`.

import { WORDS } from "./words.js";

const subtle = globalThis.crypto.subtle;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

// MARK: - Vault

export const CURRENT_VERSION = 1;
export const KDF_NAME = "PBKDF2-HMAC-SHA256";
export const DEFAULT_ITERATIONS = 600_000;
const SALT_LENGTH = 32;
const NONCE_LENGTH = 12;

/** Swift's JSONEncoder writes dates as seconds since 2001-01-01. */
const REFERENCE_EPOCH = 978_307_200;
export const nowStamp = () => Date.now() / 1000 - REFERENCE_EPOCH;
export const stampToDate = (stamp) => new Date((stamp + REFERENCE_EPOCH) * 1000);

export class VaultError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
const wrongPassword = () => new VaultError("wrongPassword", "Incorrect master password.");
const corruptFile = () => new VaultError("corruptFile", "The vault file is damaged or unreadable.");

export function toBase64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

export function fromBase64(text) {
  if (typeof text !== "string") throw corruptFile();
  let binary;
  try {
    binary = atob(text);
  } catch {
    throw corruptFile();
  }
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

/** The header fields, bound to the ciphertext as authenticated data so they can't be swapped. */
function associatedData(version, kdf, iterations, salt) {
  return encoder.encode(`safespace|${version}|${kdf}|${iterations}|${toBase64(salt)}`);
}

export async function deriveKey(password, salt, iterations) {
  const passwordBytes = encoder.encode(password);
  if (passwordBytes.length === 0) throw new VaultError("emptyPassword", "The master password can't be empty.");
  const material = await subtle.importKey("raw", passwordBytes, "PBKDF2", false, ["deriveKey"]);
  return subtle.deriveKey(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations },
    material,
    { name: "AES-GCM", length: 256 },
    false, // the key never leaves WebCrypto
    ["encrypt", "decrypt"],
  );
}

/** A fresh key with a new random salt, for a new or re-keyed vault. */
export async function createVault(password, iterations = DEFAULT_ITERATIONS) {
  const salt = crypto.getRandomValues(new Uint8Array(SALT_LENGTH));
  return { key: await deriveKey(password, salt, iterations), salt, iterations };
}

/** Encrypts entries and groups into the JSON file the Mac app writes. */
export async function encryptVault(entries, groups, vault) {
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_LENGTH));
  const plaintext = encoder.encode(JSON.stringify({ entries: entries.map(serializeEntry), groups: groups.map(serializeGroup) }));
  const sealed = new Uint8Array(
    await subtle.encrypt(
      { name: "AES-GCM", iv: nonce, additionalData: associatedData(CURRENT_VERSION, KDF_NAME, vault.iterations, vault.salt) },
      vault.key,
      plaintext,
    ),
  );
  // Same layout as CryptoKit's combined box: nonce ‖ ciphertext ‖ tag.
  const combined = new Uint8Array(nonce.length + sealed.length);
  combined.set(nonce);
  combined.set(sealed, nonce.length);
  const file = {
    ciphertext: toBase64(combined),
    iterations: vault.iterations,
    kdf: KDF_NAME,
    salt: toBase64(vault.salt),
    version: CURRENT_VERSION,
  };
  return JSON.stringify(file, null, 2);
}

function parseFile(text) {
  let file;
  try {
    file = JSON.parse(text);
  } catch {
    throw corruptFile();
  }
  if (!file || typeof file !== "object" || !Number.isInteger(file.version)) throw corruptFile();
  if (file.version > CURRENT_VERSION) {
    throw new VaultError("unsupportedVersion", `This vault was created by a newer version of Safespace (format ${file.version}).`);
  }
  const salt = fromBase64(file.salt);
  const ciphertext = fromBase64(file.ciphertext);
  if (file.kdf !== KDF_NAME || salt.length < 16 || !Number.isInteger(file.iterations) || file.iterations <= 0) throw corruptFile();
  if (ciphertext.length < NONCE_LENGTH + 16) throw corruptFile();
  return { ...file, salt, ciphertext };
}

/** Reads the KDF parameters without decrypting. */
export function readHeader(text) {
  const { salt, iterations } = parseFile(text);
  return { salt, iterations };
}

export async function decryptVault(text, password) {
  const file = parseFile(text);
  const key = await deriveKey(password, file.salt, file.iterations);
  return decryptWithKey(file, key);
}

async function decryptWithKey(file, key) {
  let plaintext;
  try {
    plaintext = await subtle.decrypt(
      {
        name: "AES-GCM",
        iv: file.ciphertext.subarray(0, NONCE_LENGTH),
        additionalData: associatedData(file.version, file.kdf, file.iterations, file.salt),
      },
      key,
      file.ciphertext.subarray(NONCE_LENGTH),
    );
  } catch {
    // GCM authentication failure: wrong key or tampered data. Indistinguishable by design.
    throw wrongPassword();
  }
  let payload;
  try {
    payload = JSON.parse(decoder.decode(plaintext));
  } catch {
    throw corruptFile();
  }
  if (!payload || !Array.isArray(payload.entries)) throw corruptFile();
  const groups = (payload.groups ?? []).map(normalizeGroup);
  const groupIDs = new Set(groups.map((g) => g.id));
  // Drop links to groups that no longer exist so the UI never sees a dangling reference.
  const entries = payload.entries.map(normalizeEntry).map((e) => (e.groupID && !groupIDs.has(e.groupID) ? { ...e, groupID: null } : e));
  return { vault: { key, salt: file.salt, iterations: file.iterations }, entries, groups };
}

// MARK: - Entries & groups

export const newID = () => crypto.randomUUID().toUpperCase();

export function makeEntry(fields = {}) {
  const now = nowStamp();
  return {
    id: newID(),
    title: "",
    username: "",
    password: "",
    url: "",
    notes: "",
    favorite: false,
    groupID: null,
    createdAt: now,
    updatedAt: now,
    ...fields,
  };
}

function normalizeEntry(raw) {
  if (!raw || typeof raw.id !== "string") throw corruptFile();
  return makeEntry({ ...raw, groupID: raw.groupID ?? null });
}

function serializeEntry(entry) {
  // Swift omits nil optionals; every other field is required by its decoder.
  const { groupID, ...rest } = entry;
  return groupID ? { ...rest, groupID } : rest;
}

function normalizeGroup(raw) {
  if (!raw || typeof raw.id !== "string") throw corruptFile();
  return { ...raw, name: String(raw.name ?? ""), color: (Number(raw.color) >>> 0) & 0xffffff };
}

function serializeGroup(group) {
  return { ...group, color: group.color & 0xffffff };
}

/** Preset swatches offered when creating a group. */
export const GROUP_PALETTE = [0x3b7dd8, 0x0b8f57, 0xd94b3d, 0xe0a800, 0x8e5bd1, 0xe06c9f, 0x1aa3a3, 0xe0772b, 0x6b6b70];

export function suggestedGroupColor(existing) {
  const used = new Set(existing.map((g) => g.color));
  return GROUP_PALETTE.find((c) => !used.has(c)) ?? GROUP_PALETTE[existing.length % GROUP_PALETTE.length];
}

/** `url` as an openable URL, adding `https://` when no scheme was typed. */
export function websiteURL(url) {
  const trimmed = (url ?? "").trim();
  if (!trimmed) return null;
  const withScheme = trimmed.includes("://") ? trimmed : `https://${trimmed}`;
  try {
    const parsed = new URL(withScheme);
    return parsed.hostname ? parsed : null;
  } catch {
    return null;
  }
}

export const hostOf = (url) => websiteURL(url)?.hostname ?? null;

// MARK: - Randomness

/** Unbiased integer in [0, n) from the system CSPRNG. */
export function randomInt(n) {
  if (n <= 0) return 0;
  const limit = Math.floor(0x1_0000_0000 / n) * n;
  const buffer = new Uint32Array(1);
  for (;;) {
    crypto.getRandomValues(buffer);
    if (buffer[0] < limit) return buffer[0] % n;
  }
}

const pick = (array) => array[randomInt(array.length)];

function shuffle(array) {
  for (let i = array.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}

// MARK: - Generator

export const DEFAULT_SYMBOLS = "!@#$%^&*()-_=+[]{};:,.<>?/~";
const AMBIGUOUS = new Set(["I", "l", "1", "O", "0", "o", "|", "`", "'", '"']);
const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
const characters = (text) => Array.from(segmenter.segment(text), (s) => s.segment);
const isLetter = (c) => /\p{L}/u.test(c);
const isNumber = (c) => /\p{N}/u.test(c);
const isWhitespace = (c) => /\s/u.test(c);

export const defaultPasswordOptions = () => ({
  length: 20,
  uppercase: true,
  lowercase: true,
  digits: true,
  symbols: true,
  symbolSet: DEFAULT_SYMBOLS,
  excludeAmbiguous: false,
  requireEveryType: true,
});

export const defaultPassphraseOptions = () => ({ wordCount: 5, separator: "-", capitalize: true, includeNumber: true });

export function characterSets(options) {
  let sets = [];
  if (options.uppercase) sets.push([..."ABCDEFGHIJKLMNOPQRSTUVWXYZ"]);
  if (options.lowercase) sets.push([..."abcdefghijklmnopqrstuvwxyz"]);
  if (options.digits) sets.push([..."0123456789"]);
  if (options.symbols) {
    const seen = new Set();
    sets.push(characters(options.symbolSet).filter((c) => !isLetter(c) && !isNumber(c) && !isWhitespace(c) && !seen.has(c) && seen.add(c)));
  }
  if (options.excludeAmbiguous) sets = sets.map((set) => set.filter((c) => !AMBIGUOUS.has(c)));
  return sets.filter((set) => set.length > 0);
}

export function generatePassword(options) {
  const sets = characterSets(options);
  if (sets.length === 0 || options.length <= 0) return "";
  const pool = sets.flat();
  const chars = [];
  if (options.requireEveryType && options.length >= sets.length) {
    for (const set of sets) chars.push(pick(set));
  }
  while (chars.length < options.length) chars.push(pick(pool));
  return shuffle(chars).join("");
}

export function passwordEntropy(options) {
  const pool = characterSets(options).reduce((sum, set) => sum + set.length, 0);
  return pool > 1 ? options.length * Math.log2(pool) : 0;
}

export function generatePassphrase(options) {
  const count = Math.max(1, options.wordCount);
  let words = Array.from({ length: count }, () => pick(WORDS));
  if (options.capitalize) words = words.map((w) => w[0].toUpperCase() + w.slice(1));
  if (options.includeNumber) words[randomInt(count)] += String(randomInt(10));
  return words.join(options.separator);
}

export function passphraseEntropy(options) {
  const count = Math.max(1, options.wordCount);
  let bits = count * Math.log2(WORDS.length);
  if (options.includeNumber) bits += Math.log2(10) + Math.log2(count);
  return bits;
}

export const WORD_COUNT = WORDS.length;

// MARK: - Strength

export const STRENGTH = [
  { label: "Very weak", tone: "red" },
  { label: "Weak", tone: "red" },
  { label: "Fair", tone: "amber" },
  { label: "Strong", tone: "green" },
  { label: "Very strong", tone: "green" },
];

/** 0 = very weak … 4 = very strong. */
export function strengthLevel(entropy) {
  if (entropy < 28) return 0;
  if (entropy < 45) return 1;
  if (entropy < 60) return 2;
  if (entropy < 80) return 3;
  return 4;
}

const COMMON = new Set([
  "password", "123456", "12345678", "123456789", "qwerty", "abc123", "111111",
  "letmein", "welcome", "admin", "iloveyou", "monkey", "dragon", "passw0rd",
  "password1", "qwerty123", "1234567890", "football", "baseball", "sunshine",
]);

/** A rough entropy estimate for a password the user typed themselves. */
export function estimateEntropy(password) {
  if (!password) return 0;
  if (COMMON.has(password.toLowerCase())) return 0;
  const chars = characters(password);
  const isASCII = (c) => c.length === 1 && c.charCodeAt(0) < 0x80;
  let pool = 0;
  if (chars.some((c) => /\p{Ll}/u.test(c))) pool += 26;
  if (chars.some((c) => /\p{Lu}/u.test(c))) pool += 26;
  if (chars.some(isNumber)) pool += 10;
  if (chars.some((c) => isASCII(c) && !isLetter(c) && !isNumber(c))) pool += 33;
  if (chars.some((c) => !isASCII(c))) pool += 100;
  if (pool <= 1) return 0;
  const length = chars.length;
  // Penalise repetition like "aaaaaaaa" or "abababab".
  const repetitionFactor = Math.min(1, new Set(chars).size / length + 0.35);
  return length * Math.log2(pool) * repetitionFactor;
}

/** IDs of logins whose password is weak, and of those sharing a password with another login. */
export function vaultHealth(entries) {
  const weak = new Set();
  const byPassword = new Map();
  for (const entry of entries) {
    if (!entry.password) continue;
    if (strengthLevel(estimateEntropy(entry.password)) <= 1) weak.add(entry.id);
    byPassword.set(entry.password, [...(byPassword.get(entry.password) ?? []), entry.id]);
  }
  const reused = new Set([...byPassword.values()].filter((ids) => ids.length > 1).flat());
  return { weak, reused };
}

// MARK: - Import

/**
 * Adds the logins and groups of an imported vault without losing anything here. Same rules as
 * `VaultContents.merging` in the Mac app: groups match by id, then by name; a login with a known
 * id replaces ours only if it was edited later; an identical copy of a login here is skipped.
 */
export function mergeVaults(current, imported) {
  const groups = [...current.groups];
  const entries = [...current.entries];
  const summary = { added: 0, updated: 0, skipped: 0, groupsAdded: 0 };
  const normalized = (name) => (name ?? "").trim().toLowerCase();

  const groupMap = new Map();
  for (const group of imported.groups) {
    const match = groups.find((g) => g.id === group.id) ?? groups.find((g) => normalized(g.name) === normalized(group.name));
    if (match) groupMap.set(group.id, match.id);
    else {
      groups.push(group);
      groupMap.set(group.id, group.id);
      summary.groupsAdded++;
    }
  }

  const sameLogin = (a, b) => a.title === b.title && a.username === b.username && a.password === b.password && a.url === b.url;
  for (const raw of imported.entries) {
    const entry = { ...raw, groupID: raw.groupID ? groupMap.get(raw.groupID) ?? null : null };
    const index = entries.findIndex((e) => e.id === entry.id);
    if (index !== -1) {
      if (entry.updatedAt > entries[index].updatedAt) {
        entries[index] = entry;
        summary.updated++;
      } else summary.skipped++;
    } else if (entries.some((e) => sameLogin(e, entry))) summary.skipped++;
    else {
      entries.push(entry);
      summary.added++;
    }
  }
  return { entries, groups, summary };
}

/** "Imported 12 logins · 1 new group · 3 already here" */
export function importMessage({ added, updated, skipped, groupsAdded }) {
  const changed = added + updated;
  const parts = [`Imported ${changed} ${changed === 1 ? "login" : "logins"}`];
  if (groupsAdded > 0) parts.push(`${groupsAdded} new ${groupsAdded === 1 ? "group" : "groups"}`);
  if (skipped > 0) parts.push(`${skipped} already here`);
  return parts.join(" · ");
}
