# Quickstart: File List and Main Window Fonts

Only on the test copy of the app (bundle id `cz.acidek.axolotlcommander.gtest`), both panels in test
folders of the session scratchpad.

1. `swift test --filter PanelFonts` — choice round trip, limits, steps, row height, defaults.
2. Settings → Appearance → Fonts: "File list" → Change… → Menlo 16 pt: both panels redraw in Menlo with
   taller rows while choosing; detailed, brief and thumbnails modes; marked items bold and red.
   The column titles and the status line follow 2 pt smaller; Folder History and the hot path menu list
   their entries in Menlo.
3. "Main window" → Change… → 15 pt: volume bar, drive row, tabs (two tabs open), path bar, command line and
   function keys larger, the file lists unchanged; the divider does not move; the narrowest panel keeps the
   first items.
4. ⌘L in a panel: the path field is monospaced at the main window size; so is the command line.
5. "Default" on each row, then "Restore Default Fonts": the look of a fresh install; buttons disabled.
6. Quit and start again: the chosen fonts are back.
7. View → Bigger / Smaller / Default File List Font: 1 pt steps, disabled at the limits and at the default.
8. Czech UI: the texts of the Fonts section fit.
