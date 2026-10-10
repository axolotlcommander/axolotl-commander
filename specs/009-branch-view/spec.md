# Feature Specification: Branch View

**Feature Branch**: `009-branch-view`

**Created**: 2026-10-10

**Status**: Draft

**Input**: User description: "Branch view (Ctrl+B) like Total Commander: all files of the current folder and all
its subfolders in one flat list in the panel."

## Context

Total Commander's "Branch View (With Subdirs)" (Ctrl+B) lists every file of a folder and of all its
subfolders in one panel. The files appear as if they were all in that folder. The maintainer wants
the same in Axolotl Commander, and the app does not have it yet.

The maintainer's reference screenshots of Total Commander show:
- the Name column with file names only, without paths;
- two files with the same name from different subfolders, both listed;
- the path field still showing the folder;
- the status bar line for the item under the cursor showing the file's path relative to the folder
  ("vzorky\tisk").

Reference behavior:
- Tandem Commander and Open Salamander have no branch view. Total Commander is the reference here,
  which is a recorded deviation from the usual reference.
- In Total Commander the branch view lists files, not folders.
- Ctrl+Shift+B in Total Commander shows the branch of the marked items only.
- Total Commander offers no branch view of Find results ("Feed to listbox"), because they are
  already a flat list.

The app already shows Find results in a panel (a results listing). The branch view is similar, with
two differences:
- the Name column shows only the file name;
- it works in archives and on servers too.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - All files of a folder tree in one list (Priority: P1)

A user wants to see, sort and work with every file of a project folder without opening each
subfolder. They press ⌃B. The panel lists all files of the folder and its subfolders. The user sorts
by date to find the newest files, views one with F3, and copies a few to the other panel.

**Why this priority**: it is the feature. Every other story builds on it.

**Independent Test**: on a test folder with nested subfolders, press ⌃B, then:
- check that every file of the tree is listed once, and no folder;
- read the relative path in the status bar;
- press ⌃B again to return.

**Acceptance Scenarios**:

1. **Given** a folder with files `a.txt` and `b.md` and a subfolder `docs/` with `c.pdf` and
   `deep/d.txt`, **When** the user presses ⌃B, **Then**:
   - the panel lists "..", `a.txt`, `b.md`, `c.pdf` and `d.txt`, and no folders;
   - each name is shown without its path;
   - the list follows the panel's current sort order.
2. **Given** branch view with the cursor on `d.txt`, **When** the user reads the status bar,
   **Then** it shows `docs/deep/d.txt`, its size and its date.
3. **Given** two files named `notes.txt`, one in the folder and one in `docs/`, **When** branch view
   is shown, **Then**:
   - both are listed;
   - the status bar tells them apart by their relative paths;
   - marking, F3 and F2 act on the exact file under the cursor.
4. **Given** branch view, **When** the user presses ⌃B again, **Then** the panel shows the normal
   listing of the same folder. If the file under the cursor is directly in the folder, the cursor
   stays on it.
5. **Given** branch view, **When** the user navigates elsewhere, **Then** branch view ends as a
   normal navigation does. The ways to navigate are:
   - Enter on "..", ⌫ or ⌘↑, which go to the parent folder;
   - a hot path;
   - the path field;
   - history back and forward.
6. **Given** branch view, **When** the user marks three files in different subfolders and presses
   F5, **Then**:
   - the three files are copied into the other panel's folder, flat;
   - conflicts use the usual conflict dialog;
   - the source panel stays in branch view.
7. **Given** branch view, **When** the user deletes a file with F8, **Then** the file is deleted at
   its real location, and the branch view is scanned again and stays in branch view.
8. **Given** branch view, **When** the user presses ⌘R, **Then** the tree is scanned again.
9. **Given** branch view, **When** the user looks at the path bar and the tab, **Then** both show the
   folder and a visible mark that this is a branch view.

---

### User Story 2 - Big trees stay responsive and can be cancelled (Priority: P1)

A user presses ⌃B on a large folder by mistake, for example their home folder. The app keeps
responding, shows how far the scan is, and Esc stops it.

**Why this priority**: without it, one keystroke can make the app unresponsive for minutes. That
risk ships with the feature, so it has the same priority.

**Independent Test**: on a test tree with 100 000 files:
- ⌃B shows progress, and the panel and the other panel respond;
- Esc during the scan returns the panel to the normal listing.

**Acceptance Scenarios**:

1. **Given** a tree that takes several seconds to scan, **When** the user presses ⌃B, **Then**:
   - the status bar shows progress (files found so far and the folder being read), updated at least
     once a second;
   - the other panel and the menus keep working.
