# Feature Specification: Encode and Decode Files

**Feature Branch**: `030-encode-decode`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Encode and decode files: turn a file into text (Base64 or UUE) that survives
channels that take only text, and turn such text — including e-mail attachments saved as `.eml` — back into
the original files." Agreed with the maintainer in chat on 2026-10-14 ("jak doporučuješ" — as you
recommend) and asked to build on the same day ("udělej to" — do it).

## Context

Axolotl Commander copies, moves, packs, unpacks, splits and combines files with a progress sheet that can be
cancelled; a name that already exists in the target gets the conflict question of spec 021; new files are
written into a hidden folder inside the target first and moved in only when complete (spec 029).

Usual behavior elsewhere: the usual two-panel file managers have File → Encode File (MIME / Base64, UUE,
XXE) and File → Decode File, which recognizes the encoding from the content, takes the file names from the
encoded text, joins a file that was encoded into several numbered pieces, and extracts the attachments of a
saved e-mail. The reference program offers the same through a plugin. This feature follows that behavior for
local folders and volumes.

## Clarifications

### Session 2026-10-14

- Q: Which encodings does Encode offer? → A: Base64 (as a small MIME message that carries the file name, so
  decoding restores it) and UUE. No splitting of the encoded text into pieces.
- Q: Which files does Encode work on? → A: The marked files, or the file under the cursor; each file gets its
  own encoded file `<name>.b64` or `<name>.uue`.
- Q: What does Decode read? → A: Base64 (plain or MIME), UUE, XXE and BinHex 4.0, recognized from the
  content, and the attachments of saved e-mails (`.eml` and other MIME messages, also multipart). Names come
  from the encoded text.
- Q: Pieces? → A: A file encoded in several pieces (UUE / XXE split over several files) is joined when the
  pieces are marked; they are read in natural name order.
- Q: Keys? → A: Menu only; the commands can be given keys in Settings → Keyboard.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Decode an e-mail attachment or encoded text (Priority: P1)

A user has a saved e-mail `invoice.eml` with a PDF attached, or received a `.uue` / `.b64` / `.hqx` file. They
put the cursor on it and choose File → Decode File…; the original files appear in the other panel's folder
under their real names.

**Why this priority**: It is the more common need today: getting files out of saved mail and old encoded
downloads.

**Independent Test**: In a test folder, decode a saved e-mail with two attachments: both files appear in the
target with their names and identical content; decode a UUE file: the file named in its `begin` line appears.

**Acceptance Scenarios**:

