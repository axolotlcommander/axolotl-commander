# Data Model: CSV Table Preview

All types live in `CommanderCore` (no AppKit) unless marked UI. Row numbers here are **file
rows**: 0-based indices into the index; the UI shows `fileRow + 1 - (header ? 1 : 0)`.

## CSVSeparator (enum)

`semicolon`, `comma`, `tab`, `bar`. Each case has a byte value and a localized title in the UI.
`CSVSeparator?` = Auto.

## CSVDialect

| Field | Type | Rule |
|---|---|---|
| separator | `CSVSeparator?` | nil = one column (no separator found) |
| encoding | `TextEncoding` | from the viewer; UTF-16 → 2-byte units |
| contentStart | `Int` | byte offset after the BOM |

## CSVSample (detection result, R4)

| Field | Type | Rule |
|---|---|---|
| separator | `CSVSeparator?` | best score, tie order by extension, then `; , tab |` |
| hasHeader | `Bool` | FR-010 on the sample |
| numericColumns | `Set<Int>` | ≥ 90 % of non-empty sampled cells match FR-013 |
| rows | `[[String]]` | sampled rows (for column widths) |

`CSVSample.detect(data:, dialect without separator, preferTab:) -> CSVSample` is pure. The
sample is 64 KiB or 1 000 rows, whichever ends first.

## CSVIndex (value snapshot, grows while indexing)

| Field | Type | Notes |
|---|---|---|
| rowStarts | `[Int]` | byte offset of each row + one end offset (`count = rows + 1`) |
| fieldCounts | `[UInt32]` | per row |
| histogram | `[UInt32: Int]` | field count → rows (header excluded when on) |
| expectedFields | `Int` | the histogram's maximum; the larger count wins a tie |
| malformed | `[Int]` | ascending file rows with `fieldCounts[r] != expectedFields` |
| maxFields | `Int` | widest row → number of columns |
| unclosedQuote | `(row: Int, offset: Int)?` | R3 |
| isComplete | `Bool` | the end of the file has been reached |

Invariants:
- `rowStarts` is strictly increasing;
- the last entry is the end of the content;
- an empty file has 0 rows.

`malformed` and `expectedFields` are recomputed when the header setting changes, without
rescanning.

## CSVIndexer

`CSVIndexer.index(data:dialect:) -> AsyncThrowingStream<CSVIndex, Error>` runs detached. It yields
snapshots every 65 536 rows or 50 ms and a final one with `isComplete = true`. It ends on
cancellation. An implementation may yield deltas instead, as long as the consumer ends up with
the same `CSVIndex`.

## CSVRow

`CSVRow.fields(in data:, from start:, to end:, dialect:, literalQuoteAt: Int?) -> [String]`
splits and decodes one row by FR-004 and FR-005. Decoding goes through `TextDecoding.decode`, so
invalid bytes become U+FFFD. The `literalQuoteAt` offset comes from `unclosedQuote` for that row.

## CSVNumber

`CSVNumber.parse(_ cell: String, separator:) -> Double?`, using the FR-013 pattern.

## TableOrder (view order)

| Field | Type | Notes |
|---|---|---|
| sort | `(column: Int, ascending: Bool)?` | nil = file order |
| order | `[Int32]?` | file rows in sorted order; nil = identity |
| malformedOnly | `Bool` | filter on top |
| rows | computed | the displayed file rows: the identity, `order`, or either filtered by `malformed` |

State transitions of `sort`: nil → ascending → descending → nil, one column at a time. A change
of separator, header, encoding or file resets it to nil. `malformedOnly` survives sorting.

## CSVSort

`CSVSort.order(data:, index:, dialect:, column:, numeric:, ascending:, header:) async throws -> [Int32]`
follows R8:
- stable;
- empty cells last;
- non-numeric cells after the numbers in a numeric column;
- text by `compare(options: .caseInsensitive, locale:)`;
- the locale is injected for tests.

## CSVSearch

`CSVSearch.next(query:, ignoreCase:, data:, index:, dialect:, rows: [Int] view order, from position:, backward:)
async throws -> (position: Int, column: Int)?` follows R9:
- diacritics are always ignored;
- the search wraps around;
- progress is reported through a callback.

## CSVClipboard

`CSVClipboard.tsv(_ rows: [[String]]) -> String` (R10 quoting).

## TablePreview (UI)

An `NSView` holding:
- the row-number table and the main table;
- the current `CSVIndex`, `CSVDialect`, `CSVSample` and `TableOrder`;
- the row cache (LRU 512).

Callbacks to the controller: `onKey`, `onStatusChange`, `onHeaderClickWhileIndexing`.
