# Research: Viewer Previews for JSON, SVG and Media

## R1 JSON parser

- **Decision**: a new order-preserving parser in the core (`JSONDocument.parse(_ data: Data, lines: Bool)`).
  It works on the UTF-8 bytes in one pass and builds a flat array of nodes (parent index, first child,
  child count). It keeps byte ranges for keys and values instead of strings, so a 10 MB file does not
  allocate millions of strings. It accepts `//` and `/* */` comments and trailing commas, keeps
  duplicate keys in file order (marking the later ones), keeps number text exactly as written, and on
  the first error stops with the line, column and a short reason. A UTF-8 BOM is skipped.
- **JSON Lines** (`.jsonl`, `.ndjson`): each non-empty line is parsed as its own top-level value. A bad
  line becomes an error node with its message and the other lines still show.
- **Rationale**: `JSONSerialization`/`JSONDecoder` lose key order and duplicates, reject comments and
  round big numbers; the existing `JSONValue` (settings) is an unordered dictionary. A hand-written
  byte scanner is fast enough for SC-001 (10 MB within 2 s) and fully testable.
- **Alternatives**: a third-party parser (new dependency, no comment support guarantees); converting
  JSONC to JSON first and then using Foundation (still loses order and duplicates).

## R2 JSON tree view

- **Decision**: `JSONTreePreview` in the UI, an `NSOutlineView` with three columns (Key, Value, Type)
  over lightweight item objects created only for expanded nodes. Arrays and objects with more than 100
  children show them in groups of 100 (`[0 … 99]`), each a collapsed node. The first two levels are
  expanded on open.
- **Keys**: → / ← expand and collapse (← on a collapsed or leaf node selects the parent); ⌥→ / ⌥←
  expand or collapse the whole subtree (groups included); Return toggles the node. ⌘C goes through
  the existing `viewerCopy` command and copies the value; new commands `viewerCopyPath` (⇧⌘C),
  `viewerExpandAll` and `viewerCollapseAll` (View menu, no default key). Space, ⌫ and Esc reach the
  viewer first through `onKey`, as in the other previews.
- **Copy Value**: a string is copied decoded and without quotes; a number, boolean or null as written;
  an object or array as indented JSON in file order (comments dropped).
- **Copy Path**: `items[3].name`; a key that is not an identifier is written as `["two words"]`; a top
  level line of JSON Lines starts with its zero-based index, `[4].name`. The root alone copies `$`.
- **Find**: the existing `HexFindBar` (as for the table and page previews). The search runs over keys
  and value texts in the core (`JSONDocument.search`), in file order, wraps around, expands the parents
  of a match and selects it.
- **Rationale**: `NSOutlineView` gives the standard keyboard behavior, accessibility and dark mode for
  free; groups keep a 1 000 000-item array responsive.

## R3 Large JSON

- **Decision**: above 20 MB (`ViewerDefaults.jsonTreeLimit`, a constant) the viewer opens the file in
  Text mode and shows a sheet: "This JSON file is 34 MB. Show it as a tree? It may take a while." with
  **Show Tree** and **Text** (Esc = Text). Show Tree switches to Preview. Choosing Preview later with
  ⌘3 builds the tree without asking. Stepping to another large file asks again. The tree is always
  built in a detached task with a progress indicator; stepping or closing cancels it.
- **Rationale**: the maintainer asked for a question rather than a silent limit or a setting.

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

- New commands: `viewerCopyPath` ("Copy Path", Edit menu, ⇧⌘C), `viewerExpandAll` ("Expand All", View),
  `viewerCollapseAll` ("Collapse All", View). ⇧⌘C is free in the viewer scope (the Find window's Copy
  Name as Text is another scope). `viewerCopy` copies the JSON value when the tree is shown.
- No new user preference (FR-009): the 20 MB limit is a constant.
- `validateMenuItem` gets the new kinds: zoom for `.vector`; find for `.json`; Copy Path / Expand All /
  Collapse All only for `.json`; Save Image As only for raster images.
