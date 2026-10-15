# Feature Specification: File List and Main Window Fonts

**Feature Branch**: `031-panel-fonts`

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "Panel and bar fonts: choose the font (family, style and size) of the file
lists and, separately, of the panel bars, with an easy way back to the defaults." Requested by a user;
agreed with the maintainer in chat on 2026-10-15 ("like the classic commander, let them set a custom font
too, there should be an easy way back to the defaults, otherwise as you recommend").

## Context

Today the file list draws its rows in the system font at the regular size (13 pt, rows 18 pt high) and the
bars of a panel (volume bar, drive row, tab titles, path bar, status line) in the small system size
(11 pt). Neither can be changed. Settings → Appearance already holds the look of marked items (color, bold).

Usual behavior elsewhere: the reference program has Configuration → Appearance → "Panel Font" with a button
that opens the font dialog. The classic two-panel file manager on Windows has a Fonts page with separate
fonts for the file list, the main window and the dialogs, each with a button that opens the font dialog.
This feature follows that model with two of its three fonts — the file list and the main window — chosen in
the standard macOS Fonts panel, and adds a way back to the defaults. The dialog font is left out: macOS
dialogs keep the system font.

## Clarifications

### Session 2026-10-15

- Q: Size only, or also the font family? → A: The whole font — family, style and size — as in the classic
  commander; the standard macOS Fonts panel is used to choose it.
- Q: How many font settings? → A: Two: the file list, and the panel bars together (volume bar, drive row,
  tab titles, path bar, status line). *Superseded below: the classic commander's two fonts.*
- Q: How does the user get back? → A: A "Default" button on each row and "Restore Default Fonts" for all.
- Q: Keys? → A: Commands for a bigger, smaller and default file list font without default keys, assignable
  in Settings → Keyboard.
- Q: The command line and the function key bar? → A: Unchanged. *Superseded below: they follow the main
  window font.*
- Q: Colors? → A: Left out for now (a later spec).
- Q: The Fonts panel after Settings closes? → A: It stops changing the panels (planning, 2026-10-15).
- Q: Do the volume buttons grow with the bar font? → A: No — they get their own row. Three rows: "File
  list", "Path, tabs and status" (path bar, tab titles, status line with its free space) and "Volume
  buttons" (volume bar, drive row with its free space), each set separately (implementation, 2026-10-15;
  replaces the single "Bars" row). *Superseded below.*
- Q: Which parts follow which font, so that it is consistent? → A: As close to the classic commander as
  possible: two rows, "File list" and "Main window". The file list font is used for the rows of every list,
  the column titles and the status line under the panel (both two points smaller, as today), the folder
  history and the hot path menu, and the rename field. The main window font is used for the volume bar, the
  drive row with its free space, the path bar, the tab titles, the command line and the function key bar.
  The main menu, context menus, the volume menu, dialogs, Settings, the viewer and the quick view keep the
  system fonts (implementation, 2026-10-15; replaces the three rows).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Choose the file list font (Priority: P1)

A user finds the file names too small (or wants a monospaced font for aligned names). They open Settings →
Appearance, click "Change…" next to "File list", and pick a family, style and size in the Fonts panel; the
panels change while they choose. The choice stays after the app restarts.

**Why this priority**: It is what the user asked for: readable file lists on large or high-resolution
displays.

**Independent Test**: Choose Menlo 16 pt for the file list: every panel in every window shows its rows in
Menlo 16 pt with taller rows; after a restart they still do.

**Acceptance Scenarios**:

1. **Given** Settings → Appearance, **When** the user looks at the "Fonts" section, **Then** the row "File
   list" shows the current font as text (for example "System font, 13 pt" or "Menlo Regular, 12 pt"),
   drawn in that font where it fits, with the buttons "Change…" and "Default".
2. **Given** the row "File list", **When** the user clicks "Change…", **Then** the standard macOS Fonts panel
   opens preset to the current file list font.
3. **Given** the Fonts panel opened from "File list", **When** the user changes the family, the style or the
   size, **Then** every panel in every window shows the new font at once, and the row in Settings shows it.
4. **Given** a chosen file list font, **When** a panel shows the detailed list, the brief list or the
   thumbnails, a Find results listing or a branch listing, **Then** the names and all columns are drawn in
   that font; the column titles and the status line under the panel use it two points smaller; the folder
   history and the hot path menu list their entries in it.
5. **Given** a larger or smaller font, **When** the list is shown, **Then** the row height follows the font
   (its line height plus today's padding, never less than today's 18 pt), the brief view's column widths and
   the thumbnail labels follow it, and the icons stay 16 pt.
6. **Given** marked items, **When** the font is changed, **Then** they keep their emphasis: the mark color
   and, with "Bold" on, the bold face of the chosen family.
7. **Given** a size outside 8–32 pt chosen in the Fonts panel, **When** it is applied, **Then** the nearest
   limit is used.
