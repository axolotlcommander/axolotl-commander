# Implementation Plan: Panel and Bar Fonts

**Branch**: `031-panel-fonts` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (`Sources/CommanderCore/Window/`, unit tested, no AppKit):
  - `PanelFonts.swift` (NEW): `FontChoice` (PostScript name + size, or nil for the system font),
    `FontRole` (file list 13 pt, 8–32; bars and volume buttons 11 pt, 8–20) with `clamped`, `bigger` / `smaller` steps and
    `rowHeight(lineHeight:)` (R3).
  - `Highlighting.swift`: `PanelAppearance` gets `listFont` / `barFont` / `buttonFont` (`FontChoice?`, nil = default),
    decoded with defaults, so the settings export and import carry them (R1).
- **UI** (`Sources/AxolotlCommander/`):
  - `PanelFontsUI.swift` (NEW): `PanelFont` resolves a role to `NSFont` (regular, bold, monospaced; falls
    back to the system font when the PostScript name is not installed), the display text for Settings;
    `FontChooser` targets the shared `NSFontManager` at one role, opens the Fonts panel and applies
    `changeFont(_:)`; Settings closing clears the target (R2).
  - File list: `textFont(marked:)`, the detailed row height, the brief view's item size and column width,
    the thumbnail labels follow `PanelFont.list` (R4).
  - Bars: `TabStrip`, `PathBar` (and its field), the status line and its free space follow `PanelFont.bar`;
    `VolumeBar`, `DriveRowView` and its `FreeSpaceLabel` follow `PanelFont.button` (clarification
    2026-10-15); heights from the font, the button control size from the font size (R5).
  - All of them re-read the fonts on `.appearanceChanged` (already posted by `AppSettings`).
  - `SettingsView.swift`: the "Fonts" section in Appearance.
  - `Command.swift`: `fileListFontBigger`, `fileListFontSmaller`, `fileListFontDefault` in the View menu,
    no default keys; enablement and handling in the window controller.
- Czech strings; version 0.8.0 (minor: new feature); `CHANGELOG.md` / `CHANGELOG.cs.md`.

## Technical Context

- Swift 6.2, AppKit + SwiftUI Settings, Swift Testing; macOS 15+. No new dependencies.
- **Storage**: two optional fields in the existing `appearance` preference.
- **Performance**: fonts resolved once per change and cached; no per-row font lookups (SC-005).
- **Constraints**: no panel may widen (spec 0.7.3 fix: split items hold at 480, content below).

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ No file operations; GUI test only on the test copy with test folders. |
| II Reference | ✅ Panel font as in the reference, separate fonts as in the classic commander; deviations recorded. |
| III Native macOS | ✅ Standard Fonts panel, SwiftUI Settings section, String Catalog. |
| IV Testable core | ✅ Choice, limits, steps, row height and decoding in the core with unit tests. |
| V Clean-room / GPL | ✅ Own code from the spec and the help. |
| VI Incremental | ✅ Core → file list → bars → Settings → commands, each committed. |
| VII Language | ✅ English code and docs, Czech UI strings and changelog. |

## Project Structure

```text
specs/031-panel-fonts/{plan,research,data-model,quickstart,tasks}.md

Sources/CommanderCore/Window/PanelFonts.swift       NEW FontChoice, FontRole
Sources/CommanderCore/Window/Highlighting.swift     listFont / barFont in PanelAppearance
Tests/CommanderCoreTests/PanelFontsTests.swift      NEW
Sources/AxolotlCommander/PanelFontsUI.swift         NEW PanelFont, FontChooser
Sources/AxolotlCommander/PanelTabs.swift            textFont(marked:)
Sources/AxolotlCommander/PanelViewController.swift  row height, status line, path field, refresh
Sources/AxolotlCommander/BriefView.swift            item size, column width
Sources/AxolotlCommander/ThumbnailView.swift        label font and height
Sources/AxolotlCommander/VolumeBar.swift            button font and size
Sources/AxolotlCommander/DriveRowView.swift         combo and free space font, height
Sources/AxolotlCommander/TabStrip.swift             title font, height
Sources/AxolotlCommander/PathBar.swift              segment font, height
Sources/AxolotlCommander/SettingsView.swift         Fonts section
Sources/AxolotlCommander/AppDelegate.swift          Settings closing clears the Fonts panel target
Sources/CommanderCore/Command.swift                 three commands
Resources/Localizable.xcstrings                     Czech strings
```

## Complexity Tracking

None.
