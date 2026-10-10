---

description: "Task list for File Sizes Like Finder"
---

# Tasks: File Sizes Like Finder

**Input**: Design documents from `specs/008-finder-size-format/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/settings-ui.md](contracts/settings-ui.md)

**Tests**: requested by the spec (unit tests of the formatting in the core). The GUI check follows
[quickstart.md](quickstart.md).

**Organization**: US1 and US2 share one setting and ship together; US3 adds the units base.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: the user story the task belongs to

## Phase 1: Setup

No setup: the existing SwiftPM layout, no new dependencies.

## Phase 2: Foundational (core formatting)

**Purpose**: the pure formatting rules every story uses.

- [X] T001 [P] Write `Tests/CommanderCoreTests/SizeFormatTests.swift` (SPDX header, Swift Testing):
  - `SizeFormat.rounded` for cs_CZ and en_US, units `.decimal` and `.binary`, for 0, 1, 402, 999,
    1 000, 1 023, 1 024, 4 300 000, 46 000 000 and 1 200 000 000 000 bytes. Compare with
    `ByteCountFormatStyle(style: .file | .binary, locale:)` and spot-check the research.md R1 table
    (e.g. cs 4 300 000 → "4,3 MB" decimal and "4,1 MB" binary; cs 402 → "402 bajtů"; cs 999 binary →
    "999 bajtů"). Compare with a normalized space: the separator may be a no-break space.
  - `SizeFormat.exact`: grouped digits.
  - `columnVariants`: `.bytes` gives `[exact, rounded]` and `.finder` gives `[rounded]`; duplicates are
    removed (e.g. 402 bytes in `.bytes` mode gives `["402", "402 bajtů"]`; 0 does not repeat).
  - `roundedIsExact`: true for 402 and for 1 000 in binary, false for 4 300 000.
  - `SizeDisplay(rawValue:)` and `SizeUnits(rawValue:)` with an unknown value give nil;
    `SizeFormat()` defaults to `.finder` and `.decimal`.
- [X] T002 Create `Sources/CommanderCore/SizeFormat.swift` (SPDX header) per data-model.md:
  - `public enum SizeDisplay: String, Sendable, CaseIterable { case finder, bytes }`;
  - `public enum SizeUnits: String, Sendable, CaseIterable { case decimal, binary }`;
  - `public struct SizeFormat: Sendable, Equatable` with `display` (default `.finder`), `units`
    (default `.decimal`), `static rounded(_:units:locale:)`, `static exact(_:locale:)`,
    `columnVariants(_:locale:)` and `roundedIsExact(_:locale:)`.
  - `roundedIsExact` compares the digits of the rounded text with the digits of the byte count.
- [X] T003 Remove `CellText.size` from `Sources/CommanderCore/CellText.swift` and its test case
  from `Tests/CommanderCoreTests/CellTextTests.swift`. Moving the case into `SizeFormatTests` is
  covered by T001. `swift test` is green. Commit.

**Checkpoint**: the core formats both modes and both bases.

## Phase 3: User Story 1 + 2 - Sizes like Finder, or exact bytes (Priority: P1) 🎯 MVP

**Goal**: the Size column follows "Size in panels". The exact bytes are in the tooltip and in the
status line.

**Independent Test**: the quickstart's steps 4, 5 and 8.

- [X] T004 [US1] Add `SizeSettings` to `Sources/AxolotlCommander/AppSettings.swift`:
  - `displayKey = "size.display"` and `unitsKey = "size.units"`;
  - `static var saved: SizeFormat`, where an unknown or missing value gives the default.
- [X] T005 [US1] Add the "Size in panels:" picker to `AppearanceSettings` in
  `Sources/AxolotlCommander/SettingsView.swift`, below "Path bar":
  - `@AppStorage(SizeSettings.displayKey)`;
  - the tags `finder` and `bytes`;
  - the labels from contracts/settings-ui.md.
- [X] T006 [US1] In `Sources/AxolotlCommander/PanelViewController.swift`, the `texts(for:item:)`
  Size case uses `sizeFormat.columnVariants(...)`, keeping `<DIR>`, "—" and the empty cells as
  today. `sizeFormat` is a stored property that holds the last applied `SizeSettings.saved`.
- [X] T007 [US1] `FileCellView` gets `exact: String?`. The tooltip is `exact` whenever the shown
  text differs from it, and nil otherwise. `viewFor` passes `SizeFormat.exact` for the Size cells
  that have a byte count. Date cells keep today's "first variant" tooltip.
- [X] T008 [US1] The status line for the item under the cursor, in `updateStatus()`: for a file or
  a calculated folder it shows `"%@ (%@ bytes)"` (rounded, exact), or only the rounded text when
  `roundedIsExact`. The totals stay as they are.
- [X] T009 [US2] Live update: in the `UserDefaults.didChangeNotification` observer, compare
  `SizeSettings.saved` with `sizeFormat`. On a difference:
  - store the new value;
  - `reloadData(forRowIndexes: all, columnIndexes: size column)`;
  - `updateStatus()`.
  The cursor, selection and scroll are kept.
- [X] T010 [US2] `Column.sizeWidth` depends on the mode (research.md R7):
  - `.bytes`: `Format.grouped(999_999_999_999)`, as today;
  - `.finder`: the widest rounded text in bold over sample values in both bases.
  It is used for new columns.
- [X] T011 [US1] Build without warnings, `swift test` green. Commit.

**Checkpoint**: the column follows the mode; the exact bytes are one glance away.

## Phase 4: User Story 3 - Units of 1000 or 1024 (Priority: P1)

**Goal**: every rounded size follows the Units setting.

**Independent Test**: the quickstart's step 6.

- [X] T012 [US3] Add the "Units:" picker to `Sources/AxolotlCommander/SettingsView.swift`:
  - `@AppStorage(SizeSettings.unitsKey)`;
  - the tags `decimal` and `binary`;
  - the labels from contracts/settings-ui.md.
- [X] T013 [US3] `Format.bytes` in `Sources/AxolotlCommander/Support.swift` returns
  `SizeFormat.rounded(value, units: SizeSettings.saved.units, locale: .current)`. This covers the
  volume bar, volume info, operations, Properties, Compare, Disk Usage and the viewer (FR-008).
- [X] T014 [US3] The panel's live update (T009) also reacts to a units change, through the same
  `SizeFormat` comparison. The volume bar is refreshed in the panel the next time it is shown.
- [X] T015 [US3] Build without warnings, `swift test` green. Commit.

## Phase 5: Polish

- [X] T016 [P] Add Czech translations to `Resources/Localizable.xcstrings`:
  - "Size in panels:", "Like Finder (kB, MB, GB)", "In bytes";
  - "Units:", "1000 (like Finder)", "1024 (like Windows)".
- [ ] T017 [P] Add a CHANGELOG "Unreleased" → "Added" entry. It says that sizes are now in Finder
  style by default, and that exact bytes are back with Settings → Appearance → Size in panels.
- [ ] T018 Run the GUI check from quickstart.md, in the test copy only, in a scratchpad test
  folder.
- [ ] T019 Run `scripts/bump-version.sh minor` (0.3.0), then commit, open a PR, merge, tag v0.3.0,
  build and install (ask first if the app is running).

## Dependencies

- T001 and T002 → T003 → Phase 3 → Phase 4 → Phase 5.
- T016 and T017 can be done at any point after T005 and T012.

## Implementation Strategy

MVP = Phase 2 + Phase 3: the Finder-style column with the exact bytes available, and the bytes
mode. Phase 4 adds the base app-wide. Each phase ends green and committed.
