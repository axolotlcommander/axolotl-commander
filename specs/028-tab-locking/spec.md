# Feature Specification: Tab Locking and Tab Menu

**Feature Branch**: `028-tab-locking`

**Created**: 2026-10-14

**Status**: Implemented

**Input**: User description: "Tab locking and a fuller tab menu: a panel tab can be locked in one of two
ways, and the tab's context menu gets the usual tab actions." Asked for by a user and passed on by the
maintainer on 2026-10-14: "zamykání záložek s klasickými volbami: Zamknout záložku – pak se každá složka
otevře do nové záložky; Zamknout záložku s možností změny složky – pak do ní mohu vlézt" (locking tabs with
the classic options: Lock Tab – then every folder opens in a new tab; Lock Tab with folder changes allowed –
then I can go into folders), "and the other actions of that menu if other commanders have them".

## Context

Each panel has tabs (spec 012): every tab keeps its folder, sort, filter, cursor, marks and its own
back/forward history; the tabs are saved with the window layout and restored at start. The tab strip's
context menu has New Tab, Close Tab and Close Other Tabs; the keyboard has New Tab, Close Tab, next and
previous tab, open the item under the cursor in a new / background / other panel's tab, Reopen Closed Tab,
Close Other Tabs, the tab list and Swap Panels with Tabs. Middle click closes a tab; the last tab of a panel
cannot be closed. Ejecting or disconnecting a volume moves tabs on it to the home folder. Spec 012 left
locked tabs out of scope.

Usual behavior elsewhere: the reference program has tabs with New, Duplicate, Close, Close Other and Close
Tabs to the Right, but no locking. Other two-panel file managers offer two lock modes with the same meaning
as asked here: a locked tab opens every other folder in a new tab, and a tab locked "with folder changes
allowed" can be browsed but returns to its folder when it is activated again; they mark locked tabs in the
strip, and "close other / all tabs" keeps locked tabs.

## Clarifications

### Session 2026-10-14

- Q: Does closing a locked tab ask first? → A: No. It closes like any tab; Reopen Closed Tab brings it back
  with its lock.
- Q: When does a tab locked with folder changes allowed return to its folder? → A: When it is activated
  again after another tab of the same panel was active (as the usual commanders do). No setting for it.
- Q: Which other actions join the tab menu? → A: Duplicate Tab, Copy Tab to Other Panel, Close Tabs to the
  Right and Reopen Closed Tab. Renaming tabs is a separate later specification.
- Q: Where do the lock mark and the close button go? (added while planning, 2026-10-14) → A: They share
  one place at the left end of the tab, as in the screenshot the maintainer sent: while the pointer is over a
  tab (any tab, active or not) it shows the close button; otherwise a locked tab shows the lock, and the
  active unlocked tab shows the close button as today. The name stays centered and does not move.
- Q: Right click on the empty part of the strip? (planning, 2026-10-14) → A: The tabs share the strip's whole
  width, so it has no empty part; New Tab and Reopen Closed Tab are in every tab's menu instead.
- Q: A "+" to add a tab with the mouse and "»" when the tabs do not fit, as in the maintainer's second
  screenshot? (implementation, 2026-10-14) → A: Yes. A "+" button at the right end of the strip opens a new
  tab. The strip still hides with a single tab by default; a new option in Settings → Panels, "Always show
  the tab bar", keeps it (and the "+") visible with one tab. Tabs no longer shrink without limit: each keeps
  a minimum width, the tabs that do not fit are left out of the strip and listed in a menu under a "»" button
  (with their lock marks); the active tab is always among the visible ones.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Keep a tab on its folder (Priority: P1)

A user keeps a tab on a project folder they return to all day. They lock it. Whatever they open from it —
a subfolder, the parent, a hot path, another volume — opens in a new tab next to it, and the locked tab stays
where it was, with its cursor.

**Why this priority**: It is what the user asked for; the rest builds on it.

**Independent Test**: Lock a tab from its context menu; press Return on a subfolder: a new tab opens right
after the locked one, active, in the subfolder; the locked tab still shows its folder with the cursor where
it was.

**Acceptance Scenarios**:

1. **Given** a normal tab, **When** the user chooses Lock Tab in its context menu, **Then** the item shows a
   checkmark the next time the menu opens and the tab shows the lock mark.
2. **Given** a locked tab, **When** the user opens a folder in it in any way (Return or double click on a
   folder, "..", Go to Parent, Back or Forward, folder history, a hot path, a volume or server button, Go to
   Folder…, `cd` in the command line, the folder of a search result, entering an archive), **Then** the
   target opens in a new tab inserted right after the locked tab and activated, and the locked tab keeps its
   folder, cursor and marks.
