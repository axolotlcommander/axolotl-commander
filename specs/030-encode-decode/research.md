# Research: Encode and Decode Files

Sources: RFC 2045–2047 (MIME, quoted-printable, encoded words), RFC 2231 (parameter values and
continuations), RFC 4648 (Base64), the POSIX `uuencode` description, the public BinHex 4.0 description
(RFC 1741 appendix), and the behavior of the usual two-panel file managers. No reference sources were read.

## R1 Reading the input

- **Decision**: one streaming line reader over the inputs in order (marked files in natural name order,
  `NameRules(caseSensitive: false).order`), 1 MiB reads, lines split at LF; a CR before the LF is dropped and
  the line remembers its ending (none / LF / CR LF), so 8bit / binary MIME parts are written with the original
  line ends. A file that does not end with a line end ends its last line there (pieces stay separate lines).
- **Rationale**: every recognized format is line based; streaming keeps memory flat for large inputs and
  gives byte progress.
- **Alternatives**: reading the whole input into memory (simple, but hundreds of MB).

## R2 Recognizing blocks

- **Decision**: a scanner reads lines and looks for block starts anywhere:
  - `begin <octal mode> <name>` → UUE or XXE; the first data line decides: valid UUE (length character in
    32…96, enough characters in that range) → UUE, else valid XXE (alphabet
    `+-0-9A-Za-z`) → XXE; lines that are valid for neither are skipped (separators, "section 2/3" lines,
    mail headers between pieces); `end` closes the block; a new `begin` or the end of the input closes it
    as incomplete.
  - `begin-base64 <mode> <name>` (GNU `uuencode -m`) → Base64 until `====`.
  - a line starting with `(This file must be converted with BinHex` → BinHex; the data starts after the
    next `:` and ends at the following `:`.
  - a MIME message: the input starts (after empty lines and an mbox `From ` line) with a header block that
    has `MIME-Version` or `Content-Type`.
- While scanning, the scanner notes whether every non-empty line consisted of Base64 characters only. When
  nothing was found and that holds (and there was at least one such line), a second pass decodes the whole
  input as plain Base64 (US1-4).
- **Rationale**: this matches what the usual managers do ("recognized from the content") with predictable
  rules; the two-pass plain Base64 avoids treating any word-like text as Base64.

## R3 MIME

- **Decision**: a recursive part parser over the line stream:
  - headers with folded lines; names case-insensitive; `Content-Type` with parameters (quoted strings,
    RFC 2231 `name*=charset'lang'%XX` and continuations `name*0*=`, `name*1=`); RFC 2047 encoded words
    (`=?charset?B|Q?…?=`) in `filename` / `name`, charsets through `CFStringConvertIANACharSetNameToEncoding`,
    UTF-8 / Latin-1 fallback.
  - `multipart/*`: the body is split at `--boundary` lines (trailing spaces allowed), `--boundary--` ends;
    preamble and epilogue are scanned like text; a missing closing boundary marks the open part incomplete.
  - `message/rfc822`: the body is parsed as a message.
  - a leaf part is an **attachment** when it has a name (`Content-Disposition` `filename`, `Content-Type`
    `name`), when `Content-Disposition` is `attachment`, or when its type is not `text/*`; attachments are
    written decoded (Base64, quoted-printable, 7bit / 8bit / binary as they are).
  - text parts that are not attachments are decoded (quoted-printable / Base64) and their lines are scanned
    for UUE / XXE / BinHex blocks (old mails carried uuencoded files in the body).
  - an unnamed attachment is named `decoded`, with the extension of its type when the system knows one
    (`UTType(mimeType:)`).
- **Rationale**: covers `.eml` files saved from Mail and other clients, including nested messages.
- **Alternatives**: a full RFC 5322 parser — more than needed for extracting files.

## R4 Decoders

- **Base64**: characters outside the alphabet are ignored, `=` ends the data; leftover bits are dropped; the
  data is complete when the character count is a multiple of four or padding was seen.
- **Quoted-printable**: `=XX` → byte, `=` at line end joins lines, other characters as they are; a hard line
  break writes the line's own ending.
- **UUE / XXE**: per line, the length character gives the byte count; four characters → three bytes; missing
  trailing characters count as zero (some encoders strip trailing spaces).
- **BinHex 4.0**: 6-bit alphabet ``!"#$%&'()*+,-012345689@ABCDEFGHIJKLMNPQRSTUVXYZ[`abcdefhijklmpqr``,
  then run-length decoding (`0x90 n`: repeat the previous byte n − 1 more times; `0x90 0x00` is a literal
  `0x90`), then the header (name length, name, version, type, creator, flags, data length, resource length,
  CRC), the data fork with its CRC, the resource fork with its CRC. CRCs are CRC-16/XMODEM (polynomial
  0x1021, initial 0; check value of "123456789" is 0x31C3). The data fork is written; the resource fork is
  read and ignored; a CRC mismatch or a short stream marks the file damaged / incomplete.

## R5 Names

- **Decision**: the name from the input is decoded (R3), then reduced to its last component after `/` and
  `\`; `:` and control characters become `_`; spaces at both ends are trimmed; `.` / `..` / empty →
  `decoded`; names longer than 255 UTF-8 bytes are shortened keeping the extension. Within one run a name that
  was already used gets ` 2`, ` 3`, … before the extension (US3-2). Comparison is case-insensitive (the usual
  macOS volumes).
- **Rationale**: nothing can leave the target folder (SC-003); the conflict question of spec 021 handles
  names that already exist in the target.

## R6 Encoding output

- **Base64** (`<name>.b64`):
  ```
  MIME-Version: 1.0
  Content-Type: application/octet-stream; name="<name>"
  Content-Transfer-Encoding: base64
  Content-Disposition: attachment; filename="<name>"

  <Base64 in lines of 76 characters>
  ```
  A name that is not plain printable ASCII (or has `"` or `\`) is written as `name*=UTF-8''<percent-encoded>`
  and `filename*=UTF-8''<percent-encoded>` (RFC 2231). Line ends are LF (files on a Mac; `base64 -D` and the
  decoder here take both).
- **UUE** (`<name>.uue`): `begin 644 <name>`, lines of 45 bytes (length character + 60 characters, `` ` ``
  for zero), a `` ` `` line, `end`; LF line ends; a line end in the name becomes `_`.
- **Rationale**: SC-005 — the output is read by `uudecode` and `base64 -D`; the MIME header carries the name
  back (SC-001).

## R7 Writing, conflicts and cleanup

- **Decision**: as Combine in spec 029: a staging folder `.~icmd-<uuid>` (mode 0700) inside the target; the
  decoded / encoded files are created there with `O_CREAT | O_EXCL` under their final names; when the run is
  complete, they are moved into the target with `FileOperations.transfer(.move)` and `ConflictAsker`
  (spec 021); the staging folder is removed afterwards, and on cancel or error (FR-009).
- Free space: Decode needs at most the input size; Encode needs ⌈size / 3⌉ × 4 × 77 / 76 plus the header
  per file (FR-010).

## R8 Progress and result

- **Decision**: progress in bytes of input read (for the second pass of plain Base64 the bar starts over); the result message lists the written files (at most 10 names, then "and N more"), and the
  files that are incomplete or damaged; nothing found → "No encoded data was found", nothing is written.
