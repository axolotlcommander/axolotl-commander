# Implementation Plan: Folder and Command History Lists

**Branch**: `014-folder-history-list` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core**:
  - `FolderHistory.entries(back:current:forward:recent:display:)` builds the list per FR-002 (time
    order, the current folder marked, duplicates kept where closest to the current folder, recent
    paths last) and `FolderHistory.initialSelection(in:)` per FR-003;
  - `HistoryFilter.matches(_:query:)`: every space-separated word must appear, ignoring case and
    diacritics (FR-004);
  - `PanelModel.historyPlaces` exposes the Back and Forward places read-only.
- **Commands**: `folderHistory` (Go, after Forward, ⌃⌘H) and `commandLineHistory` (Commands, ⌥F8).
  Classic Commander gives `folderHistory` ⌃⌘H and ⌥↓.
- **UI**:
  - `HistoryListSheet`: a sheet with a search field, a one-column table and a hint line. The search
    field keeps the focus; ↑ ↓ Page Up/Down Home End move the table selection; Return, ⌘Return and
    ⌥Return report the chosen entry with how to open it; Esc closes.
  - `PanelViewController`: the Folder History list and the three ways to open (here; new tab via
    `stateForNewTab` + `openTab`; the other panel through the window controller); a typed recent path
    goes the Go to Folder way (`goTo(typed:)`, factored out of `pathFieldCommitted`).
  - `handleMovement`: the direct ⌥ keys yield to a chord bound in the panel key map.
  - `MainWindowController` + `CommandLineBar`: the Command Line History list, `entries` and
    `setLine(_:)`; ⌥F8 also while the line edits.

## Technical Context

- Swift 6.2, AppKit, Swift Testing. Nothing new is stored.
- Tests (`HistoryListTests`): list order, marking, duplicates, recent paths, initial selection,
  filtering (words, case, diacritics), chords in both schemes.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ The lists only navigate or fill the command line; nothing runs or changes files. |
| II Reference | ✅ Classic folder and command history lists; deviations listed. |
| III Native macOS | ✅ A sheet with a search field, ⌘/⌥ Return as modifiers. |
| IV Testable core | ✅ Building and filtering in the core. |
| V Clean-room | ✅ |
| VI Incremental | ✅ Core, folder list, then the command line list. |
| VII Language | ✅ |

## Source code

```text
Sources/CommanderCore/HistoryList.swift              # NEW: FolderHistory, HistoryFilter
Sources/CommanderCore/PanelModel.swift               # historyPlaces
Sources/CommanderCore/Command.swift                  # folderHistory, commandLineHistory
Sources/CommanderCore/KeyScheme.swift                # Classic ⌥↓
Sources/AxolotlCommander/HistoryListSheet.swift      # NEW: the list sheet
Sources/AxolotlCommander/PanelViewController.swift   # folder list, goTo(typed:), ⌥ keys yield
Sources/AxolotlCommander/MainWindowController.swift  # command line list, other panel opening
Sources/AxolotlCommander/CommandLineBar.swift        # entries, setLine
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/HistoryListTests.swift      # NEW
```

## Complexity Tracking

None.
