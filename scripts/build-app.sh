#!/usr/bin/env bash
# Builds Safespace.app into ./build. Usage: scripts/build-app.sh [--install]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Safespace.app"
VERSION="1.0.0"

# With only the Command Line Tools installed, the newest SDKs declare SwiftUI's @State as a
# macro whose plugin ships only with Xcode. If the default build fails, try older SDKs.
echo "→ Compiling (release)…"
if ! swift build -c release >"$ROOT/.build-log.txt" 2>&1; then
  built=0
  if [[ -z "${SDKROOT:-}" ]]; then
    for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk 2>/dev/null | sort -rV); do
      echo "  default SDK failed, trying $(basename "$sdk")…"
      if SDKROOT="$sdk" swift build -c release >"$ROOT/.build-log.txt" 2>&1; then
        export SDKROOT="$sdk"
        built=1
        break
      fi
    done
  fi
  if [[ $built == 0 ]]; then
    grep -E "error:" "$ROOT/.build-log.txt" | head -20
    echo "✗ Build failed (full log: .build-log.txt)"
    exit 1
  fi
fi
rm -f "$ROOT/.build-log.txt"
BIN="$(swift build -c release --show-bin-path)/Safespace"

echo "→ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Safespace"

echo "→ Rendering icon…"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/build/AppIcon-1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ROOT/build/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ROOT/build/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$ROOT/build/AppIcon-1024.png"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Safespace</string>
  <key>CFBundleDisplayName</key><string>Safespace</string>
  <key>CFBundleIdentifier</key><string>app.safespace.mac</string>
  <key>CFBundleExecutable</key><string>Safespace</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Open source · MIT License</string>
</dict>
</plist>
PLIST

echo "→ Signing (ad-hoc)…"
codesign --force --deep --options runtime --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "→ Installing to /Applications…"
  rm -rf "/Applications/Safespace.app"
  cp -R "$APP" /Applications/
  echo "✓ Installed /Applications/Safespace.app"
else
  echo "✓ Built $APP"
fi
