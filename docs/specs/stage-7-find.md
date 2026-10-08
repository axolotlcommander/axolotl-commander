# Stage 7 – Find files (⌃⌥F7)

Reference: Salamander `finddlg_main.htm`, `finddlg_advan.htm`, `basicwork_find.htm`.

## Find window
- Modeless window, several can be opened. The search runs in the background, the main window stays usable.
- **Name** (combo + history of 30): Salamander masks (`;`, `|` exclusion). A mask without `*`, `?` and a dot
  means "contains" (`dog` = `*dog*`); a trailing dot means exactly (`dog.` = name `dog`).
  Empty = everything.
- **Look in** (combo + history of 30): multiple paths separated by `;`, default = the active panel's folder,
  a button to choose a folder. `~` is expanded.
- Options: subfolders (on by default), hidden files (according to the panel), inside packages (`.app` etc.,
  off by default — but the package itself may match by name).
- **Contains** (combo + history of 30): Match case, Whole words, Hex (`4A 6F "text" 00`),
  Regular expression. Text is searched in UTF-8, UTF-16 LE/BE and in the viewer's default single-byte
  encoding; both NFC and NFD forms. Content search returns only files.
- **Advanced**: size from–to (B/KB/MB/GB), modified from–to, kind (files and folders / files /
  folders), skip folders (`;`: a name with a mask, e.g. `node_modules;.git`, or an absolute path).
- **Duplicates**: same name / same size / same content (content requires size). Groups
  with alternating background shading, sorted by groups.
- Symlinks are not followed; a directory visited twice (firmlinks `/System/Volumes/Data`) is skipped
  (st_dev + st_ino). Unreadable folders and files → error log (count in the status bar).

## Results
- Table Name, Path, Size, Modified; sorting by clicking the header; multiple selection;
  results appear progressively (in batches). Status bar: the folder currently being searched, number found,
  and after completion the time and the number of errors.
- Commands (scope `find`, the menu switches as with the viewer):
  - Enter open, space bar / ⌘R show in panel (the active panel goes to the folder and places the cursor),
  - F3 viewer (sequence = results), F4 editor, ⌘Y Quick Look, ⌘I properties,
  - F8 / ⌘⌫ to Trash (confirmation, as in the panel), ⌫ remove from the list,
  - ⌘C files to the clipboard, ⌥⌘C full paths, ⌘⇧C names, ⌘A select all,
  - ⌘↩ Find, ⌘. / Esc stop (Esc when idle closes the window), ⌘⇧P results to panel.
- Results to panel: the active panel shows the list of results as a virtual folder (relative paths),
  F3/F4/F5/F6/F8 work on them; Backspace / history goes back.

## Out of scope for this stage
Saved searches, refinement (intersection/difference/add), searching in archives, attributes.
