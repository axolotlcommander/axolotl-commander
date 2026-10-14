# Tasks: Tab Locking and Tab Menu

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md),
[quickstart.md](quickstart.md)

## Phase 1: Core (blocking)

- [X] T001 `Sources/CommanderCore/Window/TabLock.swift` (NEW): `TabLock` (`mode` `.locked` / `.allowsChanges`,
  `folder`, `cursorName`), Codable as in data-model.md; `returning(_ state:)` (R3).
- [X] T002 `Sources/CommanderCore/Window/PanelState.swift`: `lock: TabLock?`, coding key `lock`, missing → nil.
- [X] T003 `Sources/CommanderCore/Window/TabList.swift`: `updateCurrent` keeps the lock; `setLock(_:at:)`,
  `split(keeping:opened:)`, `returnCurrentToLock()`, `returnAllToLocks()`, `closeOthers(keeping:)`,
  `closeToTheRight(of:)` (unlocked only, return the removed), `duplicate(at:)`, `unlock(where:)`, `redirect`
  clears locks, `relock(at:to:)` (R1–R7).
- [X] T004 `Tests/CommanderCoreTests/TabLockTests.swift` (NEW): lock kept by `updateCurrent`; split places the
  new tab after the locked one and activates it; return on activation (cursor, results cleared, history
  kept); close others / to the right keep locked tabs; duplicate unlocked; unlock and redirect drop locks;
  relock; encoding round trip; old layout JSON without `lock` decodes unlocked.

**Checkpoint**: `swift test` green, commit.

## Phase 2: US1 + US2 — lock, split, return (P1)

- [X] T005 [US1] `Sources/AxolotlCommander/PanelTabs.swift`: the split in `tabsChanged()` for a `.locked` tab
  (cursor of the locked tab from the model's last Back entry); `setLock(mode:at:)` toggling (R2).
- [X] T006 [US2] `PanelTabs.swift`: `returnCurrentToLock()` before restoring on `switchTab`, `closeTab` of the
  active tab and reopen; `restoreTab` stores the tab (and `relock`s a missing locked folder) before the strip
  updates (R3, R7).
- [X] T007 [US1] `Sources/CommanderCore/Command.swift`: `lockTab` ("Lock Tab"), `lockTabAllowingChanges`
  ("Lock Tab, Allow Folder Changes"), `duplicateTab`, `copyTabToOtherPanel`, `closeTabsToRight` in the Go
  menu next to the tab commands, no keys; `PanelViewController` `canPerform` / `perform`;
  `MainWindowController` checkmarks and Copy Tab to Other Panel.

## Phase 3: US3 — marks (P1)

- [X] T008 [US3] `Sources/AxolotlCommander/TabStrip.swift`: `Item` (title, lock, tooltip), `show(_:active:
  canReopen:)`, hover tracking and the left slot rule (R8); callers updated (`PanelTabs`,
  `PanelViewController.leave`, `ServerConnectionsUI`).
- [X] T009 [US3] Tab list (`showTabList`): the lock symbol on locked tabs.

## Phase 4: US4 + US5 — persistence details and tab menu (P2)

- [X] T010 [US5] `TabStrip.swift` context menu: the full list with enabled states; callbacks to the panel.
- [X] T011 [US4] Close Other Tabs / Close Tabs to the Right keep locked tabs (panel uses the core
  operations, pushes the removed ones to the closed tabs); eject and disconnect unlock first (R6);
  `MainWindowController.loadLayout` → `returnAllToLocks()`.

## Phase 5: Polish

- [ ] T012 Czech strings in `Resources/Localizable.xcstrings`; no menu item or tooltip cut.
- [ ] T013 `CHANGELOG.md` and `CHANGELOG.cs.md` entries under 0.6.0.
- [ ] T014 GUI check: quickstart steps 1–10 on the test copy; spec Status → Implemented; `docs/STATE.md`.

## Dependencies

T001–T003 before everything; T004 with them. T005 before T006. T008 before T009–T010. T012–T014 last.
MVP: Phases 1–3.
