# Tasks: Encode and Decode Files

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md),
[quickstart.md](quickstart.md)

## Phase 1: Core (blocking)

- [ ] T001 `Sources/CommanderCore/Advanced/CodecDecoders.swift` (NEW): `LineReader` over several files
  (R1: 1 MiB reads, LF / CR LF endings kept, a missing final line end closes the line, `readBytes`);
  `Base64Decoder`, `QuotedPrintable`, `UUDecoder` (UUE and XXE alphabets, line validity), `BinHexDecoder`
  (alphabet, RLE `0x90`, header, forks, CRC-16/XMODEM), `CRC16`; `NameAllocator` (R5: last component,
  `/` `\` `:` control → `_`, `.` `..` empty → "decoded", 255-byte limit, " 2" numbering, case-insensitive).
- [ ] T002 `Sources/CommanderCore/Advanced/MIMEMessage.swift` (NEW): `MIMEHeaders` (folding, parameters with
  quoted strings, RFC 2231 with continuations and charsets, RFC 2047 B / Q words), `contentType`,
  `disposition`, `transferEncoding`, `fileName`, `isAttachment` (R3).
- [ ] T003 `Sources/CommanderCore/Advanced/FileCodec.swift` (NEW): `EncodeFormat`, `CodecError`,
  `DecodedFile`; `encode(source:name:format:into:progress:)` (R6), `encodedSize`; `decode(_:into:progress:)`
  — scanner of R2 (UUE / XXE / `begin-base64` / BinHex / MIME at the start, multipart with boundaries,
  message/rfc822, text parts scanned for blocks, plain Base64 second pass), files created with `O_EXCL` in
  the given folder, cancellation checks per read.
- [ ] T004 `Tests/CommanderCoreTests/FileCodecTests.swift` (NEW, temporary folder only): CRC-16 check value;
  Base64 and UUE round trips (0, 1, 2, 3, 44, 45, 46, 1000 bytes; non-ASCII name); `uudecode` and
  `base64 -D` read our output, our decoder reads `uuencode` and `uuencode -m` output; MIME single part,
  multipart with Base64 + quoted-printable attachments, nested multipart, message/rfc822, RFC 2047 and
  RFC 2231 names, unnamed non-text part, e-mail without attachments; UUE inside a text body; XXE; BinHex
  (with RLE and a literal `0x90`), BinHex CRC mismatch → damaged; incomplete UUE; two pieces joined across
  inputs with junk between; plain Base64; nothing found; hostile names stay inside; duplicate names
  numbered; cancellation throws.

**Checkpoint**: `swift test` green, commit.

## Phase 2: US1 + US2 + US3 — commands (P1 / P2)

- [ ] T005 `Sources/CommanderCore/Command.swift`: `encodeFile` "Encode File…", `decodeFile` "Decode File…"
  in the File menu after Combine Files; `Sources/AxolotlCommander/PanelViewController.swift`: handled, disk
  only, `canPerform` (a non-folder file among the targets), `perform`;
  `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`: `encode.format`.
- [ ] T006 `Sources/AxolotlCommander/Codec/CodecDialog.swift` (NEW): sheet (heading, "To:" with
  `DestinationMenuPopup` and ⌥↓ / ⌃D, the format popup for Encode, Cancel / Encode or Decode).
- [ ] T007 `Sources/AxolotlCommander/Codec/CodecOperations.swift` (NEW) and the shared helpers in
  `SplitCombineOperations.swift`: sources (folders left out and mentioned), target, free space, staging,
  `perform` with progress, move in with `ConflictAsker`, result message (written / incomplete / damaged /
  nothing found / left-out folders), refresh with the cursor on the first file, staging removed in every
  case.

**Checkpoint**: build without warnings, commit.

## Phase 3: Polish

- [ ] T008 `Resources/Localizable.xcstrings`: Czech for all new strings; `CHANGELOG.md` /
  `CHANGELOG.cs.md` (0.7.0 Added).
- [ ] T009 GUI check of [quickstart.md](quickstart.md) on the test copy; spec Status → Implemented.
