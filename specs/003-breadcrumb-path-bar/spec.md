# Feature Specification: Clickable Breadcrumb Path Bar

**Feature Branch**: `003-breadcrumb-path-bar`

**Created**: 2026-10-08

**Status**: Draft

**Input**: User description: "Clickable breadcrumb path bar for file panels. Users coming from
Commander One / Finder and from Windows two-panel managers expect to jump to any parent folder
with one click. The new breadcrumb bar replaces the editable path field by default; the text
field stays available as a setting. Mac look (Finder path bar / Commander One style) is
preferred over the reference's plain-text directory line; deviations from the reference are
listed in the spec."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Jump to a parent folder with one click (Priority: P1)

Above the file list of each panel, the user sees where they are as a row of segments, from the
volume to the current folder, e.g. "Macintosh HD › Users › tester › Projects › docs". Each segment
has a small icon and the folder name. Clicking any segment takes the panel straight to that
folder, and the cursor lands on the folder the user came from, so they can step back in with
Enter. This is the default look; users who prefer the old text field can switch back in
Settings.

**Why this priority**: This is the feature itself: one-click navigation up the folder hierarchy,
as in Finder's path bar and Commander One, and as in the reference's directory line.

**Independent Test**: In the test copy of the app, open a test folder four levels deep in the
left panel, click the second segment; the panel shows that folder and the cursor is on the child
folder that leads back to where the user was. Keyboard focus is still in the file list.

**Acceptance Scenarios**:

1. **Given** a fresh installation, **When** the main window opens, **Then** both panels show the
   location as breadcrumb segments separated by "›", starting with the volume, with a volume icon
   on the first segment, a home icon on the user's home folder and folder icons on the others.
2. **Given** the left panel in `<test>/a/b/c`, **When** the user clicks the segment "a",
   **Then** the left panel shows `<test>/a`, the cursor is on "b", and Back returns to
   `<test>/a/b/c`.
3. **Given** the panel in `<test>/a/b/c`, **When** the user clicks the last segment "c",
   **Then** nothing happens.
4. **Given** the mouse is moved over a segment, **When** it hovers, **Then** that segment is
   highlighted; moving away removes the highlight.
5. **Given** the right panel is active and the user clicks a segment in the left panel,
   **When** the left panel changes folder, **Then** the left panel becomes the active panel with
   keyboard focus in its file list, as when clicking anywhere else in that panel.
6. **Given** the active panel, **When** the user looks at both path bars, **Then** the active
   panel's bar has the accent-colored background and the inactive one the neutral background, as
   today.
7. **Given** Settings → Appearance → Path bar is switched to "Text field", **When** the change is
   made, **Then** both panels immediately show the editable path text field as before this
   feature, and the choice survives a quit and relaunch.
8. **Given** "Show icons in path bar" is turned off, **When** the change is made, **Then** the
   segments show names only, in both panels, immediately.
9. **Given** dark mode or increased contrast is switched on, **When** the bar is visible,
   **Then** text, icons, separators and highlights follow the system appearance.

---

### User Story 2 - Type a path when needed (Priority: P1)

