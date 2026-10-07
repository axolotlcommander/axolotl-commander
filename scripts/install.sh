#!/bin/sh
# Builds a release bundle, installs it to ~/Applications and puts an alias on the Desktop.
set -eu
cd "$(dirname "$0")/.."
scripts/bundle.sh release >/dev/null
DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -x iCommander 2>/dev/null || true
rm -rf "$DEST/iCommander.app"
cp -R build/iCommander.app "$DEST/"
touch "$DEST/iCommander.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/iCommander.app"
if [ ! -e "$HOME/Desktop/iCommander" ]; then
  osascript -e "tell application \"Finder\" to make alias file to POSIX file \"$DEST/iCommander.app\" at desktop" \
            -e 'tell application "Finder" to set name of result to "iCommander"' >/dev/null
fi
echo "Installed $DEST/iCommander.app"
