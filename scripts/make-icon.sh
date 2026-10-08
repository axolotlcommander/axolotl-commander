#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
#
# Regenerates Resources/AppIcon.icns and docs/images/icon.png from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swift scripts/make-icon.swift "$WORK/icon-1024.png"
SET="$WORK/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
mkdir -p docs/images
sips -z 256 256 "$WORK/icon-1024.png" --out docs/images/icon.png >/dev/null
echo "Resources/AppIcon.icns, docs/images/icon.png"