8. **Given** a chosen font, **When** the app is quit and started again, **Then** the panels use that font.

---

### User Story 2 - Choose the main window font (Priority: P1)

A user wants the volume buttons, the tab titles, the path, the command line and the function keys easier to
read. They click "Change…" next to "Main window" and pick a larger size; those bars grow in height together,
the file lists stay as they are, and nothing pushes the panels apart.

**Why this priority**: The user asked for the bars separately from the file list.

**Independent Test**: Choose 15 pt for "Main window": the volume bar, the drive row, the path bar and the tab
titles of both panels, the command line and the function key bar grow; the file lists, their column titles
and status lines stay; the divider does not move.

**Acceptance Scenarios**:

1. **Given** the row "Main window", **When** the user changes the font in the Fonts panel opened from it,
   **Then** the volume bar, the drive row with its free space, the tab titles, the path bar (breadcrumbs, and
   the path field while it is edited, which stays monospaced at the chosen size unless the chosen font is
   monospaced itself), the command line (monospaced likewise) and the function key bar use it at once; the
   file lists do not change.
2. **Given** a larger main window font, **When** the bars are shown, **Then** each bar grows in height to fit the
   text; with a smaller font they shrink, never below the height of their icons.
3. **Given** a panel too narrow for all items, **When** the main window font is larger, **Then** items are shortened
   or hidden as today (the volume bar hides items from the end, tabs shorten their titles, the path bar
   shortens the middle); the panel never widens and the divider stays where it is.
4. **Given** a size outside 8–20 pt, **When** it is applied, **Then** the nearest limit is used.
5. **Given** a chosen main window font, **When** the app is started again, **Then** the bars use that font.

---

### User Story 3 - Back to the defaults (Priority: P1)

A user tried a font they do not like and wants the original look back without remembering what it was.

**Why this priority**: Asked for explicitly; without it an experiment is hard to undo.

**Independent Test**: After choosing custom fonts for both rows, "Restore Default Fonts" returns the panels and
the bars to exactly today's look.

**Acceptance Scenarios**:

1. **Given** a custom file list font, **When** the user clicks "Default" on the row "File list", **Then** the
   panels return to the system font at the regular size and the row shows "System font, 13 pt"; the bars are
   unchanged.
2. **Given** a custom main window font, **When** the user clicks "Default" on the row "Main window", **Then**
   the bars, the command line and the function keys return to their system fonts; the file lists are
   unchanged.
3. **Given** custom fonts on both rows, **When** the user clicks "Restore Default Fonts", **Then** all return
   to the defaults.
4. **Given** a row at its default, **When** Settings is shown, **Then** its "Default" button is disabled;
   "Restore Default Fonts" is disabled when every row is at its default.
5. **Given** a chosen font that is no longer installed, **When** the app starts or the font is removed while
   it runs, **Then** that row silently uses its default and Settings shows the default.

---

### User Story 4 - Change the file list size from the keyboard (Priority: P2)

A user who presents their screen wants larger names for a moment and back again, without opening Settings.

**Why this priority**: Convenient, but the setting already covers the need.

**Independent Test**: Assign keys to "Bigger File List Font" and "Smaller File List Font": each press changes
the file list by 1 pt within the limits, keeping the family and style; "Default File List Font" returns to
the default.

**Acceptance Scenarios**:

1. **Given** the View menu, **When** the user opens it, **Then** it has "Bigger File List Font", "Smaller File
   List Font" and "Default File List Font", without default keys; all three can be given keys in Settings →
   Keyboard.
2. **Given** the file list at 13 pt, **When** "Bigger File List Font" is chosen, **Then** the file list is
   14 pt in the same family and style, and Settings shows it.
3. **Given** the file list at 32 pt (or 8 pt), **When** "Bigger" (or "Smaller") is chosen, **Then** nothing
   changes and the command is disabled.
4. **Given** the default file list font, **When** the user looks at the View menu, **Then** "Default File
   List Font" is disabled.

---

### Edge Cases

- A font without a bold face: marked items use the regular face with the mark color.
- A symbol-only or very decorative font: allowed, nothing is checked; "Default" brings the panels back.
- A rename field open in a panel when the font changes: the field takes the new font; the typed text and
  the selection stay.
- A long listing when the font changes: the cursor row stays visible.
- The Fonts panel stays open after Settings is closed: it no longer changes the panels; nothing else in the
  app changes. Choosing "Change…" on the other row retargets the Fonts panel to it.
- The Fonts panel is used for something else meanwhile (for example a text field in a dialog): the panels do
  not change.
- Two windows open: both change.
- A very large file list font in the narrowest panel (240 pt): the columns shorten their text; no panel
  widens.
