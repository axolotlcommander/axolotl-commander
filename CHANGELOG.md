# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.0] - 2026-10-13

### Added

- More default shortcuts from classic two-panel file managers, next to the existing ones (spec
  010):
  - ⌥← / ⌥→ back and forward;
  - ⌃← / ⌃→ open in the left / right panel;
  - ⌃F1 Brief view, ⇧F2 Compare Panels, ⇧F6 Rename, ⌥F9 Unpack;
  - ⌃R refresh, ⌃A select all, ⌃C / ⌃V copy and paste files, ⌃I switch panel, ⌃D hot paths;
  - ⌃F and ⌃N Connect to Server, ⌃⇧B branch view of selected items;
  - ⌥↩ Get Info, ⌥⇧↩ folder sizes;
  - ⌥Num+ / ⌥Num− select / deselect the same extension;
  - ⌃J and ⌃P insert the name and the panel path into the command line.
- ⌃⇧↩ inserts the full path of the item under the cursor into the command line (⌃↩ still
  inserts its name).
- Settings → Keyboard → Key scheme: "Classic Commander" changes the keys that mean something else
  in the app:
  - ⌃T / ⌃W open and close tabs, ⌃⇥ / ⌃⇧⇥ move between them;
  - ⌃F2 is the Detailed view;
  - ⌥F3 is View With, ⌥F4 quits;
  - ⌃⇧F disconnects, ⌃⇧F5 makes a symbolic link.

  Your own shortcut changes stay on top of the scheme. The table shows where each shortcut comes
  from, and Reset returns to the scheme.
- Export Settings… and Import Settings… (app menu and Settings → General) save the whole setup to
  one JSON file and load it back: keys, preferences, appearance, hot paths, user menu, saved servers
  and toolbar. Passwords are never included. Import lets you choose the parts and reports anything it
  skipped.
- Settings → General → Panels: four behavior options, each independent of the key scheme (spec 011):
  - Space moves the cursor down (on by default; off keeps the cursor on the marked item);
  - Typing goes to the command line: characters typed in a panel fill the command line while the
    panel keeps the focus; with text in the line, Return runs it, Backspace and Esc edit it, and ⌥ +
    a character starts quick search;
  - ⌃← / ⌃→ change the panel the arrow points to, and ".." opens the other panel's folder;
  - Volume buttons open the other panel's folder on that volume, or the last folder used there.
- Tabs from the keyboard (spec 012), all in the Go and View menus:
  - Open in New Tab (⌃↑, ⌥⌘↓), Open in Background Tab (⌥⌘⇧↓) and Open in New Tab of Other Panel
    (⌃⇧↑) open the folder under the cursor without leaving the current tab;
  - Reopen Closed Tab (⌘⇧T) and Tab List… (⌘⇧\, ⌃⇧A), which also offers the recently closed tabs;
  - Close Other Tabs (⌥⌘W; ⌃⇧W in Classic Commander) and Swap Panels with All Tabs (⌃⇧U).
- Quick Filter (⌥⌘F; ⌃S in Classic Commander): typed text narrows the panel list as you type, as a
  substring or a mask such as `*.txt`. The arrows move among the matches, and Esc shows everything
  again. Quick Filter with Last Text (⌃⇧S, ⌥⌘⇧F) brings back the last filter, and Quick Filter during
  quick search turns the search into a filter. Marked items the filter hides are left out of commands
  (spec 013).
- Go → Folder History… (⌃⌘H; also ⌥↓ in Classic Commander) lists the folders the panel visited and
  the recently typed paths; typing filters the list. Return opens the folder, ⌘Return opens it in a
  new tab and ⌥Return in the other panel. Commands → Command Line History… (⌥F8) lists executed
  commands; the chosen one goes into the command line without running (spec 014).
- Small commands (spec 015):
  - File → Copy As… (⇧F5) copies the item under the cursor next to itself under a new name;
  - File → New Folder in Other Panel… (⌥⌘N; ⇧F7 in Classic Commander) offers the cursor item's name;
  - File → View Cursor File Only (⌥⇧F3; also ⇧F3 in Classic Commander) ignores the marked files;
  - File → Pack and Move… (⌥⇧F5) packs and then moves the originals to the Trash;
  - File → Test Archives (⌥⇧F9) reads the marked archives through and reports damaged ones;
  - Edit → Select All Files / Deselect All Files (⌃⇧Num+ / ⌃⇧Num−) leave folders as they are;
  - ⌥⇧↑ marks or unmarks without moving, ⌃⇧J inserts the full path into the command line;
  - in Classic Commander ⌃L calculates the size of the marked items.
