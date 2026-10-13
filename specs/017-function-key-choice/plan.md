# Implementation Plan: Choose the Function Key Buttons

**Branch**: `017-function-key-choice` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core**:
  - `FunctionKeyChoice` (NEW): the hidden F-key positions, stored as text under
    `functionKeyBar.hidden` ("5,6,8"); `visible` is never empty, `canHide(_:)` keeps the last one
    (FR-004, FR-007).
  - `FunctionKeyBarLayout.frames(count:width:edge:gap:maxWidth:)` (NEW): left-aligned buttons, at most
    140 points each, shared evenly below that, with a margin at both ends (FR-005).
  - `SettingsCatalog.app`: the new preference (string, default "").
- **UI**:
  - `FunctionKeyBarView`: `choice` hides the buttons of hidden positions in every layer; `layout()`
    uses `FunctionKeyBarLayout`; the context menu gets Choose Buttons… (FR-002, FR-006).
  - `MainWindowController.applyChromeSettings` reads the choice on every defaults change, so all
    windows follow at once; key handling is untouched (FR-003).
  - `SettingsView` → General: "Buttons on the bar:" with twelve tick boxes; the last shown one is
    disabled (FR-001, FR-004).

## Technical Context

- Swift 6.2, AppKit, SwiftUI (Settings), Swift Testing.
- Tests (`FunctionKeyChoiceTests`): storage, defaults, the last key, the layout rule.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Display only; no file operations. |
| II Reference | ✅ Extension of the bar; deviations in the spec. |
| III Native macOS | ✅ Settings tick boxes, context menu. |
| IV Testable core | ✅ Choice and layout in the core. |
| V Clean-room | ✅ |
| VI Incremental | ✅ |
| VII Language | ✅ |

## Source code

```text
Sources/CommanderCore/Window/FunctionKeyChoice.swift      # NEW: choice + layout
Sources/CommanderCore/Settings/AppSettingsCatalog.swift   # functionKeyBar.hidden
Sources/AxolotlCommander/FunctionKeyBarView.swift         # hidden buttons, layout, Choose Buttons…
Sources/AxolotlCommander/MainWindowController.swift       # reads the choice
Sources/AxolotlCommander/SettingsView.swift               # tick boxes
Tests/CommanderCoreTests/FunctionKeyChoiceTests.swift     # NEW
```
