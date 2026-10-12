# Feature Specification: Tabs from the Keyboard

**Feature Branch**: `012-keyboard-tabs`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "Tabs from the keyboard: open the cursor item in a new tab (also in the
other panel and in the background), a tab list with recently closed tabs, reopening a closed tab,
swapping the panels with all their tabs, and closing the other tabs."

## Context

Each panel has tabs. Today the user can:
- open a new tab (a copy of the current one) with ⌃⇧T, the menu or the tab strip;
- close a tab with ⌃⇧W;
- move between tabs with ⌃⇧Page Down / ⌃⇧Page Up (Classic Commander adds ⌃T, ⌃W and ⌃⇥ / ⌃⇧⇥);
- close the other tabs from the tab strip's context menu;
- open a folder of the path bar in a new tab with ⌘-click.

Classic two-panel file managers can do much more with tabs from the keyboard. The scope was agreed in
chat on 2026-10-12 (the list of specs 010–016):
- open the cursor item in a new tab;
- open it in a new tab of the other panel;
- open it in a background tab;
- a tab list that also shows recently closed tabs;
- swapping the panels with all their tabs;
- closing all other tabs.

Following spec 010, every new command gets a free default chord, and its classic chord goes into the
Classic Commander scheme when the classic chord collides. The product does not name any other file
manager. This spec ships with specs 010–016 in one release.

## Clarifications

### Session 2026-10-13

All answers below were *decided while the maintainer was away; to review*. The scope itself was
agreed in chat on 2026-10-12.

- Q: What does "open in a new tab" open for each kind of cursor item? → A: What Enter would enter:
  - a folder or an archive: its content;
  - "..": the parent folder;
  - a file or a package: the new tab is a copy of the current folder with that item under the cursor.
- Q: Default chords? → A: macOS and browser habits, next to the classic chords:
  - Open in New Tab: ⌃↑ and ⌥⌘↓;
  - Open in Background Tab: ⌥⌘⇧↓;
  - Open in New Tab of Other Panel: ⌃⇧↑;
  - Reopen Closed Tab: ⌘⇧T;
  - Close Other Tabs: ⌥⌘W;
  - Tab List: ⌃⇧A and ⌘⇧\;
  - Swap Panels with All Tabs: ⌃⇧U.

  Each command is also in the Go or View menu. Classic Commander moves ⌃⇧W from Close Tab to Close
  Other Tabs; Close Tab keeps ⌃W there.
- Q: Where does the focus go after Open in New Tab of Other Panel? → A: It stays in the active panel.
  The other panel switches to the new tab.
- Q: Which tabs does the tab list show? → A: The active panel's open tabs, then its recently closed
  tabs (at most 10, newest first). Choosing an open tab switches to it. Choosing a closed tab reopens
  it after the current tab.
- Q: Are closed tabs remembered across launches? → A: No. They are remembered per panel, in memory,
  while the window is open.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Open the cursor item in a new tab (Priority: P1)

A user is in a project folder and wants to look into `docs` without losing their place. They press ⌃↑
(or ⌥⌘↓) on `docs`. A new tab opens after the current one, showing `docs`. The original tab stays as it
was. With ⌥⌘⇧↓ the tab opens in the background and the panel stays where it is. With ⌃⇧↑ the new tab
opens in the other panel.

**Why this priority**: it is the most frequent tab action from the keyboard. Today the only way is a
copy of the tab followed by navigation.

**Independent Test**: on a test folder, use each of the three commands on a folder, a file and "..",
and check the tabs of both panels and the focus.

**Acceptance Scenarios**:

1. **Given** the cursor is on folder `docs`, **When** the user runs Open in New Tab, **Then** a new tab
   after the current one shows `docs` and is active; the previous tab still shows the old folder with
   the cursor on `docs`.
2. **Given** the cursor is on a file, **When** the user runs Open in New Tab, **Then** the new tab shows
   the same folder with the cursor on that file.
3. **Given** the cursor is on "..", **When** the user runs Open in New Tab, **Then** the new tab shows
   the parent folder with the cursor on the folder the user came from.
4. **Given** the cursor is on folder `docs`, **When** the user runs Open in Background Tab, **Then** a new
   tab showing `docs` appears after the current one, and the panel stays on the current tab.
5. **Given** the cursor is on folder `docs` in the left panel, **When** the user runs Open in New Tab of
   Other Panel, **Then** the right panel gets a new active tab showing `docs`, and the focus stays in the
   left panel.
