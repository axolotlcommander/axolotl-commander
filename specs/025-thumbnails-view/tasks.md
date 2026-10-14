# Tasks: Thumbnails View

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md),
[research.md](research.md), [quickstart.md](quickstart.md). Tests are requested by the spec (SC-005).

## Phase 1: Foundational (core)

- [X] T001 `PanelGrid` and `MoveKey` in `Sources/CommanderCore/Window/PanelGrid.swift` (NEW, SPDX header) with
  the table of data-model.md; tests first in `Tests/CommanderCoreTests/PanelGridTests.swift` (NEW): every key
  for `.list`, `.columns`, `.rows`, clamping at both ends, ↓ above a shorter last row lands on the last item,
  ↑ from the first row on the first item, count 1.
- [X] T002 `GridGeometry.indices(in:)` in the same file for both orders (rectangles over several lines, a
  rectangle only in a gap, beyond the last item, negative origin); tests in `PanelGridTests.swift`.
- [X] T003 [P] `PanelViewMode.thumbnails` and a tolerant decode of `leftMode` / `rightMode` (unknown value →
  `detailed`, the rest of the layout kept) in `Sources/CommanderCore/Window/WindowLayout.swift`; tests for the
  round trip and the fallback in `Tests/CommanderCoreTests/ThumbnailTests.swift` (NEW).
- [X] T004 [P] `ThumbnailSize` (points 64/128/256, `larger`, `smaller`, key `panel.thumbnailSize`, default
  `medium`, reading from `UserDefaults`), `ThumbnailKey`, `ThumbnailPolicy` in
  `Sources/CommanderCore/Thumbnails.swift` (NEW); `PreferenceSpec` in
  `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`; tests in `ThumbnailTests.swift`.
- [X] T005 [P] Commands `viewModeThumbnails` ("Thumbnails", ⌃⌥3), `thumbnailsLarger` ("Larger Thumbnails",
  ⌘+ ⌘=) and `thumbnailsSmaller` ("Smaller Thumbnails", ⌘−) in the View menu in
  `Sources/CommanderCore/Command.swift`; Classic Commander adds ⌃⇧F1 to `viewModeThumbnails` in
  `Sources/CommanderCore/KeyScheme.swift`; a test that the chords do not clash in the panel scope.

**Checkpoint**: build without warnings, `swift test` green, commit.

## Phase 2: User Story 1 — the view and the keyboard (P1)

**Goal**: ⌃⌥3 shows a grid of cells with icons and names that the keyboard drives like Brief.
**Independent test**: quickstart steps 1–3, 6, 9 (icons are enough at this point).

- [ ] T006 [US1] Move the Brief grid's mouse, drag source and drop target code into a base class
  `PanelGridView` in `Sources/AxolotlCommander/PanelGridView.swift` (NEW): `items(in:)` and the name-zone
  test become overridable, Brief's arithmetic moves to `GridGeometry` (T002); `BriefGridView` in
  `Sources/AxolotlCommander/BriefView.swift` subclasses it with no change in behavior.
- [ ] T007 [US1] `ThumbnailGridView` (vertical `NSCollectionViewFlowLayout`), `ThumbnailCellView` (image in
  a square, label of at most two centered lines cut with "…", tooltip, cursor and marked drawing like Brief,
  research R8) and `ThumbnailItem` in `Sources/AxolotlCommander/ThumbnailView.swift` (NEW, SPDX header), with
  a `PanelViewController` data source extension showing the type icon at the cell size.
- [ ] T008 [US1] `PanelViewController.swift`: the third scroll view in `lists`, `listView`,
  `viewModeChanged()` for three views keeping cursor, marks and focus, `modelChanged()` / `marksChanged()`
  / `updateActiveAppearance()` for the new view (reload bookkeeping like Brief's, cursor moves redraw only
  visible cells), `viewModeThumbnails` in the handled commands and `perform`.
- [ ] T009 [US1] `handleMovement` through `PanelGrid` for all three views (each view gives its
  arrangement: table page rows, Brief rows and columns, thumbnail columns and visible rows); the ⇧ marking
  path unchanged.
- [ ] T010 [US1] The View → Thumbnails checkmark in `Sources/AxolotlCommander/MainWindowController.swift`;
  the layout saves and restores the new mode.
- [ ] T011 [US1] GUI check: quickstart steps 1–3, 6, 9 on the test copy in a scratch folder.

**Checkpoint**: build, tests, commit.

## Phase 3: User Story 2 — previews (P1)

