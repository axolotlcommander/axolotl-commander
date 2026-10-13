# Feature Specification: Drive Row with Free Space

**Feature Branch**: `020-drive-row`

**Created**: 2026-10-13

**Status**: Draft (planned; not scheduled for implementation yet)

**Input**: User description: "A row in each panel, between the volume bar and the breadcrumb path bar: a
drive combo (icon, name, arrow; the same list as ⌥F1/⌥F2) and next to it the size of the current disk and
its free space, e.g. '59.07 GB free of 994.66 GB'. Shown by default, can be turned off in Settings. I
would like to see the free space even when this row is hidden: then it could be shown on the right of the
volume bar; and when that is not visible either, find another place for it. That could be a setting
too."

## Context

Each panel today shows, from the top: the volume bar (buttons for the mounted volumes, Home, iCloud
Drive, Network and server connections; spec of stage 5), the tab strip, the path bar (breadcrumbs, spec
003), the file list, and a status line with the item counts and the size of the selection. The volume
bar cannot be hidden. The free space of the panel's volume appears only in Volume Info (⌃L), so it
takes a command to see it.

Classic two-panel file managers have a drive row above each panel: a drop-down list of drives and the
free and total space of the current one. The maintainer sent a mockup of this row over our panel on
2026-10-10.

## Clarifications

### Session 2026-10-13

- Q: What does the row hold? → A: A drive combo (icon, name, arrow) with the same list as the ⌥F1/⌥F2
  volume menu, and next to it the free and total space of the panel's current disk.
- Q: Default? → A: Shown; Settings can turn it off.
- Q: The free space without the row? → A: It stays visible: on the right end of the volume bar, and,
  when the volume bar is hidden too, somewhere else in the panel. A setting can turn this off.
- The answers below were *decided while writing the spec; to review*:
  - Q: Where exactly is the row? → A: Right below the volume bar, above the tab strip, so that tabs and
    the path bar stay together.
  - Q: The volume bar hidden? → A: A new setting makes the volume bar optional (shown by default),
    since today it cannot be hidden.
  - Q: The place when both bars are hidden? → A: The right end of the panel's status line, after the
    selection summary.
  - Q: The settings? → A: In Settings → Appearance, next to the volume bar options: "Show drive row"
    (on), "Show volume bar" (on) and "Show free space when the drive row is hidden" (on). View menu
    commands: Show Drive Row and Show Volume Bar (checked when shown); they apply to both panels.
  - Q: Text? → A: "59.07 GB free of 994.66 GB", in the size units chosen in Settings (decimal or binary).
    When space is short it shortens to "59.07 GB free", then the row hides the text (the combo stays).
    The full text and the used percentage are in the tooltip.
  - Q: Click on the text? → A: Opens Volume Info (⌃L) for that panel.
  - Q: The combo and the keyboard? → A: Choosing a drive in the combo does what clicking its volume
    button does (including the spec 011 option that volume buttons open the other panel's folder or the
    last folder). ⌥F1/⌥F2 keep opening the volume menu as today. The combo never takes keyboard focus
    away from the file list.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the free space of the current disk at a glance (Priority: P1)

A user browses a folder. Below the volume bar of each panel a row shows the panel's disk in a combo and
"59.07 GB free of 994.66 GB" next to it. Copying a big folder in makes the free space go down without a
refresh.

**Why this priority**: the free space is the main reason for the row; it answers "will it fit?" before
F5.

**Independent Test**: open folders on the startup disk, an external drive and a mounted network volume
in the two panels; copy a large file; eject a drive.

**Acceptance Scenarios**:

1. **Given** default settings, **Then** every panel shows the drive row with the disk of its folder and
   its free and total space.
2. **Given** the panel moves to a folder on another disk, **Then** the combo and the space change to that
   disk at once.
3. **Given** a copy, move or delete changes the free space, **Then** the text shows the new value within a
   few seconds of the operation (or of a change made by another app).
4. **Given** the panel shows an archive, **Then** the row shows the disk that holds the archive.
5. **Given** the panel shows a server (FTP/SFTP) or the Network folder, **Then** the combo shows the
   server or Network and no space is shown (the space is unknown).
6. **Given** a narrow panel, **Then** the text shortens and finally hides, and the tooltip always shows
   the full text with the used percentage.
7. **Given** the user clicks the text, **Then** Volume Info opens for that panel's disk.

---

### User Story 2 - Choose a drive from the combo (Priority: P1)

The user clicks the combo and picks another drive from the list, the same list as ⌥F1/⌥F2. The panel
opens it as its volume button would.

**Acceptance Scenarios**:

1. **Given** the combo, **When** the user opens it, **Then** it lists the same items, in the same order,
   as the ⌥F1/⌥F2 volume menu, with the current one checked.
