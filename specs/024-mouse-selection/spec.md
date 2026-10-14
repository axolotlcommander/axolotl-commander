# Feature Specification: Mouse Selection

**Feature Branch**: `024-mouse-selection`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Mouse selection in the file panels: standard Windows-style marking with
modifier clicks and a rubber band, plus an optional Norton-style 'right button marks' setting." (Proposal
written in chat after research of other file managers; agreed on 2026-10-14: "ctrl+klik bude označovat",
"shift + myš dělá nové označení, staré zruší", "prostě označování myší ruší předchozí označení", "jinak jak
doporučuješ", that is, take the recommended answers.)

## Context

A panel keeps a cursor (the focused row) apart from the set of marked items. Operations work on the marked
items, or on the cursor item when nothing is marked. Today the mouse cannot mark anything:

- a plain click only moves the cursor; clicks with ⌘, ⇧ or ⌥ do nothing more, and ⌃-click falls through to
  the system context menu;
- a right click opens the context menu; on an unmarked item while other items are marked it first clears
  the marks, on a marked item the menu acts on all marked items;
- a left drag from an item is drag & drop (all marked items when the dragged item is marked);
- there is no rubber band;
- a double click opens the item.

Marking works only from the keyboard: Insert, Space, ⌥⇧↑, ⇧ + movement keys (the first row decides between
marking and unmarking), numpad + − *, ⌘A, ⌘⇧A, and ⌃W to restore the previous marks. The ".." row can never
be marked. Panels have two views: Detailed (a table whose rows span the full width) and Brief (a grid).

Research of how others do it:

- **The classic reference** keeps the marks on a plain click; Ctrl+click toggles one item; Shift+click marks
  the range from the cursor; a drag that starts in the empty area behind the items draws a rubber band
  (alone it replaces the marks, with Shift it adds, with Ctrl it toggles; the list scrolls at the edge).
  A setting chooses between "right click opens the context menu, Ctrl+right click marks" and the Norton
  Commander style "right click marks, Ctrl+right click opens the menu".
- **The best-known Windows two-panel file manager** has a mouse selection mode: Windows standard (a plain
  click replaces the marks, Ctrl+click toggles, Shift+click marks a range, right click opens the context
  menu) or Norton Commander style (right click toggles a mark, a right drag marks the items passed over, a
  longer right press opens the context menu, a left click only moves the cursor). Double Commander offers
  the same choice.
- **Finder and the macOS file managers** (ForkLift, Nimble Commander): ⌘-click toggles, ⇧-click marks a
  range, ⌃-click opens the context menu, a rubber band starts in empty space; none of them has a
  right-button marking mode.

The maintainer chose the Windows-standard model as the default, with ⌃ working as the Windows Ctrl key, and
the Norton style as a setting that is off by default.

This spec changes behavior, so its pull request raises the minor version (`CLAUDE.md` → Versioning).

## Clarifications

### Session 2026-10-14

- Q: Does a plain click clear the marks (Windows standard) or keep them (the classic reference)? → A: It
  clears them, including marks made with the keyboard. A plain click on a marked item leaves only that item
  marked. Marking with the mouse always replaces the previous marks, except for the adding gestures below.
- Q: ⇧+click: add a range or start a new one? → A: Start a new one: the old marks are cleared and the range
  from the cursor to the clicked item is marked.
- Q: How to add a second range? → A: ⌃⇧+click (and ⌘⇧+click) adds the range to the existing marks.
- Q: ⌃+click on macOS normally opens the context menu. → A: ⌃+click toggles the mark of one item and keeps
  the others, as Ctrl+click on Windows; ⌘+click does the same. The context menu stays on the right click.
- Q: Marking with the right button? → A: Only when a setting turns it on; by default the right button opens
  the context menu.
- Q: Rubber band? → A: Yes, from empty space (below the items, and in a row outside the icon and the name).
- Q: A plain click in the empty space below the items? → A: Clears the marks.
- Q: Marking by dragging with ⌃ held over items ("paint")? → A: No; it would clash with drag & drop. Marking
  the items passed over is a right drag in the Norton-style mode only.
