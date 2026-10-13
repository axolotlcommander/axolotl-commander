# Feature Specification: Synchronize Folders

**Feature Branch**: `023-folder-sync`

**Created**: 2026-10-13

**Status**: Implemented

**Input**: User description: "Synchronize folders: a new window that compares the folder trees of the left
and right panel and copies (optionally deletes) the differences in a chosen direction." (Proposal written in
chat after the maintainer chose folder synchronization as the next feature for 0.5.0; agreed on 2026-10-13:
"jo pokracuj", "jak doporucujes", that is, take the recommended answers.)

## Context

"Compare Panels…" (⌃F10, a dialog) and "Compare Panels" (⇧F2, at once) compare one level of both panels:
by date (with a 2-second tolerance) and size they mark the newer or larger file and the items that exist in
one panel only, and they can ignore files and folders by a mask. They do not look into subfolders, and the
marks are only useful for the next copy in that one folder. Keeping two folder trees in step (a project on
a USB stick, a backup on an external disk, a share on the network) means comparing and copying folder by
folder.

The classic reference has no synchronize window either: its "Compare Directories" can look into
subdirectories and compare size, date, attributes and content, but it only marks files in the panels, and
its copy dialog has a "copy only newer and missing files" option. This spec adds a separate window that
compares two folder trees, shows what differs, lets the user decide per item and then copies (and, when
asked for, deletes to the Trash) in one confirmed run.

This spec ships in release 0.5.0, on top of spec 022 (which builds on spec 021).

## Clarifications

### Session 2026-10-13

- Q: A separate window, or only marks in the panels as in the reference? → A: A separate window. Marks in
  the panels cannot be used to copy across subfolders.
- Q: Can synchronizing delete? → A: Yes, as an option that is off by default, only in a one-way direction,
  and always to the Trash.
- Q: Server connections (SFTP/FTP) and archives as sides? → A: Not in this version: only local folders and
  volumes mounted in macOS (including network shares). The command is greyed out otherwise.
- Q: Key? → A: ⌥⇧F10 (⌥F10 is Disk Map, ⇧F10 shows the context menu, ⌃⇧ chords are often taken by display
  utilities).
- Q: Change Compare Panels? → A: No. ⌃F10 and ⇧F2 stay as they are; synchronizing is a new command.
- Q: Saved sync profiles? → A: Out of scope.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Compare two folder trees and copy the differences (Priority: P1)

The user has a project folder in the left panel and its copy on a USB stick in the right panel. They press
⌥⇧F10, keep the default options (subfolders, date, size, both ways) and press Return. A window lists every
file and folder that differs, with an arrow showing which way it will be copied. The user presses Return,
reads the summary ("Copy 12 files (340 MB) to the right, 3 files to the left") and confirms. The files are
copied; the window compares again and shows that nothing is left to do.

**Why this priority**: it is the core of the feature; without it nothing else is useful.

**Independent Test**: two test folders with known differences (a newer file on each side, a file and a
folder on one side only, an equal file, a subfolder with a difference) are synchronized both ways; both
trees are then the same and comparing again shows no differences.

**Acceptance Scenarios**:

1. **Given** the left and right panels show two local folders, **When** the user presses ⌥⇧F10, **Then** a
   sheet opens with both folders named (left panel's folder as Left, right panel's as Right) and the
   remembered options; Return starts comparing, Esc closes the sheet without doing anything.
2. **Given** a file is newer on the left, **When** comparing both ways, **Then** its row shows → (copy to
   the right); a file newer on the right shows ←.
3. **Given** a file or a folder exists only on the left, **When** comparing both ways, **Then** it shows →;
   a folder that exists only on one side is one row (its contents go with it), not one row per file inside.
4. **Given** a file is the same on both sides by the chosen criteria, **When** comparing, **Then** it is
   "equal" and is hidden unless the "Equal" filter is on.
5. **Given** the list shows planned actions, **When** the user presses Return, **Then** a confirmation shows
   how many files and bytes will be copied to each side and how many items will be deleted, with
   Synchronize as the default button and Esc to cancel; nothing has changed before this is confirmed.
6. **Given** the user confirms, **When** the run finishes, **Then** the planned items are copied with their
   dates kept, both panels refresh, and the window compares again and shows what is left (nothing, when
   all went well).
7. **Given** comparing takes a while, **When** it runs, **Then** progress shows the number of items scanned
   and the current folder, the app stays responsive, and Cancel / Esc stops it without changing anything.

---

### User Story 2 - Decide per item before running (Priority: P1)

