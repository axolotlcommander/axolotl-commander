# Feature Specification: Split and Combine Files

**Feature Branch**: `029-split-combine`

**Created**: 2026-10-14

**Status**: Implemented

**Input**: User description: "Split and combine files: cut a large file into numbered parts of a chosen size
(with an optional checksum file) and join such parts back into the original file." Agreed with the maintainer
in chat on 2026-10-14 ("jak doporučuješ" — as you recommend) and asked to build on the same day ("udělej to" —
do it).

## Context

Axolotl Commander copies, moves, packs and unpacks files with a progress sheet that can be cancelled; when a
name already exists in the target it asks the conflict question of spec 021. Unpacking writes into a hidden
folder inside the target first and moves the result in only when it is complete. The app can already compute
CRC32 (Calculate / Verify Checksums).

Usual behavior elsewhere: the reference program has a Split & Combine plugin. The usual two-panel file
managers split a file into parts named `name.001`, `name.002`, … of a chosen size, optionally with a small text
checksum file naming the original file, its size and its CRC32, and combine such a set back, checking the
result against that file. The commands live in the File menu. This feature follows that behavior for local
folders and volumes.

## Clarifications

### Session 2026-10-14

- Q: Which file does Split work on? → A: One file: the single marked one, or the one under the cursor when
  nothing is marked. More marked files: a message that Split works on one file at a time.
- Q: Where do the parts go? → A: To a folder chosen in the dialog; by default the other panel's folder (when
  it is a local folder), with the same destination menu as the Copy dialog.
- Q: Which sizes? → A: Presets 25 MB (e-mail), 100 MB, 700 MB (CD), 4.7 GB (DVD), 4 GB − 1 byte (FAT32
  limit) and a custom size with the units k, M, G (powers of 1024). The dialog shows how many parts will be
  made.
- Q: Part names and the checksum file? → A: `<file name>.001`, `.002`, … and `<file name>.crc` in the usual
  text format (original name, size, CRC32); the checksum file is on by default and can be turned off.
- Q: Cancel? → A: Removes only what this run wrote, never a file that existed before.
- Q: Which parts does Combine take? → A: From any part or the `.crc` file it finds the whole numbered set;
  when files are marked, exactly the marked files in name order. A missing part refuses.
- Q: Checking the result? → A: With a `.crc` file the size and CRC32 are checked; a mismatch keeps the file
  and warns.
- Q: Keys? → A: Menu only; the commands can be given keys in Settings → Keyboard.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Split a file into parts (Priority: P1)

A user needs to send a 300 MB file through a service that takes at most 25 MB per file, or to put a 6 GB
file on a FAT32 stick. They split it into numbered parts of the right size, with a checksum file so the
receiver can check the joined result.

**Why this priority**: It is half of the feature and produces what Combine reads.

**Independent Test**: In a test folder, put the cursor on a 60 MB file and choose File → Split File…; pick
25 MB: the dialog says 3 parts; OK writes `file.001` (25 MB), `file.002` (25 MB), `file.003` (10 MB) and
`file.crc` into the other panel's folder; the original file is unchanged.

**Acceptance Scenarios**:

1. **Given** the cursor on a local file and nothing marked, **When** the user chooses File → Split File…,
   **Then** a dialog shows the file's name and size, the target folder (the other panel's folder when it is a
   local folder, otherwise the panel's own), the part size, a line "Creates N parts" and the checkbox "Create
   checksum file".
2. **Given** the dialog, **When** the user picks a preset or types a custom size (for example `10M`,
   `1,5 G`, `700000k`, `123456`), **Then** the number of parts updates at once.
3. **Given** a size that cannot be read, is zero, is not smaller than the file, or would need more than 999
   parts, **When** the dialog shows it, **Then** OK is disabled and a short reason replaces the part count.
4. **Given** valid settings, **When** the user presses OK, **Then** the parts `<file name>.001`, `.002`, … are
   written into the target folder (all of the chosen size except the last) and, when the checkbox is on,
   `<file name>.crc`; a progress sheet with Cancel is shown while it runs.
5. **Given** the split finished, **When** the target panel shows the target folder, **Then** it is refreshed
   with the cursor on the first part; the original file is unchanged and still in place.
6. **Given** the user split a file before, **When** they open the dialog again, **Then** the last part size
   and the state of the checkbox are preselected.
7. **Given** two or more marked files, **When** the user chooses Split File…, **Then** a message says that
   Split works on one file at a time and nothing is written.
8. **Given** the main menu, **When** the user opens File, **Then** Split File… and Combine Files… are there,
   without default keys, and can be given keys in Settings → Keyboard.

---

### User Story 2 - Combine parts back into the file (Priority: P1)

A user received `report.zip.001` … `report.zip.005` and `report.zip.crc`. They put the cursor on any of them,
choose Combine Files…, and get `report.zip`, checked against the checksum file.

**Why this priority**: It is the other half; without it the parts are useless in the app.

