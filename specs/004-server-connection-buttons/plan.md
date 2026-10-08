# Implementation Plan: Server Connections, iCloud Drive and Network in the Volume Bar

**Branch**: `004-server-connection-buttons` | **Date**: 2026-10-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-server-connection-buttons/spec.md`

## Summary

The toolbar gets a "Connect to Server" button (default) and an optional "Disconnect" item. The
volume bar above each panel shows, after the volumes, optional Home, iCloud Drive and Network
buttons and one button per open server connection; a server button returns the panel to its last
folder on that server, shows an eject symbol on hover and has a menu. The volume menu (⌥F1/⌥F2)
gets a "Servers" section. Settings → Appearance chooses which extra items the bar shows.

Approach (see [research.md](research.md)): `RemoteConnections` keeps an ordered list of opened
connections that survives a dropped session and posts a change notification (R1–R3). Pure core
types compute labels (R4), last places (R5) and the bar's items and pressed item (R6). The UI
`VolumeBar` renders those items with overflow by visibility priority (R7), a hover eject and menus
(R8–R9); settings are UserDefaults toggles (R10); toolbar items reuse the command machinery (R11).

## Technical Context

**Language/Version**: Swift 6.2 (strict concurrency, upcoming features ExistentialAny,
InternalImportsByDefault, MemberImportVisibility)

**Primary Dependencies**: Foundation; AppKit and SwiftUI (UI module only); SF Symbols
(`network`, `icloud`, `house`, `eject`)

**Storage**: UserDefaults — `volumeBar.showHome` (false), `volumeBar.showICloud`,
`volumeBar.showNetwork`, `volumeBar.showServers` (true); last places in memory only

**Testing**: Swift Testing (`swift test`) for labels, places, bar items, pressed rule and the
opened-connections list (with the existing fake connector); GUI checks in the test copy
`iCmdTest.app` against the local test SFTP/FTP servers on 127.0.0.1

**Target Platform**: macOS 15+

**Project Type**: desktop-app (SwiftPM: `CommanderCore` without AppKit + `AxolotlCommander` AppKit)

**Performance Goals**: bars rebuild within the same main-thread pass after a connection change
(SC-004); a rebuild is a handful of buttons, no I/O except volume icons (cached by the system)

**Constraints**: no file operations (FR-023); passwords never shown or copied (FR-020); connection
opening, authentication and keep-alive unchanged; new texts in en + cs

**Scale/Scope**: 3 new core files, 1 core file extended, ~6 UI files touched, ~25 new tests,
~10 strings

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | Navigation, connect and disconnect only (FR-023); disconnect reuses the F12 path; GUI tests only against local test servers and scratch folders; iCloud Drive only browsed. |
| II Faithful reference behavior | ✅ | Open connections listed in the volume (Change Drive) menu, last directory on return, F12 dialog unchanged. Deviations D-001–D-005 recorded in the spec. |
| III Native macOS | ✅ | Mac toolbar item, Finder-like eject on hover, SF Symbols, accessibility buttons, UserDefaults, `String(localized:)`. |
| IV Testable core | ✅ | Opened list, labels, last places, bar items and pressed rule in `CommanderCore` with tests; the UI renders and routes. |
| V Clean-room, GPL | ✅ | Behavior from the spec and the reference help; no reference sources; own wording; no new dependencies; SPDX headers. |
| VI Incremental delivery | ✅ | US1 and US2 (P1) first, then US3–US6; commit after each step. |
| VII Language | ✅ | Spec, plan, code, comments and commits in English; Czech only in the String Catalog. |

Re-check after Phase 1 design: unchanged, no violations → Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/004-server-connection-buttons/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1–R11
├── data-model.md        # Phase 1: opened list, labels, places, bar items, settings
├── quickstart.md        # Phase 1: validation scenarios Q1–Q16
├── contracts/
│   └── volume-bar.md    # Core API + UI behavior contract
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/CommanderCore/
├── Network/RemoteConnections.swift   # + opened list, openedEndpoints, didChangeNotification
├── Network/ServerLabels.swift        # NEW: labels for endpoints (R4)
├── Network/ConnectionPlaces.swift    # NEW: last folder per panel and connection (R5)
└── Window/VolumeBarModel.swift       # NEW: settings, items, pressed rule (R6)

Sources/AxolotlCommander/
├── VolumeBar.swift                   # items from VolumeBarModel, server buttons with hover eject,
│                                     #   Network menu, overflow priorities, observers
├── PanelViewController.swift         # wire bar callbacks; record places; volume menu "Servers"
├── ConnectSheet.swift                # Disconnect dialog lists openedEndpoints; shared disconnect
│                                     #   helper (all windows' panels go home, places forgotten)
├── MainToolbar.swift                 # connectToServer (default) + disconnect symbols, grouping
├── SettingsView.swift                # Appearance: "Volume bar shows:" toggles
└── (new) ServerConnectionsUI.swift   # shared ConnectionPlaces instance + disconnect helper, if
                                      #   it does not fit ConnectSheet.swift

Resources/Localizable.xcstrings       # new texts (en, cs)

Tests/CommanderCoreTests/
├── VolumeBarTests.swift              # NEW: labels, places, items, pressed rule
└── RemoteTests.swift (or new file)   # opened list order, dropped session kept, disconnect
```

**Structure Decision**: The existing two-module layout. Everything that decides *what* the bar
shows and *where* a click goes is pure and lives in the core next to `Volumes` and
`RemoteConnections`; AppKit buttons, menus, hover and settings stay in the UI module.

## Implementation Notes

- **Opened list**: append in `session(for:)` after a successful connect if not present; remove in
  `disconnect` (also when `sessions` has no entry); post the notification outside of any lock.
  `disconnectAll` posts once.
- **Notification threading**: observers use `queue: .main` and `MainActor.assumeIsolated`, then
  `Task { let list = await RemoteConnections.shared.openedEndpoints; … }`.
- **Places**: `PanelViewController.modelChanged()` calls `ServerPlaces.shared.visit(remote,
  panel: ObjectIdentifier(self))` whenever `model.remote` is non-nil (the resolved path).
- **Click**: `router?.activate(side)` then `go(to: RemoteURL.make(place.endpoint, path: place.path))`;
  an empty path resolves to the login folder through the existing remote loading path.
- **Disconnect helper**: one function used by the eject control, the button menu and the F12
  dialog: disconnect each endpoint, forget places, send every panel of every
  `MainWindowController` whose `model.remote` is on it to the home folder.
- **Toolbar groups**: build the default identifiers from named groups (navigation, view, file
  tools, window layout) so inserting `connectToServer` does not shift index ranges.
- **Pressed state** is re-evaluated in `show(location:)` and after every rebuild.

## Complexity Tracking

No violations.
