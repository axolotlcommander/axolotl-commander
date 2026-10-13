# Tasks: Tabs from the Keyboard

**Input**: [spec.md](spec.md), [plan.md](plan.md)

## Phase 1: Foundational (core)

- [X] T001 Add `TabList.open(_:activate:)` and `ClosedTabs` to
  `Sources/CommanderCore/Window/TabList.swift`. `ClosedTabs` has `push` (newest first, at most 10),
  `popNewest`, `remove(at:)`, `items` and `isEmpty`.
- [X] T002 Add `PanelModel.stateEnteringCursor()` to `Sources/CommanderCore/PanelModel.swift`.
- [X] T003 Add seven commands with chords and menus per FR-012 to `Sources/CommanderCore/Command.swift`:
  - `openInNewTab`, `openInBackgroundTab`, `openInNewTabOtherPanel`;
  - `reopenClosedTab`, `closeOtherTabs`, `tabList`;
  - `swapPanelsWithTabs`.
  Add the Classic Commander change to `Sources/CommanderCore/KeyScheme.swift`.
- [X] T004 [P] Add tests for T001–T003 to the existing test files and a new `TabListTests` section.
  Build, test, commit.

## Phase 2: User Story 1 — Open in a new tab (P1)

- [X] T005 [US1] In `Sources/AxolotlCommander/PanelTabs.swift`, add `openCursorInNewTab(activate:)` and
  `openTab(_:activate:)`.
- [X] T006 [US1] Wire the panel commands and their validation in `PanelViewController`. Open in New Tab
  of Other Panel goes through `MainWindowController`: un-maximize, the other panel's `openTab`, and the
  focus stays. Commit.

## Phase 3: User Story 2 — Closed tabs and the tab list (P1)

- [X] T007 [US2] Record closed tabs in `closeTab` / `closeOtherTabs`; add `reopenClosedTab()` and its
  validation.
- [X] T008 [US2] Add the Tab List… menu, popped up over the path bar: open tabs (the active one
  checked, with a path tooltip), then a "Recently Closed" section. Commit.

## Phase 4: User Story 3 — Close other tabs, swap with all tabs (P2)

- [X] T009 [US3] Add the `closeOtherTabs` command (the current tab is kept) and its validation.
- [X] T010 [US3] Add `swapPanelsWithTabs` in `MainWindowController`. Commit.

## Phase 5: Polish

- [X] T011 Add the Czech strings, a CHANGELOG entry and the quickstart (GUI) steps.
- [X] T012 Run the GUI check in the test copy when the maintainer is away (2026-10-13, all steps passed).
- [X] T013 Install for the maintainer, after asking.