**Independent Test**: Split a test file, then put the cursor on `file.002` and choose File → Combine Files…:
the dialog says 3 parts and that the result will be checked; OK writes `file` into the other panel's folder,
byte for byte equal to the original, and reports that the check passed.

**Acceptance Scenarios**:

1. **Given** the cursor on `X.001`, on any `X.NNN` of a set, or on `X.crc`, and nothing marked, **When** the
   user chooses Combine Files…, **Then** the set `X.001`, `X.002`, … of that folder is found and the dialog
   shows the number of parts, their total size, the target path with the file name, and whether the result
   will be checked against a checksum file.
2. **Given** a set with a `.crc` file, **When** the dialog opens, **Then** the proposed name is the one
   recorded in the checksum file; without one it is `X`.
3. **Given** two or more marked files, **When** the user chooses Combine Files…, **Then** exactly the marked
   files are joined in natural name order (`part2` before `part10`); a marked `.crc` file is used for the
   check and not joined; without one the proposed name is the first file's name without its last extension.
4. **Given** a set whose first part is missing or that has a gap, **When** the user chooses Combine Files…,
   **Then** a message names the missing parts and nothing is written.
5. **Given** OK, **When** the parts are joined, **Then** the file is written into the target folder under a
   temporary hidden name and gets its name only when it is complete; a progress sheet with Cancel is shown.
6. **Given** a file with the target name already exists, **When** the joined file is complete, **Then** the
   conflict question of spec 021 is asked (replace, skip, keep both with a new name, cancel).
7. **Given** a checksum file, **When** the joined file is complete, **Then** its size and CRC32 are compared
   with the recorded ones; a match is reported briefly; a mismatch keeps the file and warns with the expected
   and actual values.
8. **Given** no checksum file, **When** the joined file is complete, **Then** it is not checked and the
   result says so.
9. **Given** the combine finished, **When** the target panel shows the target folder, **Then** it is
   refreshed with the cursor on the joined file; the parts are unchanged.

---

### User Story 3 - Nothing is lost or left behind (Priority: P1)

A user cancels a long split, runs out of disk space, or splits into a folder that already holds parts of an
older split. Their existing files stay intact and no half-written parts are left.

**Why this priority**: The constitution puts user data safety first; both commands write many large files.

**Independent Test**: Start splitting a large test file and cancel: the target folder holds exactly the
files it held before. Split into a folder with an older `file.001`: a question lists it; Cancel leaves it
unchanged.

**Acceptance Scenarios**:

1. **Given** the target volume has less free space than the result needs, **When** the user presses OK,
   **Then** a message shows the needed and the available space and nothing is written.
2. **Given** a running split or combine, **When** the user cancels or an error occurs, **Then** everything
   this run wrote is removed and every file that existed before is unchanged.
3. **Given** some of the part names or the checksum file already exist in the target, **When** the user
   presses OK, **Then** one question lists them and offers Replace or Cancel; with Replace the old files are
   replaced only after all new parts are complete.
4. **Given** the source file changes size while it is split, or a part cannot be read while combining,
   **When** this is found, **Then** the run stops with a message and the cleanup of scenario 2.

---

### Edge Cases

- A file of 0 bytes, or not larger than one part: OK is disabled with "The file is not larger than one part".
- The cursor on a folder, a package, the ".." item, or the panel showing an archive or a server: Split
  File… and Combine Files… are disabled.
- A symbolic link to a file: the file it points to is read; the parts are named after the link.
- The target is the source's own folder: allowed; the parts land next to the file.
- The target folder does not exist: it is created, as the Copy dialog does. A target inside an archive or on
  a server: refused with a message.
- A checksum file whose `filename=` is empty, contains a slash, or is "." or "..": that name is ignored and
  the default name is used.
- A checksum file with LF or CR line ends, upper- or lower-case keys or hex digits, spaces around the values,
  or extra lines: accepted.
- A checksum file without the parts: the message names the missing first part.
- A set whose total size differs from the size in the checksum file: the file is written and the result
  warns as for a CRC mismatch.
- Combine accepts sets numbered with three or more digits (`.001`, `.0001`); Split never makes more than 999
  parts.
- A volume ejected during the run: the error and the cleanup of User Story 3.
- Find results: both commands work on the local files listed; the target defaults to the other panel.
- Combine on a single part `X.001` with no `X.002`: a set of one part; it is joined (a copy) and checked
  when a checksum file exists.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The File menu MUST offer Split File… and Combine Files… without default keys; both MUST be
  assignable in Settings → Keyboard and disabled when the panel shows an archive or a server or the cursor is
  on the ".." item, a folder or a package.
- **FR-002**: Split MUST work on one local file: the single marked file, or the file under the cursor when
  nothing is marked; with more marked files it MUST say that it works on one file at a time.
- **FR-003**: The Split dialog MUST show the file name and size and offer the target folder (default as in
  User Story 1, with the Copy dialog's destination menu), the part size (the presets 25 MB, 100 MB, 700 MB,
  4.7 GB, 4 GB − 1 byte and a custom size), the number of parts that will be made and the checkbox "Create
  checksum file" (on by default).
