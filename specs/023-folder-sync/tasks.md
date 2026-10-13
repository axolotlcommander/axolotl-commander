# Tasks: Synchronize Folders

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md),
[research.md](research.md), [quickstart.md](quickstart.md). Tests are requested by the spec (SC-006).

## Phase 1: Foundational (core)

- [X] T001 [P] `SyncOptions` / `SyncDirection` (Codable, every field `decodeIfPresent`, defaults from
  data-model.md) and the model types `SyncSide`, `SyncState`, `SyncAction`, `SyncItem`, `SyncComparison`
  in `Sources/CommanderCore/Sync/{SyncOptions,SyncModel}.swift`; decoding test with missing fields in
  `Tests/CommanderCoreTests/SyncRulesTests.swift`.
- [X] T002 [P] `SyncGuard.check(left:right:)` (`.same`, `.nested`) on resolved standardized paths by
  components in `Sources/CommanderCore/Sync/SyncGuard.swift`; tests: same, nested both ways, nested
  through a symbolic link, "/a" vs "/ab" not nested.
- [X] T003 `SyncScanner.compare` in `Sources/CommanderCore/Sync/SyncScanner.swift` (research R1–R5); tests
  in `Tests/CommanderCoreTests/SyncScannerTests.swift` on `TestSandbox` folders: only left/right, equal
  within 2 s, exactly one hour ignored or not, newer left/right, size difference (≠ without a newer side),
  content difference only with content on (and not read when sizes differ), file vs folder, links by
  target never followed, packages walked, NFC/NFD names match, case on case-insensitive rules, name clash
  error row, ignore masks at depth, hidden on/off, one-sided folder one row with total size and file
  count, unreadable folder error row, subfolders off, cancellation.
- [X] T004 `SyncRules` (default actions per direction and delete option; `possible`; `set` returning the
  items it could not change; `toggleExcluded` keeping the action) in
  `Sources/CommanderCore/Sync/SyncRules.swift`; tests for every row of the FR-011 rules and the
  data-model action table.
- [X] T005 `SyncPlan` (copies, replacements, deletions per side, files and bytes, summary texts) and
  `SyncCheck.unchanged` in `Sources/CommanderCore/Sync/SyncPlan.swift`; tests: counts and bytes with
  excluded and `none` rows, one-sided folder bytes, replacement counted as a deletion, changed size /
  date / appeared / vanished / link target.
- [X] T006 `SyncRunner.run` in `Sources/CommanderCore/Sync/SyncRunner.swift` (research R6, R7); tests in
  `Tests/CommanderCoreTests/SyncRunnerTests.swift`: copies both ways keep dates (comparing again finds
  no differences), overwrite only where planned, an unexpected target is skipped and reported, a
  changed source is skipped, a replacement trashes the target first, deletions go to the Trash (a temp
  folder on the boot volume; the test removes its own trashed items), a volume without a Trash is
  reported and nothing is deleted, cancellation leaves deletions undone.

**Checkpoint**: `swift test` green, build without warnings, commit.

## Phase 2: User Story 1 — compare and copy (P1)

- [X] T007 [US1] `Command.synchronizeFolders` ("Synchronize Folders…", `.commands`, `f(10, [o, s])`) in
  `Sources/CommanderCore/Command.swift`; enablement and perform in `MainWindowController`
  (`canPerformHere` / `performHere`: both panels plain local folders); `AppSettings.sync` (`syncOptions`)
  and the `SettingsCatalog.app` entry.
- [X] T008 [US1] `SyncSheet` (SwiftUI) in `Sources/AxolotlCommander/Sync/SyncSheet.swift`: folders,
  criteria, masks, direction, delete toggle disabled for Both ways; Return compares, Esc cancels; the
  `SyncGuard` messages.
- [X] T009 [US1] `SyncWindowController` in `Sources/AxolotlCommander/Sync/SyncWindowController.swift`:
  one per main window, header, table columns, in-window comparing progress with Cancel, summary line,
  Compare Again / Synchronize, "folders are in sync" state, `volumeUser` and the `VolumeEjector.users()`
  case.
- [X] T010 [US1] Run: confirmation with the plan summary; `OperationsController.perform(_:in:)`;
  `SyncRunner` with `OperationState(title:urls:)`; report of skipped and failed items; compare again;
  panels refresh.

**Checkpoint**: quickstart checks 1–3 and 8 pass; commit.

## Phase 3: User Story 2 — per-item control (P1)

- [X] T011 [US2] `SyncTableView` keys (Space, ←, →, =, Delete, F3 → `CompareWindowController.show`,
  Return, ⌘R before the menu's Refresh, Esc), click on the action cell cycles, context menu, filter
  buttons over an index list in `Sources/AxolotlCommander/Sync/`.

**Checkpoint**: quickstart checks 6, 7 and 11 pass; commit.

## Phase 4: User Story 3 — one way with deleting (P2) and User Story 4 — criteria (P2)

- [X] T012 [US3] [US4] ✕ display, the Trash line in the confirmation, the run's Trash report; criteria and
  masks end to end (they are in the core already).

**Checkpoint**: quickstart checks 4, 5, 9 and 10 pass; commit.

## Phase 5: Polish

- [ ] T013 Czech strings complete; CHANGELOG (Unreleased, Added); spec status. Build without warnings,
  `swift test` green, commit.
- [ ] T014 GUI check on the test copy following quickstart.md (scratch folders only); record the result
  here.

## Dependencies

- T001 → T003 → T004 → T005 → T006; T002 is independent.
- T006 → T010; T007 → T008 → T009 → T010 → T011 → T012.

## Parallel opportunities

- T001 and T002; the UI tasks T007–T008 can start once T001 exists.

## Implementation strategy

- MVP: Phases 1–2 (compare and copy with the confirmation). Then per-item control, then deleting and the
  criteria end to end.
