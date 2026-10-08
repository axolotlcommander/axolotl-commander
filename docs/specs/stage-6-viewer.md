# Stage 6 — F3 viewer and F4 editor (specification)

Reference: `../tandemcommander/features/viewer.md`, the help `viewer_*.htm`, `basicwork_view.htm`,
`basicwork_edit.htm`. Step 6 in `../tandemcommander/docs/macos-port/04-kroky.md`.

## Behavior
- **F3** opens the custom viewer in a separate window (multiple windows may be open at once). Images, PDF,
  audio/video and folders still use Quick Look (custom viewers by type are stage 10).
  Quick Look stays on ⌘Y and now also on ⌥F3 (alternative viewer, like Alt+F3 on Windows).
- **Text / Hex** mode (⌘1 or F5 / ⌘2 or F4); automatically: a binary file → Hex.
- The **encoding** is determined once for the whole file: BOM → UTF-16 heuristic without BOM (ASCII text in UTF-16
  is also valid UTF-8, hence earlier) → whole file is valid UTF-8 → Windows-1250/ISO-8859-2 heuristic → default encoding from settings. Switcher in the window (popup
  in the status bar + menu View → Encoding), F8/⇧F8 next/previous, "Set as default".
  The encoding actually in use is always shown. Switching never touches the file.
- Text: wrapping ⌃W, search ⌘F (system find bar), ⌘G/⌘⇧G next/previous, ⌘L go to line,
  ⌘C, ⌘A, ⌘+/⌘−/⌘0 font size, ⌘R reload, ⌘S saves the selection (or the whole text) to a file.
- Hex: 16 bytes per line, offset, hex, characters (according to the single-byte encoding), search for text or
  hex bytes, ⌘L go to offset (decimal, `0x…`, `$…`, `…h`), mouse selection, ⌘C copies hex.
- Other files of the panel: space bar next, ⌫ previous, ⌃space bar/⌃⌫ next/previous selected,
  ⇧⌫ first, ⇧space bar last. The list is a snapshot of the panel at the moment of opening.
- Esc closes the viewer; the cursor in the panel stays. Title = full name, subtitle = folder,
  proxy icon (representedURL).
- Large files: mapped data (`.alwaysMapped`), virtualized hex (draws only visible lines),
  text decodes at most 64 MiB (the rest only in Hex, announced in the status bar).
- **F4** opens the file under the cursor in the editor from settings (default TextEdit). **⇧F4** asks for a
  name, creates an empty file in the panel's directory (an existing one is only opened), puts the cursor on it, opens the editor.

## Core (`Sources/CommanderCore/Viewer/`) — interface
See the subagent brief in the transcript; files `TextEncoding.swift`, `EncodingDetector.swift`,
`HexFormat.swift`, `ByteSearch.swift`, `FileSequence.swift`, tests `Tests/CommanderCoreTests/ViewerTests.swift`.
