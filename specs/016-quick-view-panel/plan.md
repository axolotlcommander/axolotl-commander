# Implementation Plan: Quick View Panel

**Branch**: `016-quick-view-panel` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core**: `QuickViewSubject.subject(cursor:location:inArchive:onServer:isNetwork:)` returns the URL to
  preview or `.unavailable` (FR-004). The `quickView` command (View, ⌃Q).
- **UI**:
  - `QuickViewPane` (NEW): an opaque view with the item name and a `QLPreviewView`; `show(_:)` sets the
    preview item after a short debounce, so holding ↓ does not queue previews.
  - `MainWindowController`: `quickView` state; turning it on un-maximizes and lays the pane over the
    other panel's view; `activePanelCursorChanged` feeds it; Switch Panel, Maximize, Swap Panels and
    Swap with All Tabs close it first; the menu item is checked while on.
  - `PanelViewController.modelChanged` tells the window controller about cursor changes.

## Technical Context

- Swift 6.2, AppKit, Quartz (`QLPreviewView`, already linked for Quick Look), Swift Testing.
- Tests (`QuickViewTests`): subject choice and the chord.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Read-only preview. |
| II Reference | ✅ Classic quick view; deviations listed. |
| III Native macOS | ✅ System Quick Look previews. |
| IV Testable core | ✅ Subject choice in the core. |
| V Clean-room | ✅ |
| VI Incremental | ✅ |
| VII Language | ✅ |

## Source code

```text
Sources/CommanderCore/QuickViewSubject.swift         # NEW
Sources/CommanderCore/Command.swift                  # quickView
Sources/AxolotlCommander/QuickViewPane.swift         # NEW
Sources/AxolotlCommander/MainWindowController.swift  # state, overlay, closing rules
Sources/AxolotlCommander/PanelViewController.swift   # cursor change notice
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/QuickViewTests.swift        # NEW
```

## Complexity Tracking

None.
