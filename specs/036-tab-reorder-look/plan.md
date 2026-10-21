# Implementation Plan: Tab Reordering and a Prominent Tab Look

**Branch**: `036-tab-reorder-look` | **Date**: 2026-10-21 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (unit tested):
  - `TabList.move(from:to:)` exists (spec 028) and keeps the active tab; `TabList.canMove(_:by:)` (NEW) says
    whether a tab can move one place left or right.
  - `Command.moveTabLeft`, `Command.moveTabRight` ("Move Tab Left", "Move Tab Right", Go menu after Copy Tab
    to Other Panel, no keys in either scheme).
  - `TabLook` (`standard`, `prominent`) and `PanelBehavior.tabLook` (`panel.tabLook`, default `standard`) +
    `AppSettingsCatalog` entry (settings export/import).
- **Panel** (`PanelTabs.swift`, `PanelViewController.swift`): `moveTab(at:to:)` stores the model in the
  active tab, moves, shows the strip and saves the layout; the commands move the active tab and are enabled
  only when the move is possible (also in the Network folder, like the other tab commands).
- **Tab strip** (`TabStrip.swift`):
  - A press on a tab is tracked in the strip (`trackEvents`): moving more than 3 points horizontally starts
    a drag, otherwise the release is a click (switch). While dragging, a snapshot of the tab follows the
    pointer (horizontal only, kept inside the tab area), the tab's own place stays empty, and the tabs are
    reordered in the stack as the pointer passes the middle of a neighbor (animated layout). Esc restores
    the order; a release anywhere commits the order shown through `onMove(from, to)` (indices of `items`).
    Only the visible tabs take part.
  - Context menu: Move Tab Left / Move Tab Right for the tab clicked, disabled at the ends.
  - Look: `panelIsActive` (set from the panel's `updateActiveAppearance`) and the `TabLook` from the
    defaults (re-read on `UserDefaults.didChangeNotification`). Prominent: spacing 3; inactive tabs
    `tertiarySystemFill` with a `separatorColor` outline and `labelColor` text, hover `secondarySystemFill`;
    the active tab of the active panel `controlAccentColor` with white semibold text and white marks; the
    active tab of the inactive panel `systemGray` at about half opacity with `labelColor` text. Standard is
    unchanged.
- **Settings → Panels** (`SettingsView.swift`): "Tab look:" with Standard / Prominent, next to the other tab
  options.
- Czech strings; CHANGELOG entries under 0.10.0.

## Technical Context

Swift 6, AppKit + SwiftUI settings, SwiftPM; tests with Swift Testing in `Tests/CommanderCoreTests`.

## Constitution Check

| Principle | Status |
|---|---|
| Data safety | ✅ No file operations; only the order of tabs changes. |
| Clean room | ✅ Behavior from the reference help (drag, Esc cancels) and Mac conventions; no reference sources. |
| Keyboard first | ✅ Move Tab Left / Right commands, assignable keys; the look setting is reachable from the keyboard in Settings. |
| Testable core | ✅ Move rules, commands and the setting in CommanderCore with tests; the drag gesture and colors are UI. |
| Incremental | ✅ Core → commands → drag → look → setting → strings, committed in steps. |

## Research

- **R1** Following the pointer: an `NSStackView` with `fillEqually` lays out the tabs, so the dragged tab is
  drawn as a snapshot image above the stack while its own view stays in the stack (invisible) as the
  placeholder; reordering the stack's arranged views moves the neighbors, and an animation context with
  implicit animation lets them slide.
- **R2** Esc during the drag: `trackEvents` with `.keyDown` in its mask receives Esc (key code 53); other
  keys are ignored while dragging.
- **R3** The visible tabs (`TabStripLayout.visible`) are the first tabs that fit plus the active one when it
  lies further right. The item index of a slot is `shown[slot]`, and a drop on a slot moves the tab to that
  item's index; across the gap of hidden tabs it lands next to the active tab, the hidden ones keep their
  order.