- **FR-004**: A custom size MUST accept a number with an optional unit k, M or G (powers of 1024; bytes
  without a unit), a decimal comma or point and spaces; OK MUST be disabled with a reason when the size cannot
  be read, is zero, is not smaller than the file, or needs more than 999 parts.
- **FR-005**: The last used part size and the checkbox MUST be remembered for the next Split.
- **FR-006**: Split MUST write `<file name>.001`, `<file name>.002`, … (three digits), each exactly the
  chosen size except the last, which holds the rest; joined in order they MUST equal the original file.
- **FR-007**: With the checkbox on, Split MUST write `<file name>.crc` with the lines `filename=<file name>`,
  `size=<bytes>` and `crc32=<8 uppercase hex digits>`, ending each line with CR LF.
- **FR-008**: Split MUST never change, move or delete the original file.
- **FR-009**: Combine MUST, from a part or a `.crc` file under the cursor, find the set `X.001`, `X.002`, …
  in that folder, or take exactly the marked files in natural name order; a marked `.crc` file MUST be used
  for the check and not joined.
- **FR-010**: Combine MUST refuse with the names of the missing parts when the first part is missing or the
  numbering has a gap.
- **FR-011**: The Combine dialog MUST show the number of parts, their total size, the target path with the
  file name (default as in User Story 2) and whether the result will be checked.
- **FR-012**: With a checksum file, Combine MUST compare the joined file's size and CRC32 with the recorded
  ones and report the result; a mismatch MUST keep the file and show the expected and actual values.
- **FR-013**: A checksum file's name MUST be ignored when it is empty, contains a slash, or is "." or "..";
  reading the file MUST accept any line ends, case of keys and hex digits, spaces around values and extra
  lines.
- **FR-014**: Both commands MUST check the free space of the target volume before writing and refuse with
  the needed and available space when it is short.
- **FR-015**: Split MUST write all parts and the checksum file under temporary hidden names inside the target
  folder and give them their names only when all are complete; when some names exist, one question MUST list
  them and offer Replace or Cancel, and the old files MUST be replaced only after the new ones are complete.
- **FR-016**: Combine MUST write the joined file under a temporary hidden name in the target folder and give
  it its name only when it is complete; an existing file with that name MUST get the conflict question of
  spec 021.
- **FR-017**: Cancel or an error MUST remove everything the run wrote and MUST NOT remove or change any file
  that existed before the run.
- **FR-018**: A change of the source file's size during Split, or a part that cannot be read during Combine,
  MUST stop the run with a message and the cleanup of FR-017.
- **FR-019**: Both commands MUST show progress with Cancel and, when done, refresh the target panel with the
  cursor on the first part (Split) or the joined file (Combine).
- **FR-020**: A target folder that does not exist MUST be created; a target inside an archive or on a server
  MUST be refused with a message.
- **FR-021**: All new texts MUST be localized (English and Czech) and fit in their dialogs and menus without
  being cut.

### Key Entities

- **Part set**: the ordered parts of one file — their files, sizes and the base name `X`.
- **Checksum file**: the text file `X.crc` with the original file name, size and CRC32.
- **Part size**: a byte count chosen from a preset or typed with a unit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A file split and then combined is byte for byte identical to the original in every tested
  case (exact multiples, a remainder, one part, sizes above 4 GB in the size arithmetic).
- **SC-002**: After a cancelled or failed run, the target folder holds exactly the files it held before, in
  every tested case.
- **SC-003**: A single changed byte in any part is reported as a mismatch when a checksum file exists.
- **SC-004**: The part count shown in the dialog matches the number of parts written in every tested case.
- **SC-005**: Splitting or combining runs at least at the speed of copying the same amount of data on the
  same disk (within 20 %).
- **SC-006**: A set made by Split can be combined by the usual two-panel file managers, and their sets can be
  combined here (same names and checksum file format).

## Assumptions

- Only local folders and volumes are supported; servers and archives are out of scope.
- The sizes 25 MB, 100 MB, 700 MB use 1024-based megabytes; 4.7 GB (DVD) is the largest size that fits a
  single-layer DVD; 4 GB − 1 byte is 4 294 967 295 bytes.
- Natural name order is the order the panel uses when sorting by name.
- The checksum file is read as UTF-8 (falling back to Latin-1) so names written by other programs load.

## Out of Scope

- Splitting folders or several files at once; splitting into a given number of parts.
- Asking to change disks between parts.
- Multi-volume archive formats (`.z01`, `.part1.rar`): those are opened by the archive support.
- Deleting the parts after combining or the original after splitting.
- Other checksum formats (SFV, MD5): Calculate / Verify Checksums do that.
- Splitting text files by lines.
- Servers and archives.

## Deviations from the reference

- The reference's help does not describe its Split & Combine plugin in detail; the behavior follows the usual
  two-panel file managers.
- The checksum file keeps the full name (`name.zip.crc`) next to `name.zip.001`, so several split files can
  share one folder.
