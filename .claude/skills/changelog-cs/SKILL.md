---
name: changelog-cs
description: Translate the new CHANGELOG.md entries into CHANGELOG.cs.md (Czech release notes). Use whenever CHANGELOG.md gets entries, before committing a pull request that changes it, and before a release tag.
---

# Czech release notes

`CHANGELOG.cs.md` is the Czech translation of `CHANGELOG.md`; the What's New and update windows show it
when the app runs in Czech, and the release workflow publishes it. Every pull request that adds entries to
`CHANGELOG.md` carries their translation (rule in `CLAUDE.md`, Versioning).

## Steps

1. Run `scripts/changelog-cs-missing.sh`. It prints the sections ("Unreleased" or a version) whose English
   notes have no Czech counterpart; nothing printed means nothing to do.
2. For each printed section, and for entries added to or changed in a section that already has a
   translation (compare with `git diff main -- CHANGELOG.md`), write the Czech text into the same section of
   `CHANGELOG.cs.md`:
   - Keep the section headings exactly as in English (`## [Unreleased]`, `## [X.Y.Z] - YYYY-MM-DD`); the
     scripts and the app match them. Subsections: Added → Přidáno, Changed → Změněno, Fixed → Opraveno,
     Removed → Odstraněno, Security → Bezpečnost.
   - Same items in the same order, same wrapping style (about 105 characters, continuation lines indented
     by two spaces).
   - Menu, command, dialog and setting names in the app's Czech wording: look them up in
     `Resources/Localizable.xcstrings` (`grep -n -A8 '"<English text>"' Resources/Localizable.xcstrings`).
     Settings tabs are "záložky" (záložka Panely).
   - Keys (⌘, ⌃, ⌥, ⇧, F5…), code in backticks, file names and URLs unchanged. Correct Czech with all
     diacritics; never name Total Commander.
3. Run `scripts/changelog-cs-missing.sh` again; it must print nothing and exit 0.
4. Commit both changelogs together with the change they describe.
