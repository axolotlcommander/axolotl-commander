---

description: "Task list for Keyboard Schemes and Settings Export"
---

# Tasks: Keyboard Schemes and Settings Export

**Input**: Design documents from `specs/010-keyboard-schemes/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/settings-file.md](contracts/settings-file.md),
[contracts/keyboard-ui.md](contracts/keyboard-ui.md)

**Tests**: requested by the spec (core unit tests). The GUI check follows
[quickstart.md](quickstart.md).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: the user story the task belongs to

## Phase 1: Setup

No setup: the existing SwiftPM layout, no new dependencies.

## Phase 2: Foundational

None. US1 needs only the registry, and US2 and US3 build on `KeyBindings`.

## Phase 3: User Story 1 - Familiar keys work out of the box (P1) 🎯 MVP

**Goal**: the 24 FR-001 chords work in a panel, next to every existing chord.

**Independent test**: `swift test` (KeyMapTests); in the GUI, ⌥←, ⇧F6, ⌃F1 and ⌃R in a panel, and
the ⌃ / ⇧ / ⌥ layers of the function key bar.

- [X] T001 [US1] In `Sources/CommanderCore/Command.swift` `CommandRegistry.all`, **append** the FR-001
  chords (research.md R1). Existing chords keep their order.
  - Panel and navigation:
    - openInLeftPanel `K(.left, c)`; openInRightPanel `K(.right, c)`;
    - goBack `K(.left, o)`; goForward `K(.right, o)`;
    - switchPanel `ch("i", c)`;
    - hotPaths `ch("d", c)`;
    - refresh `ch("r", c)`.
  - View:
    - viewModeBrief `f(1, c)`;
    - comparePanels `f(2, s)`;
    - branchViewSelected `[ch("b", [c, s])]`, its only chord;
    - calculateSizes `K(.enter, [o, s])`.
  - File:
    - rename `f(6, s)`;
    - properties `K(.enter, o)`;
    - unpack `f(9, o)`.
  - Edit:
    - selectAll `ch("a", c)`;
    - copyFiles `ch("c", c)`; pasteFiles `ch("v", c)`;
    - selectSameExtension `K(.numPlus, o)`; deselectSameExtension `K(.numMinus, o)`.
  - Servers: connectToServer `ch("f", c)`, `ch("n", c)`.
  - Command line:
    - insertNameToCommandLine `ch("j", c)`;
    - insertPathToCommandLine `ch("p", c)`;
    - the new command `insertFullPathToCommandLine` ("Insert Full Path", panel only, no menu,
      `[K(.enter, [c, s])]`), declared next to `insertPathToCommandLine`.
- [X] T001a [US1] `Sources/AxolotlCommander/MainWindowController.swift`: handle
  `insertFullPathToCommandLine` everywhere `insertNameToCommandLine` is handled:
  - enablement;
  - the list of command-line commands;
  - `handleCommandLineKey`;
  - `performHere`.

  It inserts `ShellQuote.quote(<location displayPath joined with the item name>) + " "`. On "..", it
  inserts the folder path, like `insertPath`.
- [X] T002 [US1] In `Sources/CommanderCore/Window/FunctionKeyBar.swift`, add the bar title "Quit"
  for `.quit` (`barTitles`) and the short title "Link" for `.newSymbolicLink` (`shortTitles`).
- [X] T003 [US1] Create `Tests/CommanderCoreTests/HabitChordTests.swift`:
  - a parameterized test that every FR-001 chord maps to its command in `KeyMap.standard`, and that
    `windowsBindingsSurvive` still passes;
  - a test that no FR-001 chord is one of the panel's direct chords:
    - ⌥↑, ⌥↓, ⌥Home, ⌥End;
    - ⌃↑, ⌃↓;
    - plain or ⇧ movement keys;
    - plain, ⇧ or unmodified characters.
  - a test that every command's first chord is unchanged by T001: menu chords stay, checked through
    `menuCanPickFirstMenuSafeChord`-style expectations for goBack (⌃⌥←), rename (F2), refresh (⌃F9),
    selectAll (⌘A) and copyFiles (⌘C).

  Run `swift build` (no warnings) and `swift test`. Commit `[Spec 010] Add default chords from
  classic file manager habits`.

**Checkpoint**: US1 is complete on its own.

## Phase 4: User Story 2 + User Story 3 - Schemes and personal changes (P1)

**Goal**: the Classic Commander scheme can be switched on. User changes sit on top of it, survive
switching and reset to the scheme.

**Independent test**: `swift test` (KeySchemeTests); in the GUI, switch the scheme and check ⌃T / ⌃W
/ ⌃⇥, the menus and the F-key bar; set a user chord, switch twice and reset.

### Core

- [X] T004 [P] [US2] Create `Sources/CommanderCore/KeyScheme.swift` (SPDX header) per data-model.md:
  - `KeyScheme` (`axolotl`, `classicCommander`, String raw values, `CaseIterable`, `Sendable`), with
    `changes` holding exactly the Classic Commander table of data-model.md and `chords(for:)`;
  - `ChordSource` (`defaults`, `scheme`, `user`).
- [X] T005 [US3] Change `KeyBindings` in `Sources/CommanderCore/Command.swift` per data-model.md:
  - `scheme` (default `.axolotl`, not encoded);
  - `init(scheme:overrides:)`, which normalizes against the scheme; `init(overrides:)` delegates
    with `.axolotl`;
  - `init(from:)` keeps every valid override without normalizing;
  - `chords(for:)` = override ?? scheme chords;
  - `isCustomized` = an override exists and differs from the scheme's chords;
  - `source(for:)`;
  - `set` normalizes against the scheme.

  `reset`, `resetAll` and `conflicts` keep their code. Update the doc comments.
- [X] T006 [P] [US3] Create `Tests/CommanderCoreTests/KeySchemeTests.swift`:
  - Scheme data:
    - Axolotl has no changes;
    - every FR-006 row holds in Classic Commander through `KeyMap(context: .panel, bindings:
      KeyBindings(scheme: .classicCommander))`. For example ⌃T → newTab, ⌃W → closeTab,
      ⌃⇥ → nextTab, ⌃↓ → focusCommandLine, Num/ → restoreSelection, ⌃F2 → viewModeDetailed,
      ⌃⇧F → disconnect, ⌃⇧F5 → newSymbolicLink, ⌥F3 → viewWith, ⌥F4 → quit, F2 → rename,
      ⌃⇧T → newTab;
    - goToLinkTarget, changeAttributes and saveSelection have no chord;
    - the menu chord of quit is ⌘Q.
  - FR-007: for both schemes and every context, no chord is bound to two commands (the scheme
    chords of every command in the context, as in `noChordBoundTwice`).
  - FR-010: a user chord (⌃T for goToLinkTarget) beats the scheme's newTab ⌃T, and `KeyMap.chords(for:
    .newTab)` no longer contains ⌃T.
  - FR-011:
    - `set` equal to the scheme's chords stores no override;
    - `source` is `.scheme` for newTab under Classic Commander and `.defaults` under Axolotl.
  - FR-013:
    - switching the scheme keeps the overrides;
    - an override equal to the new scheme shows `isCustomized == false` and `source == .scheme`,
      and is customized again after switching back.
  - FR-014: `reset` and `resetAll` give the scheme's chords, and the scheme stays.
  - FR-012 / SC-006: JSON in the 0.3.x form (`{"rename":["shift+F11"]}`) decodes to the same
    overrides, applies on top of Axolotl and encodes back to the same JSON.
  - Decoding does not drop an override equal to the factory chords, so a Classic Commander user can
    pin newTab to ⌃⇧T only.
  - `conflicts` sees scheme chords: ⌃T for goToLinkTarget under Classic Commander conflicts with
    newTab.

  Run `swift test`. Commit `[Spec 010] Key schemes in the core`.

### UI

- [X] T007 [US2] `Sources/AxolotlCommander/KeyMaps.swift`:
  - store the scheme under `keys.scheme` (absent = Axolotl) and load it with the bindings at startup;
  - `update(_:)` saves the overrides (key removed when there are none) and the scheme (key removed
    for Axolotl) separately;
  - add `reload()`, which reads both keys again and goes through the update path, for import.
- [X] T008 [US2] `Sources/AxolotlCommander/MainWindowController.swift` `interceptKey`: while a panel
  has focus, a ⌃⇥ / ⌃⇧⇥ chord that `KeyMaps.panel` binds to any command runs that command on the
  active panel (focusCommandLine keeps its current handling). Command-line editing is unchanged
  (research.md R4). Check that `nextTab` / `previousTab` work through `perform`; if they are window
  actions, route them the same way the menu does.
- [X] T009 [US2] `Sources/AxolotlCommander/KeyboardSettings.swift` (contracts/keyboard-ui.md):
  - a "Key scheme:" picker above the table that sets `bindings.scheme` through `update`;
  - a source label per command row ("Default", "Scheme", "Changed");
  - chords another command took are shown as inactive, with "used by <command>";
  - Reset and Reset All… go back to the scheme, with the alert text "Reset all shortcuts to the
    selected key scheme?";
  - the Mission Control hint under the table.

  `assign` keeps removing a chord from conflicting commands, using the effective chords.
- [X] T010 [US2] Add the scheme display names in `Sources/AxolotlCommander/KeyboardSettings.swift`:
  `KeyScheme.localizedTitle`, "Axolotl" / "Classic Commander".
- [X] T011 [US2] `Resources/Localizable.xcstrings`: add en + cs for the T009/T010 strings ("Key
  scheme:" → "Schéma kláves:", "Classic Commander" → "Klasický Commander", "Default" → "Výchozí",
  "Scheme" → "Schéma", "Changed" → "Změněno", the hint, the reset alert, "used by %@", "Quit" (bar),
  "Link" (bar)).

  Run `swift build` (no warnings) and `swift test`. Run the quickstart US1–US3 GUI steps in the test
  copy. Commit `[Spec 010] Key scheme picker in Settings`.

**Checkpoint**: US1–US3 work. Schemes switch live.

## Phase 5: User Story 4 - Export and import the complete settings (P1)

**Goal**: one JSON file carries the keys, preferences, appearance, hot paths, user menu, saved servers
and toolbar. Import applies the chosen parts live and reports what it skipped.

**Independent test**: `swift test` (SettingsArchiveTests); in the GUI, export, change settings, import,
then import a broken file.

### Core

- [X] T012 [P] [US4] Create `Sources/CommanderCore/Settings/JSONValue.swift` (SPDX header):
  - `JSONValue` with its Codable form, `init(data:)` / `data(sortedPretty:)`;
  - conversion to and from property-list values (`Bool`, numbers, `String`, `[String]`,
    dictionaries and arrays of those).

  NSNumber booleans stay booleans.
- [X] T013 [US4] Create `Sources/CommanderCore/Settings/SettingsArchive.swift` (SPDX header) per
  data-model.md and contracts/settings-file.md:
  - the catalog types: `PreferenceKind`, `PreferenceSpec`, `SettingsSection`, `BlobSpec`,
    `SettingsCatalog`;
  - `SettingsCatalog.core(preferences:toolbarKey:)`, which builds the blob specs for appearance
    (`PanelAppearance`, key `appearance`), hotPaths (`HotPaths`, key `hotPaths`), connections
    (`[ConnectionProfile]` elementwise, key `connections`), userMenu (`UserMenuItem` elementwise via
    `UserMenuStore`, key `userMenu.items`) and toolbar (property list);
  - `SettingsContents`, `SettingsArchiveError`, `ImportReport`, `SkippedEntry`, `SkipReason`;
  - `export(from:catalog:appVersion:date:) -> Data`:
    - sorted keys, pretty printed;
    - only catalog keys;
    - absent defaults are not written;
    - the keyboard section always has `scheme` and `bindings`.
  - `read(_:) throws -> SettingsContents`:
    - `.notJSON`, `.notSettingsFile`;
    - `isNewer` when `formatVersion > 1`;
    - unknown sections are listed.
  - `apply(_:sections:to:catalog:) -> ImportReport`. It validates everything first, then writes the
    chosen sections (research.md R7):
    - preferences: per key;
    - keyboard: the scheme plus per-command entries; the overrides are replaced as a whole;
    - lists: elementwise, replacing the whole list;
    - whole values: replaced, or skipped when invalid.
- [X] T014 [P] [US4] Create `Tests/CommanderCoreTests/SettingsArchiveTests.swift`. Each test uses its
  own `UserDefaults(suiteName: "test.settings.<uuid>")` and calls `removePersistentDomain` at the end.
  It covers:
  - **Round trip**: fill every catalog kind, export, clear, import all, and every value is equal.
    A second export is byte-identical apart from `exported` (SC-004).
  - **Allowlist / SC-005**:
    - keys outside the catalog (`panel.left.path`, `commandLine.history`, `secret.password`) never
      appear in the file;
    - a `ConnectionProfile` export has no field whose name contains "password".
  - **Section choice**: unchecked sections stay unchanged.
  - **Skips**:
    - an unknown command, a malformed chord, an unknown preference key, a wrong type, an
      out-of-range number, an unknown scheme, a bad connection element (the good ones still
      apply), an unknown section;
    - each one is reported with its reason.
  - **Header**:
    - a newer `formatVersion` → `isNewer`, and the known parts apply;
    - not JSON → `.notJSON`;
    - a JSON object without the right `format` → `.notSettingsFile`, and the suite is unchanged
      (SC-007).
  - **An older file** missing a preference key leaves that key unchanged.

  Run `swift test`. Commit `[Spec 010] Settings archive in the core`.

### UI

- [X] T015 [US4] Add the commands `exportSettings` ("Export Settings…") and `importSettings` ("Import
  Settings…"), both app scope, to `Sources/CommanderCore/Command.swift`:
  - in the `Command` App case list;
  - in the registry after `.settings`, without chords;
  - both are in the app menu, so Quit keeps its separator.

  Check that `everyCommandIsDeclaredOnce` and `noChordBoundTwice` still pass.
- [X] T016 [US4] Create `Sources/AxolotlCommander/SettingsTransfer.swift` (SPDX header):
  - the app catalog: the preference keys of research.md R6, with allowed values taken from the app
    enums (path bar style, size display and units, text encodings, checksum algorithms), number
    ranges (viewer and compare font size 6…72), `comparison` as `json` (`ComparisonOptions`), and
    the toolbar key `"NSToolbar Configuration MainToolbar"`;
  - `exportSettings(from window:)`: an `NSSavePanel` ("Axolotl Commander Settings.json") and
    `SettingsArchive.export`, with the app version from the bundle;
  - `importSettings(from window:)`:
    1. an `NSOpenPanel` (JSON);
    2. `read`, or the error alert on failure;
    3. the checkbox alert (contracts/keyboard-ui.md);
    4. `apply` to `UserDefaults.standard`;
    5. the live reload (research.md R8);
    6. the summary alert.
- [X] T017 [US4] `Sources/AxolotlCommander/AppSettings.swift`: add `reload()`, which loads appearance,
  hotPaths, comparison and connections again from UserDefaults; the `didSet` saves are harmless. In
  `Sources/AxolotlCommander/MainToolbar.swift`, add a way to apply a toolbar configuration
  dictionary to each main window's toolbar.
- [X] T018 [US4] `Sources/AxolotlCommander/AppDelegate.swift`:
  - `exportSettings` and `importSettings` are always-enabled app commands that call
    `SettingsTransfer`;
  - Import is disabled while any main window has an attached sheet.
- [X] T019 [US4] `Sources/AxolotlCommander/SettingsView.swift`: add the "Export Settings…" and "Import
  Settings…" buttons to the General tab, calling `SettingsTransfer` with the Settings window.
- [X] T020 [US4] `Resources/Localizable.xcstrings`: add en + cs for:
  - the two commands;
  - the panel titles, the error alert and the confirmation alert;
  - the section names;
  - the newer-version line;
  - the summary and the skip reasons.

  Run `swift build` (no warnings) and `swift test`. Run the quickstart US4 GUI steps in the test copy.
  Commit `[Spec 010] Export and import of the complete settings`.

**Checkpoint**: all user stories work.

## Phase 6: Polish

- [X] T021 [P] `CHANGELOG.md`: add "Unreleased" entries for the new default chords, the Classic
  Commander key scheme and settings export and import. No version bump; 0.4.0 comes after spec 016.
- [ ] T022 Run the full quickstart in the test copy:
  - screenshots of the test windows only;
  - check the menus, the F-key bar layers and the import summary.
- [ ] T023 Install the app for the user to try (`scripts/bundle.sh release` + `scripts/install.sh`).
  If the installed app is running, ask before quitting it. Update `docs/STATE.md`.

## Dependencies & Execution Order

- **US1**: T001 → T003; T002 is independent.
- **US2/US3**:
  - T004 → T005 → T006;
  - then T007 → T008, T009, T010 → T011.
- **US4**:
  - T012 → T013 → T014 (the core is independent of US2/US3, except the keyboard section, which
    needs T005);
  - T015 → T016 → T017, T018, T019 → T020.
- **Polish** after all of them.

## Parallel Example

```text
T004 (KeyScheme.swift) ∥ T012 (JSONValue.swift) — different new files
T006 (KeySchemeTests) ∥ T014 (SettingsArchiveTests) once their sources exist
```

## Implementation Strategy

1. US1 alone is the MVP: free chords, no settings.
2. Schemes (US2 + US3) next, since the user's changes and the scheme share `KeyBindings`.
3. Export and import (US4) last, because they serialize what US2/US3 made.
4. A commit after every phase. One PR for specs 010–016, with the version bump to 0.4.0.
