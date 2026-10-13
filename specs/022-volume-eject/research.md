# Research: Volumes in the Go Menu and Ejecting Volumes

## How to eject

- **Decision**: `NSWorkspace.shared.unmountAndEjectDevice(at:)`, called off the main thread.
- **Rationale**: it is what the Finder uses; it unmounts every volume of the physical disk and ejects
  it, works for disk images and network volumes (unmount), and throws an error with the system's
  reason when a file is in use.
- **Alternatives**: DiskArbitration `DADiskUnmount` + `DADiskEject` (more control, more code, same
  result); `diskutil` / `hdiutil` processes (slower, string parsing).

## Which volumes are ejectable

- **Decision**: not the root file system; and the system's `volumeIsEjectable`, or removable, or not
  internal (external disks and disk images), or a network volume.
- **Rationale**: matches the volumes the Finder shows a ⏏ for; internal APFS volumes other than the
  startup disk stay without one (they are hidden by `.skipHiddenVolumes` in most cases anyway).
- **Alternatives**: `volumeIsEjectable` alone (misses many external disks that report false).

## Other volumes on the same disk

- **Decision**: `VolumeInfo.wholeDisk` from DiskArbitration (`DADiskCreateFromVolumePath` →
  `DADiskCopyWholeDisk` → BSD name); the question appears only when another mounted, visible volume
  has the same whole disk.
- **Rationale**: the Finder ejects the whole disk; without the question a second partition would
  disappear without warning.
- **Alternatives**: always eject only the one volume (`unmountVolume`), which leaves the disk spinning
  and is not what the Finder does.

## What keeps a volume busy in the app

- **Decision**: the panels' `DirectoryWatcher` file descriptors (opened `O_EVTONLY`, which does not
  block unmounting, but they are cancelled anyway), running operations, Find and the occupied-space
  calculation. Panels and tabs move home before the eject; running work refuses the eject.
- **Rationale**: an eject that silently aborts a copy would lose data (constitution I); moving panels
  first is cheap and matches the spec.
- **Alternatives**: cancel running operations automatically (rejected: it hides a decision from the
  user).

## The Disconnect dialog in AppKit

- **Decision**: replace the SwiftUI `DisconnectSheet` with an AppKit sheet (`KeySheetWindow` from spec
  021, `NSTableView` with group rows and checkboxes).
- **Rationale**: exact keyboard behavior (arrows, Space toggles the row, Return confirms) and live
  refresh of rows; the SwiftUI list does not toggle with Space.
- **Alternatives**: keep SwiftUI and add key handling (fragile focus handling).

## Menu title of Eject Volume

- **Decision**: set in `MainWindowController.validateMenuItem` (as Maximize/Restore Panels does).
- **Rationale**: the existing mechanism; the title follows the active panel whenever the menu opens.
