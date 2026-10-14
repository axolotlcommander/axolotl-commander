# Feature Specification: Thumbnails View

**Feature Branch**: `025-thumbnails-view`

**Created**: 2026-10-14

**Status**: Draft

**Input**: User description: "Thumbnails view: a third panel view mode that shows a grid of file previews
(thumbnails) with the name below, next to the existing Detailed and Brief views." (Proposal written in chat
after research of the reference and the classic commander; agreed on 2026-10-14: "jak doporučuješ", that is,
take the recommended answers, and "ano" to create the spec.)

## Context

A panel has two views today:

- **Detailed**: a table with one row per item and columns for name, extension, size and date.
- **Brief**: a grid of small icons and names that fills columns from top to bottom and scrolls sideways.

The view is chosen per panel (View → Detailed ⌃⌥1, View → Brief ⌃⌥2; the Classic Commander scheme adds ⌃F2
and ⌃F1) and remembered with the window layout. Icons are small type icons; no view shows a preview of the
file's content. The Quick View panel (spec 016) shows a full preview of the cursor file in the other panel.

Both views share the keyboard (cursor movement, Space, Insert, ⇧ + movement, masks, ⌃W, quick search, quick
filter, every panel command) and, since spec 024, the mouse rules (modifier clicks, rubber band, drag & drop,
the optional right-button marking).

Research of how others do it:

- **The reference** has Thumbnails as one of its panel views, chosen from the panel menu or with Alt+5. The
  thumbnail size is a setting, Ctrl + mouse wheel changes it while the view is shown, and the thumbnails come
  from loader plugins for pictures, drawings and documents.
- **The best-known Windows two-panel file manager** has a Thumbnails view on Ctrl+Shift+F1 with a width ×
  height setting, an optional thumbnail database on disk, and names cut below each thumbnail.

This spec is part of release 0.6.0, which collects several specs; the version is already raised on the
branch this one builds on, so its pull request adds only the changelog entry.

## Clarifications

### Session 2026-10-14

- Q: Where do the thumbnails come from? → A: From the system's Quick Look thumbnails, for every type the
  system can preview. No plugins of our own.
- Q: Is there a thumbnail cache on disk? → A: No. Thumbnails are kept in memory only; the app never writes
  anything into the user's folders for thumbnails.
- Q: How is the size chosen? → A: Three sizes (64, 128 and 256 points, 128 by default) in Settings → Panels,
  stepped with ⌘+ / ⌘−, ⌘ + mouse wheel or a pinch while the view is shown.
- Q: Which keys switch to the view? → A: ⌃⌥3 by default; the Classic Commander scheme adds ⌃⇧F1.
- Q: Which places get thumbnails? → A: Local folders and volumes mounted in macOS (also network volumes),
  including branch view and search results of such items. Archives, server connections and Network show
  icons only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Browse a folder as thumbnails (Priority: P1)

A user opens a folder of photos and documents and switches the panel to Thumbnails to recognize files by
their content, moves around with the keyboard and opens or copies them as in the other views.

**Why this priority**: This is the feature: without the view and its navigation nothing else matters.

**Independent Test**: In a folder with images, a PDF, a text file and a subfolder, press ⌃⌥3, see a grid of
previews with names, move with the arrows, mark with Space and copy with F5.

**Acceptance Scenarios**:

1. **Given** a panel in Detailed view with the cursor on `photo.jpg`, **When** the user presses ⌃⌥3,
   **Then** the panel shows a grid of cells with a preview and the name under each, View → Thumbnails has a
   checkmark, and the cursor is still on `photo.jpg` and visible.
2. **Given** the Thumbnails view, **When** the user presses → , **Then** the cursor moves to the next item in
   the sort order; **When** they press ↓, **Then** it moves to the item one row below (the same column), or
   to the last item when the row below is shorter.
3. **Given** the Thumbnails view, **When** the user presses Home, End, Page Down or Page Up, **Then** the
   cursor moves to the first item, the last item, or one screen of rows down or up.
4. **Given** the cursor on an item, **When** the user presses Space, Insert or ⇧ + an arrow, **Then** items
   are marked as in the other views (⇧ + ↓ marks every item in the sort order between the old and the new
   cursor), the names of marked items get the marked color and their cells a highlighted background.
5. **Given** marked items, **When** the user presses F5, **Then** the usual copy dialog opens for the marked
   items.