Not everything that differs should be copied. The user moves through the list with the arrows, excludes a
row with Space, turns another row around with ← or →, and for a file that differs with no newer side opens
the two files side by side with F3 to decide which one is right.

**Why this priority**: copying blindly can overwrite the version the user wanted to keep; per-item control
is what makes the run safe to confirm.

**Independent Test**: in the list of User Story 1, exclude one row, reverse another and set a direction for
a ≠ row; the confirmation summary and the run reflect exactly these choices.

**Acceptance Scenarios**:

1. **Given** a row is selected, **When** the user presses Space, **Then** the row is excluded (shown as
   skipped, not counted in the summary); Space again restores its previous action. With several rows
   selected, Space toggles all of them.
2. **Given** a row is selected, **When** the user presses →, **Then** its action becomes "make the right
   side like the left" (copy to the right); ← makes it "make the left side like the right" (copy to the
   left). This works on several selected rows at once; rows where the direction is not possible stay as
   they were and the app beeps.
3. **Given** a row is selected, **When** the user presses = (or Delete), **Then** its action becomes
   "nothing"; this never deletes a file.
4. **Given** a row whose two files differ, **When** the user presses F3, **Then** the two files open in
   Compare Files; for a row that is not a pair of files, F3 beeps.
5. **Given** the mouse is used, **When** the user clicks the action cell, **Then** the action cycles through
   the actions possible for that row; a right click opens a menu with the same choices (Copy to the Right,
   Copy to the Left, Do Nothing, Exclude).
6. **Given** filter buttons Equal (off by default), Different, Left Only and Right Only, **When** the user
   turns one off, **Then** those rows are hidden but keep their actions; the summary line always counts all
   rows, not only the shown ones.
7. **Given** the window is open, **When** the user presses ⌘R, **Then** the same two folders are compared
   again with the same options and the user's per-item choices are dropped.

---

### User Story 3 - Mirror one way, optionally deleting extra items (Priority: P2)

The user keeps a backup on an external disk. They choose "Left to right" and turn on "Delete items missing
on the left". The list shows → for new and newer files and ✕ for files that exist only on the backup. After
confirming, the backup mirrors the source; the extra files are in the Trash.

**Why this priority**: a one-way mirror is the second most common use; deleting is the riskiest part of
the feature and is therefore opt-in.

**Independent Test**: with "Left to right" and deleting on, a right-only file and a right-only folder are
moved to the Trash and the left side is never changed; with deleting off they stay and show no action.

**Acceptance Scenarios**:

1. **Given** the direction "Left to right", **When** comparing, **Then** files missing or older on the right
   get →, and nothing is planned to the left.
2. **Given** "Left to right" and a file newer on the right, **When** comparing, **Then** the row shows ≠ (no
   action): a newer file is never overwritten without the user choosing it.
3. **Given** "Left to right" with deleting off, **When** an item exists only on the right, **Then** it has
   no action.
4. **Given** "Left to right" with deleting on, **When** an item exists only on the right, **Then** it shows
   ✕ on the right; the confirmation names the number of items that will go to the Trash on their own line.
5. **Given** the direction is "Both ways", **When** the user opens the options, **Then** the delete option
   is not available (shown disabled).
6. **Given** a right-only item planned for deletion, **When** the run reaches it and that volume has no
   Trash, **Then** the item is not deleted (never deleted permanently) and is listed in the report.

---

### User Story 4 - Choose what counts as different (Priority: P2)

The user's USB stick is formatted FAT, which stores times in 2-second steps and shifts them by an hour when
daylight saving changes. The defaults (2-second tolerance, ignore a difference of exactly one hour) keep
such files equal. For a folder where files are rewritten with the same size and date, the user turns on
content comparison. Masks leave out build output and system clutter.

**Why this priority**: wrong "differences" make the list useless; but the defaults already work for most
folders.

**Independent Test**: test files with dates 1 s apart, exactly 3600 s apart and 10 s apart, files of the same
size and date with different content, and files matching an ignore mask produce the expected rows with each
option on and off.

**Acceptance Scenarios**:

1. **Given** two files whose dates differ by up to 2 seconds and whose sizes match, **When** comparing by
   date and size, **Then** they are equal.
2. **Given** dates differ by exactly one hour (within the tolerance) and "Ignore a difference of exactly one
   hour" is on, **When** comparing, **Then** the files are equal; with the option off, the newer one wins.
3. **Given** comparing by size only and the sizes differ, **When** comparing, **Then** the row shows ≠ (no
   newer side).
4. **Given** "Compare content" is on and two files are equal by the other chosen criteria but their bytes
   differ, **When** comparing, **Then** the row shows ≠; files already found different by date or size are
   not read.
