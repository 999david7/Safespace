// node --test tests/
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  characterSets,
  createVault,
  decryptClassicVault,
  decryptVault,
  defaultPassphraseOptions,
  defaultPasswordOptions,
  encryptVault,
  estimateEntropy,
  generatePassphrase,
  generatePassword,
  hostOf,
  importMessage,
  isClassicVault,
  mergeVaults,
  passwordVariants,
  unlockClassicVault,
  unlockVault,
  makeEntry,
  passwordEntropy,
  readClassicHeader,
  readHeader,
  strengthLevel,
  vaultHealth,
} from "../src/core.js";

// Low iteration counts keep the tests fast; the app uses DEFAULT_ITERATIONS.

test("encrypt/decrypt round trip keeps entries and groups", async () => {
  const vault = await createVault("correct horse battery staple", 1_000);
  const group = { id: "6F1C3D3E-1111-4222-8333-944455556666", name: "Work", color: 0x3b7dd8 };
  const entries = [makeEntry({ title: "GitHub", username: "me", password: "s3cr3t!", url: "github.com", groupID: group.id })];
  const text = await encryptVault(entries, [group], vault);
  const opened = await decryptVault(text, "correct horse battery staple");
  assert.deepEqual(opened.entries, entries);
  assert.deepEqual(opened.groups, [group]);
  assert.equal(opened.vault.iterations, 1_000);
});

test("ciphertext does not contain plaintext", async () => {
  const vault = await createVault("pw", 1_000);
  const text = await encryptVault([makeEntry({ title: "VerySecretTitle", password: "hunter2hunter2" })], [], vault);
  assert.ok(!text.includes("VerySecretTitle"));
  assert.ok(!text.includes("hunter2"));
});

test("wrong password and tampering are rejected", async () => {
  const vault = await createVault("right", 1_000);
  const text = await encryptVault([], [], vault);
  await assert.rejects(decryptVault(text, "wrong"), { code: "wrongPassword" });

  const file = JSON.parse(text);
  file.iterations = 2_000; // header is authenticated
  await assert.rejects(decryptVault(JSON.stringify(file), "right"), { code: "wrongPassword" });
});

test("newer and malformed files are refused", async () => {
  const vault = await createVault("pw", 1_000);
  const file = JSON.parse(await encryptVault([], [], vault));
  await assert.rejects(decryptVault(JSON.stringify({ ...file, version: 2 }), "pw"), { code: "unsupportedVersion" });
  await assert.rejects(decryptVault("not json", "pw"), { code: "corruptFile" });
  await assert.rejects(decryptVault(JSON.stringify({ ...file, kdf: "scrypt" }), "pw"), { code: "corruptFile" });
  assert.equal(readHeader(JSON.stringify(file)).iterations, 1_000);
});

test("dangling group links are dropped and nil groups are omitted on disk", async () => {
  const vault = await createVault("pw", 1_000);
  const text = await encryptVault([makeEntry({ title: "a", groupID: "MISSING" }), makeEntry({ title: "b" })], [], vault);
  const opened = await decryptVault(text, "pw");
  assert.equal(opened.entries[0].groupID, null);
});

test("generated passwords honour the options", () => {
  for (let i = 0; i < 200; i++) {
    const options = { ...defaultPasswordOptions(), length: 12, symbols: false, excludeAmbiguous: true };
    const password = generatePassword(options);
    assert.equal(password.length, 12);
    assert.match(password, /[A-Z]/);
    assert.match(password, /[a-z]/);
    assert.match(password, /[0-9]/);
    assert.doesNotMatch(password, /[Il1O0o]|[^A-Za-z0-9]/);
  }
  assert.equal(generatePassword({ ...defaultPasswordOptions(), uppercase: false, lowercase: false, digits: false, symbols: false }), "");
});