6. **Given** a folder cell under the cursor, **When** the user presses Return, **Then** the panel opens that
   folder and stays in Thumbnails view; Backspace goes back up with the cursor on the folder it came from.
7. **Given** the Thumbnails view, **When** the user presses ⌃⌥1 or ⌃⌥2, **Then** the panel returns to
   Detailed or Brief with the same cursor item and marks.
8. **Given** the left panel in Thumbnails and the right in Detailed, **When** the app is quit and started
   again, **Then** both panels come back in the same views.
9. **Given** the Thumbnails view, **When** the user types the beginning of a name, uses the quick filter or
   changes the sort, **Then** these work as in the other views and the grid follows the new order.

---

### User Story 2 - See real previews quickly (Priority: P1)

The cells show the content of the files, not only type icons, and the view stays smooth in large folders.

**Why this priority**: A thumbnails view without previews is just a larger Brief view.

**Independent Test**: Open a folder with PNG and JPEG images of different shapes, a PDF and a video; the
previews appear within a moment while scrolling stays smooth; open a folder with 100 000 files and scroll.

**Acceptance Scenarios**:

1. **Given** a folder with images, a PDF, a video and a text file, **When** the view is shown, **Then** each
   cell first shows the file's icon and then its preview, scaled to fit the square and keeping its shape;
   the grid does not move when a preview arrives.
2. **Given** a folder, a package (an app) or a file the system cannot preview, **When** shown, **Then** the
   cell shows the item's large system icon as Finder shows it (also custom folder icons and app icons).
3. **Given** a folder with 100 000 files, **When** the user opens it in Thumbnails view and scrolls with the
   keyboard or the mouse, **Then** the panel reacts at once and only the previews of the visible cells (and a
   few around them) are made; previews for cells that were scrolled away are not finished.
4. **Given** a file whose preview is shown, **When** the file changes on disk and the panel refreshes,
   **Then** the cell shows the new preview.
5. **Given** a folder seen before in this session, **When** the user comes back to it, **Then** previews that
   are still remembered appear at once.
6. **Given** any folder shown in Thumbnails view, **When** the user leaves it, **Then** no file or folder was
   created or changed in it.

---

### User Story 3 - Choose the thumbnail size (Priority: P2)

A user wants larger previews to tell photos apart, or smaller ones to see more files.

**Why this priority**: Useful, but the view works with the default size.

**Independent Test**: In Thumbnails view press ⌘+ and ⌘− and see the size change in steps; check Settings →
Panels shows the new size; restart and see the same size.

**Acceptance Scenarios**:

1. **Given** the Thumbnails view at the medium size, **When** the user presses ⌘+ (or ⌘=), **Then** the
   cells grow to the large size and the cursor item stays visible; ⌘+ again does nothing more.
2. **Given** the large size, **When** the user presses ⌘− twice, **Then** the size goes to medium and then to
   small.
3. **Given** the Thumbnails view, **When** the user scrolls with ⌘ held or pinches on the trackpad, **Then**
   the size steps up or down in the same way.
4. **Given** both panels in Thumbnails view, **When** the size changes in one, **Then** the other panel uses
   the new size too, and Settings → Panels → Thumbnail size shows it.
5. **Given** Settings → Panels → Thumbnail size, **When** the user picks another size, **Then** open
   Thumbnails views change at once and the size is kept after a restart.

---

### User Story 4 - Mark and drag with the mouse (Priority: P1)

The mouse works in the grid as in Brief view (spec 024).

**Why this priority**: Visual browsing is often done with the mouse; inconsistent mouse rules would be a
regression against the other views.

**Independent Test**: Click, ⌃-click, ⇧-click and draw a rubber band in the grid; drag marked items onto a
folder cell.

**Acceptance Scenarios**:

1. **Given** the Thumbnails view, **When** the user clicks a cell's picture or name, **Then** the cursor
   moves there and the marks follow the plain-click rule of spec 024; a double click opens the item.
2. **Given** the Thumbnails view, **When** the user ⌃/⌘-clicks, ⇧-clicks or ⌃⇧-clicks cells, **Then**
   the marks change as in spec 024 (toggle, new range, added range), with ranges in the sort order.
3. **Given** the Thumbnails view, **When** the user presses in the space between cells or after the last
   cell and drags, **Then** a rubber band marks the cells it touches (⇧ adds, ⌃/⌘ toggles), and the view
   scrolls when the pointer is held above or below it.
