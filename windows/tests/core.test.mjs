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
