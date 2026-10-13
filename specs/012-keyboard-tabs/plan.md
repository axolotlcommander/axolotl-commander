# Implementation Plan: Tabs from the Keyboard

**Branch**: `012-keyboard-tabs` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

Seven panel commands on top of the existing tab machinery (`TabList`, `PanelTabs.swift`, `TabStrip`):

- **New tab target**: the core `PanelModel.stateEnteringCursor()` builds the new tab's state with a
  scratch `PanelModel`:
  1. restore this panel's snapshot;
  2. call `enterCursor()`;
  3. take the snapshot.
  Files and packages give the current state with the item under the cursor. The visible panel never
  moves, so the background and other-panel variants are the same state inserted elsewhere.
- **Tab list operations**: `TabList.open(_:activate:)` inserts after the current tab. A core
  `ClosedTabs` (at most 10, newest first) records every closed tab.
- **Closing tabs**: `PanelViewController.closeTab` / `closeOtherTabs` record the tabs they close.
  `reopenClosedTab` pops the newest one.
- **Tab List…**: an `NSMenu` popped up over the panel's path bar, the same way the hot paths menu is
  shown. It lists open tabs (the active one checked) and recently closed tabs.
- **Swap with All Tabs**: `MainWindowController` exchanges the two panels' `TabList`s and restores each
  current tab.
- **Commands**: seven new commands with chords in `CommandRegistry`, plus a Classic Commander change (⌃⇧W
  → Close Other Tabs).

## Technical Context

- **Stack**: Swift 6.2, AppKit, Swift Testing.
- **Storage**: none new. Closed tabs are kept in memory.
- **Testing**:
  - `TabListTests`: `open(activate:)`, `ClosedTabs` and its limit;
  - `PanelModelTests`: `stateEnteringCursor` on temp folders for a folder, a file, "..", an archive and
    a package;
  - `KeySchemeTests` / `HabitChordTests`: the new chords and the scheme change, with no duplicate
    chords.
- **Constraints**: the GUI check is done in the test copy on scratchpad folders.

## Constitution Check

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | Only navigation and tab state; no file operations. |
| II Reference behavior | ✅ | The scope follows the classic tab commands; deviations are listed in the spec. |
| III Native macOS | ✅ | Browser-style chords (⌘⇧T, ⌥⌘W, ⌘⇧\) are added next to the classic ones. |
| IV Testable core | ✅ | Tab list operations, closed tabs and the new tab state are core code with tests. |
| V Clean-room, GPL | ✅ | No reference sources, SPDX headers. |
| VI Incremental | ✅ | US1, then US2, then US3, each committed green. |
| VII Language | ✅ | English in git, Czech in xcstrings. |

## Source code

```text
Sources/CommanderCore/Window/TabList.swift        # open(_:activate:), ClosedTabs
Sources/CommanderCore/PanelModel.swift            # stateEnteringCursor()
Sources/CommanderCore/Command.swift               # 7 commands, chords, menus
Sources/CommanderCore/KeyScheme.swift             # Classic: ⌃⇧W → Close Other Tabs, Close Tab ⌃W
Sources/AxolotlCommander/PanelTabs.swift          # open in tab, closed tabs, reopen, tab list menu
Sources/AxolotlCommander/PanelViewController.swift  # perform / canPerform for the panel commands
Sources/AxolotlCommander/MainWindowController.swift # other panel tab, swap with all tabs
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/…                        # tests above
CHANGELOG.md
```

## Delivery order

1. Core: TabList, ClosedTabs, `stateEnteringCursor`, commands and the scheme; tests. Commit.
2. US1: the open-in-tab commands (UI). Commit.
3. US2: closed tabs, Reopen Closed Tab, Tab List…. Commit.
4. US3: Close Other Tabs (command) and Swap Panels with All Tabs. Commit.
5. Polish: strings, CHANGELOG, GUI check, install.

## Complexity Tracking

None.