3. **Given** a locked tab, **When** the user views, edits, copies, marks, sorts, filters or refreshes, or
   opens a file with Return, **Then** it works exactly as in a normal tab.
4. **Given** a locked tab, **When** the user chooses Lock Tab again, **Then** the tab is a normal tab again.
5. **Given** a locked tab is the panel's only tab, **When** the user opens a folder, **Then** a second tab
   opens with it.
6. **Given** the active panel's tab, **When** the user runs Lock Tab from the main menu, **Then** the active
   tab of the active panel is locked; the command has no default key and can be given one in Settings →
   Keyboard.

---

### User Story 2 - Browse a tab that comes back (Priority: P1)

A user wants to look around below a folder without leaving it for good. They lock the tab with folder
changes allowed: they can go into subfolders and elsewhere, and when they come back to the tab after working
in another one, it is on its folder again.

**Why this priority**: It is the second mode the user asked for.

**Independent Test**: Lock a tab with folder changes allowed; go into a subfolder: the same tab changes;
switch to another tab and back: the tab is on its locked folder with the cursor where it was when locked.

**Acceptance Scenarios**:

1. **Given** a tab, **When** the user chooses Lock Tab, Allow Folder Changes, **Then** that item is checked,
   Lock Tab is not (the two exclude each other), and the tab shows the lock mark.
2. **Given** such a tab, **When** the user opens folders in it, **Then** they open in the same tab as in a
   normal tab.
3. **Given** such a tab shows another folder, **When** the user activates another tab of the same panel and
   then this tab again (click, next / previous tab, the tab list), **Then** the tab shows its locked folder,
   with the cursor on the item it had when locked if that item still exists.
4. **Given** such a tab, **When** the user chooses the checked item again, **Then** the tab is a normal tab
   and keeps the folder it shows now.
5. **Given** such a tab is active when the app quits, **When** the app starts again, **Then** the tab is on
   its locked folder.

---

### User Story 3 - See which tabs are locked (Priority: P1)

A user with many tabs sees at a glance which ones are locked and how.

**Why this priority**: A locked tab behaves differently; without a mark the behavior looks like a fault.

**Independent Test**: Lock two tabs, one in each mode: both show a lock mark before the name; the tooltip of
each names the mode and the locked folder's path.

**Acceptance Scenarios**:

1. **Given** a locked tab (either mode), **When** the strip is shown, **Then** a small lock mark is shown
   at the left end of the tab; the name stays the folder name.
2. **Given** any tab of a strip with more than one tab, **When** the pointer is over it, **Then** the left
   end shows the close button instead of the lock (or of nothing); a click on it closes that tab. The active
   unlocked tab shows the close button also without the pointer, as today.
3. **Given** a locked tab, **When** the pointer rests on it, **Then** the tooltip says "Locked" or "Locked,
   folder changes allowed" and the path of the locked folder.
4. **Given** many tabs with long names in a narrow window, **When** tabs get narrow, **Then** the lock mark
   and the close button stay visible and only the name is shortened.
5. **Given** the tab list (keyboard), **When** it is shown, **Then** locked tabs carry the lock mark too.

---

### User Story 4 - Locks survive (Priority: P2)

Locks are part of how the user arranges their work; they stay through a restart, a closed and reopened tab
and swapping the panels, and the bulk close commands leave locked tabs alone.

**Why this priority**: Without it, locks would be lost too easily to be worth setting.

**Independent Test**: Lock a tab, quit and start: still locked. Close it and Reopen Closed Tab: locked again.
Close Other Tabs from another tab: the locked tab stays.

**Acceptance Scenarios**:

1. **Given** locked tabs, **When** the app quits and starts, **Then** every tab has its lock mode and locked
   folder; window layouts saved by earlier versions load with all tabs unlocked.
2. **Given** a locked tab, **When** the user closes it (Close Tab, its key, the close button, middle click),
   **Then** it closes without a question; Reopen Closed Tab brings it back with its lock.
3. **Given** locked tabs, **When** the user runs Close Other Tabs or Close Tabs to the Right, **Then** the
   locked tabs stay open.
4. **Given** locked tabs, **When** the user swaps the panels with their tabs, **Then** the tabs move with
   their locks.
5. **Given** a locked tab on a volume, **When** the volume is ejected or the server disconnected, **Then** the
   tab goes to the home folder as other tabs do and is no longer locked.
