#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
# Raises the version in VERSION and moves the "Unreleased" items of CHANGELOG.md (and of its Czech
# translation CHANGELOG.cs.md) under it.
# Usage: scripts/bump-version.sh major|minor|patch   (see "Versioning" in CLAUDE.md)
set -eu
cd "$(dirname "$0")/.."
OLD="$(cat VERSION)"
case "$OLD" in
  *[!0-9.]* | *..* | .* | *.) echo "VERSION does not look like X.Y.Z: $OLD" >&2; exit 1 ;;
esac
IFS=. read -r MAJOR MINOR PATCH <<END
$OLD
END
case "${1:-}" in
  major) NEW="$((MAJOR + 1)).0.0" ;;
  minor) NEW="$MAJOR.$((MINOR + 1)).0" ;;
  patch) NEW="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  *) echo "Usage: $0 major|minor|patch" >&2; exit 2 ;;
esac
# The Unreleased section must hold something to release.
if ! awk '/^## \[Unreleased\]/ { on = 1; next } /^## \[/ { on = 0 } on && NF { found = 1 } END { exit !found }' CHANGELOG.md; then
  echo "CHANGELOG.md has nothing under [Unreleased]." >&2
  exit 1
fi
# ...and its Czech translation too (CLAUDE.md, Versioning).
if [ -f CHANGELOG.cs.md ] && ! scripts/changelog-cs-missing.sh Unreleased >/dev/null; then
  echo "CHANGELOG.cs.md has no Czech notes under [Unreleased]; translate them first (skill changelog-cs)." >&2
  exit 1
fi
DATE="$(date +%Y-%m-%d)"
# The Czech translation (CHANGELOG.cs.md) gets the same heading.
for FILE in CHANGELOG.md CHANGELOG.cs.md; do
  [ -f "$FILE" ] || continue
  awk -v new="$NEW" -v date="$DATE" '
    /^## \[Unreleased\]/ && !done { print; print ""; print "## [" new "] - " date; done = 1; next }
    { print }
  ' "$FILE" > "$FILE.tmp"
  mv "$FILE.tmp" "$FILE"
done
echo "$NEW" > VERSION
echo "$OLD -> $NEW"
