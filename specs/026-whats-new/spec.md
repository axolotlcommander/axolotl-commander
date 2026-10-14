# Feature Specification: What's New Window

**Feature Branch**: `026-whats-new`

**Created**: 2026-10-14

**Status**: Implemented

**Input**: User description: "What's New window: shows the release notes of the app (from the CHANGELOG.md
bundled into the app) once after the app was updated to a newer version, and on demand from the menu, the
About window and Settings." (Proposal written in chat after research of the reference; agreed on 2026-10-14:
"jak doporučuješ" and "pusť se do toho rovnou", that is, take the recommended answers and go ahead.)

## Context

The project keeps its release notes in `CHANGELOG.md` (Keep a Changelog: an "Unreleased" section, then one
section per released version with its date and Added / Changed / Fixed / Removed lists, in English). Users
see these notes only on the project's release page. The About window is the standard macOS about panel with
the version and the credits.

Research of how others do it:

- **The reference** has a static "What's New in This Release" page in its help; nothing is shown after an
  update. Its update window (see the companion update spec) has a button that opens the release notes in
  the browser.
- macOS apps commonly show a "What's New" window once after an update and keep it reachable from the menu.

This spec only shows the notes of the versions already on the Mac and works offline. A companion spec
(Updates) checks for newer versions, shows their notes before installing them and installs them; after such
an update this window shows the notes once more. This spec is part of release 0.6.0, which collects several
specs; the version is already raised on the branch this one builds on, so its pull request adds only the
changelog entry.

## Clarifications

### Session 2026-10-14

- Q: When is the window shown by itself? → A: Once, at the first start of a newer version than the one that
  ran before on this Mac. Not at the very first start of the app, not after a downgrade.
- Q: Where else can it be opened? → A: Help → What's New…, a link in the About window and a button in
  Settings → General.
- Q: Where do the notes come from? → A: The changelog bundled into the app; nothing is downloaded.
- Q: Where in Settings → General does the button go? → A: (during the GUI check) In the row of Export /
  Import Settings, at its right end. The General tab no longer fitted the window, so the panel options moved
  to their own Panels tab and every tab of these two scrolls when it is taller than the window.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See what changed after an update (Priority: P1)

A user updates the app (by the companion update feature or by replacing it by hand) and starts it. A moment
after the main window appears, a What's New window lists the changes of the new version and of any versions
skipped in between. The user reads it and closes it with Esc; it does not come back at the next start.

**Why this priority**: Users learn about new features (keys, settings) only if they are told; this is the
main reason for the feature.

**Independent Test**: Set the remembered version to an older one, start the app: the window appears once
with the right versions; start again: no window.

**Acceptance Scenarios**:

1. **Given** the version that last ran was 0.4.2 and the changelog has 0.6.0, 0.5.0, 0.4.3 and older,
   **When** 0.6.0 starts, **Then** the window shows 0.6.0, 0.5.0 and 0.4.3, newest first, and nothing older.
2. **Given** the window was shown once, **When** the app starts again, **Then** no window appears.
3. **Given** the app starts for the very first time on this Mac, **When** the main window appears, **Then**
   no What's New window appears and the running version is remembered.
4. **Given** an older version than the one that ran before starts (downgrade), **When** it starts, **Then**
   no window appears and the running version is remembered.
5. **Given** the window appears, **When** the user presses Esc, ⌘W or Return (Close), **Then** it closes and
   the panel that had the focus has it again.

---

### User Story 2 - Open the notes on demand (Priority: P1)

A user wants to look up what a version brought. They choose Help → What's New…, click the What's New link in
the About window, or press the What's New button in Settings → General.

**Why this priority**: The notes must stay reachable after the one-time window was closed.

**Independent Test**: Each of the three places opens the window with every version, newest first.

**Acceptance Scenarios**:

1. **Given** the app runs, **When** the user chooses Help → What's New…, **Then** the window opens with all
   versions of the bundled changelog, newest first, scrolled to the top.
2. **Given** the About window is open, **When** the user clicks "What's New…" under the version, **Then** the
   What's New window opens.
3. **Given** Settings → General is shown, **When** the user presses "What's New…", **Then** the window opens.
4. **Given** the window is already open, **When** it is asked for again, **Then** the same window comes to the
   front (there is never a second one).

---

### User Story 3 - Read the notes comfortably (Priority: P2)

