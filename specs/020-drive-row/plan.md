# Implementation Plan: Drive Row with Free Space

**Branch**: `020-drive-row` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (`Sources/CommanderCore/Window/DriveRow.swift`, NEW):
  - `DriveRowSettings`: `driveRow.show`, `volumeBar.show`, `driveRow.freeSpaceElsewhere` (all on by
    default), read through a defaults lookup like `VolumeBarSettings`.
  - `FreeSpacePlace` (driveRow, volumeBar, statusLine, hidden) and `place(for:)`: the one rule of FR-006.
  - `DiskSpace` (total, available, read-only) with `usedPercent`; `FreeSpaceText` (full "X free of Y",
    short "X free", tooltip with the used percentage and read-only) and `fitting(width:measure:)`, which
    picks the longest variant that fits (or none).
  - `toggleDriveRow` and `toggleVolumeBar` commands (View menu); the three preferences in
    `SettingsCatalog.app`.
- **UI**:
  - `DiskSpaceReader` (in `DriveRowView.swift`): reads total/available-for-important-use/read-only of a
    folder off the main thread; one read in flight per panel.
  - `FreeSpaceLabel`: a small clickable label that shows the longest text variant fitting its width;
    click opens Volume Info (⌃L). Used in all three places.
  - `DriveRowView`: the combo (icon, name, chevron; a borderless button that never takes focus) and a
    `FreeSpaceLabel`. The combo opens the panel's existing volume menu below itself.
  - `VolumeBar`: a trailing `FreeSpaceLabel`; `fitItems` gives the buttons their room first, the label
    takes what is left. The bar exposes the pressed item for the combo's title and the menu's check
    mark.
  - `PanelViewController`: stack [volumeBar, driveRow, tabStrip, pathBar, lists, status row], the status
    row being the status field and a trailing `FreeSpaceLabel`. The disk of the location: the folder, the
    folder holding an archive, the root of a flat listing; none for servers and the Network folder. Space
    refresh on every location update, on mount/unmount and every 3 s while the window is visible.
  - `MainWindowController`: the two View commands with check marks; panels observe the defaults.
  - Settings → Appearance: "Show volume bar", "Show drive row", "Show free space when the drive row is
    hidden" next to the volume bar options.

## Technical Context

- Swift 6.2, AppKit, SwiftUI (Settings), Swift Testing (`DriveRowTests`).
- Free space: `URLResourceValues.volumeAvailableCapacityForImportantUsage`, as Volume Info.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Read-only; no file operations. |
| II Reference | ✅ Classic drive row; deviations in the spec. |
| III Native macOS | ✅ Same menu as ⌥F1/⌥F2, system size texts, Volume Info. |
| IV Testable core | ✅ Settings, placement and text rules in the core. |
| V Clean-room | ✅ |
| VI Incremental | ✅ |
| VII Language | ✅ |
