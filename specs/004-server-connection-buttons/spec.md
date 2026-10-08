# Feature Specification: Server Connections, iCloud Drive and Network in the Volume Bar

**Feature Branch**: `004-server-connection-buttons`

**Created**: 2026-10-08

**Status**: Draft

**Input**: User description: "Server connections in the toolbar and the volume bar. An open
SFTP/FTP/FTPS connection is easy to see and to return to with one click, as in Commander One, and
connecting is one click away. Today a connection stays open after the panel leaves the server,
but nothing in the window shows it; connecting is only ⌘K or the menu." Extended during the
specification: iCloud Drive and Network buttons in the volume bar, as in Commander One, and a
setting for what the volume bar shows (see Clarifications).

## Clarifications

### Session 2026-10-08

- Q: Should the volume bar also offer iCloud Drive and Network, as Commander One does, and can
  the user choose what it shows? → A: Yes, both are added to this feature (User Stories 5 and 6).
- Q: What does the Network button do, given that the app has no network neighbourhood browser?
  → A: It opens a menu with the network volumes mounted in macOS, the live server connections
  and "Connect to Server…" (⌘K).
- Q: What can be turned off? → A: Settings → Appearance lists Home (off by default), iCloud
  Drive, Network and Server connections (all on by default); volumes are always shown. Hiding the
  whole volume bar is not part of this feature.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Connect from the toolbar (Priority: P1)

The main window's toolbar has a "Connect to Server" button. Clicking it opens the same Connect
to Server dialog as ⌘K, for the active panel. Users who want a Disconnect button can add one
through Customize Toolbar.

**Why this priority**: Connecting to a server is a frequent task and today it is hidden behind a
shortcut or a menu; one visible button makes it discoverable.

**Independent Test**: In the test copy of the app with the default toolbar, click "Connect to
Server"; the Connect to Server dialog opens for the active panel, exactly as with ⌘K.

**Acceptance Scenarios**:

1. **Given** a toolbar that was never customized, **When** the main window opens, **Then** the
   toolbar contains a "Connect to Server" button with a network symbol.
2. **Given** the left panel is active, **When** the user clicks "Connect to Server", **Then** the
   Connect to Server dialog opens for the left panel, the same as pressing ⌘K.
3. **Given** the toolbar's Customize Toolbar sheet, **When** the user looks at the available
   items, **Then** "Connect to Server" and "Disconnect" are both offered; "Disconnect" is not in
   the default set.
4. **Given** a "Disconnect" button in the toolbar, **When** the user clicks it, **Then** the
   existing Disconnect dialog (F12) opens; when there is no connection the button is disabled,
   exactly as the menu command is.

---

### User Story 2 - See open connections and return with one click (Priority: P1)

After connecting to a server, a button with the server's name appears in the volume bar above
each panel, next to "Macintosh HD" and the other volumes. It stays there after the panel leaves
the server. Clicking it brings the panel back to the folder it was in on that server. The button
is shown pressed while the panel is on that server, like a volume button.

**Why this priority**: This is the feature itself: open connections become visible and reachable
with one click, as in Commander One.

**Independent Test**: In the test copy of the app, connect the left panel to the local test SFTP
server, open a subfolder there, then go to a local test folder. The volume bars of both panels
show a button for the server; clicking it in the left panel shows the same subfolder again.

**Acceptance Scenarios**:

1. **Given** no server connection, **When** the user connects the left panel to the test server
   `127.0.0.1`, **Then** both panels' volume bars show a new button "127.0.0.1" with a network
   symbol at the end of the bar, and the left panel's button is pressed.
2. **Given** the left panel was in `/data/sub` on the server and then went to a local folder,
   **When** the user clicks the server button in the left panel's volume bar, **Then** the left
   panel shows `/data/sub` on the server, and Back returns to the local folder.
3. **Given** the right panel has never been on the server and the left panel's last folder there
   was `/data/sub`, **When** the user clicks the server button in the right panel's volume bar,
   **Then** the right panel shows `/data/sub` on the server while the left panel stays where it
   is; both panels may show the same server at the same time.
4. **Given** two live connections to the same host under different users, **When** the volume
   bar shows them, **Then** their labels are `user@host` (and `user@host:port` when that is
   still ambiguous) instead of the bare host name.
5. **Given** the pointer rests on a server button, **When** the tooltip appears, **Then** it shows
   the full address, e.g. `sftp://tester@127.0.0.1:2222`, never a password.
