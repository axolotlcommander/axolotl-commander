# Feature Specification: Data Safety — Gaps from the Audit (D1–D8)

**Feature Branch**: `001-data-safety-gaps`

**Created**: 2026-10-08

**Status**: Draft

**Input**: User description: "Data safety: close the gaps D1–D8 from the audit in docs/AUDIT.md against the reference program's rules (05-pravidla.md, Tandem specs 062, 092, 103, 105, 106, 107, 112, 119) and add the missing tests for the safeguards."

Reference: `../tandemcommander/docs/macos-port/05-pravidla.md` (sections File identity, Overwrite,
Move and link, Archive) and the feature records 062, 092, 103, 105, 106, 107, 112, 119 in
`../tandemcommander/specs/`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Overwriting a file on a server does not destroy the old version (Priority: P1)

The user copies (F5) a file to an FTP/SFTP server where a file of the same name already exists,
and confirms the overwrite. The connection drops during the operation, or the server rejects the
final step. The server must be left with either the old version or the new complete version —
never neither.

**Why this priority**: This is the only place where an everyday operation can destroy data
irrecoverably today (there is no Trash on a server).

**Independent Test**: A simulated server that fails in the final swap step; after the operation
either the original content of the target or the complete new content exists, and the user got an
error message.

**Acceptance Scenarios**:

1. **Given** the server holds `zprava.txt` (old version), **When** the user overwrites it with a
   new version and the final swap fails, **Then** the server keeps `zprava.txt` with the old
   content, or the new complete version under the name given in the message, and the message says
   what happened.
2. **Given** the same setup, **When** the data transfer fails midway, **Then** the old version is
   unchanged and no partial copy is left on the server.
3. **Given** the server supports an atomic swap, **When** the overwrite runs, **Then** the target
   on the server is never missing at any moment.

---

### User Story 2 - Unsaved edits to archive members survive quitting (Priority: P1)

The user opens a file inside a ZIP with F4, edits it in the editor, and then quits the app. The
app offers to put the edits back into the archive. The user chooses "Not Now", or writing to the
archive fails (the archive is read-only, the disk is full). The edit must not be lost.

**Why this priority**: Today the edited copies are deleted on quit without warning — loss of work.

**Independent Test**: Edited member copy + refusal or write error + quit → the copy exists and is
offered again at the next launch.

**Acceptance Scenarios**:

1. **Given** an edited copy of an archive member, **When** the user chooses "Not Now" on quit,
   **Then** the copy is kept and the app offers it again for restoring at the next launch (with
   the archive name and the member name).
2. **Given** an edited copy, **When** putting it back into the archive fails on quit, **Then**
   the app reports the error, keeps the copy, and tells the user where to find it.
3. **Given** a copy without edits (only viewed), **When** the app quits, **Then** it is cleaned up.
4. **Given** an edit kept from a previous run, **When** the user restores it or explicitly
   discards it at the next launch, **Then** the copy is cleaned up.

---

### User Story 3 - Archive operations do not loop into themselves (Priority: P1)

The user moves a folder into its own subfolder inside the same archive, but the archive is open
in the panels under different path spellings (via a symlink, with different letter case). Or the
user packs (Alt+F5) content into an archive that is itself among the sources or lies inside a
source folder. Both must be rejected before anything changes.

**Why this priority**: Moving into itself can remove both the original and the copy in the archive.

**Independent Test**: The archive is open via a symlink in one panel and directly in the other;
moving a folder into its descendant → rejected, archive unchanged. Packing a folder into an
archive that lies in that folder → rejected.

**Acceptance Scenarios**:

1. **Given** the archive `a.zip` is open in the left panel as `~/odkaz/a.zip` (a symlink) and in
   the right panel as `~/data/a.zip`, **When** the user moves the folder `docs` to `docs/old`
   between the panels, **Then** the operation is rejected with the message "can't be moved into
   itself" and the archive is unchanged.
