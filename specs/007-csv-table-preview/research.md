# Research: CSV Table Preview in the Viewer

Decisions for [plan.md](plan.md): Decision, Rationale, Alternatives.

**Measurements**: a throwaway benchmark (`swiftc -O`, not committed) ran on a generated file
with 1 000 000 rows of 19 semicolon-separated fields, about 117 MB:

| Step | Time |
|---|---|
| Byte scan recording row starts and field counts | 0.10 s |
| Whole-file UTF-8 validity (`String(data:encoding:)`) | 0.04 s |
| Extracting two columns as strings and numbers | 0.12 s |
| Sorting 1 M numbers | 0.005 s |
| Sorting 1 M cells with 8 distinct values (Czech locale) | 0.09 s |
| Sorting 1 M unique strings, single-threaded (Czech locale) | 7.7 s |

The Czech order came out right: Brno, Čáslav, České Budějovice, Hradec Králové, Cheb.

## R1 — Where the table lives

**Decision**: a fourth `PreviewKind.table` in `ViewerWindowController`, next to markdown, html
and image. `previewKind(for:)` returns it for `csv`, `tsv` and `tab`. After loading, a file with
binary content gets no table, so the mode falls back to Hex as today; this is needed because the
current rule picks Preview whenever a preview kind exists. The UI is a new
`Viewer/TablePreview.swift` view hidden and shown like `ImagePreview`.

**Rationale**: Preview mode already defaults per file, keeps ⌘1/⌘2, and handles the next file,
reload and encoding. A separate window or mode would duplicate all of that.

**Alternatives**:
- HTML rendered in the existing web view: cannot handle 10⁶ rows.
- Quick Look: no control over the header, malformed rows or sorting.

## R2 — Indexing the file

**Decision**: one pass over the memory-mapped `Data` the viewer already holds. The pass records
two arrays per row: `rowStarts: [Int]` (byte offset, plus one end entry) and
`fieldCounts: [UInt32]`. Fields are not stored; a visible row is split again from its bytes when
it is drawn.

How the pass handles encodings:
- **UTF-8 and the single-byte encodings** in `TextEncoding` are all ASCII-compatible. The
  separator, quote, CR and LF are single bytes that never occur inside a multi-byte UTF-8
  sequence, so the scan works on bytes.
- **UTF-16 LE/BE**: the same state machine reads 16-bit units, generic over a unit reader.
- **BOM**: the scan starts after it.

The pass runs detached. It publishes progress every 65 536 rows or 50 ms, whichever comes first,
and the table grows as the main actor receives each snapshot. `Task.checkCancellation()` runs
between chunks.

**Rationale**: the measured scan costs 0.1 s per 117 MB, so a 1 GB file is indexed in about 1 s.
Memory is 12 bytes per row: 12 MB for 10⁶ rows (SC-004).

**Alternatives**:
- Decoding the file to `String` first: double memory and slow for large files.
- Storing parsed fields: hundreds of MB.
- A line index without quote handling: wrong for fields that contain line breaks.

## R3 — Unclosed quote

**Decision**: when the scan reaches the end of the file inside a quoted field, it rewinds to the
start of the row where that field opened. It records `unclosedQuoteRow` and the quote's byte
offset, then rescans that row with the quote at that offset as an ordinary character. Scanning
then continues normally (FR-006). `TableRow.fields` gets the same offset, so it splits that row
the same way.

**Rationale**: no rows were registered while inside the quote, so nothing has to be undone.

**Limit**: each further unclosed quote costs one more scan to the end of the file. That needs
several stray quotes that each leave an odd count behind them, which is rare. The cost stays
linear per occurrence and is cancellable.

## R4 — Detection: separator, header, numeric columns

**Decision**: detection uses a sample of the first 64 KiB or the first 1 000 rows, whichever
ends first, ignoring a last partial row.

- **Separator**: for each candidate (`;` `,` tab `|`), split the sample with quote rules. The
  score is the number of rows having the most common field count, counted only when that count
  is above 1. The highest score wins. On a tie, `.tsv`/`.tab` prefer tab, then the order is
  `;` `,` tab `|`. With no score, the file is one column.
- **Numbers (FR-013)**: the pattern `^[+-]?[0-9]+([.,][0-9]+)?$` (the comma form only when the
  separator is not a comma).
- **Numeric column**: at least 90 % of its non-empty sampled cells are numbers.
- **Header (FR-010)**: the rule from the spec, evaluated on the sample.

**Rationale**: these rules are simple, deterministic and testable. The two example exports give
`;` with no header (empty cells and numbers in row 1), and the validation report gives `;` with
a header.

## R5 — Encoding detection on large files

**Decision**: keep the viewer's existing `EncodingDetector.detect` on the whole data. Whole-file
UTF-8 validity measured 0.04 s for 117 MB, so about 0.35 s per GB. If the first screen of a 1 GB
file misses SC-001, detection for `PreviewKind.table` uses the first 16 MiB instead. Invalid
bytes found later are already shown as U+FFFD.

**Rationale**: no change to shared behavior until it is shown to be needed (principle VI).

## R6 — Drawing the table

**Decision**: a view-based `NSTableView` with `numberOfRows` equal to the rows indexed so far,
minus the header. Cell views are reused.