6. **Given** the cursor is on an archive, **When** the user runs Open in New Tab, **Then** the new tab
   shows the content of the archive.

---

### User Story 2 - Reopen closed tabs and see all tabs (Priority: P1)

A user closes a tab by mistake and presses ⌘⇧T. It comes back with its folder and cursor. Later they
press ⌘⇧\ (or ⌃⇧A). A list of the panel's tabs appears, followed by the recently closed ones. They pick
one with the arrows and Return.

**Why this priority**: closing a tab must not lose work. The list also makes many tabs navigable from
the keyboard.

**Independent Test**: open three tabs, close two, reopen one with ⌘⇧T, open the tab list, and check its
content; choose an open tab and a closed tab from it.

**Acceptance Scenarios**:

1. **Given** a tab was closed, **When** the user runs Reopen Closed Tab, **Then** the tab comes back after
   the current tab with its folder, cursor, sort and history, and is active.
2. **Given** no tab was closed in this panel, **When** the user runs Reopen Closed Tab, **Then** nothing
   happens and the command is disabled.
3. **Given** a panel with tabs A, B, C and closed tabs X, Y, **When** the user opens the tab list,
   **Then** it shows A, B, C (the active one checked), a separator, a "Recently Closed" heading, and Y,
   X.
4. **Given** the tab list, **When** the user chooses an open tab, **Then** the panel switches to it;
   choosing a closed tab reopens it after the current tab.
5. **Given** more than 10 tabs were closed, **When** the user opens the tab list, **Then** only the 10
   newest closed tabs are offered.
6. **Given** the tab list is open, **When** the user presses Esc, **Then** it closes and nothing changes.

---

### User Story 3 - Close other tabs and swap with all tabs (Priority: P2)

A user has collected many tabs and wants only the current one: ⌥⌘W closes the others, and they remain
reachable as recently closed tabs. Another time they want the left side's whole set of tabs on the
right: ⌃⇧U swaps the panels with all their tabs.

**Why this priority**: useful cleanup and arrangement; the tab strip's context menu already offers
Close Other Tabs with the mouse.

**Independent Test**: with several tabs in both panels, run Close Other Tabs and Swap Panels with All
Tabs, and check both tab strips, the active tabs and the focus.

**Acceptance Scenarios**:

1. **Given** a panel with tabs A, B (active), C, **When** the user runs Close Other Tabs, **Then** only B
   remains, and A and C are among the recently closed tabs.
2. **Given** a panel with one tab, **When** the user looks at Close Other Tabs, **Then** it is disabled.
3. **Given** the left panel has tabs A, B and the right panel has tab C, **When** the user runs Swap
   Panels with All Tabs, **Then** the left panel has tab C and the right panel has tabs A, B. Each panel
   shows the tab that was active on the other side, and the focus stays on the same side.
4. **Given** the scheme Classic Commander, **When** the user presses ⌃⇧W, **Then** the other tabs close.
   ⌃W closes the current tab.

---

### Edge Cases

- **Cursor item on a server or in find results / branch view**: Open in New Tab follows what Enter
  would enter. A file in find results opens a tab with the file's own folder and the file under the
  cursor.
- **A folder that cannot be read**: the new tab is not created. The error is reported as for any failed
  navigation, and the current tab is unchanged.
- **A reopened tab whose folder is gone**: it opens at the nearest existing parent, as tab restore does
  today.
- **The last tab** cannot be closed, as today. Close Other Tabs with one tab does nothing.
- **Quick search running**: ⌃↑ / ⌃↓ keep moving between matches, as today. The new chord acts only
  when quick search is not running.
- **Mission Control** takes ⌃↑ by default. Settings → Keyboard already explains this, and ⌥⌘↓ works
  either way.
- **A display utility** takes ⌃⇧ chords on the maintainer's machine. Every command is also in a menu, and
  Open in New Tab, Reopen Closed Tab, Close Other Tabs and Tab List have chords without ⌃⇧.
- **Maximized panel**: Open in New Tab of Other Panel restores the normal layout first, so the other
  panel is visible.

## Requirements *(mandatory)*

### Functional Requirements

#### Opening in a new tab

- **FR-001**: The app MUST offer "Open in New Tab". It opens, in a new tab inserted after the current
  one and made active, the place Enter would enter for the cursor item:
  - a folder or an archive: its content;
  - "..": the parent folder, with the cursor on the folder the user came from;
  - a file or a package: the current folder, with the item under the cursor.
