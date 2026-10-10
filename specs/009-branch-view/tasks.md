---

description: "Task list for Branch View"
---

# Tasks: Branch View

**Input**: Design documents from `specs/009-branch-view/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/commands-ui.md](contracts/commands-ui.md)

**Tests**: requested by the spec (core unit tests). The GUI check follows
[quickstart.md](quickstart.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: the user story the task belongs to

## Phase 1: Setup

No setup: the existing SwiftPM layout, no new dependencies.

## Phase 2: Foundational (core)

- [ ] T001 [P] Create `Sources/CommanderCore/Branch.swift` (SPDX header) per data-model.md:
  - `BranchListing` (`root`, `starts: [URL]?`, `title`);
  - `BranchProgress`, `BranchResult`;
  - `BranchScanner.scan(_:source:includeHidden:progress:)`, iterative depth first, by the research.md R3
    rules: files only, packages are files, symlinked folders not entered, subfolder errors counted in
    `unreadable`, a root error rethrown, `Task.checkCancellation()` per folder, progress at most every
    100 ms and after the last folder.
  - Each item's `name` is the path relative to `root`; `url` is unchanged.
- [ ] T002 [P] Create `Tests/CommanderCoreTests/BranchScannerTests.swift` on a temporary folder the test
  creates and removes. It covers:
  - files only, relative names, duplicate names;
  - hidden files with and without `includeHidden`;
  - a link to a folder (`loop -> .`), not entered;
  - a package, listed as a file;
  - an unreadable folder (chmod 000, restored in `defer`), counted;
  - cancellation;
  - progress, called at least once with the final count;
  - marked starts (a file and a folder);
  - an in-memory `FileSource` with `sftp://` and archive-like URLs, for US4.
- [ ] T003 `sortItems(_:by:rules:directorySizes:byFileName:)` in `Sources/CommanderCore/Sorting.swift`:
  - when `byFileName` is set, the name order compares `url.lastPathComponent`, then `name`;
  - add a test to the existing sorting tests.
- [ ] T004 `PanelModel` in `Sources/CommanderCore/PanelModel.swift`:
  - `branch: BranchListing?`, `unreadableFolders`, `onBranchProgress`;
  - `showBranch(_:focusing:)`;
  - `load(_:results:branch:includeHidden:)` scans a branch through `BranchScanner` with `source` and
    `showHidden`;
  - `navigate`, `refresh`, `snapshot`, `restore`, the history `Place`, `buildItems` (`byFileName`
    when `branch != nil`) and quick search `matches` (the file name in branch view);
  - `goParent` keeps its normal behavior.
- [ ] T005 `PanelState` and `PanelState.Place` in `Sources/CommanderCore/Window/PanelState.swift`:
  `branch: BranchListing?`, in memory only (not in `CodingKeys`).
- [ ] T006 [P] Create `Tests/CommanderCoreTests/PanelModelBranchTests.swift`. It covers:
  - `showBranch` lists the files;
  - going back to the folder with the cursor on a direct file;
  - `goParent` goes to the parent;
  - sorting by name uses the file name;
  - quick search uses the file name;
  - `refresh` rescans;
  - `showHidden` changes rescan;
  - `PanelState` encoding has no branch;
  - `restore` with a branch rescans.
- [ ] T007 `Command` in `Sources/CommanderCore/Command.swift`:
  - `.branchView`, "Branch View (With Subfolders)", ⌃B, View menu after "Show Hidden Files";
  - `.branchViewSelected`, "Branch View of Selected Items", no chord.
  Check the chord uniqueness tests. `swift test` is green. Commit.

## Phase 3: User Stories 1 + 2 - Branch view of the folder, responsive (P1) 🎯 MVP

- [ ] T008 [US1] The ⌃B toggle in `Sources/AxolotlCommander/PanelViewController.swift` (command
  dispatch):
  - in a normal listing it starts the scan of `BranchListing(root: location)`;
  - in branch view it calls `go(to: location, focusing:)` with the cursor's file name when the file
    is directly in the folder.