2. **Given** a scan in progress, **When** the user presses Esc in that panel, **Then** the scan stops
   within one second, and the panel shows the normal listing of the folder.
3. **Given** a tree with an unreadable subfolder, **When** branch view is shown, **Then**:
   - the files of the other subfolders are listed;
   - the status bar notes how many folders could not be read.

---

### User Story 3 - Branch view of the marked items (Priority: P2)

A user marks two subfolders and one file, and picks View → Branch View of Selected Items. The panel
lists the marked file and every file in the two subfolders and below.

**Why this priority**: useful for narrowing a big tree, but the full branch view (US1) covers most
needs.

**Independent Test**: mark one file and two folders, run the command from the menu, and check the
listed files.

**Acceptance Scenarios**:

1. **Given** marked items `x.txt`, `docs/` and `src/`, **When** the user runs Branch View of Selected
   Items, **Then** the panel lists:
   - `x.txt`;
   - every file of `docs/` and `src/` and their subfolders;
   - no other files.
2. **Given** nothing marked and the cursor on a folder, **When** the user runs the command, **Then**
   it lists that folder's branch.
3. **Given** nothing marked and the cursor on "..", **When** the user opens the menu, **Then** the
   command is disabled.
4. **Given** the command, **When** the user looks for a shortcut, **Then** it has none and is
   available from the menu only.

---

### User Story 4 - Branch view in archives and on servers (Priority: P2)

A user browses a ZIP archive or an SFTP server and presses ⌃B. The branch view of the archive
folder, or of the server folder, is shown as for a local folder.

**Why this priority**: the maintainer asked for branch view everywhere. Local folders are the
common case, so these come second.

**Independent Test**:
- inside a test archive with nested folders, ⌃B lists all its files;
- on a test server, ⌃B lists all files of a nested test folder, with progress, and Esc cancels.

**Acceptance Scenarios**:

1. **Given** a panel inside an archive with nested folders, **When** the user presses ⌃B, **Then**
   all files of the archive folder and below are listed. F3 and copying out work as they do in the
   archive today.
2. **Given** a panel on an FTP, FTPS or SFTP folder, **When** the user presses ⌃B, **Then** each
   subfolder is listed over the connection, with the progress of US2, and Esc cancels.
3. **Given** a server or archive branch view, **When** the user runs a command the panel does not
   support for that location today, **Then** it stays disabled, as it is in the normal listing.

---

### Edge Cases

- **Empty branch:** a folder tree without files shows only "..", and the status bar says 0 files.
- **Links:** symbolic links to folders are not followed, so link loops are impossible. Links to
  files are listed as files.
- **Packages:** packages (.app, .bundle…) count as files and are not entered, as elsewhere in the
  panel.
- **Hidden files:** they follow the panel's hidden-files setting, at every level.
- **Highlighting and sizes:** highlighting rules and the size display settings (spec 008) apply.
- **Deep nesting and long paths:** the scan handles them. The status bar shows the relative path,
  shortened in the middle if it does not fit.
- **A subfolder removed during the scan:** it is skipped, and the scan goes on.
- **Both panels:** both can be in branch view at the same time.
- **Brief view:** it shows the file names too.
- **Network folder:** the server list has no branch view; the command is disabled there.
- **Find results:** a results listing has no branch view, as in Total Commander; the command is
  disabled there.
- **Tabs:** each tab keeps its own branch view, and switching tabs keeps it.
- **Launch:** a tab that was in branch view opens on the normal listing of its folder.
- **Commands that create items in the panel's folder:** these are disabled in branch view, as in
  the results listing. They are:
  - F7 new folder;
  - new file;
  - paste files;
  - new links.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The View menu MUST offer "Branch View (With Subfolders)" with the shortcut ⌃B, for the
  active panel. In Czech the command is "Zobrazit větev (s podsložkami)". It lists every file of the
  current folder and of all its subfolders, recursively, in one flat list.
- **FR-002**: Branch view MUST list files only, never folders. It MUST:
  - treat packages as files;
  - follow the panel's hidden-files setting;
  - not follow symbolic links to folders;
  - list symbolic links to files as files.
- **FR-003**: The Name and Ext columns MUST show the file's own name and extension, without a path.
  Files with the same name from different subfolders MUST all be listed. The ".." row MUST stay at
  the top.
- **FR-004**: The status bar line for the item under the cursor MUST show the file's path relative
  to the branch folder ("docs/deep/d.txt"), followed by its size and date. The selection and totals
  lines work as in a normal listing.
