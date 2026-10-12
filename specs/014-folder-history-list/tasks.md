# Tasks: Folder and Command History Lists

- [X] T001 Core: `FolderHistory` and `HistoryFilter` in `Sources/CommanderCore/HistoryList.swift`;
  `PanelModel.historyPlaces`.
- [X] T002 Core: `folderHistory` and `commandLineHistory` commands (chords per FR-011) and the Classic
  Commander change in `KeyScheme.swift`.
- [X] T003 [P] Tests in `Tests/CommanderCoreTests/HistoryListTests.swift`: order, marking, duplicates,
  recent paths, initial selection, filtering, chords. Build, test, commit.
- [ ] T004 [US1] UI: `HistoryListSheet` in `Sources/AxolotlCommander/HistoryListSheet.swift`; Folder
  History in `PanelViewController` with Return; `goTo(typed:)`; the direct ⌥ keys yield to bound chords.
- [ ] T005 [US2] UI: ⌘Return (new tab) and ⌥Return (the other panel) in `PanelViewController` /
  `MainWindowController`.
- [ ] T006 [US3] UI: Command Line History in `MainWindowController` and `CommandLineBar`, also while the
  line edits. Commit.
- [ ] T007 Czech strings, CHANGELOG, quickstart. Commit.
- [ ] T008 GUI check in the test copy (when the maintainer is away); install after asking.
