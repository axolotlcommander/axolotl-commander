# Tasks: App Updates

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/release.md](contracts/release.md), [quickstart.md](quickstart.md)

## Phase 1: Core (blocking)

- [X] T001 [P] `Sources/CommanderCore/Updates/ReleaseInfo.swift`: decode the API answer into `ReleaseInfo`
  (contract), the asset choice by name, HTTPS only; `Checksums.parse` (R1, R2).
- [X] T002 [P] `Sources/CommanderCore/Updates/UpdatePolicy.swift`: `UpdateState` keys and load/save on
  `UserDefaults`; `isDue(now:)`, `offer(_:running:manual:now:)`, `remindLater(now:)`, `skip(_:)`;
  `UpdateNotes.notes(english:czech:running:offered:language:)` with `ReleaseNotes.localized` (R3).
- [X] T003 `Sources/CommanderCore/Updates/UpdateInstaller.swift`: `UpdateVerifier` protocol,
  `CodeSignatureVerifier`, `InstallCapability.check`, `UpdateInstaller.verify` (checksum, unpack, one app,
  identifier, version, signature) and `replace` (Trash, move, roll back), work folder cleanup (R4–R6).
- [X] T004 [P] `Tests/CommanderCoreTests/UpdateTests.swift`: answer parsing (complete, draft, pre-release,
  bad tag, missing assets, http asset, malformed JSON), checksum parsing, `isDue` (never, 23 h/25 h after
  success, 59 min/61 min after failure, future time), offer rules (newer/equal/older, skipped, remind,
  manual), notes range and localization.
- [X] T005 `Tests/CommanderCoreTests/UpdateInstallerTests.swift`: fake bundles in a temporary folder with an
  injected verifier — success (new in place, old in Trash-like folder), checksum mismatch, two apps in the
  archive, wrong identifier, wrong version, verifier refusal, move failure → roll back; the real verifier
  on copies of system apps (own requirement accepted, another app refused).
- [X] T006 `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`: `updates.automatic` exported, the other
  `updates.*` keys not exported.

**Checkpoint**: `swift test` green, commit.

## Phase 2: US1 + US3 — check and update window (P1)

- [X] T007 [US1] `Sources/AxolotlCommander/Updates.swift`: `UpdateChecker` (ephemeral session, the request,
  the start check 5 s after the main window, the 15-minute timer, writing `lastCheck` first, results
  saved), manual check with progress and Cancel, "latest" / "failed" messages with Try Again.
- [X] T008 [US1] `Sources/AxolotlCommander/WhatsNewWindow.swift`: `NotesWebView` factored out (the web view
  configuration and the link policy) and used by What's New.
- [X] T009 [US1] `Sources/AxolotlCommander/UpdateWindow.swift`: the window (title, versions, date, notes,
  buttons, checkbox, Esc = Remind Me Later), one window at a time, Download… with the reason when
  `InstallCapability` says manual.
- [X] T021 [US1] Title-bar button "↑ Version X.Y.Z" on the main window (R10, clarification 2026-10-14): shown
  from the remembered result, hidden by Remind Me Later (24 h) and Skip This Version; a click opens the update
  window; the automatic check opens no window.
- [X] T010 [US3] `Sources/CommanderCore/Command.swift` `checkForUpdates` in the app menu after About;
  `Sources/AxolotlCommander/AppDelegate.swift` canPerform/perform and the checker start.

## Phase 3: US2 — download, verify, install, relaunch (P1)

- [X] T011 [US2] `UpdateDownloader` in `Sources/AxolotlCommander/Updates.swift`: download of the checksum file,
  the changelogs and the zip with progress and Cancel; quit cancels and removes the work folder.
- [X] T012 [US2] `Sources/AxolotlCommander/UpdateWindow.swift`: Install and Relaunch → wait while file
  operations run (message, install when they finish or later) → download → `UpdateInstaller` → relaunch
  (R5); any failure → message and Download….

## Phase 4: US4 + US5 — later/skip, Settings and About (P2)

- [X] T013 [US4] Remind Me Later, Skip This Version and the checkbox wired to `UpdateState`.
- [X] T014 [US5] `Sources/AxolotlCommander/SettingsView.swift` General: "Check for updates automatically",
  the last result with its date, Check Now (the tab scrolls).
- [X] T015 [US5] `Sources/AxolotlCommander/AboutWindow.swift`: status line (available with Install… / up to
  date with the date / never checked) and Check Now; no request on open.

## Phase 5: US6 — release notes with every release (P2)

- [X] T016 [US6] `scripts/release-notes.sh` (NEW): the version's sections of both changelogs as the release
  description (R8).
- [X] T017 [US6] `.github/workflows/release.yml`: the Czech check before the build, the description from
  `scripts/release-notes.sh` (after the install steps when not notarized) instead of generated notes,
  `CHANGELOG.md` and `CHANGELOG.cs.md` as assets; `docs/RELEASING.md` updated.

## Phase 6: Polish

- [ ] T018 Czech strings in `Resources/Localizable.xcstrings`.
- [ ] T019 `CHANGELOG.md` and `CHANGELOG.cs.md` entries under 0.6.0 (skill `changelog-cs`).
- [ ] T020 GUI check: quickstart steps 1–9 on the test copy with the local server; spec Status → Implemented;
  `docs/STATE.md`.

## Dependencies

- T001–T003 before T007–T015; T004/T005 next to their code. T008 before T009. T011 before T012.
  T016 before T017. T018–T020 last.
- MVP: Phases 1–2 (the check and the window with Download…); Phase 3 adds self-install.
