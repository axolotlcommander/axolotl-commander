#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Axolotl Commander Authors
#
# One-time GitHub settings for the repository (run by a maintainer after the first push,
# with `gh auth login` done). Safe to run again: every call sets the same state.
#
#   scripts/github-setup.sh [owner/repo]
set -euo pipefail
REPO="${1:-axolotlcommander/axolotl-commander}"

echo "== Repository settings"
gh repo edit "$REPO" \
  --description "Keyboard-driven two-panel file manager for macOS, modeled on Tandem Commander / Open Salamander" \
  --homepage "https://github.com/$REPO" \
  --enable-issues --enable-discussions --enable-wiki=false --enable-projects=false \
  --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false \
  --delete-branch-on-merge --allow-update-branch \
  --add-topic macos --add-topic file-manager --add-topic swift --add-topic appkit \
  --add-topic orthodox-file-manager --add-topic two-panel --add-topic gpl-3

echo "== Private vulnerability reporting"
gh api -X PUT "repos/$REPO/private-vulnerability-reporting" >/dev/null

echo "== Dependabot security updates"
gh api -X PUT "repos/$REPO/vulnerability-alerts" >/dev/null
gh api -X PUT "repos/$REPO/automated-security-fixes" >/dev/null

echo "== Labels"
for label in "bug:d73a4a:Something does not work" \
             "enhancement:a2eeef:New feature or improvement" \
             "data-safety:b60205:Could lose or damage user data" \
             "good first issue:7057ff:Good for newcomers" \
             "help wanted:008672:Extra attention is needed" \
             "localization:fbca04:Translations and texts"; do
  IFS=: read -r name color desc <<<"$label"
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force >/dev/null
done

echo "== Branch protection for main"
# Every change goes through a pull request with one approving review (code owners) and green CI.
# enforce_admins=false: the maintainer can still merge their own PRs (GitHub does not let anyone
# approve their own PR), and fix things in an emergency.
gh api -X PUT "repos/$REPO/branches/main/protection" --input - >/dev/null <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["Build and test"] },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "require_code_owner_reviews": true,
    "dismiss_stale_reviews": true,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON

echo "Done: https://github.com/$REPO/settings"
