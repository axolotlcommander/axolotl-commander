# Data Model: Encode and Decode Files

All types are in `CommanderCore` (`Sources/CommanderCore/Advanced/`), `Sendable`, without AppKit.

## EncodeFormat

- Cases `base64`, `uue`; `fileExtension` (`b64`, `uue`); stored as the `encode.format` preference (raw
  value), default `base64`.

## EncodedLine (internal)

- `bytes: [UInt8]` without the line end; `ending: [UInt8]` (empty, LF or CR LF).
- Produced by `LineReader` over a list of files in order; `readBytes` for progress.

## DecodedFile

| Field | Meaning |
|---|---|
| `name` | Safe, unique name within the run (R5) |
| `url` | The file in the staging folder |
| `kind` | `mime`, `uue`, `xxe`, `binhex`, `base64` |
| `state` | `complete`, `incomplete` (data ended before its end marker), `damaged` (BinHex CRC mismatch) |
| `size` | Bytes written |

## NameAllocator (internal)

- `safeName(_ raw: String, fallbackExtension: String?) -> String` (R5) and `unique(_:)` with the set of names
  used in this run (case-insensitive), ` 2`, ` 3`, … before the extension.

## Block decoders (internal)

- `Base64Decoder` (streaming, 4-character groups, ignores other characters, stops at `=`), `QuotedPrintable`
  (per line), `UUDecoder` (alphabet: UUE or XXE, per line), `BinHexDecoder` (6-bit → RLE → header / forks
  with CRC-16/XMODEM, state machine).
- `CRC16.xmodem(_:)`.

## MIME (internal)

- `MIMEHeaders`: ordered (name, value) list with unfolded values; `contentType` (type/subtype lowercased +
  parameters), `disposition` (value + parameters), `transferEncoding`; `fileName` from `filename` /
  `name` with RFC 2231 and RFC 2047 decoding.
- Part handling: multipart (boundary stack), message/rfc822, attachment vs. text (R3).

## FileCodec (public)

- `encode(source:name:format:into:progress:) async throws -> URL` — writes `<name>.<ext>` into the given
  (staging) folder with `O_EXCL`.
- `encodedSize(_ size: Int64, format:) -> Int64` — the upper bound for the free space check.
- `decode(_ inputs: [URL], into staging: URL, progress:) async throws -> [DecodedFile]` — empty when nothing
  was found; throws `CancellationError` on cancel (the caller removes the staging folder).
- Errors: the `SplitCombineError` cases of spec 029 (`cannotRead`, `cannotWrite`, `notRegularFile`), so the
  messages are shared; `makeStaging(in:)` creates the staging folder.