2. **Given** the same with a different letter case of the path on a case-insensitive volume,
   **Then** the result is the same.
3. **Given** the folder `projekt` contains `projekt/zaloha.zip`, **When** the user packs
   `projekt` into `projekt/zaloha.zip`, **Then** the operation is rejected before any write.
4. **Given** the target archive is also among the selected sources, **When** the user packs,
   **Then** it is rejected before any write.

---

### User Story 4 - Deleting on a volume without a Trash is a conscious decision (Priority: P2)

The user deletes (F8) on a network volume or a disk that does not support the Trash. They must
learn this up front and decide, rather than find out after an error that the batch was left
half-done.

**Why this priority**: Permanent deletion without warning is irreversible; a half-done batch is
confusing.

**Independent Test**: A simulated volume without a Trash; F8 on several items → a single prompt
about permanent deletion; after "Cancel" nothing is deleted, after "Delete Permanently" everything
is deleted.

**Acceptance Scenarios**:

1. **Given** items on a volume without a Trash, **When** the user presses F8, **Then** the prompt
   states explicitly that the items will be deleted permanently and cannot be recovered, and
   offers "Delete Permanently" and "Cancel".
2. **Given** a mixed selection (some on a volume with a Trash, some without), **When** F8,
   **Then** the prompt lists which items will be deleted permanently; after confirmation the
   others go to the Trash.
3. **Given** the prompt, **When** the user chooses "Cancel", **Then** nothing is deleted or moved.
4. **Given** moving to the Trash unexpectedly fails midway through a batch, **When** the
   operation ends, **Then** the user sees which items are in the Trash and which remained, and
   nothing was deleted permanently without their confirmation.

---

### User Story 5 - A volume without reliable file identity (Priority: P2)

On some volumes (network volumes, older file systems) it is not possible to reliably tell whether
two paths lead to the same file. An operation that would delete the source on a match must not
rely on a guess there.

**Why this priority**: Moving a "file onto itself" would delete the only copy.

**Independent Test**: A volume simulating missing or unstable identity; a move onto a target that
may be the same file → rejected with an explanation; a copy into a new folder works.

**Acceptance Scenarios**:

1. **Given** a volume without reliable identity and a target that already exists under a name the
   volume treats as the same, **When** the user moves or overwrites with deletion of the source,
   **Then** the operation is rejected with an explanation.
2. **Given** the same volume and a target that does not exist, **When** moving, **Then** it
   proceeds normally.
3. **Given** two files on different volumes, **When** their identity is compared, **Then** the
   decision is based on the volume and file identity, not on the path text or the device number.

---

### User Story 6 - "Save As" in the viewer does not destroy the target (Priority: P2)

In the image or text viewer the user chooses "Save As" over an existing file. The target may be a
symlink or may have labels and permissions. The save must behave like the other safe writes.

**Why this priority**: Today the save replaces a symlink with a regular file and loses attributes.

**Independent Test**: Target = a symlink to a file with a label; Save As → the symlink stays a
symlink, the file behind it has the new content and its attributes; a simulated write error →
target unchanged.

**Acceptance Scenarios**:

1. **Given** the target is a symlink, **When** Save As, **Then** the symlink stays and the file it
   points to gets the new content.
2. **Given** the target has labels and permissions, **When** Save As, **Then** the labels and
   permissions are preserved.
3. **Given** the write fails, **When** Save As, **Then** the target is unchanged and no temporary
   file is left behind after the operation.

---

### User Story 7 - Renaming onto another link of the same file is a conflict (Priority: P3)

A file has two hard links (`a.txt` and `b.txt`). The user renames `a.txt` to `b.txt`. Today the
operation silently "succeeds" and nothing happens. It should report that the target exists.

**Why this priority**: It does not cause data loss, but it gives a success message that does not
match the state.

