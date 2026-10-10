# Feature Specification: File Sizes Like Finder

**Feature Branch**: `008-finder-size-format`

**Created**: 2026-10-10

**Status**: Draft

**Input**: User description: "File sizes shown like Finder in the panels (setting): the Size column can show
rounded sizes the way Finder does ("453 kB", "4,1 MB", "402 bajtů") instead of exact bytes; a setting
chooses between the two, and a second setting chooses units of 1000 or 1024."

## Context

Today the Size column of the panels shows exact byte counts with grouping ("4 300 000"). Since
release 0.2.2 a Size column too narrow for the value shows the rounded size ("4,3 MB"), then an
ellipsis, with the full value in the tooltip. The maintainer wants the column to read like the
macOS Finder. Their reference screenshot of Finder shows "453 kB", "4,1 MB", "8,6 MB", "44,1 MB",
"5 kB" and "402 bajtů".

Reference behavior:
- Tandem Commander and Open Salamander show exact bytes in the Size column.
- Total Commander lets the user choose how sizes are shown.
- macOS users expect the Finder's style.

This feature keeps exact bytes available and makes the Finder style the default.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sizes read like Finder (Priority: P1)

A user browses a folder and reads file sizes at a glance in familiar units ("4,1 MB", "453 kB",
"402 bytes") instead of counting digit groups. When they need the exact number, it is in the
tooltip of the cell and in the status bar line for the item under the cursor.

**Why this priority**: it is the reason for the feature. Most of the time a rounded size is what
the user wants to know.

**Independent Test**: open a test folder with files of known sizes. The Size column shows the
rounded sizes as Finder formats them. The status bar for the item under the cursor, and the
tooltip of its Size cell, show the exact bytes.

**Acceptance Scenarios**:

1. **Given** default settings and a folder with files of 402, 5 000, 453 000, 4 100 000 and
   44 100 000 bytes, **When** the folder is shown, **Then** the Size column reads "402 bytes",
   "5 kB", "453 kB", "4,1 MB" and "44,1 MB" (in Czech "402 bajtů", decimal comma, per the system
   locale), right-aligned.
2. **Given** the cursor on the 4 100 000-byte file, **When** the user reads the status bar,
   **Then** it shows the exact size with grouping ("4 100 000"). **And When** the mouse rests on
   the Size cell, **Then** the tooltip shows the same exact size.
3. **Given** a folder whose size was calculated with Space, **When** the panel shows it, **Then**
   its Size cell shows the rounded size in the same style instead of "<DIR>".
4. **Given** the panel sorted by size, **When** sizes are shown rounded, **Then** the order is
   still by exact bytes. For example, 4 100 000 sorts before 4 140 000 even though both may read
   "4,1 MB".
5. **Given** the Size column made narrow, **When** a rounded size does not fit, **Then** the cell
   shows an ellipsis, never a cut number, and the tooltip shows the exact size.

---

### User Story 2 - Choose exact bytes instead (Priority: P1)

A user who works with exact sizes (comparing files, checking transfers) switches the panels back to
exact bytes in Settings.

**Why this priority**: the old behavior must stay available. Exact bytes are the reference
commander's behavior and what some users rely on.

**Independent Test**: in Settings → Appearance, switch "Size in panels" to "In bytes". Both panels
and all their tabs show exact bytes at once, without reloading.

**Acceptance Scenarios**:

1. **Given** "Like Finder" in both panels, **When** the user chooses "In bytes", **Then** every
   open panel and tab shows "4 100 000" immediately, without re-reading the folder.
2. **Given** "In bytes" and a narrow Size column, **When** the exact size does not fit, **Then**
   the cell falls back to the rounded size, then to an ellipsis, as in release 0.2.2.
3. **Given** "In bytes", **When** the app is quit and started again, **Then** the panels still
   show exact bytes.

---

### User Story 3 - Units of 1000 or 1024 (Priority: P1)

A user who thinks in binary units (as Windows and Total Commander show them) chooses 1024 in
Settings. Every rounded size in the app then uses 1024-byte units.

**Why this priority**: the maintainer asked for the choice explicitly. With the wrong base, sizes
in the app do not match what the user compares them with.

**Independent Test**: in Settings → Appearance, switch "Units" to 1024. A 4 300 000-byte file
reads "4,1 MB" instead of "4,3 MB", in the Size column and in the status bar totals.

**Acceptance Scenarios**:

1. **Given** the default units (1000), **When** a file of 4 300 000 bytes is shown, **Then** it
   reads "4,3 MB". **And Given** units of 1024, **Then** the same file reads "4,1 MB".
