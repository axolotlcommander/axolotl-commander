# Feature Specification: Small Commands

**Feature Branch**: `015-small-commands`

**Created**: 2026-10-13

**Status**: Implemented

**Input**: User description: "Small commands from classic two-panel file managers: copy in the same
folder under a new name, a new folder in the other panel, view only the cursor file, pack and move,
test archives, the name with full path, the size of marked items, marking without moving, and
selecting files only."

## Context

The research note on classic keys (local) lists small commands the app lacks. The scope was agreed in
chat on 2026-10-12 (the list of specs 010–016). Each command is small, so they share one spec. Every
command gets a menu item and a free default chord where one exists; keys that mean something else in
the app today go into the Classic Commander scheme only. This spec ships with specs 010–016 in one
release.

## Clarifications

### Session 2026-10-13

All answers below were *decided while the maintainer was away; confirmed by the maintainer on 2026-10-13*.

- Q: What does Copy As offer as the name? → A: "‹name› copy.‹ext›" (folders: "‹name› copy"), so
  Return makes a copy at once, as Finder's Duplicate does; the whole name is selected for typing a new
  one.
- Q: Does Copy As work on the marked items? → A: No, on the cursor item only, because it asks for one
  name. Marks stay.
- Q: Which name does New Folder in Other Panel offer? → A: The cursor item's name: a folder's name, a
  file's name without its extension; empty on "..".
- Q: Where do Pack and Move's originals go? → A: To the Trash, and only after the archive was written
  without an error. Into an existing archive it works like Move (F6) into it.
- Q: How are encrypted archives tested? → A: As Unpack does: the app asks for the password; Cancel
  marks that archive "not tested".
- Q: Keys? → A (factory / Classic Commander):
  - Copy As…: ⇧F5 / ⇧F5;
  - New Folder in Other Panel…: ⌥⌘N / ⌥⌘N and ⇧F7 (Go to Folder… keeps ⇧⌘G there);
  - View Cursor File Only: ⌥⇧F3 / ⇧F3 and ⌥⇧F3 (Show in Finder keeps the menu there);
  - Pack and Move…: ⌥⇧F5 in both;
  - Test Archives: ⌥⇧F9 in both;
  - Insert Full Path: ⌃⇧J added next to ⌃⇧↩ in both;
  - Calculate Folder Sizes: ⌃L added in Classic Commander (Volume Information… keeps the menu there);
  - Toggle Selection Without Moving: ⌥⇧↑ in both;
  - Select All Files / Deselect All Files: ⌃⇧Num+ / ⌃⇧Num− in both.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Copy a file next to itself under a new name (Priority: P1)

A user wants a backup of `config.json` in the same folder. They press ⇧F5, the app offers
`config copy.json`, they type `config.old.json` and press Return. The copy appears next to the original
with the cursor on it.

**Why this priority**: the most used of the small commands; today it needs F5 to the other panel and a
rename.

**Independent Test**: in a test folder, Copy As a file and a folder; check names and contents; try the
original name and an existing name.

**Acceptance Scenarios**:

1. **Given** the cursor is on `a.txt`, **When** the user runs Copy As… and confirms the offered name,
   **Then** `a copy.txt` exists with the same content and the cursor is on it.
2. **Given** the cursor is on folder `docs`, **When** the user confirms `docs2`, **Then** `docs2` holds a
   copy of the whole tree, with the inner names unchanged.
3. **Given** the user types the original name, **When** they confirm, **Then** nothing is copied and the
   app reports that an item cannot be copied onto itself.
4. **Given** the user types the name of another existing item, **When** they confirm, **Then** the
   app asks before overwriting, as Copy does.
5. **Given** marked items and the cursor on `b.txt`, **When** the user runs Copy As…, **Then** only
   `b.txt` is copied and the marks stay.

---

### User Story 2 - New folder in the other panel (Priority: P2)

The user stands on `photos-2026.zip` and wants a folder of that name in the other panel to unpack
into. They press ⌥⌘N (⇧F7 in Classic Commander), confirm `photos-2026`, and the other panel shows
the new folder with its cursor on it, while the focus stays in the active panel.

**Why this priority**: a common step before copying or unpacking, now without switching panels.

