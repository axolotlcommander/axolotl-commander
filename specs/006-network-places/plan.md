# Implementation Plan: Network Places in the Panel

**Branch**: `006-network-places` | **Date**: 2026-10-09 | **Spec**: [spec.md](spec.md)

## Summary

A click on the volume bar's Network button, or Network in the volume menu, shows the virtual
Network folder: Bonjour SMB/AFP/SFTP servers and mounted network volumes. Opening a row works
like this:
- **SMB/AFP**: the macOS mount dialog (NetFS), then the panel enters the share.
- **SFTP**: opens the Connect dialog prefilled.
- **Mounted volume**: the panel enters it.

The quick menu moves to the right-click. The Network folder can never be written to or used as a
destination (see [research.md](research.md)).

## Technical Context

**Language/Version**: Swift 6.2, strict concurrency.

**Primary Dependencies**:
- Foundation, Network (`NWBrowser`) and `dnssd` in the core;
- AppKit, SwiftUI and NetFS in the UI.

**Storage**: none new. The location URL `network:/` is persisted like any location.

**Testing**: Swift Testing for the row builder (merge, names, kinds, volumes), the location
helpers, `pressed` with the network flag, and the allow-list. GUI checks run in the test copy:
listing (the real NAS is only discovered, never contacted), Back, the menus, disabled commands,
destinations and the right-click menu. The maintainer checks mounting on the NAS.

**Target Platform**: macOS 15+

**Constraints**:
- The app never contacts a server until the user opens it.
- No writes to or through the Network folder.
- Texts in en + cs.

**Scale/Scope**:
- 3 new core files and 1 new test file;
- ~8 UI files touched;
- ~15 strings.

## Constitution Check

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | Allow-list of commands, destination guards, no drag, refusal in `run`. |
| II Reference behavior | ✅ | The reference's Change Drive menu offers Network in the panel; deviations D-001–D-003 are recorded. |
| III Native macOS | ✅ | Bonjour, the NetFS dialog with Keychain, the Local Network permission, SF Symbols. |
| IV Testable core | ✅ | Row building, location helpers and the pressed rule are pure and tested. |
| V Clean-room, GPL | ✅ | No reference sources, no new dependencies (system frameworks). |
| VI Incremental | ✅ | US1 → US2 → US3, commit after each. |
| VII Language | ✅ | English in git, Czech in the String Catalog. |

## Project Structure

```text
Sources/CommanderCore/Network/NetworkPlaces.swift     # NEW: location, service, rows (pure)
Sources/CommanderCore/Network/NetworkDiscovery.swift  # NEW: NWBrowser service, notification
Sources/CommanderCore/Network/BonjourResolver.swift   # NEW: DNSServiceResolve wrapper
Sources/CommanderCore/FileSource.swift                # network:/ listing
Sources/CommanderCore/PanelModel.swift                # isNetwork; goParent = Back/home
Sources/CommanderCore/Window/VolumeBarModel.swift     # pressed(network:)
Sources/CommanderCore/Window/Breadcrumbs.swift        # PathSegment.Kind.network
Sources/AxolotlCommander/NetworkPlacesUI.swift        # NEW: open service (NetFS mount, SFTP prefill)
Sources/AxolotlCommander/PanelViewController.swift    # allow-list, open, refresh on change, title,
                                                      #   watcher, diskFolder, volume menu item
Sources/AxolotlCommander/VolumeBar.swift              # click → Network folder, right-click menu
Sources/AxolotlCommander/PathBar.swift, Support.swift # segment/icon/displayPath
Sources/AxolotlCommander/OperationsController.swift, ArchiveOperations.swift,
  PanelLinkCommands.swift, PanelDragDrop.swift, BriefView.swift  # destination and drag guards
Sources/AxolotlCommander/ConnectSheet.swift           # prefill
scripts/bundle.sh, Resources/InfoPlist.xcstrings      # Local Network permission
Tests/CommanderCoreTests/NetworkPlacesTests.swift     # NEW
```

## Complexity Tracking

No violations.