test("symbol set drops letters, digits, whitespace and duplicates", () => {
  const sets = characterSets({ ...defaultPasswordOptions(), uppercase: false, lowercase: false, digits: false, symbolSet: "a1 !!?" });
  assert.deepEqual(sets, [["!", "?"]]);
  assert.equal(Math.round(passwordEntropy({ ...defaultPasswordOptions(), length: 20 })), 130);
});

test("passphrases have the requested shape", () => {
  const phrase = generatePassphrase({ ...defaultPassphraseOptions(), wordCount: 4, separator: ".", includeNumber: false });
  const words = phrase.split(".");
  assert.equal(words.length, 4);
  for (const word of words) assert.match(word, /^[A-Z][a-z]+$/);
});

test("strength estimate", () => {
  assert.equal(estimateEntropy("password"), 0);
  assert.equal(strengthLevel(estimateEntropy("aaaaaaaa")), 0);
  assert.ok(strengthLevel(estimateEntropy("tmfEzEgKeHwpBD9BUJff")) >= 3);
});

test("health flags weak and reused passwords", () => {
  const a = makeEntry({ password: "password1" });
  const b = makeEntry({ password: "Velvet-Comet-Ladder4-Prism" });
  const c = makeEntry({ password: "Velvet-Comet-Ladder4-Prism" });
  const { weak, reused } = vaultHealth([a, b, c, makeEntry()]);
  assert.deepEqual([...weak], [a.id]);
  assert.deepEqual([...reused].sort(), [b.id, c.id].sort());
});

test("host parsing tolerates missing schemes", () => {
  assert.equal(hostOf("github.com/login"), "github.com");
  assert.equal(hostOf("https://accounts.google.com"), "accounts.google.com");
  assert.equal(hostOf(""), null);
});

test("import merges without losing anything", () => {
  const work = { id: "W", name: "Work", color: 1 };
  const importedWork = { id: "W2", name: " work ", color: 2 };
  const banking = { id: "B", name: "Banking", color: 3 };
  const shared = makeEntry({ title: "GitHub", password: "a", updatedAt: 100 });
  const current = { entries: [shared, makeEntry({ title: "Mail", username: "me", password: "x" })], groups: [work] };
  const imported = {
    entries: [
      { ...shared, password: "b", updatedAt: 200 },
      makeEntry({ title: "Mail", username: "me", password: "x" }),
      makeEntry({ title: "Bank", password: "y", groupID: banking.id }),
      makeEntry({ title: "Jira", password: "z", groupID: importedWork.id }),
    ],
    groups: [importedWork, banking],
  };
  const merged = mergeVaults(current, imported);
  assert.deepEqual(merged.summary, { added: 2, updated: 1, skipped: 1, groupsAdded: 1 });
  assert.equal(importMessage(merged.summary), "Imported 3 logins · 1 new group · 1 already here");
  assert.deepEqual(merged.groups.map((g) => g.name), ["Work", "Banking"]);
  assert.equal(merged.entries.find((e) => e.id === shared.id).password, "b");
  assert.equal(merged.entries.find((e) => e.title === "Jira").groupID, "W");
  assert.equal(merged.entries.find((e) => e.title === "Bank").groupID, "B");

  const again = mergeVaults(merged, imported);
  assert.deepEqual(again.summary, { added: 0, updated: 0, skipped: 4, groupsAdded: 0 });
  assert.deepEqual(again.entries, merged.entries);
});

test("unlock accepts the other Unicode form of the same password", async () => {
  const nfd = "Grüße-Öl".normalize("NFD");
  const vault = await createVault(nfd, 1_000);
  const text = await encryptVault([makeEntry({ title: "a" })], [], vault);
  const typed = "Grüße-Öl".normalize("NFC");
  assert.notEqual(typed, nfd);
  assert.equal((await unlockVault(text, typed)).entries[0].title, "a");
  await assert.rejects(unlockVault(text, "Gruse-Ol"), { code: "wrongPassword" });
  assert.deepEqual(passwordVariants("plain"), ["plain"]);
});

