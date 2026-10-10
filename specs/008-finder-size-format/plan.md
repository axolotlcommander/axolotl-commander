# Implementation Plan: File Sizes Like Finder

**Branch**: `008-finder-size-format` | **Date**: 2026-10-10 | **Spec**: [spec.md](spec.md)

## Summary

Two app-wide settings in Settings → Appearance:
- **Size in panels:** "Like Finder" (default) or "In bytes".
- **Units:** 1000 (default) or 1024.

The core gets `SizeFormat`, which is pure and has the locale injected. It produces:
- the system's byte-count text in either base;
- the exact grouped count;
- the Size column's variants, longest first.

`Format.bytes` (UI) uses the saved base, so every rounded size in the app follows the Units
setting from one place.

In the panel:
- the Size cell shows the variant of the current mode that fits, never a cut number;
- the cell's tooltip shows the exact bytes;
- the status line for the item under the cursor shows "4,1 MB (4 100 000 bytes)";
- a settings change reloads only the Size column and the status line.

See [research.md](research.md).

## Technical Context

**Language/Version**: Swift 6.2, strict concurrency.

**Primary Dependencies**: Foundation (`ByteCountFormatStyle`, `IntegerFormatStyle`) in the core;
AppKit and SwiftUI (Settings) in the UI. No new packages.

**Storage**: `UserDefaults` keys `size.display` and `size.units`. A missing key means the
default.

**Testing**: Swift Testing in `Tests/CommanderCoreTests/SizeFormatTests.swift`:
- cs_CZ and en_US;
- both bases and both modes.

The GUI check follows [quickstart.md](quickstart.md) and runs in the test copy.

**Target Platform**: macOS 15+.

**Project Type**: desktop app (SwiftPM: the `CommanderCore` library and the `AxolotlCommander`
app).

**Performance Goals**: a settings change redraws both panels within one second (SC-002). That is
only one column reload, no folder read.

**Constraints**:
- sorting stays by exact bytes;
- exact counts (`Format.grouped`) do not change;
- en + cs strings.

**Scale/Scope**:
- 1 new core file and 1 new test file;
- 4 UI files touched: `Support.swift`, `PanelViewController.swift`, `SettingsView.swift` and a new
  `SizeSettings` in `AppSettings.swift`;
- the core's `CellText.swift` slimmed;
- about 7 strings.

## Constitution Check

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | Display only; tests use no files. The GUI check runs in a scratchpad folder in the test copy. |
| II Reference behavior | ✅ | The reference shows exact bytes. "In bytes" keeps that, and the Finder default is a recorded deviation (spec Context). |
| III Native macOS | ✅ | The system's byte-count formatter, the same as Finder; the settings live in the standard Settings window. |
| IV Testable core | ✅ | All formatting rules are pure core functions with an injected locale. |
| V Clean-room, GPL | ✅ | No reference sources, no new dependencies, SPDX headers. |
| VI Incremental | ✅ | US1 + US2 ship together (one setting), then US3 (base). Each is usable. |
| VII Language | ✅ | English in git; Czech only in `Localizable.xcstrings`. |

Re-check after design: no violations.

## Project Structure

### Documentation

```text
specs/008-finder-size-format/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md
├── contracts/settings-ui.md
├── checklists/requirements.md
└── tasks.md                     # /speckit-tasks
```

### Source code

```text
Sources/CommanderCore/SizeFormat.swift        # NEW: SizeDisplay, SizeUnits, SizeFormat (rounded, exact,
                                              #      columnVariants, roundedIsExact)
Sources/CommanderCore/CellText.swift          # size(_:) removed (replaced by SizeFormat.columnVariants)
Sources/AxolotlCommander/AppSettings.swift    # SizeSettings: keys + saved
Sources/AxolotlCommander/Support.swift        # Format.bytes uses SizeSettings.saved.units
Sources/AxolotlCommander/PanelViewController.swift  # cell variants per mode, tooltip = exact,
                                              #      status line with exact count, live reload,
                                              #      Size column width for the mode
Sources/AxolotlCommander/SettingsView.swift   # two pickers in Appearance
Resources/Localizable.xcstrings               # en + cs
Tests/CommanderCoreTests/SizeFormatTests.swift  # NEW (absorbs the size case of CellTextTests)
CHANGELOG.md, VERSION                         # 0.3.0 (minor)
```

**Structure Decision**: the existing layout. The formatting is core code next to `CellText`. The
settings helper sits next to the other app-wide settings.

## Delivery order

1. **Core** with tests: `SizeFormat`, and `CellText` slimmed. Commit.
2. **US1 + US2**:
   - `SizeSettings`, the "Size in panels" picker;
   - cell variants and the exact tooltip;
   - the status line;
   - live reload and the column width.
   Commit.
3. **US3**: the "Units" picker and `Format.bytes` on the saved base. Commit.
4. **Polish**:
   - localization;
   - the GUI check from the quickstart;
   - `CHANGELOG.md` and the bump to 0.3.0.
   Commit.

## Complexity Tracking

No violations.
