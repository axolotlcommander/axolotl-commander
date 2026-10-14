# Research: Split and Combine Files

## R1 Part size presets

- **Decision**: 25 MB = 25 × 1024², 100 MB = 100 × 1024², 700 MB (CD) = 700 × 1024², 4.7 GB (DVD) =
  4 480 × 1024² = 4 697 620 480 bytes (a single-layer DVD holds 4 700 372 992 bytes; the rest is room for the
  disc's file system), 4 GB − 1 byte (FAT32) = 4 294 967 295. Default: 100 MB.
- **Rationale**: 1024-based like the custom units (spec Assumptions); the DVD and FAT32 values are hard
  limits, so they are exact byte counts that fit.
- **Alternatives**: decimal megabytes (the Finder's display) — mixed units in one popup would confuse.

## R2 Custom size parser

- **Decision**: trim, drop inner spaces, accept `,` or `.` as the decimal mark, an optional unit `B`, `k`/`K`,
  `M`, `G` (also with a trailing `B`, e.g. `MB`), powers of 1024; the value is rounded down to whole bytes and
  must be ≥ 1. Invalid → nil. Part count = ⌈size / part⌉; the dialog refuses part ≥ size and count > 999.
- **Rationale**: typing `1,5G` or `700 MB` must just work; rounding down keeps parts within a limit.

## R3 Part names

- **Decision**: `<file name>.` + the 1-based index with at least three digits (`String(format: "%03d")`).
  Split never needs more than three (999 limit); Combine reads any width ≥ 3.

## R4 Checksum file

- **Decision**: write `filename=<name>\r\nsize=<bytes>\r\ncrc32=<HEX8>\r\n` in UTF-8. Read: decode UTF-8,
  else Latin-1; split on CR, LF or CR LF; each line `key=value` with the key trimmed and compared
  case-insensitively, the value trimmed; unknown keys ignored; `size` must be a non-negative integer, `crc32`
  up to 8 hex digits in either case. A name that is empty, contains `/` or NUL, or is `.` / `..` is dropped.
- **Rationale**: the usual managers write this format; other tools write variants (LF ends, lower case).

## R5 Part set detection

- **Decision**: a name is a part when it matches `<base>.<3+ digits>`; a checksum file when its extension is
  `crc` (any case). From the cursor: base from the part or the checksum file; the folder's names matching
  `<base>.<digits>` (base compared exactly, digits any width ≥ 3) form the set ordered by number; numbers
  must run 1…max without gaps, otherwise the missing names (at most 10 listed) are reported. The checksum
  file is `<base>.crc` when present (case-insensitive). Marked (two or more): files sorted with
  `NameRules.order` (natural, case-insensitive); the first marked `.crc` is the checksum file, the rest are
  joined. One marked file is treated like the cursor.
- **Default name**: checksum file's name when valid, otherwise `<base>`; for marked files without a
  `<base>.NNN` pattern, the first file's name without its last extension.

## R6 Free space

- **Decision**: `URLResourceKey.volumeAvailableCapacityKey` of the target folder (or its nearest existing
  parent); needed = file size + 4 KiB for the checksum file. Unknown capacity → no check.
- **Alternatives**: `volumeAvailableCapacityForImportantUsageKey` counts purgeable space that may not be
  freed in time; the plain value is the safe one.

## R7 Split writing

- **Decision**: open the source once (`O_RDONLY`, following links), `fstat` its size; create the staging
  folder `<target>/.~icmd-<uuid>` (the app's temporary prefix, hidden, same volume); write each part with
  `O_CREAT | O_EXCL`; 4 MiB chunks, CRC32 over every chunk, `Task.checkCancellation()` per chunk; after the
  last part a further `read` must return 0 and the total must equal the size, otherwise "the file changed
  while it was split". Then the checksum file, then the commit: each staged file is renamed into the target —
  `renamex_np(RENAME_EXCL)` normally, plain `rename` (atomic file replacement) for the names the user agreed
  to replace. A failure during the commit removes the parts already moved that did not replace anything.
  The staging folder is always removed. Existing folders with a part's name are refused before writing.
- **Conflict question**: before writing, the names that exist in the target are listed in one question
  with Replace / Cancel (the spec 021 per-file question does not fit a set where skipping one part breaks it).

## R8 Combine writing

- **Decision**: staging folder in the target folder as in R7; the joined file is written there under its
  final name, CRC32 and size counted while writing; afterwards the staged file is moved into the target with
  `FileOperations.transfer(.move)` and `ConflictAsker`, exactly as Unpack does (spec 021 question with
  replace, skip, keep both, cancel), and the staging folder is removed. The check compares the counted size
  and CRC32 with the checksum file; a mismatch is reported after the move and the file is kept.
- **Rationale**: reusing the transfer gives the existing conflict handling and its tests for free; the CRC
  of the written data equals the file's CRC.
