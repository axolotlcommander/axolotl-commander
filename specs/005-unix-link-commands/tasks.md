# Tasks: Link Commands, Go to Link Target and Change Attributes

**Input**: Design documents from `/specs/005-unix-link-commands/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/link-commands.md,
quickstart.md

**Tests**: Unit tests for the core (paths, creation, batches, retarget, resolution, chords) are
part of the plan (constitution IV). GUI checks follow quickstart.md in the test copy only, in a
scratch folder.

**Format**: `[ID] [P?] [Story] Description` — [P] = can run in parallel (different files).

## Phase 1: Setup

- [X] T001 Add the commands `newSymbolicLink`, `newHardLink`, `editSymbolicLink`,
  `pasteAsSymbolicLink`, `goToLinkTarget` and `changeAttributes` to `Command`. Register them in
  `CommandRegistry` at the contract positions and with the contract chords:
  - ⌃⌘L for New Symbolic Link…;
  - ⌃F2 for Change Attributes…;
  - ⌃⌘V and ⌃S for Paste as Symbolic Link;
  - ⌃T for Go to Link Target;
  - none for New Hard Link… and Edit Symbolic Link….

  File: Sources/CommanderCore/Command.swift
- [X] T002 [P] Add toolbar symbols for the six commands. None of them goes into the default set.
  File: Sources/AxolotlCommander/MainToolbar.swift

## Phase 2: Foundational (core, blocks all stories)

- [X] T003 Write the core types and functions in
  Sources/CommanderCore/Operations/LinkOperations.swift:
  - `LinkKind`, `LinkError`, `LinkOutcome`;
  - `LinkPaths`: `relativePath`, `storedTarget` (a typed relative path is kept as typed, `~`
    expanded), `isRelative`, `absolute`;
  - `FileOperations.makeSymbolicLink(at:storing:)`: `NameCheck`, the `DirectoryLookup`
    pre-check, then `symlink(2)`; `EEXIST` maps to `alreadyExists` and `ENOENT` to
    `path(.notFound)`;
  - `makeHardLink(at:to:)`: `lstat`; only `S_IFREG`; `st_dev` must match; then `link(2)`;
    `EXDEV` maps to `differentVolume`;
  - `makeLinks(_:to:in:relative:)`: never stops early;
  - `retargetSymbolicLink(_:storing:)`: a temporary hidden link, then `renamex_np` with
    `RENAME_SWAP`. The old item must be a symlink, otherwise swap back. The fallback is an
    `lstat` check plus `rename`. The temporary link is always cleaned up;
  - `LinkTarget.resolve` (up to 32 steps, symlinks and aliases, missing target or loop) and
    `LinkTarget.isLink`.
- [X] T004 [P] Write tests in Tests/CommanderCoreTests/LinkTests.swift, all in temporary folders:
  - relative paths: sibling, deeper, upward, the same folder, `/`;
  - stored target: typed relative, absolute with and without relative, `~`;
  - symbolic link: created and dangling; a conflict (including a case-only difference) leaves the
    existing item byte-identical; invalid name; missing folder;
  - hard link: file (same inode, `nlink` 2), folder, symlink, conflict;
  - batch: mixed outcomes, created links still present;
  - retarget: target changed, both targets untouched, a regular file refused and left intact, no
    temporary link left behind;
  - resolve: a chain of 3, a relative link, a link to a folder, a Finder alias (bookmark file),
    a missing target with its stored text, a loop.
- [X] T005 [P] Test that the new default chords are unique and that ⌃S, ⌃T, ⌃F2, ⌃⌘L and ⌃⌘V
  map to the new commands. File: Tests/CommanderCoreTests/KeyMapTests.swift

**Checkpoint**: `swift test` green; core API usable from the UI.

## Phase 3: User Story 1 — Create a symbolic link (P1) 🎯 MVP part 1

**Goal**: ⌃⌘L creates links in the other panel's folder, never over an existing name.

**Independent Test**: quickstart Q1–Q5.

- [X] T006 [US1] Build `LinkSheet` in Sources/AxolotlCommander/LinkSheet.swift as a SwiftUI view
  with three modes (symbolic, hard, edit) and two layouts (one item, several items):
  - fields Target, Link name or Destination folder, and Relative path (UserDefaults
    `links.relativePath`);
  - an inline message line;
  - Return confirms, Escape cancels, fields are labelled.

  Add `LinkSheet.present(...)` hosting it as a window sheet. The confirm handler throws and
  keeps the sheet open on inline errors.
- [X] T007 [US1] Wire the panel in Sources/AxolotlCommander/PanelViewController.swift:
  - add the new commands to `handled`, `diskOnly` and `needTargets`, and refuse them for search
    results;
  - for `newSymbolicLink`: prefill from the other panel (or the active folder when the other
    panel is not a local folder) and resolve a typed path with `PathInput`;
  - ask before creating a link to a missing target (`OperationsController.present`);
  - create the link off the main thread, refresh both panels and focus the new link;
  - for several items, show one summary alert of the skipped ones.
- [X] T008 [US1] Add `describe` texts for the `LinkError` cases in
  Sources/AxolotlCommander/OperationsController.swift

**Checkpoint**: commit.

## Phase 4: User Story 2 — Go to a link's target (P1)

**Independent Test**: quickstart Q6–Q9.

- [X] T009 [US2] Implement `goToLinkTarget` in Sources/AxolotlCommander/PanelViewController.swift:
  - enabled when the cursor item is a symlink or `LinkTarget.isLink`;
  - resolve off the main thread;
  - a folder target uses `go(to:)`, a file target uses `go(to: parent, focusing: name)`;
  - errors go to `report`.

## Phase 5: User Story 3 — Paste as symbolic links (P1) 🎯 MVP complete

**Independent Test**: quickstart Q10.

- [X] T010 [US3] Implement `pasteAsSymbolicLink` in
  Sources/AxolotlCommander/PanelViewController.swift:
  - enabled when the pasteboard has file URLs and the panel shows a local folder;
  - `makeLinks(.symbolic, …, relative: false)` into `model.location`;
  - refresh, put the cursor on the first created link, and show a summary of the skipped ones.
- [X] T011 [US3] Add entries to the context menu in
  Sources/AxolotlCommander/PanelContextMenu.swift:
  - the item menu gets New Symbolic Link…, New Hard Link…, Edit Symbolic Link… (only on a
    symlink), Go to Link Target (only on a link) and Change Attributes…;
  - the folder menu gets Paste as Symbolic Link.

**Checkpoint**: US1–US3 = P1 complete; commit.

## Phase 6: User Story 4 — Change attributes directly (P2)

**Independent Test**: quickstart Q11.

- [X] T012 [US4] Create `AttributesSheet.show(_:in:onChange:)` in
  Sources/AxolotlCommander/AttributesSheet.swift with a header, `AttributesEditView`, and
  Cancel/Apply. Share `PropertiesSheet.apply` (make it internal) in
  Sources/AxolotlCommander/PropertiesView.swift. Wire `changeAttributes` in
  PanelViewController.swift.

## Phase 7: User Story 5 — Create a hard link (P2)

**Independent Test**: quickstart Q12–Q13.

- [X] T013 [US5] Wire `newHardLink` with `LinkSheet` in hard mode: a read-only target and no
  Relative path. Errors appear inline for one item and in the summary for several. File:
  Sources/AxolotlCommander/PanelViewController.swift

## Phase 8: User Story 6 — Edit a symbolic link (P3)

**Independent Test**: quickstart Q14.

- [X] T014 [US6] Wire `editSymbolicLink` with `LinkSheet` in edit mode in
  Sources/AxolotlCommander/PanelViewController.swift:
  - show the stored target, read with `destinationOfSymbolicLink`;
  - the Relative path toggle converts the target through `LinkPaths`;
  - ask before using a missing target;
  - call `retargetSymbolicLink`, then refresh and keep the cursor on the link.

## Phase 9: Polish

- [X] T015 [P] Add en + cs texts for every new string (contract table and the sheet labels) in
  Resources/Localizable.xcstrings
- [X] T016 [P] Update README.md (feature list) and CHANGELOG.md (Unreleased)
- [X] T017 Build without warnings, run `swift test`, then run the GUI checks Q1–Q17 in the test
  copy. Record the results in the table below.
- [X] T018 Set the spec status to Implemented and record any deviation found during
  implementation in spec.md Clarifications.

## Dependencies

- T001 comes before T005–T014.
- T003 comes before T004 and T006–T014.
- T006 comes before T007, T013 and T014.
- US1, US2, US3 and US4 are independent after Phase 2; US5 and US6 reuse the sheet from US1.

## GUI verification

| # | Result | Note |
|---|---|---|
| Q1 | Pass | ⌃⌘L + Return: absolute link in the other panel, cursor on it |
| Q2 | Pass | `rel.txt -> ../a/file.txt`; "Relative path" remembered |
| Q3 | Pass | Inline "already exists", sheet stays, existing link unchanged |
| Q4 | Pass | Three items: `dir`, `other.txt` created, `file.txt` skipped, one summary |
| Q5 | Pass | Question for a missing target; Cancel returns to the sheet, Create makes the dangling link |
| Q6 | Pass | ⌃T on a file link: target folder, cursor on the file; ⌘[ returns |
| Q7 | Pass | Folder link opens the real folder |
| Q8 | Pass | Chain of three links reaches the file |
| Q9 | Pass | Broken link: message names `../a/missing`, panel stays |
| Q10 | Pass | ⌘C + ⌃⌘V: two absolute links; ⌃S again: both skipped, one summary |
| Q11 | Pass | ⌃F2 + owner Execute + Return: `-rwxr--r--`; ⌃F2 + change + Esc: unchanged |
| Q12 | Pass | Hard link `hard.txt`: same inode, link count 2 |
| Q13 | Pass | Hard link to a folder: inline "Folders cannot have hard links", nothing created |
| Q14 | Pass | Edit: checkbox converts relative ↔ absolute; retarget to `../a/other.txt`, both files unchanged, no temporary link left |
| Q15 | Pass | Disabled on ".." / ordinary file (edit, go to target) / inside a ZIP; clipboard with text only not checked (the user's clipboard was not touched again) |
| Q16 | Pass | Keyboard Shortcuts lists the commands with ⌃⌘L, ⌃⌘V ⌃S, ⌃T; toolbar items not checked in Customize Toolbar |
| Q17 | Pass | Scratch folder after each step: only the expected links and the Q11 mode change |

Found and fixed during the GUI check: the sheet's text fields did not use the sheet's width.
