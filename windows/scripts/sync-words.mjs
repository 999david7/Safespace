// Regenerates src/words.js from the Swift word list so both apps use the same passphrase words.
//   node scripts/sync-words.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = new URL("../../", import.meta.url);
const swift = readFileSync(new URL("Sources/SafespaceCore/WordList.swift", root), "utf8");
const raw = swift.split('"""')[1];
const words = [...new Set(raw.split(/\s+/).filter(Boolean))];
const lines = [];
for (let i = 0; i < words.length; i += 16) lines.push("  " + words.slice(i, i + 16).map((w) => `"${w}"`).join(", ") + ",");
writeFileSync(
  fileURLToPath(new URL("../src/words.js", import.meta.url)),
  `// Generated from Sources/SafespaceCore/WordList.swift by scripts/sync-words.mjs. Do not edit.\nexport const WORDS = [\n${lines.join("\n")}\n];\n`,
);
console.log(`${words.length} words`);
