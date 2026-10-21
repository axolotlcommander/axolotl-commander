# Tasks: Tab Reordering and a Prominent Tab Look

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Phase 1: Foundational (core)

- [X] T001 `TabList.canMove(_:by:)` in `Sources/CommanderCore/Window/TabList.swift`; `Command.moveTabLeft`,
  `Command.moveTabRight` in `Sources/CommanderCore/Command.swift`; `TabLook` and `PanelBehavior.tabLook`
  (`panel.tabLook`, default `standard`) in `Sources/CommanderCore/PanelBehavior.swift`; catalog entry in
  `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`
- [X] T002 [P] Unit tests in `Tests/CommanderCoreTests/TabReorderTests.swift`: `move` keeps the active tab
  (moving the active one, moving another across it, to the ends, out-of-range targets clamp), `canMove` at
  the ends and with one tab, the commands have no keys in either scheme and belong to the Go menu, the tab
  look defaults to Standard and reads Prominent

## Phase 2: User Story 1 — Reorder by dragging (P1)

- [X] T003 [US1] Drag tracking, snapshot, placeholder, Esc and `onMove` in
  `Sources/AxolotlCommander/TabStrip.swift`; `moveTab(at:to:)` in `Sources/AxolotlCommander/PanelTabs.swift`

## Phase 3: User Story 2 — Move commands (P2)

- [X] T004 [US2] Commands handled and enabled in `Sources/AxolotlCommander/PanelViewController.swift`;
  context menu items in `Sources/AxolotlCommander/TabStrip.swift`

## Phase 4: User Story 3 — Prominent look (P2)

- [X] T005 [US3] Look in `Sources/AxolotlCommander/TabStrip.swift`, active panel state from
  `Sources/AxolotlCommander/PanelViewController.swift`; "Tab look:" in
  `Sources/AxolotlCommander/SettingsView.swift`

## Phase 5: Polish

- [X] T006 Czech strings in `Resources/Localizable.xcstrings`; CHANGELOG.md + CHANGELOG.cs.md entries under
  0.10.0
- [X] T007 Build without warnings, `swift test` green
- [X] T008 GUI check on the test copy (`cz.acidek.axolotlcommander.gtest`), no file operations: drag a tab,
  Esc cancels, release over the other panel, click still switches, order after restart, Move Tab Left /
  Right from the context menu, Prominent look in both panels (active/inactive), light and dark (dark left to
  the maintainer: the test copy cannot switch its appearance without changing System Settings; the look uses
  system colors only)
