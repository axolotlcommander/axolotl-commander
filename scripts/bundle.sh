#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The iCommander Authors
# Builds iCommander.app into build/. Usage: scripts/bundle.sh [debug|release]
set -eu
CONFIG="${1:-debug}"
cd "$(dirname "$0")/.."
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/iCommander.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/iCommander" "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns Resources/Credits.html "$APP/Contents/Resources/"
# GPL: the license and notices travel with every copy of the program
cp LICENSE NOTICE AUTHORS THIRD_PARTY.md "$APP/Contents/Resources/"
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
# String Catalog -> en.lproj / cs.lproj (Localizable.strings[dict]); strings load from Bundle.main
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources/en.lproj"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>iCommander</string>
  <key>CFBundleDisplayName</key><string>iCommander</string>
  <key>CFBundleIdentifier</key><string>cz.acidek.icommander</string>
  <key>CFBundleExecutable</key><string>iCommander</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 The iCommander Authors. GPL-3.0-or-later.</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>iCommander.CommanderApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>cs</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
