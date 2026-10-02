// node --test tests/
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  characterSets,
  createVault,
  decryptVault,
  defaultPassphraseOptions,
  defaultPasswordOptions,
  encryptVault,
  estimateEntropy,
  generatePassphrase,
  generatePassword,
  hostOf,
  importMessage,
  isLegacyVault,
  mergeVaults,
  passwordVariants,
  unlockVault,
  makeEntry,
  passwordEntropy,
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

const latin1 = (bytes) => Buffer.from(bytes).toString("latin1");

test("ciphertext does not contain plaintext", async () => {
  const vault = await createVault("pw", 1_000);
  const text = latin1(await encryptVault([makeEntry({ title: "VerySecretTitle", password: "hunter2hunter2" })], [], vault));
  assert.ok(!text.includes("VerySecretTitle"));
  assert.ok(!text.includes("hunter2"));
});

test("vault.dat has the binary layout", async () => {
  const vault = await createVault("pw", 1_000);
  const bytes = await encryptVault([], [], vault);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  assert.equal(latin1(bytes.subarray(0, 8)), "SAFESPC\0");
  assert.equal(view.getUint32(8, true), 1);
  assert.equal(view.getUint32(12, true), 1_000);
  assert.deepEqual(bytes.subarray(16, 48), vault.salt);
  assert.equal(view.getUint32(60, true), bytes.length - 64);
  assert.equal(isLegacyVault(bytes), false);
});

test("wrong password and tampering are rejected", async () => {
  const vault = await createVault("right", 1_000);
  const bytes = await encryptVault([], [], vault);
  await assert.rejects(decryptVault(bytes, "wrong"), { code: "wrongPassword" });

  // Every header byte is authenticated, and so is the ciphertext.
  for (const offset of [8, 20, 50, bytes.length - 1]) {
    const tampered = bytes.slice();
    tampered[offset] ^= 1;
    await assert.rejects(decryptVault(tampered, "right"));
  }
});

test("newer and malformed files are refused", async () => {
  const vault = await createVault("pw", 1_000);
  const bytes = await encryptVault([], [], vault);
  const newer = bytes.slice();
  newer[8] = 2;
  await assert.rejects(decryptVault(newer, "pw"), { code: "unsupportedVersion" });
  await assert.rejects(decryptVault("not json", "pw"), { code: "corruptFile" });
  await assert.rejects(decryptVault(bytes.subarray(0, bytes.length - 1), "pw"), { code: "corruptFile" });
  assert.equal(readHeader(bytes).iterations, 1_000);
});

/** A JSON vault as Safespace 1.0–1.2 wrote it. */
async function legacyVault(password, payload) {
  const salt = crypto.getRandomValues(new Uint8Array(32));
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const material = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveKey"]);
  const key = await crypto.subtle.deriveKey({ name: "PBKDF2", hash: "SHA-256", salt, iterations: 1_000 }, material, { name: "AES-GCM", length: 256 }, false, ["encrypt"]);
  const b64 = (bytes) => Buffer.from(bytes).toString("base64");
  const additionalData = new TextEncoder().encode(`safespace|1|PBKDF2-HMAC-SHA256|1000|${b64(salt)}`);
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData }, key, new TextEncoder().encode(JSON.stringify(payload))));
  const file = { ciphertext: b64(Buffer.concat([nonce, sealed])), iterations: 1_000, kdf: "PBKDF2-HMAC-SHA256", salt: b64(salt), version: 1 };
  return JSON.stringify(file, null, 2);
}

test("old JSON vaults still open, as text or bytes, and re-save as binary", async () => {
  const entry = makeEntry({ title: "Old" });
  const text = await legacyVault("pw", { entries: [entry] });
  assert.equal(isLegacyVault(text), true);
  const opened = await decryptVault(new TextEncoder().encode(text), "pw");
  assert.deepEqual(opened.entries, [entry]);
  assert.equal((await decryptVault(text, "pw")).entries[0].title, "Old");

  const resaved = await encryptVault(opened.entries, opened.groups, opened.vault);
  assert.equal(isLegacyVault(resaved), false);
  assert.deepEqual((await decryptVault(resaved, "pw")).entries, [entry]);
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
