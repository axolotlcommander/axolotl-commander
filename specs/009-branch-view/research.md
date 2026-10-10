# Research: Branch View

## R1 — Its own panel state, next to the results listing

**Decision**: `PanelModel` gets `branch: BranchListing?`, next to `results: ResultsListing?`. Branch
view is not a kind of `ResultsListing`.

**Rationale**: the results listing (Find results) assumes local files. Its `load()` reads local
resource values, and the model drops archive and server awareness while it is shown
(`archive = results == nil ? …`, `remote = results == nil ? …`). Branch view must keep both: it works
in archives and on servers (FR-014), and command availability follows the location. A separate
property keeps `archive` and `remote` derived from the location as in a normal listing.

**Consequence**: every `model.results` check in the UI (26 places, mostly `PanelViewController`) is
reviewed once.
- Checks meaning "the panel has no single folder to create items in" also apply to the branch:
  F7, new file, paste, links, attributes (FR-009).
- Checks meaning "Find results: show relative paths, go back to the root on .." do not apply.

**Alternatives considered**:
- `ResultsListing` with a `kind` enum: rejected. The local-only assumptions spread through `archive`,
  `remote` and the operations.

## R2 — Item names: the relative path is the identity

**Decision**: branch items are `FileItem`s whose `name` is the path relative to the branch folder
("docs/deep/d.txt"), as in the results listing. The UI shows only `url.lastPathComponent` in the Name
and Ext columns and in the Brief view (FR-003).

**Rationale**: the model keys selection, cursor restore and `directorySizes` by
`rules.key(item.name)`. A unique name makes duplicates from different subfolders safe to mark,
rename and delete (SC-005) without new identity code. The status line already prints `item.name`,
which is exactly the relative path FR-004 asks for.

Two places must use the displayed name instead:
- **Sorting by name**: compare the file names first, then the relative paths as a tie-break, so
  equal names stay in a fixed order. `sortItems` gets a `byFileName: Bool` flag.
- **Quick search**: match the file name, not the path.

## R3 — One scanner for local folders, archives and servers

**Decision**: a core `BranchScanner` walks the tree through the panel's `FileSource`. It is
iterative and depth first. For every folder it calls `source.list(_:includeHidden:)`.

**Rationale**: `LocalFileSource.list` already lists local folders, folders inside archives (from
`ArchiveCatalog`) and server folders (through `RemoteConnections`). One walk therefore covers
FR-014, and tests can inject an in-memory `FileSource`.

**Rules**:
- **Files**: every item that is not a folder, or is a package, is a file.
- **Links**: a folder item with `isSymlink` is not entered (FR-002). It is not listed either,
  because it is a folder.
- **Hidden items**: the panel's `showHidden` is passed down to every level.
- **Errors**: an error listing a subfolder increments `unreadable` and the walk goes on. A vanished
  folder counts the same (FR-012). An error listing the branch folder itself is thrown, as a normal
  navigation does.
- **Cancellation**: `Task.checkCancellation()` before each folder, so Esc stops even a slow server
  walk within one folder listing (SC-003).
- **Progress**: a `@Sendable (BranchProgress) -> Void` callback reports the files found so far and
  the folder being read, at most every 100 ms and after each folder.
- **Marked items** (FR-013): the scanner takes several start items. Marked files are added as they
  are, and marked folders are walked. All names are relative to the branch folder.

**Alternatives considered**:
- `FileManager.enumerator` for local folders: faster in theory, but it is a second code path with
  its own hidden and package rules. `contentsOfDirectory` per folder lists 100 000 files in a few
  seconds, which is well within SC-002.

## R4 — Progress, Esc and refresh

**Decision**:
- The panel view controller runs the scan in a `branchTask` and shows the progress in the status
  line, like the folder size calculation (`sizingProgress`): "Reading the branch: 12 345 files —
  docs/deep — Esc stops".
- **Esc while the first scan runs**: the task is cancelled. The model has not switched yet (the load
  happens before `navigate` commits), so the panel simply stays on the folder's normal listing.
- **Esc while a rescan runs** (⌘R, after an operation, switching to the tab): the panel goes to the
  normal listing of the folder. That is what FR-011 says.
- `PanelModel.refresh()` in branch view rescans with the same progress. The model holds the progress
  handler that the controller sets (`onBranchProgress`).

**Watching**: in branch view the folder is not watched (FR-010). `watchLocation` treats branch view
as it treats servers. The panel rescans on ⌘R and after the app's own operations, which already
refresh both panels.

## R5 — Leaving branch view

**Decision**:
- ⌃B in branch view calls `go(to: location, focusing:)` with the cursor's file name when the file is
  directly in the folder (FR-006). This is a recorded navigation, so Back returns to the branch.
- `goParent` has no branch special case: ".." and ⌫ go to the parent folder.
- `enterCursor` on an archive file goes into the archive, as in a normal folder, and so leaves the
  branch.

`Place` and `PanelState` keep `branch` in memory only, like `results`: the `CodingKeys` leave it
out. Tabs and history keep the branch, and a launch shows the folder (FR-016). Switching back to a
tab in branch view rescans it.

## R6 — Operations on files from many folders

**Finding**: the local operations take URLs and work from many folders already (Find results).
Archive operations derive the archive folder from the first source:
- `transferArchive` uses `sources[0].deletingLastPathComponent()` and `names = lastPathComponent`;
- `deleteInArchive` and rename in an archive work from the panel's `archive`.

These would be wrong for members in different subfolders of an archive.

**Decision**: in branch view, archive operations group their sources by their own folder
(`url.deletingLastPathComponent()`) and run once per group, inside one operation sheet. Rename uses
the item's own folder. Server transfers and deletes take a `RemotePath` per item and need no change.
A unit test covers the grouping, and the GUI check exercises it.

**Flat copy**: copying from many folders into one target can meet the same name twice. The second
file goes through the usual conflict question (FR-008); nothing new is needed.

## R7 — Commands and the menu

**Decision**: two new `Command` cases in the View menu, after "Show Hidden Files":
- `branchView`, "Branch View (With Subfolders)", ⌃B;
- `branchViewSelected`, "Branch View of Selected Items", no chord.

Both are disabled in the Network folder and in a results listing (FR-015).
- `branchViewSelected` is also disabled when nothing is marked and the cursor is on "..".
- `branchView` acts as a toggle in branch view.

**Shortcut**: ⌃B is free: no `KeyMap` entry, no menu item and no system default in a file list. In
text fields ⌃B moves the caret back one character, and it still does. Panel commands are disabled
while a text field has focus.

## R8 — Path bar, tab and title

**Decision**: the breadcrumbs end with a "Branch" segment, which is not clickable and works like the
results title. The path field shows "<folder> — Branch". The tab title is "<folder> (Branch)".

## R9 — Version

Version 0.3.0 was not published, so the maintainer chose to ship this spec in 0.3.0 together with
spec 008 (2026-10-10). The branch is built on top of `008-finder-size-format`, and the CHANGELOG entry
is in the 0.3.0 section. There is no separate bump.
