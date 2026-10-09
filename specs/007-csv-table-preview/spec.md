# Feature Specification: CSV Table Preview in the Viewer

**Feature Branch**: `007-csv-table-preview`

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "Next feature: a quick view for CSV. We have a preview for Markdown, so
there should be one for CSV as well; Quick Look can do it, so the app should do it too. Sorting
once the file is fully loaded (a notice is fine) and clearly marked bad rows, if it is not
complicated." Agreed in discussion: the table is a new kind of the F3 viewer's Preview mode
(⌘3/F6), next to Markdown, HTML and images; it is built for large data files and for checking
them.

## Clarifications

### Session 2026-10-09

- Q: Where do Find Next (F3) and Find Previous (⇧F3) go when a row has several matches? → A: To the
  next (previous) matching cell: the remaining cells of the same row first, then the following
  (preceding) rows. Found in the maintainer's check of the first build; FR-019 and User Story 1,
  scenario 8 follow it.
- Q: Do F3 and ⇧F3 work while the cursor is still in the find field (⌘F, type, Enter, F3, F3…)?
  → A: Yes. The viewer's function keys work while any field of the viewer is being edited, in every
  mode (FR-019a).
- Q: How do the keys move in the table? → A: As in the file panels: ↑ ↓ Page Up/Down Home End move
  the selection (⇧ extends it), ← → scroll by one column, and typing does not jump to rows (FR-018).

## User Scenarios & Testing *(mandatory)*

Typical files: Czech data exports separated by semicolons, in Windows-1250 or UTF-8, with CRLF
line ends, often without a header row. Two examples: 6 MB with 53 794 rows of 19 fields, and
150 MB with 858 722 rows.

### User Story 1 - Read a CSV file as a table (Priority: P1)

The user presses F3 on a `.csv` file. The viewer opens it in Preview mode as a table. Each field
of the file is a cell, and a column with row numbers runs down the left. When the first row is a
header, it becomes the column titles and stays visible while scrolling. The status bar shows the
number of rows and columns, the separator and the encoding. ⌘1 (Text) and ⌘2 (Hex) show the raw
file as they do today. Space and ⌫ move to the next or previous file in the panel, and Esc closes
the viewer.

**Why this priority**: this is the feature. Today a CSV file shows only as raw text in the viewer.

**Independent Test**: create a `.csv` file with a header row, a quoted field that contains the
separator, and a quoted field that contains a line break, in a test directory. Press F3 on it in
the test copy of the app and check the cells, the titles and the status bar.

**Acceptance Scenarios**:

1. **Given** a semicolon separated UTF-8 file with a header row and 3 data rows, **When** the user
   presses F3 on it, **Then** the viewer opens in Preview mode. It shows a table with the header
   cells as column titles, 3 rows numbered 1–3, and "3 rows · 4 columns · Semicolon · UTF-8" (or
   the equivalent wording) in the status bar.
2. **Given** a field `"Praha; centrum"` in a semicolon separated file, **When** the table is
   shown, **Then** the cell reads `Praha; centrum` and the row has the same number of cells as the
   other rows.
3. **Given** a quoted field with a line break inside it, **When** the table is shown, **Then** the
   field is one cell on one line with a visible line-break symbol. The full text is in the cell's
   tooltip, and the row number does not skip.
4. **Given** a Windows-1250 file with Czech diacritics, **When** it opens, **Then** the text reads
   correctly. Choosing another encoding in the existing encoding popup re-reads the table in that
   encoding.
5. **Given** a file without a header (the first row has empty cells or numbers), **When** it
   opens, **Then** the columns are titled 1, 2, 3… and the first row is data row 1.
6. **Given** a table, **When** the user turns "First Row Is Header" on or off, **Then** the first
   row moves between the titles and the data, and the row numbers update.
7. **Given** a comma separated file detected wrongly, **When** the user chooses another separator
   in the status bar, **Then** the table is read again with that separator.
8. **Given** a table, **When** the user presses ⌘F, types a word and presses Enter, **Then** the
   next cell containing it (ignoring case and diacritics) is highlighted, and its row is selected
   and scrolled into view. F3 (⌘G) goes to the next matching cell, in the same row first, and
   ⇧F3 (⇧⌘G, ⇧Enter) to the previous one.