1. **Given** the cursor on a local file and nothing marked, **When** the user chooses File → Decode File…,
   **Then** a dialog shows the file name and the target folder (the other panel's folder when it is a local
   folder, otherwise the panel's own, with the destination menu of the Copy dialog).
2. **Given** a saved e-mail (MIME, also multipart and nested), **When** it is decoded, **Then** every part that
   is an attachment (it has a file name, or is not text) is written under its name, decoded from Base64,
   quoted-printable or as it is; the message text itself is not written.
3. **Given** a file with UUE, XXE or BinHex 4.0 text, possibly surrounded by other text, **When** it is
   decoded, **Then** every encoded file in it is written under the name of its header (for BinHex, the data
   fork).
4. **Given** a file with only Base64 text and no headers, **When** it is decoded, **Then** the result is
   written as the file name without its `.b64` / `.base64` extension (or with `.bin` appended when there is no
   such extension).
5. **Given** several marked files, **When** the user chooses Decode File…, **Then** they are read in natural
   name order as one text, so a file encoded in several pieces is joined; separate encoded files in them are
   all written.
6. **Given** a name that already exists in the target, **When** the decoded file is complete, **Then** the
   conflict question of spec 021 is asked.
7. **Given** the decode finished, **When** the target panel shows the target folder, **Then** it is refreshed
   with the cursor on the first decoded file, and a short result lists the written files (and anything that
   was damaged, see User Story 3).
8. **Given** a file with nothing encoded in it, **When** it is decoded, **Then** a message says that no
   encoded data was found and nothing is written.

---

### User Story 2 - Encode a file as text (Priority: P2)

A user needs to pass a small binary file through a channel that takes only text (a form, a chat, an old
mailing list). They choose File → Encode File…, pick Base64 or UUE, and get a text file next to the target.

**Why this priority**: Needed less often than decoding; it completes the pair.

**Independent Test**: Encode a test file as Base64, then decode the result: the decoded file has the
original name and is byte for byte equal to the original. The same with UUE.

**Acceptance Scenarios**:

1. **Given** the cursor on a file (or marked files), **When** the user chooses File → Encode File…, **Then** a
   dialog shows what is encoded, the target folder (default as in User Story 1) and the format (Base64 or UUE,
   the last choice remembered).
2. **Given** Base64, **When** the user confirms, **Then** each file gets `<name>.b64`: a short MIME header with
   the file name followed by the Base64 text in lines of 76 characters.
3. **Given** UUE, **When** the user confirms, **Then** each file gets `<name>.uue` with a `begin 644 <name>`
   line, the UUE lines and `end`.
4. **Given** an existing file with the output name, **When** the output is complete, **Then** the conflict
   question of spec 021 is asked.
5. **Given** folders among the marked items, **When** the user encodes, **Then** they are left out and the
   result says so; with only folders the command is disabled.

---

### User Story 3 - Damaged or unsafe input stays harmless (Priority: P1)

A user decodes a truncated download or a message with a strange attachment name. Nothing is written outside
the target folder, no existing file is changed without the question, and damaged data is reported.

**Why this priority**: Names come from text anyone can write; the constitution puts data safety first.

**Independent Test**: Decode a UUE file whose name is `../../evil` and one cut off before `end`: the first is
written as `evil` inside the target, the second is written and reported as incomplete.

**Acceptance Scenarios**:

1. **Given** a name from the encoded text with folders (`a/b/c.txt`, `..\x`), "." or "..", control
   characters or an empty name, **When** the file is written, **Then** only the last part of the name is used,
   with unsafe characters replaced; an empty result becomes "decoded"; nothing is ever written outside the
   target folder.
2. **Given** two decoded files with the same name in one run, **When** they are written, **Then** the second
   gets a number appended ("name 2.ext").
3. **Given** encoded data that ends before its end marker, or a BinHex CRC that does not match, **When** it is
   decoded, **Then** the data is written and the result marks that file as incomplete or damaged.
4. **Given** a cancelled or failed run, **When** it stops, **Then** everything this run wrote is removed and
   every file that existed before is unchanged.
5. **Given** the target volume has less free space than the input's size, **When** the user confirms, **Then**
   a message shows the needed and the available space and nothing is written.

---

### Edge Cases

- A folder, a package, the ".." item, or a panel showing an archive or a server: Encode File… and Decode
  File… are disabled (folders among marked items are left out).
- A symbolic link to a file: the file it points to is read; the output takes the link's name.
- The target is the source's own folder: allowed.
- The target folder does not exist: created; inside an archive or on a server: refused with a message.
- Base64 with other line lengths, CR LF line ends, spaces or missing padding: accepted.
- An e-mail whose attachment names are encoded (`=?UTF-8?B?…?=`, `filename*=UTF-8''…`): the decoded names are
  used.
- An e-mail without attachments: "no encoded data was found".
- A UUE file with several `begin … end` blocks: each is written.
- A file encoded in pieces but only one piece marked: what is there is written and reported as incomplete.
- Very large inputs (hundreds of MB): decoded with progress; Cancel works.
- Find results: both commands work on the local files listed; the target defaults to the other panel.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The File menu MUST offer Encode File… and Decode File… without default keys, assignable in
  Settings → Keyboard, and disabled when the panel shows an archive or a server or no file is under the
  cursor or marked.
- **FR-002**: Both dialogs MUST show what is processed and the target folder (the other panel's folder when
  it is a local folder, otherwise the panel's own) with the destination menu of the Copy dialog; Encode also
  offers the format (Base64 or UUE), remembered for the next time.
- **FR-003**: Encode MUST write, for each file, `<name>.b64` (a MIME header with Content-Type, Content-
  Transfer-Encoding base64 and the file name — encoded per RFC 2231 when it is not ASCII — then Base64 in
  lines of 76 characters) or `<name>.uue` (`begin 644 <name>`, standard UUE lines of 45 bytes, `` ` ``, `end`).
- **FR-004**: Decode MUST recognize from the content, anywhere in the input: MIME messages (single part and
  multipart, nested), UUE, XXE and BinHex 4.0 blocks, and plain Base64 text, and write every encoded file it
  finds.
- **FR-005**: For MIME messages, Decode MUST write each attachment (a part with a file name, or a part that is
  not text) decoded from Base64, quoted-printable, 7bit, 8bit or binary, with names from Content-Disposition
  `filename` or Content-Type `name`, including RFC 2047 and RFC 2231 encoded names.
- **FR-006**: Several marked files MUST be decoded as one input in natural name order, so pieces of one
  encoded file are joined.
- **FR-007**: Names from the input MUST be reduced to their last component, with "/", "\\", ":" and control
  characters replaced, "." and ".." refused, an empty result named "decoded", and duplicates within one run
  numbered; nothing may be written outside the target folder.
- **FR-008**: Data that ends before its end marker, or a BinHex CRC mismatch, MUST be reported for that file
  while the data found is still written.
- **FR-009**: All output MUST be written into a hidden staging folder inside the target and moved in with the
  conflict question of spec 021 when complete; Cancel or an error MUST remove everything the run wrote and
  MUST NOT change any file that existed before.
- **FR-010**: Both commands MUST check the free space of the target volume first (the input size for Decode,
  the output size for Encode) and refuse with the needed and available space when it is short.
- **FR-011**: Both commands MUST show progress with Cancel, refresh the target panel with the cursor on the
  first written file, and report the written files and any problem; with nothing found Decode MUST say so and
  write nothing.
- **FR-012**: A missing target folder MUST be created; a target inside an archive or on a server MUST be
  refused.
- **FR-013**: All new texts MUST be localized (English and Czech) and fit without being cut.

### Key Entities

- **Encoded block**: a piece of the input in one encoding (MIME part, UUE, XXE, BinHex, Base64) with the file
  name it carries and whether it is complete.
- **Decoded file**: the name (made safe), the data, and its state (complete, incomplete, damaged).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A file encoded and then decoded (both formats) is byte for byte identical to the original and
  gets its original name back, in every tested case (empty file, sizes not divisible by 3 or 45, non-ASCII
  names).
- **SC-002**: Attachments of tested e-mails (single part, multipart, nested multipart, encoded names) are
  extracted with their names and exact content.
- **SC-003**: No tested hostile name leads to a write outside the target folder.
- **SC-004**: After a cancelled or failed run the target folder holds exactly the files it held before.
- **SC-005**: Files encoded here decode in other common tools (`base64 -d` after the header, `uudecode`) and
  their output decodes here.

## Assumptions

- Only local folders and volumes; servers and archives are out of scope.
- The whole input is read through once; very large inputs are handled with progress, not limits.
- BinHex resource forks are not written (the data fork is the file); file type and creator are ignored.

## Out of Scope

- Encoding into several pieces of a given size; XXE or BinHex encoding.
- yEnc, `message/partial` (MIME messages split into several mails), TNEF (`winmail.dat`) and S/MIME.
- Saving the e-mail body text; showing e-mails.
- Servers and archives.

## Deviations from the reference

- Encoding into XXE is not offered (decoding it is); the usual managers offer it, but it is practically unused.
