# Tasks: Panel and Bar Fonts

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md), [data-model.md](data-model.md)

## Phase 1: Foundational (core)

- [ ] T001 Add `FontChoice` and `FontRole` (file list 13 pt, 8–32; bars 11 pt, 8–20; `clamped`, `bigger`,
  `smaller`, `isDefault`, `rowHeight(lineHeight:padding:)` never below 18) in
  `Sources/CommanderCore/Window/PanelFonts.swift`
- [ ] T002 Add `listFont` / `barFont` (`FontChoice?`, nil = default, missing keys decode as nil) to
  `PanelAppearance` in `Sources/CommanderCore/Window/Highlighting.swift`
- [ ] T003 Unit tests: round trip, clamping, steps at the limits, default detection, row height, old settings
  decode in `Tests/CommanderCoreTests/PanelFontsTests.swift`

## Phase 2: User Story 1 — File list font (P1)

- [ ] T004 [US1] `PanelFont` resolver (list / bar, regular / bold / monospaced, missing font → system font,
  cached, row height, display text) in `Sources/AxolotlCommander/PanelFontsUI.swift`
- [ ] T005 [US1] Detailed list: `textFont(marked:)` and the row height follow the list font; refresh on
  `.appearanceChanged` keeping the cursor row visible in `Sources/AxolotlCommander/PanelTabs.swift`,
  `Sources/AxolotlCommander/PanelViewController.swift`
- [ ] T006 [US1] Brief view item height and column width, thumbnail labels in
  `Sources/AxolotlCommander/BriefView.swift`, `Sources/AxolotlCommander/ThumbnailView.swift`
- [ ] T007 [US1] Find results and branch listings use the list font (wherever they show panel rows)
- [ ] T008 [US1] `FontChooser` (Fonts panel target, live `changeFont(_:)`, clamping) and the "Fonts" section
  (File list row: font text, Change…, Default) in `Sources/AxolotlCommander/SettingsView.swift`; closing
  Settings clears the target in `Sources/AxolotlCommander/AppDelegate.swift`

## Phase 3: User Story 2 — Bar font (P1)

- [ ] T009 [US2] Volume bar, drive row and free space, tab strip, path bar and path field (monospaced), status
  line follow the bar font; heights from the font; content never widens a panel
- [ ] T010 [US2] "Bars" row in the Fonts section

## Phase 4: User Story 3 — Back to the defaults (P1)

- [ ] T011 [US3] "Restore Default Fonts" button; Default buttons disabled at the default

## Phase 5: User Story 4 — Keyboard (P2)

- [ ] T012 [US4] Commands `fileListFontBigger`, `fileListFontSmaller`, `fileListFontDefault` (View menu, no
  keys) in `Sources/CommanderCore/Command.swift`, handling and enablement in the window controller

## Phase 6: Polish

- [ ] T013 Czech strings in `Resources/Localizable.xcstrings`
- [ ] T014 `CHANGELOG.md` / `CHANGELOG.cs.md`, version 0.8.0 (`scripts/bump-version.sh minor`)
- [ ] T015 GUI check per [quickstart.md](quickstart.md) on the test copy only

## Dependencies

T001–T003 first; US1 before US2 (shares `PanelFont` and the Settings section); US3 and US4 after US1/US2.