**Independent Test**: run it with the cursor on a file, a folder and ".."; check the other panel.

**Acceptance Scenarios**:

1. **Given** the cursor is on `photos-2026.zip`, **When** the user runs the command, **Then** the
   offered name is `photos-2026`.
2. **Given** the user confirms, **When** the folder is made, **Then** the other panel shows it under
   its cursor and the focus stays in the active panel.
3. **Given** the other panel shows an archive or a server folder, **When** the user runs it, **Then**
   the folder is made there, as New Folder… does in that panel.
4. **Given** the other panel shows find results, the branch view or the Network folder, **Then** the
   command is disabled.

---

### User Story 3 - View the cursor file only (Priority: P2)

With five files marked, the user wants to look at the file under the cursor without stepping through
the marked ones. View Cursor File Only opens the viewer with that file alone.

**Why this priority**: small, but F3's behavior with marks surprises users of classic managers.

**Independent Test**: mark files, run the command, check that the viewer cannot move to other files.

**Acceptance Scenarios**:

1. **Given** marked files and the cursor on `c.txt`, **When** the user runs View Cursor File Only,
   **Then** the viewer shows `c.txt` and the next/previous file commands have nothing to go to.
2. **Given** the cursor is on a folder or "..", **Then** the command is disabled.

---

### User Story 4 - Pack and move into an archive (Priority: P2)

A user packs old logs and wants them gone from the folder. Pack and Move… asks for the archive like
Pack… does; after packing the originals go to the Trash.

**Why this priority**: a classic command that saves a separate delete; it removes data, so it is careful.

**Independent Test**: in a test folder, pack and move two files; check the archive content and that the
originals are in the Trash (by the app's undo-free check: they are no longer in the folder and the
archive lists them).

**Acceptance Scenarios**:

1. **Given** two marked files, **When** the user confirms Pack and Move…, **Then** the archive holds
   both and the originals are moved to the Trash.
2. **Given** packing fails (for example the target folder is read-only), **Then** no original is
   touched and the error is shown.
3. **Given** the target archive exists, **Then** the items are moved into it as Move (F6) into an open
   archive does.
4. **Given** the panel shows an archive or a server folder, **Then** the command is disabled.

---

### User Story 5 - Test archives (Priority: P2)

A user downloaded several archives and wants to know they are complete. Test Archives reads every
marked archive through, checking its data, and reports the result.

**Why this priority**: useful and safe (read-only), but rarely needed.

**Independent Test**: test a good zip and a damaged copy of it in a test folder.

**Acceptance Scenarios**:

1. **Given** marked archives that are fine, **When** the user runs Test Archives, **Then** a progress
   window shows and the result says all of them are OK.
2. **Given** one archive is damaged, **Then** the result names it with the problem; the others are
   reported OK.
3. **Given** an encrypted archive, **Then** the app asks for the password as Unpack does; Cancel
   reports that archive as not tested.
4. **Given** the marked items include files that are not archives, **Then** they are left out of the
   test; with no archive at all the command is disabled.

---

### User Story 6 - Selection and command line helpers (Priority: P3)

Small habits: ⌃⇧J inserts the cursor item's full path into the command line (like ⌃⇧↩);
⌥⇧↑ marks or unmarks the cursor item without moving; ⌃⇧Num+ and ⌃⇧Num− select and deselect all files
and leave folders as they are; in Classic Commander ⌃L calculates the size of the marked items.

**Why this priority**: each is tiny; together they complete the classic keyboard.

**Independent Test**: try each key in a test folder and check marks, the command line and the status
line.

**Acceptance Scenarios**:

1. **Given** the cursor on `a.txt`, **When** the user presses ⌃⇧J, **Then** the command line gets
   `a.txt`'s full path (quoted when needed).
2. **Given** the cursor on `a.txt`, **When** the user presses ⌥⇧↑ twice, **Then** the item is marked
   then unmarked and the cursor stays.
3. **Given** a folder with files and subfolders, **When** the user runs Select All Files, **Then** every
   file is marked and no folder; Deselect All Files unmarks the files and keeps folder marks.
4. **Given** Classic Commander and marked folders, **When** the user presses ⌃L, **Then** their sizes
   are calculated and the status line shows the total, as Calculate Folder Sizes does.

