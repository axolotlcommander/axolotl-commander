# Tasks: Volumes in the Go Menu and Ejecting Volumes

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md),
[research.md](research.md), [quickstart.md](quickstart.md). Tests are requested by the spec (SC-006).

## Phase 1: Foundational (core)

- [ ] T001 [P] `VolumeInfo.isEjectable`, `isRootFileSystem`, `wholeDisk` (defaults `false`, `false`,
  `nil`) filled by `Volumes.mounted()` in `Sources/CommanderCore/Volumes.swift` (whole disk via
  DiskArbitration); `Ejectability.canEject` and `otherVolumes(onDiskOf:in:)` in
  `Sources/CommanderCore/Volumes/Ejectability.swift`; tests in
  `Tests/CommanderCoreTests/VolumeEjectTests.swift` (startup disk, internal, removable, external, disk
  image, network, two partitions of one disk).
- [ ] T002 `EjectTarget.resolve` and `title(for:)` in `Sources/CommanderCore/Volumes/EjectTarget.swift`;
  tests (local volume, archive on a volume, search results root, server, Network, startup disk,
  non-ejectable internal volume, names with quotes and emoji).
- [ ] T003 [P] `DisconnectList` in `Sources/CommanderCore/Volumes/DisconnectList.swift`; tests in
  `Tests/CommanderCoreTests/DisconnectListTests.swift` (sections, empty sections left out, pre-check,
  confirm title, enabled).
- [ ] T004 [P] `VolumeUse.blocking` / `isOnVolume` in `Sources/CommanderCore/Volumes/VolumeUse.swift`
  ("/Volumes/A" vs "/Volumes/AB", the root itself, standardized paths); `TabList.redirect(where:to:)` in
  `Sources/CommanderCore/Window/TabList.swift` (active tab untouched, history kept); tests in
  `VolumeEjectTests.swift`.

**Checkpoint**: `swift test` green, build without warnings, commit.

## Phase 2: User Story 2 — volume pickers in the Go menu (P1)

- [ ] T005 [US2] Remove `MenuID.left` / `.right`; `.leftVolumeMenu` / `.rightVolumeMenu` in `.go` as
  "Left Volume…" / "Right Volume…" (same chords, separator before) in
  `Sources/CommanderCore/Command.swift`; `MainMenuBuilder` titles and `contextMenus`,
  `KeyboardSettings` sections; Czech strings.

**Checkpoint**: menu bar without Left/Right; commit.

## Phase 3: User Story 1 — ⌘E with the safety path (P1)

- [ ] T006 [US1] `OperationState.urls` set at every creation site (`OperationsController`,
  `ArchiveOperations`, `RemoteOperations`, `Rename/RenameSheets`); a `VolumeUsers` list for Find and the
  occupied-space calculation.
- [ ] T007 [US1] `VolumeEjector` in `Sources/AxolotlCommander/VolumeEjector.swift`: refusal message,
  partition question, panels and tabs of all windows home with watchers stopped, eject off the main
  thread, busy mark, the system's reason on failure; servers through `ServerConnectionsUI.disconnect`,
  which now also redirects inactive tabs.
- [ ] T008 [US1] `Command.ejectVolume` (⌘E, `.commands`, after `.disconnect`) with the dynamic title in
  `MainWindowController.validateMenuItem` and enablement from `EjectTarget` in
  `PanelViewController`; Czech strings.

**Checkpoint**: quickstart "⌘E" passes; commit.

## Phase 4: User Story 3 — volume bar (P1)

- [ ] T009 [US3] `EjectableButton` (hover ⏏, busy spinner) for server buttons and ejectable volume
  buttons; context menu on volume buttons (Eject “X” / Volume Information…) in
  `Sources/AxolotlCommander/VolumeBar.swift`.

**Checkpoint**: quickstart "Volume bar" passes; commit.

## Phase 5: User Story 4 — F12 lists everything (P2)

- [ ] T010 [US4] AppKit `DisconnectSheet` in `Sources/AxolotlCommander/DisconnectSheet.swift` (replaces
  the SwiftUI one in `ConnectSheet.swift`): sections, checkboxes, Space / Return / Esc, refresh on mount
  changes, one failure message; `.disconnect` enabled by `DisconnectList.isEnabled`.

**Checkpoint**: quickstart "F12" passes; commit.

## Phase 6: Polish

- [ ] T011 Czech strings complete; CHANGELOG (Unreleased); spec status. Build without warnings,
  `swift test` green, commit.
- [ ] T012 GUI check on the test copy following quickstart.md (only the scratch disk image is
  ejected); record the result here.

## Dependencies

- T001 → T002 → T008; T003 → T010; T004 → T007.
- T005 is independent. T006 → T007 → T008, T009, T010.

## Parallel opportunities

- T001, T003, T004 are separate core files with their own tests; T005 can run beside them.

## Implementation strategy

- MVP: Phases 1–3 (menus and ⌘E with the safety path). Then the bar (4), then F12 (5).