6. **Given** the connection dropped (the test server was stopped) and the panel left the server,
   **When** the user clicks the server button, **Then** the app connects again the same way as
   opening a remote location today (saved password or the usual prompt) and shows the last
   folder; if the server cannot be reached, the error is shown as today and the button stays.

---

### User Story 3 - Disconnect from the button (Priority: P2)

Hovering over a server button shows an eject symbol (⏏) on it, as Finder shows for ejectable
volumes; clicking the symbol disconnects that server at once. Right-clicking the button offers
Open in Other Panel, Copy Address and Disconnect.

**Why this priority**: Closing a connection where it is shown is natural once connections are
visible; the F12 dialog still covers every case, so this is a convenience.

**Independent Test**: With one connection open and the left panel on the server, hover over the
server button and click ⏏; the button disappears from both volume bars and the left panel shows
the home folder.

**Acceptance Scenarios**:

1. **Given** a server button, **When** the pointer moves over it, **Then** an eject symbol
   appears on the button; when the pointer leaves, the symbol disappears.
2. **Given** the left panel is on the server, **When** the user clicks the eject symbol,
   **Then** the connection is closed without a dialog, the button disappears from both panels'
   volume bars, and every panel that showed that server shows the home folder (as after the F12
   dialog today).
3. **Given** a server button, **When** the user right-clicks it, **Then** a menu offers "Open in
   Other Panel", "Copy Address" and "Disconnect".
4. **Given** that menu, **When** the user chooses "Open in Other Panel", **Then** the other panel
   goes to the connection's last folder (the same folder a click on the button in that panel
   would show) and becomes the active panel.
5. **Given** that menu, **When** the user chooses "Copy Address", **Then** the clipboard holds
   the address of the connection's last folder, e.g. `sftp://tester@127.0.0.1:2222/data/sub`,
   without a password.
6. **Given** a file operation is running on that server, **When** the user disconnects from the
   button, **Then** the app behaves as the F12 dialog does today in the same situation.

---

### User Story 4 - Servers in the volume menu (Priority: P2)

The volume menu of a panel (⌥F1 for the left panel, ⌥F2 for the right one) gets a "Servers"
section with the same open connections, so they are reachable from the keyboard and when the
volume bar is too narrow to show every button.

**Why this priority**: Keyboard access and a fallback for narrow windows; the reference offers
open connections in exactly this menu.

**Independent Test**: With one connection open, press ⌥F1; the menu shows a "Servers" section
with the server; choosing it with the keyboard shows the connection's last folder in the left
panel.

**Acceptance Scenarios**:

1. **Given** one or more open connections, **When** the user opens the volume menu of a panel,
   **Then** a "Servers" section lists them with the same labels and symbol as the buttons, in the
   same order.
2. **Given** that section, **When** the user chooses a server, **Then** the panel does what a
   click on the server's button does.
3. **Given** no open connection, **When** the user opens the volume menu, **Then** there is no
   "Servers" section.

---

### User Story 5 - iCloud Drive and Network in the volume bar (Priority: P2)

Next to the volumes, the volume bar shows "iCloud Drive" (for users who have iCloud Drive set up)
and "Network", as Commander One does. iCloud Drive opens the iCloud Drive folder in the panel.
Network opens a menu with the network volumes mounted in macOS, the open server connections and
"Connect to Server…".

**Why this priority**: iCloud Drive is a frequent destination that today is reachable only
through the volume menu; Network gathers everything network-related in one place. The core
feature (server buttons) works without it.

**Independent Test**: In the test copy of the app on a Mac with iCloud Drive, click "iCloud
Drive" in the left volume bar; the left panel shows the iCloud Drive folder (read only, nothing is
changed). Click "Network"; a menu lists mounted network volumes (if any), open server connections
(if any) and "Connect to Server…"; choosing "Connect to Server…" opens the dialog for that panel.

**Acceptance Scenarios**:

1. **Given** iCloud Drive is set up, **When** the main window opens, **Then** the volume bars show
   "iCloud Drive" (cloud symbol) and "Network" (network symbol) after the volume buttons and
   before the server buttons.
2. **Given** iCloud Drive is not set up on the Mac, **When** the window opens, **Then** there is
   no "iCloud Drive" button.
