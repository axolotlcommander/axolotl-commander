# Tasks: What's New Window

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md), [research.md](research.md),
[quickstart.md](quickstart.md). Tests are requested by the spec (SC-004).

## Phase 1: Foundational (core)

- [ ] T001 Tests first in `Tests/CommanderCoreTests/ReleaseNotesTests.swift` (NEW, SPDX header): `AppVersion`
  parse (`0.6.0`, `v0.6.0`, `[0.6.0]`, garbage → nil) and compare (0.10.0 > 0.9.9); `ReleaseNotes.parse`
  (headings with and without brackets or date, Unreleased and the preamble dropped, body kept, newest
  first, a repeated version keeps the first); `ReleaseNotes.markdown`; `WhatsNewStart.decide` (update,
  versions skipped, same version, downgrade, first start, garbage remembered value, empty range).
- [ ] T002 `AppVersion`, `ReleaseNote`, `ReleaseNotes`, `WhatsNewStart` in
  `Sources/CommanderCore/Updates/ReleaseNotes.swift` (NEW, SPDX header) until T001 passes (research R1–R4).
- [ ] T003 [P] `app.lastRunVersion` listed in `SettingsCatalog.notExported` in
  `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`; command `whatsNew` ("What's New…", Help menu,
  app scope) in `Sources/CommanderCore/Command.swift`.

**Checkpoint**: build without warnings, `swift test` green, commit.

## Phase 2: User Stories 1–3 — the window, after an update and on demand (P1, P2)

- [ ] T004 [US1] `WhatsNewWindow.swift` (NEW): one `NSWindowController` with a web view of
  `MarkdownRenderer.render(ReleaseNotes.markdown(...))` (non-persistent data store, no JavaScript, links to
  `NSWorkspace`), Close button (Return), Esc and ⌘W, frame autosave; `WhatsNew.show(notes:)`, `show()` (all
  versions) and `showAfterStart()` (reads the bundled `CHANGELOG.md`, `WhatsNewStart.decide`, writes the
  setting first, waits while a modal window or sheet is up) (R5).
- [ ] T005 [US2] `AboutWindow.swift` (NEW): icon, name, version, credits (Credits.html as attributed text with
  links), copyright, "What's New…" button (R6); `AppDelegate.swift`: `.about` opens it, `.whatsNew` runs
  `WhatsNew.show()`, `showAfterStart()` after the main window appears.
- [ ] T006 [US2] "What's New…" button in the General section of `Sources/AxolotlCommander/SettingsView.swift`.
- [ ] T007 `scripts/bundle.sh` copies `CHANGELOG.md` into `Contents/Resources` (FR-011).
- [ ] T008 [US3] Light/dark check of the page, text selection and ⌘C (given by the renderer and web view).

**Checkpoint**: build, tests, commit.

## Phase 3: Polish

- [ ] T009 Czech strings in `Resources/Localizable.xcstrings` (What's New…, the window title, Close, "No
  release notes are available.", the About window texts).
- [ ] T010 `CHANGELOG.md` entry under 0.6.0 (Added); no version bump.
- [ ] T011 GUI check: quickstart steps 1–9 on the test copy; spec Status → Implemented; `docs/STATE.md`.

## Dependencies

- T001 → T002 → T004–T006. T003 [P] next to T001/T002. T007 before T011.