4. **Given** three marked cells, **When** the user drags one of them onto a folder cell, **Then** all three
   are dropped there; a drag cancelled with Esc leaves the marks unchanged.
5. **Given** the right-button marking setting of spec 024 is on, **When** the user right-clicks or
   right-drags over cells, **Then** they are marked as in the other views.

---

### User Story 5 - Places without previews (Priority: P2)

Inside archives, on server connections and in Network the view still works, with icons instead of previews,
so the user is never slowed down by downloading or extracting files.

**Why this priority**: Correctness and safety on slow or remote sources; the view itself is still usable.

**Independent Test**: Open a zip archive and an SFTP connection in Thumbnails view; cells show type icons and
nothing is downloaded or extracted.

**Acceptance Scenarios**:

1. **Given** a panel inside a zip archive in Thumbnails view, **When** shown, **Then** every cell shows the
   type icon and no member is extracted for a preview.
2. **Given** a server connection or Network in Thumbnails view, **When** shown, **Then** the cells show type
   icons and no file is downloaded for a preview.
3. **Given** a slow volume mounted in macOS (for example a network share), **When** shown in Thumbnails
   view, **Then** the panel reacts at once and the previews arrive in the background as they are made.
4. **Given** search results or a branch view with items on a local disk, **When** shown in Thumbnails view,
   **Then** those items get previews.

---

### Edge Cases

- An empty folder: only the ".." cell.
- Very long names or names that are only an extension: the name uses at most two lines and is cut with "…";
  the full name appears in a tooltip.
- Images with extreme shapes (a panorama, a 1-pixel line): the preview keeps its shape inside the square and
  stays visible (at least one point thick).
- Huge images and long videos: the preview is made by the system without the app decoding the whole file;
  the panel never waits for it.
- A file deleted or changed while its preview is being made: no error, the cell disappears or refreshes with
  the next listing.
- A file replaced by another with the same name: the new modification date gives a new preview.
- A file that cannot be read (no permission): the cell shows the icon, no message.
- The panel or window is resized: the grid wraps to the new width and the cursor item stays visible.
- The panel is narrower than one cell: one column, the cell is cut on the right, the view still works.
- The size changes while previews load: previews of the new size are made, the old requests stop.
- Dark mode and the marked/cursor colors follow the system appearance like the other views.
- Hidden files (when shown) appear dimmed as in the other views.
- The Quick View panel in the other panel keeps working with the cursor in Thumbnails view.

## Requirements *(mandatory)*

### Functional Requirements

**Switching**

- **FR-001**: The app MUST offer View → Thumbnails, default key ⌃⌥3; the Classic Commander scheme MUST also
  bind ⌃⇧F1; the keys are customizable like every command.
- **FR-002**: The View menu MUST show a checkmark at the current view of the active panel (Detailed, Brief or
  Thumbnails).
- **FR-003**: The view MUST be chosen per panel and remembered with the window layout, like Detailed and
  Brief.
- **FR-004**: Switching between any two views MUST keep the cursor item, the marks, the sort and the filter,
  and MUST leave the cursor item visible.

**The grid**

- **FR-005**: The view MUST lay out one cell per item in rows from left to right that wrap at the panel width
  and scroll vertically, in the panel's sort order, with ".." first when present.
- **FR-006**: Each cell MUST show a picture in a square of the chosen size and the item's name below it,
  centered, on at most two lines, cut with "…" when longer; the full name MUST be shown in a tooltip.
- **FR-007**: The picture MUST be the file's preview when one is available (FR-010), scaled to fit the square
  while keeping its shape; otherwise the item's large system icon (per item, including custom folder icons
  and app icons).
- **FR-008**: The cursor cell, marked cells (the marked name color and a highlighted cell background) and
  hidden items (dimmed) MUST be drawn with the same meaning and colors as in the other views, in light and
  dark appearance.
- **FR-009**: The info line and the status line MUST behave as in the other views.

**Previews**

- **FR-010**: Previews MUST come from the system's preview service for every file type it can preview
  (images, PDF, video, documents, text, …), made in the background; the panel MUST never wait for a preview.
- **FR-011**: Previews MUST be requested only for the visible cells and a small margin around them; requests
  for cells that leave this area MUST be cancelled, and the number of requests running at once MUST be
  limited.
- **FR-012**: While a preview is being made the cell MUST show the item's icon; the preview MUST replace it
  without changing the layout. A preview that fails or is not available MUST leave the icon, without a
  message.
