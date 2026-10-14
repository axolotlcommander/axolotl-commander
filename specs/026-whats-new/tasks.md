# Tasks: What's New Window

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md), [research.md](research.md),
[quickstart.md](quickstart.md). Tests are requested by the spec (SC-004).

## Phase 1: Foundational (core)

- [X] T001 Tests first in `Tests/CommanderCoreTests/ReleaseNotesTests.swift` (NEW, SPDX header): `AppVersion`
  parse (`0.6.0`, `v0.6.0`, `[0.6.0]`, garbage → nil) and compare (0.10.0 > 0.9.9); `ReleaseNotes.parse`
  (headings with and without brackets or date, Unreleased and the preamble dropped, body kept, newest
  first, a repeated version keeps the first); `ReleaseNotes.markdown`; `WhatsNewStart.decide` (update,
  versions skipped, same version, downgrade, first start, garbage remembered value, empty range).
- [X] T002 `AppVersion`, `ReleaseNote`, `ReleaseNotes`, `WhatsNewStart` in
  `Sources/CommanderCore/Updates/ReleaseNotes.swift` (NEW, SPDX header) until T001 passes (research R1–R4).
- [X] T003 [P] `app.lastRunVersion` listed in `SettingsCatalog.notExported` in
  `Sources/CommanderCore/Settings/AppSettingsCatalog.swift`; command `whatsNew` ("What's New…", Help menu,
  app scope) in `Sources/CommanderCore/Command.swift`.

**Checkpoint**: build without warnings, `swift test` green, commit.

## Phase 2: User Stories 1–3 — the window, after an update and on demand (P1, P2)

- [X] T004 [US1] `WhatsNewWindow.swift` (NEW): one `NSWindowController` with a web view of
  `MarkdownRenderer.render(ReleaseNotes.markdown(...))` (non-persistent data store, no JavaScript, links to
  `NSWorkspace`), Close button (Return), Esc and ⌘W, frame autosave; `WhatsNew.show(notes:)`, `show()` (all
  versions) and `showAfterStart()` (reads the bundled `CHANGELOG.md`, `WhatsNewStart.decide`, writes the
  setting first, waits while a modal window or sheet is up) (R5).
- [X] T005 [US2] `AboutWindow.swift` (NEW): icon, name, version, credits (Credits.html as attributed text with
  links), copyright, "What's New…" button (R6); `AppDelegate.swift`: `.about` opens it, `.whatsNew` runs
  `WhatsNew.show()`, `showAfterStart()` after the main window appears.
- [X] T006 [US2] "What's New…" button in the General section of `Sources/AxolotlCommander/SettingsView.swift`.
- [X] T007 `scripts/bundle.sh` copies `CHANGELOG.md` into `Contents/Resources` (FR-011).
- [X] T008 [US3] Light/dark check of the page, text selection and ⌘C (given by the renderer and web view).

**Checkpoint**: build, tests, commit.

## Phase 3: Polish

- [X] T009 Czech strings in `Resources/Localizable.xcstrings` (What's New…, the window title, Close, "No
  release notes are available.", the About window texts).
- [X] T010 `CHANGELOG.md` entry under 0.6.0 (Added); no version bump.
- [X] T011 GUI check: quickstart steps 1–9 on the test copy; spec Status → Implemented; `docs/STATE.md`.

## GUI check (2026-10-14, test copy)

- `app.lastRunVersion` = 0.4.2 → a second after the main window the window showed 0.6.0 and 0.5.0 (the
  changelog has no 0.4.3), newest first; Esc closed it; the next start showed nothing and the setting was
  0.6.0.
- Help → What's New…, the About link and the Settings button opened every version (0.6.0 … 0.2.0); asking
  again kept one window; ⌘W and the Close button closed it; Esc closed the About window.
- The Close button sat on the window edge in a stack view → plain constraints. The General tab was taller
  than the window (the tabs were partly under the title bar, the last description cut) → the panel options
  have their own Panels tab, General and Panels scroll when taller than the window, and the button is at the
  right end of the Export / Import row. All eight tabs checked by screenshot.
- Not tried in the GUI: ⌘C (it would overwrite the user's clipboard) and dark appearance (not switched for
  the whole Mac); both come from the viewer's web view and renderer (spec 019).

## Dependencies

- T001 → T002 → T004–T006. T003 [P] next to T001/T002. T007 before T011.