- [ ] T009 [US2] Scan task and progress, like `sizeTask`/`sizingProgress`:
  - `branchTask` and `branchProgress`, shown first in `updateStatus()`;
  - Esc with no quick search cancels the task. The first scan leaves the panel as it was; a cancelled
    rescan goes to the folder's normal listing.
  - `model.onBranchProgress` updates the text ("Reading the branch: N files — folder — Esc stops").
  - The panel's busy state follows the scan.
- [ ] T010 [US1] Names: in the Name and Ext cells, and in `Sources/AxolotlCommander/BriefView.swift`,
  show `url.lastPathComponent` (base name and extension) when `model.branch != nil`. The in-place
  rename (F2) uses the file name, like the results listing (lines that use `model.results == nil ?
  item.name : item.url.lastPathComponent`).
- [ ] T011 [US1] Status line: the item line already shows `item.name`, which is the relative path. The
  totals line adds "— N folders could not be read" when `unreadableFolders > 0`.
- [ ] T012 [US1] Path bar and titles:
  - `Breadcrumbs.trail(..., branch:)` in `Sources/CommanderCore/Window/Breadcrumbs.swift` appends a
    non-clickable `.branch` segment ("Branch");
  - `PathBar` draws it like `.results`;
  - `locationText` gives "<folder> — Branch";
  - the window title in `MainWindowController` and the tab title get "(Branch)";
  - `trailSource` includes the branch.
- [ ] T013 [US1] Validation (FR-009, FR-015):
  - the create and link commands at `PanelViewController` ~line 533 are disabled when
    `model.branch != nil`;
  - `branchView` is disabled in the Network folder and in a results listing;
  - drag destination rules (`PanelDragDrop`) and the context menu treat branch view like the results
    listing for dropping into the folder;
  - `PanelLinkCommands` and the `ArchiveOperations` target folder use the branch root.
- [ ] T014 [US1] Watching and refresh: `watchLocation` does not watch in branch view; ⌘R and the
  refresh after operations rescan (through `model.refresh()` with progress); switching tabs rescans.
- [ ] T015 [US1] Build without warnings, `swift test` green. Commit.

## Phase 4: User Story 3 - Branch view of the marked items (P2)

- [ ] T016 [US3] `branchViewSelected`: the starts are the marked items, or the cursor item when
  nothing is marked. It is disabled on "..", in the Network folder and in a results listing. Commit.

## Phase 5: User Story 4 - Archives and servers (P2)

- [ ] T017 [US4] Archive operations in `Sources/AxolotlCommander/ArchiveOperations.swift`:
  - `transferArchive` (extract out, add) groups the sources by their own folder and runs per group;
  - `deleteInArchive` and rename use each item's own `ArchivePath`.
  Add a core helper `groupedByFolder(_ urls: [URL]) -> [(folder: URL, names: [String])]` with a test.
- [ ] T018 [US4] Check the server branch: progress, Esc, F5 download and F8 from many folders. Fix
  what breaks; if servers turn out to be a real problem, tell the maintainer (they allowed dropping
  servers). Commit.

## Phase 6: Polish

- [ ] T019 [P] Czech translations in `Resources/Localizable.xcstrings`: the command names, "Branch",
  the progress text, the unreadable-folders text.
- [ ] T020 [P] CHANGELOG "Unreleased" → "Added": branch view.
- [ ] T021 GUI check from quickstart.md in the test copy, on a scratchpad test tree only.
- [ ] T022 After 008 is merged: rebase on `main`, `scripts/bump-version.sh minor`, then PR, merge, tag
  and install (when the maintainer says).

## Dependencies

- T001 → T002, T004; T003 → T004; T004 + T005 → T006; T007 is independent.
- Phase 2 → Phase 3 → Phases 4 and 5 (independent) → Phase 6.

## Implementation Strategy

MVP = Phases 2 + 3: ⌃B on local folders with progress and Esc. Then the marked-items variant, then
archives and servers.
