# Quickstart: Folder and Command History Lists

## Automated

`swift build` gives no warnings and `swift test` is green (`HistoryListTests`).

## GUI check (test copy, scratchpad folders, browsing only)

1. Visit `a`, `b`, `c` in the left panel. Go → Folder History…: `c` is marked, the selection is on `b`.
2. Type `a`: the list narrows; Return opens `a`; Back returns to `c`.
3. Open the list again, ⌘Return on `b`: a new tab shows `b`, the old tab keeps its folder.
4. Open the list again, ⌥Return on `a`: the right panel shows `a`, the focus stays left.
5. Esc closes the list without changes.
6. Classic Commander: ⌥↓ in the panel opens the list.
7. Run `cd a` and `cd b` in the command line. Commands → Command Line History…: `cd b` first; Return
   puts it into the line with the caret at the end and runs nothing.
