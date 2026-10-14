# Data Model: Tab Locking and Tab Menu

## TabLock (NEW, core)

| Field | Type | Meaning |
|---|---|---|
| `mode` | `.locked` / `.allowsChanges` | Locked: folder changes open new tabs. Allows changes: browse, return on activation. |
| `folder` | URL | The folder the tab showed when it was locked (moved to the nearest existing parent when gone). |
| `cursorName` | String? | The item under the cursor at locking; used when returning. |

Encoded as `{"mode": "locked" | "allowsChanges", "folder": URL, "cursorName": String?}`.

## PanelState (changed)

- `lock: TabLock?` — nil for a normal tab. Encoded under the key `lock`; missing → nil.
- Snapshots made by the panel model carry no lock; `TabList.updateCurrent` puts the stored lock back.

## TabList (changed)

| Operation | Rule |
|---|---|
| `updateCurrent(_:)` | Stores the snapshot, keeping the active tab's lock. |
| `setLock(_:at:)` | Sets or clears a tab's lock (folder and cursor from that tab's state). |
| `split(keeping:opened:)` | The active (locked) tab gets `keeping`, `opened` (unlocked) is inserted after it and activated. |
| `returnCurrentToLock()` / `returnAllToLocks()` | `.allowsChanges` tabs take `TabLock.returning`. |
| `closeOthers(keeping:)` / `closeToTheRight(of:)` | Remove unlocked tabs only; return the removed states. |
| `duplicate(at:)` | Unlocked copy inserted after the tab and activated. |
| `unlock(where:)` | Clears the locks of tabs whose location matches. |
| `redirect(where:to:)` | As before, and clears the locks of the redirected tabs. |
| `relock(at:to:)` | Moves a lock's folder (cursor cleared). |

## State transitions of one tab

```text
none ──Lock Tab──▶ locked ──Lock Tab──▶ none
none ──Lock…Allow──▶ allowsChanges ──Lock…Allow──▶ none
locked ◀──the other item──▶ allowsChanges
locked / allowsChanges ──volume ejected / server disconnected──▶ none
```
