# Feature Specification: Quick Filter

**Feature Branch**: `013-quick-filter`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "Quick filter: typed text narrows the panel list as you type; the last
filter can be brought back; Esc shows everything again; switching from quick search to the filter."

## Context

Today a panel can:
- jump to a name by typing (quick search);
- hide names with a mask, through View → Filter… (⌃F12, a dialog).

Classic two-panel file managers also have a **quick filter**. Typed text narrows the list live, so a
long folder shrinks to the few matching items, and the user moves among them with the arrows. The scope
was agreed in chat on 2026-10-12 (the list of specs 010–016): a quick filter key, bringing back the
last filter, Esc to show everything, and switching between quick search and the filter. The classic
key ⌃S means Paste as Symbolic Link in this app, so it goes into the Classic Commander scheme. This
spec ships with specs 010–016 in one release.

## Clarifications

### Session 2026-10-13

All answers below were *decided while the maintainer was away; to review*.

- Q: How does typed text match? → A: Text without wildcards matches names that contain it, ignoring
  case as the folder's name rules do. Text with `*`, `?`, `;` or `|` is a mask with the same syntax as
  Filter…, e.g. `*.txt`.
- Q: Are folders filtered too? → A: Yes. Folders that do not match are hidden as well; ".." always stays.
  (Filter… keeps folders, because it filters file types; the quick filter is for finding.)
- Q: How long does the filter last? → A: It belongs to the folder. Opening another folder, going
  back, switching tabs or restoring a tab clears it. Refreshing keeps it.
- Q: Keys? → A:
  - Quick Filter: ⌥⌘F;
  - Quick Filter with Last Text: ⌃⇧S and ⌥⌘⇧F;
  - Classic Commander adds ⌃S to Quick Filter; Paste as Symbolic Link keeps ⌃⌘V.
  ⌃F10 keeps Compare Panels; Esc clears the filter.
- Q: Can marked items hidden by the filter be copied or deleted? → A: No. Commands work on the marked
  items that are visible. The marks come back into view when the filter is cleared.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Narrow the list by typing (Priority: P1)

A user in a folder with hundreds of files presses ⌥⌘F (or ⌃S in Classic Commander) and types `invoice`.
The list shrinks to the items whose names contain "invoice". The status line shows the filter. The user
moves with the arrows among the matches, marks two with Space or Insert, and copies them with F5. Esc
brings back the full list.

**Why this priority**: it is the core of the feature and the most visible gain for large folders.

**Independent Test**: on a test folder, start the quick filter, type, move, mark and clear it; check the
list, the status line and that only visible marked items are offered to a command (by its dialog, which
is then cancelled).

**Acceptance Scenarios**:

1. **Given** a folder with `a.txt`, `b.txt`, `notes.md` and the folder `docs`, **When** the user starts the
   quick filter and types `tx`, **Then** only "..", `a.txt` and `b.txt` are shown, and the status line
   shows the filter text.
2. **Given** the quick filter is being typed, **When** the user types a character that would leave no
   item, **Then** the character is refused with a beep and the list stays.
3. **Given** the quick filter is being typed, **When** the user presses Backspace, **Then** the last
   character is removed and the list widens; with the text empty, every item is shown again.
4. **Given** the quick filter is being typed, **When** the user presses ↑, ↓, Page Up/Down, Home or End,
   **Then** the cursor moves among the shown items and typing continues.
5. **Given** the quick filter is being typed, **When** the user presses Esc, **Then** the filter is
   cleared and every item is shown.
6. **Given** the quick filter `*.md` is typed, **When** the list updates, **Then** only "..", `notes.md`
   and matching folders are shown (a mask).
7. **Given** a filter is active and typing has ended (another key was pressed), **When** the user presses
   Esc, **Then** the filter is cleared.
8. **Given** a filter is active, **When** the user opens a folder, **Then** the new folder shows every
   item.

---

### User Story 2 - Bring the last filter back (Priority: P2)

A user filtered a folder by `.log`, went elsewhere, and comes back. ⌃⇧S (or ⌥⌘⇧F) applies `.log` again
and lets them continue typing.

**Why this priority**: it saves retyping, but it is a convenience on top of US1.

**Independent Test**: filter, clear by leaving the folder, come back, use Quick Filter with Last Text.

**Acceptance Scenarios**:

1. **Given** the user typed the filter `log` earlier in this panel, **When** they run Quick Filter with
   Last Text, **Then** the filter `log` is applied and typing continues after it.
