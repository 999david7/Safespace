# Security

Safespace stores passwords, so the threat model matters more than the feature list.

## Reporting a vulnerability

Please report security issues privately through GitHub: open the repository's **Security** tab and
choose **Report a vulnerability**. Please don't open a public issue for anything exploitable.

Include what you did, what happened, and the affected version or commit. Expect a first reply within
a week.

## How the vault is protected

| Layer | Choice |
| --- | --- |
| Encryption | AES-256-GCM (CryptoKit), fresh random nonce on every save |
| Key derivation | PBKDF2-HMAC-SHA256, 600,000 rounds, 32-byte random salt |
| Integrity | GCM tag; the file header (version, KDF, iterations, salt) is authenticated as associated data |
| File | `~/Library/Application Support/Safespace/vault.safespace`, mode `0600`, written atomically, previous version kept as `.bak` |
| Touch ID | Vault key sealed to a Secure Enclave P-256 key created with `.biometryCurrentSet`; unsealed via ECDH → HKDF-SHA256 → AES-GCM after a fingerprint match |
| Clipboard | Copies are marked `org.nspasteboard.ConcealedType` and cleared on a timer, on lock, and on quit |
| Network | None. The app makes no network requests and has no sync or telemetry |

Everything inside the ciphertext is encrypted, including titles, usernames, URLs and notes. A wrong
master password or a modified file fails GCM authentication and is rejected; the two cases are
indistinguishable by design.

## What this does not protect against

- **A compromised Mac.** While the vault is unlocked, the key and decrypted entries live in process
  memory. Swift strings can't be reliably wiped, so memory scraping by malware or another process
  with debug rights defeats the app.
- **A forgotten master password.** There is no recovery and no backdoor.
- **Keyloggers, screen capture and clipboard readers** running as your user.
- **Weak master passwords.** 600,000 PBKDF2 rounds slow an attacker down; they don't rescue a short
  or common password.
- **Backups you make yourself.** The vault file stays encrypted wherever you copy it, but keep it
  somewhere you trust.

## Releases

Builds are signed ad-hoc, not notarized, so Gatekeeper asks on first launch. If you don't want to
trust a downloaded binary, build from source — it's one script.
