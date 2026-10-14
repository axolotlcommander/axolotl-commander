# Tasks: Mouse Selection

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md),
[research.md](research.md), [quickstart.md](quickstart.md). Tests are requested by the spec (SC-005).

## Phase 1: Foundational (core)

- [X] T001 In `Sources/CommanderCore/PanelModel.swift` make `selectable(_:)`, `set(_:_:)` and the
  `previousSelection` setter internal (no behavior change); add the `MouseSelectionMode`, `MouseModifiers`
  and `RubberBand` types (data-model.md) in `Sources/CommanderCore/PanelMouse.swift`.
- [X] T002 [P] `PanelBehavior.rightButtonMarks` (key constant `rightButtonKey` = `panel.rightButtonMarks`, default `false`) in
  `Sources/CommanderCore/PanelBehavior.swift` and its `PreferenceSpec` in
  `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`; test the default and reading from
  `UserDefaults` in `Tests/CommanderCoreTests/PanelMouseTests.swift`.

**Checkpoint**: build without warnings, `swift test` green, commit.

## Phase 2: User Story 1 — modifier clicks (P1)

**Goal**: plain, ⌃/⌘, ⇧ and ⌃⇧/⌘⇧ clicks mark as in the spec in both views.
**Independent test**: quickstart steps 1–4, 6–8.

- [X] T003 [US1] Tests first in `Tests/CommanderCoreTests/PanelMouseTests.swift` (fixture: temp folder with
  a…j and one folder, removed after): plain press on unmarked clears all (also keyboard marks) and moves
  the cursor; plain press on marked keeps the marks and allows drag, release leaves only it; ⇧ new range
  from the cursor (both directions); ⇧ on the cursor item marks just it; ⌃⇧ adds a range; ⌃ toggles and
  keeps others; ".." never marked (range from "..", toggle on ".."); press on empty space clears, cursor
  stays; ⌃W restores marks removed by a plain click, by ⇧+click and by "only this one"; modifier presses
  return no-drag; in `.rightButtonMarks` a plain press keeps the marks.
- [X] T004 [US1] Implement `mousePressed(at:modifiers:mode:) -> Bool`, `mouseReleased(at:)` and
  `mousePressedOnEmptySpace(mode:)` in `Sources/CommanderCore/PanelMouse.swift` (FR-001 to FR-005,
  FR-007, FR-018 to FR-020) until T003 passes.
- [X] T005 [US1] `marksChanged()` in `Sources/AxolotlCommander/PanelViewController.swift`: redraw visible
  rows (Detailed) or items (Brief), sync the table's selected row to the cursor, update the info line
  (research R8).
- [X] T006 [US1] Name-zone hit tests in `Sources/AxolotlCommander/PanelMouseTracking.swift` (NEW, SPDX
  header): for a `FileCellView` row (icon frame plus the label cut to its text width) and for a `BriefItem`;
  `MouseModifiers(event:)` from `NSEvent.modifierFlags` (⌃ or ⌘ → toggle, ⇧ → range).
- [X] T007 [US1] `PanelTableView.mouseDown` decision tree in
  `Sources/AxolotlCommander/PanelViewController.swift` (research R3): make the table first responder;
  empty space → empty-space rule; name zone with modifiers → press rule only, no `super`; name zone plain →
  press rule, `super.mouseDown`, then the release rule when no drag session began (flag set in
  `draggingSession(_:willBeginAt:)`); a row outside the name zone → press and release rules on that row
  (rubber band comes in T011), double click opens; `menu(for:)` returns nil for a left mouse down (⌃-click,
  research R5); call `marksChanged()` after each rule.
- [X] T008 [US1] The same tree in `BriefGridView.mouseDown` / `mouseDragged` / `mouseUp` in
  `Sources/AxolotlCommander/BriefView.swift` (research R4): its own drag start only after a plain press on
  the name zone; `menu(for:)` nil for a left mouse down; `onClick` replaced by callbacks for the rules.
- [X] T009 [US1] Right click in the default mode unchanged (FR-008): check `contextMenu(at:)` in
  `Sources/AxolotlCommander/PanelContextMenu.swift` still clears marks on an unmarked item and keeps them
  on a marked one after T007/T008.
- [ ] T010 [US1] GUI check on the test copy (quickstart steps 1–4, 6–8 in a scratch folder only); if a
  ⌃-click still opens a menu, apply the `CommanderApplication.sendEvent` fallback (research R5) in
  `Sources/AxolotlCommander/main.swift`.

**Checkpoint**: build, tests, commit.

## Phase 3: User Story 2 — rubber band (P2)

