#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
# Builds a release bundle, installs it to ~/Applications and puts an alias on the Desktop.
set -eu
cd "$(dirname "$0")/.."
scripts/bundle.sh release >/dev/null
DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x AxolotlCommander 2>/dev/null || true
rm -rf "$DEST/Axolotl Commander.app"
cp -R "build/Axolotl Commander.app" "$DEST/"
touch "$DEST/Axolotl Commander.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/Axolotl Commander.app"
if [ ! -e "$HOME/Desktop/Axolotl Commander" ]; then
  osascript -e "tell application \"Finder\" to make alias file to POSIX file \"$DEST/Axolotl Commander.app\" at desktop" \
            -e 'tell application "Finder" to set name of result to "Axolotl Commander"' >/dev/null
fi
echo "Installed $DEST/Axolotl Commander.app"
