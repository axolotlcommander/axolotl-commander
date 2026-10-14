# Research: Tab Locking and Tab Menu

Sources for the usual behavior: the reference program's help on panel tabs (New, Duplicate, Close, Close
Other, Close Tabs to the Right; no locking) and public descriptions of other two-panel managers (two lock
modes, a mark in the strip, "close all / other tabs" keeping locked tabs, an option to confirm closing).

## R1 — Where the lock lives

- **Decision**: `PanelState.lock: TabLock?` with `mode` (`.locked`, `.allowsChanges`), `folder` (URL) and
  `cursorName`. It is encoded with the tab (new key `lock`); `decodeIfPresent` keeps old layouts working.
  `TabList.updateCurrent(_:)` copies the stored tab's lock onto the snapshot it receives, because the panel
  model (which makes the snapshots) knows nothing about locks.
- **Rationale**: The lock travels with the tab everywhere tabs already travel: the saved layout, closed tabs
  (Reopen Closed Tab), Swap Panels with Tabs.
- **Alternatives**: a parallel array of locks in `TabList` (would have to be kept in step on every insert,
  move and close); a lock inside the panel model (the model is per panel, not per tab).

## R2 — Catching every folder change of a locked tab

- **Decision**: After any change of the panel model, `tabsChanged()` mirrors the model into the active tab.
  When the active tab is `.locked` and the model's folder differs from the tab's stored folder (and no tab
  is being restored), it calls `TabList.split(keeping:opened:)`: the locked tab keeps its stored state
  (cursor from the model's last Back entry when that entry is the locked folder), the new state is inserted
  right after it and activated. The panel already shows the new folder, so nothing is reloaded.
- **Rationale**: Folder changes come from many places (Return, "..", Back/Forward, history, hot paths, volume
  and server buttons, Go to Folder, `cd`, the other panel's commands, search results, archives). Reacting to
  the result in one place covers them all, including future ones, without touching each path.
- **Alternatives**: a check before each navigation call (many call sites, easy to miss one); a hook inside
  the model (the model would need to know about tabs).
- **Notes**: A refresh or a change to the same folder leaves the folder equal, so nothing opens (edge case).
  Leaving search results for their own folder keeps the folder and opens nothing.

## R3 — Returning to the locked folder

- **Decision**: `TabLock.returning(_:)` gives the stored state with `location = folder`, `cursorName` from
  the lock, results, branch and selection cleared, history kept. `TabList.returnCurrentToLock()` applies it
  to the active tab when its mode is `.allowsChanges`; the panel calls it whenever another tab becomes active
  (`switchTab`: click, next/previous, tab list; closing the active tab; reopening a closed tab) before
  restoring the tab. `returnAllToLocks()` runs on the layout loaded at start, so the app starts on the locked
  folders.
- **Rationale**: "Activated again after another tab was active" is exactly a change of the active index.

## R4 — Closing several tabs

- **Decision**: `closeOthers(keeping:)` and `closeToTheRight(of:)` remove only unlocked tabs and return the
  removed ones (oldest last) for the closed-tab list; the active index follows the kept tab, or the given
  one when the active tab was closed. Closing one tab directly ignores the lock (clarification).

## R5 — Duplicate and Copy to Other Panel

- **Decision**: `duplicate(at:)` inserts a copy of the tab (its stored state, or the live snapshot for the
  active one) with `lock = nil` right after it and activates it. Copy Tab to Other Panel takes the same
  unlocked copy and calls the other panel's `openTab(_:activate: true)`.

## R6 — Ejected volumes and disconnected servers

- **Decision**: Before the panel and its tabs move home, `TabList.unlock(where:)` removes the locks of every
  tab on the volume (the active one included), then the existing `redirect` and navigation run; with the
  lock gone, the active tab's move home does not split.

## R7 — A locked folder that is gone

- **Decision**: `restoreTab` already falls back to the nearest existing parent. When the restored tab is
  locked, `relock(at:to:)` moves its locked folder to that parent (cursor cleared) and the tab is stored
  before the strip updates, so the fallback itself does not count as a folder change.

## R8 — The strip

- **Decision**: `TabStrip.Item` (title, lock mode, tooltip). Each tab view tracks the pointer
  (`NSTrackingArea`, `.mouseEnteredAndExited`, `.activeAlways`); its left slot (12 × 12 pt, 4 pt from the edge,
  as today) shows: the close button while hovered (when the panel has more than one tab); else the lock
  (`lock.fill`, secondary label color) for a locked tab; else the close button for the active tab; else
  nothing. The name keeps its 18 pt insets, so it never moves. Tooltip: the title, or for a locked tab
  "Locked: <path>" / "Locked, folder changes allowed: <path>". The tab list menu shows the lock symbol as the
  item image.
- **Context menu**: built per tab with the tab index as tag; enabled states from the list (Close Tab and Close
  Other Tabs need two tabs, Close Tabs to the Right a following tab, Reopen Closed Tab a closed tab). The
  strip's tabs fill its whole width, so there is no empty part to right-click (spec User Story 5, scenario 5
  does not occur; recorded in Clarifications).