**Goal**: cells show the system's previews, fast and smooth in large folders.
**Independent test**: quickstart steps 1 and 7.

- [X] T012 [US2] Tests first in `ThumbnailTests.swift`: `ThumbnailCache` (limit by cost, least recently used
  dropped first, a read makes an entry recent, keys differ by date and size) and `ThumbnailQueue` (at most
  `limit` running, visible keys before margin keys, keys no longer wanted are cancelled, `finished` starts
  the next).
- [X] T013 [US2] `ThumbnailCache` and `ThumbnailQueue` in `Sources/CommanderCore/Thumbnails.swift` until T012
  passes.
- [ ] T014 [US2] `ThumbnailLoader` in `Sources/AxolotlCommander/ThumbnailLoader.swift` (NEW): requests with
  `QLThumbnailGenerator` (`.icon` and `.thumbnail`, the cell size and the backing scale), cancels by the
  queue's answers, stores images in `ThumbnailCache<NSImage>` (256 MB, cost = pixels × 4), updates the cell
  of a finished key if it is visible; errors leave the icon.
- [ ] T015 [US2] Wire the loader into the thumbnail view: the wanted keys (visible cells plus one screen of
  margin) after reloads, scrolling (bounds change of the clip view), resizing and size changes; previews only
  when `ThumbnailPolicy` allows them for the panel and the item (FR-015).
- [ ] T016 [US2] GUI check: quickstart steps 1, 7 and 8; `ls -la` of the scratch folders before and after.

**Checkpoint**: build, tests, commit.

## Phase 4: User Story 3 — sizes (P2)

**Goal**: three sizes from Settings, ⌘+ / ⌘−, ⌘ + wheel and pinch.
**Independent test**: quickstart step 4.

- [ ] T017 [US3] `thumbnailsLarger` / `thumbnailsSmaller` in `PanelViewController.swift`: enabled only in a
  focused Thumbnails view, write the setting; every panel re-lays out its Thumbnails view on the
  `UserDefaults` change and keeps the cursor visible.
- [ ] T018 [US3] ⌘ + scroll wheel (accumulated delta) and `magnify(with:)` (a step per 0.25) in
  `ThumbnailGridView`.
- [ ] T019 [US3] "Thumbnail size" picker (Small, Medium, Large) in the Panels section of
  `Sources/AxolotlCommander/SettingsView.swift`.
- [ ] T020 [US3] GUI check: quickstart step 4 and the size after a restart (step 10).

**Checkpoint**: build, tests, commit.

## Phase 5: User Story 4 — mouse (P1)

**Goal**: spec 024 rules in the new view.
**Independent test**: quickstart step 5.

- [ ] T021 [US4] Name zone of `ThumbnailCellView` (the image's drawn aspect-fit rectangle, at least 4 points,
  plus the label's text lines) and `items(in:)` from `GridGeometry` (`.rowsFirst`) in `ThumbnailGridView`;
  the rubber band overlay and autoscroll from spec 024 in the vertical direction.
- [ ] T022 [US4] GUI check: quickstart step 5 (scratch folder only, the drop into its subfolder).

**Checkpoint**: build, tests, commit.

## Phase 6: User Story 5 — places without previews (P2)

- [ ] T023 [US5] Check archives, server connections, Network, branch view and search results in the
  Thumbnails view (type icons, no request made outside `ThumbnailPolicy`); a test that the policy refuses
  archive member URLs in `ThumbnailTests.swift`.

## Phase 7: Polish

- [ ] T024 Czech strings in `Resources/Localizable.xcstrings` (Thumbnails, Larger/Smaller Thumbnails,
  Thumbnail size, Small/Medium/Large).
- [ ] T025 `CHANGELOG.md` entry under 0.6.0 (Added: Thumbnails view, sizes); no version bump (release 0.6.0
  collects specs).
- [ ] T026 Full quickstart run on the test copy; spec Status → Implemented; `docs/STATE.md` updated.

## Dependencies

- T001–T005 → everything. T006 before T007 (the base class), T007 → T008 → T009/T010.
- US2 (T012–T016) needs US1; US3 needs US1; US4 needs T006 and T007; US5 needs US2.
- Core tests before their implementation (T001, T002, T012→T013).

## Parallel opportunities

- T003, T004, T005 next to T001/T002.
- After US1: US3 and US4 next to US2.

## Implementation strategy

MVP = Phase 1 + US1: the view with icons and the keyboard. Then previews, sizes, the mouse, the sources
without previews. One pull request on top of spec 024; release 0.6.0 when the maintainer says so.