3. **Given** the left panel shows a folder inside iCloud Drive, **When** the user looks at the
   left volume bar, **Then** "iCloud Drive" is pressed and "Macintosh HD" is not.
4. **Given** the user clicks "iCloud Drive", **When** the panel changes, **Then** it shows the top
   of iCloud Drive, the change is in Back/Forward history and the panel becomes active with focus
   in its file list.
5. **Given** the user clicks "Network", **When** the menu opens, **Then** it lists the mounted
   network volumes (each opens its root in that panel), then the live server connections (each
   does what its server button does), then "Connect to Server…" (opens the dialog for that
   panel); empty groups are left out.

---

### User Story 6 - Choose what the volume bar shows (Priority: P2)

In Settings → Appearance, the user chooses which extra items the volume bar shows: Home, iCloud
Drive, Network and Server connections. Volumes are always shown. The choice applies to both
panels of every window at once and is remembered.

**Why this priority**: Different users want a different bar; a narrow window benefits from a
shorter one. The defaults already match the common case.

**Independent Test**: In the test copy of the app, open Settings → Appearance, turn off "Network"
and turn on "Home"; both volume bars at once drop the Network button and show a Home button;
after quitting and relaunching the choice is kept.

**Acceptance Scenarios**:

1. **Given** a fresh installation, **When** the user opens Settings → Appearance, **Then** a
   "Volume bar shows:" group lists Home (off), iCloud Drive (on), Network (on) and Server
   connections (on).
2. **Given** the user turns an item off or on, **When** the checkbox changes, **Then** both
   panels' volume bars in every window update immediately.
3. **Given** "Server connections" is off and a connection is open, **When** the user looks at the
   volume bar, **Then** no server button is shown, and the connection is still listed in the
   volume menu's "Servers" section and in the Network menu.
4. **Given** "Home" is on, **When** the user clicks the Home button (house symbol), **Then** the
   panel shows the home folder; the Home button is pressed only while the panel is exactly in the
   home folder.
5. **Given** the user changed the choices, **When** the app is quit and launched again, **Then**
   the same items are shown.

---

### Edge Cases

- **Connecting in progress**: a connection that is still being opened (login, host key question)
  shows no button; the button appears once the connection is live.
- **Failed connection**: a connection that never became live (wrong password, cancelled) shows no
  button.
- **Many connections or a narrow window**: server buttons come after the volume buttons and are
  the first to be hidden when the bar is too narrow, as volume buttons are today; every
  connection stays reachable through the volume menu's "Servers" section.
- **Same server, two protocols**: SFTP and FTP to the same host and user are two connections with
  two buttons; when their labels would be equal, the label starts with the protocol
  (`sftp://host`, `ftp://host`).
- **Restored tabs**: after a relaunch no connection is open, so there are no server buttons; a
  tab on a server connects when it is shown, and its button appears then.
- **Several windows**: every main window shows the same set of server buttons, and a connection
  closed from one window disappears from all.
- **Disconnect from the F12 dialog**: buttons of the closed connections disappear at once.
- **Order of items**: volumes, then Home, iCloud Drive, Network (each when shown), then server
  buttons; when the bar is too narrow, items are hidden from the end, so volumes stay visible
  longest.
- **iCloud Drive set up or removed while the app runs**: the button appears or disappears the next
  time the volume bar is rebuilt (a volume is mounted or unmounted, a setting changes, or the app
  starts).
- **Network with nothing to show**: when there are no mounted network volumes and no live
  connections, the Network menu contains only "Connect to Server…".
- **Pressed state**: a panel that shows search results or an archive located on the server
  presses the server button only when its location is on that server.

## Requirements *(mandatory)*

### Functional Requirements

**Toolbar**

- **FR-001**: The main window toolbar MUST offer a "Connect to Server" item (network symbol) that
  runs the existing Connect to Server command for the active panel, identical to ⌘K.
- **FR-002**: "Connect to Server" MUST be part of the default toolbar set; toolbars the user has
  customized are left as they are (no migration).
- **FR-003**: The toolbar MUST offer a "Disconnect" item (running the existing Disconnect command,
  F12) in Customize Toolbar; it MUST NOT be in the default set.
- **FR-004**: Both toolbar items MUST be enabled exactly when their menu commands are.

**Server buttons in the volume bar**

- **FR-005**: When shown (FR-028), the volume bar above each panel MUST show one button per live
  server connection, at the end of the bar (FR-031), in the order the connections were opened.
