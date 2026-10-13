# Implementation Plan: Button Bar

**Branch**: `018-button-bar` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (`Sources/CommanderCore/Window/ButtonBar.swift`, NEW):
  - `ButtonBarPlacement` (off/top/bottom, `buttonBar.placement`, `buttonBar.lastPlacement`).
  - `ButtonBarItem` (command name kept as text, program as a `UserMenuItem`, separator, icon text);
    `ButtonBarStore` (key `buttonBar.items`, lossy decoding, samples).
  - `ButtonBarIcon.resolve` (own symbol, app icon, default per command from `CommandSymbols`, which the
    toolbar now shares), `ButtonBarSymbols` (picker list and search).
  - `ButtonBarLayout` (natural width, what fits before », the bottom row split with the function keys).
  - Settings export: `buttonBar` section and the two preferences; `toggleButtonBar` command (View).
- **UI**:
  - `ButtonBarView` (icon buttons, separators, » menu, context menu) and `BottomRowView` (function keys
    + buttons) in `ButtonBarView.swift`; `ButtonBarDefaults` (store access, toggle, edit/add/remove).
  - `MainWindowController`: a top bar above the panels and a bottom bar in the bottom row, shown by the
    placement; commands via `performFromBar`, programs via `UserMenuPresenter.run`; validation with the
    function key bar.
  - `ButtonBarSettings.swift` (NEW): the Settings tab, the command chooser, the icon picker; the program
    fields reuse `UserMenuItemEditor` without the shortcut row.

## Technical Context

- Swift 6.2, AppKit, SwiftUI, SF Symbols, Swift Testing (`ButtonBarTests`).

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Programs run as user menu commands; no new file operations. |
| II Reference | ✅ Classic button bar; deviations in the spec. |
| III Native macOS | ✅ SF Symbols, app icons, Settings tab. |
| IV Testable core | ✅ Model, icons and layout in the core. |
| V Clean-room | ✅ |
| VI Incremental | ✅ |
| VII Language | ✅ |