Breadcrumbs must not take away the ability to type or paste a path (including `sftp://` and
`ftp://` addresses). Clicking the empty area right of the last segment, or pressing ⌘L ("Edit
Path"), turns the bar into the familiar text field with the full path selected; Enter goes there,
Esc cancels, and the bar returns to breadcrumbs.

**Why this priority**: Typing a path is used daily (pasting a path, connecting to a server);
without it the default mode would be a step back from today.

**Independent Test**: Press ⌘L in the active panel, type the path of another test folder, press
Enter; the panel goes there and the bar shows breadcrumbs again with focus in the file list.
Press ⌘L and then Esc; nothing changes.

**Acceptance Scenarios**:

1. **Given** breadcrumb mode, **When** the user presses ⌘L, **Then** the active panel's bar
   becomes a text field containing the full path of the current location, all text selected,
   with keyboard focus in it.
2. **Given** breadcrumb mode, **When** the user clicks the empty area right of the last segment,
   **Then** the same happens for that panel (and it becomes the active panel).
3. **Given** the text field opened by ⌘L, **When** the user types a valid path and presses
   Enter, **Then** the panel goes there exactly as the text field does today, the bar returns to
   breadcrumbs, and focus returns to the file list.
4. **Given** the text field opened by ⌘L, **When** the user types a path that does not exist and
   presses Enter, **Then** the app beeps, the status line shows the error, the panel stays where
   it was, and the bar returns to breadcrumbs showing the unchanged location.
5. **Given** the text field opened by ⌘L, **When** the user presses Esc or clicks into the file
   list, **Then** nothing is navigated and the bar returns to breadcrumbs.
6. **Given** the text field opened by ⌘L, **When** the user types `sftp://user@host/path` and
   presses Enter, **Then** the connection is made exactly as from today's path field.
7. **Given** text-field mode is chosen in Settings, **When** the user presses ⌘L, **Then** the
   text field of the active panel gets focus with its content selected.
8. **Given** the user assigned another shortcut to "Edit Path" in Settings → Keyboard, **When**
   they press it, **Then** it behaves like ⌘L above; the command is also in the Go menu.

---

### User Story 3 - More actions on a segment (Priority: P2)

Right-clicking a segment offers actions for that folder: open it in the other panel, open it in a
new tab, copy its path, set it as a hot path, show it in Finder. ⌘-click on a segment opens that
folder in a new tab of the same panel.

**Why this priority**: Convenient shortcuts that the reference offers in part (hot path, copy
path); the main navigation works without them.

**Independent Test**: Right-click the segment "a" of `<test>/a/b/c` in the left panel and choose
"Open in Other Panel"; the right panel shows `<test>/a` and the left panel is unchanged.

**Acceptance Scenarios**:

1. **Given** the left panel in `<test>/a/b/c`, **When** the user right-clicks "a" and chooses
   "Open in Other Panel", **Then** the right panel shows `<test>/a` and the left panel stays in
   `<test>/a/b/c`.
2. **Given** the same, **When** the user chooses "Open in New Tab", **Then** a new tab opens in
   the left panel showing `<test>/a`, and the previous tab still shows `<test>/a/b/c`.
3. **Given** the same, **When** the user chooses "Copy Path", **Then** the clipboard contains
   the full path of `<test>/a` as text.
4. **Given** the same, **When** the user chooses a slot under "Set as Hot Path", **Then** that hot
   path slot points to `<test>/a`, the same as the existing "Set Hot Path" command would set it
   for the current folder (including asking before replacing an occupied slot, if the existing
   command asks).
5. **Given** the same, **When** the user chooses "Show in Finder", **Then** Finder shows
   `<test>/a`.
6. **Given** a segment of a remote location or of a folder inside an archive, **When** the user
   right-clicks it, **Then** "Show in Finder" is disabled; the other items work where the panel
   supports them for that location, otherwise they are disabled.
7. **Given** the left panel in `<test>/a/b/c`, **When** the user ⌘-clicks "a", **Then** a new
   tab opens in the left panel showing `<test>/a`.

---

### User Story 4 - Long paths stay readable (Priority: P2)

When the path does not fit, whole segments in the middle collapse into a "…" segment. The volume
and the current folder are always visible. Clicking "…" lists the hidden folders to choose from.

**Why this priority**: Deep folders are common (projects, Library); without collapsing, the bar
would be unusable in a narrow panel.

**Independent Test**: Open a test folder ten levels deep and narrow the panel; the bar shows the
volume, "…", and the last few folders; clicking "…" lists the hidden folders and choosing one
goes there.

**Acceptance Scenarios**:

1. **Given** a path whose segments do not fit, **When** the bar is laid out, **Then** whole
   middle segments are replaced by one "…" segment, the first segment and the current folder
   are always visible, and as many segments next to the current folder as fit are kept.
2. **Given** the collapsed bar, **When** the user clicks "…", **Then** a menu lists the hidden
   folders in path order with their icons, and choosing one takes the panel there (cursor on the
   child on the path, as in User Story 1).
3. **Given** a current folder whose name alone does not fit, **When** the bar is laid out,
   **Then** only that last name is shortened with "…" at its end; no other name is ever cut.
4. **Given** the window or the panel split is resized, **When** the width changes, **Then** the
   segments are laid out again at once.

---

### User Story 5 - Archives, servers and search results (Priority: P2)

The breadcrumbs also work where the panel shows something other than a plain local folder:
inside an archive, on an SFTP/FTP server, and when it shows search results.

**Why this priority**: Without it the bar would show something wrong or useless in these
places; the main local navigation works without it.

**Independent Test**: Open a test archive with nested folders, enter two folders inside it, click
the archive segment; the panel shows the archive root. Click the segment of the folder that
contains the archive; the panel leaves the archive with the cursor on the archive file.

**Acceptance Scenarios**:

1. **Given** the panel inside `<test>/pack.zip/inner/deep`, **When** the user looks at the bar,
   **Then** it shows the segments to `<test>`, then "pack.zip" with an archive icon, then "inner"
   and "deep".
2. **Given** the same, **When** the user clicks "pack.zip", **Then** the panel shows the root of
   the archive; **When** the user clicks the segment of `<test>`, **Then** the panel leaves the
   archive and the cursor is on "pack.zip".
3. **Given** the panel on a remote server, **When** the user looks at the bar, **Then** the first
   segment is the server (as "user@host" or host, with a network icon), followed by the remote
   folders; clicking a folder segment goes there on the server.
4. **Given** the panel shows search results, **When** the user looks at the bar, **Then** it
   shows the results title as a first segment that cannot be clicked, followed by the clickable
   segments of the folder the search started in; clicking one of them leaves the results and goes
   to that folder.

---

### Edge Cases

- **Folder disappears**: the current folder is deleted, renamed or its volume is unmounted; the
  panel falls back to another location as today and the bar shows that location.
- **Volume root**: a panel at the root of a volume shows a single segment (the volume).
- **Folders outside the home folder or on other volumes**: the first segment is that volume
  (e.g. an external disk or "Macintosh HD" for system folders such as `/Library`).
- **Names containing "›" or very long names**: shown as they are; the separator is drawn between
  segments, not taken from the name, so a name with "›" is never split into two segments.
- **Paths shown today under another form**: the bar follows the same display path as the current
  text field (e.g. symbolic links resolved the same way), so the two modes always agree.
- **Click while the panel is still loading a folder**: the latest click wins; the bar ends up
  showing the location the panel actually shows.
- **Edit Path while the panel shows search results**: the text field shows what today's field
  shows for results; Enter with unchanged text keeps the results (as today).
- **Settings changed while the text field is being edited**: switching the mode in Settings ends
  the editing without navigating.
- **Right-to-left languages**: out of scope; the app has no right-to-left localization.

## Requirements *(mandatory)*

### Functional Requirements

**Breadcrumb bar**

- **FR-001**: Each panel MUST show its location above the file list either as breadcrumbs or as
  the editable path text field, according to the setting "Path bar" (Breadcrumbs / Text field) in
  Settings → Appearance. Default: Breadcrumbs.
- **FR-002**: Changing the path bar setting MUST apply to both panels at once without a restart,
  and the setting MUST be remembered across launches.
- **FR-003**: In breadcrumb mode, the location MUST be shown as a sequence of segments from the
  root of the location (volume, server or archive host volume) to the current folder, separated by
  "›".
- **FR-004**: Each segment MUST show the folder name and, when "Show icons in path bar" is on (the
  default), a small icon: the volume's icon for a volume, the home icon for the user's home
  folder, an archive icon for an archive, a network icon for a server, and a folder icon
  otherwise. Icons MUST follow the system appearance.
- **FR-005**: Hovering a segment that can be clicked MUST highlight it.
- **FR-006**: Clicking a segment other than the current folder MUST take the panel to that folder,
  add the change to the back/forward history, and place the cursor on the item of the clicked
  folder that leads back toward the previous location (the same rule as going to the parent).
- **FR-007**: Clicking the current folder's segment MUST do nothing.
- **FR-008**: Segments MUST never take keyboard focus. Clicking a segment MUST make that panel the
  active panel with keyboard focus in its file list.
- **FR-009**: The path bar background MUST mark the active panel as today (accent color for the
  active panel, neutral for the other) in both modes.
- **FR-010**: The bar MUST show the same location text as the text field mode would (same display
  path rules).
- **FR-011**: Folder names MUST be shown in full, never split or cut, except as allowed by FR-016.

**Editing a path**

- **FR-012**: A new command "Edit Path" MUST exist in the Go menu with the default shortcut ⌘L,
  assignable in Settings → Keyboard like any command. In breadcrumb mode it MUST replace the
  active panel's bar with the text field holding the current location text, all selected and
  focused; in text-field mode it MUST focus the text field and select its content.
- **FR-013**: Clicking the empty area right of the last segment MUST do the same as "Edit Path"
  for that panel.
- **FR-014**: Enter in the text field MUST behave exactly as today's path field (local paths,
  relative paths, `~`, `sftp://` and `ftp://` addresses, errors with a beep and a message in the
  status line). Esc, Enter, or moving focus away MUST end editing; in breadcrumb mode the bar then
  shows breadcrumbs again for the location the panel shows, and focus returns to the file list
  (except when focus was moved elsewhere by the user).

