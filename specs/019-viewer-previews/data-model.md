# Data Model: Viewer Previews for JSON, SVG and Media

All core types live in `Sources/CommanderCore/Viewer/` and have no AppKit dependency.

## JSONDocument

| Field | Type | Notes |
|---|---|---|
| `bytes` | `[UInt8]` | the file content (BOM skipped); ranges below point into it |
| `nodes` | `[JSONNode]` | flat, in file order; index 0 is the root (a virtual root holding the lines for JSON Lines) |
| `isLines` | `Bool` | parsed as JSON Lines |
| `error` | `JSONParseError?` | set when a whole-file parse failed; then `nodes` is empty |

- `static func parse(_ data: Data, lines: Bool, isCancelled: () -> Bool) throws -> JSONDocument`
  (throws `CancellationError`).
- `func children(of node: Int) -> Range<Int>`-like access through `firstChild`/`childCount` and
  `nextSibling`.
- `func keyText(_ node: Int) -> String?`, `func valueText(_ node: Int, limit: Int) -> String`
  (short display text, strings decoded and cut at `limit` characters with "…").
- `func path(of node: Int) -> String` (R2 format), `func copyValue(of node: Int) -> String` (R2 rules).
- `func search(_ text: String, from node: Int, backward: Bool, ignoreCase: Bool) -> Int?` over keys and
  value texts, wrapping around.

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
| `isDuplicate` | `Bool` | a later key with the same name in the same object |
| `message` | `String?` | only for `error` nodes |

## JSONParseError

`line`, `column` (1-based, in characters of the line), `reason` (English source string, localized in
the UI: unexpected character, unterminated string, unsupported JSON5 syntax, trailing data…).

## JSONTreeGroup (UI only)

The outline item for a range of 100 children of a large container: `parent`, `lower`, `upper`.
Displayed as `[0 … 99]` (arrays) or `{0 … 99}` (objects).

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
all of them except: invalid JSON → Text, Preview disabled; JSON above 20 MB → Text with the question.

## SVGData

`static func unpack(_ data: Data, maxSize: Int) throws -> Data` — returns gzip-compressed data unpacked
(through libarchive), other data unchanged; throws over `maxSize`.
