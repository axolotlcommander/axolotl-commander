# Feature Specification: Quick View Panel

**Feature Branch**: `016-quick-view-panel`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "⌃Q quick view panel: the other panel shows a preview of the item under the
cursor and follows the cursor."

## Context

Today Quick Look (⌘Y, ⌥F3) shows the item under the cursor in a floating window. Classic two-panel file
managers have a quick view *panel*: the other panel turns into a preview of the item under the cursor
in the active panel and changes as the cursor moves, so the user can step through files and read them
without opening anything. The scope was agreed in chat on 2026-10-12 (the list of specs 010–016). This
spec ships with specs 010–016 in one release.

## Clarifications

### Session 2026-10-13

All answers below were *decided while the maintainer was away; to review*.

- Q: What does the preview show? → A: The system preview (Quick Look) of the item: text, images, PDF,
  media, and an icon with details for anything else, including folders. On ".." it shows the panel's
  folder.
- Q: Items in archives and on servers? → A: Not previewed; the panel shows a short note instead.
- Q: Keys? → A: Quick View Panel (View menu) on ⌃Q in both schemes; ⌃Q again closes it.
- Q: What happens with Tab, maximizing and swapping panels? → A: They close the quick view first:
  the preview side cannot take the focus. Tab then switches to the other panel as usual. A click on
  the preview does the same; the mouse wheel scrolls the preview.
- Q: Is it remembered? → A: No; it is off when a window opens.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preview files while moving the cursor (Priority: P1)

A user in the left panel presses ⌃Q. The right panel shows the preview of the file under the cursor.
They press ↓ several times; the preview follows. ⌃Q again brings the right panel back.

**Why this priority**: the whole feature.

**Independent Test**: in a test folder with text and image files, turn it on, move, turn it off; check
the other panel's content and that its folder is unchanged afterwards.

**Acceptance Scenarios**:

1. **Given** the cursor on `a.txt` in the left panel, **When** the user runs Quick View Panel, **Then**
   the right panel shows the text of `a.txt` with the name above it, and the focus stays in the left
   panel.
2. **Given** the quick view is on, **When** the cursor moves to `b.png`, **Then** the preview shows the
   image.
3. **Given** the quick view is on, **When** the cursor is on a folder or "..", **Then** the preview
   shows that folder (or the panel's folder) as the system preview presents it.
4. **Given** the quick view is on, **When** the user runs Quick View Panel again, **Then** the right
   panel shows its folder as before, with its cursor where it was.
5. **Given** the left panel is maximized, **When** the user turns the quick view on, **Then** both
   panels are shown first.

---

### User Story 2 - Keep panel commands working (Priority: P2)

While the quick view is on, the active panel works as usual: marking, opening folders, F5 into the
other panel's folder. Commands that would focus the preview side close the quick view first.

**Why this priority**: the preview must not get in the way.

**Independent Test**: with the quick view on, open a folder, press Tab, maximize; check the results.

**Acceptance Scenarios**:

1. **Given** the quick view is on, **When** the user opens a folder in the active panel, **Then** the
   preview follows the cursor in the new folder.
2. **Given** the quick view is on, **When** the user presses Tab, **Then** the quick view closes and
   the other panel becomes active.
3. **Given** the quick view is on, **When** the user maximizes the panel or swaps the panels, **Then**
   the quick view closes first.
4. **Given** the cursor is on an item in an archive or on a server, **Then** the preview area says
   that such items have no preview.

---

### Edge Cases

- **A large file**: the preview loads in the background; moving on does not wait for it.
- **Holding ↓**: the preview follows the last item shown, without lagging behind the cursor.
- **The previewed file is deleted or renamed**: the next cursor move shows the new cursor item.
- **The Network folder**: the note instead of a preview.
- **Find results and branch view**: the items are real files and are previewed.
- **The window closes**: the quick view goes with it; a new window starts without it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST offer "Quick View Panel" (View menu, checked while on) for the window, on
  ⌃Q in both schemes. It toggles the quick view.
- **FR-002**: While on, the panel opposite the active one MUST be covered by a preview of the active
  panel's cursor item, with the item's name above it. The covered panel MUST keep its folder, tabs
  and cursor.
- **FR-003**: The preview MUST follow every cursor change of the active panel, including folder
  changes, and MUST NOT take the keyboard focus.
- **FR-004**: Files, packages and folders on disk (also in find results and the branch view) MUST be
  previewed; ".." MUST preview the panel's folder; items in archives, on servers and in the Network
  folder MUST show a note instead.
- **FR-005**: Switch Panel, Maximize Panel, Swap Panels and Swap Panels with All Tabs MUST close the
  quick view before they act. Turning it on MUST show both panels first.
- **FR-006**: The quick view MUST NOT be saved; each window starts without it.

### Key Entities

- **Quick view**: on or off for a window, the side it covers, and the item it shows.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Moving the cursor with the quick view on stays as responsive as without it.
- **SC-002**: The choice of what to preview (file, folder, "..", archive, server, Network) has automated
  tests.

## Assumptions

- The system Quick Look previews are good enough; no own viewer is embedded.

## Out of Scope

- A separate quick view window that follows the cursor.
- Previews of archive members and server files.
- Focusing or scrolling the preview from the keyboard.

## Deviations from the classic reference

- The preview is the system Quick Look, not the app's own viewer and its plugins.
- Tab closes the quick view instead of moving the focus into it.
