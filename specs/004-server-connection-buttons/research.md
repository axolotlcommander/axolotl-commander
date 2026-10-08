# Research: Server Connections, iCloud Drive and Network in the Volume Bar

Decisions for [plan.md](plan.md). Each one: Decision, Rationale, Alternatives considered.

## R1 — Which connections get a button (opened list)

**Decision**: `RemoteConnections` keeps an ordered list `opened: [RemoteEndpoint]`. An endpoint
is appended when its first session succeeds and removed only by `disconnect(_:)` /
`disconnectAll()`. A session that dropped (removed from `sessions` when a reconnect is tried)
stays in `opened`. New read-only property `openedEndpoints` returns the list in opening order.

**Rationale**: FR-005 (opening order) and FR-012 (a dropped connection keeps its button) need a
list that differs from `sessions`: today `sessions` loses the entry as soon as a dropped session
is noticed, and `connected` is sorted by name. Keeping the list in the actor that owns the
sessions keeps both consistent.

**Alternatives**: deriving the list in the UI from panel locations (misses connections no panel
shows); changing `connected` to opening order (it is also "live sessions only", used by the F12
dialog).

## R2 — Telling the UI about changes

**Decision**: when `opened` changes, the actor posts `RemoteConnections.didChangeNotification`
on `NotificationCenter.default`. The UI observes on the main queue and asks the actor for
`openedEndpoints` (async) before rebuilding the bars.

**Rationale**: FR-011 requires every volume bar in every window to update at once; a
notification reaches all of them without wiring windows together. The pattern matches the volume
bar's existing mount/unmount observers.

**Alternatives**: an `AsyncStream` per subscriber (more bookkeeping for many bars);
`@Observable` on the actor (not available for actors).

## R3 — The F12 dialog lists the same connections

**Decision**: the Disconnect dialog uses `openedEndpoints` instead of `connected`, so a dropped
connection that still has a button can also be closed there. `disconnect(_:)` removes the
endpoint from `opened` even when no session is open, and posts the notification.

**Rationale**: one notion of "open connection" in the whole app; FR-017 says the button result
equals the dialog result.

## R4 — Labels

**Decision**: pure function `ServerLabels.labels(for: [RemoteEndpoint]) -> [RemoteEndpoint: String]`
in the core: start with the host; endpoints whose labels collide get `user@host`; still colliding
ones get `user@host:port` (port shown only when not the protocol default); still colliding ones
(different protocols) get `protocol://` + that. Tooltip and Copy Address use the existing
`RemoteURL` formatting (never with a password; `RemoteEndpoint` holds none).

**Rationale**: FR-006/FR-007 are deterministic and easy to test without AppKit.

## R5 — Last folder per connection

**Decision**: core value type `ConnectionPlaces` records visits `(panel id, location)` and
answers `place(for endpoint, panel id) -> RemoteLocation?` following FR-009: this panel's last
folder, else the last folder of any panel, else nil (→ the server's login folder, i.e. a
`RemoteLocation` with an empty path, resolved by `RemoteConnections.resolve`). `forget(endpoint)`
on disconnect. The UI keeps one shared instance on the main actor, fed from
`PanelViewController.modelChanged()` whenever `model.remote` is set (the panel id is the panel
controller's `ObjectIdentifier`).

**Rationale**: the rule is pure and testable; memory only (spec assumption: not stored on disk).

**Alternatives**: reading panel history (tabs and Back lists would need scanning; does not cover
closed tabs).

## R6 — Volume bar items and pressed state

**Decision**: pure builder `VolumeBarModel.items(volumes:home:iCloud:servers:settings:)` returns
the ordered items (FR-031): `.volume(VolumeInfo)`, `.home(URL)`, `.iCloud(URL)`, `.network`,
`.server(RemoteEndpoint, label)`. `VolumeBarModel.pressed(location:remote:items:volumeRoot:)`
returns the index to press: a remote location presses its server (if shown); a local location
inside iCloud Drive presses iCloud Drive (FR-025); exactly the home folder presses Home when shown
(FR-027); otherwise the volume of the location (today's rule).

**Rationale**: the order, the visibility rules and the pressed rule are where mistakes would hide;
keeping them pure gives unit tests. The view only renders.

## R7 — Overflow in a narrow bar

**Decision**: keep `NSStackView` and give arranged views descending visibility priorities from
the first to the last item (`setVisibilityPriority`), with `detachesHiddenViews`; the stack then
drops items from the end when they do not fit (FR-031, edge case "narrow window").

**Rationale**: built-in AppKit behavior, no custom layout; volumes stay visible longest.

**Alternatives**: a custom overflow "»" menu (more UI, and the volume menu already lists
everything).

## R8 — Eject on hover and the button menu

**Decision**: server buttons are a small `NSButton` subclass with a tracking area; on hover it
shows an eject symbol (`eject.fill`, small) at its trailing edge as an accessibility child button
"Disconnect <label>"; a click on that area disconnects, elsewhere navigates. `menu(for:)` returns
Open in Other Panel / Copy Address / Disconnect.

**Rationale**: FR-013/FR-014/FR-021 with standard AppKit pieces; the same hover approach as the
path bar segments (spec 003).

## R9 — iCloud Drive and Network

**Decision**: iCloud Drive = `~/Library/Mobile Documents/com~apple~CloudDocs` when it exists
(the same check the volume menu uses today), symbol `icloud`. Network = symbol `network`; a click
pops up a menu: mounted volumes with `isNetwork` (open their root), the opened connections (as
the server buttons), "Connect to Server…" (the existing command for that panel).

**Rationale**: FR-024–FR-026; no network neighbourhood browser (out of scope).

## R10 — Settings

**Decision**: UserDefaults keys `volumeBar.showHome` (false), `volumeBar.showICloud`,
`volumeBar.showNetwork`, `volumeBar.showServers` (true), as `@AppStorage` toggles in Settings →
Appearance under "Volume bar shows:". Bars rebuild on `UserDefaults.didChangeNotification`
(the same mechanism the path bar settings use).

## R11 — Toolbar items

**Decision**: `MainToolbar.symbols` gets `.connectToServer: "network"` and
`.disconnect: "eject"`; `defaultItems` gets `.connectToServer` at the end of the tools group
(before the flexible space), and `toolbarDefaultItemIdentifiers` slices the groups by name
instead of fixed indexes. Enabling follows the existing `validateToolbarItem` → `canPerform` path.

**Rationale**: FR-001–FR-004 with the existing toolbar machinery.
