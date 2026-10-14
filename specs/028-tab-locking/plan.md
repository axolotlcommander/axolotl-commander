# Implementation Plan: Tab Locking and Tab Menu

**Branch**: `028-tab-locking` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (`Sources/CommanderCore/Window/`, unit tested):
  - `PanelState.swift`: a new optional `lock: TabLock?` (mode, locked folder, cursor item at locking),
    encoded with the tab and decoded with `decodeIfPresent` (old layouts load unlocked) (R1).
  - `TabLock.swift` (NEW): `TabLock` and its modes; `returning(_:)` builds the state a tab locked with folder
    changes allowed shows when it becomes active again (R3).
  - `TabList.swift`: `updateCurrent` keeps the tab's lock (the panel model knows nothing about locks);
    `setLock(_:at:)`; `split(keeping:opened:)` for a folder change in a locked tab (the locked tab gets its
    old state back, the new state is inserted after it and activated) (R2); `returnCurrentToLock()` and
    `returnAllToLocks()` (R3); `closeOthers(keeping:)` and `closeToTheRight(of:)` that keep locked tabs and
    return what they closed (R4); `duplicate(at:)` → an unlocked copy after the tab (R5);
    `unlock(where:)` and `redirect` dropping locks for ejected volumes (R6); `relock(at:to:)` for a locked
    folder that no longer exists (R7).
- **UI** (`Sources/AxolotlCommander/`):
  - `PanelTabs.swift`: the split in `tabsChanged()` — the one place every folder change of the panel passes
    through (R2); the return on activation in `switchTab`, `closeTab` and reopen (R3); the menu actions
    (duplicate, copy to the other panel, lock modes, close to the right) and the fallback for a missing
    locked folder (R7); the lock mark in the tab list.
  - `TabStrip.swift`: `show(_ items:active:canReopen:)` with title, lock mode and tooltip per tab; the left
    slot shows the close button while the pointer is over a tab (any tab), otherwise the lock on a locked
    tab, otherwise the close button on the active tab (clarification 2026-10-14) (R8); the fuller context
    menu acting on the tab under the pointer.
  - `PanelViewController.swift`: `canPerform` / `perform` for the new commands; `leave(volume:)` unlocks
    the tabs on the volume before moving them home (R6). `ServerConnectionsUI.swift`: the same for a
    disconnected server.
  - `MainWindowController.swift`: checkmarks for the two lock commands (`validateMenuItem`); Copy Tab to
    Other Panel opens the copy in the other panel; the window layout returns tabs to their locks at start.
  - `Command.swift`: `duplicateTab`, `copyTabToOtherPanel`, `closeTabsToRight`, `lockTab`,
    `lockTabAllowingChanges` in the Go menu next to the tab commands, no default keys.
- Czech strings; `CHANGELOG.md` and `CHANGELOG.cs.md` entries under 0.6.0.

## Technical Context

- Swift 6.2, AppKit, Swift Testing; macOS 15+. No new dependencies.
- **Storage**: the lock is part of the tab in the saved window layout (`window.layout`); nothing new in
  Settings or its export.
- **Performance**: the split and the return are in-memory list changes; no extra disk access except the
  existing folder load of the new tab.
- **Constraints**: the panel model stays unaware of locks; every navigation path keeps working unchanged
  and the tab list reacts to the result (R2).

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ No file operations; GUI check only browses a scratchpad folder on the test copy. |
| II Reference | ✅ The reference has the tab menu items (New, Duplicate, Close, Close Other, Close to the Right); locking is a recorded addition following the usual two-panel managers, agreed with the maintainer. |
| III Native macOS | ✅ SF Symbol lock, hover close like Safari tabs, menu checkmarks, String Catalog. |
| IV Testable core | ✅ All tab list rules (split, return, keep-locked closing, duplicate, unlock, relock, decoding) in the core with unit tests. |
| V Clean-room / GPL | ✅ Behavior from the help and public descriptions of other managers; no code read. |
| VI Incremental | ✅ Core → lock + split → return → strip marks → menu → persistence details, each committed. |
| VII Language | ✅ English code and docs, Czech UI strings and changelog. |

## Project Structure

```text
specs/028-tab-locking/{plan,research,data-model,quickstart}.md

Sources/CommanderCore/Window/TabLock.swift        NEW
Sources/CommanderCore/Window/PanelState.swift     lock field
Sources/CommanderCore/Window/TabList.swift        lock rules
Tests/CommanderCoreTests/TabLockTests.swift       NEW
Sources/AxolotlCommander/PanelTabs.swift          split, return, menu actions
Sources/AxolotlCommander/TabStrip.swift           items, left slot, menu
Sources/AxolotlCommander/PanelViewController.swift commands, eject unlock
Sources/AxolotlCommander/ServerConnectionsUI.swift disconnect unlock
Sources/AxolotlCommander/MainWindowController.swift checkmarks, other panel, layout load
Sources/CommanderCore/Command.swift               new commands
Resources/Localizable.xcstrings                   Czech strings
```

## Complexity Tracking

None.
