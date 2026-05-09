#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/.build/OBSBOT Remote.app"

cd "$REPO_ROOT"
swift build --product obsbot-remote-menu --configuration "$CONFIGURATION"

BIN_DIR="$(swift build --show-bin-path --configuration "$CONFIGURATION")"
EXECUTABLE="$BIN_DIR/obsbot-remote-menu"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/OBSBOT Remote"
cp "$REPO_ROOT/Resources/remote-button-capture.json" "$APP_DIR/Contents/Resources/remote-button-capture.json"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>OBSBOT Remote</string>
  <key>CFBundleIdentifier</key>
  <string>com.jcdoll.obsbotremote</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>OBSBOT Remote</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR" >/dev/null
echo "$APP_DIR"
