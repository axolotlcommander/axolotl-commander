# Tasks: Shortcut Conflict Checks

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Phase 1: Foundational (core)

- [ ] T001 `FixedKey` (menu items, macOS keys, panel movement keys), `SystemShortcut` with the macOS default
  list and `SystemShortcuts.current(from:)` (merge of the `AppleSymbolicHotKeys` dictionary), `KeyChord` from
  the system parameters, `ShortcutCheck.check` / `problem` / `reasons` in
  `Sources/CommanderCore/ShortcutCheck.swift`
- [ ] T002 [P] Unit tests in `Tests/CommanderCoreTests/ShortcutCheckTests.swift`: fixed keys per context,
  movement keys only in Panels (⌥↑ not refused), text-key rule for both settings (characters, ⇧ + character,
  ⌥ + character, Space / Return / Backspace / Tab / Esc not counted, other contexts not counted), macOS list
  merged with overrides (missing entries keep defaults, disabled, remapped, without key, malformed), conflict
  with commands and app-wide commands, User Menu items only in Panels, several reasons in one result, refusal
  wins, a chord the command already has is clean, no default chord of either scheme is refused

## Phase 2: User Stories 1, 2 and 4 — Refusals, text keys, explicit choice (P1)

- [ ] T003 [US1] [US2] [US4] Recorded chords go through `ShortcutCheck.check` in
  `Sources/AxolotlCommander/KeyboardSettings.swift`: refusal message, warnings with every reason, "Move to
  This Command" / "Assign Anyway" / "Cancel"; User Menu items from `UserMenuStore`; wording in
  `Sources/AxolotlCommander/ShortcutCheckText.swift`

## Phase 3: User Stories 3 and 5 — macOS shortcuts, recording hint (P2)

- [ ] T004 [US3] macOS list read on appear and on app activation; "Open Keyboard Settings" in the warning;
  warning marks with tooltips next to chords that cannot run; the two captions removed
- [ ] T005 [US5] Hint under the editor while recording

## Phase 4: User Story 6 — User Menu editor (P3)

- [ ] T006 [US6] `ShortcutCheck.reasons` added to the warnings in
  `Sources/AxolotlCommander/UserMenu/UserMenuSettings.swift`

## Phase 5: Polish

- [ ] T007 Czech strings in `Resources/Localizable.xcstrings`
- [ ] T008 `CHANGELOG.md` / `CHANGELOG.cs.md` under Unreleased
- [ ] T009 GUI check on the test copy only, Settings → Keyboard and User Menu, no file operations, System
  Settings never changed: ⌘W and ↓ refused; "q" with the typing setting on and off; ⌘D on Copy Files moves
  the chord; ⇧⌘4 warning if the key reaches the app; marks on ⌃↑ rows; recording hint