5. **Given** an ignore-files mask `*.o;.DS_Store` and an ignore-folders mask `build;.git`, **When** comparing,
   **Then** matching items (at any depth) are not listed and not copied or deleted.
6. **Given** the user changes options and compares, **When** they open the sheet next time (also after
   relaunching), **Then** the last options are preselected.

---

### Edge Cases

- **One folder inside the other** (Left `/a`, Right `/a/b`, also through a symbolic link): a message says
  the folders are nested; no window opens.
- **The same folder on both sides**: a message says there is nothing to compare.
- **A panel is not a local folder** (server connection, archive, search results, Network): the command is
  greyed out.
- **A file on one side and a folder of the same name on the other**: ≠. Choosing a direction replaces the
  item on the target side: the replaced item goes to the Trash first (this counts as a deletion in the
  summary, even when the delete option is off, because the user chose it for that row).
- **Symbolic links**: compared as links (by their target path), never followed; copied as links.
- **Packages** (.app and other bundles): treated as folders.
- **Names that differ only in case**: matched case-insensitively when the volume is case-insensitive;
  names that differ only in Unicode normalization (composed vs decomposed accents) always match.
- **Hidden files**: included when Show Hidden Files is on at the time of comparing, left out otherwise.
- **Unreadable folders**: shown as error rows with the reason; nothing inside them is copied or deleted.
- **A file changes after comparing** (size or date differs from the compared state, or a planned target
  appeared or vanished): it is skipped during the run and listed in the report.
- **The panels change folder while the window is open**: the window keeps its own two folders, shown in
  its header.
- **A side becomes unavailable** (volume ejected or unmounted): comparing or the run stops with a message;
  nothing more is copied. Ejecting a volume while the comparison or the run uses it is refused (spec 022).
- **Read-only target, out of disk space, permission errors**: reported as in a normal copy; the run can be
  continued or cancelled as there.
- **Cancel during the run**: stops after the current file; what was done stays done; the window compares
  again.
- **Very large trees** (100 000 files): comparing stays responsive and the list scrolls smoothly.
- **The sync window is already open for this main window**: the command brings it to the front instead of
  opening a second one.
- **No differences**: the window says the folders are in sync (with the Equal filter offering the full
  list); Return does nothing.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Commands menu MUST offer "Synchronize Folders…" with the default key ⌥⇧F10, customizable
  like every command. It MUST be greyed out unless both panels show a folder on the local file system
  (including volumes mounted in macOS).
- **FR-002**: The command MUST open a sheet naming the left panel's folder as Left and the right panel's
  folder as Right, with the options: include subfolders (default on); compare by date (default on) with a
  2-second tolerance and "Ignore a difference of exactly one hour" (default on); compare by size (default
  on); compare content (default off); an ignore-files mask and an ignore-folders mask (the Compare Panels
  mask syntax); direction "Both ways" (default), "Left to right" or "Right to left"; "Delete items missing on
  the source side" (default off, available only for a one-way direction). Return compares, Esc cancels.
- **FR-003**: The options MUST be remembered across launches and included in the settings export.
- **FR-004**: The command MUST refuse with a message, before any scan, when the two folders are the same or
  one is inside the other (after resolving symbolic links).
- **FR-005**: Comparing MUST run in the background, the app staying responsive, with progress (items scanned, current folder) and MUST
  be cancellable without changing anything.
- **FR-006**: Items MUST be matched by their path relative to the two folders, case-insensitively on
  case-insensitive volumes, and regardless of Unicode normalization.
- **FR-007**: Each matched item MUST get one state: only left, only right, equal, left newer, right newer,
  or different (no newer side: the dates are equal within the tolerance but size or content differs, the
  date is not compared, or a file faces a folder). A pair is equal when no enabled criterion finds a
  difference; content is read only for pairs that are equal by the other enabled criteria.
- **FR-008**: Date comparison MUST treat differences up to 2 seconds as equal and, when the option is on,
  differences of exactly one hour (± the tolerance) as equal.
- **FR-009**: Symbolic links MUST be compared as links by their target path and never followed; packages
  MUST be treated as folders; an item present on one side only MUST be a single row even when it is a
  folder; unreadable folders MUST be error rows.
- **FR-010**: Ignore masks MUST apply to item names at every depth; ignored items are neither listed nor
  touched. Hidden items MUST follow Show Hidden Files at the time of comparing.
- **FR-011**: Default actions MUST follow the direction:
  - Both ways: the newer side is copied over the older; a one-sided item is copied to the other side;
    "different" gets no action (≠).
  - One way (source → target): items missing or older on the target are copied from the source; a target
    newer than the source is ≠ with no action; target-only items are marked for deletion (✕) only when the
    delete option is on, otherwise they get no action.
