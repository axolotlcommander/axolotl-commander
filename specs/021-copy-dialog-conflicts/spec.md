# Feature Specification: Copy Dialog and Replace Question

**Feature Branch**: `021-copy-dialog-conflicts`

**Created**: 2026-10-13

**Status**: Implemented

**Input**: User description: "Copy dialog and replace question: richer choices when a file already
exists, and a faster way to pick and name the destination of F5/F6." (Proposal written in chat from the
gap list of docs/research; the maintainer agreed to all of it on 2026-10-13: "jo jak doporučuješ".)

## Context

When a copy, move, extraction from an archive or a server transfer meets a file that already exists,
the app asks "“x.txt” already exists." The question shows the size and date of both files and offers
Overwrite, Overwrite All, Skip, Skip All and Cancel. The arrow keys move the default button and Return
presses it; Esc cancels (both arrived in 0.5.0, before this spec). The user cannot see what the two
files contain, and the only way to keep both is to cancel and rename by hand.

The F5/F6 dialog offers a "To:" field filled with the other panel's folder and a "Name mask:" field
(default `*.*`). Any other destination has to be typed, and renaming one file while copying it needs a
mask.

Classic two-panel file managers let the user look into both files from the replace question, compare
them, overwrite only older files and rename the new one. Their copy dialog offers a list of
destinations and, for one file, the destination already contains the name.

This spec ships in release 0.5.0, on top of the dialog arrow keys and the ⇧F2 / ⌃F10 compare split.

## Clarifications

### Session 2026-10-13

- Q: Which parts? → A: All of the proposal: look into both files (F3, ⇧F3), compare them (⌥F3), the
  "newer"/"larger" marks, the More… choices (Overwrite All Older, Rename…, Rename Automatically, Rename
  All Automatically), the destination menu, ⌃D in the dialog, and the name in "To:" for one item with the
  F5/F6 selection cycle.
- Q: Look into files in an archive or on a server? → A: Yes: they are fetched into a temporary local copy
  first, as F3 in a panel does.
- Q: Automatic names? → A: Like the Finder: "x 2.txt", "x 3.txt".
- Q: Compare key? → A: ⌥F3, since ⌃F3 sorts by name.
- *Decided while planning; confirmed by the maintainer on 2026-10-13*:
  - Adding to an archive keeps its own question for all existing members at once (Overwrite / Skip /
    Cancel), since the archive is rewritten in one pass. The replace question of this spec covers copy,
    move, extraction, downloads and uploads.
  - When extracting, the new file is already a local temporary copy, so ⇧F3 opens it without another
    fetch.
  - Rename… refuses a taken name at once for local destinations; on a server the replace question comes
    back for that name instead (no extra listing of the server folder).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Look into both files before deciding (Priority: P1)

A user copies a folder of documents into a backup. The replace question appears for "report.md". The
user presses F3 to read the existing file, closes the viewer, presses ⇧F3 to read the new one, then ⌥F3
to see the differences side by side, and finally chooses Overwrite.

**Why this priority**: deciding blind is the main risk of the question; looking costs a key press.

**Independent Test**: in a scratch folder, copy a file onto an older copy with different content; use
F3, ⇧F3 and ⌥F3 from the question; repeat with a source inside a zip archive and on a test server.

**Acceptance Scenarios**:

1. **Given** the replace question for two files, **When** the user presses F3, **Then** the existing file
   opens in the viewer; **When** the viewer closes, **Then** the question is in front again with the same
   default button.
2. **When** the user presses ⇧F3, **Then** the new (source) file opens in the viewer.
3. **When** the user presses ⌥F3, **Then** Compare Files opens with the existing file on the left and the
   new file on the right.
4. **Given** the source is in an archive or on a server, **When** the user presses ⇧F3 or ⌥F3, **Then**
   the file is fetched into a temporary copy first, with the progress and cancel behavior of F3 in a
   panel; cancelling the fetch returns to the question.
5. **Given** one side is a folder, **When** the user presses F3, ⇧F3 or ⌥F3, **Then** nothing opens and
   the app beeps once.
6. **Then** the question shows a hint line naming the three keys.

---

### User Story 2 - See which file is newer and larger (Priority: P1)

The question marks the newer date and the larger size, so the user does not have to compare numbers.

**Independent Test**: conflicts with a newer source, an older source, equal dates and equal sizes.

**Acceptance Scenarios**:

1. **Given** the new file is newer and larger, **Then** its date line carries "newer" and its size
   carries "larger".
2. **Given** the existing file is newer, **Then** the "newer" mark is on the existing side.
3. **Given** equal dates or equal sizes, **Then** that value has no mark.

---

### User Story 3 - Pick the destination from a list (Priority: P1)

The user presses F5 and wants a folder other than the other panel's. A menu next to "To:" (or ⌥↓ in the
field) lists the other panel's folder, the folders open in tabs, the hot paths and the recent
destinations. One choice fills the field.

