# Feature Specification: App Updates

**Feature Branch**: `027-app-updates`

**Created**: 2026-10-14

**Status**: Implemented

**Input**: User description: "Updates: the app checks once a day whether a newer published release exists,
offers it with its release notes, and on the user's consent downloads, verifies and installs it and
relaunches; after the relaunch the What's New window (spec 026) shows the notes once." Agreed with the
maintainer in chat on 2026-10-14: check once a day, can be turned off in Settings, the app downloads and
updates itself, offers the update with the notes, reachable from the menu, About and Settings ("zvaž
specifikace jak doporučuješ a pusť se do toho rovnou"); and "the changelog in both languages must be made
automatically with every release".

## Context

Releases are built by the project's release workflow from a version tag: an app archive
(`Axolotl-Commander-X.Y.Z.zip`), a disk image and a checksum file (`SHA256SUMS.txt`). The workflow creates a
draft that the maintainer publishes by hand. The app is signed with the project's own stable certificate
(with a Developer ID and notarization when those are configured); development builds and the GUI test copy
are signed ad hoc. The release notes live in `CHANGELOG.md` and its Czech translation `CHANGELOG.cs.md`; the
What's New window (spec 026) shows them from the copies bundled into the app, in the app's language, once
after an update.

Today users learn about a new version only from the project page and update by hand.

Reference behavior (the reference program's help on checking for a new version):

- Help → Check for New Version; on demand it always answers: a new-version window, "you have the latest
  version", or why the check failed; Cancel while it is slow.
- An automatic check at start-up, on by default, at most once per 24 hours; after an unreachable server at
  most once an hour; in the background and silent on failure. The option is in the general configuration.
- One request to the release server; nothing about the user is sent; only published releases with an
  installer, never pre-releases.
- The window shows the running version, the new version and its date, with Download (opens the installer in
  the browser — the reference installs nothing itself), Remind Me Later (not before the next day; Esc does
  the same), Skip This Version (a still newer one is announced), Release Notes (in the browser) and a
  checkbox for the automatic check. It does not block the program; several running copies show it once.
- The About window shows the last result (an update / up to date with the date of the check / never
  checked with "Check Now"); opening About does not contact the server.

Deliberate deviations: this app downloads, verifies and installs the update itself and shows the notes
inside its window in the app's language; the release notes in both languages are produced by the release
workflow from the changelogs, not written by hand at release time.

This spec is part of release 0.6.0 (specs 024–027); the version is already raised on the branch it builds
on, so its pull request adds only changelog entries.

## Clarifications

### Session 2026-10-14

- Q: How often and when? → A: At most once a day, a few seconds after the start and while the app keeps
  running; after a failure at most once an hour. On by default; turned off in Settings → General.
- Q: Does the app install the update itself? → A: Yes, after the user agrees in the update window: download,
  verify, replace, relaunch. When that is not possible it offers the manual download and says why.
- Q: Where is it reachable? → A: "Check for Updates…" in the app menu; Settings → General (option, last
  result, Check Now); the About window (last result, Check Now).
- Q: Which notes does the update window show? → A: The notes of every version newer than the running one up
  to the offered one, from the changelogs published with that release, in the app's language (English for a
  version without a translation). After the relaunch What's New shows them once more (spec 026).
- Q: Does the automatic check open a window? (added during implementation, 2026-10-14) → A: No. It shows
  an unobtrusive button "↑ Version X.Y.Z" at the right end of the main window's title bar; it takes no focus
  and opens nothing. A click on it, or "Check for Updates…", opens the update window. Remind Me Later hides
  the button until the next day, Skip This Version hides it for that version. The manual check opens the
  window at once as before.
- Q: How are the notes in both languages made for a release? → A: Automatically by the release workflow
  from the two changelogs (the release description and the attached changelog files); the workflow stops
  before creating the release when either changelog has no notes for the version. Each pull request adds its
  entries to both changelogs: the agent writes the Czech translation automatically while it prepares the pull
  request (a project skill), and the pull request checks fail without it (project rule in `CLAUDE.md`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Learn about a new version without looking for it (Priority: P1)

A user works with the app as usual. Once a day the app quietly asks the release server whether a newer
version is out. When one is, a small button in the main window's title bar names the new version; a click
on it opens a window that tells them when it was released and what it brings, in their language. Nothing happens when there is nothing new or the Mac is offline.

**Why this priority**: Without it users stay on old versions and miss fixes; it is the base of the feature.

**Independent Test**: Point the check at a test server that announces a newer version; start the app: the
title-bar button appears a few seconds after the main window, and a click on it opens the window with the
right versions and notes; start again the same day: no check.

**Acceptance Scenarios**:

1. **Given** automatic checking is on and the last check was more than 24 hours ago, **When** the app starts,
   **Then** a few seconds after the main window it checks once, and if a newer published release exists the
   button "↑ Version X.Y.Z" appears in the main window's title bar; no window opens and the focus stays.
2. **Given** a check succeeded less than 24 hours ago, **When** the app starts or keeps running, **Then** it
   does not check again until 24 hours have passed.
3. **Given** the check failed (offline, server error, too many requests), **When** an hour has passed,
   **Then** the app tries again at most once an hour, and shows nothing about the failure.
4. **Given** the newest published release is the running version or older, **When** the check runs,
   **Then** nothing is shown and the result is remembered as "up to date".
5. **Given** automatic checking is turned off, **When** the app runs for days, **Then** it never contacts
   the release server by itself.
6. **Given** two copies of the app run, **When** a check is due, **Then** only one checks; the other shows the button from the remembered result.

---

### User Story 2 - Update with one click (Priority: P1)

In the update window the user presses "Install and Relaunch". The app downloads the new version with a
progress bar, checks that it is genuine and complete, replaces itself and starts again; the What's New
window then shows what changed.

**Why this priority**: The maintainer asked for the app to update itself; downloading and replacing an app by
hand is the main burden this removes.

**Independent Test**: With a test server offering a correctly signed newer build of a test copy, press
Install and Relaunch: the copy is replaced at its place, starts again in the new version and shows What's
New; the old copy is in the Trash.

**Acceptance Scenarios**:

1. **Given** the update window offers a newer version that this app can install, **When** the user presses
   Install and Relaunch (or Return), **Then** the download runs with progress and Cancel, the archive is
   checked against the published checksum, the new app is checked to be the same app signed by the same
   certificate and of the announced version, it replaces the running app at the same place under the same
   name, the old app goes to the Trash, and the new version starts.
2. **Given** a download runs, **When** the user presses Cancel or quits the app, **Then** the download stops,
   the temporary files are removed and the running app is unchanged.
3. **Given** the checksum does not match, the archive does not contain exactly one app, or the new app's
   identity, version or signature does not match, **When** the check finds it, **Then** nothing is
   replaced, the temporary files are removed, the user is told what failed, and "Download…" opens the
   release page.
4. **Given** copy, move or delete operations are running, **When** the user presses Install and Relaunch,
   **Then** the app does not interrupt them: it says so and offers to install when they finish, or later.
5. **Given** the update was installed, **When** the new version starts, **Then** the What's New window shows
   the notes of the versions since the old one (spec 026).

---

### User Story 3 - Check on demand (Priority: P1)

A user hears about a new version and wants it now. They choose "Check for Updates…" in the app menu (or
Check Now in Settings or About) and always get an answer.

**Why this priority**: Users with the automatic check off, or impatient ones, need a way in; the reference
always answers a manual check.

**Independent Test**: With the test server announcing a newer version, the command opens the update window;
with the same version it says the app is up to date; with the server stopped it says the check failed.

**Acceptance Scenarios**:

1. **Given** a newer version exists, **When** the user chooses Check for Updates…, **Then** the update window
   opens, even when the version was skipped or "remind me later" was chosen.
2. **Given** the running version is the newest, **When** the user checks, **Then** a message says
   "Axolotl Commander X.Y.Z is the latest version."
3. **Given** the server cannot be reached or answers with an error, **When** the user checks, **Then** a
   message says why the check failed, with Try Again.
4. **Given** the check takes more than a moment, **When** it runs, **Then** a progress indicator with Cancel
   is shown.

---

### User Story 4 - Decide later or skip a version (Priority: P2)

The user does not want to update now. "Remind Me Later" (or Esc) closes the window and hides the title-bar
button until the next day; "Skip This Version" hides it for this version, but a newer one is announced again.

**Why this priority**: An update offer must not nag; it follows the reference.

**Independent Test**: Remind Me Later → no title-bar button at the next starts the same day, the button the
next day; Skip → no button for that version, the button when a newer one appears.

**Acceptance Scenarios**:

1. **Given** the update window, **When** the user presses Remind Me Later or Esc, **Then** the window closes
   and the title-bar button for this version stays hidden for 24 hours.
2. **Given** the update window, **When** the user presses Skip This Version, **Then** the automatic check
   does not show this version again; a newer version shows the button again.
3. **Given** the update window, **When** the user clears "Check for updates automatically", **Then** the
   setting changes at once (also in Settings).

---

### User Story 5 - See the update state in Settings and About (Priority: P2)

Settings → General has "Check for updates automatically", the date and result of the last check, and Check
Now. The About window shows the last result ("Version X.Y.Z is available" with Install…, "up to date
(checked on <date>)" or "never checked") and Check Now. Opening either does not contact the server.

**Why this priority**: The status is useful but the feature works without it.

**Independent Test**: After a check, Settings and About show its date and result; opening them does not
start a check.

**Acceptance Scenarios**:

1. **Given** an update was found, **When** the user opens About, **Then** it says which version is available
   and Install… opens the update window.
2. **Given** no check has ever run, **When** the user opens About or Settings, **Then** they say "Never
   checked" and offer Check Now.
3. **Given** About or Settings is opened, **When** nothing else happens, **Then** no request is made.

---

### User Story 6 - Release notes in both languages with every release (Priority: P2)

When the maintainer releases a version, its notes in English and Czech are published with it automatically:
the release description on the project page and the two changelog files attached to the release, which the
update window reads. A release without notes in both languages is not created.

**Why this priority**: The update window and the project page need the notes; the maintainer asked that they
appear automatically with each release.

**Independent Test**: Tag a version in a test run of the workflow: the draft release has the English and
Czech notes of that version in its description and both changelogs attached; remove the Czech section and
the workflow stops with a message before creating the release.

**Acceptance Scenarios**:

1. **Given** both changelogs have notes for version X.Y.Z, **When** the release workflow runs for the tag,
   **Then** the draft release describes the version with its English notes, then its Czech notes (after the
   installation steps for builds that are not notarized), and carries `CHANGELOG.md` and `CHANGELOG.cs.md`
   as assets.
2. **Given** either changelog has no notes for X.Y.Z, **When** the workflow runs, **Then** it fails before
   creating the release and says which file lacks the notes.
3. **Given** a pull request adds English changelog entries but no Czech ones (or the other way round),
   **When** the checks run, **Then** they fail and say which changelog lacks the entries.

### Edge Cases

- Offline, DNS failure, timeout: the automatic check is silent and retries in an hour; on demand the user is
  told.
- Too many requests (the server's rate limit): treated as a failure (silent / explained).
- A malformed answer, a release whose tag is not a version, a release without the app archive or the
  checksum file: no offer; on demand "no suitable release was found".
- Drafts and pre-releases are never offered; a downgrade is never offered (also after the user installed an
  older version by hand).
- A skipped version followed by a newer one: the newer one is offered.
- The release has no changelog assets or they cannot be read: the window shows the release without notes and
  a link to the release page.
- The download is interrupted or the disk is full: nothing replaced, temporary files removed, the user told.
- The user renamed or moved the app ("Axolotl Commander 2.app" in another folder): the update keeps that
  name and place.
- The app runs translocated, from a disk image or read-only volume: the manual way with "Move Axolotl
  Commander to the Applications folder first".
- The app's folder is not writable for the user: the manual way, with the reason; no administrator password
  is asked.
- A development or ad-hoc signed build, or a release signed by another certificate: the manual way, with the
  reason.
- Moving the old app to the Trash fails: the old app is removed only if the new one is in place; if the new
  one cannot be put in place, the old one stays.
- The system clock was moved back: a "last check" in the future counts as due.
- Remind Me Later, then a manual check: the manual check shows the window at once.
- The user quits during a check or download: it stops quietly; temporary files are removed.
- The update window is open when another check finds the same version: the same window stays (no second).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST check for a newer published release automatically, on by default, at most once
  per 24 hours (a few seconds after the start, and while running), and after a failed check at most once an
  hour, silently. A found update MUST be shown only as a button "↑ Version X.Y.Z" at the right end of the
  main window's title bar (no window, no focus taken); a click on it opens the update window.
- **FR-002**: Settings → General MUST have "Check for updates automatically", the date and result of the
  last check, and Check Now; turning the option off MUST stop all automatic contact with the release server.
- **FR-003**: "Check for Updates…" in the app menu, Check Now in Settings and in About MUST check at once and
  always answer: the update window, "the latest version", or why it failed (with Try Again); a check that
  takes longer than a second MUST show progress with Cancel.
- **FR-004**: A release MUST be offered only when it is published (not a draft, not a pre-release), its
  version is newer than the running one, and it has the app archive and the checksum file.
- **FR-005**: The check MUST send no information about the user or the Mac beyond what the request itself
  needs (no version, identifier or settings).
- **FR-006**: The update window MUST show the running version, the offered version and its release date, and
  the notes of every version newer than the running one up to the offered one, read from the changelogs
  published with the release, in the app's language with English for versions without a translation; links
  MUST open in the browser and nothing remote MUST be loaded into the window.
- **FR-007**: The update window MUST offer Install and Relaunch (default), Remind Me Later (Esc), Skip This
  Version and the automatic-check checkbox; when this app cannot install itself, the default MUST be
  Download… (the release page in the browser) with the reason shown.
- **FR-008**: Remind Me Later MUST hide the title-bar button for 24 hours; Skip This Version MUST hide it for
  that version (a newer one shows it again); a manual check MUST ignore both.
- **FR-009**: Install and Relaunch MUST download the archive with progress and Cancel, verify it against the
  published checksum, and verify that the new app has the same identifier, the announced version and a
  valid signature by the same certificate as the running app, before anything is replaced.
- **FR-010**: The installation MUST replace the running app at its current place under its current name,
  move the old app to the Trash, and start the new version; on any failure the running app MUST stay
  unchanged and working, the temporary files MUST be removed, and the user MUST be told what failed and
  offered the manual download.
- **FR-011**: Installing MUST NOT interrupt running file operations; the app MUST say so and offer to install
  when they finish or later.
- **FR-012**: The app MUST offer only the manual download, with the reason, when it cannot install itself:
  its folder is not writable, it runs translocated or from a read-only volume, it is a development or
  ad-hoc build, or the release is signed by another certificate. It MUST NOT ask for an administrator
  password.
- **FR-013**: The installer MUST touch only the running app bundle, the Trash entry of the old app and its
  own temporary folder.
- **FR-014**: The About window MUST show the last result (available with Install…, up to date with the date,
  or never checked) and Check Now; opening About or Settings MUST NOT contact the server.
- **FR-015**: Only one running copy MUST check at a time; every copy shows the title-bar button from the
  remembered result.
- **FR-016**: The release workflow MUST publish with every release the version's English and Czech notes as
  the release description and attach both changelogs; it MUST stop before creating the release when either
  changelog has no notes for the version.
- **FR-017**: The checks of a pull request MUST fail when the unreleased part of one changelog has entries
  and that of the other has none; the version script MUST refuse to raise the version in that case.
- **FR-018**: All texts of the update window, messages, menu item and settings MUST be localized (English
  and Czech).
- **FR-019**: A hidden setting, not shown in Settings and not exported, MAY point the check at another
  release server address (for tests); the app MUST use the project's release server otherwise.

### Key Entities

- **Release**: version, publication date, release page, whether it is a draft or pre-release, the app
  archive and checksum file, the changelog files.
- **Update state** (kept in the app's settings, not exported): automatic check on/off, time and result of
  the last check, the version found, a skipped version, a "remind later" time.
- **Download**: the archive being fetched, its progress, its verified checksum, the unpacked new app in a
  private temporary folder.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with the automatic check on learns about a published version within 24 hours of the
  next use of the app, without any action.
- **SC-002**: From the update window to the new version running takes one click and, on a typical home
  connection, under a minute.
- **SC-003**: No failure of a check, download or verification leaves the user without a working app.
- **SC-004**: With the automatic check off, the app makes no request to the release server by itself.
- **SC-005**: Every release published from the workflow has notes in English and Czech without the
  maintainer writing them at release time.
- **SC-006**: Unit tests cover the release answer parsing, the offer rules, the schedule, skip/remind, the
  checksum parsing, and the installer steps including roll-back, without touching any real app or user data.

## Assumptions

- Releases stay on the project's GitHub page and keep the archive and checksum names of the current release
  workflow; the newest published release is the one offered.
- The release notes are written into both changelogs in each pull request, the Czech part by the agent
  automatically (project rule and skill); the workflow only publishes and checks them. The release workflow
  itself does not translate.
- Installing over the app is allowed because it is the app's own bundle, not user data; it happens only
  after the user's consent in the update window.
- A future change of the signing certificate (e.g. a Developer ID) makes self-install refuse that one release;
  users then download it by hand once.
- The GUI check uses a local test server and a test copy; real installs are tested by the maintainer with a
  real release.

## Out of Scope

- Delta or patch updates, a beta or pre-release channel, a separate update feed or third-party update
  framework.
- Installing with an administrator password, installing without asking.
- Updating copies managed by a package manager.
- Notarization and signing changes.
- Machine translation of the notes in the release workflow.
