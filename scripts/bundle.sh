#!/bin/bash
# Build Melete.app from the Swift package. Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/Melete.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Melete" "$APP/Contents/MacOS/Melete"
# SwiftPM resource bundles (if any) go to Contents/Resources.
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.melete.Melete</string>
  <key>CFBundleName</key><string>Melete</string>
  <key>CFBundleDisplayName</key><string>Melete</string>
  <key>CFBundleExecutable</key><string>Melete</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>GPL-3.0</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP ($CONFIG)"
