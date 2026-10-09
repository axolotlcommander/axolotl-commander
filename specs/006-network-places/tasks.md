# Tasks: Network Places in the Panel

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md)

**Format**: `[ID] [P?] [Story] Description`

## Phase 1: Foundational (core)

- [ ] T001 Write `NetworkPlaces` in Sources/CommanderCore/Network/NetworkPlaces.swift:
  - `location`, `isNetwork(_:)`;
  - `Service` (name, kind smb/afp/sftp, domain);
  - `items(services:volumes:)` (merge duplicates, names `<name>.<kind>`, volume rows);
  - `service(of:)`.
- [ ] T002 [P] Write `NetworkDiscovery` in Sources/CommanderCore/Network/NetworkDiscovery.swift:
  one `NWBrowser` per type, started on demand, a locked set and `didChangeNotification`.
- [ ] T003 [P] Write `BonjourResolver` in Sources/CommanderCore/Network/BonjourResolver.swift:
  `DNSServiceResolve` with a 5 s timeout, returning the host and port.
- [ ] T004 Wire the core:
  - `LocalFileSource.list` answers `network:/`;
  - `PanelModel.isNetwork`, and `goParent` goes Back (or home) on the network location;
  - `VolumeBarModel.pressed(network:)`;
  - `PathSegment.Kind.network`.
- [ ] T005 [P] Write tests in Tests/CommanderCoreTests/NetworkPlacesTests.swift for rows, merging,
  `service(of:)`, the pressed rule and `isNetwork`.

## Phase 2: User Story 1 — Browse (P1)

- [ ] T006 [US1] Update the panel for the network location in
  Sources/AxolotlCommander/PanelViewController.swift:
  - the allow-list in `canPerform`;
  - no watcher, `diskFolder` = home, refresh on `didChangeNotification` and on mounts;
  - title and path bar "Network";
  - a "Network" item in the volume menu.
- [ ] T007 [US1] Add the server icon and `displayPath` "Network" in Support.swift, and the
  network segment in PathBar.swift.
- [ ] T008 [US1] Add the destination and drag guards in OperationsController (transfer sheet
  prefill and the `run` refusal), ArchiveOperations (pack/unpack), PanelLinkCommands,
  PanelDragDrop and BriefView.
- [ ] T009 [US1] Add `NSLocalNetworkUsageDescription` and `NSBonjourServices` in scripts/bundle.sh,
  with the text in Resources/InfoPlist.xcstrings.

## Phase 3: User Story 2 — Open (P1)

- [ ] T010 [US2] In Sources/AxolotlCommander/NetworkPlacesUI.swift, resolve the service, then
  mount it through NetFS with UI (SMB/AFP) or open `ConnectSheet` prefilled (SFTP). Wire it into
  `openCursor`.
- [ ] T011 [US2] Add the `ConnectSheet.show(for:prefill:)` draft prefill in
  Sources/AxolotlCommander/ConnectSheet.swift.

## Phase 4: User Story 3 — Button and menu (P2)

- [ ] T012 [US3] In Sources/AxolotlCommander/VolumeBar.swift, a left click calls
  `onChooseNetwork` (the panel shows the Network folder), the right-click shows the quick menu,
  and the button shows pressed.

## Phase 5: Polish

- [ ] T013 [P] Add en + cs texts in Resources/Localizable.xcstrings.
- [ ] T014 [P] Update README and CHANGELOG.
- [ ] T015 Build without warnings and run `swift test`. GUI checks in the test copy:
  - listing with DISKSTATION (discovery only), Back, ⌥F1 Network, right-click menu, pressed state;
  - the disabled commands in the Network folder;
  - F5/F6, pack and links from the other panel do not offer `network:/`;
  - no drop or drag.

  Record the results below.
- [ ] T016 The maintainer checks mounting DISKSTATION and the SFTP prefill. Then set the spec
  status.

## GUI verification

| # | Result | Note |
|---|---|---|
