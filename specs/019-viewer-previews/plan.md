# Implementation Plan: Viewer Previews for JSON, SVG and Media

**Branch**: `019-viewer-previews` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

Four parts, each shipped with its own commit, in the order JSON → SVG → .NET → media (Clarifications).

- **Core** (`Sources/CommanderCore/Viewer/`, tested):
  - `JSONDocument` / `JSONNode` / `JSONParseError` (NEW): an order-preserving byte parser with comments,
    trailing commas, duplicates, exact numbers, JSON Lines, error positions, paths, copy text and search
    (research R1, R2; FR-001 to FR-003).
  - `SVGData.unpack` (NEW) for `.svgz` through the existing libarchive binding (R4).
  - `MediaDetails` (NEW) with the status line formatting (R5).
  - `SyntaxHighlighter.swift`: F#, solution files, Razor, more XML extensions (R6; FR-007).
  - `Command.swift`: `viewerCopyPath` (⇧⌘C), `viewerExpandAll`, `viewerCollapseAll` (R7).
- **UI** (`Sources/AxolotlCommander/Viewer/`):
  - `ViewerWindowController`: `PreviewKind.json`, `.vector`, `.media`; `previewKind(for:)`,
    `prefersQuickLook` (SVG and playable media stay in the viewer, FR-004 to FR-006), default modes, the
    20 MB question (R3), `show`/`showPreview`, `validateMenuItem`, `zoom`, `find`, `updateInfo`, `step`
    (image stepping accepts SVG), `windowWillClose` and leaving Preview stop media.
  - `JSONTreePreview.swift` (NEW): `NSOutlineView` with Key / Value / Type columns, groups of 100, keys,
    copy, expand/collapse all, find through `HexFindBar`, progress while building (R2).
  - `ImagePreview`: show an `NSImage` drawn from SVG data (vector) besides raster images (R4).
  - `MediaPreview.swift` (NEW): container keeping focus around `AVPlayerView`, Return / ←→ / ↑↓, details
    line, stop on step/close (R5).
- Czech strings; CHANGELOG (Unreleased, Added).

## Technical Context

- Swift 6.2, AppKit, AVKit/AVFoundation (system frameworks, no new dependency), Swift Testing.
- **Performance**: SC-001 — the parser runs in a detached task over `[UInt8]` with byte ranges, the tree
  creates outline items only for expanded nodes, long containers are grouped by 100.
- **Constraints**: no network for SVG (system renderer, verified R4) and none for the existing web
  previews (unchanged); playback never starts by itself; CI fails on warnings; the viewer is read-only.
- **Settings**: none new (FR-009); the 20 MB limit is a constant.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Read-only viewer; nothing is written; SVG cannot reach the network; the GUI check only reads scratch files. |
| II Reference | ✅ Classic managers use lister plugins; built-in previews are a recorded deviation (spec). |
| III Native macOS | ✅ NSOutlineView, the system SVG renderer, AVKit player, dark mode, String Catalog. |
| IV Testable core | ✅ Parser, paths, copy text, search, svgz unpacking, media formatting and highlighting rules in the core with tests. |
| V Clean-room | ✅ No reference sources; behavior from the spec. |
| VI Incremental | ✅ JSON → SVG → .NET → media, a commit after each. |
| VII Language | ✅ |

## Project Structure

```text
specs/019-viewer-previews/{plan,research,data-model,quickstart,tasks}.md

Sources/CommanderCore/Viewer/{JSONDocument,SVGData,MediaDetails}.swift      NEW
Sources/CommanderCore/Viewer/SyntaxHighlighter.swift                        F#, sln, Razor, XML extensions
Sources/CommanderCore/Command.swift                                         viewerCopyPath, viewerExpandAll, viewerCollapseAll
Sources/AxolotlCommander/Viewer/{JSONTreePreview,MediaPreview}.swift        NEW
Sources/AxolotlCommander/Viewer/{ViewerWindowController,ImagePreview}.swift
Resources/Localizable.xcstrings, CHANGELOG.md
Tests/CommanderCoreTests/{JSONDocumentTests,SVGDataTests,MediaDetailsTests}.swift   NEW
Tests/CommanderCoreTests/SyntaxHighlighterTests.swift
```

**Structure Decision**: the existing two-target layout; every rule the spec names for JSON, svgz, media
details and highlighting is in the core so `swift test` covers it (SC-003).
