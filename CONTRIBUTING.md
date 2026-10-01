# Contributing

Thanks for taking a look. Issues and pull requests are welcome.

## Getting started

```bash
git clone https://github.com/<owner>/Safespace-for-Mac.git
cd Safespace-for-Mac
swift build      # build
swift test       # run the core test suite
swift run        # run the app against your real vault
```

To work on the interface without touching your own vault, launch a demo screen with sample data in a
temporary directory (debug builds only):

```bash
SAFESPACE_DEMO=vault swift run     # also: stage, generator, editor, locked, setup
```

## Ground rules

- **`SafespaceCore` stays UI-free.** Crypto, storage, generator and strength estimation live there
  and are covered by tests. Add a test with any change to that target.
- **Don't weaken the crypto defaults** (AES-256-GCM, PBKDF2 rounds, salt/nonce handling) in a PR
  that's about something else. Security changes should stand alone and explain the reasoning.
- **No network calls, no telemetry, no analytics.** Offline is a feature.
- **Match the existing style:** monochrome surfaces, hairline rules, square corners, tracked
  uppercase labels, yellow and red as the only accents. Shared pieces live in
  `Sources/Safespace/Views/Components.swift` and `Controls.swift`.
- Keep comments to what the code can't say itself.

## Pull requests

Describe what changed and why, and include a screenshot for interface changes. Make sure
`swift build` and `swift test` pass first. If you have only the Command Line Tools installed, see the
SDK note in the README.
