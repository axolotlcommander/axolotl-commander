# Data Model: Viewer Previews for JSON, SVG and Media

All core types live in `Sources/CommanderCore/Viewer/` and have no AppKit dependency.

## JSONDocument

| Field | Type | Notes |
|---|---|---|
| `bytes` | `[UInt8]` | the file content (BOM skipped); ranges below point into it |
| `nodes` | `[JSONNode]` | flat, in file order; index 0 is the root (a virtual root holding the lines for JSON Lines) |
| `isLines` | `Bool` | parsed as JSON Lines |

- `static func parse(_ data: Data, lines: Bool, isCancelled: () -> Bool) throws -> JSONDocument`
  (throws `JSONParseError` for a broken document, `CancellationError` when cancelled).
- Children are walked through `firstChild`/`childCount` and `nextSibling`.
- `func formatted() -> String`: the indented text of research R2 (two spaces per level, at most
  `maxIndentDepth` = 64 levels, tokens as written; JSON Lines one record after another).
- `var firstLineError: JSONParseError?`: the first bad line of a JSON Lines file, for the status line.

## JSONNode

| Field | Type | Notes |
|---|---|---|
| `kind` | `JSONKind` | `object`, `array`, `string`, `number`, `bool`, `null`, `error` (a bad JSON Lines line) |
| `key` | `Range<Int>?` | byte range of the key token (with quotes) in an object; nil in arrays and at the top |
| `index` | `Int` | position among siblings (the array index; the line index for JSON Lines) |
| `value` | `Range<Int>` | byte range of the value text (whole container for objects and arrays) |
| `parent` | `Int` | -1 for the root |
| `firstChild`, `childCount` | `Int` | children are contiguous by subtree: `nextSibling` is stored for O(1) walking |
| `nextSibling` | `Int` | -1 when last |
| `line`, `column` | `Int` | 1-based position of the value in the file (for errors and future "show in Text") |
| `error` | `JSONParseError?` | only for `error` nodes; line and column are absolute in the file |

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