// MARK: - Original SafeSpace (C++ vault.dat)

/** Writes a vault the way the original app's `Vault::save` does. */
async function classicVault(records, password, iterations = 1_000) {
  const enc = new TextEncoder();
  const parts = [];
  const u32 = (v) => { const b = new Uint8Array(4); new DataView(b.buffer).setUint32(0, v, true); parts.push(b); };
  const i64 = (v) => { const b = new Uint8Array(8); new DataView(b.buffer).setBigInt64(0, BigInt(v), true); parts.push(b); };
  const str = (s) => { const b = enc.encode(s); u32(b.length); parts.push(b); };
  u32(records.length);
  u32(records.length + 1);
  records.forEach((r, i) => {
    u32(i + 1);
    [r.service, r.username ?? "", r.password ?? "", r.category ?? "", r.notes ?? ""].forEach(str);
    i64(r.created ?? 1_700_000_000);
    i64(r.updated ?? 1_700_000_000);
  });
  const plain = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  parts.reduce((offset, p) => (plain.set(p, offset), offset + p.length), 0);

  const salt = crypto.getRandomValues(new Uint8Array(16));
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const material = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveKey"]);
  const key = await crypto.subtle.deriveKey({ name: "PBKDF2", hash: "SHA-256", salt, iterations }, material, { name: "AES-GCM", length: 256 }, false, ["encrypt"]);
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, plain));
  const cipher = sealed.subarray(0, sealed.length - 16);
  const tag = sealed.subarray(sealed.length - 16);

  const header = new Uint8Array(64);
  header.set(enc.encode("SAFESPC\0"));
  const view = new DataView(header.buffer);
  view.setUint32(8, 1, true);
  view.setUint32(12, iterations, true);
  header.set(salt, 16);
  header.set(nonce, 32);
  header.set(tag, 44);
  view.setUint32(60, cipher.length, true);
  return new Uint8Array([...header, ...cipher]);
}

test("original SafeSpace vault decrypts, categories become groups", async () => {
  const bytes = await classicVault(
    [
      { service: "GitHub", username: "me", password: "s3cr3t!", category: "Work", notes: "2FA on", created: 1_700_000_000, updated: 1_700_000_500 },
      { service: "Bänk", username: "ü", password: "pässwörd", category: " work " },
      { service: "Misc" },
    ],
    "hunter2 ✓",
  );
  assert.ok(isClassicVault(bytes));
  assert.equal(readClassicHeader(bytes).iterations, 1_000);
  const { entries, groups } = await decryptClassicVault(bytes, "hunter2 ✓");
  assert.deepEqual(entries.map((e) => [e.title, e.username, e.password, e.notes]), [
    ["GitHub", "me", "s3cr3t!", "2FA on"],
    ["Bänk", "ü", "pässwörd", ""],
    ["Misc", "", "", ""],
  ]);
  assert.deepEqual(groups.map((g) => g.name), ["Work"]);
  assert.deepEqual(entries.map((e) => e.groupID), [groups[0].id, groups[0].id, null]);
  // Unix seconds become Swift reference-date stamps.
  assert.equal(entries[0].updatedAt, 1_700_000_500 - 978_307_200);
});

test("original SafeSpace vault: wrong password, NFD password, damaged file", async () => {
  const bytes = await classicVault([{ service: "a" }], "Grüße");
  await assert.rejects(decryptClassicVault(bytes, "wrong"), { code: "wrongPassword" });
  const opened = await unlockClassicVault(bytes, "Grüße".normalize("NFD"));
  assert.equal(opened.password, "Grüße".normalize("NFC"));
  assert.throws(() => readClassicHeader(bytes.subarray(0, bytes.length - 3)), { code: "corruptFile" });
  assert.ok(!isClassicVault(new TextEncoder().encode('{"version":1}')));
});
