#!/usr/bin/env bash
# Packs build/Safespace.app into build/Safespace.dmg with a drag-to-Applications layout.
# Run scripts/build-app.sh first. Usage: scripts/make-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Safespace.app"
DMG="build/Safespace.dmg"
[[ -d "$APP" ]] || { echo "✗ $APP not found, run scripts/build-app.sh first"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Safespace" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "✓ Built $DMG"
