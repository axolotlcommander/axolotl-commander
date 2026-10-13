# Feature Specification: Viewer Previews for JSON, SVG and Media

**Feature Branch**: `019-viewer-previews`

**Created**: 2026-10-13

**Status**: Implemented (GUI check pending)

**Input**: User description: "For the next spec: preview of JSON, SVG, possibly WAV, videos and media in
general; syntax highlighting for .NET sources (C#) if it is not there yet."

## Context

The F3 viewer has three modes: Text (with syntax highlighting), Hex and Preview. Preview exists today for
Markdown, HTML, images that the system image reader can open, and tables (CSV/TSV). Files with no
preview of their own but with a system preview (PDF, fonts, audio, video, and images the image reader
cannot open, such as SVG) are handed to the floating Quick Look window instead of the viewer. The
viewer's own features are therefore unavailable there: stepping to the next or previous file, Text and
Hex modes, find and encodings.

- **JSON**: shown as highlighted text only. A long or minified file is hard to read.
- **SVG**: an image to the user but text to the viewer's image reader, so F3 shows it in Quick Look and
  the XML source is not one keystroke away.
- **Audio and video** (WAV, MP3, AAC, FLAC, MP4, MOV…): Quick Look plays them, outside the viewer.
- **.NET sources**: C# (`.cs`), Visual Basic (`.vb`) and the XML project files `.csproj`, `.xaml`,
  `.resx` are highlighted already. F# (`.fs`, `.fsi`, `.fsx`), Razor (`.cshtml`, `.razor`), solution
  files (`.sln`) and the other MSBuild files (`.props`, `.targets`, `.vbproj`, `.fsproj`, `.nuspec`) are
  shown as plain text.

The Quick View panel (spec 016) uses the system preview and is not changed by this spec.

## Clarifications

### Session 2026-10-13

The maintainer asked for this spec without implementation, to keep the work in the plan. All answers
below were *decided while writing the spec; confirmed by the maintainer on 2026-10-13*:

- Q: Scope? → A: One spec with four parts in priority order: JSON tree, SVG, audio/video, .NET
  highlighting. Each part can be planned and shipped on its own.
- Q: How is JSON shown? → A: A collapsible tree in Preview mode (keys, values, types, item counts);
  Text mode keeps the highlighted source. Preview is the default for JSON files, as it is for Markdown.
- Q: Comments and trailing commas (JSONC, JSON5)? → A: The tree accepts comments and trailing commas;
  other JSON5 syntax falls back to Text mode with a note.
- Q: SVG? → A: Rendered as an image in Preview mode (fit, zoom, actual size, like images); Text mode
  shows the highlighted XML. Scripts in the SVG do not run and nothing is loaded from the internet.
- Q: Audio and video? → A: A player in Preview mode (play/pause, position, volume) for the formats the
  system can play, with duration and format details. Media then opens in the viewer instead of Quick
  Look, so stepping through files works. Formats the system cannot play keep going to Quick Look.
- Q: PDF and fonts? → A: Stay with Quick Look (out of scope).
- Q: Where does the JSON tree start? → A: The first two levels expanded; the rest collapsed.

### Session 2026-10-13 (scheduling)

The maintainer scheduled the spec for 0.5.0 and answered the questions found against the current viewer:

- Q: Space is the viewer's Next File key; what does it do in the media player? → A: Space stays Next
  File everywhere, so a folder of media can be stepped through. Return plays and pauses, ← and → move
  the position by 5 seconds, ↑ and ↓ change the volume.
- Q: More keys in the JSON tree? → A: ⌥→ / ⌥← expand or collapse the whole subtree, Return toggles the
  node, ⌘C copies the value, ⇧⌘C copies the path; Expand All and Collapse All are in the View menu.
  Space stays Next File.
- Q: Large JSON files? → A: Above 20 MB the viewer asks before building the tree ("Show as a tree? It
  may take a while"), with Tree and Text as answers. The limit is fixed, not a setting.
- Q: Scope and branch? → A: All four parts, in the order JSON, SVG, .NET highlighting, media; a commit
  after each. The branch builds on `023-folder-sync`, and everything ships in 0.5.0. If media turns out
  hard, it moves to a spec of its own.

### Session 2026-10-13 (plan)

Found while planning and confirmed by the maintainer ("pokracuj jak doporucujes"):

- Copy Value: a string without quotes, a number as written, an object or array as indented JSON in file
  order without comments.
- Copy Path: `a["two words"][1]` for keys that are not identifiers; JSON Lines paths start with the line
  index (`[4].name`); the root is `$`.
- Space in the image preview steps to the next picture (raster or SVG), in the media preview to the
  next playable media file, elsewhere to any file.
- Save Image As stays for raster images only.
- Media details are shown in the status line, as image details are.
- Expand All and Collapse All are in the View menu without a default key.

### Session 2026-10-13 (review)

After trying the tree the maintainer decided that formatted text is enough ("showing the JSON formatted
would be quite enough"; the Type column is not needed). This replaces the tree answers above (the
questions about the tree's start, its keys, Copy Value, Copy Path and Expand All / Collapse All):

- Q: How is JSON shown? → A: Preview shows the document as indented, highlighted text in the text view,
  with the text view's find, selection, copy (⌘C copies the selected text), wrapping and zoom. There is no
  tree: the tree keys (→/← expand, ⌥→/⌥←, Return), Copy Value, Copy Path (⇧⌘C), Expand All and Collapse
  All are dropped, and so are the Type column, duplicate marks and item counts.
- Formatting: two spaces per level (deeper than 64 levels share the indentation of level 64), members in
  file order, keys, strings and numbers exactly as written (escapes are kept), comments, trailing commas
  and a BOM dropped, duplicate keys kept as they are.
- JSON Lines: one record after another, each indented; a bad line is kept as written and the status line
  names the first bad line; empty lines are left out.
- Large files: above 20 MB the viewer opens Text and asks whether to format the file (Show Formatted /
  Text, Esc = Text). ⌘3 later formats without asking. *Replaced the same day after the GUI check, see
  the next session.*
- Invalid JSON is unchanged: Text with the place of the first error in the status line, Preview disabled.

### Session 2026-10-13 (GUI check)

The GUI check showed that formatting the 26 MB test file takes about 5 seconds, while Text mode needs
about 90 seconds to lay out the same file (one 26 MB line), and the question appeared only after that.
The maintainer chose to format without asking:

- Q: Large JSON? → A: No question. Every JSON file up to the Text mode limit (64 MB) opens formatted,
  with "Formatting…" in the status line until the text is ready; stepping or closing cancels it. A larger
  file opens in Text mode (the start of the source, as for other large text), and ⌘3 formats it on
  request.

### Session 2026-10-13 (memory)

After the GUI check the maintainer asked that a 26 MB file must not take gigabytes ("a 26 MB file cannot
take GB"):

- Text mode with a huge line: lines over 10 000 characters are split for display only (a change of the
  earlier edge case that left Text mode as it was). Copying, saving and Go to Line keep the source text;
  the status line says the long lines are split. A find match across a split is not found (accepted
  limit for now).
- Formatting no longer builds a node list: the formatter writes the text during its validating pass.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read a JSON file formatted (Priority: P1)

A user presses F3 on a JSON file, for example a minified API response or a settings export. The viewer
opens in Preview mode with the document indented and highlighted, one member per line. The user scrolls,
finds and copies text as in Text mode, and switches to Text mode for the source as written.

**Why this priority**: JSON is the most common structured text a developer opens, and a minified file is
unreadable without formatting.

**Independent Test**: open a minified 1 MB JSON file and a settings export; scroll, find a key, copy a
selection, switch to Text and back.

**Acceptance Scenarios**:

1. **Given** a valid JSON file, **When** the user presses F3, **Then** Preview mode shows the indented,
   highlighted document, and Text mode still shows the highlighted source as written.
2. **Given** the formatted text, **When** the user presses ⌘F, ⌘G or ⌘C, wraps lines or zooms, **Then** it
   behaves as in Text mode; Space stays Next File.
3. **Given** keys, strings or numbers with escapes or beyond double precision, **Then** they appear
   exactly as written in the file.
4. **Given** invalid JSON, **Then** the viewer opens in Text mode and says where the first error is
   (line and column); Preview is disabled for that file.
5. **Given** the user moves to the next file (the viewer's next-file key), **Then** the next JSON file
   opens in Preview mode too.

---

### User Story 2 - See an SVG file as an image (Priority: P1)

A user presses F3 on an SVG file. The viewer shows the drawing in Preview mode, fitted to the window,
with the same zoom commands as for images, and Text mode shows the XML source with highlighting.

**Why this priority**: SVG is very common in projects, and today F3 leaves the viewer for it.

**Independent Test**: open an icon SVG, a large drawing and an SVG with a script and an external
image; zoom; switch to Text; step to the next file.

**Acceptance Scenarios**:

1. **Given** an SVG file, **When** the user presses F3, **Then** the viewer (not Quick Look) opens in
   Preview mode with the drawing fitted to the window.
2. **Given** the preview, **When** the user zooms in, out, to actual size or to fit, **Then** it behaves
   as the image preview does.
3. **Given** an SVG with a script or a reference to an internet resource, **Then** the script does not
   run and nothing is requested from the network.
4. **Given** an SVG that cannot be drawn, **Then** Preview says so and Text mode shows the source.

---

### User Story 3 - Play audio and video in the viewer (Priority: P2)

A user presses F3 on a sound or video file. The viewer shows a player in Preview mode: play/pause,
position, volume, the duration and the format. The user can step to the next or previous file without
leaving the viewer.

**Why this priority**: useful for reviewing many media files in a row; Quick Look already covers single
files.

**Independent Test**: open WAV, MP3, AAC, FLAC, MP4 and MOV files; play, pause, seek; step to the next
file; close the viewer while playing.

**Acceptance Scenarios**:

1. **Given** a media file the system can play, **When** the user presses F3, **Then** the viewer opens
   in Preview mode with a player; playback does not start on its own.
2. **Given** the player is shown, **When** the user presses Return, **Then** playback starts or pauses;
   ← and → move the position by 5 seconds, ↑ and ↓ change the volume, and Space still moves to the next
   file.
3. **Given** a file is playing, **When** the user steps to another file or closes the viewer, **Then**
   the playback stops.
4. **Given** a sound file, **Then** the preview shows its duration, format, sample rate and channels;
   a video shows its frame size too.
5. **Given** a media format the system cannot play, **Then** F3 keeps handing it to Quick Look, as
   today.
6. **Given** the Hex mode, **Then** the bytes of a media file stay viewable.

---

### User Story 4 - Highlight the rest of the .NET sources (Priority: P3)

A user opens F#, Razor, solution and MSBuild files with F3 and sees them highlighted, like C#.

**Independent Test**: open one file of each new extension in Text mode.

**Acceptance Scenarios**:

1. **Given** a `.fs`, `.fsi` or `.fsx` file, **Then** F# keywords, strings, comments (`//`, `(* *)`)
   and numbers are highlighted.
2. **Given** a `.cshtml` or `.razor` file, **Then** the HTML parts are highlighted as HTML and the
   `@` code parts as C#.
3. **Given** a `.sln` file, **Then** its sections, keys, GUIDs and strings are highlighted.
4. **Given** a `.props`, `.targets`, `.vbproj`, `.fsproj` or `.nuspec` file, **Then** it is highlighted
   as XML.

---

### Edge Cases

- **Large JSON** (tens of MB): formatting runs off the main thread, and the viewer stays responsive.
  Above 64 MB (the Text mode limit) the file opens in Text mode, and ⌘3 formats it on request.
- **A huge minified file in Text mode** (one line of tens of MB): lines longer than 10 000 characters are
  split on screen only, so the file opens in seconds; copy, Save Copy and Go to Line use the original
  text, and the status line says "long lines split for display". Find does not match text across such a
  split.
- **Very deep nesting**: indentation stops growing after 64 levels, so the formatted text stays about as
  long as the source.
- **Duplicate keys** in an object: all are shown in file order.
- **Numbers beyond double precision**: shown exactly as written in the file.
- **JSON Lines** (`.jsonl`, `.ndjson`): each record is formatted on its own. A bad line is kept as
  written, the status line names the first one, and the others are still formatted.
- **JSON in an archive or on a server**: opens as F3 opens such files today.
- **An SVG that is huge or slow to draw**: drawing can be cancelled by closing or moving to another
  file.
- **Compressed SVG** (`.svgz`): shown like `.svg`.
- **A media file without sound or video tracks**, or a broken file: Preview says it cannot be played;
  Hex works.
- **Text files that the system types as media** (the ".ts" TypeScript/MPEG-2 case): the existing rule
  stays. A file with a source code extension that starts as text opens as text.
- **Dark mode**: the highlighting and the player follow the system appearance. An SVG keeps its own colors on a
  neutral background.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The viewer MUST offer formatted JSON in Preview mode for `.json`, `.jsonc`, `.json5`
  (comments and trailing commas only), `.geojson`, `.jsonl`, `.ndjson` and other files whose content
  type is JSON. Preview MUST be the default mode for them up to 64 MB; larger files MUST open in Text
  mode with Preview available on request.
- **FR-002**: The formatted text MUST be indented by two spaces per level (at most 64 levels), keep
  members in file order and keys, strings and numbers exactly as written, and drop comments and
  trailing commas. It MUST be highlighted and offer the text view's find, selection, copy, wrapping and
  zoom. Space MUST stay Next File.
- **FR-003**: Invalid JSON MUST open in Text mode with the position of the first error; Preview is then
  disabled.
- **FR-004**: The viewer MUST render SVG (`.svg`, `.svgz`) in Preview mode with the image zoom commands.
  It MUST NOT run scripts or load anything from the network. F3 MUST no longer hand SVG to Quick Look.
- **FR-005**: The viewer MUST play audio and video formats the system can play, in Preview mode. Media
  details MUST be shown, playback MUST never start by itself and MUST stop on a file change or close.
  Return plays and pauses, ←/→ seek by 5 seconds, ↑/↓ change the volume; Space stays Next File. Such
  files MUST no longer go to Quick Look.
- **FR-006**: Media formats the system cannot play, PDF and fonts MUST keep going to Quick Look.
- **FR-007**: Text mode MUST highlight F# (`.fs`, `.fsi`, `.fsx`), Razor (`.cshtml`, `.razor`), `.sln`,
  and as XML `.props`, `.targets`, `.vbproj`, `.fsproj`, `.nuspec`.
- **FR-008**: Text and Hex modes MUST stay available for every file this spec previews. The next/previous
  file keys MUST work across previews of different kinds.
- **FR-009**: Any new viewer preference MUST be a user preference in the settings export. The 64 MB
  JSON limit is the fixed Text mode limit and is not a preference.

### Key Entities

- **JSON document**: the parsed values in file order with their position in the source, used to check
  the file and to write the formatted text.
- **Media details**: duration, container format, codecs, sample rate, channels, frame size.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A 10 MB minified JSON file shows formatted within 2 seconds on the maintainer's machine,
  and the viewer stays responsive while it is formatted.
- **SC-002**: F3 on SVG, WAV, MP3 and MP4 files never opens Quick Look; stepping through a folder of
  mixed files stays in one viewer window.
- **SC-003**: The JSON parser and formatter (comments, trailing commas, duplicates, big numbers, escapes,
  error positions, JSON Lines, deep nesting) and the new highlighting rules have automated tests.

## Assumptions

- The system's own media playback and web rendering are good enough for the formats in scope. No
  third-party decoders are added.
- The formatted JSON is read-only and never written to disk.

## Out of Scope

- Editing JSON or SVG in the viewer.
- A JSON tree, JSON Schema validation, JSONPath queries, and formatting/minifying a file on disk.
- Full JSON5 (unquoted keys, single quotes, hexadecimal numbers): such files open in Text mode.
- Playlists, subtitles chosen by the user, or audio waveforms and spectrograms.
- Previews of PDF, fonts, Office documents or 3D models (they stay with Quick Look).
- Changing the Quick View panel (spec 016).

## Deviations from the classic reference

- Classic two-panel managers add such previews through lister plugins. Here they are built into the
  viewer, with no plugin interface.