- Q: Keyboard marking? → A: Unchanged. Moving the cursor with the keys never clears the marks.
- Q: In the Norton-style mode, what does the menu opened by a long right press act on? → A: The marks stay;
  the cursor moves to the pressed item and the menu acts on the marked items, or on the pressed item when
  nothing is marked (agreed during planning: "jo pokračuj").

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Mark files with modifier clicks (Priority: P1)

A user who works with the mouse marks a few files with ⌃+click, a block of files with ⇧+click, or adds
another block with ⌃⇧+click, and then copies them with F5. A plain click starts over.

**Why this priority**: Without it the mouse cannot mark anything; it is the core of the feature and the
behavior people know from Windows file managers.

**Independent Test**: In a test folder with ten files, mark items with each click kind in Detailed and
Brief view and check which items are marked and where the cursor is.

**Acceptance Scenarios**:

1. **Given** a panel with files a…j, nothing marked, cursor on a, **When** the user ⌃-clicks c and then
   ⌃-clicks e, **Then** c and e are marked and the cursor is on e.
2. **Given** c and e are marked, **When** the user ⌃-clicks c again, **Then** only e is marked and the
   cursor is on c.
3. **Given** the same state, **When** the user ⌘-clicks g, **Then** e and g are marked (⌘ works as ⌃).
4. **Given** c and e are marked and the cursor is on b, **When** the user ⇧-clicks d, **Then** exactly b, c
   and d are marked (the old marks are gone) and the cursor is on d.
5. **Given** b…d are marked and the cursor is on d, **When** the user ⌃-clicks g and then ⌃⇧-clicks i,
   **Then** b, c, d, g, h and i are marked.
6. **Given** several items are marked (by mouse or keyboard), **When** the user clicks an unmarked item
   without a modifier, **Then** no item is marked and the cursor is on the clicked item.
7. **Given** b, c and d are marked, **When** the user clicks c without a modifier and releases the button
   without moving, **Then** only c is marked.
8. **Given** b, c and d are marked, **When** the user presses the button on c and drags, **Then** the drag
   carries b, c and d and the marks stay as they were.
9. **Given** marks were cleared by a plain click, **When** the user presses ⌃W, **Then** the previous marks
   come back.
10. **Given** the cursor is on "..", **When** the user ⇧-clicks the third file, **Then** the first three
    files are marked and ".." is not.
11. **Given** files are marked, **When** the user clicks in the empty space below the last item, **Then**
    no item is marked and the cursor does not move.
12. **Given** files are marked, **When** the user right-clicks a marked item, **Then** the context menu opens
    for all marked items; **When** the user right-clicks an unmarked item instead, **Then** the marks are
    cleared and the menu is for that item (as today).

---

### User Story 2 - Mark with a rubber band (Priority: P2)

A user drags a rectangle from an empty spot over a block of files to mark them, holding ⇧ to add another
block or ⌃/⌘ to flip some items in and out.

**Why this priority**: Fast for blocks of files and expected by Finder users, but modifier clicks already
cover every marking need.

**Independent Test**: In a test folder with 50 files, drag rectangles from the empty space with and without
modifiers in both views, including past the bottom edge, and check the marks.

**Acceptance Scenarios**:

1. **Given** a Detailed panel with f01…f50 and f02 marked, **When** the user presses the button in the Size
   column of f05 and drags down to f09, **Then** exactly f05…f09 are marked.
2. **Given** f05…f09 are marked, **When** the user drags a rectangle with ⇧ over f20…f22, **Then** f05…f09
   and f20…f22 are marked.
3. **Given** f05…f09 are marked, **When** the user drags a rectangle with ⌃ over f08…f11, **Then** f05, f06,
   f07, f10 and f11 are marked.
4. **Given** the panel shows f01…f30, **When** the user drags the rectangle past the bottom edge, **Then** the
   list scrolls and the items that come into the rectangle get marked.
5. **Given** a Brief panel, **When** the user drags from the space outside the item names over several
   columns, **Then** the items the rectangle touches are marked.
6. **Given** a Detailed panel, **When** the user presses the button on a file's name and drags, **Then** drag
   & drop starts (no rubber band).
7. **Given** a Detailed panel, **When** the user clicks (without dragging) in the Size column of a row,
   **Then** it acts as a click on that row.