**Long paths**

- **FR-015**: When the segments do not fit the width of the bar, whole middle segments MUST be
  replaced by one "…" segment; the first segment and the current folder MUST always be visible,
  and segments next to the current folder MUST be kept as long as they fit.
- **FR-016**: Only when the current folder's segment alone does not fit next to the first segment
  and "…", its name MAY be shortened with "…" at the end.
- **FR-017**: Clicking "…" MUST show a menu of the hidden folders in path order (with icons when
  icons are on); choosing one MUST navigate as in FR-006.
- **FR-018**: The bar MUST re-lay out immediately when its width changes.

**Context menu**

- **FR-019**: Right-clicking a segment MUST show a menu acting on that segment's folder: Open in
  Other Panel, Open in New Tab, Copy Path, Set as Hot Path (one item per hot path slot, with the
  slot's current target shown where it has one), Show in Finder.
- **FR-020**: Items that cannot act on the segment's location (e.g. Show in Finder for a remote
  or archive location) MUST be disabled.
- **FR-021**: ⌘-click on a segment MUST open that folder in a new tab of the same panel.
- **FR-022**: "Set as Hot Path" MUST store the same thing and follow the same rules as the
  existing "Set Hot Path" command does for the current folder.

**Special locations**

- **FR-023**: Inside an archive, the bar MUST show the segments leading to the archive file, a
  segment for the archive file, and segments for the folders inside the archive. Clicking the
  archive segment MUST go to the archive root; clicking a segment outside the archive MUST leave
  the archive, with the cursor on the item leading back (the archive file when its folder is
  clicked).
