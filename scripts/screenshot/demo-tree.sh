#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
#
# Makes the made-up folder the screenshots show: a small website project and a Documents folder.
# Big files are sparse (they take no disk space); dates are a few days to months before today.
# Usage: scripts/screenshot/demo-tree.sh <folder that does not exist yet>
set -euo pipefail

ROOT=$1
[[ -e "$ROOT" ]] && { echo "$ROOT already exists" >&2; exit 1; }
mkdir -p "$ROOT"
touch "$ROOT/.axolotl-demo"

# file <path> <bytes> <days ago> <HHMM>
file() {
  mkdir -p "$(dirname "$ROOT/$1")"
  dd if=/dev/zero of="$ROOT/$1" bs=1 count=0 seek="$2" 2>/dev/null
  touch -t "$(date -v-"$3"d +%Y%m%d)$4" "$ROOT/$1"
}
# folder <path> <days ago> <HHMM>, after its contents
folder() {
  mkdir -p "$ROOT/$1"
  touch -t "$(date -v-"$2"d +%Y%m%d)$3" "$ROOT/$1"
}

W=Projects/website
file $W/assets/logo.svg 4210 14 1130
file $W/assets/hero.jpg 482113 14 1132
file $W/docs/deploy.md 3120 13 0915
file $W/src/main.js 18211 2 1744
file $W/app.js 43008 2 1744
file $W/deploy.sh 1024 23 1408
chmod +x "$ROOT/$W/deploy.sh"
file $W/favicon.ico 15360 216 0845
file $W/index.html 18432 39 0932
file $W/LICENSE 35149 284 0900
file $W/package.json 2048 15 1120
file $W/README.md 4096 13 0915
file $W/robots.txt 1024 216 0846
file $W/site-backup.zip 24117248 38 1830
file $W/sitemap.xml 6144 14 1702
file $W/styles.css 9216 31 1510
folder $W/assets 14 1130
folder $W/docs 13 0915
folder $W/src 2 1744
folder $W 2 1744

file Projects/mobile-app/App.swift 12288 6 1020
file Projects/mobile-app/Package.swift 1536 40 1610
folder Projects/mobile-app 6 1020
folder Projects 2 1744

D=Documents
file $D/Invoices/invoice-2026-09.pdf 182400 35 1200
folder $D/Invoices 35 1200
file $D/Recipes/pancakes.md 2210 35 1200
folder $D/Recipes 35 1200
file $D/Reports/q3-report.pdf 1834000 41 1200
folder $D/Reports 41 1200
file $D/Travel/itinerary.pdf 98200 41 1200
folder $D/Travel 41 1200
file $D/backup.sh 2048 164 0800
chmod +x "$ROOT/$D/backup.sh"
file $D/budget-2026.xlsx 389120 21 1948
file $D/checklist.txt 2048 10 1805
file $D/contract-draft.pdf 1228800 47 0930
file $D/floor-plan.png 2457600 91 1120
file $D/letter.pages 215040 34 0910
file $D/meeting-notes.md 6144 7 1015
file $D/photos-2025.tar.gz 671088640 271 1200
file $D/presentation.key 12582912 25 1622
folder $D 7 1015