**Independent Test**: Two hard links; F2 of one to the name of the other → a message about the
existing target, both links unchanged. Changing only the letter case of the same name still works.

**Acceptance Scenarios**:

1. **Given** `a.txt` and `b.txt` are hard links to the same file, **When** F2 `a.txt` → `b.txt`,
   **Then** the app reports that the target already exists and changes nothing.
2. **Given** `Zprava.txt`, **When** F2 to `zprava.txt` (letter case only), **Then** the rename
   succeeds.

---

### User Story 8 - Safeguards that already hold have tests (Priority: P3)

Several of the reference program's rules are already satisfied but have no automated test, so a
future change could break them unnoticed.

**Why this priority**: Regression protection; behavior does not change.

**Independent Test**: The new tests pass on the current code and fail when a safeguard is
deliberately switched off.

**Acceptance Scenarios**:

1. **Given** a symlink to a directory by itself, **When** the user moves it elsewhere, **Then**
   the files behind the link stay and only the link is moved.
2. **Given** a folder with an unreadable subfolder, **When** moving, **Then** the source is not
   deleted and the user learns what was not transferred.
3. **Given** a name in decomposed form (NFD), **When** another file is copied or renamed into the
   same folder, **Then** the names keep exactly the code units they had.

---

### Edge Cases

- A server without support for renaming over an existing file: the new version is uploaded under
  a temporary name and the old one is removed only after a successful upload; when the swap
  fails, the user knows where each version is (US1).
- The user cancels the operation midway through an overwrite on a server: the same as a failure
  (US1).
- The archive disappeared or changed between the edit and the restore: the edit is not restored
  blindly, the copy stays and the user gets a message (US2).
- Several edits kept from previous runs: all are offered at once in a single overview (US2).
- A hard link in the same folder under a name differing only in NFC/NFD: identity decides, not
  the text (US7).
- Deleting where some items are on a volume without a Trash and the user has no permission to
  delete: the prompt is not shown for items that would fail anyway; the error is reported (US4).
- A volume where identity exists but changes after unmounting and remounting: identity is not
  used across mounts (US5).

## Requirements *(mandatory)*

### Functional Requirements

**Overwrite on a server (D1)**

- **FR-001**: Overwriting an existing file on a server MUST first upload the new data completely
  under a temporary name in the same folder; the target MUST NOT be removed before the upload is
  complete.
- **FR-002**: If the server can swap the file in a single step, that step MUST be used.
- **FR-003**: When the swap fails, at least one complete version (the old one, or the new one
  under a temporary name) MUST remain on the server, and the message MUST say where it is.
- **FR-004**: When the upload itself fails or is cancelled, the old version MUST remain
  unchanged and the unfinished temporary copy MUST be removed.

**Edits of archive members (D2)**

- **FR-005**: Quitting the app MUST NOT delete an edited copy of an archive member that the user
  has not put back into the archive or explicitly discarded.
- **FR-006**: Kept edits MUST be offered for restoring or discarding at the next launch, naming
  the archive and the member.
- **FR-007**: When putting the copy back into the archive fails, the app MUST keep the copy and
  say where it is.
- **FR-008**: Copies without edits MUST be cleaned up on quit.
- **FR-009**: An edit MUST NOT be put back into the archive if the archive has changed or
  disappeared in the meantime; the user gets a message and the copy stays.

**Archive and operations into themselves (D3, D7)**

- **FR-010**: The check "folder into itself or its descendant" inside an archive MUST compare the
  identity of the archive file, not the text of its path.
- **FR-011**: Packing into an archive that is among the sources or lies inside one of the source
  folders MUST be rejected before any write.
- **FR-012**: Every rejection MUST leave the archive and the sources unchanged and show the
  reason.

**Deleting without a Trash (D4)**

- **FR-013**: Before deleting, the app MUST determine which items cannot be moved to the Trash.
- **FR-014**: For such items, a single prompt MUST state the permanent deletion explicitly and
  offer "Delete Permanently" and "Cancel"; nothing is permanently deleted without confirmation.
