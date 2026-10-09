#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
# Builds Axolotl Commander.app into build/. Usage: scripts/bundle.sh [debug|release]
# Environment: VERSION (default: the VERSION file), BUILD_NUMBER, UNIVERSAL=1 (Apple silicon + Intel),
# SIGN_IDENTITY (code signing identity; see the end of this script).
set -eu
CONFIG="${1:-debug}"
VERSION="${VERSION:-$(cat "$(dirname "$0")/../VERSION")}"
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
cp LICENSE NOTICE AUTHORS THIRD_PARTY.md THIRD_PARTY_LICENSES.txt "$APP/Contents/Resources/"
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
# String Catalogs -> en.lproj / cs.lproj (Localizable.strings[dict], InfoPlist.strings); strings load
# from Bundle.main, InfoPlist.strings localizes the Info.plist texts below (folder access prompts)
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
xcrun xcstringstool compile Resources/InfoPlist.xcstrings --output-directory "$APP/Contents/Resources"
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
  <!-- Folder access prompts: the same English texts as Resources/InfoPlist.xcstrings (translations there) -->
  <key>NSDesktopFolderUsageDescription</key><string>Axolotl Commander shows and manages the files on your Desktop when you open it in a panel.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Axolotl Commander shows and manages the files in Documents when you open the folder in a panel.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Axolotl Commander shows and manages the files in Downloads when you open the folder in a panel.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Axolotl Commander shows and manages the files on external disks when you open them in a panel.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Axolotl Commander shows and manages the files on network volumes when you open them in a panel.</string>
  <key>NSLocalNetworkUsageDescription</key><string>Axolotl Commander finds file servers on your local network to list them in the Network folder.</string>
  <key>NSBonjourServices</key><array><string>_smb._tcp</string><string>_afpovertcp._tcp</string><string>_sftp-ssh._tcp</string></array>
  <key>NSFileProviderDomainUsageDescription</key><string>Axolotl Commander shows and manages the files of cloud storage (such as iCloud Drive) when you open it in a panel.</string>
</dict></plist>
PLIST
# Signing. macOS remembers granted folder access (Downloads, Documents, disks…) per signature: an
# ad-hoc signature changes with every build, so access would be asked for again after each one.
# SIGN_IDENTITY wins; otherwise a local build uses the first "Apple Development" identity in the
# keychain (any free Apple ID in Xcode has one); without one it falls back to ad hoc. CI signs
# releases itself (.github/workflows/release.yml).
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && [ "${CI:-}" != true ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/"Apple Development: / { print $2; exit }')"
fi
if [ -n "$IDENTITY" ] && codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1; then
  :
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi
echo "$APP"
