# Quickstart: Synchronize Folders (GUI check)

Run on the test copy of the app (own bundle id), never the installed app. All files live in the session's
scratch folder.

## Setup

1. Make `sync/L` and `sync/R` in the scratch folder:
   - `same.txt` on both sides, same content and date;
   - `newer-left.txt` (left 1 hour + 10 s newer), `newer-right.txt` (right 10 min newer);
   - `fat.txt` with dates exactly 3600 s apart, `close.txt` 1 s apart;
   - `size.txt` same date, different size; `content.txt` same date and size, different bytes;
   - `only-left.txt`, folder `only-left-dir/` with two files, `only-right.txt`;
   - `sub/deep.txt` newer on the left; `kind` as a file on the left and a folder on the right;
   - `link` → `same.txt` on both sides; `.hidden` on the left; `build/x.o` on the left.
2. Point the left panel to `sync/L` and the right panel to `sync/R` (settings `panel.left.path` /
   `panel.right.path` before launch).

## Checks

1. **Menu**: Commands has "Synchronize Folders…" with ⌥⇧F10; with a panel in an archive it is greyed out.
2. **Sheet**: ⌥⇧F10 shows Left `…/L`, Right `…/R` and the defaults; Delete is disabled for Both ways;
   Esc closes it.
3. **Compare both ways**: Return → the window lists newer-left → , newer-right ←, only-left.txt →,
   only-left-dir (one row) →, only-right.txt ←, sub (folder row) and sub/deep.txt →, size.txt ≠, kind ≠;
   same.txt, fat.txt, close.txt, link and content.txt are equal (shown with the Equal filter on); .hidden
   follows Show Hidden Files.
4. **Content**: with Compare content on, content.txt becomes ≠.
5. **Masks**: ignore folders `build` → build/ is not listed.
6. **Rows**: Space on size.txt marks it excluded; → on size.txt sets copy to the right; = clears it; ← on
   only-left.txt beeps; F3 on size.txt opens Compare Files.
7. **Filters**: turning off Left Only hides the left-only rows; the summary line does not change.
8. **Run**: Return → the summary names the files and bytes per side and no deletions; Synchronize → files
   are copied, both panels refresh, the window compares again and only the ≠ rows the user left alone stay.
9. **One way with deleting**: options Left to right + Delete items missing on the left → only-right.txt
   shows ✕; the summary has "1 item to the Trash"; after the run it is in the Trash. Afterwards remove only that test item
   from the Trash; never empty the Trash or touch anything else in it.
10. **Refusals**: left `sync/L`, right `sync/L/sub` → the nested message; both `sync/L` → the same-folder
    message.
11. **Esc** closes the window; ⌥⇧F10 while it is open brings it to the front.
12. Remove `sync/` at the end.