9. **Given** a table, **When** the user presses ⌘L and enters 500, **Then** data row 500 is
   selected and scrolled into view.
10. **Given** two selected rows, **When** the user presses ⌘C, **Then** the clipboard holds the two
    rows as tab-separated text, one line per row, which pastes into Numbers as cells.
11. **Given** a table, **When** the user presses ⌘1, **Then** the text view shows the raw file at
    about the same position. ⌘3 returns to the table.

---

### User Story 2 - Large files open quickly (Priority: P1)

The user opens a file of hundreds of megabytes with hundreds of thousands of rows. The first
screen of rows appears almost at once. The rest of the file is read in the background while the
status bar counts rows. Scrolling to any place in the file stays smooth.

**Why this priority**: the files the maintainer checks are this large. A table that has to read
the whole file first, or keeps all of it in memory, is not usable for them.

**Independent Test**: generate a 1 000 000-row, 19-column file (about 150 MB) in a test
directory. Open it with F3 and measure the time to the first screen. Drag the scroller to the end
and back, and watch the app's memory.

**Acceptance Scenarios**:

1. **Given** a 150 MB file, **When** the user presses F3, **Then** the first screen of rows is
   shown within half a second. Meanwhile the status bar shows "counting…" with the rows read so
   far.
2. **Given** a file still being read, **When** the user scrolls or presses End, **Then** the
   table scrolls through the rows read so far without freezing. When reading finishes, the row
   count is final.
3. **Given** a file still being read, **When** the user presses Space (next file) or closes the
   viewer, **Then** reading stops at once.
4. **Given** a fully read 150 MB file, **When** the user scrolls through it, **Then** the app's
   memory stays well below the file size. Viewing keeps only the positions of rows, not their
   contents.

---

### User Story 3 - Find malformed rows (Priority: P1)

The user checks an export. Rows whose number of fields differs from the rest are marked clearly.
The status bar says how many there are. Keys jump from one to the next, and a view shows only
them.

**Why this priority**: checking exports for rows with the wrong number of fields is the
maintainer's daily task; today they use a separate validation script.

**Independent Test**: create a file where most rows have 19 fields, row 4 has 18 and row 9 has
20. Open it and check the markers, the count, the jumps and the filter.

**Acceptance Scenarios**:

1. **Given** that file, **When** it opens, **Then** rows 4 and 9 show a warning marker on the row
   number in the warning color, and the status bar reads "2 malformed rows (expected 19 fields)".
   Row 4 has an empty last cell and row 9 has an extra 20th column. The table has 20 columns, and
   only row 9 fills the last one.
2. **Given** the cursor on row 1, **When** the user presses ⌘↓ twice, **Then** rows 4 and then 9
   are selected. ⌘↑ goes back to row 4.
3. **Given** that file, **When** the user turns on View → Show Only Malformed Rows (⇧⌘D), **Then**
   only rows 4 and 9 are listed, still numbered 4 and 9. Turning it off shows all rows with row 4
   or 9 still selected.
4. **Given** a file with a quote opened in row 7 and never closed, **When** it opens, **Then** the
   status bar reports the unclosed quote in row 7. Row 7 is shown with the quote as an ordinary
   character and marked as malformed, and rows 8 and on are read normally.
5. **Given** a file where all rows have the same number of fields, **When** it opens, **Then** no
   row is marked and ⌘↓/⌘↑ do nothing (the commands are disabled).

---

### User Story 4 - Sort by a column (Priority: P2)

Once the whole file is read, the user clicks a column title to sort the rows by that column. The
second click sorts descending and the third returns to the file's order. Row numbers keep showing
where each row is in the file.

**Why this priority**: useful for finding extremes and duplicates. The table is valuable without
it.

**Independent Test**: create a file with a numeric column, a Czech text column and empty cells.
Click the titles and check the order.

**Acceptance Scenarios**:

1. **Given** a fully read file, **When** the user clicks the title of a numeric column, **Then**
   rows are ordered by value (2 before 10) with empty cells last. The title shows the sort
   direction.
2. **Given** a text column with "Čáslav", "cheb", "Brno", "Hradec", "Cvikov", **When** it is sorted
   ascending in the Czech locale, **Then** the order follows Czech rules, ignoring case: Brno,
   Cvikov, Čáslav, Hradec, cheb ("ch" comes after "h").