---

### User Story 3 - Mark with the right button (Norton style) (Priority: P2)

A user used to the Norton Commander model turns on "Right mouse button marks" in Settings. Then a right
click toggles a mark, a right drag marks the files passed over, a longer right press opens the context
menu, and a left click only moves the cursor.

**Why this priority**: Important to long-time two-panel users, but optional and off by default.

**Independent Test**: Turn the setting on, mark with right clicks and right drags, open the menu with a
long press and with ⌃+right click, then turn it off and check that the right click opens the menu again.

**Acceptance Scenarios**:

1. **Given** the setting is on and nothing is marked, **When** the user right-clicks c, **Then** c is
   marked, the cursor is on c and no menu opens.
2. **Given** c is marked, **When** the user right-clicks c again, **Then** c is unmarked.
3. **Given** the setting is on, **When** the user presses the right button on b (unmarked) and drags down
   to f, **Then** b…f are marked; **When** the user then right-drags from c (marked) to e, **Then** c…e are
   unmarked.
4. **Given** the setting is on, **When** the user holds the right button on an item for about half a second
   without moving, **Then** the context menu opens and no mark changes.
5. **Given** the setting is on, **When** the user ⌃+right-clicks an item, **Then** the context menu opens at
   once.
6. **Given** the setting is on and b…f are marked, **When** the user left-clicks h without a modifier,
   **Then** the cursor moves to h and b…f stay marked.
7. **Given** the setting is on, **When** the user uses ⌃/⌘/⇧ left clicks or a rubber band, **Then** they
   work as in User Stories 1 and 2.
8. **Given** the setting was turned on, **When** the app is restarted, **Then** it is still on.

---

### Edge Cases

- **Empty panel / only "..":** clicks mark nothing; a plain click clears nothing that is not there.
- **⌃+click or ⌃⇧+click on "..":** nothing is marked; the cursor moves to "..".
- **⇧+click on the cursor item itself:** marks just that item (unless it is "..").
- **Range start on "..":** the range starts at the next item; ".." is never marked by a range, a rubber
  band or a right drag.
- **Listing still loading or refreshing:** marks are kept by name and survive a refresh as today; a range
  covers the items shown at the moment of the click.
- **Click in the inactive panel:** the panel becomes active first, then the same rule applies to the click.
- **Drag of marked items released outside the window or cancelled with Esc:** the marks stay.
- **Double click:** opens the item as today; its first click acts as a plain click.
- **Very large folders** (hundreds of thousands of items): a rubber band and a ⇧+click range stay
  responsive.
- **Norton mode, right press that moves before half a second:** it becomes a right drag, not a menu.
- **Trackpad:** a two-finger click is a right click; ⌃+click marks.
- **Other panel sources:** archives, server connections, search results and Network follow the same rules.
- **Quick View, Info panel, volume buttons, the command line:** unaffected.

## Requirements *(mandatory)*

### Functional Requirements

**Default mode (setting off)**

- **FR-001**: A left click without a modifier on an unmarked item MUST clear all marks (also those made with
  the keyboard) and move the cursor to the item.
- **FR-002**: A left click without a modifier on a marked item MUST move the cursor to the item and, when the
  button is released without a drag, leave only that item marked. A drag that starts there MUST carry all
  marked items and keep the marks.
- **FR-003**: ⇧+click MUST clear the marks and mark the range from the cursor item to the clicked item, both
  included; the cursor moves to the clicked item.
- **FR-004**: ⌃⇧+click and ⌘⇧+click MUST add the range from the cursor item to the clicked item to the
  existing marks; the cursor moves to the clicked item.
- **FR-005**: ⌃+click and ⌘+click MUST toggle the mark of the clicked item, keep the other marks and move the
  cursor to it; ⌃+click MUST NOT open the context menu.
- **FR-006**: A press with ⌃, ⌘ or ⇧ on an item MUST NOT start drag & drop. Modifiers pressed after a drag
  has started keep their drag & drop meaning.
- **FR-007**: A left click without a modifier in the empty space below the items MUST clear the marks and
  leave the cursor where it is.