**Independent Test**: open several tabs in both panels, define hot paths, copy to two folders, then open
the destination menu in a new F5 dialog.

**Acceptance Scenarios**:

1. **Given** the F5 or F6 dialog, **When** the user presses ⌥↓ in "To:" or clicks the menu button,
   **Then** a menu opens with the sections: the other panel's folder; the folders of the other panel's
   other tabs, then of this panel's tabs; hot paths; recent destinations.
2. **When** the user chooses an entry, **Then** the folder part of "To:" becomes that folder and the name
   part (for one item) stays.
3. **Given** a copy or move to a folder has started, **Then** that folder is first among the recent
   destinations the next time, also after a restart; the list keeps 10 folders without duplicates.
4. **Given** the user presses ⌃D in the dialog, **Then** the hot paths open directly.
5. **Then** no folder appears twice, the source panel's own folder is left out, empty sections are left
   out, and Network is never offered.

---

### User Story 4 - Rename one item while copying it (Priority: P1)

The user presses F5 on "notes.txt". "To:" shows ".../backup/notes.txt" with "notes" selected, so typing
"notes-old" and Return copies it under the new name. Pressing F5 again selects the extension, then the
folder, then everything.

**Independent Test**: F5 and F6 on one file, one folder and a file named "a.tar.gz"; type new names, an
existing folder and a path ending with "/".

**Acceptance Scenarios**:

1. **Given** one item, **When** the F5 or F6 dialog opens, **Then** "To:" holds the destination folder and
   the item's name, the name without its extension is selected, and the mask field is not shown.
2. **When** the user presses F5 (in the copy dialog) or F6 (in the move dialog) again, **Then** the
   selection moves: name → extension → folder part → whole text → name.
3. **Given** "To:" names an existing folder or ends with "/", **Then** the item goes into that folder
   under its own name.
4. **Given** "To:" names something that does not exist, **Then** its last part is the new name and the
   rest is the destination folder, which must exist (errors as today).
5. **Given** several items, **Then** "To:" holds the folder and the mask works as today.

---

### User Story 5 - Keep both files or overwrite only older ones (Priority: P2)

Copying photos into a folder with older copies, the user chooses More… → Overwrite All Older: newer
files replace older ones, the rest are skipped, and no more questions come. Another time the user
chooses Rename Automatically and gets "photo 2.jpg" next to "photo.jpg".

**Independent Test**: in a scratch folder, copy a set of files where some sources are newer, some older
and some equally old; try each More… choice.

**Acceptance Scenarios**:

1. **Given** the question, **When** the user moves to More… with the arrow keys and presses Return (or
   clicks it), **Then** a menu opens with Overwrite All Older, Rename…, Rename Automatically and Rename
   All Automatically.
2. **When** the user chooses Overwrite All Older, **Then** this and every later conflict of the operation
   overwrites when the new file is newer and skips otherwise (equal dates skip), without asking.
3. **When** the user chooses Rename…, **Then** a field asks for the new name, prefilled with the
   automatic name with its base part selected; an empty name, a name with "/" or a name that exists in
   the destination is refused with a message and the field stays (on a server a taken name brings the question back for that name); Cancel returns to
   the question.
4. **When** the user chooses Rename Automatically, **Then** the item is written under the first free name
   "name 2.ext", "name 3.ext"…; Rename All Automatically does the same for every later conflict.
5. **Given** a destination where renaming is not possible, **Then** the rename items are disabled.

---

### Edge Cases

- **Archives and servers**: the question, the marks and the More… choices work the same for extraction,
  downloads and uploads (adding to an archive keeps its own question, see Clarifications); looking into a file on such a side fetches a temporary
  copy, which is cleaned up as after F3 in a panel.
- **Moving a folder tree**: a rename applies to the item in conflict, not to the whole folder.
- **Automatic names that collide again** keep counting until a free name.
- **Names with several dots** ("a.tar.gz"): the extension is the part after the last dot, as elsewhere
  in the app; the automatic name is "a.tar 2.gz".
- **Folders and names without an extension**: the automatic name is "name 2"; F5/F6 cycles skip the
  extension step.
- **Very long names**: the automatic name stays within the file system's name limit by shortening the
  base part.
- **The viewer or Compare Files open while the question waits**: the question stays attached to its
  window; the user can return to it at any time; the operation waits.
- **Recent destinations that no longer exist** are left out of the menu.
- **One item in a flat listing** (branch view, find results): the name in "To:" is the item's name; the
  folder is the other panel's folder as today.
- **Hot paths empty**: the section is left out; ⌃D in the dialog beeps.
- **Copying one item onto itself or a folder into itself**: today's safeguards still apply after the name
  is read from "To:".
