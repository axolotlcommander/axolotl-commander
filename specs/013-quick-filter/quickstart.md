# Quickstart: Quick Filter

## Automated

`swift build` gives no warnings and `swift test` is green (`QuickFilterTests`).

## GUI check (test copy, scratchpad folders, browsing only)

1. View → Quick Filter, then type `tx`: only ".." and the `.txt` files are left, and the status line shows
   "Quick filter: tx".
2. Type a character that matches nothing: a beep, and the list stays.
3. ↓ / ↑ move among the matches; Backspace widens the list; Esc shows everything.
4. Filter again, press Tab (typing ends), then Esc in the panel: the filter is cleared.
5. Filter, open a folder: the new folder is unfiltered. Back: unfiltered.
6. View → Quick Filter with Last Text: the last text is applied.
7. Type `re` (quick search), then View → Quick Filter: the search becomes the filter.
8. Mark all, filter to one file, and press F8: the dialog names only that file. Cancel it.
