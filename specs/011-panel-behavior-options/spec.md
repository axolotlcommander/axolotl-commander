# Feature Specification: Panel Behavior Options

**Feature Branch**: `011-panel-behavior-options`

**Created**: 2026-10-12

**Status**: Draft

**Input**: User description: "Panel behavior options: four switches in Settings that make the panels
behave like classic two-panel file managers, each independent and each off unless stated (Space
movement keeps today's default)."

## Context

Spec 010 gave classic two-panel file manager users their keys: free default chords and the opt-in
"Classic Commander" key scheme. Some habits are not keys but **behavior**, and they were left for this
spec on purpose. Each becomes a setting that anyone can switch, independent of the key scheme. The
product does not name any other file manager.

**What the app does today:**
- **Space** marks or unmarks the cursor item (a folder also gets its size) and moves the cursor down.
- **Typed characters** start quick search in the panel.
- **Open in Left Panel / Open in Right Panel** (⌃⇧← / ⌃⇧→, ⌃← / ⌃→, the menu and the context menu)
  always send the cursor item to the other panel. The arrow only decides whether the focus moves
  there. The command is disabled on "..".
- **A volume button** above a panel, and a volume chosen from the volume menu (⌥F1 / ⌥F2), always
  opens the volume root. Home, iCloud Drive, Network and saved server entries open their own place.

A comparison with the classic habits was made beforehand (a local research note, not published).
This spec ships with specs 010–016 in one release.

**Maintainer decisions (2026-10-12, in chat):**
- Letters to the command line follow the classic model: the focus stays in the panel.
- The classic ⌃← / ⌃→ logic is a setting, off by default.
- Volume buttons take over the other panel's folder **and** remember the last folder per volume, as one
  setting.
- The key scheme does not switch these settings. The Keyboard tab only says where they are.

## Clarifications

### Session 2026-10-12

- Q: How does typing into the command line work? → A: The classic model. The focus stays in the
  panel, the characters are appended to the command line, and quick search moves to ⌥ + character.
- Q: Is the classic ⌃← / ⌃→ logic the default? → A: No. It is a setting, off by default.
- Q: What do volume buttons do with the setting on? → A: Take over the other panel's folder on the same
  volume, otherwise reopen the last folder used on that volume; one setting for both.
- Q: Does choosing the Classic Commander key scheme switch these settings on? → A: No. They are
  separate. Settings → Keyboard points to them.
- Q: A volume button for the volume the panel already shows, when the other panel is on the same
  volume: root or the other panel's folder? → A: The root, as today; taking over the other panel's
  folder already has its own command (Same Folder as Other Panel). *Decided while the maintainer was
  away; to review.*

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Space marks and stays (Priority: P1)

A user who marks items one by one and then looks at what they marked turns off "Space moves the cursor
down". Space now marks or unmarks the cursor item and the cursor stays on it. A folder still gets its
size.

**Why this priority**: it is the simplest habit and the one a classic user notices at the first
keystroke.

**Independent Test**: switch the setting off, press Space on a file and on a folder, and check the
mark, the folder size and the cursor position; switch it on and check today's behavior.

**Acceptance Scenarios**:

1. **Given** the setting is off and the cursor is on a file, **When** the user presses Space, **Then**
   the file is marked and the cursor stays on it; another Space unmarks it.
2. **Given** the setting is off and the cursor is on a folder, **When** the user presses Space, **Then**
   the folder is marked, its size is calculated and the cursor stays on it.
3. **Given** the setting is on (the default), **When** the user presses Space, **Then** the item is
   marked and the cursor moves down, as today.
4. **Given** either setting, **When** the user presses Insert, **Then** it behaves as today.
5. **Given** a running quick search, **When** the user presses Space, **Then** a space is added to the
   search, as today.

---

### User Story 2 - Typing goes to the command line (Priority: P1)

A user switches on "Typing goes to the command line". In a panel they type `zip -r archive.zip `. The
characters appear in the command line while the panel keeps the focus. They move the cursor to a
folder with the arrows and press ⌃↩ to add its name, then press Return to run the line. To jump to a
file by name they use ⌥ + character, which starts quick search.

**Why this priority**: it is the habit that changes the most keystrokes. Without it, every command
line use needs an extra key to focus the line and another to get back.

**Independent Test**: switch the setting on, type into a panel, build a line with ⌃↩, clear it with
Esc, and start quick search with ⌥ + character. Never run a line that changes files during the check.

**Acceptance Scenarios**:

1. **Given** the setting is on and the command line is empty, **When** the user types "ls", **Then**
   the command line shows "ls" and the panel still has the focus (↓ moves the panel cursor).
2. **Given** the command line holds "ls -l ", **When** the user moves the cursor to a file and presses
   ⌃↩, **Then** the line becomes "ls -l " followed by the file's name, as today.
3. **Given** the command line holds text, **When** the user presses Return in the panel, **Then** the
   line runs exactly as if Return were pressed in the command line.
4. **Given** the command line holds text, **When** the user presses Backspace, **Then** the last
   character of the line is removed and the panel does not go to the parent folder; with the line
   empty, Backspace goes to the parent folder as today.
5. **Given** the command line holds text, **When** the user presses Esc, **Then** the line is cleared.
6. **Given** the command line holds text, **When** the user presses Space, **Then** a space is added to
   the line and nothing is marked; with the line empty, Space marks as today.
7. **Given** the setting is on, **When** the user presses ⌥R, **Then** quick search starts with "r";
   further plain characters extend the search; Esc ends it.
8. **Given** the command line is hidden, **When** the user types a character in a panel, **Then** the
   command line appears with that character.
9. **Given** the setting is off, **When** the user types characters, **Then** quick search runs as
   today and ⌥ + character does nothing new.

---

### User Story 3 - ⌃← / ⌃→ change the panel the arrow points to (Priority: P2)

A user switches on "⌃← / ⌃→ change the panel the arrow points to". In the left panel, ⌃→ opens the
cursor folder in the right panel. ⌃← makes the left panel open what the right panel's cursor is on, or
the right panel's folder. The focus stays in the left panel in both cases.

**Why this priority**: valuable for heavy keyboard users. Today's behavior also works, so it can come
after the P1 stories.

**Independent Test**: switch the setting on, use Open in Left Panel / Open in Right Panel (by key or
menu) from each panel on a folder, a file and "..", and check which panel changes and where the focus
is; switch it off and check today's behavior.

**Acceptance Scenarios**:

1. **Given** the setting is on, the left panel is active and its cursor is on folder A, **When** the user
   runs Open in Right Panel, **Then** the right panel opens A and the focus stays in the left panel.
2. **Given** the setting is on, the left panel is active and the right panel's cursor is on folder B,
   **When** the user runs Open in Left Panel, **Then** the left panel opens B and keeps the focus.
3. **Given** the setting is on and the source panel's cursor is on a file, **When** the user runs the
   command, **Then** the target panel opens the folder holding that file with the file under the
   cursor.
4. **Given** the setting is on and the source panel's cursor is on "..", **When** the user runs the
   command, **Then** the target panel opens the source panel's current folder.
5. **Given** the setting is on and the source panel shows find results or a branch view, **When** the
   cursor is on a file, **Then** the target panel opens that file's own folder.
6. **Given** the setting is off, **When** the user runs either command, **Then** it behaves as today.

---

### User Story 4 - Volume buttons follow the other panel or the last folder (Priority: P2)

A user switches on "Volume buttons open the other panel's folder or the last folder used there". The
left panel shows a folder deep on an external disk. The user clicks that disk's button above the right
panel, and the right panel opens the same folder. Later the right panel goes to the startup disk. When
the user picks the external disk again for the right panel, it opens the folder it last showed there.

**Why this priority**: it saves navigation between two volumes, but the path bar, hot paths and Same
Folder as Other Panel already cover most of it.

**Independent Test**: with two panels on test folders, switch the setting on and pick volumes from the
buttons and the volume menu; check rules a–d (FR-018); switch it off and check that the root opens.

**Acceptance Scenarios**:

1. **Given** the setting is on and the other panel shows folder F on volume V, **When** the user picks V
   for this panel (which is not on V), **Then** this panel opens F.
2. **Given** the setting is on and this panel already shows a folder on V, **When** the user picks V,
   **Then** this panel opens the root of V.
3. **Given** the setting is on, this panel showed folder G on V earlier in this window, and the other
   panel is not on V, **When** the user picks V for this panel, **Then** it opens G.
4. **Given** the remembered folder G no longer exists, **When** the user picks V, **Then** the panel
   opens the root of V.
5. **Given** the setting is on, **When** the user picks Home, iCloud Drive, Network or a saved server,
   **Then** it opens its own place, as today.
6. **Given** the setting is off, **When** the user picks any volume, **Then** the panel opens the volume
   root, as today.

---

### User Story 5 - Find and switch the options (Priority: P1)

A user opens Settings → General and finds a "Panels" section with the four switches, each with a short
explanation. A Classic Commander user in Settings → Keyboard sees a note next to the key scheme
picker that says where the behavior options are. The options take effect at once in every window and
travel with the exported settings.

**Why this priority**: without the switches none of the other stories can be used.

**Independent Test**: open Settings, change each switch, and check its effect in an open window
without a restart; export the settings and check that the four values are in the file; import a file
with other values and check that they apply.

**Acceptance Scenarios**:

1. **Given** Settings → General, **When** the user looks at the "Panels" section, **Then** it shows the
   four switches with their defaults: Space moves the cursor down on; the other three off.
2. **Given** an open window, **When** the user changes a switch, **Then** the next keystroke or click in
   any window follows the new value.
3. **Given** Settings → Keyboard, **When** the user looks at the key scheme picker, **Then** a note
   points to the behavior options in Settings → General.
4. **Given** changed switches, **When** the user exports the settings and imports the file on another
   Mac, **Then** the four switches have the exported values.
5. **Given** the user selects the Classic Commander scheme, **When** they look at the behavior options,
   **Then** the options have not changed.

---

### Edge Cases

- **Typing during quick search**: while quick search runs, characters, Space and Backspace go to the
  search, as today, even with "Typing goes to the command line" on.
- **Typing in other places**: in an archive, on a server or in find results, typing fills the command
  line the same way. Running the line follows today's command line rules for that place.
- **Keys with a command**: keypad keys and chords with ⌘, ⌃ or ⌥ that are bound to a command keep running
  that command, even with the line holding text.
- **⇧Return**: with the line holding text it works on the panel item, as in the command line today.
- **Clicking into the command line**: normal text editing, as today; Esc or ⇥ returns to the panel.
- **".." in the source panel**: with the arrow setting on, ⌃← in the left panel (or ⌃→ in the right
  panel) while the other panel's cursor is on ".." makes the active panel open the other panel's
  current folder.
- **Archives and servers in ⌃← / ⌃→**: the same rules as today decide what can be opened, applied to
  the source panel. Where today's command is disabled for an item, it stays disabled, except "..".
- **Volume button while the other panel is in an archive or on a server**: that is not "a folder on the
  volume"; the rules fall through to the remembered folder or the root.
- **Remembered folder gone**: a deleted folder, or a volume that was ejected and mounted again, falls
  back to the root.
- **The startup disk**: folders under Home count as being on the startup disk volume.
- **Mission Control** takes ⌃← / ⌃→ by default. Settings → Keyboard already explains this (spec 010).
  ⌃⇧← / ⌃⇧→ and the menu items work either way.
- **Dead keys**: characters composed from dead keys behave as they do in quick search today.

## Requirements *(mandatory)*

### Functional Requirements

#### Space

- **FR-001**: The app MUST offer the setting "Space moves the cursor down", on by default.
- **FR-002**: With FR-001 off, Space MUST mark or unmark the cursor item and calculate a folder's size
  as today, and MUST leave the cursor where it is. With FR-001 on, Space MUST behave as today.
- **FR-003**: FR-001 MUST NOT change Insert, the other marking keys, or Space during quick search.

#### Typing into the command line

- **FR-004**: The app MUST offer the setting "Typing goes to the command line", off by default.
- **FR-005**: With FR-004 on, a character that would start quick search today (typed without ⌘, ⌃ or
  ⌥; ⇧ allowed) MUST be appended to the command line instead. The keyboard focus MUST stay in the
  panel.
- **FR-006**: With FR-004 on, a hidden command line MUST be shown when a character is appended, the
  same way Focus Command Line shows it.
- **FR-007**: With FR-004 on and the command line holding text, these panel keys MUST act on the line:
  - Return runs the line exactly as Return in the command line does;
  - Backspace removes the line's last character;
  - Esc clears the line;
  - Space appends a space.
  With the line empty these keys MUST behave as today.
- **FR-008**: With FR-004 on, ⌥ + a character MUST start quick search with the character the key
  produces without ⌥. While quick search runs, characters, Space, Backspace, Esc and navigation keys
  MUST behave as in quick search today.
- **FR-009**: Keys bound to commands, navigation keys, F-keys and the insert-into-command-line commands
  (⌃↩, ⌃J, ⌃⇧↩, ⌃P and the others) MUST keep acting as today with FR-004 on, whatever the line holds.
- **FR-010**: With FR-004 off, typing and ⌥ + character MUST behave exactly as today.

#### Open in Left / Right Panel

- **FR-011**: The app MUST offer the setting "⌃← / ⌃→ change the panel the arrow points to", off by
  default. It MUST apply to Open in Left Panel and Open in Right Panel however they are run (any chord,
  the menu, the context menu).
- **FR-012**: With FR-011 on, the panel named by the command (left or right) MUST be the target and the
  other panel the source, whichever panel is active.
- **FR-013**: With FR-011 on, the target MUST open:
  - for a source cursor item today's command would open (a folder, an archive): that item;
  - for a file: the folder holding it, with the file under the cursor (including find results and
    branch views, where that is the file's own folder);
  - for "..": the source panel's current folder.
- **FR-014**: With FR-011 on, the focus MUST stay in the panel that was active.
- **FR-015**: With FR-011 on, the command MUST be enabled exactly when the source item can be opened
  under FR-013. Items today's command cannot open stay disabled; ".." becomes enabled.
- **FR-016**: With FR-011 off, both commands MUST behave exactly as today.

#### Volume buttons

- **FR-017**: The app MUST offer the setting "Volume buttons open the other panel's folder or the last
  folder used there", off by default. It MUST apply to the volume buttons above a panel and to a volume
  chosen from the volume menu (⌥F1 / ⌥F2).
- **FR-018**: With FR-017 on, picking volume V for a panel MUST open, in this order of precedence:
  - a. the root of V if the panel already shows a folder on V;
  - b. otherwise the other panel's folder if the other panel shows a folder on V;
  - c. otherwise the last folder this panel showed on V while the window has been open, if it still
    exists;
  - d. otherwise the root of V.
- **FR-019**: The last folder per volume MUST be remembered per panel, in memory only, for as long as the
  window is open. It MUST survive switching tabs within the panel. It MUST NOT be saved or exported.
- **FR-020**: Home, iCloud Drive, Network and saved server entries MUST open their own place regardless
  of FR-017.
- **FR-021**: A panel showing an archive, a server or the Network place MUST NOT count as showing a
  folder on a volume for FR-018 a and b.
- **FR-022**: With FR-017 off, picking a volume MUST open its root, as today.

#### Settings

- **FR-023**: Settings → General MUST have a "Panels" section with the four switches of FR-001, FR-004,
  FR-011 and FR-017, each with a one-line explanation.
- **FR-024**: A change of any switch MUST take effect in all open windows without a restart.
- **FR-025**: Settings → Keyboard MUST show, next to the key scheme picker, a note pointing to the
  behavior options in Settings → General.
- **FR-026**: Choosing a key scheme MUST NOT change any of the four switches.
- **FR-027**: The four switches MUST be part of the exported and imported preferences. A settings file
  without them (from an older version) MUST leave them unchanged on import.

### Key Entities

- **Behavior options**: four user preferences:
  - Space moves the cursor down (on/off, default on);
  - Typing goes to the command line (default off);
  - ⌃← / ⌃→ change the panel the arrow points to (default off);
  - Volume buttons open the other panel's folder or the last folder used there (default off).
- **Last folder per volume**: for each panel, a map from a volume to the folder last shown there. It
  lives in memory while the window is open.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With default settings every keystroke and click covered by this spec behaves exactly as
  before the update (checked automatically for the decision logic, and in the GUI check).
- **SC-002**: With "Typing goes to the command line" on, a user can build and run a command line that
  names the cursor item without the focus ever leaving the panel: type, ⌃↩, Return.
- **SC-003**: A switch change applies to the next keystroke or click in every window, without a
  restart.
- **SC-004**: Each of the four rules (Space, typing, arrows, volumes) has automated tests for every case
  listed in its requirements.
- **SC-005**: An export and import round trip keeps all four switches (checked automatically).

## Assumptions

- The four switches are user preferences. They join the Preferences section of the settings file
  without a format change (spec 010).
- "Typing goes to the command line" takes the same characters quick search takes today, including the
  Czech number row characters.
- Return with text in the line runs it exactly as the command line does today. That includes opening
  folders, `cd` and running programs in the terminal.
- "Last folder on a volume" is decided by the volume a folder belongs to, as the system reports it.
- The open-in-other-panel item of the panel context menu is one of the two commands. It follows FR-011
  like the menu does.

## Out of Scope

- Tying the behavior options to the key scheme.
- Quick search variants with ⌃⌥ + character.
- The quick filter (spec 013) and the folder history list (spec 014).
- Remembering last folders across launches, or exporting them.
- Changes to the path bar or breadcrumb behavior.
- ← / → in the Detailed view moving into the command line.

## Deviations from the classic reference

- Space keeps "moves down" as the default, since macOS users of the app expect today's behavior.
- Quick search stays the default for typed characters.
- Quick search in the typing mode uses ⌥ + character only.
- Last folders are remembered per panel and only while the window is open.
- A volume button for the volume the panel already shows always opens the root (see Clarifications).
