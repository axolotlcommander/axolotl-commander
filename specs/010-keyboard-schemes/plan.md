# Implementation Plan: Keyboard Schemes and Settings Export

**Branch**: `010-keyboard-schemes` | **Date**: 2026-10-12 | **Spec**: [spec.md](spec.md)

## Summary

Three pieces, all on top of the existing key machinery (`CommandRegistry`, `KeyBindings`, `KeyMap`,
`KeyMaps`):

1. **More default chords.** The 23 chords of FR-001 are appended to the chord lists in
   `CommandRegistry.all`. Each command's first chord stays the same, so menus do not change. The
   existing `noChordBoundTwice` test guards collisions. A new test guards the keys the panel
   handles directly.
2. **Key schemes.** A core `KeyScheme` enum (`axolotl`, `classicCommander`) carries its changes as
   data. `KeyBindings` gets a `scheme`: a command's chords are the user's override, else the
   scheme's chords, else the factory chords. `KeyMaps` stores the scheme under its own key
   (`keys.scheme`), so the overrides format stays exactly as before. Settings → Keyboard gets a
   scheme picker, the source of each command's chords and a Mission Control hint.
3. **Export and import.** A core `SettingsArchive` writes and reads one JSON file. It works on an
   injected `UserDefaults` and an allowlist catalog of keys and sections, so it is unit-tested on a
   temporary suite and can never export a key that is not in the catalog. The app adds two
   app-menu commands and two buttons in Settings → General. It also adds the import dialog with
   section checkboxes and the live reload of everything it changed.

See [research.md](research.md) for the decisions and [data-model.md](data-model.md) for the types.

## Technical Context

**Language/Version**: Swift 6.2, strict concurrency.

**Primary Dependencies**: Foundation in the core, AppKit and SwiftUI (Settings) in the UI. No new
packages.

**Storage**: UserDefaults:
- `keys.bindings`: unchanged format, the user's overrides;
- `keys.scheme`: new, the raw scheme value, absent = Axolotl;
- the settings file is a user-chosen JSON file, written only on export and read only on import.

**Testing**: Swift Testing:
- `KeySchemeTests`: scheme data, effective chords, sources, normalization, switching, migration,
  no chord bound twice per scheme and context, the FR-001 chords and the panel's direct keys;
- `SettingsArchiveTests`: round trip on a temporary `UserDefaults(suiteName:)` suite, removed after
  the test; skipping and reporting; newer version; damaged and foreign files; the allowlist (no
  secret);
- the existing `KeyBindingTests` and `KeyMapTests` stay green.

The GUI check follows [quickstart.md](quickstart.md) in the test copy.

**Target Platform**: macOS 15+.

**Project Type**: desktop app (SwiftPM: the `CommanderCore` library and the `AxolotlCommander` app).

**Performance Goals**:
- a scheme switch rebuilds four key maps and the menu key equivalents, well under 1 s (SC-002);
- export and import of a settings file are instant.

**Constraints**:
- tests never touch `UserDefaults.standard` or real files;
- import writes only the catalog's keys of the app's own defaults;
- no secret ever reaches the file (the catalog has no secret keys, and `ConnectionProfile` has no
  password field);
- the app never changes system settings.

**Scale/Scope**:
- core:
  - 2 new files: `KeyScheme.swift` and `Settings/SettingsArchive.swift` (+ `JSONValue`);
  - changes in `Command.swift` (chords, 2 commands, `KeyBindings`) and `FunctionKeyBar.swift` (bar
    titles);
- UI:
  - 1 new file, `SettingsTransfer.swift` (export/import flows);
  - changes in `KeyMaps`, `KeyboardSettings`, `SettingsView`, `AppDelegate`, `AppSettings`,
    `MainWindowController` (⌃⇥ routing), `MainToolbar` and `UserMenuPresenter`;
- about 30 strings;
- 2 new test files.

