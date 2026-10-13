# Feature Specification: Viewer Previews for JSON, SVG and Media

**Feature Branch**: `019-viewer-previews`

**Created**: 2026-10-13

**Status**: In progress (scheduled for 0.5.0 on 2026-10-13)

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

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read a JSON file as a tree (Priority: P1)

A user presses F3 on a JSON file, for example a minified API response or a settings export. The viewer
opens in Preview mode with a tree: objects and arrays can be expanded and collapsed, every node shows
its key, a short value or the item count, and its type. The user moves through the tree with the
keyboard, copies a value or its path, and switches to Text mode for the source.

**Why this priority**: JSON is the most common structured text a developer opens, and the tree is the
largest gain in readability.

**Independent Test**: open a minified 1 MB JSON file and a settings export; expand, collapse, copy a
path and a value, find a key, switch to Text and back.

**Acceptance Scenarios**:

1. **Given** a valid JSON file, **When** the user presses F3, **Then** Preview mode shows the tree with
   the first two levels expanded, and Text mode still shows the highlighted source.
2. **Given** the tree has focus, **When** the user presses → or ←, **Then** the node under the cursor
   expands or collapses (on a collapsed or leaf node ← moves to the parent). ⌥→ / ⌥← do the same for
   the whole subtree, Return toggles the node. ↑/↓, Page Up/Down, Home/End move as in other lists;
   Space stays Next File.
3. **Given** a node, **When** the user presses ⌘C (Copy Value) or ⇧⌘C (Copy Path), **Then** the
   clipboard holds the value as JSON text or the path in the form `items[3].name`.
4. **Given** the tree, **When** the user searches for text (⌘F), **Then** matching keys and values are
   found one after another and their parents are expanded to show them.
5. **Given** invalid JSON, **Then** the viewer opens in Text mode and says where the first error is
   (line and column); Preview is disabled for that file.
6. **Given** the user moves to the next file (the viewer's next-file key), **Then** the next JSON file
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

- **Large JSON** (tens of MB): the tree is built off the main thread with progress, and the viewer stays
  responsive. Above 20 MB the viewer asks first whether to show the tree or the text; stepping to such
  a file asks again.
- **Very deep or very long arrays**: long arrays show their items in groups (for example 100 at a time)
  so expanding one does not freeze the viewer.
- **Duplicate keys** in an object: all are shown in file order, and the duplicates are marked.
- **Numbers beyond double precision**: shown exactly as written in the file.
- **JSON Lines** (`.jsonl`, `.ndjson`): each line is a top-level node. A bad line is marked and the
  others still show.
- **JSON in an archive or on a server**: opens as F3 opens such files today.
- **An SVG that is huge or slow to draw**: drawing can be cancelled by closing or moving to another
  file.
- **Compressed SVG** (`.svgz`): shown like `.svg`.
- **A media file without sound or video tracks**, or a broken file: Preview says it cannot be played;
  Hex works.
- **Text files that the system types as media** (the ".ts" TypeScript/MPEG-2 case): the existing rule
  stays. A file with a source code extension that starts as text opens as text.
- **Dark mode**: the tree and the player follow the system appearance. An SVG keeps its own colors on a
  neutral background.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The viewer MUST offer a JSON tree in Preview mode for `.json`, `.jsonc`, `.json5`
  (comments and trailing commas only), `.geojson`, `.jsonl`, `.ndjson` and other files whose content
  type is JSON. Preview MUST be the default mode for them; above 20 MB the viewer MUST ask before
  building the tree.
- **FR-002**: The tree MUST show key, type, a short value or item count per node. It MUST support
  keyboard expand/collapse (→/←, ⌥→/⌥← for a subtree, Return), Copy Value (⌘C), Copy Path (⇧⌘C),
  Expand All and Collapse All (View menu), and find. Space MUST stay Next File.
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
- **FR-009**: Any new viewer preference MUST be a user preference in the settings export. The 20 MB
  JSON limit is fixed and is not a preference.

### Key Entities

- **JSON node**: key or index, type (object, array, string, number, boolean, null), value text, children,
  path, position in the source.
- **Media details**: duration, container format, codecs, sample rate, channels, frame size.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A 10 MB minified JSON file shows its tree within 2 seconds on the maintainer's machine,
  and the viewer stays responsive while it builds.
- **SC-002**: F3 on SVG, WAV, MP3 and MP4 files never opens Quick Look; stepping through a folder of
  mixed files stays in one viewer window.
- **SC-003**: The JSON parser and tree model (comments, trailing commas, duplicates, big numbers, error
  positions, JSON Lines, paths) and the new highlighting rules have automated tests.

## Assumptions

- The system's own media playback and web rendering are good enough for the formats in scope. No
  third-party decoders are added.
- The JSON tree is read-only.

## Out of Scope

- Editing JSON or SVG in the viewer.
- JSON Schema validation, JSONPath queries, and formatting/minifying a file on disk.
- Full JSON5 (unquoted keys, single quotes, hexadecimal numbers): such files open in Text mode.
- Playlists, subtitles chosen by the user, or audio waveforms and spectrograms.
- Previews of PDF, fonts, Office documents or 3D models (they stay with Quick Look).
- Changing the Quick View panel (spec 016).

## Deviations from the classic reference

- Classic two-panel managers add such previews through lister plugins. Here they are built into the
  viewer, with no plugin interface.
