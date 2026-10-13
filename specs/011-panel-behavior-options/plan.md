# Implementation Plan: Panel Behavior Options

**Branch**: `011-panel-behavior-options` | **Date**: 2026-10-12 | **Spec**: [spec.md](spec.md)

## Summary

Four switches, each a UserDefaults preference read live. The decisions behind them are pure core
code, so they can be tested:

1. **Space stays**: the panel's Space command skips the cursor move when "Space moves the cursor
   down" is off. Insert (`toggleSelection`) is untouched.
2. **Typing into the command line**: a core `PanelTyping.route` maps a key (plus the setting, the
   quick search state and whether the command line is empty) to an action:
   - append text;
   - delete the last character;
   - clear;
   - run;
   - start quick search;
   - none (today's handling).
   The panel asks it first in `handleKey`. The window controller carries out the line actions on
   `CommandLineBar` without taking the focus from the panel.
3. **⌃← / ⌃→ classic**: a core `OpenInPanel.plan` picks source, target and focus from the command, the
   active side and the setting. `PanelModel.openTarget(parentOpensLocation:)` extends today's
   `otherPanelTarget` with "..". The window controller runs the plan.
4. **Volume buttons**: a core `VolumeChoice.target` applies rules a–d. The core `VolumePlaces` keeps the
   last folder per volume for one panel, in memory. The panel records a visit on every location
   change. Volume buttons and the ⌥F1 / ⌥F2 menu's volume entries go through one method.

Settings → General gets a "Panels" section, and Settings → Keyboard gets a note. The four keys join
`SettingsCatalog.app`.

See [research.md](research.md) for the decisions and [data-model.md](data-model.md) for the types.

## Technical Context

**Language/Version**: Swift 6.2, strict concurrency.

**Primary Dependencies**: Foundation in the core; AppKit and SwiftUI (Settings) in the UI. No new
packages.

**Storage**: UserDefaults:
- `panel.spaceMovesDown` (bool, default true);
- `panel.typingToCommandLine` (bool, default false);
- `panel.arrowsTargetPointedPanel` (bool, default false);
- `panel.volumeButtonsFollow` (bool, default false).

All four are exported in the Preferences section. The last folder per volume is memory only.

**Testing**: Swift Testing, `PanelBehaviorTests`, covering:
- the routing table of `PanelTyping`;
- `OpenInPanel.plan` for both settings, both sides and both commands;
- `PanelModel.openTarget` with "..", folders, files, archives and flat listings, on temp folders;
- `VolumeChoice.target` rules a–d with Home, iCloud, Network and servers excluded;
- `VolumePlaces` visits and the missing-folder fallback;
- the catalog entries and an export round trip.

The existing catalog coverage and format-1 tests stay green.

**Target Platform**: macOS 15+.

**Project Type**: desktop app (SwiftPM: the `CommanderCore` library and the `AxolotlCommander` app).

**Performance Goals**: no visible cost per keystroke. `Volumes.root(of:)` is called once per
location change and per volume pick.

**Constraints**:
- tests use temporary folders and temporary defaults suites only;
- the GUI check never runs a command line that changes files.

**Scale/Scope**:
- core:
  - 1 new file, `PanelBehavior.swift`;
  - a `PanelModel.openTarget` addition;
  - 4 catalog entries;
- UI:
  - `PanelViewController` (keys, Space, volume picks, visits);
  - `MainWindowController` (line actions, open-in-panel plan);
  - `CommandLineBar` (append, delete last, clear, run);
  - `SettingsView` (Panels section);
  - `KeyboardSettings` (note);
- about 12 strings;
- 1 new test file.

## Constitution Check

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | No file operation changes. The typing mode only fills the command line; running it stays an explicit Return, exactly as today. Tests use temp folders and suites. The GUI check browses test folders and never runs a line that changes files. |
| II Reference behavior | ✅ | Each switch follows the classic behavior described in the research note. Deviations are listed in the spec. |
| III Native macOS | ✅ | Defaults keep today's macOS-friendly behavior. The settings are SwiftUI toggles with live effect. |
| IV Testable core | ✅ | All decisions are pure core functions with unit tests; the UI only wires them. |
| V Clean-room, GPL | ✅ | No reference sources, SPDX headers, no new dependencies, no product named. |
| VI Incremental | ✅ | Each switch ships alone: settings first, then Space, typing, arrows, volumes, each committed green. |
| VII Language | ✅ | English in git; Czech only in `Localizable.xcstrings`. |

Re-check after design: no violations.

## Project Structure

### Documentation

```text
specs/011-panel-behavior-options/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md
├── contracts/behavior-ui.md      # the settings, the note and the key routing table
├── checklists/requirements.md
└── tasks.md
```

### Source code

```text
Sources/CommanderCore/PanelBehavior.swift            # NEW: PanelBehavior, PanelTyping, OpenInPanel, VolumeChoice, VolumePlaces
Sources/CommanderCore/PanelModel.swift               # openTarget(parentOpensLocation:)
Sources/CommanderCore/Settings/AppSettingsCatalog.swift  # 4 preferences
Sources/AxolotlCommander/PanelViewController.swift   # typing route, Space, volume picks, visits
Sources/AxolotlCommander/MainWindowController.swift  # line actions, open-in-panel plan
Sources/AxolotlCommander/CommandLineBar.swift        # append, deleteLast, clear, run, text
Sources/AxolotlCommander/SettingsView.swift          # "Panels" section
Sources/AxolotlCommander/KeyboardSettings.swift      # note next to the scheme picker
Resources/Localizable.xcstrings                      # en + cs
Tests/CommanderCoreTests/PanelBehaviorTests.swift    # NEW
CHANGELOG.md                                         # Unreleased
```

**Structure Decision**: the existing layout. All four behavior decisions live in one core file, because
they share the settings type and the tests.

## Delivery order

1. **Settings**:
   - `PanelBehavior` with keys and defaults;
   - catalog entries;
   - the "Panels" section and the Keyboard note;
   - strings;
   - tests for the catalog.
   Commit.
2. **US1 Space**: the Space command honors the setting; test. Commit.
3. **US2 typing**:
   - `PanelTyping.route` with tests;
   - the `CommandLineBar` line actions;
   - panel routing and the window's line actions.
   Commit.
4. **US3 arrows**:
   - `OpenInPanel.plan`, `PanelModel.openTarget` with tests;
   - window wiring and validation.
   Commit.
5. **US4 volumes**:
   - `VolumeChoice`, `VolumePlaces` with tests;
   - panel wiring for buttons, the menu and visits.
   Commit.
6. **Polish**:
   - CHANGELOG;
   - the GUI check (quickstart) in the test copy;
   - install for the maintainer.

## Complexity Tracking

None.
