# Implementation Plan: Function Key Bar and Hideable Command Line

**Branch**: `002-function-key-bar` | **Date**: 2026-10-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-function-key-bar/spec.md`

## Summary

A row of twelve buttons F1–F12 at the bottom of the main window shows, for the modifiers held
right now, the command each function key runs (key number and name, no icons), and runs it on click
without taking focus. The bar and the command line can each be hidden from the View menu,
Settings and the bar's right-click menu; both are shown by default and remembered. Settings →
Keyboard and a one-time notice explain when function keys need `fn` and open System Settings.

Approach (see [research.md](research.md)): the core computes the slots from the existing
`KeyMap` (R1) and holds short titles (R2) and the notice rule
(R10); the UI adds `FunctionKeyBar` (AppKit view, R3, R6, R11) to the window's vertical stack,
follows `.flagsChanged` (R5), validates through `canPerformIgnoringFocus` (R7), and stores the
two visibility flags in UserDefaults shared with Settings (R8). The system `fnState` is only
read (R9).

## Technical Context

**Language/Version**: Swift 6.2 (strict concurrency, upcoming features ExistentialAny,
InternalImportsByDefault, MemberImportVisibility)

**Primary Dependencies**: Foundation; AppKit and SwiftUI (UI module only); CoreFoundation
preferences API (read-only) for `com.apple.keyboard.fnState`

**Storage**: UserDefaults — `showCommandLine`, `showFunctionKeyBar` (Bool, default true),
`functionKeyNotice` (JSON); existing `keys.bindings` unchanged

**Testing**: Swift Testing (`swift test`) for the core (slots, short titles, notice
rule); GUI checks in the test copy `iCmdTest.app` (bundle id `cz.acidek.axolotlcommander.gtest`)
with both panels in a scratch folder

**Target Platform**: macOS 15+

**Project Type**: desktop-app (SwiftPM: `CommanderCore` without AppKit + `AxolotlCommander` AppKit)

**Performance Goals**: modifier switch updates all twelve buttons well under 100 ms (SC-003);
validation on window update costs twelve `canPerform` calls

**Constraints**: buttons never take focus; the app never writes the system function-key
setting; no hard-coded command names in the bar; all new texts in en + cs

**Scale/Scope**: 2–3 core files, ~6 UI files touched, ~15 new tests, ~30 new strings

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | No new file operations; buttons run the existing commands with their existing confirmations. GUI tests of F5/F7/F8 clicks only in a scratch folder in the test copy. |
| II Faithful reference behavior | ✅ | Bar as in Tandem/Total Commander (F-key row, modifier sets). Deviations D-001–D-002 recorded in the spec (D-003 withdrawn: no icons). Unfinished commands stay grayed out. |
| III Native macOS | ✅ | AppKit buttons with system label colors (dark mode, contrast), UserDefaults, System Settings link; no main-thread I/O; texts through `String(localized:)` and the String Catalog. |
| IV Testable core | ✅ | Slot computation, short titles and notice rule live in `CommanderCore` with tests; the UI only renders. |
| V Clean-room, GPL | ✅ | Behavior from the spec and the reference help; no reference sources; own wording; no new dependencies; SPDX headers in new files. |
| VI Incremental delivery | ✅ | US1 → US2 → US3 → US4, each usable on its own; commit after each step. |
| VII Language | ✅ | Spec, plan, code, comments and commits in English; Czech only in the String Catalog translations. |

Re-check after Phase 1 design: unchanged, no violations → Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/002-function-key-bar/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1–R11
├── data-model.md        # Phase 1: slots, presentation, settings, notice state
├── quickstart.md        # Phase 1: validation scenarios
├── contracts/
│   └── function-key-bar.md   # Core API + UI behavior contract
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/CommanderCore/
├── Command.swift                 # + .toggleCommandLine, .toggleFunctionKeyBar (View menu)
└── Window/
    ├── FunctionKeyBar.swift      # NEW: slots(in:modifiers:), short titles
    └── FunctionKeyNotice.swift   # NEW: notice state and decision rule

Sources/AxolotlCommander/
├── FunctionKeyBarView.swift      # NEW: the bar (buttons, fitting, tooltips, context menu)
├── FunctionKeys.swift            # NEW: read fnState, open System Settings, show the notice
├── MainWindowController.swift    # stack layout, modifier monitor, visibility, performFromBar
├── SettingsView.swift            # General: two visibility toggles
├── KeyboardSettings.swift        # fn state line + "Open Keyboard Settings"
├── AppDelegate.swift             # trigger the notice after the main window appears
└── Localization.swift            # localizedShortTitle

Resources/Localizable.xcstrings   # new titles, short titles, notice and settings texts (en, cs)

Tests/CommanderCoreTests/
├── FunctionKeyBarTests.swift     # NEW: slots × modifiers, remap, short titles
└── FunctionKeyNoticeTests.swift  # NEW: shown at most twice, suppress, standard keys
```

**Structure Decision**: The existing two-module layout. Pure logic (what each slot shows, what
it is called, whether to show the notice) goes into `CommanderCore/Window` next to
`WindowLayout`; AppKit rendering and system integration go into the UI module.

## Implementation Notes

- **Layout**: `MainWindowController.container` stacks `[split, separator, commandLine,
  separator, functionKeyBar]`; visibility toggles `isHidden` of an element and its separator.
- **performFromBar**: shares routing with `perform`, but uses `canPerformIgnoringFocus` and does
  not change the first responder; `.focusCommandLine` and the insert commands go through the
  same "show the command line first" path as keys and menu items.
- **Focus-independent commands**: `.toggleCommandLine` and `.toggleFunctionKeyBar` are enabled
  even while the command line edits.
- **Refresh triggers for the bar**: `KeyMaps.didChange` (remap, FR-005), `.flagsChanged` and
  key/resign key of the window (FR-013/015), `NSWindow.didUpdateNotification` (enabled state,
  FR-008), `viewDidLayout`/frame change (label fitting, FR-011).
- **Notice timing**: after `showWindow` in `applicationDidFinishLaunching`, on the next run loop
  turn, as a sheet of the main window.

## Complexity Tracking

> No Constitution Check violations.
