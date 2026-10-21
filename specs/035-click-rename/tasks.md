# Tasks: Rename by Clicking the Name

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Phase 1: Foundational (core)

- [ ] T001 `ClickRename` (`Press`, `arms`, `Pending.fires`, `selection(of:)`) in
  `Sources/CommanderCore/ClickRename.swift`; `PanelBehavior.clickToRename` (`panel.clickToRename`, default
  true) in `Sources/CommanderCore/PanelBehavior.swift`; catalog entry in
  `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`
- [ ] T002 [P] Unit tests in `Tests/CommanderCoreTests/ClickRenameTests.swift`: arms only for a single plain
  click on the name text of the cursor item in an active panel with the setting on and Rename available,
  never on "..", icon, other zones, modifiers, click count 2, inactive panel, another item, setting off;
  fires only with the same cursor, same item, same scroll origin, active panel, no editing; preselection
  range for a file with an extension, without one, a dot file, a folder, a package

## Phase 2: User Story 1 — A slow click renames (P1)

- [ ] T003 [US1] `MouseHit.onText`, "was active" read before focusing, candidate on press, wait on release,
  event monitor and timer in `Sources/AxolotlCommander/PanelMouseTracking.swift`,
  `Sources/AxolotlCommander/PanelViewController.swift` (table) and `Sources/AxolotlCommander/PanelGridView.swift`

## Phase 3: User Story 2 — In-place editing in Brief and Thumbnails (P1)

- [ ] T004 [US2] Overlay rename field for the grid views in `Sources/AxolotlCommander/GridRename.swift`;
  `.rename` uses `beginRename()` in every view; ending removes the overlay; `askRename` removed
  (`Sources/AxolotlCommander/PanelViewController.swift`); `ThumbnailCellView.nameTextContains` and Brief
  text hit in `Sources/AxolotlCommander/ThumbnailView.swift`, `Sources/AxolotlCommander/BriefView.swift`

## Phase 4: User Story 3 — The setting (P2)

- [ ] T005 [US3] Checkbox in Settings → Panels in `Sources/AxolotlCommander/SettingsView.swift`

## Phase 5: Polish

- [ ] T006 Czech strings in `Resources/Localizable.xcstrings`; CHANGELOG.md + CHANGELOG.cs.md entries under
  0.10.0
- [ ] T007 Build without warnings, `swift test` green
- [ ] T008 GUI check on the test copy (`cz.acidek.axolotlcommander.gtest`) in a scratchpad test directory
  with dummy files only: slow click in Detailed, Brief, Thumbnails; double click opens; icon click and
  inactive panel click do not rename; F2 in Brief/Thumbnails in place; Esc; setting off
