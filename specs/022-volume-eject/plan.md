# Implementation Plan: Volumes in the Go Menu and Ejecting Volumes

**Branch**: `022-volume-eject` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (pure, tested):
  - `VolumeInfo` gets `isEjectable` (the system's flag), `isRootFileSystem` and `wholeDisk` (the BSD
    name of the physical disk, nil for network volumes); `Volumes.mounted()` fills them.
  - `Ejectability` (`Volumes/Ejectability.swift`, NEW): `canEject(_ volume:)` (FR-005, FR-006) and
    `otherVolumes(onDiskOf:in:)` for the partition question (FR-014).
  - `EjectTarget` (`Volumes/EjectTarget.swift`, NEW): what ⌘E acts on for a panel location
    (`.volume(VolumeInfo)`, `.server(RemoteEndpoint)`, `nil`), from the location, the archive file,
    the search results root, Network and the volume list; the menu title ("Eject “X”" /
    "Disconnect “X”" / "Eject Volume").
  - `DisconnectList` (`Volumes/DisconnectList.swift`, NEW): sections (servers, network volumes,
    disks), the pre-checked item for the active panel, the confirm title rule, and whether the
    command is enabled (FR-009, FR-010).
  - `VolumeUse` (`Volumes/VolumeUse.swift`, NEW): `blocking(_ root: URL, users: [VolumeUser]) ->
    VolumeUser?` where a `VolumeUser` is a title plus the URLs it touches; a URL is on the volume
    when its standardized path equals the root or starts with root + "/" (FR-012).
  - `TabList.redirect(where:to:)` (`Window/TabList.swift`): sends every inactive tab whose location
    matches to a new location and clears its cursor (FR-011).
- **UI**:
  - Menus: `MenuID.left` / `.right` removed; `.leftVolumeMenu` / `.rightVolumeMenu` move to `.go`
    ("Left Volume…", "Right Volume…", same chords, separator before the pair); `MainMenuBuilder`
    titles and context-menu set, `KeyboardSettings` sections updated.
  - `Command.ejectVolume` ("Eject Volume", `.commands`, ⌘E, right after `.disconnect`); title set in
    `MainWindowController.validateMenuItem` from `EjectTarget`; enabled when the target is not nil.
  - `VolumeEjector` (`VolumeEjector.swift`, NEW, `@MainActor`): the single path used by ⌘E, ⏏, the
    context menu and F12:
    1. collect users from every window (`OperationsController.running` with their URLs, Find
       windows, size calculations) and refuse with a message when `VolumeUse.blocking` finds one;
    2. when `otherVolumes(onDiskOf:)` is not empty, ask (Eject / Cancel) naming them;
    3. send every panel and tab on the volume home and stop their watchers (`DirectoryWatcher.cancel`);
    4. mark the volume busy (volume bar), call `NSWorkspace.unmountAndEjectDevice(at:)` off the main
       thread, unmark; on error show the system's reason (`localizedDescription` /
       `localizedFailureReason`);
    5. servers go through the existing `ServerConnectionsUI.disconnect`, which also moves inactive tabs
       now (`TabList.redirect`).
  - `OperationState` gets `urls: [URL]` (sources and destination), set at its creation sites in
    `OperationsController`, `ArchiveOperations`, `RemoteOperations` and `RenameSheets`; Find and the
    occupied-space calculation register their roots in a small `VolumeUsers` list while they run.
  - `VolumeBar`: `ServerButton`'s hover ⏏ becomes `EjectableButton`, used by server buttons and by
    volume buttons whose volume `canEject`; volume buttons get `menuProvider` (Eject / Volume
    Information…); a busy volume shows a small spinner in place of the ⏏ and ignores clicks on it.
  - `DisconnectSheet` (AppKit, replaces the SwiftUI sheet in `ConnectSheet.swift`): a `KeySheetWindow`
    with an `NSTableView` (group rows for the sections, a checkbox per row), Space toggles, Return
    confirms, Esc cancels; rows refresh on mount / unmount / server changes. `.disconnect` enabled by
    `DisconnectList.isEnabled`.

## Technical Context

- Swift 6.2, AppKit, Swift Testing. `NSWorkspace.unmountAndEjectDevice(at:)` for ejecting (the
  Finder's behavior for a whole disk); DiskArbitration (`DADiskCopyWholeDisk`, BSD name) only to find
  the other volumes on the same disk.
- No new dependencies, no new settings.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ No eject while an operation uses the volume; panels leave it first; errors reported; the startup disk is never ejectable; the GUI check ejects only a disk image made in the scratch folder. |
| II Reference | ✅ Eject / disconnect from the drive buttons and the disconnect command; Mac conventions (⌘E, ⏏, menu bar by function) recorded as deviations in the spec. |
| III Native macOS | ✅ NSWorkspace for ejecting, off the main thread; String Catalog for all texts. |
| IV Testable core | ✅ Ejectability, target and title, dialog list and pre-check, the volume-use check and tab redirection in the core with tests. |
| V Clean-room | ✅ Behavior only. |
| VI Incremental | ✅ US2 (menus) → US1 (⌘E with the safety path) → US3 (bar) → US4 (F12). |
| VII Language | ✅ |

## Project Structure

```text
Sources/CommanderCore/Volumes.swift                         VolumeInfo fields
Sources/CommanderCore/Volumes/{Ejectability,EjectTarget,DisconnectList,VolumeUse}.swift      NEW
Sources/CommanderCore/Window/TabList.swift                  redirect(where:to:)
Sources/CommanderCore/Command.swift                         MenuID, ejectVolume, volume items in Go
Sources/AxolotlCommander/{VolumeEjector,DisconnectSheet}.swift                                NEW
Sources/AxolotlCommander/{MainMenuBuilder,KeyboardSettings,MainWindowController,PanelViewController,
  VolumeBar,OperationsController,ArchiveOperations,RemoteOperations,ServerConnectionsUI,ConnectSheet}.swift
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/{VolumeEjectTests,DisconnectListTests}.swift                          NEW
```