The notes are formatted: a heading per version with its release date, the Added / Changed / Fixed lists,
inline code for keys and settings, and links that open in the default browser.

**Why this priority**: Plain Markdown source would be hard to read; the formatting adds comfort, not
function.

**Independent Test**: Open the window; headings, lists, code and links look formatted in light and dark
appearance; a link opens the browser; text can be selected and copied.

**Acceptance Scenarios**:

1. **Given** the window is open, **When** the user clicks a link in the notes, **Then** the default browser
   opens it and the window stays.
2. **Given** the window is open, **When** the user selects text and presses ⌘C, **Then** the text is copied.
3. **Given** the system switches between light and dark appearance, **When** the window is shown, **Then** it
   follows the appearance.

### Edge Cases

- The bundled changelog is missing (a development build run without a bundle): the window is never shown by
  itself; opened on demand it says that no notes are available.
- The changelog is empty or malformed: the window says there are no notes for this version; no crash.
- A version in the range has no section (released without notes): the other versions are still shown; if
  none is left, the window is not shown by itself.
- The remembered value is not a version number: treated as nothing remembered (no window, the running version
  is remembered).
- The "Unreleased" section is never shown.
- Two copies of the app start at once: only one shows the window.
- A sheet or dialog is open when the window would appear: the window waits until it is closed and does not
  take the keyboard focus from it.
- Versions compare by number, not as text: 0.10.0 is newer than 0.9.9.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST remember the version that last ran on this Mac in its settings and update it at
  every start.
- **FR-002**: At the start of a version newer than the remembered one, the app MUST show the What's New window
  once, a moment after the main window appears, listing every version newer than the remembered one up to
  the running one, newest first.
- **FR-003**: The window MUST NOT be shown by itself at the very first start (nothing remembered or the
  remembered value is not a version), after a downgrade, at the start of the same version, or when no
  section of the range has notes.
- **FR-004**: Help → What's New… MUST open the window with all versions of the bundled changelog, newest
  first; the About window MUST show a "What's New…" link under the version, and Settings → General MUST have
  a "What's New…" button that does the same.
- **FR-005**: There MUST be at most one What's New window; asking for it again MUST bring it to the front and
  show the requested versions.
- **FR-006**: The window MUST show the notes formatted (version headings with dates, lists, inline code,
  links), follow the light and dark appearance, allow selecting and copying text, and open links in the
  default browser.
- **FR-007**: The window MUST NOT load anything from the internet.
- **FR-008**: The "Unreleased" section MUST never be shown.
- **FR-009**: Esc, ⌘W and a Close button (the default button, Return) MUST close the window; it MUST be
  resizable and remember its size.
- **FR-010**: The window title and buttons MUST be localized; the notes stay in English.
- **FR-011**: Every app bundle built by the project's bundle script MUST contain the changelog.
- **FR-012**: A missing, empty or malformed changelog MUST NOT crash the app; on demand the window says that
  no notes are available.
- **FR-013**: When two copies of the app start, at most one MUST show the window by itself.

### Key Entities

- **Release notes**: the versions of the bundled changelog, each with a version number, an optional date and
  its body (the lists and text below the heading).
- **Last run version**: the version that last started on this Mac, kept in the app's settings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After an update, the notes of every version the user skipped appear within 2 seconds of the
  main window, exactly once.
- **SC-002**: From any of the three places, the notes open in one action.
- **SC-003**: The window opens in under half a second with a changelog of 100 versions.
- **SC-004**: Unit tests cover the changelog parsing, the version comparison and every start case of FR-002
  and FR-003.

## Assumptions

- The changelog keeps the Keep a Changelog headings (`## [X.Y.Z] - YYYY-MM-DD`, `## [Unreleased]`); other
  text inside a section is shown as it is.
- Two copies starting at once are rare; it is enough that the one that updates the remembered version first
  shows the window.
- The About window keeps the content and look of the standard macOS panel (icon, name, version, credits,
  copyright); it is the app's own window because the standard panel cannot run an action from a link (plan R6).
- Deviation from the reference: the reference has no window after an update; this is an addition agreed with
  the maintainer.

## Out of Scope

- Downloading notes from the internet (the update spec shows the notes of a newer version from its release).
- Translating the notes.
- A "do not show again" option (the window appears once per update anyway).