**Goal**: a rectangle from empty space replaces, adds or toggles marks, with autoscroll.
**Independent test**: quickstart step 5 in both views.

- [X] T011 [US2] Tests in `Tests/CommanderCoreTests/PanelMouseTests.swift`: plain band replaces (start
  marks cleared, stored for ⌃W); ⇧ adds and items leaving the band get their start state back; ⌃ toggles
  against the start state; shrinking the band undoes; ".." in the covered set stays unmarked; 100 000
  covered indices applied in one step under 0.1 s (SC-003, on a generated in-memory listing if the model
  allows, else a temp folder with fewer files and a timing on the update only).
- [X] T012 [US2] `beginRubberBand(modifiers:)` and `updateRubberBand(_:covering:)` (incremental, research
  R6) in `Sources/CommanderCore/PanelMouse.swift` until T011 passes.
- [X] T013 [US2] `RubberBandView` overlay and the rubber band tracking loop with periodic events and
  `autoscroll(with:)` in `Sources/AxolotlCommander/PanelMouseTracking.swift`; covered rows from
  `rows(in:)` for the table, covered items by grid arithmetic for Brief (research R4).
- [X] T014 [US2] Wire the band into `PanelTableView.mouseDown` (empty space and a row outside the name zone,
  more than 3 points of movement) and `BriefGridView.mouseDown` (outside an item's name zone and after the
  last item); a click without movement keeps the US1 rules (FR-013).
- [ ] T015 [US2] GUI check: quickstart step 5 and step 8 for the band, including past the bottom edge and in
  a 2 000-file scratch folder for smoothness.

**Checkpoint**: build, tests, commit.

## Phase 4: User Story 3 — Norton-style right button (P2)

**Goal**: with the setting on, right click toggles, right drag paints, long press opens the menu, left
click keeps the marks.
**Independent test**: quickstart step 9.

- [X] T016 [US3] Tests in `Tests/CommanderCoreTests/PanelMouseTests.swift`: right click toggles and moves the
  cursor; right drag from an unmarked item marks every item passed over, from a marked item unmarks; a
  range filled between non-adjacent rows; ".." skipped.
- [X] T017 [US3] `toggleMarkByRightClick(at:)`, `beginRightDrag(at:) -> Bool`, `rightDrag(from:to:marking:)` in
  `Sources/CommanderCore/PanelMouse.swift` until T016 passes.
- [X] T018 [US3] `contextMenu(at:)` in `Sources/AxolotlCommander/PanelContextMenu.swift`: with the setting
  on the marks stay, the cursor moves, the menu acts on the marked items or the pressed one
  (Clarifications 2026-10-14).
- [X] T019 [US3] Right-button tracking in `Sources/AxolotlCommander/PanelMouseTracking.swift` (research R7):
  ⌃ → menu at once; wait up to 0.5 s for a release (toggle), a drag over 3 points (paint with autoscroll)
  or the timeout (menu, marks kept); `rightMouseDown` overrides in `PanelTableView` and
  `BriefGridView` call it only when `PanelBehavior(defaults: .standard).rightButtonMarks` is on, else
  today's path.
- [X] T020 [US3] Settings toggle "Right mouse button marks (Norton Commander style)" with a caption in the
  Panels section of `Sources/AxolotlCommander/SettingsView.swift` (`@AppStorage(PanelBehavior.rightButtonKey)`).
- [ ] T021 [US3] GUI check: quickstart step 9 (on and off, restart keeps it).

**Checkpoint**: build, tests, commit.

## Phase 5: Polish

- [X] T022 Czech translations for the new strings in `Resources/Localizable.xcstrings`.
- [ ] T023 `CHANGELOG.md` "Unreleased" entry (Added: mouse marking, rubber band, right-button setting) and
  `scripts/bump-version.sh minor` in the pull request.
- [ ] T024 Full quickstart run on the test copy in both views; spec Status → Implemented; `docs/STATE.md`
  updated.

## Dependencies

- T001 → everything; T002 → T019, T020.
- US1 (T003–T010) before US2 (T014 builds on the T007/T008 trees) and US3 (T019 builds on them).
- US2 and US3 are independent of each other once US1 is done.
- Core tests before their implementation (T003→T004, T011→T012, T016→T017).

## Parallel opportunities

- T002 next to T001's types.
- T005 and T006 next to T003/T004.
- After US1: US2 (T011–T015) and US3 (T016–T021) can run side by side; T022 at the end.

## Implementation strategy

MVP = Phase 1 + US1: the mouse can mark with modifier clicks and a plain click starts over. Then the
rubber band, then the Norton setting; one pull request for the whole spec with the minor version bump.
