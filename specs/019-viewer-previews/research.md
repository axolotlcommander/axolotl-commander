# Research: Viewer Previews for JSON, SVG and Media

## R1 JSON parser

- **Decision**: a new order-preserving parser in the core
  (`JSONFormatter.format(_ data: Data, lines: Bool)`). It works on the UTF-8 bytes in one pass and writes
  the formatted text while it validates, copying keys, strings and numbers as byte ranges, so a 10 MB file
  does not allocate millions of strings. (The first version built a flat node array first; for the 26 MB
  test file that peaked near 1 GB, so it was replaced by the streaming formatter, spec Clarifications
  "memory".) It accepts `//` and `/* */` comments and trailing commas, keeps
  duplicate keys in file order, keeps number text exactly as written, and on
  the first error stops with the line, column and a short reason. A UTF-8 BOM is skipped.
- **JSON Lines** (`.jsonl`, `.ndjson`): each non-empty line is parsed as its own top-level value. A bad
  line is copied as written, the first one is reported, and the other lines are still formatted.
- **Rationale**: `JSONSerialization`/`JSONDecoder` lose key order and duplicates, reject comments and
  round big numbers; the existing `JSONValue` (settings) is an unordered dictionary. A hand-written
  byte scanner is fast enough for SC-001 (10 MB within 2 s) and fully testable.
- **Alternatives**: a third-party parser (new dependency, no comment support guarantees); converting
  JSONC to JSON first and then using Foundation (still loses order and duplicates).

## R2 JSON formatted view

- **Decision** (revised 2026-10-13, spec Clarifications "review"; it replaces a tree view built first):
  `JSONFormatter.format` writes the document indented by two spaces per level, members in file order,
  keys, strings and numbers as their original tokens (escapes kept), comments, trailing commas and the
  BOM dropped. Levels below 64 share the indentation of level 64, so a deeply nested file cannot make
  the text grow quadratically. JSON Lines: each record formatted on its own, one after another, a bad
  line copied as written, empty lines left out; `firstLineError` gives the first bad line for the
  status line.
- **View**: Preview of a JSON file shows the formatted text in the viewer's existing text view
  (`showsFormattedJSON`), with JSON highlighting whatever the extension, the system find bar (⌘F, ⌘G),
  selection and ⌘C, wrapping and zoom. The source is decoded again when Text mode comes back
  (`decodedAs` is reset). Go to Line stays a Text mode command.
- **Rationale**: the maintainer tried the tree and found formatted text enough; the text view already
  has every reading tool, so no new view, keys or commands are needed.
- **Alternatives**: the `NSOutlineView` tree with Key / Value / Type columns, Copy Path and Expand All
  (built, then dropped); a separate text view for Preview (duplicates the text view setup).

## R3 Large JSON

- **Decision** (revised 2026-10-13 after the GUI check): no question. Parsing and formatting always run
  in a detached task ("Formatting…" in the status line); stepping or closing cancels it. A JSON file
  larger than `ViewerDefaults.textLimit` (64 MB) opens in Text mode like other large text, even when the
  previous file was in Preview; ⌘3 formats it on request.
- **Rationale**: formatting 26 MB took about 5 s, while laying out the same single-line file in Text mode
  took about 90 s, so opening Text first and asking was the slow path. The 64 MB cap keeps the source and
  the formatted text within reasonable memory.
- **Long lines** (spec Clarifications "memory"): TextKit 2 lays out a whole paragraph at once, so the
  26 MB single line needed about 90 s and 4.6 GB. `SplitText` (data-model) inserts display-only line
  breaks into lines longer than 10 000 UTF-16 units; an experiment showed lines of 2 000–30 000 lay out
  instantly. Copy, Save Copy, Go to Line and highlighting map back to the source. Measured on the 26 MB
  file after the change: Preview formatted within a few seconds at 270 MB (the formatter alone 0.1 s), Text in about 3 s at 375 MB.
  Find: the text view's own find bar would search the displayed text and miss a match across an
  inserted break, so the viewer runs its own `NSTextFinder` with a client (`ViewerFindClient`) that
  hands out the source text and maps selection, scrolling and match rectangles to the display.
- **Alternatives for long lines**: a custom layout for one huge line (much more code); no wrapping for
  long lines (TextKit 2 still lays out the paragraph).
- **Alternatives**: the first design (above 20 MB open Text and ask "Format it?") — dropped for the
  reason above; asking before anything is shown (still slow when Text is chosen).

## R4 SVG

