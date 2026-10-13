# Data Model: Volumes in the Go Menu and Ejecting Volumes

## VolumeInfo (extended)

| Field | Type | Notes |
|---|---|---|
| `isEjectable` | Bool | the system's flag (`volumeIsEjectable`) |
| `isRootFileSystem` | Bool | the startup disk |
| `wholeDisk` | String? | BSD name of the physical disk (e.g. `disk4`); nil for network volumes |

Existing: `url`, `name`, `isRemovable`, `isNetwork`, `isInternal`, capacities. Defaults keep existing
initializer calls compiling (`false`, `false`, `nil`).

## Ejectability

- `canEject(v)` = `!v.isRootFileSystem && v.url.path != "/" && (v.isEjectable || v.isRemovable ||
  !v.isInternal || v.isNetwork)`.
- `otherVolumes(onDiskOf v, in volumes)` = volumes with the same non-nil `wholeDisk`, other than `v`.

## EjectTarget

```text
enum EjectTarget { case volume(VolumeInfo), server(RemoteEndpoint) }
static func resolve(location:, archiveFile:, isNetwork:, remote:, volumes:, rootOf:) -> EjectTarget?
```

- Network → nil. Remote location → `.server(endpoint)`.
- Otherwise the file-system URL is the archive file when inside an archive, else the location (search
  results use their root); its volume root (`rootOf`) is matched against `volumes`; a volume that
  `canEject` → `.volume`, else nil.
- `title(for target?)`: `.volume(v)` → "Eject “name”"; `.server(e)` → "Disconnect “name”"; nil →
  "Eject Volume".

## DisconnectList

- `Item`: `kind` (`server(RemoteEndpoint)` / `volume(VolumeInfo)`), `name`, `detail` (protocol and host
  for servers, "Network Volume" / "Disk Image" / "External Disk" for volumes).
- `sections(servers:, volumes:)` → Servers, Network Volumes (`isNetwork`), Disks (other `canEject`);
  empty sections left out; order inside as given.
- `preChecked(target: EjectTarget?)` → the matching item id or none.
- `confirmTitle(checked:)` → "Disconnect" when every checked item is a server, otherwise "Eject";
  confirm disabled when nothing is checked.
- `isEnabled(servers:, volumes:)` → any item exists.

## VolumeUse

- `VolumeUser`: `title` (localized operation name, e.g. "Copying 3 items"), `urls: [URL]`.
- `isOnVolume(url, root)`: standardized file path equals the root path or starts with root path + "/"
  (root "/" never matches here, since the startup disk is not ejectable).
- `blocking(root, users)` → first user with any URL on the volume.

## TabList.redirect

- `redirect(where match: (URL) -> Bool, to: URL)`: every tab except the active one whose `location`
  matches gets `location = to`, empty cursor and selection; history kept. Returns the count changed.

## OperationState (UI)

- New `urls: [URL]`: sources plus the destination folder of the operation (archive operations: the
  archive file and the folder; remote: the local side only).
