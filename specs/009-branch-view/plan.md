# Implementation Plan: Branch View

**Branch**: `009-branch-view` | **Date**: 2026-10-10 | **Spec**: [spec.md](spec.md)

## Summary

⌃B shows every file of the panel's folder and its subfolders in one flat list. "Branch View of
Selected Items" does the same for the marked items.

The core gets two pieces:
- `BranchListing`, a value next to the results listing;
- `BranchScanner`, which walks the tree through the panel's `FileSource`. That one source covers
  local folders, archives and servers. The walk can be cancelled and reports its progress.

The items keep their path relative to the branch folder as their name, so selection, rename and
delete stay exact among duplicate names. The UI shows only the file name.

The panel view controller:
- runs the scan with progress in the status line, and Esc cancels it;
- marks the path bar and the tab;
- disables the commands that create items.

Archive operations group their sources by folder. See [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6.2, strict concurrency.

**Primary Dependencies**:
- Foundation in the core: `FileSource`, `ArchiveCatalog`, `RemoteConnections`, all existing;
- AppKit in the UI;
- no new packages.

**Storage**: none. The branch state lives in memory only, like the results listing.

**Testing**: Swift Testing:
- `BranchScannerTests`, on a temporary folder and with an in-memory `FileSource`;
- `PanelModelBranchTests`;
- a sorting test.

The GUI check follows [quickstart.md](quickstart.md) and runs in the test copy.

**Target Platform**: macOS 15+.

**Project Type**: desktop app (SwiftPM: the `CommanderCore` library and the `AxolotlCommander`
app).

**Performance Goals**:
- 100 000 local files within 30 s (SC-002);
- Esc within 1 s (SC-003);
- progress at least once a second.

**Constraints**:
- the scan runs off the main actor;
- no file is changed by the scan;
- tests touch only folders they create.

**Scale/Scope**:
- core: 1 new file (`Branch.swift`), changes in `PanelModel`, `PanelState`, `Sorting` and `Command`;
- UI: `PanelViewController`, `PathBar`/`Breadcrumbs`, tab title, `ArchiveOperations`, menu
  validation;
- about 10 strings;
- 2 new test files.

## Constitution Check

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | The scan only reads. Operations act on the item's real URL, and duplicates are safe because the relative path is the identity. Tests create and remove their own folders. The GUI check runs in the scratchpad, in the test copy. |
| II Reference behavior | ✅ | Tandem Commander has no branch view; Total Commander's behavior is followed and recorded in the spec Context. |
| III Native macOS | ✅ | Menu commands with validation, ⌃B without a conflict, the status line progress pattern already in the app. |
| IV Testable core | ✅ | The scanner and the model logic are core code with an injected `FileSource`. |
| V Clean-room, GPL | ✅ | No reference sources, SPDX headers, no new dependencies. |
| VI Incremental | ✅ | US1 + US2 (local, with progress and Esc) first, then US3 (marked items), then US4 (archives, servers). |
| VII Language | ✅ | English in git; Czech only in `Localizable.xcstrings`. |

Re-check after design: no violations.

## Project Structure

### Documentation

```text
specs/009-branch-view/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md
├── contracts/commands-ui.md
├── checklists/requirements.md
└── tasks.md                    # /speckit-tasks
```

### Source code

```text
Sources/CommanderCore/Branch.swift               # NEW: BranchListing, BranchProgress, BranchResult, BranchScanner
Sources/CommanderCore/PanelModel.swift           # branch state, showBranch, load/refresh, quick search
Sources/CommanderCore/Window/PanelState.swift    # branch in Place and PanelState (in memory)
Sources/CommanderCore/Sorting.swift              # byFileName
Sources/CommanderCore/Command.swift              # branchView (⌃B), branchViewSelected
Sources/AxolotlCommander/PanelViewController.swift  # scan task, progress, Esc, names, validation, no watching
Sources/AxolotlCommander/PathBar.swift (+ Breadcrumbs in core)  # "Branch" segment, path field text
Sources/AxolotlCommander/PanelTabs.swift / TabStrip.swift       # tab title
Sources/AxolotlCommander/BriefView.swift          # file names
Sources/AxolotlCommander/ArchiveOperations.swift  # sources grouped by folder, rename in own folder
Resources/Localizable.xcstrings                   # en + cs
Tests/CommanderCoreTests/BranchScannerTests.swift      # NEW
Tests/CommanderCoreTests/PanelModelBranchTests.swift   # NEW
CHANGELOG.md                                      # in the 0.3.0 section, together with spec 008
```

**Structure Decision**: the existing layout. The branch types live in one core file next to
`ResultsListing`.

## Delivery order

1. **Core**:
   - `Branch.swift` with tests;
   - `sortItems(byFileName:)`;
   - the `PanelModel` and `PanelState` changes with tests;
   - the `Command` cases.
   Commit.
2. **US1 + US2, local**:
   - the ⌃B toggle;
   - the scan task with progress and Esc;
   - names in the Name, Ext and Brief views;
   - the status line;
   - the path bar and tab mark;
   - command validation;
   - no watching;
   - a rescan after operations and on ⌘R.
   Commit.
3. **US3**: Branch View of Selected Items. Commit.
4. **US4**:
   - archive and server branches, checked;
   - archive operations grouped by folder;
   - rename in the item's folder.
   Commit.
5. **Polish**:
   - localization;
   - the GUI check;
   - the CHANGELOG entry, in 0.3.0 with spec 008 (research.md R9).
   Commit.

## Complexity Tracking

No violations.