3. **Given** a sorted table, **When** the user clicks the same title a third time, **Then** the
   file's order returns.
4. **Given** a file still being read, **When** the user clicks a title, **Then** a short notice
   says sorting is available once the file is fully loaded, and nothing changes.
5. **Given** a large file, **When** sorting runs, **Then** a progress indicator is shown, the table
   stays usable in its previous order, and Esc cancels the sort without closing the viewer.
6. **Given** a sorted table, **When** the user presses ⌘L 500, **Then** the row with file row
   number 500 is selected wherever it is. Find and ⌘↓/⌘↑ follow the displayed order.

### Edge Cases

- **Empty file**: an empty table and "0 rows" in the status bar.
- **No separator found** (a single column): one column, and the separator popup shows Auto.
- **Only a header row**: the titles are shown with no data rows ("0 rows").
- **A field of several megabytes** (no line breaks): the cell shows the beginning, truncated, and
  the viewer stays responsive. The tooltip and ⌘C carry the whole field.
- **Binary content** with a `.csv` extension: opens in Hex, as the viewer does for binary files
  today.
- **The file changes on disk** while open: the same behavior as the text mode today. ⌘R reloads
  it.
- **Files in archives and on servers**: they open through the same temporary copy the viewer uses
  today.
- **NUL characters and invalid bytes**: shown with the replacement character, as in the text mode.
- **A file over the text mode's size limit**: still opens as a table.
- **A UTF-8 byte order mark**: not part of the first cell.
- **An empty line**: a row with one empty cell. Next to rows with more fields it counts as
  malformed.
- **A line break at the end of the file**: does not add a row.
- **Mixed line ends** (CR, LF, CRLF): each one ends a row outside quotes.
- **Very wide files** (hundreds of columns): scroll sideways, and the row number column stays in
  place.

## Requirements *(mandatory)*

### Functional Requirements

**Opening and modes**

- **FR-001**: Files with the extension `.csv`, `.tsv` or `.tab` (any case) MUST have a Table
  preview. The viewer MUST open them in Preview mode by default, as it does for Markdown, and
  Text (⌘1/F5) and Hex (⌘2/F4) MUST stay available.
- **FR-002**: Switching between Text, Hex and Preview MUST keep the approximate position in the
  file: the first visible row maps to its line or offset, and back.
- **FR-003**: Space/⌫ (next/previous file), ⌃Space/⌃⌫, ⇧Space/⇧⌫, Esc, ⌘R (reload) and ⌘S (copy
  to file) MUST work in the table as in the other modes.

**Reading the file**

- **FR-004**: The file MUST be read by RFC 4180 rules:
  - a field may be enclosed in double quotes;
  - a doubled quote inside a quoted field is one quote;
  - separators and line breaks inside a quoted field belong to the field;
  - outside quotes, CR, LF and CRLF each end a row;
  - spaces around fields are kept;
  - a line break at the end of the file does not add a row.
- **FR-005**: A quote that starts in the middle of an unquoted field MUST be an ordinary
  character.
- **FR-006**: A quoted field that is still open at the end of the file MUST NOT swallow the rest
  of the file. The quote that opened it MUST be treated as an ordinary character, reading MUST
  continue from that row, and the row MUST be malformed (FR-020). The status bar MUST name the row
  where the quote opened.
- **FR-007**: The separator MUST be detected from a sample at the beginning of the file among
  semicolon, comma, tab and vertical bar. The detection MUST choose the candidate that gives the
  most rows with the same field count above 1. On a tie, `.tsv`/`.tab` files prefer tab, then the
  order is semicolon, comma, tab, bar. When no candidate gives more than one field, the file is
  one column.
- **FR-008**: The user MUST be able to change the separator in the status bar and in the View
  menu (Auto, Semicolon, Comma, Tab, Vertical Bar). The table MUST then be read again. The choice
  applies to the current file and resets to Auto for the next file.
- **FR-009**: The text encoding MUST come from the viewer's existing detection, and the existing
  encoding popup and F8/⇧F8 MUST change it. A change MUST re-read the table. A byte order mark
  MUST NOT be part of the first cell.

**Header and columns**

- **FR-010**: The first row MUST be taken as the header when all of these hold:
  - the file has at least two rows;
  - every cell of the first row is non-empty and not a number (FR-013);
  - at least one column is numeric in the sampled following rows (FR-013), or none of the first
    row's values appears again in its own column among the sampled rows.
