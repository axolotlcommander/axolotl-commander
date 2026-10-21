# Feature Specification: Rename by Clicking the Name

**Feature Branch**: `035-click-rename`

**Created**: 2026-10-21

**Status**: Draft

**Input**: User description: "When I make that second, slower click on the focused (or marked) file, it should
do the same as Rename, i.e. go into editing the file's name; Finder behaves like that too." Agreed in chat on
2026-10-21: behave like Finder, with in-place editing in every view mode; the setting is on by default; F2 in
Brief and Thumbnails renames in place too ("yes, as you recommend").

## Context

Each panel shows a folder in one of three view modes: Detailed (a table with a Name column), Brief (names in
columns) and Thumbnails (a grid of pictures with the name below, up to two lines). The panel has a cursor
(one focused item) and marks. Mouse marking (spec 024): a plain left click on an item's icon or name moves the
cursor there and, in the standard mode, marks only that item on release; ⌘ or ⌃ click toggles a mark, ⇧ click
marks a range; a press on the icon or name that moves becomes drag & drop; a press elsewhere draws a
selection rectangle. In the alternative mode "Right mouse button marks (Norton Commander style)" the right
button marks. A double click opens the item.

Rename (F2 in the default scheme) edits the name in place in Detailed: the base name is preselected and the
extension kept, Enter commits, Esc cancels, moving the focus elsewhere ends editing; find results and the
branch view rename only the last part of the path. In Brief and Thumbnails it opens a dialog "Rename / New
name:" instead. Rename is available only where the place is writable and there is a target item, never on "..".

The reference (Open Salamander / Tandem help) has the option "Rename by slowly clicking the name twice"
(Configuration → Panels): a click on the name of the item that already has the focus renames it in place; a
quick double click opens it; when the item does not have the focus, the first click focuses it and, after a
pause, a second click starts renaming. The help gives no default and no delay. Finder does the same: a click
on the name of the selected item starts editing after the double-click interval; a click on the icon does not.

## Clarifications

### Session 2026-10-21

- Q: Which view modes rename in place on a click? → A: All of them, as in Finder. Brief and Thumbnails get
  in-place editing, which they do not have today.
- Q: Does F2 in Brief and Thumbnails keep its dialog? → A: No, it edits in place too, so the mouse and the
  key do the same thing.
- Q: Is the click rename a setting, and what is its default? → A: A checkbox in Settings → Panels, on by
  default.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A slow click renames in place (Priority: P1)

A user who has the cursor on a file clicks its name once more and, after a short pause, types the new name
right there, as in Finder.

**Why this priority**: It is the feature the maintainer asked for.

**Independent Test**: In Detailed, with the cursor on a file in the active panel, click its name once and wait;
the name becomes editable.

**Acceptance Scenarios**:

1. **Given** Detailed, the active panel, the cursor on "a.txt", **When** the user clicks its name once and waits,
   **Then** the name becomes editable with "a" selected; typing "b" and Enter renames it to "b.txt".
2. **Given** the cursor on an item, **When** the user double-clicks its name, **Then** the item opens as today
   and no editing starts.
3. **Given** the cursor on another item, **When** the user clicks the name of "a.txt", **Then** only the cursor
   moves to "a.txt"; **When** the user then clicks its name again slowly, **Then** editing starts.
4. **Given** the cursor on "a.txt", **When** the user clicks its icon, **Then** no editing starts.
5. **Given** the other panel is active, **When** the user clicks the name of the cursor item in this panel,
   **Then** this panel becomes active and no editing starts.
6. **Given** the cursor on "a.txt", **When** the user clicks its name and presses a key (for example ↓) before
   the pause ends, **Then** no editing starts and the key works as usual.
7. **Given** the cursor on "..", **When** the user clicks its name slowly, **Then** no editing starts.

---

### User Story 2 - In-place editing in Brief and Thumbnails (Priority: P1)

Brief and Thumbnails rename in place too, from the slow click and from F2.

**Why this priority**: The agreed behavior is "as in Finder" in every view; without it the click would do
nothing or open a dialog in two of the three views.

**Independent Test**: In Brief, press F2 on a file; the name becomes editable in its place, no dialog.

**Acceptance Scenarios**:

1. **Given** Brief, the cursor on "photo.jpg", **When** the user presses F2, **Then** a field appears over the name
   with "photo" selected; **When** the user presses Esc, **Then** the name is unchanged.
2. **Given** Thumbnails, the cursor on an item, **When** the user clicks its name slowly, **Then** an editable
   field appears under the picture with the base name selected; a long typed name wraps onto more lines and
   stays visible; Enter renames the item.
