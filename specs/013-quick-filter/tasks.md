# Tasks: Quick Filter

- [ ] T001 Core: `QuickFilter.matches` in `Sources/CommanderCore/QuickFilter.swift`; `PanelModel.quickFilter`,
  `setQuickFilter(_:)`, clearing in `navigate` / `restore`.
- [ ] T002 Core: `quickFilter` and `quickFilterLast` commands (View menu, chords per FR-011) and the Classic
  Commander change in `KeyScheme.swift`.
- [ ] T003 [P] Tests in `Tests/CommanderCoreTests/QuickFilterTests.swift`: matching, model behavior,
  visible-only `selectedItems`, chords. Build, test, commit.
- [ ] T004 [US1] UI: typing state, keys per FR-004 / FR-005, status line, and the spec 011 typing route
  yielding to the filter, in `PanelViewController`.
- [ ] T005 [US2] [US3] UI: `lastQuickFilter`, Quick Filter with Last Text, and quick search turning into
  the filter. Commit.
- [ ] T006 Czech strings, CHANGELOG, quickstart. Commit.
- [ ] T007 GUI check in the test copy (when the maintainer is away); install after asking.
