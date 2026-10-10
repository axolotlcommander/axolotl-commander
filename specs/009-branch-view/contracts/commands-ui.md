# Contract: Branch View Commands and Panel

## View menu (after "Show Hidden Files")

| Command | Czech | Chord | Enabled when |
|---|---|---|---|
| Branch View (With Subfolders) | Zobrazit větev (s podsložkami) | ⌃B | not in the Network folder, not in a results listing |
| Branch View of Selected Items | Zobrazit větev označených položek | none | as above, and something is marked or the cursor is on an item other than ".." |

In branch view, ⌃B returns to the normal listing of the folder.

## Panel in branch view

| Element | Content |
|---|---|
| Name and Ext columns, Brief view | the file's own name and extension |
| Size and Date columns | as for any file (spec 008 settings) |
| ".." row | first; Enter goes to the parent folder |
| Path bar | the folder's breadcrumbs, then a "Branch" segment (Czech "Větev") |
| Path field | "<folder> — Branch" |
| Tab title | "<folder name> (Branch)" |

## Status bar

| Situation | Text (English / Czech) |
|---|---|
| scan running | "Reading the branch: 12,345 files — docs/deep — Esc stops" / "Načítám větev: 12 345 souborů — docs/deep — Esc zastaví" |
| cursor on a file | "docs/deep/d.txt   4.1 MB (4,100,000 bytes)   date" |
| nothing marked, some folders unreadable | "N files, 0 folders — <size> — 2 folders could not be read" / "… — 2 složky nešlo přečíst" |

## Disabled in branch view

- New folder (F7) and new file.
- Paste files and Move files here.
- The new link commands and Go to link target.
- Change attributes.

## Operations

- **F5 and F6**: the marked files, or the file under the cursor, are copied flat into the target.
  When the target panel is in branch view, its folder is the target.
- **F8, F2, F3, F4, Enter and Quick Look**: they act on the file at its real location.
- After an operation the branch is scanned again.
