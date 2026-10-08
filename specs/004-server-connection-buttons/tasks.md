# Tasks: Server Connections, iCloud Drive and Network in the Volume Bar

**Input**: Design documents from `/specs/004-server-connection-buttons/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/volume-bar.md, quickstart.md

**Tests**: Unit tests for the core (opened list, labels, places, bar items, pressed rule) are part
of the plan (constitution IV); GUI checks follow quickstart.md in the test copy only, against the
local test servers.

**Format**: `[ID] [P?] [Story] Description` — [P] = can run in parallel (different files).

## Phase 1: Setup

- [X] T001 [P] Toolbar symbols `.connectToServer: "network"`, `.disconnect: "eject"`; default identifiers built from named groups (navigation, view, file tools, window layout) instead of fixed index ranges, in Sources/AxolotlCommander/MainToolbar.swift

## Phase 2: Foundational (core, blocks all stories)

- [X] T002 Opened connections in `RemoteConnections`: ordered `opened` list (appended on the first successful session, unique, kept when a session drops, removed only by `disconnect`/`disconnectAll`, also when no session is open), `openedEndpoints`, `didChangeNotification` posted after every change, in Sources/CommanderCore/Network/RemoteConnections.swift
- [X] T003 [P] `ServerLabels.labels(for:)` (host → user@host → user@host:port with non-default port → protocol:// prefix; never a password) in Sources/CommanderCore/Network/ServerLabels.swift
- [X] T004 [P] `ConnectionPlaces<PanelID>` (`visit`, `place(for:panel:)` = this panel's last folder, else any panel's, else login folder with empty path; `forget`) in Sources/CommanderCore/Network/ConnectionPlaces.swift
- [X] T005 [P] `VolumeBarSettings` (showHome false, showICloud/showNetwork/showServers true; UserDefaults keys `volumeBar.showHome`, `volumeBar.showICloud`, `volumeBar.showNetwork`, `volumeBar.showServers`) and `VolumeBarModel.items(...)` (order: volumes, Home, iCloud Drive, Network, servers) and `pressed(...)` (remote → its server; inside iCloud → iCloud Drive; exactly home → Home; else the volume) in Sources/CommanderCore/Window/VolumeBarModel.swift
- [X] T006 Tests: opened list order, dropped session kept, disconnect without session removes it, notification posted (fake connector as in existing remote tests) in Tests/CommanderCoreTests/RemoteConnectionsListTests.swift
- [X] T007 [P] Tests: labels (unique hosts, same host other users, same user other ports, SFTP vs FTP), places (own panel, other panel, none, forget), items (each setting, iCloud missing), pressed rule (remote, iCloud vs Macintosh HD, home exact vs below, volume) in Tests/CommanderCoreTests/VolumeBarTests.swift

**Checkpoint**: `swift test` green; core API usable from the UI.

## Phase 3: User Story 1 — Connect from the toolbar (P1) 🎯 MVP part 1

**Goal**: "Connect to Server" in the default toolbar; "Disconnect" optional.

**Independent Test**: quickstart Q1–Q2.

- [X] T008 [US1] Add `.connectToServer` to the default toolbar set (file tools group) and allow `.disconnect` in Customize Toolbar; verify enabling follows `canPerform`, in Sources/AxolotlCommander/MainToolbar.swift

## Phase 4: User Story 2 — See open connections and return with one click (P1) 🎯 MVP part 2

**Goal**: Server buttons in every volume bar; click returns to the last folder.

**Independent Test**: quickstart Q3–Q6, Q9.

- [X] T009 [US2] Shared UI state: one `ConnectionPlaces` on the main actor and a disconnect helper (disconnect endpoints, forget places, every panel of every main window on them goes home) in Sources/AxolotlCommander/ServerConnectionsUI.swift
- [X] T010 [US2] `VolumeBar` renders `VolumeBarModel.items` (volume buttons as today, server buttons with network symbol, label, tooltip `protocol://user@host:port`), rebuilds on mount/unmount, `RemoteConnections.didChangeNotification` and `UserDefaults.didChangeNotification`, presses the item from `VolumeBarModel.pressed`, callbacks `onChooseVolume(URL)` / `onChooseServer(RemoteEndpoint)`, in Sources/AxolotlCommander/VolumeBar.swift
- [X] T011 [US2] Panel wiring: record `visit` in `modelChanged()` when `model.remote` is set; server click → activate panel + `go(to:)` the place; pass remote endpoint to `volumeBar.show`, in Sources/AxolotlCommander/PanelViewController.swift
- [X] T012 [US2] Disconnect dialog lists `openedEndpoints` and uses the shared disconnect helper, in Sources/AxolotlCommander/ConnectSheet.swift

