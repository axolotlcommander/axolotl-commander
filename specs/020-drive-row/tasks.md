# Tasks: Drive Row with Free Space

- [X] T001 Core: settings, placement rule, disk space text in `Sources/CommanderCore/Window/DriveRow.swift`;
  `toggleDriveRow`, `toggleVolumeBar` in `Sources/CommanderCore/Command.swift`; the preferences in
  `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`.
- [X] T002 [P] Tests in `Tests/CommanderCoreTests/DriveRowTests.swift`.
- [X] T003 [US1] [US2] UI: `DiskSpaceReader`, `FreeSpaceLabel`, `DriveRowView` in
  `Sources/AxolotlCommander/DriveRowView.swift`; the panel stack, disk of the location and refresh in
  `Sources/AxolotlCommander/PanelViewController.swift`; the volume menu from the combo with a check mark.
- [X] T004 [US3] UI: the free space in `Sources/AxolotlCommander/VolumeBar.swift` and the status row; the
  volume bar optional; View commands in `Sources/AxolotlCommander/MainWindowController.swift`; Settings →
  Appearance in `Sources/AxolotlCommander/SettingsView.swift`.
- [X] T005 Czech strings, CHANGELOG, quickstart. Build, test, commit.
- [X] T006 GUI check in the test copy (reading only). Done in the background (2026-10-13): the row in
  both panels, the space at the right end of the volume bar and of the status line, shortening in a
  narrow window. In front (2026-10-13): the combo opens the volume menu with the current volume
  checked, a click on the space opens Volume Info, and View → Show Drive Row / Show Volume Bar move
  the space to the volume bar and the status line and are checked when shown.
- [X] T007 Install for the maintainer, after asking (with release 0.4.0).
