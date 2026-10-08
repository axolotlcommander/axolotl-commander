# Data Model: Server Connections, iCloud Drive and Network in the Volume Bar

All types below live in `CommanderCore` (no AppKit) unless marked UI.

## Opened connections (in `RemoteConnections`)

| Field | Type | Rule |
|---|---|---|
| `opened` | `[RemoteEndpoint]` | Appended when the first session to an endpoint succeeds; unique; removed only by `disconnect` / `disconnectAll`; survives a dropped session (R1). |
| `openedEndpoints` | `[RemoteEndpoint]` (read) | `opened` in opening order. |
| `didChangeNotification` | `Notification.Name` | Posted after every change of `opened` (R2). |

## ServerLabels

`labels(for endpoints: [RemoteEndpoint]) -> [RemoteEndpoint: String]` (R4)

- Level 1: `host`.
- Level 2 for endpoints whose level-1 label is shared: `user@host` (`host` when no user).
- Level 3 for endpoints still sharing: `user@host:port` (port only when not the protocol default).
- Level 4 for endpoints still sharing: `protocol://` + level 3.
- Never contains a password (an endpoint holds none).

## ConnectionPlaces

Remembers where panels were on each connection (R5). Memory only.

| Member | Meaning |
|---|---|
| `visit(_ location: RemoteLocation, panel: PanelID)` | Records the folder as this panel's last place on its endpoint and as the endpoint's overall last place. |
| `place(for endpoint: RemoteEndpoint, panel: PanelID) -> RemoteLocation` | This panel's last place, else the overall last place, else `RemoteLocation(endpoint, path: "")` (login folder). |
| `forget(_ endpoint: RemoteEndpoint)` | Drops all places of the endpoint (on disconnect). |

`PanelID` is an opaque `Hashable` chosen by the UI (the panel controller's `ObjectIdentifier`).

## VolumeBarSettings

| Key | Type | Default |
|---|---|---|
| `volumeBar.showHome` | Bool | false |
| `volumeBar.showICloud` | Bool | true |
| `volumeBar.showNetwork` | Bool | true |
| `volumeBar.showServers` | Bool | true |

## VolumeBarModel

`Item` (ordered, FR-031): `.volume(VolumeInfo)`, `.home(URL)`, `.iCloud(URL)`, `.network`,
`.server(RemoteEndpoint, label: String)`.

`items(volumes:home:iCloud:servers:settings:) -> [Item]`

- Volumes always, in the order `Volumes.mounted()` gives.
- `.home` when `showHome`; `.iCloud` when `showICloud` and an iCloud URL is given (it exists);
  `.network` when `showNetwork`; one `.server` per endpoint of `servers` when `showServers`,
  labels from `ServerLabels`.

`pressed(local: URL?, remote: RemoteEndpoint?, volumeRoot: URL?, items:) -> Int?`

- Remote location → index of its `.server` item, else nil.
- Local location inside the iCloud URL and `.iCloud` present → that index.
- Local location equal to the home URL and `.home` present → that index.
- Otherwise the `.volume` whose URL equals `volumeRoot` (today's rule).

## UI state (UI module)

- One shared `ConnectionPlaces` on the main actor, fed by every panel's `modelChanged()`.
- Each `VolumeBar` holds its `[Item]`, rebuilt on mount/unmount, on
  `RemoteConnections.didChangeNotification` and on `UserDefaults.didChangeNotification`;
  `show(location:)` re-evaluates `pressed`.
