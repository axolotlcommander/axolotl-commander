# Research: App Updates

## R1 — Where the app learns about releases

- **Decision**: `GET /repos/axolotlcommander/axolotl-commander/releases/latest` on `api.github.com` with
  `Accept: application/vnd.github+json` and `User-Agent: AxolotlCommander` (GitHub requires one; no version).
  This endpoint returns the newest published release and never a draft or a pre-release; the app still
  checks the `draft` and `prerelease` flags. The tag `vX.Y.Z` is parsed with `AppVersion` (spec 026).
  HTTP 403/429 (rate limit), other non-2xx, a body that does not decode, or a tag that is not a version →
  a failed check with a reason.
- **Rationale**: One request, no account, already where releases are published; the reference does the
  same.
- **Alternatives**: an appcast file in the repository (another file to keep in step); the list endpoint
  (more data, has to filter drafts the API hides anyway from anonymous users).

## R2 — Which files a release must have

- **Decision**: `Axolotl-Commander-X.Y.Z.zip` (X.Y.Z = the tag's version) and `SHA256SUMS.txt` are
  required; `CHANGELOG.md` and `CHANGELOG.cs.md` are optional (no notes without them). `SHA256SUMS.txt`
  lines are `<64 hex>  <file name>` (shasum format, also `*name`); the zip's line gives the expected hash.
  Asset URLs must be HTTPS. See [contracts/release.md](contracts/release.md).
- **Rationale**: The names the release workflow already produces; the checksum file is published next to
  the zip by the same workflow run.
- **Alternatives**: the API's per-asset `digest` field (newer, not on older releases; can be added later).

## R3 — Schedule and offer rules

- **Decision**: State in `UserDefaults`: `updates.automatic` (Bool, default true), `updates.lastCheck`
  (Date of the last attempt), `updates.lastSuccess` (Date), `updates.lastResult`
  (`upToDate`/`available`/`failed`), `updates.availableVersion`, `updates.skippedVersion`,
  `updates.remindAfter` (Date). A check is due when automatic is on and: never checked; or the last attempt
  failed and is ≥ 1 h old; or the last success is ≥ 24 h old; a time in the future counts as due (clock moved
  back). The timer re-evaluates every 15 minutes; the start check runs 5 s after the main window. The
  automatic check offers a release only when it is newer than the running version, not the skipped
  version, and `remindAfter` has passed; a manual check offers any newer release.
- **Rationale**: Pure rules that unit tests can drive with a fixed "now".

## R4 — Download and verification

- **Decision**: `URLSession` (ephemeral) download task with progress into the installer's work folder; then
  SHA-256 with CryptoKit streaming in 1 MB chunks against the expected hash; `ditto -x -k` into
  `work/unpacked`; exactly one top-level `*.app` (ignore `__MACOSX`); `Info.plist` bundle identifier equal to
  the running app's, `CFBundleShortVersionString` equal to the release version; then the signature check.
  The work folder is `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
  appropriateFor: appURL, create: true)` — on the app's volume, so the final moves are renames.
- **Rationale**: No quarantine attribute is set by `URLSession` for a non-sandboxed app, so Gatekeeper does
  not prompt for the replaced app; the signature check gives the trust instead.

## R5 — Replacing and relaunching

- **Decision**: After all checks: (1) move the running app to the Trash (`FileManager.trashItem`, keeps
  its name there); (2) move the new app to the original URL; (3) on failure of (2) move the old app back
  from the Trash URL; on failure of (1) stop with the old app untouched. A running app's bundle can be moved;
  the process keeps its open files. Relaunch: start `/bin/sh -c 'while kill -0 PID 2>/dev/null; do sleep
  0.2; done; open "$APP"'` detached, then `NSApp.terminate`. If the user cancels termination (a
  confirmation of running operations), the new app is already in place and starts at the next launch.
- **Rationale**: The Trash keeps a way back as the spec asks; no helper executable to sign.
- **Alternatives**: `replaceItemAt` (deletes the original, no Trash); a helper tool replacing after exit
  (more parts, the same result).

## R6 — When the app cannot install itself

- **Decision**: `InstallCapability.check(appURL:)` returns a reason, in this order: not a bundle
  (development run); the running code is ad-hoc signed or unsigned (`SecCodeCopySigningInformation` flags);
  the path is translocated (`/AppTranslocation/`); the volume is read-only; the app or its parent folder is
  not writable by the user. The signature mismatch is found only after the download (R4) and gives the
  same manual path with its own reason. `CodeSignatureVerifier` uses `SecStaticCodeCreateWithPath` +
  `SecStaticCodeCheckValidity` with the requirement from `SecCodeCopyDesignatedRequirement` of the running
  code (`SecCodeCopySelf`), flags `kSecCSCheckAllArchitectures | kSecCSStrictValidate`.
- **Rationale**: An ad-hoc requirement names one exact build, so it could never accept a new one; telling it
  before the download saves the user a useless download.
- **Testing**: Unit tests run the real verifier on copies of system apps in a temporary folder (a copy
  satisfies its own requirement, another app does not, a modified copy fails); the installer steps run on
  fake bundles with an injected verifier.

## R7 — One running copy

- **Decision**: Before a check the app writes `updates.lastCheck` (shared through the user defaults by all
  copies), like spec 026 writes the last run version first; another copy finds the check not due. Every copy
  shows the title-bar button from the remembered result (`updates.availableVersion`); a click on it in a copy
  that has not fetched the release runs the manual check, which opens the window.

## R10 — Showing a found update without a window (clarification 2026-10-14)

- **Decision**: An `NSTitlebarAccessoryViewController` with `layoutAttribute = .trailing` on the main window
  holds a small rounded button "↑ Version X.Y.Z" (accent tint). It is visible while `updates.availableVersion`
  is newer than the running version, not skipped, and `updates.remindAfter` has passed; the controller posts
  a notification on every change of the state and the button follows it. The menu item stays "Check for
  Updates…"; with a fetched release it opens the window without a new request.
- **Rationale**: The maintainer asked for no pop-up; the title bar is visible in every layout (the bottom
  bars can be hidden) and the accessory takes no focus.
- **Alternatives**: a text in the bottom bar (hidden together with it); only the menu and About (easy to
  miss); a window (the original plan, rejected as intrusive).

## R8 — Release notes in both languages with every release

- **Decision**: `scripts/release-notes.sh X.Y.Z` prints the version's section of `CHANGELOG.md`, then a
  `## Česky` heading and the section of `CHANGELOG.cs.md`. The release workflow runs
  `scripts/changelog-cs-missing.sh X.Y.Z` first (fails before building when the Czech notes are missing),
  passes the notes (after `.github/release-install.md` for builds that are not notarized) with
  `--notes-file` instead of `--generate-notes`, and uploads both changelogs. The translation itself is made
  in each pull request by the agent (skill `changelog-cs`, CI check).
- **Rationale**: Nothing to write at release time; the app reads the notes of a release from its own
  changelog files, which cover every version up to it.

## R9 — GUI check without the real server

- **Decision**: The hidden setting `updates.feedURL` (not exported, not in Settings) replaces the API URL.
  The GUI check runs a small HTTP server from the session's scratchpad on 127.0.0.1 (not port 8765) serving
  a JSON answer and the assets. If App Transport Security refuses plain HTTP to 127.0.0.1, the bundle gets
  `NSAppTransportSecurity → NSAllowsLocalNetworking` (local addresses only).
- **Addendum (implementation)**: the release parser accepts HTTPS addresses and plain HTTP only to this Mac
  (`127.0.0.1`, `localhost`, `::1`), so the local server can serve the assets; any other HTTP address makes
  the release incomplete.
