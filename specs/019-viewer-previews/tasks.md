# Tasks: Viewer Previews for JSON, SVG and Media

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md),
[data-model.md](data-model.md), [quickstart.md](quickstart.md). Tests are requested by the spec (SC-003).

## Phase 1: Foundational

- [X] T001 ~~Commands `viewerCopyPath`, `viewerExpandAll`, `viewerCollapseAll` in
  `Sources/CommanderCore/Command.swift`~~ — added for the tree, removed again by T014.

## Phase 2: User Story 1 — formatted JSON (P1)

- [X] T002 [US1] (partly superseded by T014: `keyText`, `valueText`, `path`, `copyValue`, `search` and
  duplicate marks were removed) `JSONDocument`, `JSONNode`, `JSONKind`, `JSONParseError` in
  `Sources/CommanderCore/Viewer/JSONDocument.swift` (research R1, data-model): byte parser with
  comments, trailing commas, BOM, duplicates marked, numbers as written, JSON Lines with error nodes,
  1-based line/column errors ("unsupported JSON5 syntax" for unquoted keys, single quotes, hex numbers),
  cancellation; `keyText`, `valueText(limit:)`, `path(of:)`, `copyValue(of:)`, `search`.
- [X] T003 [US1] (partly superseded by T014: the path, copy and search tests were replaced by
  formatting tests) Tests in `Tests/CommanderCoreTests/JSONDocumentTests.swift`: every value kind, nesting,
  key order, duplicates, big number text, escapes and surrogate pairs in keys and values, comments and
  trailing commas, JSON5 rejections with positions, error line/column, JSON Lines (good, bad, empty
  lines), paths (identifier, `["two words"]`, arrays, JSON Lines `[4]`, root `$`), copy value rules,
  search forward/backward/wrap/ignore case, a generated 10 MB document parses within 2 s (release
  timing is checked in the GUI; the test only asserts it finishes and counts nodes).
- [X] T004 [US1] (partly superseded by T014: the limit is `jsonFormatLimit` and the sheet asks Show
  Formatted / Text) `PreviewKind.json` in `Sources/AxolotlCommander/Viewer/ViewerWindowController.swift`:
  extensions `json jsonc json5 geojson jsonl ndjson` and UTTypes conforming to `.json`; parse in the
  detached load; invalid JSON → Text with the error in the status line and Preview disabled; above 20 MB
  (`ViewerDefaults.jsonTreeLimit`) open Text and ask (sheet: Show Tree / Text, Esc = Text); ⌘3 later
  builds without asking; cancellation on step/close.
- [X] T005 [US1] ~~`JSONTreePreview`~~ (replaced by T014) in `Sources/AxolotlCommander/Viewer/JSONTreePreview.swift`:
  `NSOutlineView` with Key / Value / Type columns, items for expanded nodes only, groups of 100, first
  two levels expanded, `onKey` first, → ← ⌥→ ⌥← Return, duplicate mark, dark mode colors from
  `SyntaxColors`; wired into `show`/`showPreview`/`validateMenuItem`/`find` (HexFindBar)/`closeFindBar`/
  `updateInfo` (node count, path of the selected node) and the commands `viewerCopy`, `viewerCopyPath`,
  `viewerExpandAll`, `viewerCollapseAll`.

**Checkpoint**: build without warnings, `swift test` green, commit "[Spec 019] JSON tree preview".

- [X] T014 [US1] Formatted JSON instead of the tree (spec Clarifications "review", research R2/R3):
  `JSONDocument.formatted()` (two spaces, `maxIndentDepth` 64, tokens as written, JSON Lines record by
  record, bad lines as written) and `firstLineError` in `Sources/CommanderCore/Viewer/JSONDocument.swift`;
  the tree-only API (`keyText`, `valueText`, `path`, `copyValue`, `search`, `children`, `ancestors`,
  duplicate marks) removed; tests in `Tests/CommanderCoreTests/JSONDocumentTests.swift` for formatting,
  escapes, JSON Lines and the indentation cap. `ViewerWindowController` shows the text in the text view
  (`showsFormattedJSON`: JSON highlighting, find, wrap, copy; source decoded again for Text), the 20 MB
  question becomes Show Formatted / Text (`jsonFormatLimit`); `JSONTreePreview.swift` and the three
  commands deleted; `jsonl ndjson` highlighted as JSON; strings and CHANGELOG updated.

