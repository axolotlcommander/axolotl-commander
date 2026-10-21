# Implementation Plan: Rename by Clicking the Name

**Branch**: `035-click-rename` | **Date**: 2026-10-21 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (unit tested), `Sources/CommanderCore/ClickRename.swift` (NEW):
  - `ClickRename.Press`: what a left press saw — setting on, click count, modifiers, the panel was active
    before the press, the item was the cursor before the press, the press was on the name text, the item is
    "..", Rename is available.
  - `ClickRename.arms(_:)`: whether the release of that press (without a drag) starts the wait.
  - `ClickRename.Pending`: the index and identity (URL) of the item and the scroll origin when the wait
    began; `fires(cursor:item:scrollOrigin:panelActive:editing:)` says whether editing starts when the
    interval ends (same cursor, same item, no scroll, panel still active, no editing in progress).
  - `ClickRename.selection(of:)`: the preselected range of a name (base name; a folder's whole name) — moved
    from `beginRename()` so all three views share it.
  - `PanelBehavior.clickToRename` (`panel.clickToRename`, default true) + `AppSettingsCatalog` entry
    (settings export/import).
- **Panel** (`PanelMouseTracking.swift`, `PanelViewController.swift`):
  - `MouseHit` gains `onText` (the name text alone, not the icon). The table, Brief and Thumbnails compute it
    (`isOnText` helper; `ThumbnailCellView.nameTextContains`).
  - The views read "the panel was active" before they make themselves first responder, and pass it on.
  - `mousePressed` stores a candidate when `ClickRename.arms` agrees; `mouseReleasedAfterPlainPress` starts
    the wait (`NSEvent.doubleClickInterval`) for the candidate item.
  - While waiting, a local event monitor drops the pending rename on any key down, mouse down (any button) or
    scroll wheel event; the timer then checks `Pending.fires` and `canPerform(.rename)` and runs
    `perform(.rename)`.
  - The activating click of an inactive window never reaches the list (the list views do not accept the
    first mouse), and the panel-was-active check covers the click that activates a panel: the panel remembers
  the press that made it active (`activatingPress`), see R1.
- **In-place editing in Brief and Thumbnails** (`PanelViewController.swift`, new `GridRename.swift`):
  - `.rename` runs `beginRename()` in every view. In a grid view an overlay `NSTextField` is placed over the
    cell's label in the grid's coordinates (it scrolls with the content): Brief single line, at least the
    label's width, as wide as the text needs, kept inside the visible width; Thumbnails wrapping, the cell's
    width (wider for short cells up to the visible width), as tall as the text needs. The field grows while
    typing (`controlTextDidChange`).
  - The same delegate as in Detailed: Enter commits, Esc cancels, focus elsewhere commits (as today). Enter
    and Esc end the rename before the field stops being editable: turning editing off ends the field's
    editing, which would otherwise count as focus moving away and keep the typed name. The
    overlay is removed when editing ends; focus returns to the list view.
  - `renaming` keeps blocking reloads; the item is scrolled into view before the field appears.
  - The rename dialog (`askRename`) is no longer used by the panel and is removed.
- **Settings → Panels** (`SettingsView.swift`): checkbox "Rename by clicking the name of the item under the
  cursor" with a caption.
- Czech strings; CHANGELOG entries under 0.10.0 (no further bump: 034–036 collect into 0.10.0).

## Technical Context

Swift 6, AppKit + SwiftUI settings, SwiftPM; tests with Swift Testing in `Tests/CommanderCoreTests`.

## Constitution Check

| Principle | Status |
|---|---|
| Data safety | ✅ The rename runs through the existing rename operation; nothing renames without the user typing and committing. GUI tests rename only dummy files in a scratchpad test directory on the test copy. |
| Clean room | ✅ Behavior from the reference help and Finder; no reference sources. |
| Keyboard first | ✅ F2 keeps working and gets the same in-place editing in every view; the click only adds a mouse path. |
| Testable core | ✅ The arming and firing decisions and the preselection range are in CommanderCore with tests. |
| Incremental | ✅ Core → click in Detailed → in-place in grids → setting → strings, each committed. |

## Research

- **R1** Click delivery: `NSTableView` and `NSCollectionView` keep the default `acceptsFirstMouse` (false),
  so the click that activates the window or the app is not delivered to the list. The panel becomes active
  in `becomeFirstResponder` of the list, and the window makes the clicked list the first responder before it
  sends `mouseDown`, so the press cannot read "was active" itself: when the list becomes the first responder
  during a left press while the panel is inactive, the panel stores that press's time stamp, and a press
  with that time stamp counts as one the panel was not active for (found in the GUI check).
- **R2** Double click: the table's `doubleAction` and the grid's click count 2 open the item; the second
  press arrives before the wait ends and the event monitor drops the pending rename. Only a release of a
  press with click count 1 arms.
- **R3** Selection change after the release (standard mode marks only the clicked item) triggers
  `modelChanged()` through observation; it must not cancel the wait, so the firing check compares the cursor
  index and the item's URL instead of listening to reloads. A folder update that replaces or removes the item
  fails that check.
- **R4** Scroll: comparing the list's clip view origin at arming and at firing covers scrolling by any means
  (wheel, keys, autoscroll); the scroll wheel also cancels through the monitor.
