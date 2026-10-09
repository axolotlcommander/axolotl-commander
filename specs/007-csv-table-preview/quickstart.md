# Quickstart: validating the CSV Table Preview

## Prerequisites

- A build with no warnings: `swift build`.
- `swift test` is green, including the new `CSVTableTests` suites.
- The test copy of the app (own bundle id) is built and running. Every file below lives in a
  scratch directory that the tester creates and later removes. Nothing is written anywhere else.

## Generated test files

Create them in a scratch directory (`$T`) with any script:

| File | Content | Checks |
|---|---|---|
| `header.csv` | UTF-8; `;`; header `name;city;amount;note`; 3 rows; one field `"Praha; centrum"`; one field with a line break inside quotes | US1 1–3, 5–6, 11 |
| `cp1250.csv` | the same rows encoded in Windows-1250 | US1 4 |
| `comma.csv` | `,` separated; numbers with a decimal point | US1 7, FR-013 |
| `noheader.csv` | the first row has empty cells and numbers (like an export) | US1 5, FR-010 |
| `malformed.csv` | 19 fields per row; row 4 has 18, row 9 has 20 | US3 1–3 |
| `quote.csv` | row 7 opens a quote that is never closed | US3 4 |
| `sort.csv` | a numeric column with 2, 10, empty and `x`; a text column with Čáslav, cheb, Brno, Hradec, Cvikov | US4 1–3, 6 |
| `big.csv` | 1 000 000 rows × 19 fields, about 120–150 MB | US2, SC-001–004, SC-007 |
| `empty.csv`, `one.csv` (a single column), `onlyheader.csv` | edge cases | Edge Cases |
| `binary.csv` | random bytes containing NUL | opens in Hex |

## Unit tests (core)

```sh
swift test --filter CSV
```

What they cover:
- **Reading**: RFC 4180 cases (quotes, doubled quotes, CR/LF/CRLF, a final line break, an empty
  line), a quote in the middle of a field, an unclosed quote with recovery, the BOM, UTF-16
  LE/BE, Windows-1250.
- **Detection**: separators and their tie order; the header rule on both example shapes;
  numeric columns.
- **Malformed rows**: the histogram, the expected count with a header on and off, and the list.
- **Sorting**: numbers, Czech text with an injected `cs_CZ` locale, empty cells last, stable,
  cancellation.
- **Find and clipboard**: diacritics and case, wrapping around, TSV quoting.
- **Large file**: `big.csv` generated in a temporary directory; indexing finishes in under 2 s in
  release builds and is marked as a performance check.

## GUI checks (test copy, keyboard)

1. **US1**: F3 on `header.csv` opens the table with titles and 3 rows, and the status bar reads
   `3 rows · 4 columns`. Check these keys:
   - ⌘1 → text, ⌘3 → table;
   - ⌘F `praha` Enter → row 1 selected;
   - ⌘L `2` → row 2;
   - ⇧↓, then ⌘C, then paste in TextEdit → two lines separated by tabs;
   - Space → the next file; Esc closes the viewer.
2. **US1**: `cp1250.csv` reads correctly. F8 changes the encoding and the table is read again.
   The separator popup set to Comma re-splits `header.csv` into one column.
3. **US3**: `malformed.csv` reads `2 malformed rows (expected 19 fields)`.
   - ⌘↓ ⌘↓ reaches rows 4 and then 9, and ⌘↑ goes back to 4.
   - ⇧⌘D shows only rows 4 and 9; ⇧⌘D again shows all rows.
4. **US3**: `quote.csv` shows `unclosed quote in row 7` and rows 8 and on are normal.
5. **US2**: `big.csv` shows its first rows within 0.5 s while `counting…` runs. Then:
   - End and ⌘↑ work while it is still reading;
   - Space during reading moves to the next file at once;
   - memory in Activity Monitor stays below the file size + 50 MB.
6. **US4**: in `sort.csv`, clicking the numeric title gives 2, 10, x, empty, and a second click gives 10, 2, x, empty;
   the third click restores the file order. The text column orders Brno, Cvikov, Čáslav, Hradec,
   cheb. In `big.csv`, a click while it is reading shows the notice. After reading, sorting the
   unique-text column shows `Sorting…`, and Esc cancels it.
7. **Edge cases**:
   - `empty.csv` shows `0 rows`;
   - `one.csv` shows one column with the separator popup on Auto;
   - `onlyheader.csv` shows the titles and `0 rows`;
   - `binary.csv` opens in Hex with Preview disabled.

## Maintainer's real files (local only)

The maintainer's exports are used only for manual checks in the test copy (SC-006). They are
never copied into the repository, the test sources or any upload. Expected result: `;`, the
right encoding, no header for the 19-field export, and 0 malformed rows unless the file really
has them.