- **FR-011**: View → First Row Is Header (also in the status bar) MUST switch the header on or off
  for the current file and reset with the next file. Without a header the columns MUST be titled
  1, 2, 3… The header MUST stay visible while scrolling.
- **FR-012**: The table MUST have as many columns as its widest row. The first column holds the
  row numbers. A row number is the data row's position in the file, starting at 1 and not
  counting the header; it does not change when sorting or filtering.
- **FR-013**: A cell is a number when it is an optional sign followed by digits with at most one
  decimal point or comma (when the comma is not the separator) followed by more digits. A column
  is numeric when at least 90 % of its non-empty sampled cells are numbers. Cells of numeric
  columns MUST be right-aligned.
- **FR-014**: Each cell MUST be shown on one line. A line break inside a field MUST be shown as a
  visible symbol, and text that does not fit MUST be truncated. The tooltip MUST show the full
  field; above 10 000 characters it MUST show the beginning with a note that the field is longer.
- **FR-015**: Initial column widths MUST come from the sampled content and the title, within a
  minimum and a maximum. The user MUST be able to resize and reorder columns for the current file;
  this is not saved.
- **FR-016**: ⌘+, ⌘− and ⌘0 MUST change the table's text size as in the other modes.

**Status bar and navigation**

- **FR-017**: The status bar MUST show the row count ("counting… N" while reading), the column
  count, the separator, the encoding and the malformed-row count (FR-021).
- **FR-018**: The user MUST be able to select rows: click, ⇧-click, ⌘-click, ↑ ↓ Page Up/Down
  Home End (each moving the selection as in the file panels, ⇧ extending it) and ⌘A. ← and →
  MUST scroll sideways by one column. Typing letters MUST NOT select rows. ⌘C MUST copy the selected rows, without the header, as tab-separated
  text with one line per row. Fields that contain a tab, a quote or a line break MUST be quoted.
  With no selection, ⌘C copies nothing (the command is disabled).
- **FR-019a**: While a field of the viewer (a find bar) is being edited, the viewer's function-key
  commands (F3, ⇧F3, F7 and the others) MUST work as they do outside the field, in every mode.
- **FR-019**: Edit → Find (⌘F/F7) MUST open the viewer's find bar for the table. Matches MUST
  ignore case and diacritics. Find Next/Previous (⌘G/F3, ⇧⌘G/⇧F3, Enter/⇧Enter in the find bar)
  MUST go to the next/previous matching cell in the displayed order: the remaining cells of the
  current row first, then the following (preceding) rows. They MUST highlight the cell, select
  its row and wrap at the end. A row selected without a found cell is searched after (before)
  it as a whole. Searching a large file MUST run in the background, show that it is
  searching, and be cancellable with Esc. Go to Line or Offset (⌘L) MUST take a row number in
  Table mode and select that file row (in a filtered view, the nearest shown row).

**Malformed rows**

- **FR-020**: The expected field count is the most common field count among the rows read so far;
  for a fully read file, among all rows. A row with any other count is malformed. A malformed row
  MUST show a warning symbol and the warning color on its row number, and its tooltip MUST state
  the row's field count and the expected one. Markers MAY change while the file is still being
  read.
- **FR-021**: The status bar MUST show "N malformed rows (expected M fields)" when N > 0, and
  nothing about malformed rows when N = 0.
- **FR-022**: Go → Next Malformed Row (⌘↓) and Previous Malformed Row (⌘↑) MUST select the
  next/previous malformed row in the displayed order and scroll it into view. They MUST be
  disabled when there is none in that direction.
- **FR-023**: View → Show Only Malformed Rows (⇧⌘D) MUST list only malformed rows, keeping their
  file row numbers. Turning it off MUST keep the selected row selected.

**Sorting**

- **FR-024**: Clicking a column title MUST cycle through ascending, descending and the file's
  order. The title MUST show the current direction, and only one column sorts at a time.
- **FR-025**: Numeric columns (FR-013) MUST sort by value, with non-numeric cells after the
  numbers. Other columns MUST use the system's localized comparison ignoring case (Czech rules in
  the Czech locale). Empty cells MUST come last in both directions. Equal values MUST keep the
  file's order.
