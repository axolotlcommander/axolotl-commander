# Feature Specification: Link Commands, Go to Link Target and Change Attributes

**Feature Branch**: `005-unix-link-commands`

**Created**: 2026-10-08

**Status**: Implemented

**Input**: User description: "The menus should have at least a command to create a symbolic link,
and the other Unix-specific things a file manager must have. Find out what we should have, write
a spec and make it as standard and expected as possible." Agreed in chat: New Symbolic Link,
New Hard Link, Edit Symbolic Link, Paste as Symbolic Link, Go to Link Target and a direct
Change Attributes command; owner/group changes, servers, archives and panel columns are out of
scope.

## Clarifications

### Session 2026-10-08

- Q: Where is a new link created? → A: As in common Unix two-panel file managers (Midnight
  Commander, Double Commander, Total Commander): in the other panel's folder, pointing to the item
  under the cursor (or the selected items) in the active panel. The name and folder can be edited
  in the sheet.
- Q: May a new link replace an existing item with the same name? → A: Never. One item: the sheet
  stays open with a message. Several items: the conflicting ones are skipped and listed.
- Q: Should Paste as Symbolic Link (the counterpart of the reference's Paste Shortcut) be part of
  this feature? → A: Yes (User Story 3).
- Q: Changing owner and group? → A: Out of scope: it needs administrator rights and the app does
  not elevate privileges.
- Q: Is a relative target computed from the folder path as the panel shows it? → A: No, from the
  real folders, because the system follows ".." physically; a panel folder reached through a link
  otherwise gets dangling links. Absolute targets are stored exactly as typed (FR-006, FR-012).
  Recorded during implementation (code review).
- Q: Is Go to Link Target available in search results? → A: No, as FR-017 says ("in a local
  folder"); the alias state comes from the folder listing. Recorded during implementation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a symbolic link (Priority: P1)

The user puts the cursor on a file or folder in the active panel and chooses File → New Symbolic
Link… (⌃⌘L). A sheet offers the link's target (the item) and its name in the other panel's
folder. Confirming creates the link there; the other panel shows it with the cursor on it. With
several selected items, one link per item is created in the chosen folder. A "Relative path"
option stores a path relative to the link's folder instead of an absolute one.

**Why this priority**: Creating symbolic links is the most common Unix-specific file task that the
app cannot do today; it is the reason for this feature.

**Independent Test**: In the test copy of the app, with the left panel in `<test>/a` on
`file.txt` and the right panel in `<test>/b`, press ⌃⌘L and Return; `<test>/b/file.txt` is a
symbolic link whose stored target is the absolute path of `<test>/a/file.txt`.

**Acceptance Scenarios**:

1. **Given** the cursor on `file.txt` in `<test>/a` (active, left) and the right panel in
   `<test>/b`, **When** the user presses ⌃⌘L, **Then** a sheet opens with "Target" =
   `<test>/a/file.txt`, "Link name" = `<test>/b/file.txt` and "Relative path" in its remembered
   state (off the first time).
2. **Given** that sheet, **When** the user presses Return, **Then** `<test>/b/file.txt` is a
   symbolic link to `<test>/a/file.txt`, the right panel shows it with the cursor on it, and
   nothing else changes.
3. **Given** the same sheet with "Relative path" on, **When** the user confirms, **Then** the
   stored target is `../a/file.txt`; the next time the sheet opens, "Relative path" is on.
4. **Given** `<test>/b/file.txt` already exists, **When** the user confirms the sheet, **Then** an
   inline message says an item with that name already exists, the sheet stays open, and the
   existing item is unchanged.
5. **Given** three selected items in `<test>/a`, **When** the user presses ⌃⌘L and confirms,
   **Then** the sheet showed the destination folder `<test>/b` (not a name), and three links with
   the items' names exist there; if one name already existed, that item was skipped and a
   summary lists it.
6. **Given** the user typed a target that does not exist, **When** the user confirms, **Then** the
   app asks whether to create the link anyway; "Create" creates the dangling link, "Cancel"
   returns to the sheet.
7. **Given** the active panel shows a server, an archive or search results, **When** the user
   opens the File menu, **Then** New Symbolic Link… is disabled.

---

### User Story 2 - Go to a link's target (Priority: P1)

With the cursor on a symbolic link or a Finder alias, the user chooses Commands → Go to Link
Target (⌃T). For a file target, the panel opens the folder containing the target and puts the
cursor on it; for a folder target, the panel opens that folder.

**Why this priority**: Links are only useful if the user can see where they lead; the reference
offers this command (Ctrl+T) and Finder offers Show Original.

**Independent Test**: In the test copy of the app, with the cursor on a link `<test>/b/file.txt`
to `<test>/a/file.txt`, press ⌃T; the panel shows `<test>/a` with the cursor on `file.txt`, and
Back returns to `<test>/b`.

**Acceptance Scenarios**:

1. **Given** the cursor on a symbolic link to a file, **When** the user presses ⌃T, **Then** the
   active panel shows the target's folder with the cursor on the target, and Back returns to the
   link's folder with the cursor on the link.
2. **Given** the cursor on a symbolic link to a folder, **When** the user presses ⌃T, **Then** the
   active panel shows the contents of the target folder (by its real path, not through the link).
3. **Given** a chain link1 → link2 → file, **When** the user presses ⌃T on link1, **Then** the
   panel goes to the final file.
4. **Given** a Finder alias to a file, **When** the user presses ⌃T, **Then** the panel goes to the
   original file as in scenario 1.
5. **Given** a broken link or a link loop, **When** the user presses ⌃T, **Then** a message says
   the target does not exist or cannot be resolved, naming the stored target, and the panel
   stays where it was.
6. **Given** the cursor on an ordinary file or on "..", **When** the user opens the Commands menu,
   **Then** Go to Link Target is disabled.

---

### User Story 3 - Paste copied items as symbolic links (Priority: P1)

The user copies items (⌘C in the app, or Copy in Finder), goes to another folder and chooses
Edit → Paste as Symbolic Link (⌃⌘V or ⌃S). One symbolic link per copied item is created in the
active panel's folder, with the item's name and its absolute path as the target.

**Why this priority**: It is the reference's Paste Shortcut adapted to macOS and the fastest way to
link several items from different places.

**Independent Test**: In the test copy of the app, select two files in `<test>/a`, press ⌘C, go to
`<test>/b` and press ⌃⌘V; two symbolic links with the files' names and absolute targets appear in
`<test>/b`.

**Acceptance Scenarios**:

1. **Given** two files copied with ⌘C and the active panel in `<test>/b`, **When** the user presses
   ⌃⌘V, **Then** two links with the files' names exist in `<test>/b`, pointing to the files'
   absolute paths, and the panel shows them with the cursor on the first.
2. **Given** one of the names already exists in `<test>/b`, **When** the user pastes as links,
   **Then** that item is skipped (the existing item is unchanged), the other link is created and a
   summary lists the skipped name.
3. **Given** the clipboard holds no files (for example only text), **When** the user opens the Edit
   menu, **Then** Paste as Symbolic Link is disabled.
4. **Given** the active panel shows a server or an archive, **When** the user opens the Edit menu,
   **Then** Paste as Symbolic Link is disabled.

---

### User Story 4 - Change attributes directly (Priority: P2)

The user selects items and chooses File → Change Attributes… (⌃F2). The existing attributes
editor (permissions incl. octal, locked, hidden, tags, dates with "Now", recursion into folders)
opens directly as a sheet, without going through Get Info.

**Why this priority**: Changing permissions is a daily Unix task; the editor exists but is hidden
behind Get Info. The reference has this command on Ctrl+F2.

**Independent Test**: In the test copy of the app, select a file in `<test>`, press ⌃F2, turn on
"Execute" for the owner and click Apply; the file's mode gains the owner execute bit.

**Acceptance Scenarios**:

1. **Given** two selected files, **When** the user presses ⌃F2, **Then** the attributes editor
   opens as a sheet for both files with the same content and behavior as Get Info → edit.
2. **Given** the editor with changes, **When** the user clicks Apply, **Then** the changes are
   applied as today; **When** the user clicks Cancel or presses Escape, **Then** nothing changes.
3. **Given** the cursor on ".." with nothing selected, or a server or archive panel, **When** the
   user opens the File menu, **Then** Change Attributes… is disabled.

---

### User Story 5 - Create a hard link (Priority: P2)

The user puts the cursor on a file and chooses File → New Hard Link…. The same sheet as for a
symbolic link appears (without "Relative path", the target is fixed). Confirming creates a second
name for the same file in the other panel's folder.

**Why this priority**: Hard links are a standard Unix tool, less frequent than symbolic links.

**Independent Test**: In the test copy of the app, with the cursor on `<test>/a/file.txt` and the
right panel in `<test>/b`, choose New Hard Link… and confirm; `<test>/b/file.txt` is the same file
(same identity, link count 2).

**Acceptance Scenarios**:

1. **Given** the cursor on a file and the other panel on the same volume, **When** the user
   chooses New Hard Link… and confirms, **Then** a hard link with the file's name exists in the
   other panel's folder and the other panel shows it with the cursor on it.
2. **Given** the cursor on a folder or on a symbolic link, **When** the user confirms the sheet,
   **Then** a message explains that only files can have hard links, and nothing is created.
3. **Given** the other panel on a different volume, **When** the user confirms, **Then** a message
   explains that hard links must be on the same volume as the file, and nothing is created.
4. **Given** several selected items of which one is a folder, **When** the user confirms, **Then**
   links are created for the files and a summary lists the folder as skipped.
5. **Given** the name already exists, **Then** the behavior is the same as User Story 1
   scenario 4 (single) or 5 (several).

---

### User Story 6 - Edit a symbolic link (Priority: P3)

With the cursor on a symbolic link, the user chooses File → Edit Symbolic Link…. A sheet shows
the target exactly as stored (absolute or relative) and lets the user change it. Applying
replaces the link in one step; the link never disappears and the old or new target is never
touched.

**Why this priority**: Useful for repairing or retargeting links (Midnight Commander has it); the
user can also delete and recreate a link, so it comes last.

**Independent Test**: In the test copy of the app, with the cursor on a link to `<test>/a/file.txt`,
choose Edit Symbolic Link…, change the target to `<test>/a/other.txt` and apply; the link now
points to `other.txt` and both files are unchanged.

**Acceptance Scenarios**:

1. **Given** the cursor on a symbolic link with a relative stored target `../a/file.txt`, **When**
   the user opens Edit Symbolic Link…, **Then** the target field shows `../a/file.txt` and
   "Relative path" is on.
2. **Given** the sheet, **When** the user changes the target and applies, **Then** the link has
   the new target, keeps its name and stays selected, and no other item changes.
3. **Given** "Relative path" toggled, **When** the user applies, **Then** the stored target is the
   same location expressed relatively (or absolutely).
4. **Given** a new target that does not exist, **When** the user applies, **Then** the same
   question as User Story 1 scenario 6 is asked.
5. **Given** the cursor on an ordinary file or a Finder alias, **When** the user opens the File
   menu, **Then** Edit Symbolic Link… is disabled.

---

### Edge Cases

- **Typed link name with a folder path** (e.g. `<test>/c/name`): the link is created at that path
  when its folder exists; otherwise an error names the missing folder and nothing is created.
- **Empty name, a name with only spaces, "." or ".."**: the sheet refuses it with an inline
  message.
- **Special characters**: targets and names with spaces, non-ASCII letters or quotes are stored
  exactly as shown.
- **Link to a link**: the cursor item is itself a symbolic link → the new symbolic link points to
  that link (its path), not to the link's target, as `ln -s` does.
- **Link to the containing folder or to a parent**: allowed; it is a link, not a copy.
- **Both panels in the same folder**: a single item's prefilled name already exists → the inline
  conflict message appears and the user edits the name; several items are all skipped and listed.
- **The other panel is not a local folder** (server, archive, search results): the link name is
  prefilled in the active panel's folder (and therefore conflicts until renamed); the
  several-items sheet prefills the active panel's folder.
- **Relative path across volumes**: still computed as a path (e.g. `../../Volumes/X/file`); it is
  just text.
- **Read-only volume, no permission**: the system's reason is shown; nothing else changes.
- **Hidden items** (leading dot, hidden flag): handled like any other item; whether the new link
  is visible follows the panel's hidden-files setting.
- **Folder links and Enter**: unchanged; Enter on a link to a folder still opens it through the
  link (the path shows the link), while Go to Link Target opens the real folder.
- **Clipboard items that no longer exist**: Paste as Symbolic Link still creates the links (they
  are dangling) — the user explicitly copied them; no question is asked for pasted items.
- **Paste as Symbolic Link into the items' own folder**: every name exists → all are skipped and
  listed.

## Requirements *(mandatory)*

### Functional Requirements

**New Symbolic Link**

- **FR-001**: The File menu MUST contain "New Symbolic Link…" after "New Folder…", with the
  default shortcut ⌃⌘L, also offered in the panel's context menu.
- **FR-002**: The command MUST act on the active panel's selected items, or on the item under the
  cursor when nothing is selected; ".." is never a source.
- **FR-003**: For one item, the sheet MUST show an editable "Target" (prefilled with the item's
  absolute path), an editable "Link name" (prefilled with the other panel's folder + the item's
  name; when the other panel does not show a local folder, the active panel's folder + the
  item's name) and a "Relative path" checkbox.
- **FR-004**: For several items, the sheet MUST show the list size, an editable destination folder
  (prefilled like FR-003) and the "Relative path" checkbox; one link per item MUST be created in
  that folder with the item's own name.
- **FR-005**: The "Relative path" choice MUST be remembered between uses (shared by New Symbolic
  Link and Edit Symbolic Link) and is off the first time.
- **FR-006**: With "Relative path" on, the stored target MUST be the path of the target relative
  to the folder that contains the link; with it off, the absolute path. A target the user typed
  as a relative path MUST be stored exactly as typed (the checkbox does not change it).
- **FR-007**: A target that does not exist MUST lead to a question (Create / Cancel) before a
  single link is created; Cancel returns to the sheet.

**New Hard Link**

- **FR-008**: The File menu MUST contain "New Hard Link…" after "New Symbolic Link…", with no
  default shortcut (assignable in Keyboard Shortcuts), also offered in the context menu.
- **FR-009**: The sheet MUST follow FR-002–FR-004 with the target not editable and without
  "Relative path".
- **FR-010**: Only regular files MAY be hard-linked (a Finder alias is a regular file); folders,
  packages (bundles shown as one item) and symbolic links MUST be refused with an explanation.
  The new name MUST be on the same volume as the file, otherwise an explanation is shown. With
  several items the refused ones are skipped and listed.

**Edit Symbolic Link**

- **FR-011**: The File menu MUST contain "Edit Symbolic Link…" after "New Hard Link…", no default
  shortcut, also in the context menu, enabled only when the cursor item is a symbolic link in a
  local folder.
- **FR-012**: The sheet MUST show the stored target exactly (relative or absolute) and the
  "Relative path" checkbox reflecting it; toggling the checkbox MUST convert the shown target
  between the relative and absolute form of the same location.
- **FR-013**: Applying MUST replace the link so that at every moment a link with that name exists
  (the old one until the new one takes its place); no other item, including the old and new
  target, MAY be changed. FR-007 applies to the new target.

**Paste as Symbolic Link**

- **FR-014**: The Edit menu MUST contain "Paste as Symbolic Link" after "Move Files Here", with the
  default shortcuts ⌃⌘V and ⌃S, also in the context menu.
- **FR-015**: It MUST create, in the active panel's folder, one symbolic link per file or folder
  on the clipboard (from the app's Copy Files or from other apps), named like the item and
  storing the item's absolute path, without a sheet and without the FR-007 question.
- **FR-016**: The command MUST be enabled only when the clipboard holds at least one file location
  and the active panel shows a local folder.

**Go to Link Target**

- **FR-017**: The Commands menu MUST contain "Go to Link Target" with the default shortcut ⌃T,
  also in the context menu, enabled only when the cursor item is a symbolic link or a Finder alias
  in a local folder.
- **FR-018**: The target MUST be resolved completely (chains of links, relative targets against the
  link's folder, aliases). A file target MUST open its folder in the active panel with the cursor
  on it; a folder target MUST open the folder itself; both by real path and recorded in
  Back/Forward history.
- **FR-019**: A missing target or a loop MUST show a message naming the stored target; the panel
  MUST stay unchanged.

**Change Attributes**

- **FR-020**: The File menu MUST contain "Change Attributes…" after "Get Info", with the default
  shortcut ⌃F2, also in the context menu.
- **FR-021**: It MUST open the existing attributes editor for the selected items (or the cursor
  item) as a sheet of the main window, with the same contents, rules and Apply behavior as the
  editor reached from Get Info; Cancel and Escape change nothing.
- **FR-022**: It MUST be disabled for ".." with no selection, on servers, in archives and in search
  results.

**Common rules**

- **FR-023**: No command of this feature MAY delete, move, overwrite or replace an existing item,
  except that Edit Symbolic Link replaces the edited link itself (FR-013).
- **FR-024**: An existing name MUST never be replaced: one item → inline message, the sheet stays
  open; several items → those items are skipped and a summary lists every skipped item with its
  reason after the others are created.
- **FR-025**: Link-creating commands MUST be disabled unless the active panel shows a local folder
  (not a server, archive or search results); a typed destination MUST be a local folder.
- **FR-026**: After a command creates or changes items, every panel showing the affected folder
  MUST refresh; for a single new link, the panel showing the destination puts the cursor on it.
- **FR-027**: System errors (no permission, read-only volume, invalid name, missing folder) MUST be
  shown with the system's reason; items already created stay, nothing else changes.
- **FR-028**: Every new command MUST appear in Keyboard Shortcuts and be available as a toolbar
  item through Customize Toolbar, like existing commands; none is added to the default toolbar.
- **FR-029**: New texts MUST exist in English and Czech; sheets MUST be fully usable from the
  keyboard (Tab, Return confirms, Escape cancels) and accessible (labelled fields).

### Deviations from the reference program

- **D-001 (FR-001–FR-013)**: The reference (Windows) has no commands to create symbolic or hard
  links or to edit a link; they follow common Unix two-panel file managers.
- **D-002 (FR-014, FR-015)**: The reference's Paste Shortcut (Ctrl+S) creates Windows shortcuts;
  here it creates symbolic links, and ⌃⌘V is added next to ⌃S.
- **D-003 (FR-017, FR-018)**: The reference's Go to Shortcut or Link Target handles Windows
  shortcuts and junctions; here symbolic links and Finder aliases. A folder target is opened by
  its real path.
- **D-004 (FR-020, FR-021)**: The reference's Change Attributes dialog shows Windows attributes;
  here it is the app's existing permissions/attributes editor.

### Key Entities

- **Link request**: sources (one or more items), destination (a full name for one item, a folder
  for several), stored-target form (absolute or relative), kind (symbolic or hard).
- **Link outcome**: per item, created / skipped with a reason (name exists, folder, symbolic link,
  other volume, system error).
- **Stored target**: the text a symbolic link holds, exactly as written (relative or absolute); the
  resolved target is the final existing item after following every link or alias.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A symbolic link to the item under the cursor can be created in the other panel's
  folder with two keystrokes (⌃⌘L, Return).
- **SC-002**: In every scenario of this specification, no existing item other than an edited link
  is deleted, moved or changed (verified by comparing the scratch folder before and after).
- **SC-003**: Go to Link Target reaches the final target of a chain of at least three links in one
  command, and Back returns to the starting place in one command.
- **SC-004**: Ten items copied on the clipboard become ten links with one paste command; conflicts
  are reported in a single summary, not ten dialogs.
- **SC-005**: The permissions editor is reached in one command (⌃F2) instead of two steps.
- **SC-006**: Every new command is disabled in all situations where it cannot act (server, archive,
  search results, "..", wrong item type, empty clipboard), checked in the menus.
- **SC-007**: All acceptance scenarios pass in the test copy of the app using only the keyboard
  and mouse, inside a scratch folder.

## Assumptions

- The app runs on macOS 15 or later on APFS or HFS+ volumes, which support symbolic and hard links;
  volumes that do not (some network or FAT volumes) report an error that is shown as such.
- "Local folder" means a folder of the Mac's file system shown directly (including mounted network
  volumes and iCloud Drive), not a server connection, an archive or a search-results listing.
- The existing attributes editor and its data-safety rules are reused unchanged.
- The clipboard format written by Copy Files (⌘C) is the standard file-location format that Finder
  also writes and reads.
- Shortcuts ⌃⌘L, ⌃⌘V, ⌃S, ⌃T and ⌃F2 are free in the default key map.
