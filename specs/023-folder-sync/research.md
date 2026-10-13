# Research: Synchronize Folders

## R1 Scanning two trees

- **Decision**: a new core scanner walks both folders together, one relative folder at a time: it lists
  the left and the right folder with `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)`
  (keys: is directory, is symbolic link, is package, is hidden, file size, content modification date),
  matches the names by `NameRules.key`, and descends only into folders that exist on both sides. A folder
  on one side only becomes one row; its total size and file count are summed by walking it (for the
  summary bytes), without making rows.
- **Rationale**: matching folder by folder keeps memory low (no full tree of each side first) and lets
  progress report the current folder. `FileSource.list` follows a link's target for `isDirectory` and has
  no link target, so it is not used; `BranchScanner` is the model for cancellation and unreadable folders.
- **Alternatives**: scanning each side fully and joining by path (twice the memory, no early rows);
  `fts` as in `DiskUsage` (fast, but name matching and the per-folder merge would be on raw C strings).

## R2 Name matching

- **Decision**: case-sensitive only when both volumes are case-sensitive (as Compare Panels does),
  otherwise `NameRules.apfsDefault`; `NameRules.key` already folds Unicode to NFC, so composed and
  decomposed names match. When two names on one side map to the same key (possible on a case-sensitive
  volume against a case-insensitive one), the second becomes an error row ("Name clashes with …") and is
  not touched.
- **Rationale**: copying "A" and "a" onto a case-insensitive volume would make one overwrite the other.

## R3 Dates and the one-hour rule

- **Decision**: content modification dates; |Δ| ≤ 2 s counts as equal; with the option on, ||Δ| − 3600 s|
  ≤ 2 s also counts as equal. The newer side is the one with the later date when |Δ| is beyond both rules.
- **Rationale**: FAT stores 2-second steps and local time; daylight saving shifts by exactly one hour.

## R4 Content comparison

- **Decision**: only for pairs of regular files that are equal by the other enabled criteria and have the
  same size (different sizes are already different); read both in 1 MB chunks, stop at the first
  difference, check cancellation between chunks, count read bytes in the progress.
- **Rationale**: FR-007 ("content is read only for pairs that are equal by the other criteria").

## R5 Symbolic links and packages

- **Decision**: a link is its own kind: equal when both are links with the same target text
  (`destinationOfSymbolicLink`), otherwise newer by the link's own date when date comparison is on, else
  different. A link facing a file or folder is "different" (kind mismatch). Packages are folders (walked).
- **Rationale**: FR-009; links are never followed, so a link to a large folder cannot pull it in.

## R6 Copying

- **Decision**: the run groups planned copies by destination folder (target root + the item's parent
  path) and calls `FileOperations.transfer` once per group with `TransferKind.copy`. The conflict closure
  answers `overwrite` only for target URLs the plan expects to overwrite and `skip` for anything else, which
  is recorded as "changed since comparing". Before each group, each item is checked against the compared
  state (`SyncCheck`: existence, kind, size, date of both sides; link target); changed items are left out
  and reported.
- **Rationale**: reuses verification, metadata copying (`copyfile` keeps dates and permissions, links as
  links), progress and cancellation; one destination per request is a property of `TransferRequest`.
- **Order**: replacements (file ↔ folder: the target goes to the Trash first, then the copy), then copies,
  then deletions last, so cancelling during the copies never leaves deletions done.

## R7 Deleting

- **Decision**: `TrashSupport.isAvailable` per volume, then `TrashSupport.moveToTrash` per item; an item on
  a volume without a Trash is reported and left alone; never `deletePermanently`.

## R8 Progress and the eject guard

- **Decision**: comparing shows progress inside the sync window (spinner, items scanned, current folder,
  Cancel; Esc cancels). The run goes through `OperationsController.perform`, which gains an optional
  window for its progress sheet so the sheet attaches to the sync window; the `OperationState` carries
  `urls: [left, right]`, so the eject guard (spec 022) sees it, and `perform` refreshes the panels. While
  comparing, the sync window's `volumeUser` names both folders; `VolumeEjector.users()` gets the new
  window type.

## R9 Window

- **Decision**: `SyncWindowController` (AppKit), one per main window (kept in a weak map keyed by the main
  window controller); a header (both folders, the options in one line), filter buttons (Equal, Different,
  Left Only, Right Only), a view-based `NSTableView` with the columns name (icon + relative path, indented
  by depth), left size, left date, action, right size, right date; a summary line; buttons Compare Again
  and Synchronize. Rows are a filtered index list over the comparison, so filters never touch actions.
- **Keys**: the table subclass handles Space, ←, →, =, Delete, F3 and Return; ⌘R is intercepted before
  the main menu's Refresh when the sync window is key; Esc closes (or cancels comparing).

## R10 Options sheet and settings

- **Decision**: a SwiftUI sheet like `CompareSheet`, bound to `AppSettings.shared.sync` (JSON under the
  UserDefaults key `syncOptions`, listed in `SettingsCatalog.app` next to `comparison`). `SyncOptions` has
  a custom `init(from:)` with `decodeIfPresent` for every field, so later fields do not break older files.
  The delete toggle is disabled while the direction is Both ways.

## R11 Key

- **Decision**: ⌥⇧F10 (`f(10, [o, s])`) is free in the default keys and in the Classic Commander scheme.