2. **Given** units of 1024, **When** the user marks files, **Then** the status bar total ("Selected
   3 files, 0 folders — …") uses 1024-byte units.
3. **Given** units of 1024, **When** the user looks at the free space in the volume bar, the
   volume information, an operation's progress, or the Find, Compare and Disk Usage windows,
   **Then** their rounded sizes use 1024-byte units too, once the value is next shown.
4. **Given** either base, **When** a size is shown exactly (with grouping), **Then** it is
   unaffected by the units setting.

---

### Edge Cases

- **Small and exact values:** 0, 1, 999, 1 000, 1 023 and 1 024 bytes are shown as the system's
  file-size formatting shows them in each base. For example, 0 is "Zero kB" in English and "0 kB"
  in Czech, 1 is "1 byte" or "1 bajt", and 999 is "1 kB" with 1000 but "999 bytes" with 1024.
- **Large values:** files over 1 TB show TB in both modes, and nothing overflows or truncates at
  the default column width.
- **Marked rows:** marked (bold) rows use the same format, and the default column width fits the
  widest default-format value in bold.
- **Items without a size:** "<DIR>", the package dash "—" and the empty Size cells of ".." and of
  servers in the Network folder stay unchanged.
- **Other listings:** FTP/SFTP listings, archive contents and search results listed in the panel
  follow the same settings as local folders.
- **Locale:** the system locale decides the language and the decimal separator, as for other
  formatting in the app.
- **Width:** a narrow column follows FR-005 in both modes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Settings → Appearance MUST offer "Size in panels:" with two choices, "Like Finder
  (kB, MB, GB)" and "In bytes". The default is "Like Finder", both for new installations and for
  existing ones that never set it.
- **FR-002**: With "Like Finder", the Size column MUST show each file size, and each calculated
  folder size, as the system formats file sizes for the current locale. This is the same style as
  the Finder, in the chosen units base.
- **FR-003**: With "In bytes", the Size column MUST show exact byte counts with grouping, as today.
- **FR-004**: In both modes, the exact byte count MUST be available:
  - in the tooltip of every Size cell that shows a rounded value or an ellipsis;
  - in the status bar line for the item under the cursor.
- **FR-005**: A value that does not fit the column width MUST never be shown cut:
  - in "In bytes" mode the cell falls back to the rounded size, then to an ellipsis;
  - in "Like Finder" mode it falls back to an ellipsis.
- **FR-006**: Changing "Size in panels" MUST update every open panel and tab immediately, without
  re-reading folders. The setting MUST persist across launches.
- **FR-007**: Settings → Appearance MUST offer "Units:" with two choices, "1000 (like Finder)" and
  "1024 (like Windows)". The default is 1000.
- **FR-008**: The units setting MUST apply to every rounded size the app shows:
  - the Size column (both modes);
  - panel status bar totals;
  - free space in the volume bar and volume information;
  - operation progress and dialogs;
  - the Find, Compare and Disk Usage windows;
  - file properties.
  Exact byte counts MUST NOT change.
- **FR-009**: Units of 1024 MUST use the system's binary counting with the labels the system writes
  for it (on current macOS the same "kB", "MB", "GB" as for 1000), not IEC labels ("KiB").
- **FR-010**: Changing "Units" MUST update the open panels immediately and persist across launches.
  Other open windows show the new base the next time they show a value; open dialogs need not be
  rebuilt.
- **FR-011**: Sorting by size MUST stay by exact bytes in every mode and base.
- **FR-012**: The initial width of the Size column MUST fit the widest value of the selected mode
  in bold, as today for exact bytes.
- **FR-013**: The new setting labels MUST be localized in English and Czech.

### Key Entities

- **Size display mode**: "Like Finder" or "In bytes", applied to all panels.
- **Units base**: 1000 or 1024, applied to every rounded size in the app.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With default settings, the Size column shows exactly the system's file-size text (the
  Finder's style) for a test folder containing files of 0, 1, 402, 999, 1 000, 1 023, 1 024, 4 300 000, 46 000 000 and
  1 200 000 000 000 bytes, in both English and Czech.
- **SC-002**: Switching either setting updates both panels within one second, with no folder
  reload and with the cursor, selection and scroll position kept.
- **SC-003**: For every Size cell that shows a rounded value or an ellipsis, the exact byte count
  can be read in at most one step: the tooltip, or the status bar after moving the cursor there.
- **SC-004**: No Size cell ever shows a number cut in the middle, at any column width, in either
  mode.

## Assumptions

- **Default for existing users:** the maintainer chose "Like Finder" as the default, so existing
  installations change from exact bytes to Finder style on update. The CHANGELOG states this.
- **"Like Finder":** means the system's file-size formatting, which is what Finder uses. Where the
  system's output differs from a particular Finder screen, the system formatter is the reference.
- **Units setting:** it is a single app-wide setting, not per panel or per tab.
- **Brief view:** it has no Size column and is unaffected.

## Out of Scope

- Per-panel or per-tab settings.
- Other formats: short Unix style ("4.1M"), a fixed unit, a chosen number of decimals.
- The Date column format.
- The formatting of exact byte counts.
- The Brief view.
