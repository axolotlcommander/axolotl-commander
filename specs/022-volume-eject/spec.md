# Feature Specification: Volumes in the Go Menu and Ejecting Volumes

**Feature Branch**: `022-volume-eject`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "Volumes in the Go menu and ejecting volumes: drop the Left/Right menus and
add ways to eject disks and network volumes from the keyboard, the volume buttons and the Disconnect
dialog." (Proposal written in chat after the maintainer asked whether the Left/Right menus are needed and
noted that there is no way to eject a volume; agreed on 2026-10-13: "ano udělej to".)

## Context

The menu bar has two menus, Left and Right, that each hold one item, "Volume…" (⌥F1 / ⌥F2), which opens
the volume picker of that panel. Two whole menus for one command each take room in the menu bar and do
not group commands by function, as Mac menus do.

The volume bar above each panel shows a button for every mounted volume and for every open server
connection. Server buttons show an eject symbol while the pointer is over them and disconnect when it is
clicked; F12 "Disconnect…" lists the open server connections. A USB stick, an external disk, a disk
image or a network share mounted in macOS cannot be ejected from the app at all: the user has to switch
to the Finder, and the app's own panels on that volume may keep it busy.

Classic two-panel file managers keep the drive lists of both panels in one place and can eject or
disconnect drives from their drive buttons and from a disconnect command. On the Mac, the Finder ejects
with ⌘E and a ⏏ next to the volume.

This spec ships in release 0.5.0, on top of spec 021.

## Clarifications

### Session 2026-10-13

- Q: Keep the Left and Right menus? → A: No. "Left Volume…" (⌥F1) and "Right Volume…" (⌥F2) move to the
  Go menu; the command identifiers and their custom key bindings stay.
- Q: Which ways to eject? → A: All of the proposal: ⌘E "Eject Volume" for the active panel's volume, a ⏏
  on hover over ejectable volume buttons, a context menu on volume buttons (Eject / Volume Information…),
  and F12 "Disconnect…" also listing network volumes and ejectable disks.
- Q: Safety? → A: Panels on the volume go to the home folder and stop watching it before the eject; the
  eject is refused while an operation uses the volume; the system's reason is shown when it refuses; the
  startup disk can never be ejected (greyed out, no ⏏).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Eject the volume of the active panel from the keyboard (Priority: P1)

A user copies photos onto a USB stick in the right panel. When the copy ends, the user presses ⌘E. Both
panels that showed the stick go to the home folder, the stick is ejected and its button disappears from
the volume bar. The user pulls the stick out.

**Why this priority**: ejecting is the last step of every work with a removable disk; today it needs the
Finder.

**Independent Test**: attach a small disk image in a scratch folder, point a panel to it, press ⌘E.

**Acceptance Scenarios**:

1. **Given** the active panel shows a folder on the ejectable volume "USB", **When** the user opens the
   Commands menu, **Then** it shows "Eject “USB”" with ⌘E, next to "Disconnect…".
2. **Given** the active panel and the inactive panel both show folders on "USB", **When** the user presses
   ⌘E, **Then** both panels (and every tab on "USB" in every window) go to the home folder and "USB" is
   ejected; its button leaves the volume bar.
3. **Given** the active panel shows the startup disk, **When** the user opens the Commands menu, **Then**
   "Eject Volume" is greyed out and ⌘E does nothing.
4. **Given** the active panel shows a folder on a server connection, **When** the user presses ⌘E,
   **Then** that server is disconnected (as its ⏏ does) and panels on it go to the home folder.
5. **Given** the active panel shows the contents of an archive stored on "USB", **When** the user presses
   ⌘E, **Then** the archive view is left and "USB" is ejected.
6. **Given** a copy into "USB" is running, **When** the user presses ⌘E, **Then** a message says that the
   copy is using the volume and nothing is ejected; the panels stay where they are.
7. **Given** another app has a file on "USB" open, **When** the user presses ⌘E, **Then** the panels go
   to the home folder, the eject fails, and a message shows the system's reason; "USB" stays mounted.

---

### User Story 2 - Volume pickers in the Go menu (Priority: P1)

A user looks for the volume picker of the right panel in the menu bar. It is in the Go menu, next to the
other ways to change folders, and the Left and Right menus are gone.

**Why this priority**: it frees two menus and makes the eject commands of this spec easy to find among
fewer menus.

