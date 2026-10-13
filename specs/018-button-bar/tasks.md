# Tasks: Button Bar

- [X] T001 Core: model, store, icons, symbols, layout in `Sources/CommanderCore/Window/ButtonBar.swift`;
  `CommandSymbols` shared with `Sources/AxolotlCommander/MainToolbar.swift`.
- [X] T002 Core: settings export (`buttonBar` section, preferences) in
  `Sources/CommanderCore/Settings/SettingsArchive.swift` and `AppSettingsCatalog.swift`; `toggleButtonBar`
  in `Sources/CommanderCore/Command.swift`.
- [X] T003 [P] Tests in `Tests/CommanderCoreTests/ButtonBarTests.swift`; the compatibility test lists the
  new section as added after the fixture.
- [X] T004 [US1] [US3] UI: `ButtonBarView`, `BottomRowView` in `Sources/AxolotlCommander/ButtonBarView.swift`;
  window integration in `Sources/AxolotlCommander/MainWindowController.swift`.
- [X] T005 [US2] UI: Settings tab in `Sources/AxolotlCommander/ButtonBarSettings.swift`.
- [X] T006 [US4] UI: the bar's context menu.
- [X] T007 Czech strings, CHANGELOG, quickstart. Build, test, commit.
- [X] T008 GUI check in the test copy (2026-10-13, in the background without focus: top and bottom
  placement, live icon change, the » overflow in a narrow window, a program button run by AX press,
  the Settings tab and the icon picker; then in front: View → Show Button Bar, right click → Remove
  Button and Edit Button…, a command button (Hot Paths) keeping the focus in the panel, the » menu).
- [ ] T009 Install for the maintainer, after asking (with release 0.4.0).
