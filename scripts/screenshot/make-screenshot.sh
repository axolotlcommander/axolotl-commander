#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
#
# Takes the screenshots of the README and the website, one per language, of the app in its
# default settings (plus the button bar) over a made-up folder. See scripts/screenshot/README.md.
#
# Usage: scripts/screenshot/make-screenshot.sh [--no-build] [en cs ...]
# Output: docs/images/screenshot.png (English) and docs/images/screenshot-<lang>.png (others).
set -euo pipefail
cd "$(dirname "$0")/../.."

BUILD=1
if [[ "${1:-}" == "--no-build" ]]; then BUILD=0; shift; fi
LANGS=("$@")
[[ ${#LANGS[@]} -gt 0 ]] || LANGS=(en cs)

DEMO="/Users/Shared/Demo"
BUNDLE_ID="cz.acidek.axolotlcommander.screenshot"
WIDTH=1320
HEIGHT=660
# The real path: the running app reports /private/var/..., not /var/....
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/axolotl-screenshot.XXXXXX")" && pwd -P)"
APP="$WORK/Axolotl Screenshot.app"
DRIVE="$WORK/drive"
PID=""

[[ -e "$DEMO" ]] && { echo "$DEMO already exists; move it away first (this script never touches it)" >&2; exit 1; }

cleanup() {
  pkill -f "$APP/Contents/MacOS/" 2>/dev/null || true
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  # Only the folder this script made: it carries the marker.
  [[ -f "$DEMO/.axolotl-demo" ]] && rm -rf "$DEMO"
  rm -rf "$WORK"
}
trap cleanup EXIT

# A copy of the app with its own bundle id, so it starts with default settings and never
# touches the settings of an installed copy.
if [[ $BUILD == 1 ]]; then scripts/bundle.sh release >/dev/null; fi
cp -R "build/Axolotl Commander.app" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force -s - "$APP" >/dev/null 2>&1
swiftc -O -o "$DRIVE" scripts/screenshot/drive.swift 2>/dev/null || { echo "drive.swift does not compile" >&2; exit 1; }

scripts/screenshot/demo-tree.sh "$DEMO"

shoot() {
  local lang=$1 locale=$2 out=$3
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  defaults write "$BUNDLE_ID" panel.left.path "$DEMO/Projects"
  defaults write "$BUNDLE_ID" panel.right.path "$DEMO/Documents"
  # The button bar with its sample buttons, which is off by default.
  defaults write "$BUNDLE_ID" buttonBar.placement top
  open -n "$APP" --args -AppleLanguages "($lang)" -AppleLocale "$locale" -NSRequiresAquaSystemAppearance YES
  for _ in $(seq 50); do
    PID=$(pgrep -f "$APP/Contents/MacOS/" | head -1 || true)
    [[ -n "$PID" ]] && break
    sleep 0.2
  done
  [[ -n "$PID" ]] || { echo "the app did not start" >&2; exit 1; }
  "$DRIVE" wait "$PID"
  "$DRIVE" frame "$PID" $WIDTH $HEIGHT
  sleep 3  # the first start of a new copy takes longer to list both panels
  # Left panel: open "website" from Projects in a new tab, mark three files, rest on README.
  #   Projects:  ..  mobile-app  website
  #   website:   ..  assets docs src  app.js deploy.sh favicon.ico index.html LICENSE
  #              package.json README.md robots.txt site-backup.zip sitemap.xml styles.css
  "$DRIVE" keys "$PID" 'down*2' opt+cmd+down
  sleep 1.5  # the new tab lists the folder
  "$DRIVE" keys "$PID" 'down*4' space 'down*2' space 'down*6' space 'up*4'
  sleep 1.5
  "$DRIVE" wait "$PID"
  screencapture -x -l"$("$DRIVE" window "$PID")" "$out"
  kill "$PID"
  wait "$PID" 2>/dev/null || true
  PID=""
  sleep 1
  echo "$out: $(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixel/ { printf "%s ", $2 }')"
}

for lang in "${LANGS[@]}"; do
  case $lang in
    en) shoot en en_US docs/images/screenshot.png ;;
    cs) shoot cs cs_CZ docs/images/screenshot-cs.png ;;
    *) echo "no locale for $lang; add it to the case in this script" >&2; exit 1 ;;
  esac
done