- **FR-008**: The right click MUST keep today's behavior (context menu; on an unmarked item while others are
  marked it clears the marks first and the menu is for that item; on a marked item the menu is for all
  marked items).
- **FR-009**: A double click MUST open the item as today.

**Rubber band**

- **FR-010**: A left drag that starts in empty space MUST draw a selection rectangle: below the last item; in
  Detailed view anywhere in a row outside the item's icon and name text (to the right of the name, in the
  other columns); in Brief view outside an item's icon and name.
- **FR-011**: Without a modifier the rectangle MUST replace the marks with the items it touches; with ⇧ it
  MUST add them; with ⌃ or ⌘ it MUST toggle them (compared with the marks at the start of the drag). The
  marks MUST update while dragging.
- **FR-012**: Dragging the rectangle past the top or bottom edge of the list MUST scroll it, and items that
  come into the rectangle MUST be marked.
- **FR-013**: In Detailed view drag & drop MUST start only from an item's icon or name text. A click without
  a drag in a row's empty part MUST act as a click on that row (FR-001…FR-005).

**Right-button marking (setting on)**

- **FR-014**: Settings MUST offer "Right mouse button marks (Norton Commander style)", off by default, next to
  the other panel behavior settings, and remember it.
- **FR-015**: With the setting on, a short right click MUST toggle the mark of the item under the pointer and
  move the cursor there, without a menu.
- **FR-016**: With the setting on, a right drag MUST mark or unmark every item passed over; the first item
  decides (unmarked → mark, marked → unmark).
- **FR-017**: With the setting on, holding the right button on the same spot for about half a second MUST
  open the context menu without changing marks; ⌃+right click MUST open it at once. That menu acts on the
  marked items, or on the pressed item when nothing is marked. The keyboard ways to open it (⇧F10) stay.
- **FR-018**: With the setting on, a left click without a modifier MUST only move the cursor and keep the
  marks; ⌃/⌘/⇧ left clicks and the rubber band MUST work as in the default mode.

**Everywhere**

- **FR-019**: The ".." row MUST never be marked by any mouse gesture; ranges, rectangles and right drags
  skip it.
- **FR-020**: Marks cleared or replaced by a mouse gesture MUST be restorable with ⌃W, as other clearing
  operations.
- **FR-021**: The rules MUST be the same in Detailed and Brief view and for every panel source.
- **FR-022**: Keyboard marking MUST stay unchanged.

### Key Entities

- **Marks**: the set of marked items of a panel, kept by name.
- **Cursor**: the focused item; the anchor of ⇧ ranges.
- **Mouse gesture**: a click or drag with its button, modifiers, start position (item, its icon/name, empty
  space) and whether it moved.
- **Mouse selection mode**: Windows standard (default) or Norton style, from the setting.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Each acceptance scenario of User Stories 1–3 gives the stated marks and cursor position in both
  Detailed and Brief view.
- **SC-002**: A user can mark three separate blocks of files with the mouse alone in under 15 seconds.
- **SC-003**: A rubber band or ⇧+click over 100 000 items updates the marks without a visible pause (under
  0.1 s per step).
- **SC-004**: No mouse gesture ever marks ".."; keyboard marking behaves exactly as before (existing tests
  pass unchanged).
- **SC-005**: The marking rules (every click kind, both modes, ".." handling, ⌃W after a click) are covered by
  unit tests that run without any user data.

## Assumptions

- "About half a second" for the long right press is a fixed value; making it configurable is out of scope.
- The rubber band is drawn in the system's usual selection style.
- The GUI check uses a test folder in the session's scratch folder with the test copy of the app (own bundle
  id); only browsing and marking happen there, drags are cancelled before dropping.
- Out of scope: opening with a single click (point to select); renaming by clicking the name twice slowly;
  marking by a plain left drag over items; mouse wheel changes; an option to toggle a mark by clicking the
  icon; changes to keyboard marking.
- Deviations from the classic reference: a plain click clears the marks (Windows standard) where the
  reference keeps them; ⌃+click marks although on macOS it normally opens the context menu; ⌘ works as Ctrl;
  ⌃⇧/⌘⇧+click adds a range; Norton-style marking is a setting that is off by default, and in it a long
  right press (not only ⌃+right click) opens the menu.