- **FR-006**: A server button MUST show a network symbol and a label: the host name; when two live
  connections would get the same label, `user@host`; when still equal, `user@host:port`; when
  still equal (different protocols), the label starts with the protocol (`sftp://…`).
- **FR-007**: The button's tooltip MUST show the full address `protocol://user@host:port`.
- **FR-008**: A server button MUST be shown pressed while its panel's location is on that
  connection, by the same rule that presses the volume of a local location.
- **FR-009**: Clicking a server button MUST take that panel to the last folder that panel visited
  on the connection; if the panel has not been there, to the last folder visited on the
  connection by any panel; otherwise to the folder the server opens after login. The change MUST
  be recorded in the panel's Back/Forward history like any folder change.
- **FR-010**: Clicking a server button MUST make that panel the active panel with keyboard focus
  in its file list, as clicking a volume button does.
- **FR-011**: Server buttons MUST appear and disappear in every panel of every main window as soon
  as a connection becomes live or is closed.
- **FR-012**: A connection that dropped MUST keep its button until the user disconnects it; a
  click on it MUST reconnect the same way as opening a remote location does today (saved password
  or the usual prompt) and errors MUST be reported as today.

**Disconnecting from the button**

- **FR-013**: While the pointer is over a server button, the button MUST show an eject symbol;
  clicking the symbol MUST close that connection without a dialog.
- **FR-014**: Right-clicking a server button MUST show a menu with "Open in Other Panel", "Copy
  Address" and "Disconnect".
- **FR-015**: "Open in Other Panel" MUST take the other panel to the folder FR-009 would choose
  for it and make it the active panel.
- **FR-016**: "Copy Address" MUST put the address of the connection's last folder on the
  clipboard as text (`protocol://user@host:port/path`).
- **FR-017**: After a connection is closed from a button or its menu, every panel whose location
  is on that connection MUST show the home folder, and the connection's buttons MUST disappear —
  the same result as closing it in the existing Disconnect dialog.
- **FR-018**: Disconnecting from a button while a file operation uses that connection MUST behave
  as the existing Disconnect dialog does in the same situation.

**Volume menu**

- **FR-019**: The volume menu of each panel (⌥F1 / ⌥F2) MUST contain a "Servers" section listing
  the live connections with the same labels, symbol and order as the buttons; choosing one MUST
  do what FR-009 and FR-010 describe. The section MUST be omitted when there are no connections.

**iCloud Drive, Network and Home**

- **FR-024**: When iCloud Drive is set up on the Mac and shown (FR-028), the volume bar MUST show
  an "iCloud Drive" button (cloud symbol) after the volume and Home buttons; clicking it MUST take the panel
  to the top of iCloud Drive, recorded in history, and activate the panel as FR-010 describes.
- **FR-025**: The "iCloud Drive" button MUST be pressed while the panel's location is inside
  iCloud Drive; the volume containing iCloud Drive MUST then not be pressed.
- **FR-026**: When shown (FR-028), the volume bar MUST show a "Network" button (network symbol)
  after "iCloud Drive"; clicking it MUST open a menu with, in this order and each group only when
  not empty: the network volumes mounted in macOS (choosing one opens its root in that panel), the
  live server connections (choosing one does what FR-009 and FR-010 describe), and "Connect to
  Server…" (opens the Connect to Server dialog for that panel).
- **FR-027**: When shown (FR-028), the volume bar MUST show a "Home" button (house symbol) before
  "iCloud Drive"; clicking it MUST take the panel to the home folder; it MUST be pressed only while
  the panel is exactly in the home folder.

**Volume bar settings**

- **FR-028**: Settings → Appearance MUST offer a "Volume bar shows:" group with four checkboxes:
  Home (off by default), iCloud Drive, Network and Server connections (on by default). Volumes are
  always shown.
- **FR-029**: A change MUST apply immediately to both panels of every main window and MUST be
  remembered across launches.
- **FR-030**: Turning "Server connections" off MUST only hide the server buttons; connections stay
  open and remain listed in the volume menu (FR-019) and the Network menu (FR-026).
- **FR-031**: Items MUST appear in this order: volumes, Home, iCloud Drive, Network, server
  buttons; when the bar is too narrow, items MUST be hidden from the end.

**General**

- **FR-020**: Passwords MUST never appear in labels, tooltips, menus, copied addresses or
  accessibility labels.
