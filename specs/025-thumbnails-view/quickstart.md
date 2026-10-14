# Quickstart: Thumbnails View

## Build and unit tests

```sh
swift build 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3
```

Expected: no warnings, all tests pass, among them `PanelGridTests` and `ThumbnailTests`.

## GUI check (test copy only)

Prerequisites: the test copy of the app (own bundle id `cz.acidek.axolotlcommander.gtest`) and a scratch
folder with generated images (a square PNG, a wide panorama JPEG, a tall PNG, a 1 × 400 pixel line), a PDF,
a text file, a subfolder, a file with a 120-character name, and a second scratch folder with 2 000 files.
Both panels point to the scratch folder. Mouse events only inside the test window, modifiers always released.

1. Cursor on the panorama, ⌃⌥3 → a grid with previews and names, View → Thumbnails checked, the cursor still
   on the panorama; the panorama and the line keep their shape.
2. → ← ↓ ↑ Home End Page Down Page Up move as in [data-model.md](data-model.md) (`.rows`).
3. Space marks and moves on; ⇧ + ↓ marks the items between; F5 offers the marked items (Esc).
4. ⌘+ → large cells, ⌘+ again nothing; ⌘− twice → small; ⌘ + wheel steps; Settings → Panels shows the size.
5. Click, ⌃-click, ⇧-click on cells; a rubber band from a gap marks cells; a drag of a marked cell cancelled
   with Esc keeps the marks; a drop of marked files onto the subfolder cell moves them (scratch folder only).
6. Return on the subfolder opens it in Thumbnails view; Backspace returns with the cursor on it.
7. The 2 000-file folder: opening and scrolling with Page Down and the wheel stay smooth; previews appear for
   the visible cells.
8. A zip in the scratch folder opened in Thumbnails view: type icons only.
9. ⌃⌥1 and ⌃⌥2 → the same cursor and marks in Detailed and Brief; Brief still behaves as before.
10. Quit and start the test copy → the panel comes back in Thumbnails view at the chosen size; nothing new
    was written into the scratch folders (`ls -la` before and after).