- **Both key schemes**: the keys are the same in both.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The replace question MUST open the existing file in the viewer on F3 and the new file on
  ⇧F3, and Compare Files for both (existing left, new right) on ⌥F3; the question MUST stay open and come
  back to the front when they close.
- **FR-002**: Files in an archive or on a server MUST be fetched into a temporary local copy before they
  are shown, with the same progress, cancel and cleanup as F3 in a panel.
- **FR-003**: When either side is a folder, F3, ⇧F3 and ⌥F3 MUST do nothing except one beep.
- **FR-004**: The question MUST show a hint line naming F3, ⇧F3 and ⌥F3.
- **FR-005**: The question MUST mark the newer modification date and the larger size with localized
  words; equal values MUST get no mark.
- **FR-006**: The question MUST offer a More… button before Cancel, reachable with the arrow keys, that
  opens a menu with Overwrite All Older, Rename…, Rename Automatically and Rename All Automatically.
- **FR-007**: Overwrite All Older MUST overwrite this and every later conflict of the same operation where
  the new file is newer than the existing one, and skip the rest, without further questions.
- **FR-008**: Rename… MUST ask for a new name prefilled with the automatic name, refuse empty names, names
  containing "/" and names that exist in the destination, and return to the question on Cancel.
- **FR-009**: Automatic names MUST be the first free name of the form "base N.ext" (N from 2), or "base N"
  without an extension, fitting the file system's name length limit.
- **FR-010**: Rename All Automatically MUST apply the automatic name to every later conflict of the same
  operation without asking.
- **FR-011**: Where a destination cannot take a renamed item, the rename choices MUST be disabled.
- **FR-012**: The F5/F6 dialog MUST offer a destination menu (a button next to "To:" and ⌥↓ in the field)
  with the other panel's folder, the folders of the other panel's tabs and of this panel's tabs, hot
  paths and recent destinations, without duplicates, without the source folder, without empty sections
  and without Network.
- **FR-013**: Choosing a destination MUST replace the folder part of "To:" and keep the name part.
- **FR-014**: The app MUST remember the last 10 destinations of started copy and move operations, newest
  first, without duplicates, across launches; they MUST NOT be part of the settings export. Folders that
  no longer exist MUST be left out of the menu.
- **FR-015**: ⌃D in the F5/F6 dialog MUST open the hot paths directly.
- **FR-016**: For one item, "To:" MUST hold the destination folder plus the item's name, with the name
  without extension selected, and the mask field MUST be hidden; for several items the dialog MUST stay
  as today.
- **FR-017**: F5 in the copy dialog and F6 in the move dialog MUST cycle the selection in "To:": name →
  extension (skipped when there is none) → folder part → whole text.
- **FR-018**: For one item, a "To:" naming an existing folder or ending with "/" MUST put the item into
  that folder under its own name; otherwise the last component MUST be the new name and the rest the
  destination folder, which must exist.
- **FR-019**: All existing safeguards of copy and move (onto itself, folder into itself, atomic overwrite,
  links) MUST apply unchanged.

### Key Entities

- **Conflict**: the existing and the new item (name, kind, size, date, location), plus the marks derived
  from them.
- **Conflict policy for an operation**: ask, overwrite all, skip all, overwrite all older, rename all
  automatically.
- **Recent destinations**: up to 10 folders, newest first, kept across launches.
- **Destination menu entry**: a folder, its section (other panel, tab, hot path, recent) and its label.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From the replace question the user can read either file or compare both with one key press
  and come back to the question without losing the operation.
- **SC-002**: Keeping both files takes at most two choices (More…, Rename Automatically) instead of
  cancelling and renaming by hand.
- **SC-003**: Copying one file under a new name takes F5, typing the name and Return, with no mask.
- **SC-004**: A destination used before, a hot path or a tab folder can be chosen in the F5 dialog with at
  most three key presses.
- **SC-005**: Automatic names, the Overwrite All Older decision, the marks, recent destinations, the
  destination menu entries, the "To:" parsing and the selection cycle have automated tests.

## Assumptions

- "Newer" compares modification dates as shown in the question; time zones and file systems with coarse
  dates (FAT: 2 seconds) are taken as reported.
- The temporary copies for looking into archive and server files use the same cache and cleanup as F3 in
  a panel.
- The recent destinations are stored like the folder history (spec 014), which is also not exported.
- The hint line uses the key names of the current key scheme; both schemes use the same keys here.

## Out of Scope

- Directory synchronization.
- A background operation queue.
- A folder tree for picking the destination.
- Editing inside Compare Files.
- Changing the default button of the question.
- A list of all conflicts shown before the operation starts.

## Deviations from the classic reference

- Automatic names follow the Finder ("x 2.txt") instead of "x(2).txt".
- Compare is on ⌥F3, since ⌃F3 sorts by name here.
- The destination list is one menu (button or ⌥↓) instead of separate keys per source.
