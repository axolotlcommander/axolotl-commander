# Data Model: Copy Dialog and Replace Question

## ConflictMarks

- `newerSide: Side?` (`existing` | `new`), from the modification dates; nil when equal or unknown.
- `largerSide: Side?`, from the sizes; nil when equal, unknown or a folder side.

## AutoName

- `name(for original: String, isDirectory: Bool, attempt: Int) -> String`, attempt ≥ 2.
- Files with an extension: "base N.ext" (extension = after the last dot, a leading dot is not an
  extension: ".zshrc" → ".zshrc 2"). Folders and names without an extension: "base N".
- The result fits 255 UTF-8 bytes: the base is shortened at a character boundary.

## ConflictPolicy

- `mode`: `ask` | `overwriteAllOlder` | `renameAllAutomatically`.
- `pending`: the last automatic candidate (source URL, attempt) to continue counting.
- `decide(Conflict) -> Decision` (`.answer(ConflictResolution)` | `.ask`):
  - a conflict for the pending source whose destination name is the pending candidate → next attempt;
  - `overwriteAllOlder`: `overwrite` when the new date is later, else `skip` (also for folders and
    unknown dates);
  - `renameAllAutomatically`: `rename(attempt 2)` when `canRename`, else ask;
  - `ask` → `.ask`.
- `choose(Choice, for: Conflict) -> ConflictResolution`: the user's choice from the question;
  `overwriteAllOlder` and `renameAllAutomatically` switch the mode and answer this conflict;
  `renameAutomatically` answers attempt 2 once.

## TransferTarget

- `init(text:sourceName:)`; `resolve(isFolder: (String) -> Bool) -> (folder: String, name: String)`:
  an existing folder or a trailing "/" → (text, sourceName); otherwise (parent, last component).
- `ranges(in text: String) -> [NSRange-like UTF-16 ranges]`: name without extension, extension (absent
  when none), folder part, whole text; `next(after:)` cycles.

## DestinationMenu

- `Section`: `otherPanel`, `tabs`, `hotPaths`, `recent`; `Entry(section, title, path)`.
- `build(otherPanel:, otherTabs:, ownTabs:, source:, hotPaths:, recent:, isNetwork:, exists:)`:
  sections in that order, a path listed once (first occurrence wins), the source folder, Network and
  missing local folders left out, empty sections left out.

## Recent destinations

- `RecentPaths(limit: 10)`, key `transfer.recentDestinations`, newest first, no duplicates (trailing "/"
  ignored), passwords scrubbed; not exported.
