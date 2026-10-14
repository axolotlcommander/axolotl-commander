# Implementation Plan: What's New Window

**Branch**: `026-whats-new` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (pure, tested; `Sources/CommanderCore/Updates/ReleaseNotes.swift`, NEW):
  - `AppVersion`: a semantic version (`X.Y.Z`, an optional leading `v`), comparable by numbers (R1).
  - `ReleaseNotes.parse(_:)`: the Keep a Changelog text → `[ReleaseNote]` (version, date, body), the
    "Unreleased" section dropped, newest first (R2).
  - `ReleaseNotes.markdown(_:)`: the notes → one Markdown page with a heading per version (R3).
  - `WhatsNewStart.decide(lastRun:running:notes:)`: what to show at a start and the version to remember
    (FR-002, FR-003) (R4).
- **UI** (`Sources/AxolotlCommander/`):
  - `WhatsNewWindow.swift` (NEW): one window with a web view of the rendered page (scripts off, nothing
    remote, links to the browser), a Close button, Esc / ⌘W, size remembered (R5); `WhatsNew.showAfterStart()`
    and `WhatsNew.show()`.
  - `AboutWindow.swift` (NEW): an About window of our own with the icon, name, version, credits, copyright
    and a "What's New…" button — the standard panel cannot run an action from its credits (R6).
  - `Command.swift`: `whatsNew` ("What's New…") in the Help menu, app scope; `AppDelegate.swift`: runs it,
    opens the new About window, calls `showAfterStart()` after the main window appears.
  - `SettingsView.swift`: a "What's New…" button in General; `AppSettingsCatalog.swift`: the last run version
    is local, not exported.
  - `scripts/bundle.sh`: copies `CHANGELOG.md` into `Contents/Resources` (FR-011).
  - Czech strings; `CHANGELOG.md` entry under 0.6.0.

## Technical Context

- Swift 6.2 (strict concurrency), AppKit, WebKit (already used by the viewer), Swift Testing; macOS 15+.
  The existing `MarkdownRenderer` (spec 019) makes the HTML with a policy that blocks scripts and remote
  content (FR-007).
- **Performance**: SC-003 (100 versions in under 0.5 s): one parse and one render of a few hundred kB.
- **Constraints**: no network (FR-007); the setting `app.lastRunVersion` is written at every start
  (FR-001).

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Reads a file inside the app bundle; writes only its own setting. |
| II Reference | ✅ The reference has a static "What's New" help page only; the window after an update is a recorded, agreed addition. |
| III Native macOS | ✅ A normal window, system appearance, String Catalog, keyboard close. |
| IV Testable core | ✅ Parsing, comparison and the start decision in the core with unit tests. |
| V Clean-room | ✅ Behavior from the reference help and common macOS practice. |
| VI Incremental | ✅ US1 (after an update) → US2 (on demand) → US3 (formatting, mostly given by the renderer). |
| VII Language | ✅ Notes in English, the window localized. |

## Project Structure

```text
specs/026-whats-new/{plan,research,data-model,quickstart}.md

Sources/CommanderCore/Updates/ReleaseNotes.swift        NEW
Tests/CommanderCoreTests/ReleaseNotesTests.swift        NEW
Sources/AxolotlCommander/WhatsNewWindow.swift           NEW
Sources/AxolotlCommander/AboutWindow.swift              NEW
Sources/CommanderCore/Command.swift                     whatsNew
Sources/CommanderCore/Settings/AppSettingsCatalog.swift lastRunVersion not exported
Sources/AxolotlCommander/AppDelegate.swift              about, whatsNew, start
Sources/AxolotlCommander/SettingsView.swift             button
scripts/bundle.sh                                       CHANGELOG.md into Resources
Resources/Localizable.xcstrings                         Czech strings
```

## Complexity Tracking

None.
