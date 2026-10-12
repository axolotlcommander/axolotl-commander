# Tasks: Panel Behavior Options

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/behavior-ui.md](contracts/behavior-ui.md)

**Tests**: requested by the spec (SC-004, SC-005), so the core logic gets unit tests.

## Phase 1: Setup

- [X] T001 Create `Sources/CommanderCore/PanelBehavior.swift` with the SPDX header and `PanelBehavior`:
  - the four keys `panel.spaceMovesDown`, `panel.typingToCommandLine`,
    `panel.arrowsTargetPointedPanel`, `panel.volumeButtonsFollow`;
  - defaults: true, false, false, false;
  - `init()`, `init(defaults:)`.
  Add `Side.other` in the same file.

## Phase 2: Foundational (settings, blocks all stories)

- [X] T002 Add the four `PreferenceSpec(..., .bool, default:)` entries, using the `PanelBehavior` key
  constants, to `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`.
- [X] T003 [P] Create `Tests/CommanderCoreTests/PanelBehaviorTests.swift` with tests for:
  - the defaults and `init(defaults:)` on a temporary suite;
  - the catalog entries (kinds, defaults);
  - an export / apply round trip of the four values.
- [X] T004 [US5] Add a "Panels" section to `Sources/AxolotlCommander/SettingsView.swift`: four
  `@AppStorage` toggles with captions per contracts/behavior-ui.md, after the command line section.
- [X] T005 [US5] Add the note under the key scheme picker in
  `Sources/AxolotlCommander/KeyboardSettings.swift`.
- [X] T006 [US5] Add the Czech strings for T004–T005 to `Resources/Localizable.xcstrings`.
  Build, test, commit.

## Phase 3: User Story 1 — Space marks and stays (P1)

- [X] T007 [US1] In `Sources/AxolotlCommander/PanelViewController.swift`, `.toggleSelectionAndSize`
  moves the cursor only when `PanelBehavior(defaults: .standard).spaceMovesDown`. Build, test, commit.

## Phase 4: User Story 2 — Typing goes to the command line (P1)

- [X] T008 [US2] Add `PanelTyping.Action` and `PanelTyping.route(...)` to
  `Sources/CommanderCore/PanelBehavior.swift`, following the data-model rules 1–6.
- [X] T009 [P] [US2] Add routing table tests to `Tests/CommanderCoreTests/PanelBehaviorTests.swift`:
  - each rule;
  - an empty versus a non-empty line;
  - a bound chord;
  - quick search active;
  - ⌥ + character;
  - ⇧ + character;
  - ⇧Return.
- [X] T010 [US2] Add `text`, `append(_:)`, `deleteLast()`, `clear()` to
  `Sources/AxolotlCommander/CommandLineBar.swift`. They work without focus and reset the history
  browser.
- [X] T011 [US2] Add `MainWindowController.commandLine(_ action:)` in
  `Sources/AxolotlCommander/MainWindowController.swift`: it shows the line, appends, deletes the last
  character, clears, or runs it through `execute`, and never moves the focus.
- [X] T012 [US2] In `PanelViewController.handleKey`, when the setting is on and quick search is not
  running, route the key first. `.startQuickSearch` starts quick search with the text. The other
  actions go to the window. `isBound` = a panel command or user menu chord. Build, test, commit.

## Phase 5: User Story 3 — ⌃← / ⌃→ change the panel the arrow points to (P2)

- [X] T013 [US3] Add `OpenInPanel.Plan` and `OpenInPanel.plan(target:active:classic:)` to
  `Sources/CommanderCore/PanelBehavior.swift`, and `PanelModel.openTarget(parentOpensLocation:)` to
  `Sources/CommanderCore/PanelModel.swift`, with `otherPanelTarget` delegating to it.
- [X] T014 [P] [US3] Add tests:
  - plans for both settings, both active sides and both commands;
  - `openTarget` on temp folders: a folder, a file, an archive and "..", with and without the flag.
- [X] T015 [US3] In `MainWindowController`, validate and perform `.openInLeftPanel` /
  `.openInRightPanel` from the plan: the source panel's `openTarget`, the target's `go(to:focusing:)`,
  and the focus. Build, test, commit.

## Phase 6: User Story 4 — Volume buttons (P2)

- [X] T016 [US4] Add `VolumeChoice.target(...)` and `VolumePlaces` to
  `Sources/CommanderCore/PanelBehavior.swift`.
- [X] T017 [P] [US4] Add tests for rules a–d, the missing remembered folder, path normalization and
  `VolumePlaces` visits.
- [X] T018 [US4] In `Sources/AxolotlCommander/VolumeBar.swift`, add an `onChooseVolume` callback for
  `.volume` items (buttons and the overflow menu).
- [X] T019 [US4] In `PanelViewController`:
  - keep `volumePlaces`;
  - record a disk-folder visit in the location-change hook;
  - add `chooseVolume(_:)`, which activates the panel and applies `VolumeChoice` when the setting is
    on, otherwise opens the root;
  - wire `VolumeBar.onChooseVolume` and the volume entries of `showVolumeMenu`.
  Build, test, commit.

## Phase 7: Polish

- [X] T020 Add a CHANGELOG "Unreleased" entry.
- [ ] T021 Run the GUI check from quickstart.md in the test copy, when the maintainer is not at the
  computer.
- [ ] T022 Install for the maintainer, after asking if the app is running.

## Dependencies

- T001 → T002 → the stories.
- US1, US2, US3 and US4 are independent of each other, and all of them come after Phase 2.
- Tests marked [P] can be written next to their implementation task.
