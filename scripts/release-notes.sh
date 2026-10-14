#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
# Prints the release description of a version: its section of CHANGELOG.md, then "## Česky" and
# its section of CHANGELOG.cs.md (spec 027, R8). Fails when either changelog has no notes for it.
# Usage: scripts/release-notes.sh X.Y.Z
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release-notes.sh X.Y.Z}"
# The lines of one version's section, without its heading and the blank lines around it
section() {
  awk -v v="$VERSION" '
    /^## \[/ { inside = index($0, "## [" v "]") == 1; next }
    inside { lines[++n] = $0 }
    END {
      first = 1; while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
      last = n; while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = first; i <= last; i++) print lines[i]
    }
  ' "$1"
}
EN="$(section CHANGELOG.md)"
CS="$(section CHANGELOG.cs.md)"
[ -n "$EN" ] || { echo "CHANGELOG.md has no notes for $VERSION" >&2; exit 1; }
[ -n "$CS" ] || { echo "CHANGELOG.cs.md has no notes for $VERSION" >&2; exit 1; }
printf '%s\n\n## Česky\n\n%s\n' "$EN" "$CS"
