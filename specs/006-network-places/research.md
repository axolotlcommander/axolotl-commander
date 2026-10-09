# Research: Network Places in the Panel

Decisions for [plan.md](plan.md): Decision, Rationale, Alternatives.

## R1 — How a panel shows the Network folder

**Decision**: a location URL `network:/` (`NetworkPlaces.location`). `PanelModel.isNetwork`
tells it apart. `LocalFileSource.list` answers it from the discovery service.

**Rationale**: history, tabs, persistence and refresh already work on location URLs. The
alternative, a separate mode like `ResultsListing`, would have to be threaded through
`PanelState`, history entries and snapshots.

**Risk and answer**: code that treats the location as a folder on disk (new folder, transfers,
links, terminal, watcher). `canPerform` therefore allows only navigation commands for a network
panel (allow-list, FR-011). Every place that uses the other panel's location as a destination
checks `isNetwork`, and `OperationsController.run` refuses a network destination (FR-012).

## R2 — Rows

**Decision**: a pure `NetworkPlaces.items(services:volumes:)`:
- A service becomes `FileItem(url: network:/<kind>/<name>, name: "<name>.<kind>", isDirectory: false)`,
  so the extension column shows the protocol. A server icon is chosen by the URL scheme.
- A mounted network volume becomes a folder row with its `/Volumes/...` URL, so Enter enters it
  through the normal path.
- Services with the same name and kind (several interfaces) are merged. Rows are sorted by the
  panel as usual.

**Alternatives**: a new "Kind" column (needs configurable columns).

## R3 — Discovery

**Decision**: `NetworkDiscovery.shared` (core, Network framework). It runs one `NWBrowser` per
type: `_smb._tcp`, `_afpovertcp._tcp` and `_sftp-ssh._tcp` in `local.`. It starts on the first
request and keeps the current set behind a lock. After each change it posts
`NetworkDiscovery.didChangeNotification`. Panels showing the Network folder refresh on that
notification and on volume mount/unmount.

**Rationale**: `NWBrowser` is the current API. `NetServiceBrowser` is deprecated and would warn.

## R4 — Resolving a service

**Decision**: `BonjourResolver.resolve(name:type:domain:)` (core, `dnssd`). It uses
`DNSServiceResolve` with `DNSServiceSetDispatchQueue` and a 5 s timeout, and returns the host
name without the trailing dot plus the port.

**Rationale**: it gives the `.local` host name the mount URL and the Connect dialog need.
`NWConnection` would give IP addresses with interface scopes instead.

## R5 — Mounting SMB/AFP

**Decision**: `NetFSMountURLAsync` (UI module, NetFS):
- URL `smb://<host>` or `afp://<host>`, without a share;
- open options `UIOption = AllowUI`, so macOS shows the login dialog (Keychain) and the share
  picker;
- on success the panel goes to the first mount point; a cancel is ignored; other errors are
  reported.

**Rationale**: this is the same service Finder uses. No credentials pass through the app.

## R6 — SFTP

**Decision**: `ConnectSheet.show(for:prefill:)` opens the dialog with a draft for SFTP and the
resolved host and port. The user name stays empty.

## R7 — Volume bar and menus

**Decision**:
- `VolumeBar.onChooseNetwork`: a left click calls it, and the existing `menuProvider` keeps the
  quick menu for the right-click.
- `VolumeBarModel.pressed(... network:)` presses `.network` when the panel shows the Network
  folder.
- The volume menu gets a "Network" item.
- The path bar shows a single segment "Network" (new `PathSegment.Kind.network`), and the window
  title shows "Network".

## R8 — Local network permission

**Decision**: Info.plist gets `NSLocalNetworkUsageDescription` (localized in InfoPlist.xcstrings)
and `NSBonjourServices` with the three types, so macOS can ask the user once.
