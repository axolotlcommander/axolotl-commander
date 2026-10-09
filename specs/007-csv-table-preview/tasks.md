# Tasks: CSV Table Preview in the Viewer

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/viewer-table-ui.md](contracts/viewer-table-ui.md),
[quickstart.md](quickstart.md)

**Format**: `[ID] [P?] [Story] Description`

## Phase 1: Foundational (core reading)

- [X] T001 Write `CSVSeparator` in Sources/CommanderCore/Viewer/CSVFormat.swift:
  - the cases semicolon, comma, tab, bar, with their byte values.
- [X] T002 Write `CSVDialect` in Sources/CommanderCore/Viewer/CSVFormat.swift:
  - the separator, the encoding and `contentStart` (after the BOM);
  - a unit width of 2 for UTF-16.
- [X] T003 Write `CSVNumber.parse` in Sources/CommanderCore/Viewer/CSVFormat.swift:
  - the pattern from FR-013, with a decimal comma only when the separator is not a comma.
- [X] T004 Write the row splitter `CSVRow.fields(in:from:to:dialect:literalQuoteAt:)` in
  Sources/CommanderCore/Viewer/CSVIndex.swift:
  - RFC 4180 rules (FR-004, FR-005);
  - decoding through `TextDecoding`;
  - 1- and 2-byte units.
- [X] T005 Write the indexer in Sources/CommanderCore/Viewer/CSVIndex.swift:
  - a scanner that records `rowStarts` and `fieldCounts`;
  - unclosed-quote recovery (R3);
  - `CSVIndex` snapshots with `maxFields` and `isComplete`;
  - `CSVIndexer.index(data:dialect:)` as a cancellable `AsyncThrowingStream`.
- [X] T006 Write `CSVSample.detect` in Sources/CommanderCore/Viewer/CSVFormat.swift:
  - the sample: 64 KiB or 1 000 rows;
  - separator scoring and the tie order (R4);
  - numeric columns at 90 %;
  - the header rule (FR-010).
- [X] T007 [P] Write `CSVClipboard.tsv` in Sources/CommanderCore/Viewer/CSVClipboard.swift:
  - tab and LF separators;
  - fields with a tab, quote, CR or LF quoted, with quotes doubled.
- [X] T008 [P] Write tests in Tests/CommanderCoreTests/CSVTableTests.swift for:
  - parsing: quotes, doubled quotes, CR/LF/CRLF, the final line break, an empty line, a quote
    mid-field;
  - the BOM, UTF-16 LE/BE and Windows-1250;
  - unclosed-quote recovery;
  - detection on both example shapes and the tie order;
  - numbers, TSV, and streaming plus cancellation;
  - a performance check of indexing 10⁶ generated rows.

## Phase 2: User Story 1 + 2 — Table, large files (P1)

- [X] T009 [US1] Write `TablePreview` in Sources/AxolotlCommander/Viewer/TablePreview.swift:
  - the row-number gutter table, synchronized vertically;
  - the main view-based table, with columns added as `maxFields` grows;
  - titles from the header or 1, 2, 3…;
  - widths from the sample (40–400 pt);
  - right-aligned numeric columns;
  - ↵ for line breaks, truncation, and tooltips up to 10 000 characters;
  - an LRU cache of 512 rows;
  - the font size;
  - `onKey` passed to the viewer;
  - row selection, and the first visible row ⇄ byte offset.
- [X] T010 [US1] Change ViewerWindowController for `PreviewKind.table`:
  - `.csv`, `.tsv` and `.tab`, falling back to Hex for binary content;
  - show/hide, starting the indexer and cancelling it on step, reload or close;
  - re-reading on encoding and separator changes;
  - the status controls: a separator popup and a Header checkbox;
  - the info text (rows / counting…, columns);
  - position mapping (R10);
  - zoom.
- [X] T011 [US1] Wire table find into ViewerWindowController:
  - `HexFindBar` with `allowsHex = false`;
  - `CSVSearch` (Sources/CommanderCore/Viewer/CSVSearch.swift) in the background with a
    progress text;
  - Esc cancels;
  - the found cell is highlighted.
- [X] T012 [US1] Add Go to Row… (⌘L), ⌘C as TSV and ⌘A in table mode.
- [X] T013 [US1] Register the new commands in Sources/CommanderCore/Command.swift:
  - `viewerHeaderRow`;
  - `viewerSeparator` with a submenu like Text Encoding (MainMenuBuilder);
  - validation in the viewer.

## Phase 3: User Story 3 — Malformed rows (P1)

- [X] T014 [US3] Add malformed rows to `CSVIndex` (R7):
  - the histogram, the expected count (the larger count wins a tie) and the malformed list;
  - the header excluded when it is on;
  - recomputation without a rescan;
  - tests.
- [X] T015 [US3] Add the markers to `TablePreview`:
  - ⚠ and orange on the row number;
  - a tooltip and an accessibility label;
  - the status text "N malformed rows (expected M fields)" and "unclosed quote in row N".
- [X] T016 [US3] Add the commands `viewerNextMalformed` (⌘↓), `viewerPreviousMalformed` (⌘↑) and
  `viewerMalformedOnly` (⇧⌘D):
  - the filter keeps file row numbers and the selection.

## Phase 4: User Story 4 — Sorting (P2)

- [X] T017 [US4] Write `CSVSort` in Sources/CommanderCore/Viewer/CSVSort.swift:
  - key extraction;
  - numbers with non-numeric cells after them;
  - text deduplicated, sorted by the locale comparison (parallel above 50 000 distinct values)
    and turned into ranks;
  - stable, with empty cells last;
  - cancellable;
  - tests with an injected `cs_CZ` locale.
- [X] T018 [US4] Add title clicks to `TablePreview`:
  - the ascending → descending → file order cycle and the indicator;
  - before the file is fully read, a notice and no change;
  - a confirmation above 256 MB;
  - a progress text, with Esc cancelling;
  - the filter combines with the sort;
  - a reset on a separator, header, encoding or file change;
  - ⌘L, find and ⌘↓/⌘↑ follow the view order.

## Phase 5: Polish

- [X] T019 [P] Add en + cs strings in Resources/Localizable.xcstrings.
- [X] T020 [P] Update CHANGELOG.md (Unreleased → Added) and the README feature list if it
  mentions the viewer.
- [X] T021 Build without warnings and run `swift test`. GUI checks from quickstart.md in the test
  copy, plus the maintainer's export (local only).
- [ ] T022 Update docs/STATE.md (local), commit and open the PR.

## Dependencies

- T001–T007 come before everything else; T008 can be written alongside them.
- US1 + US2 (T009–T013) depend on Phase 1.
- US3 (T014–T016) depends on T005 and T009.
- US4 (T017–T018) depends on T005, T009 and T014 (filter combination).
- Polish comes last.

## Parallel opportunities

- T007 and T008 can run alongside T004–T006.
- T017 (core sort) can be written alongside T009–T016.
- T019 and T020 can run alongside T021.

## Implementation strategy

The MVP is Phase 1 + Phase 2: a usable table for files of any size. Then malformed rows, which
is the maintainer's main use, then sorting. Commit after each phase with a build without
warnings and green tests.