- View → Quick View Panel (⌃Q): the other panel shows the preview of the item under the cursor and
  follows the cursor; ⌃Q again, Tab or a click on it brings the panel back (spec 016).
- Settings → General → Buttons on the bar: tick boxes F1–F12 choose which buttons the function key
  bar shows; a key whose button is off still works. A button is at most 140 points wide, so a few
  buttons stand at the left instead of filling the bar. The bar's context menu has Choose Buttons…
  (spec 017).
- Button bar (spec 018): a row of icon buttons for any app command or program (with the user
  menu's variables), at the top or at the bottom after the function keys; View → Show Button Bar,
  Settings → Button Bar (buttons, order, separators, SF Symbols or app icons) and a right click on
  the bar. Buttons that do not fit go into a » menu. Off by default, with a few sample buttons.

- A drive row below the volume bar of each panel (spec 020): a drive combo with the same list as
  ⌥F1/⌥F2 and the free and total space of the panel's disk ("273.9 GB free of 994.7 GB"); clicking
  the space opens Volume Info. When the row is hidden the free space moves to the right end of the
  volume bar, or of the status line when the volume bar is hidden too (Settings → General; View →
  Show Drive Row, Show Volume Bar). The volume bar can be hidden now.

### Changed

- The function key bar leaves a small margin at both ends, so F1 no longer sits in the window's
  rounded corner.

### Fixed

- ⌃↩ in a panel inserts the name of the item under the cursor into the command line again; macOS
  showed the context menu for it instead.
- ⌘X cuts the selected text in the command line and other text fields; the Edit menu had no Cut
  item. ⌃X, ⌃C and ⌃V also cut, copy and paste text while the command line has focus.
- Extracting an archive no longer briefly changes the process umask, which could give files
  created at the same moment (by another operation) the wrong permissions.
- Names in zip files made on Windows without the UTF-8 flag (for example Czech names in CP852)
  show and extract correctly instead of with "�"; the code page follows the system language.
- An archive opened through a symlinked folder or with different letter case no longer shows a
  stale member list after it changes.
- F4 says when the editor chosen in Settings is not installed instead of silently opening
  TextEdit.

## [0.3.1] - 2026-10-11

### Changed

- F1 (Help → Axolotl Commander Help) opens the project page on GitHub until the app has its own
  help; before, it was always grayed out.

### Fixed

- The function key bar keeps every key and name in a fixed place: each key is drawn in a key cap
  of one width at the left of its button with the name right after it, so holding ⇧, ⌃ or ⌥ no
  longer shifts the labels around.
- F3 on a TypeScript file (`.ts`, `.mts`) opens the viewer with syntax highlighting. macOS takes
  these extensions for MPEG-2 video, so they went to Quick Look; a real video file still does.

## [0.3.0] - 2026-10-10

### Added

- Sizes in the panels read like Finder: "402 bytes", "453 kB", "4.1 MB", in the language and
  number format of the system. **This is the new default**; to get exact bytes in the Size column
  back, choose Settings → Appearance → Size in panels → In bytes. The exact byte count is always in
  the tooltip of the Size cell and in the status bar for the item under the cursor
  ("4.3 MB (4,300,000 bytes)").
- Settings → Appearance → Units chooses 1000 (as Finder counts, the default) or 1024 (as Windows
  counts) for every rounded size in the app: panels, status bars, the volume bar, operations,
  Properties, Compare and Disk Usage.
- A size that does not fit a narrow Size column shows an ellipsis, never a cut number.
- Branch view (⌃B, View → Branch View (With Subfolders)), as in Total Commander: the panel lists
  every file of the folder and of all its subfolders in one list. The Name column shows the file's
  own name; the status bar shows its path below the folder. ⌃B again returns to the folder. It
  works in folders on disk, in archives and on servers; a long scan shows its progress, and Esc stops
  it. View → Branch View of Selected Items does the same for the marked files and folders.

## [0.2.2] - 2026-10-10

### Changed

- The Size and Date columns of the panel can be made narrow. A value that does not fit shows a
  shorter form instead: a rounded size ("1.2 MB"); the date without the time, with a two-digit
  year, or only the day and month; an ellipsis when nothing fits. The full value is in the
  tooltip. Before, the columns could not get narrower than their widest value, so their edges
  offered no resizing in that direction.
- A column resized by hand takes its width from Name, so the columns always fill the panel, and
  the right edge of the last column can be dragged too.

## [0.2.1] - 2026-10-09

### Fixed

- Symbolic links to folders open again in the panel (for example /Volumes/Macintosh HD, a link
  to /); before, the panel only beeped with "Not a directory".

## [0.2.0] - 2026-10-09

The first versioned release (earlier builds called themselves 0.1.0 without a tag): a two-panel file manager (stages 0–11 of the plan in
[docs/PLAN.md](docs/PLAN.md)) and the data-safety fixes from the
[001-data-safety-gaps](specs/001-data-safety-gaps/spec.md) specification.

### Added

- CSV, TSV and TAB files open in the viewer's Preview as a table, also when they are hundreds of
  megabytes large. The table has:
  - a detected separator, encoding and header row;
  - fixed row numbers;
  - marked malformed rows (⌘↓/⌘↑, Show Only Malformed Rows ⇧⌘D);
  - find cell by cell (F3/⇧F3);
  - Go to Row (⌘L) and copy as tab-separated text;
  - sorting by a column once the file is read
  ([007-csv-table-preview](specs/007-csv-table-preview/spec.md)).
- In the viewer, function keys such as F3 and ⇧F3 also work while the find field is being edited.
- Website [axolotlcommander.org](https://axolotlcommander.org), linked from the README and the
  About window.
- Function key bar F1–F12 at the bottom of the main window, following the held modifiers
  (⇧ ⌃ ⌥ ⌘); the bar and the command line can be hidden from the View menu or Settings
  ([002-function-key-bar](specs/002-function-key-bar/spec.md)).
- Settings → Keyboard shows whether F1–F12 need `fn` and opens System Settings; a one-time
  notice on launch explains it.
- Clickable breadcrumb path bar above each panel: click a folder to go there, ⌘-click for a
  new tab, right-click for more; ⌘L (Edit Path) types a path; long paths collapse into "…";
  the text field stays available in Settings → Appearance
  ([003-breadcrumb-path-bar](specs/003-breadcrumb-path-bar/spec.md)).
- Open server connections as buttons in the volume bar: one click returns to the last folder on
  the server, ⏏ on hover or the right-click menu disconnects; the volume menu (⌥F1/⌥F2) lists
  them under "Servers". The volume bar also offers iCloud Drive, Network (mounted network
  volumes, connections, Connect to Server…) and an optional Home button, chosen in Settings →
  Appearance; the toolbar gets Connect to Server, and Disconnect can be added
  ([004-server-connection-buttons](specs/004-server-connection-buttons/spec.md)).
- Links: New Symbolic Link… (⌃⌘L) and New Hard Link… create links in the other panel's folder
  (absolute or relative target, several items at once), Edit Symbolic Link… changes a link's
  target in one step, Paste as Symbolic Link (⌃⌘V, ⌃S) links copied items, and Go to Link Target
  (⌃T) follows symbolic links and Finder aliases. Existing items are never replaced. Change
  Attributes… (⌃F2) opens the permissions editor directly
  ([005-unix-link-commands](specs/005-unix-link-commands/spec.md)).
- Network folder: the Network button in the volume bar (and Network in the volume menu) shows
  the SMB, AFP and SFTP servers announced on the local network and the mounted network volumes
  in the panel; Enter mounts an SMB/AFP share through the macOS dialog and enters it, or opens
  Connect to Server for an SFTP server. The quick menu of the Network button moved to its
  right-click ([006-network-places](specs/006-network-places/spec.md)).
- The macOS prompts for folder access (Desktop, Documents, Downloads, disks, cloud storage)
  explain why a file manager needs it, in English and Czech.
- Releases can be signed with a stable project certificate (`scripts/make-signing-cert.sh`), so
  folder access granted by users survives updates even without an Apple Developer ID; local
  builds are signed with the developer's "Apple Development" certificate when there is one.