- **FR-012**: The result window MUST show one row per item, sorted by relative path, with columns for the
  left size and date, the action, the right size and date, and the item's icon and relative path. Its
  header MUST name both folders and the options used.
- **FR-013**: The action of a row MUST be one of: copy to the right (→), copy to the left (←), delete on the
  target side (✕, which is "make this side like the other" for a one-sided item), nothing (= or ≠), or
  excluded. Deleting MUST be possible only when the delete option is on and only on the target side of the
  chosen direction, except for the file-versus-folder replacement of the edge cases.
- **FR-014**: In the window, the arrows and page keys MUST move, ⇧ with them and ⇧/⌘ click MUST extend the
  selection, Space MUST toggle excluded for the selected rows, → / ← MUST set "make the right / left side
  like the other" where possible (beep otherwise), = and Delete MUST set "nothing", F3 MUST open Compare
  Files for a pair of files, ⌘R MUST compare again, Return MUST open the run confirmation, Esc MUST close
  the window. Clicking the action cell MUST cycle the possible actions; a context menu MUST offer them.
- **FR-015**: Filter buttons Equal (default off), Different, Left Only and Right Only MUST hide or show rows
  without changing their actions; a summary line MUST show, for all rows, the number of items and bytes to
  copy each way and the number of items to delete.
- **FR-016**: Nothing MUST change on disk before the user confirms a summary that states the files and bytes
  to copy to each side and, on its own line, the number of items going to the Trash. Synchronize is the
  default button; Esc cancels.
- **FR-017**: The run MUST copy with the app's normal copy (progress, cancel, errors, dates and permissions
  kept, symbolic links copied as links). Planned overwrites MUST replace the target without the conflict
  question; before each item the app MUST check that both sides still match the compared state (existence,
  size, date) and skip and report any item that does not.
- **FR-018**: Deleting MUST move items to the Trash; when the volume has no Trash, the item MUST be skipped
  and reported, never deleted permanently.
- **FR-019**: After the run, both panels MUST refresh and the window MUST compare again; a report MUST list
  skipped and failed items with the reason.
- **FR-020**: The comparison and the run MUST count as app work on both volumes, so ejecting either volume
  is refused while they run (spec 022).
- **FR-021**: At most one sync window per main window: the command MUST bring an open one to the front.
- **FR-022**: "Compare Panels…" (⌃F10) and "Compare Panels" (⇧F2) MUST stay unchanged.
- **FR-023**: All new text MUST be localized (English source, Czech translation).

### Key Entities

- **Sync options**: the two folders, the criteria (subfolders, date with tolerance and the one-hour rule,
  size, content), the ignore masks, the direction and the delete option.
- **Sync item**: a relative path with what is on each side (kind, size, date, link target, or nothing), its
  compared state and its action (default and user-chosen, plus excluded).
- **Sync plan**: the items with an action, as copies in each direction and deletions, with counts and bytes;
  it is what the confirmation shows and the run carries out.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After a run that ended without errors, comparing the same two folders again shows no
  differences (all copied items are equal by date and size).
- **SC-002**: No file outside the planned, confirmed actions is created, changed or removed; deleted items
  are always in the Trash afterwards.
- **SC-003**: Comparing two trees of 100 000 files each on an internal SSD by date and size finishes within
  15 seconds; progress updates at least once a second and the app responds to keys during it.
- **SC-004**: The whole flow (open, compare, adjust rows, confirm, run, close) can be done with the keyboard
  alone.
- **SC-005**: Files 1 to 2 seconds apart, and exactly one hour apart with the option on, are never listed as
  different.
- **SC-006**: The core rules (matching, states, default actions per direction, action changes, the plan
  summary, the nested and same-folder refusals, the changed-since-comparing check) are covered by unit tests
  that run without touching real user data.

## Assumptions

- The app's normal copy engine (spec 021) does the copying; this spec only decides what to copy and
  answers the overwrite question from the plan.
- Content comparison reads both files fully; it is slow for large files and therefore off by default.
- The GUI check uses two test folders created in the session's scratch folder, with both panels pointed to
  them first; deleting is tried only there.
- Out of scope: server connections and archives as sides; saved sync profiles; scheduled or automatic
  syncing; merging the contents of two changed files; detecting moved or renamed files; more than two
  folders; copying part of a file.
- Deviations from the classic reference: a separate synchronize window with directions and a confirmed run
  instead of only marking files in the panels; the one-hour rule is an option of the dialog rather than a
  global setting.
