# Contract: Volume Bar, Server Buttons and Toolbar Items

## Core API (CommanderCore)

```swift
// RemoteConnections (actor) — additions
public static let didChangeNotification: Notification.Name   // posted after `opened` changes
public var openedEndpoints: [RemoteEndpoint] { get }          // opening order, includes dropped
// disconnect(_:) also removes the endpoint from `opened` when no session is open

public enum ServerLabels {
    public static func labels(for endpoints: [RemoteEndpoint]) -> [RemoteEndpoint: String]
}

public struct ConnectionPlaces<PanelID: Hashable> {
    public mutating func visit(_ location: RemoteLocation, panel: PanelID)
    public func place(for endpoint: RemoteEndpoint, panel: PanelID) -> RemoteLocation
    public mutating func forget(_ endpoint: RemoteEndpoint)
}

public struct VolumeBarSettings: Equatable, Sendable {
    public var showHome = false, showICloud = true, showNetwork = true, showServers = true
}

public enum VolumeBarModel {
    public enum Item: Equatable { case volume(VolumeInfo), home(URL), iCloud(URL), network,
                                       server(RemoteEndpoint, label: String) }
    public static func items(volumes: [VolumeInfo], home: URL, iCloud: URL?,
                             servers: [RemoteEndpoint], settings: VolumeBarSettings) -> [Item]
    public static func pressed(local: URL?, remote: RemoteEndpoint?, volumeRoot: URL?,
                               items: [Item]) -> Int?
}
```

## UI behavior (AxolotlCommander)

| Element | Click | Right-click | Hover | Accessibility |
|---|---|---|---|---|
| Volume button | Root of the volume (unchanged) | — | — | button, volume name |
| Home | Home folder | — | — | button "Home" |
| iCloud Drive | Top of iCloud Drive | — | — | button "iCloud Drive" |
| Network | Menu: network volumes · servers · Connect to Server… | same menu | — | button "Network" |
| Server button | `ConnectionPlaces.place(for:panel:)` in this panel | Open in Other Panel · Copy Address · Disconnect | eject symbol at the trailing edge | button label; eject = button "Disconnect <label>" |

- Every click activates the panel with focus in its file list and records the change in history.
- Disconnect (eject, menu): `RemoteConnections.disconnect`, `ConnectionPlaces.forget`, every
  panel of every main window on that endpoint goes home (same as the F12 dialog).
- Volume menu (⌥F1/⌥F2): a "Servers" section with `openedEndpoints` (labels from
  `ServerLabels`), omitted when empty.
- Toolbar: `cmd.connectToServer` (symbol `network`) in the default set; `cmd.disconnect`
  (symbol `eject`) allowed but not default; both validated like their menu commands.
- Settings → Appearance: "Volume bar shows:" — Home, iCloud Drive, Network, Server connections.

## Texts (en → cs, String Catalog)

| Key | cs |
|---|---|
| Home | Domů |
| iCloud Drive | iCloud Drive (existing key) |
| Network | Síť |
| Servers | Servery |
| Connect to Server… | (existing command title) |
| Open in Other Panel | (existing key) |
| Copy Address | Kopírovat adresu |
| Disconnect | Odpojit |
| Disconnect %@ | Odpojit %@ |
| Volume bar shows: | Lišta disků zobrazuje: |
| Server connections | Připojené servery |