3. **Given** editing in Brief or Thumbnails, **When** the user clicks the other panel, **Then** editing ends as it
   does in Detailed today.
4. **Given** a rename is committed in Brief or Thumbnails, **When** the folder updates, **Then** the cursor is on
   the renamed item.

---

### User Story 3 - The setting (Priority: P2)

A user who does not want click renaming turns it off.

**Why this priority**: Some users click the cursor item often and do not want an accidental edit.

**Independent Test**: Turn the setting off; a slow click on the cursor item's name does nothing beyond today's
click.

**Acceptance Scenarios**:

1. **Given** a fresh installation, **When** the user opens Settings → Panels, **Then** "Rename by clicking the name
   of the item under the cursor" is on.
2. **Given** the setting is off, **When** the user clicks the cursor item's name slowly, **Then** no editing starts;
   F2 still renames in place.

---

### Edge Cases

- A click inside the name field while editing places the text cursor (the field's normal behavior).
- A name shortened with an ellipsis: the clickable name area is the visible text.
- The cursor came to the item by keyboard just before the click: it counts, the item was the cursor before
  the press.
- The item changes or disappears during the pause (the folder updates), the list scrolls or the cursor moves:
  no editing.
- The press becomes drag & drop or a selection rectangle: no editing.
- A click that brings the app or the window to the front: no editing.
- A click with ⇧, ⌘, ⌃ or ⌥, a right click (also in the Norton mode), a middle click: no editing.
- Several marked items: the standard mode's release on one of them leaves only that item marked as today;
  the rule then applies to the cursor item.
- Places where Rename is disabled (read-only volume or any place where the command is unavailable): no
  editing. A remote folder or an archive where Rename is enabled: same as F2.
- Find results and the branch view: only the last part of the path is edited, as with F2 in Detailed.
- An item near the edge of the panel: the field stays inside the panel and the item scrolls into view.
- The pause is the macOS double-click interval.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A left click without modifiers on the name text of the panel's cursor item MUST start in-place
  renaming of that item when the double-click interval has passed after the release without another click.
- **FR-002**: The click MUST NOT start renaming when, before the press, the item was not the cursor item, the
  panel was not the active panel, or the window or app was not active.
- **FR-003**: The click MUST NOT start renaming when it lands on the icon or outside the name text, carries a
  modifier, becomes a drag or a selection rectangle, or is followed within the interval by another click, a
  key press, scrolling, a folder update or a cursor move. A key pressed during the pause MUST work as usual.
- **FR-004**: The click MUST NOT start renaming on ".." or where the Rename command is unavailable.
- **FR-005**: Brief and Thumbnails MUST offer in-place name editing at the item's name. Brief: a single-line
  field over the name, at least as wide as the item and wider when the name needs it, kept inside the panel.
  Thumbnails: a field below the picture that wraps and grows to show the whole name.
- **FR-006**: In-place editing MUST behave the same in all three views: the base name is preselected (a folder's
  whole name), Enter commits, Esc cancels, moving the focus elsewhere ends editing, the item stays visible,
  the panel does not reload under the field, and after a commit the cursor is on the renamed item. Find
  results and the branch view edit only the last part of the path.
- **FR-007**: The Rename command (F2) in Brief and Thumbnails MUST start in-place editing instead of the dialog.
- **FR-008**: Settings → Panels MUST have the checkbox "Rename by clicking the name of the item under the
  cursor", on by default, included in settings export and import. When it is off, FR-001 never applies; F2
  is unaffected.
- **FR-009**: Click renaming MUST work in both mouse marking modes; the right button never starts it.

### Key Entities

- **Pending click rename**: the item clicked, the time of the release, and whether anything in FR-003 has
  happened since; it either starts editing at the end of the interval or is dropped.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In each of the three views, a slow click on the cursor item's name starts editing within the
  double-click interval plus a fraction of a second, every time in the acceptance scenarios.
- **SC-002**: A double click on any item never starts editing; it opens the item as before.
- **SC-003**: F2 in Brief and Thumbnails never shows the rename dialog; the user renames without leaving the
  panel.
- **SC-004**: None of the cases in FR-002 to FR-004 starts editing.

## Assumptions

- The same rename operation as today runs after the edit (conflicts, errors and undo unchanged).
- The click rename uses the same availability rule as the Rename command.
- The rename dialog stays in the code only where in-place editing is not possible, if anywhere.

## Out of Scope

- Renaming several items at once (Multi-Rename stays a separate command).
- Changing which part of the name is preselected.
- Renaming in the tab strip, the path bar or other lists (the Find window's results, hot paths).

## Deviations from the reference

- None in behavior: the reference renames in place on a slow click, as we do now in every view. The pause is
  the macOS double-click interval; the reference does not document one.