- **FR-013**: Made previews MUST be kept in memory with a size limit, dropping the least recently used first,
  and MUST be keyed by the item and its modification date and the size, so a changed file gets a new preview.
- **FR-014**: The app MUST NOT write any file for previews (no cache on disk, nothing in the user's folders).
- **FR-015**: Previews MUST be made only for items on a local disk or a volume mounted in macOS (including
  network volumes, branch view and search results of such items). Items in archives, on server connections
  and in Network MUST show type icons, and the app MUST NOT extract or download anything for a preview.

**Size**

- **FR-016**: The thumbnail size MUST be one of small (64 pt), medium (128 pt, default) or large (256 pt), set
  in Settings → Panels → Thumbnail size and kept after a restart.
- **FR-017**: While a Thumbnails view has the focus, ⌘+ and ⌘= MUST step to the next larger size and ⌘− to the
  next smaller one; ⌘ + mouse wheel and the trackpad pinch MUST step the same way; at the largest or smallest
  size the step does nothing.
- **FR-018**: A size change MUST apply to every Thumbnails view at once, update the setting, and keep the
  cursor item visible.

**Keyboard**

- **FR-019**: ← and → MUST move the cursor by one item in the sort order; ↑ and ↓ by one row (the same
  column; to the last item when the target row is shorter, to the first item from the first row up); Home and
  End to the first and last item; Page Up and Page Down by the number of fully visible rows; ⌘↑ and ⌘↓ as in
  the other views.
- **FR-020**: Marking keys (Space, Insert, ⇧ + movement keys, masks, ⌃W), quick search, quick filter,
  Return, Backspace, the function keys and every panel command MUST work as in Brief view; ranges marked with
  ⇧ + movement MUST contain every item in the sort order between the old and the new cursor position.

**Mouse**

- **FR-021**: The mouse rules of spec 024 MUST apply as in Brief view: plain click, double click, ⌃/⌘, ⇧ and
  ⌃⇧ clicks, the rubber band with autoscroll and ⇧ / ⌃ / ⌘ variants, drag & drop (all marked items when a
  marked one is dragged), drops onto folder cells and the panel, the right-click menu and the right-button
  marking setting.
- **FR-022**: The cell's picture and name text MUST count as the item for clicks and drags; the rest of the
  cell, the gaps between cells and the area after the last cell MUST count as empty space (a click there
  clears the marks in the default mode, a drag there starts a rubber band).

**Other**

- **FR-023**: The Quick View panel, branch view, search results, hidden files, sorting and refresh MUST keep
  working with a panel in Thumbnails view.
- **FR-024**: Detailed and Brief views MUST behave as before.

### Key Entities

- **Panel view**: Detailed, Brief or Thumbnails, per panel, stored with the window layout.
- **Thumbnail size**: small, medium or large; one app-wide setting.
- **Preview**: the picture made for an item at a size; identified by the item, its modification date and the
  size; kept in memory only.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a local folder of 50 images, the previews of all visible cells appear within 2 seconds after
  switching to the view.
- **SC-002**: In a folder with 100 000 items, switching to the view, scrolling a screen and moving the cursor
  each react within 0.1 seconds; the view never stops responding while previews are made.
- **SC-003**: Memory used by remembered previews stays within the set limit, however many folders are browsed.
- **SC-004**: After browsing any number of folders in Thumbnails view, no file or folder was created or
  changed in them.
- **SC-005**: Every navigation, marking and size rule of this spec has an automated test, and the GUI check
  on the test copy passes in both panels.

## Assumptions

- The system preview service decides which file types get a preview; types it cannot preview show icons.
- The memory limit for previews is a fixed amount chosen in the plan (enough for several screens of large
  previews), not a setting.
- Cell spacing, name font and the highlight shapes follow the Brief view's look, adjusted to the larger cells.
- The size steps apply only while a Thumbnails view has the focus; elsewhere ⌘+ / ⌘− keep their meaning (the
  viewer and the file comparison use them for text size).
- Out of scope: thumbnail plugins of our own, a thumbnail cache on disk, a free width × height size, extra
  lines under the thumbnail (size, date), previews inside archives or on servers, editing or rotating images,
  playing videos in the grid, separate "tiles" or "icons" views.
- Deviations from the reference, recorded on purpose: previews come from the system instead of plugins;
  there is no thumbnail cache on disk; there are three fixed sizes instead of a free width × height; the grid
  scrolls vertically.
