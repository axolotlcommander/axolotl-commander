# Tasks: Network Places in the Panel

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md)

**Format**: `[ID] [P?] [Story] Description`

## Phase 1: Foundational (core)

- [X] T001 Write `NetworkPlaces` in Sources/CommanderCore/Network/NetworkPlaces.swift:
  - `location`, `isNetwork(_:)`;
  - `Service` (name, kind smb/afp/sftp, domain);
  - `items(services:volumes:)` (merge duplicates, names `<name>.<kind>`, volume rows);
  - `service(of:)`.
- [X] T002 [P] Write `NetworkDiscovery` in Sources/CommanderCore/Network/NetworkDiscovery.swift:
  one `NWBrowser` per type, started on demand, a locked set and `didChangeNotification`.
- [X] T003 [P] Write `BonjourResolver` in Sources/CommanderCore/Network/BonjourResolver.swift:
  `DNSServiceResolve` with a 5 s timeout, returning the host and port.
- [X] T004 Wire the core:
  - `LocalFileSource.list` answers `network:/`;
  - `PanelModel.isNetwork`, and `goParent` goes Back (or home) on the network location;
  - `VolumeBarModel.pressed(network:)`;
  - `PathSegment.Kind.network`.
- [X] T005 [P] Write tests in Tests/CommanderCoreTests/NetworkPlacesTests.swift for rows, merging,
  `service(of:)`, the pressed rule and `isNetwork`.

## Phase 2: User Story 1 — Browse (P1)

- [X] T006 [US1] Update the panel for the network location in
  Sources/AxolotlCommander/PanelViewController.swift:
  - the allow-list in `canPerform`;
  - no watcher, `diskFolder` = home, refresh on `didChangeNotification` and on mounts;
  - title and path bar "Network";
  - a "Network" item in the volume menu.
- [X] T007 [US1] Add the server icon and `displayPath` "Network" in Support.swift, and the
  network segment in PathBar.swift.
- [X] T008 [US1] Add the destination and drag guards in OperationsController (transfer sheet
  prefill and the `run` refusal), ArchiveOperations (pack/unpack), PanelLinkCommands,
  PanelDragDrop and BriefView.
- [X] T009 [US1] Add `NSLocalNetworkUsageDescription` and `NSBonjourServices` in scripts/bundle.sh,
  with the text in Resources/InfoPlist.xcstrings.

## Phase 3: User Story 2 — Open (P1)

- [X] T010 [US2] In Sources/AxolotlCommander/NetworkPlacesUI.swift, resolve the service, then
  mount it through NetFS with UI (SMB/AFP) or open `ConnectSheet` prefilled (SFTP). Wire it into
  `openCursor`.
- [X] T011 [US2] Add the `ConnectSheet.show(for:prefill:)` draft prefill in
  Sources/AxolotlCommander/ConnectSheet.swift.

## Phase 4: User Story 3 — Button and menu (P2)

- [X] T012 [US3] In Sources/AxolotlCommander/VolumeBar.swift, a left click calls
  `onChooseNetwork` (the panel shows the Network folder), the right-click shows the quick menu,
  and the button shows pressed.

## Phase 5: Polish

- [X] T013 [P] Add en + cs texts in Resources/Localizable.xcstrings.
- [X] T014 [P] Update README and CHANGELOG.
- [X] T015 Build without warnings and run `swift test`. GUI checks in the test copy:
  - listing with DISKSTATION (discovery only), Back, ⌥F1 Network, right-click menu, pressed state;
  - the disabled commands in the Network folder;
  - F5/F6, pack and links from the other panel do not offer `network:/`;
  - no drop or drag.

  Record the results below.
- [X] T016 The maintainer checks mounting DISKSTATION and the SFTP prefill. Then set the spec
  status.

## GUI verification

| # | Result | Note |
|---|---|---|
| 1 | Pass | Click on Network (left panel): the Network folder listed `DISKSTATION` with extension `smb` and a server icon; the button was pressed; the title and the path bar showed "Network"; the command line showed `~`. |
| 2 | Pass | Later the NAS stopped announcing `_smb._tcp` (only `_device-info._tcp` answered, checked with an `NWBrowser` outside the app): the folder was empty with "0 files, 0 folders", ⌘R too; nothing failed. |
| 3 | Pass | Backspace and ⌘[ in the Network folder returned to the previous folder (`l6/a`). |
| 4 | Pass | ⌥F1 lists "Network" after the favourite folders; choosing it shows the Network folder. |
| 5 | Pass | Right-click on Network shows the quick menu (Connect to Server… with nothing mounted or connected); the panel stays where it was. |
| 6 | Pass | Menus with the Network folder active: only navigation, sorting, view, tabs, volume menus, refresh, Connect to Server and window commands are enabled; Copy, Move, New Folder, Move to Trash, Rename, links, Pack, Get Info, Paste Files, Open Terminal Here and the rest are disabled. Compare Panels stays enabled (it compares the listed names and dates only). |
| 7 | Pass | F5 in the other panel (Network folder on the left) prefills the other panel's own folder, not "Network". |
| 8 | Pass | Dragging `f.txt` from the right panel onto the Network folder: the drop is refused, no dialog, nothing copied. Drag out of the Network folder not tried in the GUI (no rows while the NAS was silent); `pasteboardWriterForRow` and the Brief view's drag return nothing on the network location. |
| 9 | Pass | 2026-10-09: the maintainer opened `DISKSTATION` from the Network folder in the test copy (macOS login/share dialog, then the panel entered the share). |