2. **Given** no filter was typed yet in this panel, **When** they run it, **Then** an empty quick filter
   starts.

---

### User Story 3 - From quick search to the filter (Priority: P2)

A user starts quick search by typing `rep`, sees there are many matches, and presses ⌥⌘F. The search
text becomes the filter, and only the matching items are listed.

**Why this priority**: it joins the two ways of finding without retyping.

**Independent Test**: start quick search, run Quick Filter, and check the list and the status line.

**Acceptance Scenarios**:

1. **Given** quick search with the text `rep` is running, **When** the user runs Quick Filter, **Then**
   quick search ends and the quick filter starts with `rep`.
2. **Given** a filter is active and typing has ended, **When** the user runs Quick Filter, **Then** typing
   continues with the current filter text.

---

### Edge Cases

- **Mask filter at the same time**: the quick filter applies on top of Filter… (⌃F12); both must match.
- **Find results and branch view**: the filter matches the shown file name (without its folder), as
  quick search does there.
- **Sizes and totals**: the status totals count the shown items.
- **Marked items hidden by the filter**: they stay marked but are not part of any command until they are
  shown again.
- **"Typing goes to the command line" (spec 011)**: while the quick filter is being typed, characters go
  to the filter, not the command line.
- **The folder changes on disk** while a filter is active: the refreshed list is filtered the same way.
- **Space** while typing the filter: it is part of the filter text (names with spaces), as in quick
  search.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST offer "Quick Filter" for a panel. It starts typing a filter that narrows the
  list after every keystroke.
- **FR-002**: Filter text without `*`, `?`, `;` or `|` MUST match the names that contain it, compared
  the way the folder compares names (case). Text with one of those characters MUST be a mask with the
  syntax of Filter….
- **FR-003**: The filter MUST hide non-matching files and folders. ".." MUST stay.
- **FR-004**: While typing:
  - a character without ⌘, ⌃ or ⌥ (and Space) MUST extend the text, unless no item would match; then it
    MUST be refused with a beep;
  - Backspace MUST remove the last character;
  - Esc MUST clear the filter and end typing;
  - ↑, ↓, Page Up/Down, Home and End MUST move the cursor and keep typing;
  - any other key MUST end typing, keep the filter and do what it does today.
- **FR-005**: With a filter active and typing ended, Esc MUST clear the filter.
- **FR-006**: The status line MUST show the filter text while a filter is active.
- **FR-007**: Opening another folder, going back or forward, and switching or restoring a tab MUST clear
  the filter. A refresh MUST keep it.
- **FR-008**: Commands MUST work only on visible items. Marked items hidden by the filter MUST NOT be
  copied, moved, deleted or otherwise processed.
- **FR-009**: Each panel MUST remember the last non-empty filter text, in memory. "Quick Filter with
  Last Text" MUST start the quick filter with it, or empty when there is none.
- **FR-010**: Running Quick Filter while quick search runs MUST turn the search text into the filter.
  Running it with a filter active MUST resume typing.
- **FR-011**: Factory chords and menu (View menu, after Filter…):
  - Quick Filter: ⌥⌘F;
  - Quick Filter with Last Text: ⌃⇧S, ⌥⌘⇧F.
  Classic Commander MUST add ⌃S in front of Quick Filter's chords and remove it from Paste as Symbolic
  Link, which keeps ⌃⌘V.
- **FR-012**: No chord MUST be bound twice in the panel context in either scheme.

### Key Entities

- **Quick filter**: the text, whether it is being typed, and the panel's last filter text. It belongs to
  the panel's current folder and lives in memory.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a folder of 1 000 items, the list narrows visibly at once after each keystroke.
- **SC-002**: A user can get from a full folder to a single matching item with one chord and a few
  characters.
- **SC-003**: No command ever acts on an item hidden by the filter (checked automatically on the
  model).
- **SC-004**: The matching rules (substring, mask, folders, "..", branch view names) have automated
  tests.

## Assumptions

- The filter text is not saved in the tab or the settings; it is session state of a folder.
- The quick filter does not change the sort or the mask filter.

## Out of Scope

- Saved filters and filter history beyond the last text.
- Filtering by content, size or date.
- A visible filter field in the panel; the status line shows the text.

## Deviations from the classic reference

- The factory chord is ⌥⌘F; ⌃S only in Classic Commander.
- ⌃F10 keeps Compare Panels; Esc clears the filter.
