# Tasks: Basic Commands

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Phase 1: Foundational (core)

- [ ] T001 `CutSet` (items, change count, `contains`, `isActive`, `remaining(exists:)`, `pasteAction`) in
  `Sources/CommanderCore/Operations/CutSet.swift`
- [ ] T002 `DuplicateName` and `StandardFolder` in `Sources/CommanderCore/Operations/DuplicateName.swift`
- [ ] T003 Commands `cutFiles` (⌘X, ⌃X), `duplicate` (⌘D), `goDesktop` (⇧⌘D), `goDocuments` (⇧⌘O),
  `goDownloads` (⌥⌘L), `goApplications`; tab keys ⌘T, ⇧⌘], ⇧⌘[ in `Sources/CommanderCore/Command.swift` and
  `Sources/CommanderCore/KeyScheme.swift`
- [ ] T004 [P] Unit tests in `Tests/CommanderCoreTests/CutSetTests.swift` and
  `Tests/CommanderCoreTests/DuplicateNameTests.swift` (paste decision, remaining items, names in English and
  Czech, extensions, dot files, folders, taken names, long names, folder targets, new chords without
  collisions in the panel scope, classic scheme keeps its keys)

## Phase 2: User Story 1 — Cut and paste (P1)

- [ ] T005 [US1] `CutClipboard` (pasteboard write, polling, `.cutSetChanged`) in
  `Sources/AxolotlCommander/CutClipboard.swift`; `cut(_:)` in `MainWindowController.swift`; `cut:` selector in
  `MainMenuBuilder.swift`
- [ ] T006 [US1] Cut Files and the paste decision in `Sources/AxolotlCommander/PanelViewController.swift`;
  `onFinish` in `Sources/AxolotlCommander/OperationsController.swift`
- [ ] T007 [US1] Dimmed cut items in the detailed, brief and thumbnail views (`PanelTabs.swift`,
  `PanelViewController.swift`, `BriefView.swift`, `ThumbnailView.swift`)

## Phase 3: User Story 2 — Tab keys (P1)

- [ ] T008 [US2] Verify the new tab keys reach the commands (menu key equivalents) and appear in Settings →
  Keyboard

## Phase 4: User Story 3 — Duplicate (P2)

- [ ] T009 [US3] `OperationsController.duplicate(_:panel:)` and the panel command (enabled only in disk
  folders, beep on "..")

## Phase 5: User Story 4 — Standard folders (P2)

- [ ] T010 [US4] Desktop, Documents, Downloads, Applications through `go(to:)` in
  `Sources/AxolotlCommander/PanelViewController.swift`

## Phase 6: Polish

- [ ] T011 Czech strings in `Resources/Localizable.xcstrings`
- [ ] T012 `CHANGELOG.md` / `CHANGELOG.cs.md` under Unreleased
- [ ] T013 GUI check on the test copy only (scratchpad folders): cut → dim → paste moves → dimming ends;
  same-folder paste beeps; Copy after Cut ends the dimming; Duplicate names and cursor; ⌘T, ⇧⌘], ⇧⌘[;
  ⇧⌘D / ⇧⌘O / ⌥⌘L browse only
