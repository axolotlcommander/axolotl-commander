# Feature Specification: Folder and Command History Lists

**Feature Branch**: `014-folder-history-list`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "Folder history as a filterable list, from which a folder can be opened in
the panel, in a new tab or in the other panel; a command line history list."

## Context

Today a panel remembers where it has been:
- Back and Forward (⌃⌥← / ⌃⌥→, ⌘[ / ⌘]) step through the panel's history one folder at a time;
- Go to Folder… offers recently typed paths in its combo box.

The command line remembers executed lines; ⌃↑ / ⌃↓ step through them while it edits.

Classic two-panel file managers show the whole folder history as a list (⌥↓ in the classic layout)
and the command line history as a list too. The scope was agreed in chat on 2026-10-12 (the list of
specs 010–016): a filterable folder history list that can open a folder here, in a new tab or in the
other panel, and a command line history list. This spec ships with specs 010–016 in one release.

## Clarifications

### Session 2026-10-13

All answers below were *decided while the maintainer was away; to review*.

- Q: What does the folder history list contain? → A: First the panel's own history in time order:
  the folders Forward would reach (furthest first), the current folder (marked), then the folders
  Back would reach (newest first). Then the recently typed paths from Go to Folder that are not in the
  panel's history. Each folder appears once, at the place closest to the current folder.
- Q: How is the list filtered? → A: Typing filters it at once. Every word of the text (split by spaces)
  must appear in the path, ignoring case and diacritics.
- Q: Which keys open a folder? → A: Return opens it in the panel; ⌘Return in a new tab of the panel;
  ⌥Return in the other panel (the focus stays in the active panel). Double-click = Return. Esc closes
  the list.