---

### Edge Cases

- **Copy As in find results or the branch view**: the copy goes next to the original, in its own folder.
- **Copy As inside an archive or on a server**: disabled (local disk only, like Duplicate in Finder).
- **Copy As with a name containing "/"**: refused with the name error, as Rename does.
- **New Folder in Other Panel with an existing name**: the error is shown, as New Folder… shows it.
- **View Cursor File Only on a package or a file the viewer leaves to Quick Look**: behaves as F3 does
  for that file.
- **Pack and Move with folders**: whole folders are packed and then moved to the Trash.
- **Pack and Move with special files** (pipes, sockets, devices): they are not packed, so they stay
  where they are; only what the archive holds goes to the Trash.
- **Pack and Move when the Trash is not available** (some network volumes): the archive stays, the
  originals stay, and the app reports that they could not be moved to the Trash.
- **Test Archives with a long archive**: the progress window can cancel; the result then says the test
  was cancelled.
- **Select All Files with the quick filter**: only visible files are marked (as Select All does).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Copy As… (File menu, after Copy…) MUST ask for a new name, offering "‹base› copy.‹ext›"
  (folders "‹name› copy"), and copy the cursor item into its own folder under that name, the whole tree
  for a folder. It MUST refuse the item's own name and ask before overwriting another existing item. It
  MUST be disabled on "..", in archives, on servers and in the Network folder. It MUST put the cursor
  on the copy.
- **FR-002**: New Folder in Other Panel… (File menu, after New Folder…) MUST ask for a name, offering the
  cursor item's name (a file without its extension, empty on ".."), create the folder in the other
  panel's folder (also in an archive or on a server), put the other panel's cursor on it and keep the
  focus. It MUST be disabled when the other panel shows find results, the branch view or the Network
  folder.
- **FR-003**: View Cursor File Only (File menu, after View) MUST open the viewer with only the cursor
  file, ignoring marks. It MUST be disabled on folders and "..".
- **FR-004**: Pack and Move… (File menu, after Pack…) MUST ask like Pack…. After the archive is written
  without an error it MUST move the packed items to the Trash; on any packing error it MUST leave them.
  Into an existing archive it MUST work like Move into an open archive. It MUST be disabled in archives,
  on servers and in the Network folder.
- **FR-005**: Test Archives (File menu, after Unpack…) MUST read every marked archive (or the cursor
  archive) completely, checking the data, with a cancellable progress window, and then report per
  archive: OK, the problem, or not tested (password cancelled). Marked items that are not archives are
  left out. It MUST NOT write
  anything. It MUST be disabled in archives, on servers and in the Network folder.
- **FR-006**: Insert Full Path MUST also be bound to ⌃⇧J.
- **FR-007**: Toggle Selection Without Moving MUST mark or unmark the cursor item and keep the cursor;
  on ".." it does nothing.
- **FR-008**: Select All Files and Deselect All Files (Edit menu) MUST mark / unmark all visible files
  and leave folders as they are.
- **FR-009**: Factory chords and the Classic Commander changes MUST be as in Clarifications, and no
  chord MUST be bound twice in one context in either scheme.

### Key Entities

- **Archive test result**: an archive and its outcome (OK, problem with a message, not tested).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A copy under a new name in the same folder takes one chord, a name and Return.
- **SC-002**: Pack and Move never removes an original when the archive was not written (automated test
  on the core rule).
- **SC-003**: Test Archives finds a damaged archive (automated test with a corrupted zip).
- **SC-004**: Copy As of a folder keeps the inner names (automated test).

## Assumptions

- The archive formats are those the app already reads and writes.
- "Size of the marked items" is the existing Calculate Folder Sizes, whose status line shows the total.

## Out of Scope

- Split and combine files, encode and decode.
- Saving selections to a file.
- Copy As for several items at once (with a name mask; Copy… already has the mask).

## Deviations from the classic reference

- Pack and Move moves the originals to the Trash instead of deleting them.
- Copy As offers "‹name› copy" instead of the same name.
- New Folder in Other Panel and View Cursor File Only have free factory chords; ⇧F7 and ⇧F3 only in
  Classic Commander. ⌃L only in Classic Commander.