- **FR-021**: Each server button MUST be exposed to accessibility as a button labeled with its
  label; the eject symbol as a button labeled "Disconnect <label>".
- **FR-022**: All new user-visible texts MUST be localized (English and Czech).
- **FR-023**: The feature MUST NOT copy, move, rename or delete any file; it only navigates,
  connects and disconnects.

### Deviations from the reference program

- **D-001 (FR-005)**: The reference's drive bar does not show open connections; they appear only
  in the Change Drive menu. Here they also get buttons in the volume bar, as in Commander One.
- **D-002 (FR-009, User Story 2 scenario 3)**: In the reference, a connection used by the other
  panel is disabled in the Change Drive menu, because one connection cannot be in both panels.
  Here connections are shared and both panels may show the same server at once.
- **D-003 (FR-013, FR-014)**: The reference closes connections only in the Disconnect dialog
  (F12). Here a connection can also be closed from its button (eject symbol or menu); the F12
  dialog stays.
- **D-005 (FR-024–FR-031)**: The reference's drive bar shows drives, Documents and Network; here
  the Mac volume bar shows volumes plus optional Home, iCloud Drive, Network and server buttons,
  chosen in Settings. The Network button opens a menu (mounted network volumes, live connections,
  Connect to Server…) instead of a network neighbourhood browser.
- **D-004 (FR-001)**: The reference has its own toolbar buttons; here the Mac toolbar gets
  "Connect to Server" by default and "Disconnect" as an optional item.

### Key Entities

- **Live connection**: an open session to one server endpoint (protocol, user, host, port), kept
  by the app until the user disconnects; shared by all panels and windows.
- **Last folder of a connection**: per panel and overall, the most recent folder visited on the
  connection; kept while the app runs, never stored on disk.
- **Volume bar settings**: four remembered choices (Home, iCloud Drive, Network, Server
  connections) with the defaults of FR-028.
- **Server button**: the volume-bar representation of a live connection: label, tooltip, pressed
  state, eject symbol and menu.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can open the Connect to Server dialog with one click from the main window
  in a default setup.
- **SC-002**: After leaving a server, a user returns to the exact folder they left on it with one
  click in 100 % of tested cases (SFTP and FTP test servers).
- **SC-003**: Every live connection is visible as a button or, when the bar is too narrow, in
  the volume menu, at all times; a closed connection is never shown.
- **SC-004**: Server buttons appear or disappear at the same moment the connection opens or
  closes, in both panels of every window; a user never sees a stale button.
- **SC-005**: No password appears anywhere in the window, menus or clipboard as a result of this
  feature (verified with a password-protected test server).
- **SC-007**: With default settings on a Mac with iCloud Drive, the volume bar shows the volumes,
  iCloud Drive, Network and every live connection, and a user reaches iCloud Drive with one click.
- **SC-008**: A change in "Volume bar shows:" is visible in every volume bar within the same moment
  and survives a relaunch in 100 % of tested cases.
- **SC-006**: No volume bar action changes any file or folder (verified by GUI tests against
  the local test servers only).

## Assumptions

- The existing Connect to Server dialog, the Disconnect dialog and the rules for opening,
  authenticating and keeping connections are reused unchanged.
- The app has a single user today, so no migration of customized toolbars is needed.
- The volume bar keeps its current layout rules; server buttons follow the volume buttons and
  use the same button style.
- iCloud Drive is the folder macOS uses for it in the user's Library; it counts as set up when that
  folder exists. Opening it only browses; downloading or evicting cloud files is unchanged.
- Network volumes are the volumes macOS reports as network volumes (SMB, AFP, NFS); they keep
  their own volume buttons as today and are additionally listed in the Network menu.
- "Last folder" is remembered only while the app runs; after a relaunch it starts empty.
- Out of scope: a network neighbourhood browser (finding SMB shares on the local network); hiding
  the whole volume bar; saved servers that are not connected (from ⌘K) in the volume bar; dropping files
  onto a server button; free or used space of a server; server buttons in the Find, Compare,
  Viewer or Disk Map windows; changes to how connections are opened, authenticated or kept alive.
- Verification follows the project rules: unit tests for labels, ordering and last-folder logic
  in the core; GUI checks only in the test copy of the app against the local test SFTP/FTP
  servers on 127.0.0.1, never against real servers.
