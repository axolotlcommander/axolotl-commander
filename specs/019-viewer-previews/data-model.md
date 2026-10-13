# Data Model: Viewer Previews for JSON, SVG and Media

All core types live in `Sources/CommanderCore/Viewer/` and have no AppKit dependency.

## JSONFormatter

A namespace with one function; there is no document model (revised 2026-10-13, spec Clarifications
"memory"):

- `static func format(_ data: Data, lines: Bool, isCancelled: () -> Bool) throws -> Output`
  validates and formats in one pass over the UTF-8 bytes (BOM skipped) and writes the indented text of
  research R2 directly (two spaces per level, at most `maxIndentDepth` = 64 levels, tokens as written;
  JSON Lines one record after another). It throws `JSONParseError` for a broken document and
  `CancellationError` when cancelled.
- `Output.text`: the formatted text; `Output.firstLineError: JSONParseError?`: the first bad line of a
  JSON Lines file, for the status line.

## SplitText

Text for the viewer's text view with very long lines cut on screen only (research R3).

| Field | Type | Notes |
|---|---|---|
| `source` | `String` | the text as decoded or formatted |
| `display` | `String` | `source` with a line break inserted before each offset in `breaks` |
| `breaks` | `[Int]` | ascending UTF-16 offsets into `source`; empty when no line is longer than `maxLineLength` (10 000) |

- A cut goes after the last comma, semicolon or space within 200 units before the limit, otherwise at
  the limit, never inside a surrogate pair.
- `displayOffset(ofSource:)`, `displayRange(ofSource:)`, `sourceOffset(ofDisplay:)` and
  `sourceText(ofDisplay:)` map between the two; copy, Save Copy, Go to Line and highlighting use them.

## JSONParseError

`line`, `column` (1-based, in characters of the line), `reason` (English source string, localized in
the UI: unexpected character, unterminated string, unsupported JSON5 syntax, trailing data…).

## MediaDetails

| Field | Type |
|---|---|
| `duration` | `Double?` (seconds) |
| `container` | `String?` (e.g. "MPEG-4", "WAVE") |
| `audio` | `[AudioTrack]` — `codec`, `sampleRate`, `channels` |
| `video` | `[VideoTrack]` — `codec`, `width`, `height`, `frameRate` |

- `var summaryParts: [String]` — the status line items ("3:42", "AAC", "44.1 kHz", "Stereo",
  "1920 × 1080", "29.97 fps"), formatting tested in the core. Filling it from `AVURLAsset` is UI code.

## PreviewKind (UI, `ViewerWindowController`)

`markdown`, `html`, `image`, `table` (existing) + `json`, `vector`, `media`. Default mode is Preview for
all of them except: invalid JSON → Text, Preview disabled; JSON above 64 MB → Text, Preview on request.
Preview of `json` is the formatted text in the viewer's text view.

## SVGData

`static func unpack(_ data: Data, maxSize: Int) throws -> Data` — returns gzip-compressed data unpacked
(through the Compression framework), other data unchanged; throws over `maxSize`.