- **Decision**: draw SVG with the system image class (`NSImage(data:)`, which uses the system's SVG
  renderer since macOS 14; the app targets macOS 15). Checked on 2026-10-13: gradients, CSS classes and
  text draw; an `<image href="http://…">` is not loaded (a local test server got no request); scripts are
  not supported by the renderer at all. The picture goes into the existing `ImagePreview` with fit,
  zoom steps and actual size; the status line shows the drawing size (from the image) and "SVG".
  `.svgz` is unpacked with the system Compression framework (gzip header per RFC 1952, then raw deflate; the app's minimal libarchive header has no raw-format calls) before drawing, with a
  64 MB cap on the unpacked size.
- **Preview kind**: a new `PreviewKind.vector` for `svg` and `svgz` (also when the UTType conforms to
  `public.svg-image`), Preview the default, Text shows the highlighted XML (`svgz` unpacked).
  `prefersQuickLook` returns false for them, and image stepping in Preview accepts them.
- **Cannot draw**: `NSImage(data:)` returns nil or a zero size → the Preview area says the drawing
  cannot be shown, and Text is one key away.
- **Save Image As** stays for raster images only (disabled for SVG).
- **Alternatives**: a `WKWebView` page with the SVG as `<img>` (also script-free, but zoom and fit
  would need a second implementation and the network blocking is more moving parts).

## R5 Audio and video

- **Decision**: `MediaPreview` in the UI: an `AVPlayerView` (inline controls) inside a container view
  that keeps the keyboard focus, so the viewer's Space/⌫/Esc and our keys win over the player's own
  (the player view does not accept first responder). Return plays and pauses, ←/→ seek by 5 s, ↑/↓
  change the volume by 10 %. The status line shows the details: duration, container, codecs, sample rate,
  channels, and for video the frame size and frame rate (`AVURLAsset.load(.duration, .tracks)` and
  the tracks' format descriptions).
- **Which files**: a `PreviewKind.media` when the UTType conforms to `.audiovisualContent` and is in
  `AVURLAsset.audiovisualTypes()` (a synchronous check, so `prefersQuickLook` can use it). Such files
  open in the viewer; other audiovisual types keep going to Quick Look (FR-006). When the asset turns
  out not playable (`isPlayable` false or loading fails) the preview says so; Hex still works.
- **The `.ts` rule**: unchanged; a `.ts` file that starts as text opens as text.
- **Stepping**: in the image preview Space keeps stepping to the next picture (now raster or SVG); in
  the media preview to the next playable media file; elsewhere to any file, as today.
- **Lifetime**: playback never starts by itself; stepping, closing the window or leaving Preview mode
  pauses and releases the player. Media files are not decoded as text: Text mode for them shows the
  same "binary file" behavior as today (Hex the default fallback).
- **Loading**: the viewer's `Loaded` step maps the whole file; for media the player reads the URL
  itself, so `Loaded` only maps the file for Hex (mapping is lazy, so a large video costs no memory
  until Hex is shown).

## R6 .NET highlighting

- **Decision** in `SyntaxHighlighter.swift`:
  - F# (`fs fsi fsx`): a `code` definition with `//` and `(* *)` comments, strings (normal, verbatim
    `@"…"`, triple-quoted), characters, numbers, the F# keyword list and `#if/#else/#endif` lines.
  - Solution files (`sln`): a small `code` definition: `#` comments, strings, GUIDs as numbers,
    keywords `Project EndProject Global EndGlobal GlobalSection EndGlobalSection ProjectSection
    EndProjectSection`, `preSolution postSolution preProject postProject` as types.
  - XML: add `props targets vbproj fsproj nuspec slnx` to the XML extensions.
  - Razor (`cshtml razor`): a markup family variant: HTML as today, plus `@*…*@` comments, `@@` as text,
    `@identifier(.member | (…) | […])*` implicit expressions, `@(…)` explicit expressions, `@{…}` and
    `@code {…}` / `@functions {…}` blocks and `@if/@foreach/@for/@while/@switch/@using/@try (…) {…}`
    statements lexed as C# through the re-entrant `SyntaxEngine.lex` used for `<script>`. Inside a C#
    block a line whose first non-blank character is `<` is lexed as HTML again; directives at line
    start (`@page @model @using @inject @inherits @namespace @layout @attribute`) are keywords with the
    rest of the line as C#.
- **Rationale**: the existing engine already embeds JavaScript and CSS in HTML; Razor reuses that hook.
  A full Razor parser is out of proportion for a viewer.

## R7 Commands, menus and settings

- No new commands: the formatted JSON uses the text view's Copy, Find and Wrap commands.
- No new user preference (FR-009): the 64 MB limit is the existing Text mode constant.
- `validateMenuItem` gets the new kinds: zoom for `.vector`; find, wrap and highlighting for the
  formatted JSON as in Text mode; Save Image As only for raster images.
