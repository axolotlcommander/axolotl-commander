# Contract: Viewer Table Preview (commands, keys, status bar)

The user-facing interface of the table preview. Keys are registered in `CommandRegistry` with
`scope: .viewer`, so they show in the menus and in Keyboard Shortcuts.

## Opening

| File | Default mode | Preview segment |
|---|---|---|
| `*.csv`, `*.tsv`, `*.tab` (any case), text content | Preview (table) | enabled |
| the same extensions, binary content | Hex | disabled |
| any other file | unchanged | unchanged |

## Commands active in table preview

| Command | Menu | Keys | Enabled when |
|---|---|---|---|
| Next / Previous File, Next / Previous Selected, First / Last File | File | Space, ⌫, ⌃Space, ⌃⌫, ⇧⌫, ⇧Space | as today |
| Copy to File… | File | ⌘S | as today (whole file) |
| Copy | Edit | ⌘C | at least one row is selected |
| Select All | Edit | ⌘A | rows > 0 |
| Find… / Find Next / Find Previous | Edit | ⌘F F7 / ⌘G F3 / ⇧⌘G ⇧F3 | rows > 0 |
| Go to Row… (title of `viewerGoTo`) | Edit | ⌘L | rows > 0 |
| Next Malformed Row (new) | Go | ⌘↓ | a malformed row exists after the selection in view order |
| Previous Malformed Row (new) | Go | ⌘↑ | a malformed row exists before it |
| Text / Hex / Preview | View | ⌘1 F5 / ⌘2 F4 / ⌘3 F6 | as today |
| Show Only Malformed Rows (new, check mark) | View | ⇧⌘D | malformed rows > 0, or the filter is on |
| First Row Is Header (new, check mark) | View | — | rows ≥ 1 |
| Separator ▸ Auto, Semicolon, Comma, Tab, Vertical Bar (new, check marks) | View | — | always in table preview |
| Text Encoding ▸ …, Next / Previous Encoding | View | F8 / ⇧F8 | as today; re-reads the table |
| Bigger / Smaller / Actual Size | View | ⌘+ / ⌘− / ⌘0 | the table font size, shared with the text mode |
| Reload | View | ⌘R | as today; keeps the separator, header and position |
| Close Viewer | — | Esc | Esc first cancels a running find or sort, or closes the find bar |

In table preview, Wrap Lines, Highlight Syntax, Zoom to Fit, Save Image As… and Load Images from
the Internet are disabled.

Inside the table (as in the file panels):
- ↑ ↓ Page Up/Down Home End move the selection;
- ⇧ with them extends it;
- ← → scroll sideways by one column;
- typing letters does nothing;
- a click selects, and ⌘-click / ⇧-click extend.

In the find field:
- Enter / ⇧Enter find the next / previous match;
- F3 / ⇧F3 do the same, so ⌘F, a query, Enter, F3, F3… never leaves the field;
- the other function keys of the viewer work as outside the field;
- Esc closes the find bar and returns to the table.

Find Next / Previous go cell by cell: the rest of the current row first, then the following
(preceding) rows, wrapping at the end.

## Column titles (mouse)

| Click | Result |
|---|---|
| a title, file fully read | sort cycle: ascending → descending → file order; an indicator is shown on that column |
| a title, still reading | notice "Sorting is available once the file is fully loaded." in the status bar; nothing changes |
| file over 256 MB, first sort | confirmation sheet: "Sort by “<title>”?" / "Sorting keeps this column's values in memory and may use a lot of it." / Sort, Cancel |

Column titles can be dragged to reorder and their edges dragged to resize. This is not saved.

## Status bar (table preview)

From left to right:
1. the mode control;
2. the encoding popup;
3. the separator popup (Auto, Semicolon, Comma, Tab, Vertical Bar);
4. the "Header" checkbox;
5. the info field;
6. the position field ("n / m" files).

The info field joins its parts with " · ", in this order:

1. `53 794 rows`, or while reading `counting… 120 000 rows`;
2. `19 columns`;
3. `2 malformed rows (expected 19 fields)`, only when N > 0;
4. `unclosed quote in row 7`, only when present;
5. a transient message: `Searching… 42 %`, `Sorting…`, `Not found.`, or the sorting notice.

Malformed row marker:
- **Row number cell**: `⚠ 4` in the system orange color.
- **Tooltip**: "Row 4 has 18 fields; most rows have 19."
- **VoiceOver label**: "Row 4, malformed: 18 of 19 fields".

## Clipboard

⌘C puts plain text on the pasteboard:
- the selected rows in view order, without the header;
- fields separated by tab, rows by LF;
- a field with a tab, quote, CR or LF is enclosed in quotes, with quotes doubled.
