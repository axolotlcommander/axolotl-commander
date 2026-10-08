#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
# Builds Axolotl Commander.app into build/. Usage: scripts/bundle.sh [debug|release]
# Environment: VERSION (e.g. 0.2.0), BUILD_NUMBER, UNIVERSAL=1 (Apple silicon + Intel).
set -eu
CONFIG="${1:-debug}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
cd "$(dirname "$0")/.."
if [ "${UNIVERSAL:-0}" = 1 ]; then
  set -- --arch arm64 --arch x86_64
else
  set --
fi
swift build -c "$CONFIG" "$@"
BIN="$(swift build -c "$CONFIG" "$@" --show-bin-path)"
APP="build/Axolotl Commander.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AxolotlCommander" "$APP/Contents/MacOS/"
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
  <key>CFBundleName</key><string>Axolotl Commander</string>
  <key>CFBundleDisplayName</key><string>Axolotl Commander</string>
  <key>CFBundleIdentifier</key><string>cz.acidek.axolotlcommander</string>
  <key>CFBundleExecutable</key><string>AxolotlCommander</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 The Axolotl Commander Authors. GPL-3.0-or-later.</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>AxolotlCommander.CommanderApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>cs</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