- **FR-024**: On a remote server, the first segment MUST be the server (as "user@host" when a
  user name is part of the connection, otherwise the host), followed by the remote folders.
- **FR-025**: When the panel shows search results, the bar MUST show the results title as a
  first, non-clickable segment, followed by the clickable segments of the folder the search
  started in; clicking one of those MUST leave the results and go to that folder.

**General**

- **FR-026**: Each segment MUST be exposed to accessibility as a button named after its folder;
  the bar as a group named "Path"; the "…" segment as a button named for the hidden folders.
- **FR-027**: All new user-visible texts MUST be localized (English source, Czech translation).
- **FR-028**: The feature MUST only navigate: no segment action may copy, move, rename or delete
  any file or folder.
- **FR-029**: Breadcrumbs MUST appear only in the file panels of the main window.

### Deviations from the reference program

- **D-001 (FR-003, FR-004)**: The reference's directory line looks like plain text and highlights
  a path part only under the mouse. Here the path is shown as Mac-style segments with icons and
  "›" separators, like Finder's path bar; icons can be turned off.
- **D-002 (FR-012–FR-014)**: In the reference, a path is typed in the Change Directory dialog.
  Here that dialog (⇧F7) stays, and in addition the bar itself turns into a text field (⌘L or a
  click right of the path), as the app's path field does today.
- **D-003 (FR-019, FR-021)**: The reference's right-click menu on the path offers setting a hot
  path and copying the path. Here it also offers Open in Other Panel, Open in New Tab and Show in
  Finder, and ⌘-click opens a new tab (macOS convention).
- **D-004 (FR-001)**: The reference has no choice of path bar style; here the user can keep the
  text field.

### Key Entities

- **Path segment**: one step of the location: its display name, the location it leads to, its
  kind (volume, home, folder, archive, server, results title) and whether it can be clicked.
- **Breadcrumb trail**: the ordered segments of a panel's current location, from the root to the
  current folder; derived from the location, never stored.
- **Path bar settings**: two remembered choices: the path bar style (Breadcrumbs by default) and
  "Show icons in path bar" (on by default).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can go from any folder to any of its ancestors with a single click, without
  using the keyboard, in 100 % of tested locations (local, archive, remote).
- **SC-002**: After clicking an ancestor, the cursor is on the item leading back to the previous
  folder in 100 % of cases, so pressing Enter returns one level down.
- **SC-003**: Everything that can be typed into today's path field can still be typed after
  pressing ⌘L in breadcrumb mode, with the same result, in 100 % of the cases covered by the
  existing path field tests.
- **SC-004**: At any panel width down to the minimum window size, the first segment and the
  current folder are visible, no folder name is cut except the current folder's when it alone
  does not fit, and no text overlaps or wraps.
- **SC-005**: The bar shows the new location at the same moment the file list does after any
  navigation (keyboard, click, history, hot path); a user never sees a stale path.
- **SC-006**: No segment action changes any file or folder (verified by the GUI tests running in
  test folders only).

## Assumptions

- The existing path text field, its input rules and its error handling are reused unchanged for
  typing a path; this feature does not change what can be typed.
- The existing commands and rules for tabs, hot paths, copying a path and showing in Finder are
  reused for the segment menu; the menu adds no new rules of its own.
- ⌘L is free in the file panel key map (the viewer's own ⌘L "Go to Line" is a separate key map and
  stays unchanged).
- Icons come from the system (volume, home, folder, archive and network icons as Finder and the
  file list show them).
- The volume shown as the first segment for local paths is the volume that contains the folder,
  named as the volume bar names it.
- Verification follows the project rules: unit tests for building segments from a location and
  for the collapsing rule in the core; GUI checks only in the test copy of the app with panels in
  test folders.