2. **When** the user picks a drive, **Then** the panel opens it exactly as a click on that drive's
   volume button does, and the keyboard focus returns to the file list.
3. **Given** a drive is ejected or mounted while the combo is closed, **Then** the next time it opens
   the list is current.

---

### User Story 3 - Keep the free space without the row (Priority: P2)

The user turns the drive row off to save space. The free space moves to the right end of the volume bar.
When the user hides the volume bar too, it moves to the right end of the panel's status line. When the
user does not want it at all, a setting turns it off.

**Independent Test**: toggle the row, the volume bar and the free space option in all combinations and
check where the text is in both panels.

**Acceptance Scenarios**:

1. **Given** the drive row is off and the volume bar is on, **Then** the free space is shown at the right
   end of the volume bar. When the bar is too narrow, the text shortens and then hides before any
   volume button is hidden (today a narrow bar hides buttons from the end).
2. **Given** the drive row and the volume bar are off, **Then** the free space is shown at the right end
   of the status line, after the selection summary, which keeps priority when space is short.
3. **Given** "Show free space when the drive row is hidden" is off, **Then** the free space appears only
   in the drive row.
4. **Given** the drive row is on, **Then** the free space is shown only there, never twice.
5. **Given** the user chooses View → Show Drive Row or View → Show Volume Bar, **Then** the bar turns on
   or off in both panels of every window and the menu item is checked when shown.

---

### Edge Cases

- **Home and iCloud Drive**: the combo shows the item that the volume bar would show pressed. The space
  is that of the disk holding the folder (the startup disk).
- **A folder on a disk image or a network volume (SMB/AFP)**: it is a mounted volume with its own
  capacity, shown like any disk. If the server does not report it, no space is shown.
- **Read-only volumes** (a DMG, a CD): space is shown as reported; the tooltip says read-only.
- **Space the system can free** (purgeable space): the value is the space available for important use,
  as Volume Info (⌃L) and the Finder show it.
- **A disk ejected while shown**: the panel moves away as today; the row follows the new folder.
- **Find results and branch view** (flat listings): the disk of the listing's root folder.
- **Quick View panel** (spec 016) and a maximized panel: the hidden panel's row is hidden with it.
- **Settings export**: the three new options are user preferences in the settings export.
- **Both key schemes**: no new keys.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each panel MUST be able to show a drive row below the volume bar: a drive combo and the free
  and total space of the disk holding the panel's location. It MUST be shown by default.
- **FR-002**: The combo MUST list the same items as the ⌥F1/⌥F2 volume menu. Choosing one MUST act as a
  click on the matching volume button and return the focus to the file list.
- **FR-003**: The space text MUST use the size units from Settings, shorten when space is short, carry the
  full text and used percentage in a tooltip, and open Volume Info on click.
- **FR-004**: The text MUST update when the panel's location changes, after file operations and when
  another app changes the disk (within a few seconds), and when volumes mount or unmount.
- **FR-005**: The volume bar MUST become optional (shown by default).
- **FR-006**: When the drive row is hidden and the option "Show free space when the drive row is hidden"
  is on (default), the free space MUST be shown at the right end of the volume bar, or, when that is
  hidden too, at the right end of the panel's status line. It MUST never be shown twice.
- **FR-007**: Settings → Appearance MUST hold the three options; the View menu MUST have Show Drive Row
  and Show Volume Bar. Changes MUST apply at once to both panels of every window.
- **FR-008**: The new options MUST be user preferences in the settings export, with the existing
  compatibility guards.
- **FR-009**: Locations without a known disk (servers, the Network folder) MUST show no space and MUST
  NOT show an error.

### Key Entities

- **Drive row settings**: show drive row, show volume bar, show free space elsewhere (three switches).
- **Disk space**: the disk of a location, its total and available capacity, read-only flag.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With default settings the free space of both panels' disks is visible without any command.
- **SC-002**: After copying 1 GB onto a disk the shown free space changes within 5 seconds.
- **SC-003**: The placement rule (row, volume bar or status line, never twice, off), the text and its
  shortening, and the choice of the disk for archives, servers, Home and flat listings have automated
  tests.

## Assumptions

- The space is the value the system reports for important use, as in Volume Info (⌃L).
- The row has the height of the path bar.

## Out of Scope

- A free space warning before a copy (the copy already checks space).
- Showing the space of a server (FTP/SFTP) folder.
- Changing the volume bar's buttons or the ⌥F1/⌥F2 menu.
- A drive combo that replaces the volume bar.

## Deviations from the classic reference

- The volume bar stays as the main drive switcher and the row adds to it. In the classic layout the
  combo and the drive buttons are alternatives.
- The free space can also live in the volume bar or the status line when the row is hidden.