## Constitution Check

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | Export writes only the file the user picks in a save panel. Import reads only the picked file and writes only the catalog's keys of the app's own defaults. Tests use a temporary defaults suite and the temporary directory. The GUI check runs in the test copy with its own bundle id, so the installed app's settings are never touched. |
| II Reference behavior | ✅ | The reference has no key schemes or settings export. The keys follow classic two-panel manager habits, which the spec Context records. |
| III Native macOS | ✅ | `NSSavePanel` / `NSOpenPanel`, app-menu commands with validation, live updates through the existing notifications. No system settings are changed; Mission Control is only explained. |
| IV Testable core | ✅ | Schemes, effective chords and the whole archive format, validation and apply logic are core code, with injected `UserDefaults` and catalog. |
| V Clean-room, GPL | ✅ | No reference sources, SPDX headers, no new dependencies. No other product is named in the UI. |
| VI Incremental | ✅ | US1 (chords) ships alone; US2 + US3 (schemes) next; US4 (export/import) last. Each is committed green. |
| VII Language | ✅ | English in git; Czech only in `Localizable.xcstrings` ("Klasický Commander"). |

Re-check after design: no violations.

## Project Structure

### Documentation

```text
specs/010-keyboard-schemes/
├── spec.md, plan.md, research.md, data-model.md, quickstart.md
├── contracts/settings-file.md    # the JSON format
├── contracts/keyboard-ui.md      # scheme picker, sources, commands, import dialog
├── checklists/requirements.md
└── tasks.md                      # /speckit-tasks
```

### Source code

```text
Sources/CommanderCore/Command.swift              # FR-001 chords; exportSettings/importSettings; KeyBindings.scheme
Sources/CommanderCore/KeyScheme.swift            # NEW: KeyScheme, ChordSource
Sources/CommanderCore/Window/FunctionKeyBar.swift  # bar titles: Quit, Link
Sources/CommanderCore/Settings/JSONValue.swift   # NEW: generic JSON value (sorted, typed)
Sources/CommanderCore/Settings/SettingsArchive.swift  # NEW: catalog, export, read, apply, ImportReport
Sources/AxolotlCommander/KeyMaps.swift           # scheme load/save, reload()
Sources/AxolotlCommander/KeyboardSettings.swift  # scheme picker, sources, Reset to scheme, hint
Sources/AxolotlCommander/SettingsTransfer.swift  # NEW: app catalog, save/open panels, import dialog, live reload
Sources/AxolotlCommander/SettingsView.swift      # General tab buttons
Sources/AxolotlCommander/AppDelegate.swift       # the two app-menu commands
Sources/AxolotlCommander/AppSettings.swift       # reload() after import
Sources/AxolotlCommander/MainWindowController.swift  # ⌃⇥ / ⌃⇧⇥ routed to the panel command; sheet check
Sources/AxolotlCommander/MainToolbar.swift       # apply an imported toolbar configuration
Resources/Localizable.xcstrings                  # en + cs
Tests/CommanderCoreTests/KeySchemeTests.swift    # NEW
Tests/CommanderCoreTests/SettingsArchiveTests.swift  # NEW
CHANGELOG.md                                     # "Unreleased" (the 0.4.0 bump comes after spec 016)
```

**Structure Decision**: the existing layout. Settings import and export get their own core folder,
because later specs (011) add preferences to the same catalog.

## Delivery order

1. **US1, default chords**:
   - FR-001 chords in the registry;
   - bar titles;
   - tests for the chords and for the panel's direct keys.
   Commit.
2. **US2 + US3, schemes (core)**:
   - `KeyScheme` with the FR-006 data;
   - `KeyBindings.scheme`, `chords(for:)`, `source(for:)`, `isCustomized`, `set`, `reset`;
   - tests (FR-007, FR-010–FR-014, migration).
   Commit.
3. **US2 + US3, schemes (UI)**:
   - `KeyMaps` scheme storage;
   - the Settings → Keyboard picker, sources, reset and hint;
   - ⌃⇥ routing;
   - strings.
   Build, then a GUI check. Commit.
4. **US4, archive (core)**:
   - `JSONValue`, `SettingsArchive` with its catalog types and report;
   - tests.
   Commit.
5. **US4, export and import (UI)**:
   - the app catalog;
   - the menu commands and General buttons;
   - the panels and the import dialog;
   - the live reload;
   - strings.
   Build, then a GUI check. Commit.
6. **Polish**:
   - CHANGELOG "Unreleased";
   - the full quickstart run in the test copy;
   - install for the user to try (no version bump; 0.4.0 comes after spec 016).

## Complexity Tracking

None.