- **FR-015**: After "Cancel", no item of the batch MAY be deleted or moved.
- **FR-016**: When moving to the Trash fails midway through a batch, the app MUST stop and show
  what is in the Trash and what remained; failed items MUST NOT be permanently deleted without a
  new confirmation.

**File identity (D5)**

- **FR-017**: File identity MUST be determined by the volume identity and the file identifier;
  the device number alone is not enough, and identity MUST NOT be retained across a volume being
  unmounted.
- **FR-018**: On a volume where identity cannot be reliably determined, an operation that would
  delete the source if the source and target match MUST be rejected when the target exists under
  a name the volume treats as the same or may be the same file.
- **FR-019**: Operations that do not delete the source (a copy to a new name) MUST work on such a
  volume.

**Save As (D6)**

- **FR-020**: "Save As" in the viewers MUST write via a temporary file in the same folder and swap
  only after a complete write; on error the target stays unchanged and the temporary file is
  gone.
- **FR-021**: If the target is a symlink, it MUST stay a symlink and the file behind it gets the
  new content.
- **FR-022**: The target's permissions, labels, and extended attributes MUST be preserved.

**Rename (D8)**

- **FR-023**: Renaming onto the name of another hard link of the same file MUST be reported as an
  existing target and change nothing.
- **FR-024**: Renaming the same entry only to a different letter case or a different Unicode form
  MUST keep working.

**Tests (D1–D8 and existing safeguards)**

- **FR-025**: Every requirement FR-001 through FR-024 MUST have an automated test that fails when
  the safeguard is removed; the tests run only in isolated temporary folders and on simulated
  servers/volumes.
- **FR-026**: The tests MUST also cover the existing safeguards: moving a symlink to a directory
  by itself, an incomplete tree walk leaves the source, and preservation of name code units
  (NFC/NFD).
- **FR-027**: The logic for edits of archive members (tracking copies, deciding what to put back
  and what to keep) MUST be testable without the user interface.

### Key Entities

- **Edited copy of an archive member**: a temporary file extracted from an archive for F4; it is
  tied to the archive (identity), the member name, and the state at extraction; states: unedited
  / edited / restored / discarded / kept for next time.
- **File identity**: a pair of volume identity + file identifier; valid only during a single
  mount of the volume; may be missing ("unknown").
- **Delete batch**: a list of items split into "to the Trash" and "permanently" before execution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of simulated overwrite failures on a server (interrupted upload, failed
  swap, cancellation), at least one complete version of the file remains on the server.
- **SC-002**: In 100% of cases of quitting the app with an unsaved edit of an archive member, the
  edit is available after the next launch.
- **SC-003**: None of the "into itself" operations (moving into a descendant within an archive,
  packing into its own source) changes a single byte of the archive or the sources — verified for
  all path spellings in the US3 scenarios.
- **SC-004**: No item is permanently deleted without a prompt that explicitly states permanent
  deletion.
- **SC-005**: All gaps D1–D8 have at least one automated test; the whole test suite passes and
  takes at most 10 seconds.
- **SC-006**: Every rejection of an operation shows the user an understandable reason (no silent
  failure and no silent "success").

## Assumptions

- The server tests use a simulated server file system (like the existing transfer tests); no real
  servers or user data are used.
- A "volume without reliable identity" is recognized by volume properties reported by the system;
  the tests simulate it.
- Kept edits of archive members are stored in the app's private folder (not in the system
  temporary folder, which the system may clean up).
- The default choice of the permanent-deletion prompt is "Cancel" (the safe choice, like Finder).
- The plan (not this specification) will decide on moving the archive-member edit logic into the
  app core so it can be tested without the UI (FR-027).
- Out of scope: passwords and privacy (P1–P4 of the audit, a separate specification), new UI
  features.