**Independent Test**: open the menu bar and press ⌥F1 / ⌥F2.

**Acceptance Scenarios**:

1. **Given** the main window is open, **When** the user looks at the menu bar, **Then** there are no Left
   and Right menus, and the Go menu has "Left Volume…" (⌥F1) and "Right Volume…" (⌥F2).
2. **Given** the user has bound "Right Volume…" to another key in the settings, **When** the app starts
   after this change, **Then** that key still opens the right volume picker.
3. **Given** the Classic Commander key scheme, **When** the user presses ⌥F1, **Then** the left volume
   picker opens as before.

---

### User Story 3 - Eject from the volume buttons (Priority: P1)

A user moves the pointer over the button of an external disk in the volume bar. A ⏏ appears at its edge;
clicking it ejects the disk. A right click on the button offers "Eject “Backup”" and "Volume
Information…".

**Why this priority**: the volume bar is where the user sees the disk; Mac users expect a ⏏ there.

**Independent Test**: attach a disk image, hover its button, click ⏏; right click its button.

**Acceptance Scenarios**:

1. **Given** an ejectable volume is mounted, **When** the pointer is over its button, **Then** a ⏏ appears
   at the trailing edge, as on server buttons; it disappears when the pointer leaves.
2. **Given** the ⏏ is shown, **When** the user clicks it, **Then** the volume is ejected with the same
   safety steps as ⌘E.
3. **Given** the startup disk or an internal volume that cannot be ejected, **When** the pointer is over
   its button, **Then** no ⏏ appears.
4. **Given** any volume button, **When** the user right clicks or ⌃clicks it, **Then** a menu offers
   "Eject “X”" (disabled when it cannot be ejected) and "Volume Information…" for that volume; on a server
   button the first item is "Disconnect “X”".

---

### User Story 4 - Disconnect or eject several things at once (Priority: P2)

Before leaving with the laptop, the user presses F12. The dialog lists the open server connections, the
network share mounted in macOS and the USB stick. The user checks all three and presses Return.

**Why this priority**: it extends an existing dialog; the single-volume cases are covered by the stories
above.

**Independent Test**: with a disk image attached and no server connected, press F12.

**Acceptance Scenarios**:

1. **Given** server connections, network volumes and ejectable disks exist, **When** the user presses
   F12, **Then** the dialog lists them in sections (Servers, Network Volumes, Disks), each row with a
   checkbox, the name and a short kind.
2. **Given** the active panel is on one of the listed items, **When** the dialog opens, **Then** that item
   is checked and nothing else; otherwise nothing is checked.
3. **Given** only servers are checked, **Then** the confirm button reads "Disconnect"; **given** any
   volume is checked, **Then** it reads "Eject".
4. **Given** the dialog is open, **When** the user uses the arrows, Space, Return and Esc, **Then** they
   move between rows, toggle the checkbox, confirm and cancel.
5. **Given** no server is connected and no network volume or ejectable disk is mounted, **Then**
   "Disconnect…" is greyed out.
6. **Given** several items are checked and one of them cannot be ejected, **When** the user confirms,
   **Then** the others are ejected or disconnected and one message lists what failed and why.

### Edge Cases

- A volume disappears while the context menu or the F12 dialog is open: the dialog rows refresh; acting
  on a gone volume does nothing and shows no error.
- Only the inactive panel is on the volume: it still goes to the home folder.
- A viewer or Compare Files window shows a file from the volume: the system may refuse; its reason is
  shown.
