# Implementation Plan: Thumbnails View

**Branch**: `025-thumbnails-view` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (pure, tested; `Sources/CommanderCore/Window/PanelGrid.swift` and
  `Sources/CommanderCore/Thumbnails.swift`, NEW):
  - `PanelGrid` (cursor moves for the three arrangements) and `GridGeometry` (cells under a rectangle,
    both fill orders) — research R2.
  - `ThumbnailSize` (64/128/256, steps, setting `panel.thumbnailSize`), `ThumbnailKey`, `ThumbnailCache`
    (LRU with a cost limit), `ThumbnailQueue` (wanted, running, limit 8), `ThumbnailPolicy` (which items
    may get previews) — R4–R7.
  - `PanelViewMode.thumbnails` with a tolerant decode in `WindowLayout` — R9.
  - New commands `viewModeThumbnails` (⌃⌥3; Classic Commander adds ⌃⇧F1), `thumbnailsLarger` (⌘+, ⌘=),
    `thumbnailsSmaller` (⌘−) in `Command.swift` / `KeyScheme.swift`.
- **UI** (`Sources/AxolotlCommander/`):
  - `PanelGridView.swift` (NEW): the Brief grid's mouse, drag and drop code moved into a shared base class;
    `BriefGridView` subclasses it unchanged in behavior (R1).
  - `ThumbnailView.swift` (NEW): `ThumbnailGridView` (a uniform vertical grid layout of its own, ⌘ + wheel, pinch),
    `ThumbnailCellView` and `ThumbnailItem`, the data source extension of `PanelViewController`, the
    reload/cursor bookkeeping like Brief's (R8).
  - `ThumbnailLoader.swift` (NEW): carries out `ThumbnailQueue` answers with `QLThumbnailGenerator`,
    fills `ThumbnailCache<NSImage>` and the visible cells (R3, R5, R6).
  - `PanelViewController.swift`: three views in `lists`, `listView`, `viewModeChanged()`, `modelChanged()`
    / `marksChanged()` per view, `handleMovement` through `PanelGrid`, the new commands, the setting
    observer.
  - `MainWindowController.swift`: the checkmark for Thumbnails; `SettingsView.swift`: the size picker in
    Panels; Czech strings in `Resources/Localizable.xcstrings`; `CHANGELOG.md` entry under 0.6.0.

## Technical Context

- Swift 6.2 (strict concurrency), AppKit, QuickLookThumbnailing (system framework, no new dependency),
  Swift Testing; macOS 15+.
- **Performance**: SC-001 (visible previews within 2 s), SC-002 (100 000 items, every step under 0.1 s):
  recycled collection view cells, previews only for visible cells plus one screen of margin, at most 8
  requests running, the cursor move redraws only the visible cells (no reload), rubber band by arithmetic.
- **Memory**: SC-003: previews in an LRU cache limited to 256 MB of pixels.
- **Constraints**: nothing written to disk for previews (FR-014); no extraction or download for previews
  (FR-015); Detailed and Brief unchanged (FR-024); CI fails on warnings.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ The view only reads; no cache files, nothing written into folders (FR-014, SC-004); no extraction or download for previews; tests use temp folders; the GUI check works in scratch folders only. |
| II Reference | ✅ A Thumbnails panel view with a size setting and a key to step the size, as in the reference; previews from the system instead of plugins, no disk cache, three sizes and vertical scrolling are recorded deviations in the spec. |
| III Native macOS | ✅ System Quick Look thumbnails and per-file icons, pinch and ⌘ + wheel, system colors in light and dark mode, String Catalog. |
| IV Testable core | ✅ Movement, rectangle, size, cache, queue and policy rules in the core with unit tests; the views only lay out and draw. |
| V Clean-room | ✅ Behavior from the reference help and public descriptions of other file managers. |
| VI Incremental | ✅ US1 (view + keyboard, icons) → US2 (previews) → US3 (sizes) → US4 (mouse, mostly shared) → US5 (sources without previews). |
| VII Language | ✅ |

## Project Structure

```text
specs/025-thumbnails-view/{plan,research,data-model,quickstart}.md

Sources/CommanderCore/Window/PanelGrid.swift                 NEW
Sources/CommanderCore/Thumbnails.swift                       NEW
Sources/CommanderCore/Window/WindowLayout.swift
Sources/CommanderCore/{Command,KeyScheme}.swift
Sources/CommanderCore/Settings/AppSettingsCatalog.swift
Sources/AxolotlCommander/PanelGridView.swift                 NEW
Sources/AxolotlCommander/ThumbnailView.swift                 NEW
Sources/AxolotlCommander/ThumbnailLoader.swift               NEW
Sources/AxolotlCommander/{BriefView,PanelViewController,MainWindowController,SettingsView}.swift
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/PanelGridTests.swift                NEW
Tests/CommanderCoreTests/ThumbnailTests.swift                NEW
CHANGELOG.md
```

**Structure Decision**: the existing two-target layout; every rule that can be stated without AppKit is in
the core with tests, the AppKit side is limited to the collection view, the cell and the generator calls.