- **FR-005**: The path bar and the tab title MUST show the branch folder with a visible mark that the
  panel is in branch view.
- **FR-006**: ⌃B in branch view MUST return to the normal listing of the same folder. The cursor
  MUST stay on the same file when the file is directly in the folder. Any other navigation MUST
  leave branch view as a normal navigation does.
- **FR-007**: In branch view these MUST act on the listed files at their real locations, as in a
  normal listing:
  - sorting by every column;
  - marking;
  - quick search;
  - F3 and F4;
  - opening;
  - Quick Look;
  - copying the path;
  - dragging out of the panel;
  - F2, which renames the file in its own subfolder;
  - F5, F6 and F8.
- **FR-008**: F5 and F6 from branch view MUST copy or move the files flat into the target, with the
  usual conflict handling. When the target panel is in branch view, its branch folder is the target.
- **FR-009**: Commands that create items in the panel's folder MUST be disabled in branch view:
  - new folder;
  - new file;
  - paste files;
  - new links.
- **FR-010**: After an operation that changes files in the branch, and on ⌘R, the branch MUST be
  scanned again, and the panel MUST stay in branch view. Changes made outside the app are not
  watched.
- **FR-011**: The scan MUST NOT block the app. While it runs, the status bar MUST show the number of
  files found and the folder being read, updated at least once a second. Esc MUST cancel it within
  one second and return the panel to the normal listing.
- **FR-012**: Unreadable or vanished subfolders MUST be skipped, and the scan goes on. The status bar
  MUST note how many folders could not be read.
- **FR-013**: The View menu MUST offer "Branch View of Selected Items" without a shortcut. In Czech
  it is "Zobrazit větev označených položek". It lists:
  - the marked files;
  - every file in the marked folders and their subfolders, by the rules of FR-002.
  With nothing marked it acts on the item under the cursor. It is disabled when there is nothing to
  act on.
- **FR-014**: Branch view MUST work in local folders, inside archives the panel can browse, and on
  FTP, FTPS and SFTP folders. Commands keep the availability they have in a normal listing of that
  location.
- **FR-015**: Both branch commands MUST be disabled in the Network folder and in a results listing.
- **FR-016**: Each tab MUST keep its own branch view state. Branch view MUST NOT be restored at
  launch.
- **FR-017**: The new command names and status texts MUST be localized in English and Czech.

### Key Entities

- **Branch**:
  - the folder it was made from (the branch folder), or the marked items it was made from;
  - the location kind: local, archive or server;
  - the list of files found, each with its path relative to the branch folder;
  - the number of folders that could not be read.
- **Branch scan**: a running, cancellable listing of a folder tree, with the progress so far.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a test tree, the branch view lists exactly the files of the tree:
  - each file once;
  - no folders;
  - no files from linked folders;
  - hidden files only when the panel shows them.
- **SC-002**: A local tree of 100 000 files is listed within 30 seconds on the maintainer's
  machine. During the scan the other panel responds to keys without a noticeable delay.
- **SC-003**: Esc stops a running scan within 1 second, locally and on a server.
- **SC-004**: Every listed file's relative path can be read in the status bar in one step, by moving
  the cursor to it.
- **SC-005**: Copying, moving, deleting and renaming from branch view always change the exact file
  shown, also among files with the same name. A GUI test confirms this on duplicate names.

## Assumptions

- **Exit:** ⌃B again returns to the normal listing. The sources did not confirm whether Total
  Commander does this, so it follows the maintainer's agreement. ".." and ⌫ go to the parent folder,
  as in a normal listing.
- **Selected items:** following Total Commander's Ctrl+Shift+B, the variant for marked items lists
  the marked files themselves as well as the contents of the marked folders.
- **No shortcut for the variant:** ⌃⇧B is not used. Chords with ⌃⇧ are taken by Dell Display Manager
  on the maintainer's machine, and ⌃⇧B has no macOS convention.
- **No folder structure:** copying from branch view is flat. "Keep folder structure" is not
  offered.
- **Servers:** server branches are listed folder by folder over the existing connection. Their speed
  depends on the server, so SC-002 applies to local folders only.

## Out of Scope

- A tree view.
- Listing folders in the branch view. Total Commander's plugin "Branch View Extended" does that.
- A relative-path column.
- Filtering the branch view by a mask. Find covers that.
- Automatic refresh when files change in subfolders.
- Keeping the folder structure when copying.
- Restoring branch view at launch.