6. **Given** the locked folder no longer exists (at start, or when a tab locked with folder changes allowed
   returns), **When** the tab shows it, **Then** it shows the nearest existing parent and stays locked on it.

---

### User Story 5 - The usual tab actions in the tab menu (Priority: P2)

A user right-clicks a tab and finds the usual actions: make a copy of the tab, put a copy into the other
panel, close the tabs to the right, reopen a closed tab, and the two lock modes.

**Why this priority**: The user asked for the other actions of that menu; most exist as keys already.

**Independent Test**: Right-click a tab that is not active: the menu has the items below, and each acts on
that tab, not on the active one.

**Acceptance Scenarios**:

1. **Given** a right click on a tab, **When** the menu opens, **Then** it offers, in this order: New Tab,
   Duplicate Tab, Copy Tab to Other Panel; Lock Tab, Lock Tab, Allow Folder Changes; Close Tab, Close Other
   Tabs, Close Tabs to the Right, Reopen Closed Tab — with separators between the groups.
2. **Given** the menu of a tab, **When** the user chooses Duplicate Tab, **Then** a copy of that tab (folder,
   sort, filter, cursor, history) opens right after it, active and unlocked.
3. **Given** the menu of a tab, **When** the user chooses Copy Tab to Other Panel, **Then** a copy of that tab
   opens as a new active tab in the other panel, unlocked; the tab itself stays.
4. **Given** the last tab of the strip, **When** its menu opens, **Then** Close Tabs to the Right is disabled;
   Reopen Closed Tab is disabled when no tab of the panel was closed; Close Tab and Close Other Tabs are
   disabled when the panel has only one tab.
5. **Given** the main menu, **When** the user opens its tab commands, **Then** Duplicate Tab, Copy Tab to
   Other Panel, Close Tabs to the Right and the two lock commands are there too, acting on the active tab of
   the active panel.
6. **Given** the app runs in Czech, **When** any of these menus opens, **Then** no item text is cut.

---

### Edge Cases

- A locked tab opening its own folder again (Refresh, Go to Folder to the same path, a hot path to the same
  folder): nothing new opens; the folder is refreshed as usual.
- "..", Go to Parent at a volume root in a locked tab: nothing happens, as in a normal tab.
- A locked tab showing search results or a branch view: the lock applies to the folder of the results;
  leaving the results (Return on a folder, Go to Parent) opens a new tab.
- Commands from the other panel or from outside that set this panel's folder (Target = Source, "open in the
  other panel", a folder dropped on the path bar or on a volume button, Reveal in panel) on a locked tab: a
  new tab opens instead of changing the locked tab.
- Files dragged into a locked tab are still copied or moved into its folder (no folder change).
- A folder dropped on a locked tab's strip entry does not change the tab.
- Duplicate Tab and Copy Tab to Other Panel of a locked tab make an unlocked copy of its current state.
- Locking a tab while it shows search results or a branch view locks its folder.
- Close Other Tabs from a locked tab keeps it and the other locked tabs.
- A tab locked with folder changes allowed that is the only tab of its panel never becomes inactive, so it
  does not return by itself; it returns when another tab was active in between, or at the next start.
- Swap Panels with Tabs while a tab locked with folder changes allowed shows another folder: it moves as it
  is; it returns when activated again after another tab.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A tab MUST have one of three lock modes: none, locked, or locked with folder changes allowed;
  a locked tab MUST remember its locked folder (the folder it showed when it was locked) and the cursor item
  of that moment.
- **FR-002**: Lock Tab and Lock Tab, Allow Folder Changes MUST be available in the tab's context menu
  (acting on that tab) and as commands in the main menu (acting on the active tab of the active panel),
  shown with a checkmark when that mode is on; choosing the other mode MUST switch modes, choosing the
  checked one MUST unlock. The commands MUST have no default key and MUST be assignable in Settings →
  Keyboard.
- **FR-003**: In a locked tab, every change of the panel's folder MUST instead open the target in a new tab
  inserted right after the locked tab and activated, leaving the locked tab's folder, cursor and marks as
  they were; a change to the folder the tab already shows MUST open nothing.
- **FR-004**: In a locked tab, every action that does not change the folder (view, edit, copy, move into the
  folder, marking, sorting, filtering, refreshing, opening files) MUST work as in a normal tab.
- **FR-005**: A tab locked with folder changes allowed MUST change folders like a normal tab, and MUST show
  its locked folder again whenever it becomes the active tab of its panel after another tab of that panel
  was active, with the cursor on the remembered item if it still exists.