- **FR-002**: The tab the command was run from MUST keep its folder, cursor, selection and history.
- **FR-003**: The app MUST offer "Open in Background Tab". It works like FR-001, but the new tab is not
  made active.
- **FR-004**: The app MUST offer "Open in New Tab of Other Panel". It works like FR-001, but the new tab
  is created in the other panel (after its current tab, made active). The focus MUST stay in the active
  panel.
- **FR-005**: If the place cannot be opened, no tab MUST be created and the error MUST be reported as for
  a failed navigation.

#### Closed tabs and the tab list

- **FR-006**: Each panel MUST remember its closed tabs, newest first, at most 10, in memory, while the
  window is open. This covers every way of closing a tab: the key, the menu, the tab strip and Close
  Other Tabs.
- **FR-007**: The app MUST offer "Reopen Closed Tab". It reopens the newest closed tab of the active
  panel after the current tab and makes it active. It removes the tab from the closed list and restores
  its folder, cursor, sort, filter and history. The command MUST be disabled when there is no closed
  tab.
- **FR-008**: The app MUST offer "Tab List…". It shows the active panel's open tabs in order, with the
  active one checked, then the closed tabs under a "Recently Closed" heading. Each entry shows the
  tab's title, with its full path as a tooltip. It MUST be fully usable from the keyboard: arrows,
  Return, Esc, and typing to select.
- **FR-009**: Choosing an open tab in the list MUST switch to it. Choosing a closed tab MUST reopen it
  as in FR-007.

#### Arranging tabs

- **FR-010**: The app MUST offer "Close Other Tabs". It closes all tabs of the active panel except the
  current one, recording them as closed tabs. It is disabled with a single tab.
- **FR-011**: The app MUST offer "Swap Panels with All Tabs". It exchanges the complete tab lists of the
  two panels, each with its active tab, and keeps the focus on the same side. "Swap Panels" (⌃U)
  keeps swapping only the current tabs.

#### Keys and menus

- **FR-012**: The new commands MUST have these factory chords and menu places (no existing chord
  changes):

  | Command | Chords | Menu |
  |---|---|---|
  | Open in New Tab | ⌃↑, ⌥⌘↓ | Go |
  | Open in Background Tab | ⌥⌘⇧↓ | Go |
  | Open in New Tab of Other Panel | ⌃⇧↑ | Go |
  | Reopen Closed Tab | ⌘⇧T | Go |
  | Close Other Tabs | ⌥⌘W | Go |
  | Tab List… | ⌃⇧A, ⌘⇧\ | Go |
  | Swap Panels with All Tabs | ⌃⇧U | View |

- **FR-013**: The Classic Commander scheme MUST give ⌃⇧W to Close Other Tabs; Close Tab keeps ⌃W in that
  scheme.
- **FR-014**: No chord MUST be bound twice in the panel context, in either scheme (the existing
  automatic check).
- **FR-015**: While quick search runs, ⌃↑ and ⌃↓ MUST keep moving between matches.

### Key Entities

- **Closed tab**: a saved tab state (folder, cursor, selection, sort, filter, history) of one panel, in a
  list of at most 10, newest first. It lives in memory.
- **Tab list entry**: an open tab or a closed tab, with title and path.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can open a folder in a new tab with one chord, and get back a tab closed by mistake
  with one chord.
- **SC-002**: Every new command can be reached from the keyboard without ⌃⇧ chords (an alternative chord
  or a menu item reachable from the keyboard).
- **SC-003**: Every rule of FR-001–FR-011 that does not need a window has an automated test: tab list
  operations, the closed-tab list and its limit, the swap.
- **SC-004**: No existing chord changes meaning in the Axolotl scheme (checked automatically).

## Assumptions

- The tab title shown in the tab list is the one the tab strip shows.
- Reopening a tab uses the same restore as switching tabs, including the fallback to the nearest
  existing folder.
- The layout file (`window.layout`) keeps saving open tabs only; closed tabs are session memory, not
  settings, and are not exported.

## Out of Scope

- Locked tabs, renamed tabs, saved tab sets and favorite tabs.
- Remembering closed tabs across launches.
- Moving a tab to the other panel by drag and drop.
- A tab list covering both panels at once.

## Deviations from the classic reference

- Open in Background Tab opens the cursor item, not a copy of the current tab.
- Extra macOS-style chords: ⌘⇧T, ⌥⌘W, ⌘⇧\, ⌥⌘↓ and ⌥⌘⇧↓.
- The tab list shows only the active panel's tabs.