- **FR-026**: Sorting MUST be available only when the file is fully read. Before that, a click on a
  title MUST show a short notice that sorting becomes available once the file is loaded, and MUST
  change nothing.
- **FR-027**: Sorting MUST run in the background with a progress indicator. Esc MUST cancel it
  without closing the viewer, and the table MUST stay usable in its previous order until the
  sort finishes. Before sorting a file over 256 MB, the viewer MUST ask for confirmation, stating
  that sorting keeps the column's values in memory.
- **FR-028**: Sorting and the malformed-only filter MUST combine. Sorting MUST reset when the
  separator, header, encoding or file changes.

**Safety and accessibility**

- **FR-029**: The table MUST only read the file. Nothing MUST be written into it, next to it or
  anywhere else except the clipboard on ⌘C.
- **FR-030**: Reading, searching and sorting MUST NOT block the window. Reading MUST stop when the
  viewer moves to another file, reloads or closes.
- **FR-031**: The table MUST be accessible. VoiceOver MUST read the column titles, the row number
  and the cell text, and a malformed row MUST be announced as malformed.
- **FR-032**: All new texts MUST be localized (English and Czech).

### Deviations from the reference program

- The reference (Open Salamander / Tandem Commander) shows CSV through a viewer plugin. Here the
  table is part of the built-in viewer's Preview mode, alongside Markdown, HTML and images.
- Malformed-row markers, navigation and the malformed-only view are additions for checking data
  exports; the reference has no equivalent.
- The keys follow the app's own windows: ⌘↓/⌘↑ and ⇧⌘D match next/previous difference and Show
  Differences Only in the compare window.

### Key Entities

- **Table document**: one file read as rows of fields. It has a separator, an encoding, a header
  setting, a row count that grows while reading, the expected field count, the list of malformed
  rows and an optional unclosed-quote row.
- **Row**: a data row identified by its file row number. It has its field count and whether it is
  malformed; its fields are read from the file when shown.
- **View order**: the file's order, or the order sorted by one column in one direction. The
  malformed-only filter can apply on top of it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a file of any size up to 1 GB, the first screen of rows is visible within 0.5
  seconds of pressing F3 on a typical Mac with an internal SSD.
- **SC-002**: A 150 MB file with about 1 000 000 rows is read completely, with its row count and
  malformed rows final, within 10 seconds.
- **SC-003**: Scrolling from the start to the end of a 1 000 000-row file and back never freezes
  the window for more than 0.1 seconds.
- **SC-004**: Viewing (without sorting) a fully read 150 MB file adds less than 50 MB of memory to
  the app.
- **SC-005**: Every malformed row in a generated test file with known malformed rows is marked, and
  no other row is. ⌘↓ reaches each of them in order.
- **SC-006**: The two example exports (6 MB, 19 fields, no header; 150 MB) open with the right
  separator, encoding and header setting without any manual change.
- **SC-007**: Sorting a 1 000 000-row file by one column finishes within 5 seconds and can be
  cancelled at any time.
- **SC-008**: All acceptance scenarios can be performed with the keyboard alone, except sorting,
  which is done by clicking column titles.

## Assumptions

- **Extensions**: only `.csv`, `.tsv` and `.tab` get the Table preview. Other text files stay in
  Text mode, and there is no "open as table" command.
- **Large files**: the file is read through the system's file mapping as the viewer does today,
  so files larger than memory work for viewing. Sorting is the exception.
- **Detection sample**: the first 64 KiB or the first 1 000 rows, whichever ends first.
- **Numbers**: the number check (FR-013) is meant only for alignment, sorting and header
  detection; thousands separators, currency and dates are treated as text.
- **Not saved per file**: column widths, column order, the separator, the header setting and the
  sort order are kept for the current file only.
- **Quick Look**: the behavior of ⌘Y is unchanged.
- **Test data**: automated tests use only files they generate in a temporary directory. Real
  files provided by the maintainer are used only for local manual testing in the test copy of the
  app, and are never committed or uploaded.
- **Out of scope**:
  - editing cells or saving;
  - export;
  - Excel, Numbers, ODS and DBF formats;
  - formulas;
  - column filters and statistics;
  - multi-column sorting;
  - cell-by-cell (spreadsheet-style) selection;
  - a quick view panel that previews the file under the cursor in the other panel.
