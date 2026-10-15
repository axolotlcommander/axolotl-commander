# Tasks: Find Results Like the Classic Commander

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Phase 1: Foundational (core)

- [X] T001 `FindWindowBehavior` (key `find.afterGoToFile`, default `hide`) and `FindGoToTarget` in
  `Sources/CommanderCore/Search/FindResultActions.swift`; add the preference to
  `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`
- [X] T002 Unit tests (default, stored values, file / folder / missing item / missing folder targets) in
  `Tests/CommanderCoreTests/FindResultActionsTests.swift`
- [X] T003 Commands: `findNewSearch` (⌘N), `findInNewWindow` (no keys), "Go to File" takes Return / keypad
  Enter, "Results to Panel" title, in `Sources/CommanderCore/Command.swift`

## Phase 2: User Story 1 — Go to the file (P1)

- [X] T004 [US1] Double click and Return run Go to File; folder → parent with cursor on it; missing item →
  beep; missing folder → message; main window front, panel focused, in
  `Sources/AxolotlCommander/Find/FindWindowController.swift`

## Phase 3: User Story 2 — Buttons (P1)

- [X] T005 [US2] Button row (F3 View, F4 Edit, New Search, Go to File, Results to Panel; Find stays the default button), never
  focused, enabled with the commands, fits at the minimum width

## Phase 4: User Story 3 — New search (P1)

- [X] T006 [US3] New Search clears and focuses the name field (`FindForm`, `FindFormView`)

## Phase 5: User Story 4 — Step aside (P1)

- [X] T007 [US4] Hide after Go to File / Results to Panel / Esc; Find Files brings the hidden window back;
  one hidden window; Keep open = today
- [X] T008 [US4] Settings → General "After going to a file:" in `Sources/AxolotlCommander/SettingsView.swift`

## Phase 6: User Story 5 — New window (P2)

- [X] T009 [US5] "Find Files in New Window…" next to Find Files, routed like `.find`

## Phase 7: Polish

- [X] T010 Czech strings in `Resources/Localizable.xcstrings`
- [X] T011 `CHANGELOG.md` / `CHANGELOG.cs.md` under 0.8.0
- [X] T012 GUI check on the test copy only (scratchpad folders)

## Dependencies

T001–T003 first; US1 → US2 (buttons call the same commands) → US3 → US4 → US5.
