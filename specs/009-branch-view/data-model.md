# Data Model: Branch View

Types are in `CommanderCore` unless marked UI.

## BranchListing (value, Hashable, Sendable)

| Field | Type | Rule |
|---|---|---|
| root | `URL` | the branch folder; it is the panel's location while the branch is shown |
| starts | `[URL]?` | nil: the whole folder (⌃B). Otherwise the marked items (FR-013), all directly in `root` |

`title` is a computed property ("Branch"), used for the path bar segment and the tab.

## BranchProgress (value, Sendable)

| Field | Type |
|---|---|
| files | `Int`: the files found so far |
| folder | `String`: the relative path of the folder being read ("" for the root) |

## BranchResult (value, Sendable)

| Field | Type | Rule |
|---|---|---|
| items | `[FileItem]` | files only; `name` is the path relative to `root`, `url` is the real location |
| unreadable | `Int` | the subfolders that could not be listed or had vanished |

## BranchScanner (enum, static)

```text
scan(_ listing: BranchListing, source: any FileSource, includeHidden: Bool,
     progress: @Sendable (BranchProgress) -> Void) async throws -> BranchResult
```

It follows the rules of research.md R3. An error listing `root` is rethrown, and a cancellation is
thrown as `CancellationError`.

## Changes to existing types

- **`PanelModel`**:
  - `branch: BranchListing?`;
  - `unreadableFolders: Int`;
  - `onBranchProgress: (@MainActor (BranchProgress) -> Void)?`;
  - `showBranch(_:focusing:)`;
  - `load` dispatches to `BranchScanner` when it gets a branch.
  - `refresh` rescans.
  - Quick search and name sorting use the file name in branch view (R2).
- **`PanelState.Place` and `PanelState`**: `branch: BranchListing?`, kept in memory only and left out
  of `CodingKeys`.
- **`sortItems(..., byFileName: Bool = false)`**: the name order compares `url.lastPathComponent`
  first, then `name`.
- **`Command`**:
  - `.branchView` ("Branch View (With Subfolders)", ⌃B, View menu);
  - `.branchViewSelected` ("Branch View of Selected Items", View menu, no chord).

## UI (AxolotlCommander)

- **`PanelViewController`**:
  - `branchTask` and `branchProgress` (the status text);
  - Esc cancels the scan (R4);
  - the Name and Ext text and the Brief view use the file name in branch view;
  - the command validation follows FR-009 and FR-015;
  - the folder is not watched in branch view.
- **Archive operations**: sources are grouped by their own folder (R6).
