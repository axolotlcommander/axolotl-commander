# Feature Specification: Network Places in the Panel

**Feature Branch**: `006-network-places`

**Created**: 2026-10-09

**Status**: Implemented

**Input**: User description: "The Network button next to Macintosh HD should not open a menu for
connecting; it should show the places on the network, as Commander One does (a 'Síť' folder with
DISKSTATION, smb, PC), the same way clicking iCloud Drive shows what is on the drive." Changes the
Network item of [004-server-connection-buttons](../004-server-connection-buttons/spec.md)
(User Story 5, FR-026), which is closed.

## Clarifications

### Session 2026-10-09

- Q: Which servers are listed? → A: Servers that announce themselves on the local network
  (Bonjour): SMB, AFP and SFTP, plus the network volumes already mounted in macOS.
- Q: What happens to the menu the Network button opens today? → A: A click shows the Network
  folder in the panel; the menu moves to the right-click of the button.
- Q: iCloud Drive turned off in System Settings? → A: Its button stays hidden, as today (spec 004);
  when iCloud Drive is on, a click already shows its contents.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse the network in a panel (Priority: P1)

The user clicks "Network" in the volume bar (or chooses Network in the volume menu ⌥F1/⌥F2).
The panel shows a virtual folder "Network" listing the servers found on the local network and
the network volumes already mounted, like a folder of the Mac. The list follows servers that
appear and disappear.

**Why this priority**: This is the feature: network places visible without knowing their
addresses, as in Commander One and Finder.

**Independent Test**: With a Bonjour SMB server on the network (here `DISKSTATION`), click
"Network" in the left volume bar of the test copy; the left panel shows a row "DISKSTATION" with
the extension "smb", and the Network button is pressed.

**Acceptance Scenarios**:

1. **Given** a panel on a local folder, **When** the user clicks "Network" in its volume bar,
   **Then** the panel shows the Network folder: one row per discovered server (name, extension
   `smb`, `afp` or `sftp`, a server icon) and one row per mounted network volume (its name and
   volume icon); the window title and the path bar show "Network"; the Network button is pressed.
2. **Given** the Network folder, **When** a server starts or stops announcing itself, **Then** its
   row appears or disappears within a few seconds without a manual refresh; ⌘R also refreshes.
