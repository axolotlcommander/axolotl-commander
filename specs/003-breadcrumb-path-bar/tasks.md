# Tasks: Clickable Breadcrumb Path Bar

**Input**: Design documents from `/specs/003-breadcrumb-path-bar/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/path-bar.md, quickstart.md

**Tests**: Unit tests for the core (trail, fit) are part of the plan (constitution IV); GUI checks
follow quickstart.md in the test copy only.

**Format**: `[ID] [P?] [Story] Description` — [P] = can run in parallel (different files).

## Phase 1: Setup

- [ ] T001 Add `Command.editPath` ("Edit Path", Go menu, ⌘L) after `changeDirectory` in Sources/CommanderCore/Command.swift

## Phase 2: Foundational (core, blocks all stories)

- [ ] T002 [P] Create `PathSegment`, `BreadcrumbFit` and `Breadcrumbs.trail(location:results:archive:remote:volume:home:)` for local locations (volume prefix rule R1, home kind) in Sources/CommanderCore/Window/Breadcrumbs.swift
- [ ] T003 Add `Breadcrumbs.focusName(after:in:)` and `Breadcrumbs.fit(widths:available:ellipsis:separator:)` (R4: keep first and last, add from the end, one hidden range after index 0, `lastWidth` when even first + "…" + last does not fit) in Sources/CommanderCore/Window/Breadcrumbs.swift
- [ ] T004 [P] Tests for local trails (boot volume, `/Volumes/X/...`, volume root alone, home kind, firmlinked path not under the volume root, names with "›") and for `focusName` in Tests/CommanderCoreTests/BreadcrumbsTests.swift
- [ ] T005 Tests for `fit` (all fit, collapse from the middle, keep neighbors of the last, two segments, one segment, truncate last only, invariants) in Tests/CommanderCoreTests/BreadcrumbsTests.swift

**Checkpoint**: `swift test` green; trail and fit usable from the UI.

## Phase 3: User Story 1 — Jump to a parent folder with one click (P1) 🎯 MVP

**Goal**: Breadcrumbs replace the path field by default; click navigates with the cursor on the child.

**Independent Test**: quickstart Q1–Q4, Q14 (style switch), Q15.

- [ ] T006 [US1] Create `PathBar` (hosts the existing field and a breadcrumb row; draws the active/neutral background; `show(trail:)`; mode breadcrumbs/text; icons on/off) in Sources/AxolotlCommander/PathBar.swift
- [ ] T007 [US1] Segment views in Sources/AxolotlCommander/PathBar.swift: icon (R6) + name, "›" separators, hover highlight via tracking area, never first responder, click callback, accessibility button/group (R12)
- [ ] T008 [US1] Replace `pathField` in the panel stack with `PathBar`, compute the trail on every model change (volume root/name from resource values, home folder), click → `router?.activate(side)` + `go(to:focusing:)`, current segment → activate only, in Sources/AxolotlCommander/PanelViewController.swift
- [ ] T009 [US1] Anchor the volume menu and hot paths menu at the path bar instead of the field in Sources/AxolotlCommander/PanelViewController.swift and Sources/AxolotlCommander/PanelTabs.swift
- [ ] T010 [US1] Settings → Appearance: "Path bar" picker (Breadcrumbs / Text field) and "Show icons in path bar" toggle (`pathBar.style`, `pathBar.showIcons`), panels re-apply on `UserDefaults.didChangeNotification`, in Sources/AxolotlCommander/SettingsView.swift and Sources/AxolotlCommander/PanelViewController.swift

**Checkpoint**: breadcrumbs work for local folders; text mode identical to before.

## Phase 4: User Story 2 — Type a path when needed (P1)

**Goal**: ⌘L or a click right of the path opens the field; Enter/Esc/focus loss return to breadcrumbs.

**Independent Test**: quickstart Q5–Q8.

- [ ] T011 [US2] `PathBar.beginEditing()` / `endEditing()` (R7), click in the empty area right of the last segment begins editing, in Sources/AxolotlCommander/PathBar.swift
- [ ] T012 [US2] Handle `.editPath` (both modes), `controlTextDidEndEditing` → breadcrumbs, Enter in breadcrumb mode returns focus to the list also after an error, Esc as today, in Sources/AxolotlCommander/PanelViewController.swift

**Checkpoint**: US1 + US2 = P1 complete; commit.

## Phase 5: User Story 3 — More actions on a segment (P2)

**Independent Test**: quickstart Q9–Q10.

- [ ] T013 [US3] Refactor `setHotPath(_:)` into `setHotPath(_:path:)` (current folder by default) in Sources/AxolotlCommander/PanelTabs.swift
- [ ] T014 [US3] Segment context menu (Open in Other Panel, Open in New Tab, Copy Path, Set as Hot Path ▸ slots, Show in Finder; disabled per contract) and ⌘-click = new tab, in Sources/AxolotlCommander/PathBar.swift and Sources/AxolotlCommander/PanelViewController.swift

## Phase 6: User Story 4 — Long paths stay readable (P2)

**Independent Test**: quickstart Q11.

- [ ] T015 [US4] Lay out the row with `Breadcrumbs.fit` on every width change: "…" segment with a menu of hidden folders (icons), last segment truncated only when `lastWidth` is set, in Sources/AxolotlCommander/PathBar.swift

## Phase 7: User Story 5 — Archives, servers and search results (P2)

**Independent Test**: quickstart Q12–Q13; remote by unit tests.

- [ ] T016 [P] [US5] Trails for archives (`archive`, `archiveFolder` kinds), remote locations (server segment, empty path) and results (non-clickable title + root trail) in Sources/CommanderCore/Window/Breadcrumbs.swift
- [ ] T017 [P] [US5] Tests for archive, remote and results trails and `focusName` across the archive boundary in Tests/CommanderCoreTests/BreadcrumbsTests.swift
- [ ] T018 [US5] Icons and menu enabling for the new kinds; results title drawn as static text; in Sources/AxolotlCommander/PathBar.swift

## Phase 8: Polish & Cross-Cutting

- [ ] T019 [P] Czech translations for all new strings in Resources/Localizable.xcstrings (test that each new key has a cs entry in Tests/CommanderCoreTests/BreadcrumbsTests.swift)
- [ ] T020 [P] README (path bar paragraph) and CHANGELOG (Unreleased → Added)
- [ ] T021 GUI verification per quickstart.md Q1–Q15 in the test copy; record results at the end of this file
- [ ] T022 Mark spec Status Implemented, all tasks [X]; merge to main; `scripts/bundle.sh release` + `scripts/install.sh` (ask first if the app runs)

## Dependencies

- T001 → T012. T002 → T003 → T004/T005. Phase 2 → all stories.
- US1 (T006–T010) → US2 (T011–T012) → US3, US4, US5 (independent of each other; all touch
  PathBar.swift, so run them one after another).
- Polish after the stories.

## Parallel Opportunities

- T002 with T001; T004 with T003 (after the API exists); T016/T017 together; T019 with T020.

## Implementation Strategy

MVP = Phases 1–4 (US1 + US2): the default bar navigates and typing a path still works. Then US3,
US4, US5, each committed on its own, then polish and GUI verification.