## Phase 3: User Story 2 — SVG (P1)

- [X] T006 [P] [US2] `SVGData.unpack(_:maxSize:)` in `Sources/CommanderCore/Viewer/SVGData.swift` via the
  Compression framework; tests in `Tests/CommanderCoreTests/SVGDataTests.swift` (plain passes through,
  gzip unpacks, over the cap throws, corrupt gzip throws).
- [X] T007 [US2] `PreviewKind.vector` (`svg`, `svgz`, `public.svg-image`); `prefersQuickLook` false for
  them; `ImagePreview` shows the vector `NSImage` with fit/zoom/actual size; status "SVG" and the size;
  "cannot be shown" for nil/zero size; Save Image As disabled; image stepping accepts SVG; Text shows the
  XML (svgz unpacked).

**Checkpoint**: commit "[Spec 019] SVG preview".

## Phase 4: User Story 4 — .NET highlighting (P3)

- [X] T008 [US4] In `Sources/CommanderCore/Viewer/SyntaxHighlighter.swift` (research R6): F# (`fs fsi fsx`),
  solution files (`sln`), XML extensions `props targets vbproj fsproj nuspec slnx`, Razor (`cshtml razor`)
  with the `@` rules through the re-entrant lexer.
- [X] T009 [US4] Tests in `Tests/CommanderCoreTests/SyntaxHighlighterTests.swift`: lookup of every new
  extension, F# comments/strings/keywords, sln sections and GUIDs, Razor comment, implicit and explicit
  expressions, code block with an HTML line inside, directive line; the mixed-input validity test
  covers the new languages.

**Checkpoint**: commit "[Spec 019] Highlight F#, Razor, solution and MSBuild files".

## Phase 5: User Story 3 — media (P2)

- [X] T010 [P] [US3] `MediaDetails` in `Sources/CommanderCore/Viewer/MediaDetails.swift` with
  `summaryParts`; tests in `Tests/CommanderCoreTests/MediaDetailsTests.swift` (durations under a minute,
  over an hour, mono/stereo/5.1, kHz formatting, frame size and rate, missing values).
- [X] T011 [US3] `PreviewKind.media` (UTType conforms to `.audiovisualContent` and is in
  `AVURLAsset.audiovisualTypes()`, the `.ts` text rule first); `prefersQuickLook` false for them;
  `MediaPreview` in `Sources/AxolotlCommander/Viewer/MediaPreview.swift` (focus container, Return,
  ←/→ 5 s, ↑/↓ volume, never autoplay, "cannot be played"); details into the status line; stop on step,
  close and leaving Preview; media stepping goes to the next playable media file; Hex works.

**Checkpoint**: commit "[Spec 019] Audio and video player in the viewer".

## Phase 6: Polish

- [X] T012 Czech strings complete; CHANGELOG (Unreleased, Added); spec status Implemented. Build
  without warnings, `swift test` green, commit.
- [ ] T013 GUI check on the test copy following quickstart.md (scratch files only); record the result
  here.

## Dependencies

- T001 → T005. T002 → T003, T004 → T005 → T014. T006 → T007. T008 → T009. T010 → T011. T012 → T013.
- The phases are independent apart from shared edits in `ViewerWindowController.swift` (do them in
  order).

## Parallel opportunities

- The core tasks T002/T003, T006, T008/T009 and T010 touch different files and can run in parallel.

## Implementation strategy

- MVP: Phase 2 (formatted JSON). Then SVG, .NET highlighting and media, each its own commit.
