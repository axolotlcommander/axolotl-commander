# Implementation Plan: Encode and Decode Files

**Branch**: `030-encode-decode` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (`Sources/CommanderCore/Advanced/`, unit tested, no AppKit):
  - `CodecDecoders.swift` (NEW): the streaming line reader over several files (R1); Base64,
    quoted-printable, UUE / XXE and BinHex 4.0 decoders with CRC-16/XMODEM (R4); safe and unique names (R5).
  - `MIMEMessage.swift` (NEW): header parsing (folding, parameters, RFC 2231, RFC 2047) and the part walk
    (multipart, message/rfc822, attachment vs. text) (R3).
  - `FileCodec.swift` (NEW): `encode` (Base64 with the MIME header, UUE) (R6); `decode` — the block scanner
    (R2) that writes every found file into the staging folder with `O_EXCL` and returns `DecodedFile`s;
    `encodedSize`; `CodecError`.
- **UI** (`Sources/AxolotlCommander/Codec/`):
  - `CodecDialog.swift` (NEW): one sheet for both commands — heading (the file name or the count), "To:"
    with the destination menu (`DestinationMenuPopup`, spec 029), for Encode the format popup (Base64 /
    UUE, remembered); buttons Cancel / Encode or Decode.
  - `CodecOperations.swift` (NEW): `OperationsController` extension — sources (marked files or the cursor,
    folders left out), target folder (the helpers of spec 029 shared), free space check, staging folder,
    `perform` with progress, moving the results in with `FileOperations.transfer(.move)` and `ConflictAsker`
    (spec 021), the result message, refresh and cursor (R7, R8).
  - `SplitCombineOperations.swift`: the target helpers (`defaultTargetFolder`, `targetFolder`,
    `checkSpace`, `createIfMissing`, `show`) become internal so both features use them.
  - `Command.swift`: `encodeFile` ("Encode File…"), `decodeFile` ("Decode File…") in the File menu after
    Combine Files, no default keys. `PanelViewController`: handled, disk only, `canPerform`, `perform`.
  - `AppSettingsCatalog.swift`: `encode.format`.
- Czech strings; still version 0.7.0 (one release with spec 029); `CHANGELOG.md` / `CHANGELOG.cs.md`.

## Technical Context

- Swift 6.2, AppKit, Swift Testing; macOS 15+. No new dependencies (`UniformTypeIdentifiers` is a system
  framework).
- **Storage**: one preference (the encode format).
- **Performance**: 1 MiB reads, decoders work on byte arrays; progress per read.
- **Constraints**: everything is written into the staging folder first; the target changes only through the
  move with the conflict question (constitution I); names from the input never leave the target (SC-003).

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Staging folder, `O_EXCL`, the conflict question of spec 021, safe names, cleanup of only this run's files; tests in a temporary folder; GUI test only in the scratchpad on the test copy. |
| II Reference | ✅ Encode / Decode as in the usual managers and the reference's plugin; deviations recorded in the spec. |
| III Native macOS | ✅ AppKit sheet like Split / Combine, progress sheet, String Catalog. |
| IV Testable core | ✅ All decoders, MIME, names and both directions in the core with unit tests, including `uudecode` / `base64` interoperability. |
| V Clean-room / GPL | ✅ Formats from public RFCs and descriptions; own code. |
| VI Incremental | ✅ Core decoders → MIME → codec → UI, each committed. |
| VII Language | ✅ English code and docs, Czech UI strings and changelog. |

## Project Structure

```text
specs/030-encode-decode/{plan,research,data-model,quickstart,tasks}.md

Sources/CommanderCore/Advanced/CodecDecoders.swift      NEW line reader, decoders, CRC-16, names
Sources/CommanderCore/Advanced/MIMEMessage.swift        NEW headers, parameters, encoded words
Sources/CommanderCore/Advanced/FileCodec.swift          NEW encode, decode (scanner), errors
Tests/CommanderCoreTests/FileCodecTests.swift           NEW
Sources/AxolotlCommander/Codec/CodecDialog.swift        NEW
Sources/AxolotlCommander/Codec/CodecOperations.swift    NEW
Sources/AxolotlCommander/SplitCombine/SplitCombineOperations.swift  shared target helpers
Sources/CommanderCore/Command.swift                     two commands
Sources/AxolotlCommander/PanelViewController.swift      enablement, perform
Sources/CommanderCore/Settings/AppSettingsCatalog.swift one preference
Resources/Localizable.xcstrings                         Czech strings
```

## Complexity Tracking

None.