- **FR-006**: A locked tab (either mode) MUST show a lock mark at the left end of its strip entry and in the
  tab list; its tooltip MUST name the mode and the locked folder's path. The left end MUST show the close
  button instead while the pointer is over the tab (any tab, when the panel has more than one), and on the
  active unlocked tab; the mark and the close button MUST stay visible when tabs are narrow.
- **FR-007**: Lock modes and locked folders MUST be saved with the window layout and restored at start, a
  tab locked with folder changes allowed MUST start on its locked folder, and layouts without lock data MUST
  load with unlocked tabs.
- **FR-008**: Closing a locked tab directly MUST close it without a question; Reopen Closed Tab MUST restore
  it with its lock mode and locked folder.
- **FR-009**: Close Other Tabs and Close Tabs to the Right MUST keep locked tabs open.
- **FR-010**: Swap Panels with Tabs MUST move tabs with their locks.
- **FR-011**: When a volume or server is ejected or disconnected, a locked tab on it MUST go to the home
  folder like other tabs and become unlocked.
- **FR-012**: When the locked folder does not exist, the tab MUST show its nearest existing parent and stay
  locked with that parent as the locked folder.
- **FR-013**: The tab context menu MUST offer New Tab, Duplicate Tab, Copy Tab to Other Panel, the two lock
  modes, Close Tab, Close Other Tabs, Close Tabs to the Right and Reopen Closed Tab, in groups as in User
  Story 5, acting on the tab under the pointer.
- **FR-014**: Duplicate Tab MUST open an unlocked copy of the tab (folder, sort, filter, cursor, history)
  right after it and activate it; Copy Tab to Other Panel MUST open such a copy as the active tab of the
  other panel.
- **FR-015**: Close Tabs to the Right MUST close every unlocked tab after the given one; it MUST be disabled
  when no tab follows. Items that cannot act MUST be disabled, never hidden.
- **FR-016**: Duplicate Tab, Copy Tab to Other Panel and Close Tabs to the Right MUST also exist as commands
  in the main menu, without default keys and assignable in Settings → Keyboard.
- **FR-017**: All new texts (menu items, tooltips) MUST be localized (English and Czech) and fit without
  being cut.
- **FR-018**: The strip MUST end with a "+" button that opens a new tab like New Tab.
- **FR-019**: Settings → Panels MUST offer "Always show the tab bar" (off by default); when on, the strip is
  shown even for a single tab, when off it hides with a single tab as before. The change applies at once.
- **FR-020**: Tabs MUST keep a minimum width; tabs that do not fit MUST be reachable from a "»" menu at the
  end of the strip, which lists them in order with their lock marks; the active tab MUST always be visible.

### Key Entities

- **Tab lock**: per tab — the mode (none, locked, folder changes allowed), the locked folder and the cursor
  item at the moment of locking. Saved with the tab in the window layout and kept by Reopen Closed Tab.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a locked tab, each of the folder changes listed in User Story 1 opens a new tab and leaves
  the locked tab unchanged — 100 % in the GUI check.
- **SC-002**: A tab locked with folder changes allowed shows its locked folder every time it is activated
  after another tab, in all three ways of switching tabs.
- **SC-003**: After a restart, every lock mode and locked folder is the same as before quitting.
- **SC-004**: A user can tell locked from unlocked tabs and the two modes apart (mark and tooltip) without
  opening a menu.
- **SC-005**: No item of the tab menus is cut in English or Czech at the default window width.

## Assumptions

- The lock mark is a small lock symbol shared by both modes; the tooltip tells the modes apart.
- "Locked folder" for a tab showing search results or a branch view is the folder those were made from.
- The new tab opened from a locked tab is a normal tab with the target's own defaults (as Open in New Tab
  makes today), and inherits the locked tab's sort and filter as a new tab does today.
- Keyboard commands that already exist (Open in New Tab, Reopen Closed Tab, Close Other Tabs…) keep their
  keys; the new commands get none by default, also in the Classic Commander key scheme.
- Locks are per window layout, like the tabs themselves; nothing new is exported with Settings beyond what
  the layout already carries.

## Out of Scope

- Renaming tabs (a later specification), favorite tab sets.
- Reusing an existing tab that shows the target folder instead of opening a new one.
- A confirmation before closing locked tabs; a setting to stop the return to the locked folder.
- Moving (not copying) a tab to the other panel; reordering tabs by dragging.
