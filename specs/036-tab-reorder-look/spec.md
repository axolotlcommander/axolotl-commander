# Feature Specification: Tab Reordering and a Prominent Tab Look

**Feature Branch**: `036-tab-reorder-look`

**Created**: 2026-10-21

**Status**: Draft

**Input**: A user's request relayed by the maintainer: "The panel tabs are rather hard to see and hard to tell
apart. Maybe make them darker, like the disks above them… It would also help to be able to move them with
the mouse, i.e. change their order within the left or the right panel, not between panels." The maintainer:
"moving with the mouse yes; propose something for the tab look (maybe behind a setting)". Agreed in chat on
2026-10-21: reordering by dragging, commands to move a tab left or right, and a "Prominent" tab look as a
setting with "Standard" (today's look) as the default ("yes, as you recommend").

## Context

Each panel has a tab strip (spec 028), hidden while the panel has one tab unless Settings → Panels keeps it
shown. A click switches tabs, a middle click or the × closes one, the context menu offers New Tab, Duplicate
Tab, Copy Tab to Other Panel, Lock Tab, Lock Tab Allow Folder Changes, Close Tab, Close Other Tabs, Close Tabs
to the Right and Reopen Closed Tab. "+" opens a tab; tabs that do not fit are listed in the "»" menu; the
active tab is always visible. The tabs and their order are restored after a restart. Spec 028 left
reordering tabs by dragging out of scope.

Today inactive tabs have a faint gray fill and the active tab a light tint of the accent color, with one point
between tabs, so the tabs blend into each other and into the panel. The disk buttons above them have a
stronger gray fill.

The reference (Open Salamander / Tandem help): a tab is moved left or right by dragging it with the mouse; Esc
cancels the drag. It has no commands to move a tab and documents no dragging between panels. Its tab colors
follow the panel caption colors: the active tab of the active panel uses the active caption color, the
inactive panel's tabs the inactive one; there are no tab look options.

## Clarifications

### Session 2026-10-21

- Q: Can a tab be dragged to the other panel? → A: No, only within its own panel.
- Q: Keyboard commands for moving a tab? → A: Yes, "Move Tab Left" and "Move Tab Right", with no default
  shortcut, also in the tab's context menu.
- Q: How is the more visible look offered, and what is the default? → A: A setting "Tab look: Standard /
  Prominent" in Settings → Panels; Standard (today's look) is the default.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reorder tabs by dragging (Priority: P1)

A user with several tabs in a panel drags one to another place in the same strip.

**Why this priority**: It was asked for directly and is the most common way to reorder tabs.

**Independent Test**: With three tabs A B C, drag A to the right of C; the order becomes B C A.

**Acceptance Scenarios**:

1. **Given** tabs A B C in the left panel, **When** the user drags A to the right past C and releases, **Then** the
   order is B C A, and the tab that was active is still active.
2. **Given** a drag in progress, **When** the pointer passes the middle of a neighboring tab, **Then** that tab
   moves aside at once, showing where the dragged tab will land.
3. **Given** a drag in progress, **When** the user presses Esc, **Then** the tabs return to their original order.
4. **Given** a drag in progress, **When** the user releases the button outside the tab strip (for example over the
   other panel), **Then** the tab lands in the position last shown in the strip; it never moves to the other
   panel.
5. **Given** a press on a tab that moves less than 3 points, **When** the user releases, **Then** it is a click
   (switches to that tab), not a move.
6. **Given** the order was changed, **When** the app restarts, **Then** the tabs come back in the new order.

---

### User Story 2 - Move commands (Priority: P2)

A keyboard user moves the active tab left or right; a mouse user can do it from the tab's context menu.

**Why this priority**: The app is keyboard-first; dragging alone would leave keyboard users without a way.

**Independent Test**: Assign a key to "Move Tab Right" in Settings → Keyboard; with tabs A B C and A active,
press it; the order becomes B A C and A stays active.

**Acceptance Scenarios**:

1. **Given** tabs A B C with A active, **When** the user runs Move Tab Right, **Then** the order is B A C and A is
   still active.
2. **Given** the active tab is the first one, **When** the user looks at Move Tab Left, **Then** it is disabled;
   likewise Move Tab Right for the last tab and both for a single tab.
3. **Given** a right click on tab B, **When** the user chooses Move Tab Left in its menu, **Then** B moves one
   place left, whether or not it is the active tab, and the active tab does not change.
4. **Given** Settings → Keyboard, **When** the user searches for "Move Tab", **Then** both commands are listed in
   the Panels context with no shortcut.

---

### User Story 3 - Prominent tab look (Priority: P2)

A user who finds the tabs hard to see switches to a more visible look.

**Why this priority**: It addresses the user's complaint, but today's look stays the default.

**Independent Test**: Choose Settings → Panels → Tab look → Prominent; the tabs are clearly separated and the
active tab of the active panel stands out in the accent color.

**Acceptance Scenarios**:

1. **Given** Tab look is Prominent, **When** the user looks at a panel with several tabs, **Then** each inactive
   tab has a gray fill at least as strong as the disk buttons above it, a thin outline and a visible gap
   from its neighbors.
2. **Given** Tab look is Prominent, **When** the left panel is active, **Then** its active tab is filled with the
   accent color with white bold text, and the right panel's active tab is filled with a darker gray than its
   inactive tabs, with normal text.
3. **Given** Tab look is Prominent, **When** the user switches the active panel (Tab key or a click), **Then** the
   accent fill moves to the newly active panel's active tab at once.
4. **Given** the pointer is over an inactive tab, **When** Tab look is Prominent, **Then** the tab's fill darkens
   slightly.
5. **Given** light or dark appearance, **When** Tab look is Prominent, **Then** the text stays readable and the
   tabs stay distinguishable in both.
6. **Given** a fresh installation, **When** the user opens Settings → Panels, **Then** Tab look is Standard and
   the tabs look as today.

---

### Edge Cases

- Dragging a locked tab: allowed; a lock concerns the folder, not the position.
- Tabs hidden in the "»" menu are not drag targets; a drag moves only among the visible tabs, and an order
  change can show or hide tabs at the strip's end as today.
- The strip is hidden (one tab): nothing to drag; the move commands are disabled.
- A drag that ends where it began: the order is unchanged.
- Files dragged from a panel over a tab keep their current behavior (spec 028); only a tab itself is
  reordered by dragging.
- The panel shown on a tab keeps its folder, history and lock when the tab moves.
- Font size from Settings → Fonts: the prominent look follows the strip's height and font.
- Increased contrast or reduced transparency in macOS accessibility settings: colors come from the system and
  adapt.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Dragging a tab horizontally within its strip MUST reorder the tabs of that panel; a press moving
  less than 3 points MUST remain a click.
- **FR-002**: During a drag the dragged tab MUST follow the pointer horizontally and the other tabs MUST move
  aside to show the landing position.
- **FR-003**: Esc during a drag MUST restore the original order; releasing anywhere else MUST keep the position
  shown. A tab MUST NOT move to the other panel.
- **FR-004**: Reordering MUST keep the active tab active and keep each tab's folder, history and lock.
- **FR-005**: The new order MUST be saved like any other tab change and restored after a restart.
- **FR-006**: The commands "Move Tab Left" and "Move Tab Right" MUST move the active tab one place, have no
  default shortcut, be assignable in Settings → Keyboard (Panels context) and appear in the menu next to
  the other tab commands; they MUST be disabled when the move is not possible.
- **FR-007**: The tab context menu MUST offer Move Tab Left and Move Tab Right for the tab clicked, disabled at
  the ends.
- **FR-008**: Settings → Panels MUST have "Tab look: Standard / Prominent", Standard by default, included in
  settings export and import; a change MUST apply to both panels at once.
- **FR-009**: Standard MUST look as today.
- **FR-010**: Prominent MUST give inactive tabs a gray fill at least as strong as the disk buttons, a thin outline
  and a gap of about 3 points between tabs; the active tab of the active panel MUST be filled with the accent
  color with white bold text; the active tab of the inactive panel MUST be filled with a darker neutral gray
  than its inactive tabs; hovering an inactive tab MUST darken it slightly.
- **FR-011**: Prominent MUST use system colors so that it works in light and dark appearance and with the
  user's accent color.

### Key Entities

- **Tab look**: a panel behavior setting with the values Standard and Prominent.
- **Tab order**: the order of a panel's tabs, already part of the saved window state.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can move any visible tab to any other visible position of its strip in one drag.
- **SC-002**: Esc during a drag leaves the order exactly as it was in 100% of the tries.
- **SC-003**: A keyboard user can reorder tabs without the mouse once a key is assigned.
- **SC-004**: With Prominent on, the active panel's active tab can be told apart from all other tabs at a
  glance, in light and dark appearance.

## Assumptions

- The tab order is part of the saved window state already (spec 028), so a reorder only changes the order.
- The menu that holds the tab commands today (Go) also gets the move commands.

## Out of Scope

- Moving or copying a tab to the other panel by dragging (Copy Tab to Other Panel stays in the menu).
- Dragging a tab out to a new window.
- Tab colors chosen per tab, or more looks than the two.
- Reordering the tabs listed in the "»" menu.

## Deviations from the reference

- Added "Move Tab Left/Right" commands (the reference has none) for keyboard users.
- The tab look is a setting with two values; the reference has a single look tied to the caption colors. Its
  idea, the active panel's active tab in the active color, is what Prominent does.