- Q: Keys for the commands? → A:
  - Folder History…: ⌃⌘H (⌃H is taken by the viewer's Highlight Syntax);
  - Classic Commander adds ⌥↓ after ⌃⌘H; in the panel it then replaces "next marked item" (which keeps
    the menu-free direct keys ⌥↑, ⌥Home and ⌥End);
  - Command Line History…: ⌥F8 in both schemes, also while the command line edits.
- Q: What does choosing a command line history entry do? → A: It replaces the command line text with
  the entry, shows the line if it is hidden and puts the caret at its end, ready to edit or run with
  Return. It never runs the command by itself.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Jump back to a folder from the history list (Priority: P1)

A user worked in several folders in the left panel. They press ⌃⌘H (⌥↓ in Classic Commander), see the
folders the panel visited, type `proj`, and press Return. The panel opens the folder.

**Why this priority**: it is the core of the feature: reaching any earlier folder in one step instead
of pressing Back many times.

**Independent Test**: visit three test folders in a panel, open the list, filter, press Return, check
the panel's folder.

**Acceptance Scenarios**:

1. **Given** the panel visited `a`, then `b`, then `c` (current), **When** the user opens Folder
   History…, **Then** the list shows `c` marked as current, then `b`, then `a`, and the selection is on
   `b`.
2. **Given** the user went Back from `c` to `b`, **When** the list opens, **Then** it shows `c` above
   the current `b`, and `a` below it.
3. **Given** the list is open, **When** the user types `a b`, **Then** only paths that contain both "a"
   and "b" are shown, and the first one is selected.
4. **Given** a path is selected, **When** the user presses Return, **Then** the list closes and the panel
   opens that folder; Back then returns to the folder shown before.
5. **Given** the filter leaves no path, **When** the user presses Return, **Then** nothing happens except
   a beep.
6. **Given** the list is open, **When** the user presses Esc, **Then** it closes and nothing changes.
7. **Given** recently typed paths exist in Go to Folder, **When** the list opens, **Then** they follow
   the panel's history, without the paths already listed.

---

### User Story 2 - Open a history folder in a new tab or the other panel (Priority: P2)

From the same list, the user presses ⌘Return to open the folder in a new tab, or ⌥Return to open it
in the other panel while keeping the focus.

**Why this priority**: it builds on US1 and joins the history with tabs and two panels.

**Independent Test**: open the list, choose with ⌘Return and with ⌥Return, check tabs and panels.

**Acceptance Scenarios**:

1. **Given** a path is selected, **When** the user presses ⌘Return, **Then** a new tab opens in the
   active panel, becomes active and shows the folder; the previous tab keeps its folder.
2. **Given** a path is selected, **When** the user presses ⌥Return, **Then** the other panel opens the
   folder and the focus stays in the active panel.
3. **Given** the panel is maximized (the other panel hidden), **When** the user presses ⌥Return,
   **Then** the panels are shown again first, as Open in New Tab of the Other Panel does.

---

### User Story 3 - Pick a command from the command line history (Priority: P2)

A user ran several commands earlier. They press ⌥F8, type `git`, and press Return. The command line
shows the chosen command with the caret at its end.

**Why this priority**: it is a separate, smaller list with the same mechanics.

**Independent Test**: run harmless commands (`cd` into test folders) to fill the history, open the
list, filter, choose; check the line text and that nothing ran.

**Acceptance Scenarios**:

1. **Given** the history holds `cd a`, then `cd b`, **When** the user opens Command Line History…,
   **Then** the list shows `cd b` first and `cd a` below it.
2. **Given** an entry is selected, **When** the user presses Return, **Then** the command line holds
   the entry, has the keyboard focus with the caret at the end, and nothing ran.
3. **Given** the command line is hidden, **When** the user chooses an entry, **Then** the line is shown.
4. **Given** the command line edits, **When** the user presses ⌥F8, **Then** the list opens.
5. **Given** the history is empty, **When** the user runs the command, **Then** it beeps and no list
   opens.

---

### Edge Cases

- **A history folder no longer exists**: opening it shows the error in the status line, as Go to Folder
  does; the list does not check folders beforehand.
- **Find results and branch view in the history**: listed and opened as their folder (the results are
  not rebuilt).
- **Archives and servers in the history**: listed by their shown path and opened the same way Back does
  (an archive is reopened; a server reconnects as Go to Folder does for a typed address).
- **Network folder**: listed as "Network" and opened as the Network folder.
- **Passwords**: never shown; recent paths are already stored without them.
- **A single folder**: the list shows just the current folder; Return on it refreshes nothing and
  closes the list.
- **Long paths**: shown truncated in the middle; the full path is the tooltip.
- **Classic Commander ⌥↓ while quick search or the quick filter is typed**: the list opens and typing
  ends, as other commands end it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST offer "Folder History…" (Go menu) for the active panel. It opens a list
  with a search field.
- **FR-002**: The list MUST contain, in this order:
  - the folders Forward would reach (furthest first);
  - the current folder, marked as current;
  - the folders Back would reach (newest first);
  - the recent paths from Go to Folder that are not listed yet.
  Each folder MUST appear once, where it is closest to the current folder.
- **FR-003**: The selection MUST start on the entry below the current folder (the folder Back would
  open), or on the current folder when there is none.
- **FR-004**: Typing in the search field MUST filter the list at once: every space-separated word MUST
  appear in the path, ignoring case and diacritics. The first remaining entry MUST be selected.
- **FR-005**: ↑, ↓, Page Up, Page Down, Home and End MUST move the selection while the search field
  keeps the keyboard focus.
- **FR-006**: Return (or double-click) MUST open the selected folder in the active panel as a new visit
  (Back returns). ⌘Return MUST open it in a new, active tab of the active panel. ⌥Return MUST open it in
  the other panel, showing both panels first, with the focus staying in the active panel.
- **FR-007**: Esc MUST close the list without changes. Return with no entry MUST beep.
- **FR-008**: The app MUST offer "Command Line History…" listing executed command lines, newest first,
  with the same search field, filtering and movement.
- **FR-009**: Choosing a command line entry MUST put it into the command line (replacing its text),
  show the line, focus it and put the caret at the end. It MUST NOT run the command.
- **FR-010**: Command Line History… with an empty history MUST beep and open nothing.
- **FR-011**: Factory chords and menus:
  - Folder History… (Go menu, after Forward): ⌃⌘H;
  - Command Line History… (Commands menu, next to the command line commands): ⌥F8; it MUST also work
    while the command line edits.
  Classic Commander MUST give Folder History… the chords ⌃⌘H and ⌥↓. A panel chord bound to a command
  MUST take precedence over the direct ⌥↑ / ⌥↓ / ⌥Home / ⌥End keys.
- **FR-012**: No chord MUST be bound twice in one context in either scheme.
- **FR-013**: The lists MUST NOT store anything new; they show existing history.

### Key Entities

- **Folder history entry**: a place to open (a location, or a typed path from Go to Folder), its shown
  path and whether it is the current folder.
- **Command history entry**: one executed command line (already stored without passwords).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Any folder from the panel's last 64 visits can be reached with one chord, a few
  characters and Return.
- **SC-002**: With 100 entries, the list narrows visibly at once after each keystroke.
- **SC-003**: The list building and filtering rules (order, duplicates, recent paths, words, case,
  diacritics) have automated tests.
- **SC-004**: Choosing a command line entry never runs a command (checked in the GUI test).

## Assumptions

- The panel's history is the existing Back / Forward history (64 entries each way, per tab).
- Recent paths are the existing Go to Folder list, shared by all panels.

## Out of Scope

- Removing entries from the lists.
- A history shared by both panels or saved across tabs (each tab has its own Back / Forward).
- Running a command line entry straight from the list.
- Changing what Back / Forward or Go to Folder remember.

## Deviations from the classic reference

- The factory chord is ⌃⌘H; ⌥↓ only in Classic Commander.
- The list is filterable and can open a folder in a new tab or the other panel.
- The command line history opens as a list on ⌥F8 instead of a drop-down of the line.
