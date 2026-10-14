# Implementation Plan: Mouse Selection

**Branch**: `024-mouse-selection` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (pure, tested; `Sources/CommanderCore/PanelMouse.swift`, NEW):
  - `MouseSelectionMode`, `MouseModifiers`, `RubberBand` ([data-model.md](data-model.md)).
  - `PanelModel` methods per gesture step: left press and release on an item, press on empty space, rubber
    band begin and update, right click toggle, right drag begin and over (FR-001 to FR-005, FR-007,
    FR-011, FR-015, FR-016, FR-018). Every method skips ".." (FR-019) and stores removed marks for ⌃W
    (FR-020).
  - `PanelModel.swift`: `set(_:_:)`, `selectable(_:)` and the `previousSelection` setter become internal so
    the extension can use them.
  - `PanelBehavior.rightButtonMarks` (key `panel.rightButtonMarks`, default off) and its `PreferenceSpec`
    (FR-014).
- **UI** (`Sources/AxolotlCommander/`):
  - `PanelTableView` (in `PanelViewController.swift`): `mouseDown` decision tree by hit (empty space, a row
    outside the name zone, the name zone with or without modifiers), `super.mouseDown` only for a plain
    press on the name zone, release rule when no drag began; `menu(for:)` returns nil for a ⌃-left-click;
    `rightMouseDown` for the Norton mode (FR-001 to FR-010, FR-013, FR-015 to FR-017) (research R3, R5, R7).
  - `BriefGridView` (`BriefView.swift`): the same tree; its own drag start only from a plain press on the
    name zone; items under a rectangle from the grid geometry (R4).
  - `PanelMouseTracking.swift` (NEW): the shared tracking loops (rubber band with periodic autoscroll, right
    press with the 0.5 s timer and right drag), `RubberBandView` overlay, name-zone hit tests for
    `FileCellView` and `BriefItem` (R6, R7).
  - `PanelViewController.marksChanged()`: redraw visible rows/items and the info line only (R8).
  - `PanelContextMenu.swift`: `contextMenu(at:)` keeps the marks while the setting is on (R7).
  - `SettingsView.swift`: the "Right mouse button marks (Norton Commander style)" toggle in Panels.
  - Czech strings in `Resources/Localizable.xcstrings`; `CHANGELOG.md` entry; `bump-version.sh minor` in the
    pull request.

## Technical Context

- Swift 6.2 (strict concurrency), AppKit, Swift Testing; macOS 15+. No new dependencies.
- **Performance**: SC-003 (100 000 items, under 0.1 s per step): incremental rubber band (only items that
  enter or leave), ranges applied by index, visible-only redraw; Brief hit sets by arithmetic.
- **Constraints**: keyboard marking untouched (FR-022); drag & drop and double click keep the existing code
  paths; CI fails on warnings.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Marking changes no files; tests on temp folders only; the GUI check only browses and marks in a scratch folder, drags are cancelled before dropping. |
| II Reference | ✅ Ctrl+click, Shift+click, rubber band from empty space with the same modifiers, the right-button option as in the reference; the Windows-standard default, ⌃ = Ctrl on macOS, ⌘ = ⌃ and ⌃⇧+click are recorded deviations in the spec. |
| III Native macOS | ✅ System selection colors, autoscroll, trackpad secondary click; String Catalog. |
| IV Testable core | ✅ All marking rules in `PanelModel` with unit tests; the views only hit-test and call them. |
| V Clean-room | ✅ Behavior from the reference help and public documentation of other file managers. |
| VI Incremental | ✅ US1 (modifier clicks) → US2 (rubber band) → US3 (Norton setting), each usable alone. |
| VII Language | ✅ |

## Project Structure

```text
specs/024-mouse-selection/{plan,research,data-model,quickstart}.md

Sources/CommanderCore/PanelMouse.swift                         NEW
Sources/CommanderCore/{PanelModel,PanelBehavior}.swift
Sources/CommanderCore/Settings/AppSettingsCatalog.swift
Sources/AxolotlCommander/PanelMouseTracking.swift              NEW
Sources/AxolotlCommander/{PanelViewController,BriefView,PanelContextMenu,PanelDragDrop,SettingsView}.swift
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/PanelMouseTests.swift                 NEW
CHANGELOG.md, VERSION
```

**Structure Decision**: the existing two-target layout; the rules in the core so every scenario of the spec
has a unit test, the AppKit side limited to hit-testing, tracking loops and drawing.
