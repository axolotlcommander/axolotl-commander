# Tasks: Copy Dialog and Replace Question

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md),
[research.md](research.md), [quickstart.md](quickstart.md). Tests are requested by the spec (SC-005).

## Phase 1: Foundational (core)

- [X] T001 [P] `ConflictMarks` and `AutoName` in `Sources/CommanderCore/Operations/ConflictMarks.swift`
  and `Sources/CommanderCore/Operations/AutoName.swift` (rules in data-model.md: "base N.ext", "base N",
  ".zshrc 2", "a.tar 2.gz", 255 UTF-8 bytes); tests in `Tests/CommanderCoreTests/ConflictPolicyTests.swift`.
- [X] T002 `ConflictPolicy` in `Sources/CommanderCore/Operations/ConflictPolicy.swift` (modes, pending
  candidate, `decide`, `choose`); `Conflict.canRename` (default true) in
  `Sources/CommanderCore/Operations/OperationTypes.swift`; tests for overwrite-all-older (newer, older,
  equal, unknown date, folder), rename-all, the next candidate after a taken name, canRename false.
- [X] T003 `RemoteTransfer` in `Sources/CommanderCore/Network/RemoteTransfer.swift`: a rename to a
  taken name asks again with the new destination (upload and download); the server-side move sets
  `canRename: false`; tests in `Tests/CommanderCoreTests/RemoteTransferTests.swift` with the existing
  fake server.

**Checkpoint**: `swift test` green, build without warnings, commit.

## Phase 2: User Stories 1 + 2 — look into both files, marks (P1)

- [X] T004 [US1] [US2] `ConflictSheet` and `ConflictAsker` in
  `Sources/AxolotlCommander/ConflictSheet.swift`: key-first sheet window; title, two info lines with
  "newer"/"larger", hint line; buttons Overwrite, Overwrite All, Skip, Skip All, Cancel (Esc), default
  Overwrite; F3 / ⇧F3 / ⌥F3 open the viewer / Compare Files from `ArchiveScratch` copies (one beep for a
  folder side; errors reported, the question stays).
- [X] T005 [US1] Replace `askConflict` in `Sources/AxolotlCommander/OperationsController.swift` and the
  call sites in `Sources/AxolotlCommander/ArchiveOperations.swift` and
  `Sources/AxolotlCommander/RemoteOperations.swift` with one `ConflictAsker` per operation.

**Checkpoint**: quickstart "Replace question" passes; commit.

## Phase 3: User Story 4 — one item with its name in "To:" (P1)

- [X] T006 [P] [US4] `TransferTarget` in `Sources/CommanderCore/Operations/TransferTarget.swift` (resolve,
  selection ranges, cycle); tests in `Tests/CommanderCoreTests/TransferTargetTests.swift` (existing
  folder, trailing "/", new name, no extension, "a.tar.gz", folder item, emoji names in UTF-16 ranges).
- [X] T007 [US4] `TransferDialog` in `Sources/AxolotlCommander/TransferDialog.swift` (replaces
  `TransferSheet`): "To:", mask only for several items, F5/F6 cycle, OK/Cancel;
  `OperationsController.transfer` fills folder + name for one item and runs with `targetName`.

**Checkpoint**: quickstart "Copy dialog" 1–2 pass; commit.

## Phase 4: User Story 3 — destination menu (P1)

- [X] T008 [P] [US3] `DestinationMenu` in `Sources/CommanderCore/Window/DestinationMenu.swift`;
  `RecentPaths` instance limit in `Sources/CommanderCore/Window/RecentPaths.swift`;
  `transfer.recentDestinations` in `AppSettingsCatalog.notExported`; tests in
  `Tests/CommanderCoreTests/DestinationMenuTests.swift` (order, dedupe, source and Network left out,
  missing folders, empty sections, limit 10).
- [X] T009 [US3] Menu button and ⌥↓ in `TransferDialog`; ⌃D opens the hot paths; choosing keeps the
  name part; `AppSettings.recentDestinations` in `Sources/AxolotlCommander/AppSettings.swift`, added on
  OK.

**Checkpoint**: quickstart "Copy dialog" 3 passes; commit.

## Phase 5: User Story 5 — More… (P2)

- [X] T010 [US5] More… button (before Cancel) with its menu in `ConflictSheet`: Overwrite All Older,
  Rename…, Rename Automatically, Rename All Automatically (rename items disabled when `canRename` is
  false); Rename… sheet with the checks of FR-008.

**Checkpoint**: quickstart "More…" passes; commit.

## Phase 6: Polish

- [X] T011 Czech strings in `Resources/Localizable.xcstrings`; CHANGELOG (Unreleased); spec status.
  Build without warnings, `swift test` green, commit.
- [X] T012 GUI check on the test copy following quickstart.md (scratch folders only); record the result
  here.
  - 2026-10-13, test copy, scratch folders `c21/a` → `c21/b`: one item: "To:" holds folder + name,
    the name selected; F5 and F6 cycle name → extension → folder → whole text; renaming to
    `x-copy.txt` copied under the new name. Replace question: marks ("larger" on the existing,
    "newer" on the new file), hint line, F3 / ⇧F3 open the viewer on the existing / new file,
    ⌥F3 compares them (existing on the left), Esc closes them and the question stays. More… by
    arrows + Return: Rename Automatically → `x 2.txt`; Rename… offers the first free name
    (`x 3.txt`), refuses a taken name with a message and returns to the field, `y` → `y.txt`;
    Esc in the field returns to the question, Esc there cancels without copying. Overwrite All
    Older on p1–p3 + x: older destinations overwritten (p1, x), newer (p2) and equal (p3) skipped,
    no further questions. Several items: "To:" holds the folder, the mask field is shown. ⌥↓
    opens the destination menu; ⌃D opens Hot Paths only (a beep when there are none); choosing
    one keeps the name. Found and fixed during the check: the dialog crashed for one item (a
    width constraint on the hidden mask field), the initial selection was lost, the sheets kept
    empty space, and Rename… offered a name that was already taken.
- [ ] T013 Install for the maintainer, after asking (the installed app may be running).

## Dependencies

- T001 → T002 → T004/T010; T003 before the server parts of T010 are checked.
- T004 → T005. T006 → T007 → T009; T008 → T009.
- Phases 2 and 3–4 are independent of each other; Phase 5 needs Phase 2.

## Parallel opportunities

- T001, T006 and T008 are separate core files with their own tests.

## Implementation strategy

- MVP: Phases 1–2 (the question with looking into files and the marks).
- Then the dialog (3–4), then More… (5).