3. **Given** the Network folder, **When** the user presses Backspace or ⌘[, **Then** the panel
   returns to where it was before (Back history); the Network folder has no ".." row.
4. **Given** the volume menu (⌥F1), **When** the user opens it, **Then** it contains "Network";
   choosing it shows the Network folder.
5. **Given** no server on the network and no mounted network volume, **When** the Network folder
   is shown, **Then** it is empty and the status line says so; nothing fails.

---

### User Story 2 - Open a server from the Network folder (Priority: P1)

Enter (or a double-click) on a server opens it: an SMB or AFP server asks for the login and the
share through the standard macOS dialog (with passwords from the Keychain), mounts the share and
the panel enters it; an SFTP server opens the Connect to Server dialog with its address filled
in. Enter on a mounted network volume enters it.

**Why this priority**: Listing alone is not useful; getting to the files is.

**Independent Test**: In the Network folder, Enter on a mounted network volume shows its root;
Enter on `DISKSTATION` (smb) shows the macOS login/share dialog (verified by the maintainer on
the real NAS — automated GUI tests never connect to real servers).

**Acceptance Scenarios**:

1. **Given** the cursor on an SMB or AFP server, **When** the user presses Enter, **Then** the
   standard macOS dialog asks for the account (Keychain used when stored) and lets the user pick
   a share; after mounting, the panel shows the share's root and Back returns to the Network
   folder.
2. **Given** the share is already mounted, **When** the user presses Enter on its server, **Then**
   the dialog still lets the user pick a share, and choosing a mounted one enters it without a
   second mount.
3. **Given** the user cancels the dialog or the login fails, **Then** the panel stays in the
   Network folder; a failure (not a cancel) shows the system's reason.
4. **Given** the cursor on an SFTP server, **When** the user presses Enter, **Then** the Connect to
   Server dialog opens with protocol SFTP, the server's host name and port filled in.
5. **Given** the cursor on a mounted network volume, **When** the user presses Enter, **Then** the
   panel shows the volume's root.

---

### User Story 3 - The Network button and menu (Priority: P2)

The Network button in the volume bar shows the Network folder on a click; its right-click shows
the quick menu that spec 004 put on the click (mounted network volumes, open connections,
Connect to Server…).

**Why this priority**: Keeps the quick menu reachable after the click changed meaning.

**Independent Test**: Right-click "Network": the menu lists mounted network volumes, the open
connections and Connect to Server….

**Acceptance Scenarios**:

1. **Given** the volume bar, **When** the user right-clicks "Network", **Then** the quick menu of
   spec 004 appears; a left click never opens it.
2. **Given** the panel shows the Network folder, **Then** the Network button is pressed and no
   volume button is.

---

### Edge Cases

- **Copy, move, delete, rename, links, new folder, packing** while the Network folder is shown:
  disabled; it is not a folder on disk. When the other panel shows the Network folder, F5/F6, pack,
  unpack and new links do not offer it as the destination (they use the active panel's folder, as
  for search results), and dropping items on the Network folder is refused.
- **Dragging** rows out of the Network folder is not possible (servers are not files; dragging a
  whole mounted share is too easy a mistake).
- **Two servers with the same name** but different protocols: two rows (`NAS.smb`, `NAS.afp`).
- **A server announced on several network interfaces** (Wi-Fi and Ethernet): one row.
- **A server name containing dots**: the extension column still shows the protocol.
- **The app starts with a panel restored to the Network folder**: discovery starts, rows appear
  as servers answer.
- **Local network access**: macOS may ask once whether the app may find devices on the local
  network; if the user refuses, the list shows only mounted volumes.
- **Hot paths**: the Network folder cannot be stored as a hot path; going to the Network folder
  through the path field (⌘L) is not supported.
- **Command line and Open Terminal** while the Network folder is shown use the home folder.

## Requirements *(mandatory)*

### Functional Requirements

**Network folder**

- **FR-001**: The app MUST provide a virtual Network folder for a panel, reached by a click on the
  volume bar's Network button and by a "Network" item of the volume menu (⌥F1/⌥F2).
- **FR-002**: The Network folder MUST list servers announced on the local network over Bonjour for
  SMB, AFP and SFTP, one row per server and protocol (duplicates from several interfaces merged),
  named by the announced name with the protocol as the extension and a server icon.
- **FR-003**: It MUST also list the network volumes currently mounted in macOS, with their names
  and volume icons.
- **FR-004**: The list MUST update by itself when servers appear or disappear or volumes are
  mounted or unmounted; ⌘R refreshes it too. Discovery starts the first time the Network folder
  is shown and then runs while the app runs; it sends only the standard discovery queries, never
  anything to a server until the user opens it.
- **FR-005**: The Network folder MUST show "Network" in the window title and the path bar, press
  the Network button of its panel's volume bar, and have no ".." row; Backspace (Enclosing Folder)
  goes Back, or to the home folder when there is no history.
- **FR-006**: Entering and leaving the Network folder MUST be recorded in Back/Forward history and
  survive tab switches and relaunch like any location.

**Opening**

- **FR-007**: Enter or double-click on an SMB or AFP server MUST resolve its address and mount it
  through the macOS network file system service with its standard user interface (login with
  Keychain, share selection); on success the panel MUST enter the mounted share; a cancel MUST
  leave the panel unchanged silently; a failure MUST show the system's reason.
- **FR-008**: Enter on an SFTP server MUST open the Connect to Server dialog for the panel with
  protocol SFTP and the resolved host and port filled in.
- **FR-009**: Enter on a mounted network volume MUST enter its root.

**Button and menu**

- **FR-010**: A left click on the volume bar's Network button MUST show the Network folder in that
  panel; a right-click MUST show the quick menu of spec 004 (mounted network volumes, open
  connections, Connect to Server…).

**Safety**

- **FR-011**: While a panel shows the Network folder, only navigation commands MAY be enabled for
  it (open, back/forward, home, go to folder, volume menu, tabs, sorting, view mode, refresh,
  connect/disconnect); every command that writes, reads file contents or uses the panel's folder
  as a place on disk MUST be disabled.
- **FR-012**: The Network folder MUST never be used as the destination of copy, move, pack,
  unpack, new links or a drop; such commands started in the other panel MUST offer the active
  panel's folder instead, and any request with the Network folder as the destination MUST be
  refused.
- **FR-013**: No row of the Network folder MAY be dragged.

**General**

- **FR-014**: New texts in English and Czech; rows and the Network button accessible (name and
  protocol read out).

### Deviations from the reference program

- **D-001 (FR-002)**: The reference's Network (Windows network neighbourhood plugin) lists
  workgroups and computers of the Windows network; here servers announced over Bonjour, plus
  mounted network volumes. Workgroup browsing (NetBIOS) is not offered.
- **D-002 (FR-007)**: Shares are not listed as a folder level; the macOS dialog chooses the share
  and mounts it.
- **D-003 (FR-010)**: Changes spec 004 FR-026: the quick menu moves from the click to the
  right-click.

### Key Entities

- **Network service**: announced name, protocol (SMB, AFP, SFTP), Bonjour domain; resolved on
  demand to a host name and port.
- **Network folder row**: a service or a mounted network volume.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A server that announces itself appears in the Network folder within 5 seconds of
  opening it, without typing any address.
- **SC-002**: From the Network folder to the files of an SMB share takes one Enter plus the macOS
  login/share dialog.
- **SC-003**: No command can write to or through the Network folder (checked for every command in
  the menus with the Network folder active and as the other panel).
- **SC-004**: All acceptance scenarios except real-server mounting pass in the test copy of the
  app; mounting is confirmed by the maintainer on their NAS.

## Assumptions

- macOS 15+ with Bonjour; the app may need the Local Network permission (macOS asks the user).
- Mounting uses the system's network file system service, the same as Finder's Connect to Server;
  shares appear under /Volumes.
- SFTP servers announce `_sftp-ssh._tcp`; SMB `_smb._tcp`; AFP `_afpovertcp._tcp`.
- Out of scope: NetBIOS/workgroup browsing, NFS, WebDAV, listing shares without mounting,
  unmounting from the Network folder (⏏ in the volume bar and the F12 dialog stay), FTP servers
  (rarely announced).
