#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
# Lists the sections of CHANGELOG.md ("Unreleased" and the versions) whose notes have no Czech
# translation in CHANGELOG.cs.md (the section is missing or empty). With an argument (a version or
# "Unreleased"), checks only that section. Used by CI on pull requests and by the release workflow.
# Exit status: 0 = nothing missing, 1 = something missing (printed one version per line).
# Usage: scripts/changelog-cs-missing.sh [X.Y.Z|Unreleased]
set -eu
cd "$(dirname "$0")/.."
ONLY="${1:-}"
# "section<TAB>has notes" for every section of a changelog
sections() {
  awk '
    function flush() { if (v != "") print v "\t" (n ? 1 : 0) }
    /^## \[/ { flush(); v = $0; sub(/^## \[/, "", v); sub(/\].*/, "", v); n = 0; next }
    v != "" && NF { n = 1 }
    END { flush() }
  ' "$1"
}
[ -f CHANGELOG.cs.md ] || { echo "CHANGELOG.cs.md is missing" >&2; exit 1; }
CS="$(sections CHANGELOG.cs.md)"
MISSING=0
for LINE in $(sections CHANGELOG.md | tr '\t' ':'); do
  VERSION="${LINE%%:*}"
  NOTES="${LINE##*:}"
  [ -n "$ONLY" ] && [ "$VERSION" != "$ONLY" ] && continue
  [ "$NOTES" = 1 ] || continue
  if ! printf '%s\n' "$CS" | grep -qx "$VERSION	1"; then
    echo "$VERSION"
    MISSING=1
  fi
done
if [ -n "$ONLY" ] && ! sections CHANGELOG.md | grep -q "^$ONLY	"; then
  echo "CHANGELOG.md has no section for $ONLY" >&2
  exit 1
fi
exit "$MISSING"
