# Implementation Plan: Clickable Breadcrumb Path Bar

**Branch**: `003-breadcrumb-path-bar` | **Date**: 2026-10-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/003-breadcrumb-path-bar/spec.md`

## Summary

Each panel's path line becomes a row of clickable segments (volume › … › current folder) with
Finder icons; a click goes to that folder with the cursor on the child the user came from. ⌘L
("Edit Path") or a click right of the path swaps in the existing text field for typing. Right-click
offers Open in Other Panel / New Tab / Copy Path / Set as Hot Path / Show in Finder; long paths
collapse their middle into "…". The text field remains available as a setting.

Approach (see [research.md](research.md)): the core builds the trail of segments from a location
(R1–R3) and decides which segments fit (R4), both pure and tested. The UI adds a `PathBar` view
that hosts the breadcrumb row and the existing `pathField` (R5–R8), reads two settings from
UserDefaults (R9), and routes segment actions to existing panel functions (R10). A new command
`.editPath` (⌘L, Go menu) opens editing (R11).

## Technical Context

**Language/Version**: Swift 6.2 (strict concurrency, upcoming features ExistentialAny,
InternalImportsByDefault, MemberImportVisibility)

**Primary Dependencies**: Foundation; AppKit and SwiftUI (UI module only); `NSWorkspace` icons

**Storage**: UserDefaults — `pathBar.style` (`"breadcrumbs"` default, `"text"`),
`pathBar.showIcons` (Bool, default true); hot paths unchanged (existing `AppSettings`)

**Testing**: Swift Testing (`swift test`) for trail building and fitting; GUI checks in the test
copy `iCmdTest.app` (bundle id `cz.acidek.axolotlcommander.gtest`) with panels in a scratch folder

**Target Platform**: macOS 15+

**Project Type**: desktop-app (SwiftPM: `CommanderCore` without AppKit + `AxolotlCommander` AppKit)

**Performance Goals**: the bar updates in the same main-thread pass as the file list after a
navigation (SC-005); layout of a trail of up to ~60 segments is a linear pass, no I/O except
icon lookup (cached by `NSWorkspace`)

**Constraints**: segments never take focus; only navigation, no file operations (FR-028); the
text field and its input rules are reused unchanged; all new texts in en + cs

**Scale/Scope**: 1 new core file, 1 new UI file, ~5 UI files touched, ~20 new tests, ~20 strings

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | Navigation only (FR-028); no drop target, no file operations. GUI tests in a scratch folder of the test copy; Show in Finder only on scratch folders. |
| II Faithful reference behavior | ✅ | Click on a path part goes there, hover highlight, right-click hot path / copy path, active panel color, ⇧F7 unchanged. Deviations D-001–D-004 recorded in the spec. |
| III Native macOS | ✅ | Finder-like segments with system icons and label colors (dark mode, contrast), ⌘-click = new tab, accessibility buttons, UserDefaults, `String(localized:)`. |
| IV Testable core | ✅ | Trail building (local, home, other volume, archive, remote, results) and the collapsing rule live in `CommanderCore` with tests; the UI only renders and routes. |
| V Clean-room, GPL | ✅ | Behavior from the spec and the reference help; no reference sources; own wording; no new dependencies; SPDX headers. |
| VI Incremental delivery | ✅ | US1+US2 (P1) first, then US3, US4, US5; commit after each step. |
| VII Language | ✅ | Spec, plan, code, comments and commits in English; Czech only in the String Catalog. |

Re-check after Phase 1 design: unchanged, no violations → Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/003-breadcrumb-path-bar/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1–R12
├── data-model.md        # Phase 1: segment, trail, fit, settings
├── quickstart.md        # Phase 1: validation scenarios
├── contracts/
│   └── path-bar.md      # Core API + UI behavior contract
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/CommanderCore/
├── Command.swift                 # + .editPath ("Edit Path", Go menu, ⌘L)
└── Window/
    └── Breadcrumbs.swift         # NEW: PathSegment, Breadcrumbs.trail(...), Breadcrumbs.fit(...)

Sources/AxolotlCommander/
├── PathBar.swift                 # NEW: PathBar (row of segments + hosted pathField), segment views,
│                                 #      hover, click, ⌘-click, context menu, "…" menu, accessibility
├── PanelViewController.swift     # pathField → PathBar; trail on every model change; .editPath;
│                                 #   end editing → breadcrumbs; segment actions
├── PanelTabs.swift               # setHotPath(slot, path:), menus anchored at the path bar
├── SettingsView.swift            # Appearance: Path bar style picker + "Show icons in path bar"
└── MainWindowController.swift    # (only if needed) activation from a segment click

Resources/Localizable.xcstrings   # new texts (en, cs)

Tests/CommanderCoreTests/
└── BreadcrumbsTests.swift        # NEW: trails for all location kinds, fitting rule
```

**Structure Decision**: The existing two-module layout. What the trail is and which segments fit
are pure functions of the location and of measured widths, so they go to
`CommanderCore/Window` next to `FunctionKeyBar`; AppKit drawing, icons and event handling go into
the UI module.

## Implementation Notes

- **Hosting the field**: `PathBar` owns the breadcrumb row and gets the existing `pathField`
  as a subview; both fill the bar. In breadcrumb mode the row is visible and the field hidden
  except while editing; in text mode only the field is visible. The bar keeps the field's height
  so switching modes does not move the file list.
- **Active color**: the bar draws the background (accent tint / neutral fill) for both modes, so
  the field's own background is turned off.
- **Ending editing**: `controlTextDidEndEditing` (Enter, Esc, focus moved) switches back to the
  row. In breadcrumb mode Enter also returns focus to the list right away, also after an error
  (spec US2 scenario 4); in text mode Enter keeps today's behavior.
- **Menus anchored at the path line** (volume menu ⌥F1/⌥F2, hot paths menu) pop up at the bar
  instead of the field, so they work in both modes.
- **Trail inputs**: location, results, archive, remote endpoint, the volume root and its name,
  the home folder. The UI supplies volume root/name (resource values, the same names the volume
  bar shows) and the home folder; the core never touches the file system.
- **Cursor after a click**: `go(to: segment.url, focusing: child)` where `child` is the name of
  the next segment on the trail (the archive file name when leaving an archive).

## Complexity Tracking

No violations.