- The quick view pane and the internal viewer keep their own fonts.
- Exporting the settings (one file with the preferences) includes both fonts; importing it on a Mac without
  the chosen font falls back to the default for that row.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Settings → Appearance MUST have a "Fonts" section with two rows, "File list" and "Main window",
  each with a short caption saying what it changes, showing the current font as text (family and style, or "System font", and the size in points), drawn in
  that font where it fits, with the buttons "Change…" and "Default", and the button "Restore Default Fonts"
  below them.
- **FR-002**: "Change…" MUST open the standard macOS Fonts panel preset to that row's font; while the Fonts
  panel is targeted at a row, each change of family, style or size MUST apply to that row at once.
- **FR-003**: The file list font MUST be used for every item and column of the detailed list, the brief
  list, the labels of the thumbnails, Find results and branch listings in every panel of every window, for
  the rename field, and, two points smaller, for the column titles and the status line under each panel
  with its free space; the folder history and the hot path menu MUST list their entries in it.
- **FR-004**: The row height of the file list MUST be the chosen font's line height plus today's padding,
  never less than 18 pt; the brief view's column widths and the thumbnail labels MUST follow the font; icons
  MUST stay 16 pt.
- **FR-005**: Marked items MUST keep the mark color and, with "Bold" on, use the bold face of the chosen
  family when it has one, otherwise the regular face.
- **FR-006**: The main window font MUST be used for the volume bar, the drive row with its free space, the
  tab titles, the path bar (breadcrumbs; the path field while edited), the command line and the function key
  bar; the path field and the command line MUST stay monospaced (the chosen font when it is monospaced, else
  the monospaced system font at the chosen size); the height of each bar MUST follow the font; the volume
  buttons keep their size relative to the text.
- **FR-007**: A larger main window or file list font MUST NOT widen a panel or move the divider; text that does not
  fit is shortened and bar items are hidden as today.
- **FR-008**: File list sizes MUST be limited to 8–32 pt and main window sizes to 8–20 pt; a size outside is
  replaced by the nearest limit.
- **FR-009**: "Default" MUST return its row to the system font at that row's default size (file list 13 pt,
  main window 11 pt); "Restore Default Fonts" MUST return both; each button MUST be disabled while what it would
  restore is already in use.
- **FR-010**: Both fonts MUST be remembered across launches and included in the settings export and
  import.
- **FR-011**: A remembered font that is not installed MUST be replaced by that row's default without a
  message.
- **FR-012**: The View menu MUST have "Bigger File List Font", "Smaller File List Font" (1 pt steps within
  the limits, same family and style) and "Default File List Font", without default keys and assignable in
  Settings → Keyboard; each MUST be disabled when it would change nothing.
- **FR-013**: The toolbar, the main menu, context menus, the volume menu, dialogs, Settings, the quick view
  pane and the internal viewer MUST keep their fonts.
- **FR-014**: All new texts MUST be localized (English and Czech) and fit in their places in both languages.

### Key Entities

- **Font choice**: one per row (file list, main window) — "default", or a font family with its style (face) and a size in points.
  It is stored so that the same font is found again; the size is kept within the row's limits.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user changes the file list font to another family and size in under 30 seconds from opening
  Settings, and sees the panels change while choosing.
- **SC-002**: After "Restore Default Fonts", the panels and bars look identical to a fresh installation
  (same font, row height and bar heights).
- **SC-003**: With the largest sizes (file list 32 pt, main window 20 pt) in the narrowest panel, no panel widens,
  the divider does not move and every bar keeps at least its first item usable.
- **SC-004**: The chosen fonts are in effect after a restart in 100 % of launches; a removed font never
  prevents the app from starting or shows an error.
- **SC-005**: Moving the cursor in a list of 10,000 items is as smooth with a custom font as with the
  default.

## Assumptions

- The default sizes are those used today: 13 pt for the file list, 11 pt for the bars; parts drawn at
  another size today (the command line 12 pt, the function key names 11 pt and their key caps 10 pt, the
  column titles and the status line 11 pt) keep that distance from the chosen size.
- "Today's padding" of a row is the difference between the current row height (18 pt) and the line height
  of the 13 pt system font.
- The Fonts panel's color, underline and shadow options have no effect; only family, style and size are
  used.
- Text colors, the mark color and the bold option stay as they are in Settings → Appearance.

## Out of Scope

- Colors of the panels (a later spec).
- Fonts of the internal viewer (it has its own zoom), the toolbar, menus and dialogs (the classic
  commander's dialog font).
- Fonts per panel or per tab; line spacing; scaling the icons with the font.

## Deviations from the reference

- Two font settings (file list, main window) instead of the single panel font of the reference program, as
  in the classic commander; its dialog font is left out (macOS dialogs keep the system font).
- The standard macOS Fonts panel instead of a Windows font dialog, with the change shown while choosing.
- "Default" buttons and "Restore Default Fonts", which neither model has.