- A disk with several mounted volumes (partitions): ejecting one ejects the physical disk, as in the
  Finder. When the disk has other mounted volumes, a question names them first ("Eject all volumes of
  this disk?" Eject / Cancel); a disk with one volume is ejected without a question.
- A server connection whose share is also mounted locally: each is ejected or disconnected by its own
  item.
- Names with quotes or emoji appear unchanged in the menu titles and the dialog.
- Ejecting from a second main window: panels of all windows on the volume go to the home folder.
- An eject that takes a while: the app stays responsive; the volume button shows that it is busy until
  the eject ends.
- Hidden volumes (such as Time Machine snapshots or system volumes) are not listed, as today.
- Network (the browse location) is never ejectable; ⌘E is greyed out there.
- In the viewer, ⌘E keeps its viewer meaning.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The menu bar MUST NOT have the Left and Right menus; the Go menu MUST hold "Left Volume…"
  (⌥F1, plus the alternative chord of today) and "Right Volume…" (⌥F2, plus today's alternative chord).
- **FR-002**: The two volume commands MUST keep their identifiers, so custom key bindings and key schemes
  keep working.
- **FR-003**: The app MUST offer "Eject Volume" (⌘E) in the Commands menu next to "Disconnect…"; its
  title MUST name the volume of the active panel ("Eject “X”") when there is one.
- **FR-004**: Eject Volume MUST act on the volume that holds the active panel's location (a folder, an
  archive shown as a folder, or a list of search results on that volume); on a server connection it MUST
  disconnect the server.
- **FR-005**: Eject Volume MUST be disabled for the startup disk, for internal volumes that cannot be
  ejected or unmounted, and for Network.
- **FR-006**: A volume is ejectable when it is removable, external, a disk image, or a network volume
  mounted in macOS, and is not the startup disk.
- **FR-007**: Volume buttons of ejectable volumes MUST show a ⏏ while the pointer is over them; clicking
  it MUST eject that volume. Server buttons keep their ⏏.
- **FR-008**: A right click or ⌃click on a volume button MUST open a menu with "Eject “X”" (or
  "Disconnect “X”" for a server; disabled when not possible) and "Volume Information…" for that volume.
- **FR-009**: "Disconnect…" (F12) MUST list server connections, network volumes and ejectable disks in
  sections; it MUST pre-check the item of the active panel's location when listed and nothing else; its
  confirm button MUST read "Disconnect" when only servers are checked and "Eject" otherwise.
- **FR-010**: "Disconnect…" MUST be enabled when at least one item can be listed and disabled otherwise.
- **FR-011**: Before an eject, every panel and tab in every window whose location is on that volume MUST
  go to the home folder and stop watching the volume; after a failed eject they MUST stay at home.
- **FR-012**: An eject MUST be refused, with a message naming the operation, while a file operation
  (copy, move, delete, pack, unpack, search, size calculation) has a source or a destination on that
  volume; nothing MUST change in that case.
- **FR-013**: When the system refuses an eject, the app MUST show the system's reason; the volume stays
  mounted.
- **FR-014**: When the physical disk has other mounted volumes, the app MUST ask before ejecting and name
  them; otherwise it MUST eject without a question.
- **FR-015**: After several items are ejected or disconnected from the F12 dialog, failures MUST be
  reported in one message that names each failed item and its reason.
- **FR-016**: All new texts MUST be localized (English source, Czech translation).
- **FR-017**: An eject MUST NOT block the app; the button of the volume MUST show that it is busy while
  the eject runs.

### Key Entities

- **Ejectable item**: something the user can remove: a server connection (disconnect), a network volume
  or an ejectable disk (eject); it has a name, a kind and the location it covers.
- **Volume use**: whether a running operation, a panel or a tab uses a volume; it decides refusal (an
  operation) and moving home (panels and tabs).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can eject the volume of the active panel with one key press (⌘E), without leaving
  the app.
- **SC-002**: After an eject started from the app, no panel or tab of the app is left on the ejected
  volume (0 panels in all windows).
- **SC-003**: No eject starts while an operation of the app uses that volume (0 cases in the tests).
- **SC-004**: The startup disk cannot be ejected from any of the four entry points (⌘E, ⏏, context menu,
  F12).
- **SC-005**: The menu bar has two menus fewer, and both volume pickers keep their keys.
- **SC-006**: Core unit tests cover which volumes are ejectable, the F12 list and pre-check, the title and
  enablement of Eject Volume for each kind of location, and the refusal while an operation uses the
  volume.

## Assumptions

- The Finder's behavior is the model for what counts as ejectable and for ejecting a disk with several
  partitions.
- Disk images and network shares mounted in macOS are ejected with the same command as disks; no new
  mounting features are added.
- The GUI check uses a small disk image created and attached in the session's scratch folder; no real
  disk is ejected.
- Out of scope: formatting, partitioning or repairing disks; mounting disk images or shares (beyond the
  existing Connect to Server); a device tree; notifying other apps; changes to the volume picker.
- Deviations from the classic reference: no separate Left/Right menus (Mac menus group by function); ⌘E
  ejects as in the Finder; network volumes and disks share the Disconnect dialog with server connections.