- **Columns**: added when the widest row grows. Titles are the header cells or 1, 2, 3…
- **Row numbers**: a separate narrow `NSTableView` in its own scroll view to the left. It has no
  scrollers and its vertical scrolling follows the main table through `boundsDidChange`, the same
  pattern as `DiffView`'s common scrolling. It therefore stays in place when the table scrolls
  sideways.
- **Header**: the main table's header view stays on top natively.
- **Row cache**: split rows are kept in a small LRU cache of 512 rows, keyed by file row.
- **Cell text**: at most the first 1 000 characters are shown, with line breaks replaced by ↵
  (U+21B5). The tooltip shows up to 10 000 characters.
- **Column widths**: measured on the sample rows with the table font, between 40 and 400 points.
- **Font**: the system font at the viewer's font size, so ⌘+/⌘−/⌘0 work as in the text mode.

**Alternatives**:
- One table with the row number as its first column: it scrolls away sideways.
- `NSScrollView.addFloatingSubview`: unproven for this case.
- `NSCollectionView`: no built-in column header, resizing or reordering.

## R7 — Malformed rows

**Decision**: a histogram of field counts excluding the header row when the header is on. The
expected count is the histogram's maximum, with the larger field count winning a tie.

- **Malformed list**: an ascending list of file rows whose count differs. It is extended per
  chunk and rebuilt only when the expected count changes; that happens a few times early in
  indexing and costs O(rows).
- **Next/Previous Malformed Row**: binary search in that list in file order. In sorted order it
  walks the view order from the current position.
- **Malformed-only filter**: the malformed list mapped through the view order.

## R8 — Sorting

**Decision**:
1. **Extract keys** in the background over all rows. A numeric column (FR-013 on the sample)
   stores `Double`, with NaN for non-numeric cells and a flag for empty ones. A text column stores
   `String`.
2. **Sort text**:
   1. Deduplicate the values.
   2. Sort the distinct values with `compare(_:options: .caseInsensitive, locale: .current)`.
      Above 50 000 distinct values, split them into one chunk per active core, sort the chunks
      concurrently and merge them.
   3. Give each row the rank of its value.
3. **Order rows**: sort by `(rank or number, fileRow)`. That is stable and handles empty cells
   last in both directions.
4. **Result**: only the resulting `[Int32]` order is kept. Keys are freed.

Esc cancels between chunks. Files over 256 MB ask first (FR-027).

**Rationale**: the measured single-threaded cost for 10⁶ unique strings is 7.7 s. Split across 8
to 10 performance cores, plus an O(n log k) merge, that is about 1.5–2.5 s, which meets SC-007.
Deduplication makes the common case (repeated values) fast: 0.09 s.

**Alternatives**: ICU sort keys (`ucol_getSortKey` is not public API on macOS) and a hand-made
Czech key transform (fragile, wrong for other locales).

## R9 — Find

**Decision**: the existing `HexFindBar` with `allowsHex = false`. Its Ignore Case checkbox
applies; diacritics are always ignored (FR-019). The search runs detached over the view order
from the row after the selection, and wraps around.

- **Per row**: decode the row once with `range(of:options: [.diacriticInsensitive,
  .caseInsensitive?], locale: .current)`. Only on a hit is the row split to find the cell.
- **Feedback**: the status bar shows "Searching… n %". Esc cancels, or closes the bar when no
  search is running.
- **Result**: the row is selected and scrolled into view, and the cell is highlighted (selected
  text color background) until the selection changes.

## R10 — Position between modes, Go to Row, Copy

- **Position**: Table → Text/Hex converts the first visible row's byte offset into the existing
  fraction `rowStarts[r] / data.count`. Text/Hex → Table binary-searches the fraction's byte
  offset in `rowStarts`; past the indexed part, it scrolls to the last indexed row.
- **Go to Row**: ⌘L asks for a file row number: the "Go to Row…" title and the "Row number:"
  prompt. A row beyond the indexed part beeps while indexing is running. In a filtered view it
  takes the nearest shown row.
- **Copy (⌘C)**: the selected rows in view order. Fields are joined with tab and rows with LF. A
  field containing a tab, quote, CR or LF is quoted, with quotes doubled. The pasteboard type is
  plain text.

## R11 — Commands and keys

New viewer-scope commands in `CommandRegistry`:

| Command | Title | Menu | Keys |
|---|---|---|---|
| `viewerNextMalformed` | Next Malformed Row | Go | ⌘↓ |
| `viewerPreviousMalformed` | Previous Malformed Row | Go | ⌘↑ |
| `viewerMalformedOnly` | Show Only Malformed Rows | View | ⇧⌘D |
| `viewerHeaderRow` | First Row Is Header | View | — |
| `viewerSeparator` | Separator (submenu: Auto, Semicolon, Comma, Tab, Vertical Bar) | View | — |

The submenu is built like Text Encoding. ⌘↓/⌘↑ are free in `KeyMaps.viewer` and match the compare
window's next/previous difference. ⇧⌘D matches Show Differences Only. `viewerGoTo` becomes
enabled in table preview, titled "Go to Row…".

The status bar gets a separator popup and a "Header" checkbox, both visible only in table
preview. The info field shows rows, columns and malformed rows.

## R12 — Accessibility and localization

- **VoiceOver**: `NSTableView` gives row and column navigation. Column titles are the header
  cells. A malformed row's number cell gets the accessibility label "Row 4, malformed: 18 of 19
  fields".
- **Localization**: about 25 new strings go into `Resources/Localizable.xcstrings` (en + cs).
