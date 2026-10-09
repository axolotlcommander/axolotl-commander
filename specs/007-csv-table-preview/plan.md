# Implementation Plan: CSV Table Preview in the Viewer

**Branch**: `007-csv-table-preview` | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

## Summary

`.csv`, `.tsv` and `.tab` files get a fourth Preview kind in the F3 viewer: a table. The core
reads the memory-mapped file in one pass and records only row offsets and field counts, which
measured 0.1 s per 117 MB. A visible row is split from its bytes when it is drawn. Separator,
header and numeric columns are detected from a sample. Malformed rows come from a histogram of
field counts. Sorting runs once the file is fully read: deduplicated, locale-aware and parallel
for text. Find and copy work on the view order. The UI has two parts:
- a view-based `NSTableView` showing the rows indexed so far;
- a synchronized row-number gutter beside it.

Status bar controls and the new commands live in the existing viewer. See
[research.md](research.md).

## Technical Context

**Language/Version**: Swift 6.2, strict concurrency.

**Primary Dependencies**: Foundation in the core; AppKit in the UI. No new packages.

**Storage**: none. Per-file choices (separator, header, sort, column layout) are not saved.

**Testing**: Swift Testing suites in `Tests/CommanderCoreTests/CSVTableTests.swift`. They use
generated strings and files in `TestSandbox` only:
- reading, recovery, encodings;
- detection, malformed rows;
- sorting with an injected locale;
- search, TSV;
- a performance check on 10⁶ generated rows.

GUI checks follow [quickstart.md](quickstart.md) in the test copy. The maintainer's real exports
are used only locally.

**Target Platform**: macOS 15+.

**Performance Goals**:
- the first screen within 0.5 s for any size;
- full indexing of 150 MB within 10 s (measured ~0.15 s);
- sorting 10⁶ rows within 5 s;
- no main-thread stall over 0.1 s.

**Constraints**:
- read-only on the file;
- viewing memory is about 12 B/row plus a cache of 512 rows;
- reading, finding and sorting can be cancelled;
- texts in en + cs.

**Scale/Scope**:
- 5 new core files and 1 new UI file;
- 3 UI files touched;
- 1 new test file;
- ~25 strings.

## Constitution Check

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | The viewer only reads (FR-029); tests write only into `TestSandbox`; the maintainer's real files are never committed. |
| II Reference behavior | ✅ | The reference views CSV as a table through a plugin; the deviations (built into Preview, malformed tools, keys) are recorded in the spec. |
| III Native macOS | ✅ | `NSTableView`, the system locale comparison, VoiceOver, the String Catalog; all heavy work detached and cancellable. |
| IV Testable core | ✅ | Parser, indexer, detection, sort, search and TSV are pure core code covered by `swift test`. |
| V Clean-room, GPL | ✅ | No reference sources, no new dependencies, SPDX headers. |
| VI Incremental | ✅ | US1 → US2 → US3 → US4, each usable; the measured design is the simple one, and R5 stays unoptimized until measured. |
| VII Language | ✅ | English in git; Czech only in `Localizable.xcstrings`. |

Re-check after design: no violations.

## Project Structure

### Documentation

```text
specs/007-csv-table-preview/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md
├── contracts/viewer-table-ui.md
├── checklists/requirements.md
└── tasks.md                     # /speckit-tasks
```

### Source code

```text
Sources/CommanderCore/Viewer/CSVFormat.swift    # NEW: CSVSeparator, CSVDialect, CSVNumber, CSVSample (detection)
Sources/CommanderCore/Viewer/CSVIndex.swift     # NEW: scanner (1/2-byte units), CSVIndex, CSVIndexer (stream,
                                                #      unclosed-quote recovery), CSVRow.fields
Sources/CommanderCore/Viewer/CSVSort.swift      # NEW: key extraction, dedupe + parallel locale sort, order
Sources/CommanderCore/Viewer/CSVSearch.swift    # NEW: find over the view order, wrap-around, progress
Sources/CommanderCore/Viewer/CSVClipboard.swift # NEW: TSV with quoting
Sources/CommanderCore/Command.swift             # new viewer commands + keys (R11)
Sources/AxolotlCommander/Viewer/TablePreview.swift  # NEW: gutter + table, row cache, columns, markers,
                                                    #      sort clicks, find highlight, accessibility
Sources/AxolotlCommander/Viewer/ViewerWindowController.swift  # PreviewKind.table, binary fallback,
                                                    #      status controls, commands, position, Go to Row
Sources/AxolotlCommander/MainMenuBuilder.swift      # Separator submenu (like Text Encoding), if needed
Resources/Localizable.xcstrings                     # en + cs strings
Tests/CommanderCoreTests/CSVTableTests.swift        # NEW
```

**Structure Decision**: the existing layout. The core goes into `Sources/CommanderCore/Viewer/`
next to `TextDecoding` and `EncodingDetector`. The UI goes into `Sources/AxolotlCommander/Viewer/`
next to `ImagePreview` and `MarkdownPreview`.

## Delivery order

1. **US1 + US2 together** (the table on top of the indexer):
   - core format, index and row, with tests;
   - `TablePreview` showing rows as indexing proceeds;
   - controller wiring, status bar, find, Go to Row and copy;
   - commit.
2. **US3**: histogram and malformed list in the core, with tests; markers, ⌘↓/⌘↑, ⇧⌘D; commit.
3. **US4**: `CSVSort` with tests, title clicks, notice, progress, cancel, confirmation; commit.
4. **Polish**:
   - localization, accessibility labels, the Keyboard Shortcuts listing;
   - GUI checks from the quickstart;
   - `CHANGELOG.md`;
   - commit.

## Complexity Tracking

No violations.