**Checkpoint**: US1 + US2 = P1 complete; commit.

## Phase 5: User Story 3 — Disconnect from the button (P2)

**Independent Test**: quickstart Q7–Q8.

- [X] T013 [US3] Server button subclass: hover tracking shows an eject symbol at the trailing edge (accessibility child "Disconnect <label>"), click on it disconnects via the helper; right-click menu Open in Other Panel / Copy Address (`RemoteURL` of the place, no password) / Disconnect, in Sources/AxolotlCommander/VolumeBar.swift and Sources/AxolotlCommander/PanelViewController.swift

## Phase 6: User Story 4 — Servers in the volume menu (P2)

**Independent Test**: quickstart Q10.

- [X] T014 [US4] "Servers" section in the volume menu (⌥F1/⌥F2) with `openedEndpoints` and labels, omitted when empty; choosing = server click, in Sources/AxolotlCommander/PanelViewController.swift

## Phase 7: User Story 5 — iCloud Drive and Network (P2)

**Independent Test**: quickstart Q11–Q12.

- [X] T015 [US5] Home, iCloud Drive and Network buttons (symbols `house`, `icloud`, `network`); Network pops up a menu: mounted network volumes, servers, "Connect to Server…" (existing command for that panel), empty groups omitted, in Sources/AxolotlCommander/VolumeBar.swift and Sources/AxolotlCommander/PanelViewController.swift

## Phase 8: User Story 6 — Choose what the volume bar shows (P2)

**Independent Test**: quickstart Q13.

- [X] T016 [US6] Settings → Appearance "Volume bar shows:" with Home, iCloud Drive, Network, Server connections (`@AppStorage` with the keys and defaults of T005), in Sources/AxolotlCommander/SettingsView.swift

## Phase 9: Polish & Cross-Cutting

- [X] T017 Overflow: descending visibility priorities from first to last item so a narrow bar drops items from the end (quickstart Q14), in Sources/AxolotlCommander/VolumeBar.swift
- [X] T018 [P] Czech translations for all new strings in Resources/Localizable.xcstrings (Home, Network, Servers, Copy Address, Disconnect, Disconnect %@, Volume bar shows:, Server connections) and a test that each new key has a cs entry in Tests/CommanderCoreTests/VolumeBarTests.swift
- [X] T019 [P] README (volume bar paragraph) and CHANGELOG (Unreleased → Added)
- [ ] T020 GUI verification per quickstart.md Q1–Q16 in the test copy against the local test servers; record results at the end of this file
- [ ] T021 Mark spec Status Implemented, all tasks [X]; merge to main through a pull request; `scripts/bundle.sh release` + `scripts/install.sh` (ask first if the app runs)

## Dependencies

- T002 → T006, T009–T014. T003/T004/T005 → T007, T010. Phase 2 → all stories.
- US1 (T008) is independent of US2. US2 (T009–T012) → US3, US4, US5, US6 (all touch VolumeBar or
  PanelViewController, so run them one after another).
- Polish after the stories.

## Parallel Opportunities

- T001 with T002–T005; T003, T004, T005 together; T007 with T006; T018 with T019.

## Implementation Strategy

MVP = Phases 1–4 (toolbar button + server buttons with return to the last folder). Then US3,
US4, US5, US6, each committed on its own, then polish and GUI verification.
