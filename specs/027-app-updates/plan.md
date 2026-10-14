# Implementation Plan: App Updates

**Branch**: `027-app-updates` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (`Sources/CommanderCore/Updates/`, Foundation and Security only, unit tested):
  - `ReleaseInfo.swift` (NEW): the releases API answer → `ReleaseInfo` (version, date, page, draft,
    pre-release, assets), the asset choice (`Axolotl-Commander-X.Y.Z.zip`, `SHA256SUMS.txt`,
    `CHANGELOG.md`, `CHANGELOG.cs.md`) and `Checksums.parse` of `SHA256SUMS.txt` (R1, R2).
  - `UpdatePolicy.swift` (NEW): `UpdateState` (the settings of the feature) and the pure rules: is a check
    due (24 h after success, 1 h after failure, a time in the future counts as due), is a release offered
    automatically or on demand (newer, published, complete; skip and remind-later only for the automatic
    check) (R3).
  - `UpdateInstaller.swift` (NEW): the steps after the download — checksum (CryptoKit SHA-256), unpack
    (`ditto`), find the one app, check identifier and version, check the signature through an injected
    `UpdateVerifier`, then replace: the old app to the Trash, the new one into its place, roll back on
    failure (R4, R5). `CodeSignatureVerifier`: the real verifier with the Security framework (the new app
    must satisfy the running app's designated requirement), plus `InstallCapability` (why this app cannot
    install itself: development/ad-hoc build, translocated, read-only volume, folder not writable) (R6).
  - `UpdateNotes` (in `UpdatePolicy.swift`): the versions newer than the running one up to the offered one
    from the release's changelogs, localized with `ReleaseNotes.localized` (spec 026).
- **UI** (`Sources/AxolotlCommander/`):
  - `Updates.swift` (NEW): `UpdateChecker` — the one request (`URLSession`, ephemeral, no cookies, plain
    `User-Agent`), the hourly timer, the start check a few seconds after the main window, the single-copy
    rule (R7), the results remembered in `UserDefaults`; `UpdateDownloader` — the download with progress and
    Cancel into the installer's temporary folder.
  - `UpdateWindow.swift` (NEW): the update window (versions, date, notes in a web view shared with What's
    New, Install and Relaunch / Download…, Remind Me Later, Skip This Version, the checkbox), the progress
    state, the messages for "latest" and "failed"; relaunch through a small detached shell that waits for
    the old process (R5).
  - `WhatsNewWindow.swift`: the notes web view factored out for reuse (`NotesWebView`).
  - `Command.swift`: `checkForUpdates` ("Check for Updates…", app menu after About, app scope);
    `AppDelegate.swift`: runs it, starts the checker; `AboutWindow.swift`: the status line, Install…, Check
    Now; `SettingsView.swift`: the option, the last result, Check Now (General).
  - `AppSettingsCatalog.swift`: `updates.automatic` exported; the state keys and the hidden
    `updates.feedURL` not exported.
- **Release workflow** (`.github/workflows/release.yml`): checks `scripts/changelog-cs-missing.sh X.Y.Z`
  before the build, writes the release description from the version's sections of both changelogs
  (`scripts/release-notes.sh`, NEW), attaches `CHANGELOG.md` and `CHANGELOG.cs.md` (R8).
  `docs/RELEASING.md` updated. The pull request check of the Czech notes is already in CI (commit cde2280).
- Czech strings; `CHANGELOG.md` and `CHANGELOG.cs.md` entries under 0.6.0.

## Technical Context

- Swift 6.2 (strict concurrency), AppKit, WebKit, Foundation `URLSession`, CryptoKit, Security
  (`SecStaticCode`), `/usr/bin/ditto`; Swift Testing; macOS 15+. No new dependencies.
- **Network**: `GET https://api.github.com/repos/axolotlcommander/axolotl-commander/releases/latest`, then on
  consent the asset downloads from the release (`browser_download_url`, HTTPS, redirects to GitHub's
  storage). An ephemeral session: no cookies, no cache, no credentials.
- **Storage**: `UserDefaults` keys under `updates.`; the download and unpacking in an
  `itemReplacementDirectory` on the app's volume (same-volume moves); removed on success, failure, Cancel
  and quit.
- **Performance**: the check is one small request off the main thread; the download streams to disk.
- **Constraints**: FR-005 (nothing about the user sent), FR-011 (no install while operations run), FR-013
  (only the app bundle, its Trash entry and the temporary folder are touched).

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ The installer touches only the running app bundle (with the user's consent), the old bundle in the Trash and its own temporary folder; any failure rolls back; unit tests use fake bundles and copies of system apps in temporary folders; the GUI check never installs over the installed app. |
| II Reference | ✅ Check rules, buttons, About status and silence on failure follow the reference; self-install and in-window notes are recorded deviations agreed with the maintainer. |
| III Native macOS | ✅ "Check for Updates…" in the app menu, a normal non-blocking window, Trash for the old app, String Catalog. |
| IV Testable core | ✅ Parsing, policy, checksums and installer steps in the core with an injected verifier and file locations. |
| V Clean-room / GPL | ✅ Own implementation from the help's behavior; no update framework added. |
| VI Incremental | ✅ Core → check & window → install → About/Settings → workflow, each committed. |
| VII Language | ✅ Code and docs in English, texts localized, Czech notes per constitution 1.2.0. |

## Project Structure

```text
specs/027-app-updates/{plan,research,data-model,quickstart}.md, contracts/release.md

Sources/CommanderCore/Updates/ReleaseInfo.swift        NEW
Sources/CommanderCore/Updates/UpdatePolicy.swift       NEW
Sources/CommanderCore/Updates/UpdateInstaller.swift    NEW
Tests/CommanderCoreTests/UpdateTests.swift             NEW
Tests/CommanderCoreTests/UpdateInstallerTests.swift    NEW
Sources/AxolotlCommander/Updates.swift                 NEW (checker, downloader)
Sources/AxolotlCommander/UpdateWindow.swift            NEW
Sources/AxolotlCommander/WhatsNewWindow.swift          NotesWebView shared
Sources/AxolotlCommander/AboutWindow.swift             status, Check Now
Sources/AxolotlCommander/SettingsView.swift            option, last result, Check Now
Sources/AxolotlCommander/AppDelegate.swift             command, start
Sources/CommanderCore/Command.swift                    checkForUpdates
Sources/CommanderCore/Settings/AppSettingsCatalog.swift keys
scripts/release-notes.sh                               NEW
.github/workflows/release.yml                          check, description, assets
docs/RELEASING.md                                      procedure
Resources/Localizable.xcstrings                        Czech strings
```

## Complexity Tracking

None. The relaunch helper is a one-line shell command, not a separate executable.
