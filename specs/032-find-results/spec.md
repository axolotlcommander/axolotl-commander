# Feature Specification: Find Results Like the Classic Commander

**Feature Branch**: `032-find-results`

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "Find results like the classic commander: go to the file on double click,
buttons under the results, and the Find window that steps aside after an action." Requested by a user
(with a screenshot of the classic commander's Find Files dialog); agreed with the maintainer in chat on
2026-10-15 ("as you propose", "I personally prefer the classic commander's behavior").

## Context

Find Files (⌃⌥F7, ⌘F) opens a separate window that does not block the main window; the results fill a
table (Name, Folder, Size, Modified) while the search runs. Today:

- double click and Return **open** the focused result in its default app;
- "Show in Panel" (⌘R, Space) moves the active panel to the result's folder with the cursor on it;
- "Show Results in Panel" (⌘⇧P) puts all results into the active panel as a flat listing, where copy, move
  and delete work and Back returns;
- F3 views the result (and walks through the found files), F4 edits it;
- none of these has a visible button, so users do not find them;
- every Find Files opens a new, empty window.

Usual behavior elsewhere: the classic two-panel commander on Windows has a modal Find Files dialog with the
buttons "F3 View", "F4 Edit", "New search", "Go to file" and "Feed to listbox" under the results. Double
click or Enter on a result goes to the file in the panel and the dialog goes away; opening Find again shows
the last search with its results; a separate command opens an independent Find window. The reference program
opens the result on Enter and focuses it in the panel with Space.

This feature follows the classic commander. The window stays non-modal (blocking the main window brings
nothing on macOS); the dialog "going away" is reproduced by hiding the window after an action and bringing it
back, with its results, the next time Find Files is chosen.

## Clarifications

### Session 2026-10-15

- Q: What does double click / Return on a result do? → A: Go to File, as in the classic commander; opening
  the file stays available as "Open".
- Q: Modal like the classic dialog? → A: No; the window is hidden after an action and brought back by Find
  Files, which gives the same workflow without blocking the main window.
- Q: Keep today's behavior available? → A: Yes, as a setting; the classic behavior is the default.
- Q: Search within the found files (the classic commander's F2 option)? → A: Not now (postponed).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Go to the file (Priority: P1)

A user searches for a file, sees it in the results and wants to work with it in the panel: copy it, look at
its neighbors. They double click it (or press Return) and are in the panel on that file.

**Why this priority**: It is what the user asked for; today the same gesture opens the file instead.

**Independent Test**: Search a test folder, focus a result in a subfolder, press Return: the active panel
shows that subfolder with the cursor on the result, and the panel has the keyboard focus.

**Acceptance Scenarios**:

1. **Given** a focused result, **When** the user double clicks it or presses Return or keypad Enter, **Then**
   the active panel of the main window shows the result's folder with the cursor on the result, the main
   window comes to the front and the panel (not the command line) has the keyboard focus.
2. **Given** a focused result, **When** the user presses Space or ⌘R, **Then** the same happens (Go to File).
3. **Given** a focused result, **When** the user chooses "Open" (⌘O, ⌘↓ or the context menu), **Then** the
   result opens as it does today (a file in its app, a folder in the panel).
4. **Given** a folder result, **When** the user goes to it, **Then** the panel shows the folder's parent with
   the cursor on the folder.
5. **Given** a result that has been deleted meanwhile, **When** the user goes to it, **Then** the panel shows
   its folder with the cursor on the first item and the app beeps; **When** the folder is gone too, **Then** a
   message says so and the panel does not change.

---

### User Story 2 - Buttons under the results (Priority: P1)

A user who does not know the keys sees, under the results, what they can do with them.

**Why this priority**: The commands exist but nobody finds them; the buttons make them visible.

**Independent Test**: With results shown, each button does what its key does; with no results they are
disabled; the texts fit in Czech at the smallest window size.

**Acceptance Scenarios**:

1. **Given** the Find window, **When** it is shown, **Then** a row of buttons under the results reads, in this
   order, "F3 View", "F4 Edit", "New Search", "Go to File" and "Results to Panel"; "Go to File" is drawn as
   the default button.
2. **Given** a focused result, **When** the user clicks a button, **Then** it does exactly what its command
   does from the keyboard on the focused result (View, Edit, New Search, Go to File, Results to Panel).
3. **Given** no results, **When** the window is shown, **Then** "F3 View", "F4 Edit", "Go to File" and
   "Results to Panel" are disabled; "F3 View" and "F4 Edit" are also disabled when the focused result cannot
   be viewed or edited (as their keys refuse it today, e.g. Edit on a folder).
4. **Given** a click on a button, **When** it has run, **Then** the keyboard focus stays where it was (the
   results or the form); the buttons never keep the focus.
5. **Given** the Czech interface, **When** the window is at its smallest size, **Then** all button texts are
   readable in full ("F3 Zobrazit", "F4 Upravit", "Nové hledání", "Přejít na soubor", "Výsledky do panelu").
6. **Given** the menus and Settings → Keyboard, **When** the user looks for the command that shows all results
   in the panel, **Then** it is named "Results to Panel" everywhere (Czech "Výsledky do panelu").

---

### User Story 3 - New search (Priority: P1)

A user found what they wanted and wants to search for something else in the same window.

**Why this priority**: Part of the classic button row; with the window kept and brought back (story 4) the user
needs a way to start over.

**Independent Test**: After a search, "New Search" empties the results and puts the cursor in the name field
with the previous text selected; the options stay.

**Acceptance Scenarios**:

1. **Given** results or a running search, **When** the user chooses "New Search" (the button, or its command in
   the Find window's menu with its key), **Then** a running search stops, the results and the status line are
   cleared, every field and option of the form stays as it was, and the name field has the focus with its text
   selected.

---

### User Story 4 - The Find window steps aside, with a setting (Priority: P1)

A user goes from a result to the panel, works there, and wants the results back later — as in the classic
commander, where Find Files shows the last search again.

**Why this priority**: Without it, Go to File leaves the Find window in the way and the next Find Files starts
empty.

**Independent Test**: With the default setting, Go to File hides the Find window; ⌃⌥F7 brings it back with the
same results, cursor and form. With "Keep the Find window open", the window stays and ⌃⌥F7 opens a new one.

**Acceptance Scenarios**:

1. **Given** Settings → General, **When** the user looks at it, **Then** it has "After going to a file:" with
   "Hide the Find window" (the default) and "Keep the Find window open".
2. **Given** "Hide the Find window", **When** the user runs Go to File or Results to Panel, or presses Esc while
   no search runs, **Then** the Find window disappears without losing anything: results, focused result,
   marked results, scroll position and form stay; a running search continues in the background.
3. **Given** a search running with "Hide the Find window", **When** the user presses Esc, **Then** the search
   stops (as today) and the window stays; a second Esc hides it.
4. **Given** a hidden Find window, **When** the user chooses Find Files (⌃⌥F7, ⌘F or the menu), **Then** that
   window comes back as it was left, with the progress of a search that is still running.
5. **Given** a Find window closed with its close button or ⌘W, **When** the user chooses Find Files, **Then** a
   new, empty window opens, prefilled from the active panel as today.
6. **Given** "Keep the Find window open", **When** the user runs Go to File or Results to Panel, **Then** the
   Find window stays open behind the main window, and Find Files opens a new window, as today; Esc closes the
   window as today.
7. **Given** a hidden Find window and another Find window that gets hidden later, **When** the second one is
   hidden, **Then** only the last one is kept and the earlier one is closed (its search stops).
8. **Given** a hidden Find window, **When** the app quits, **Then** nothing is kept for the next launch.

---

### User Story 5 - Find in a new window (Priority: P2)

A user wants two searches side by side, as the classic commander's command for a separate Find window allows.

**Why this priority**: Useful but rarer; with the default setting Find Files reuses the last window.

**Independent Test**: "Find Files in New Window" opens an empty window even when a hidden one exists; both keep
their results.

**Acceptance Scenarios**:

1. **Given** the File menu (next to Find Files), **When** the user chooses "Find Files in New Window", **Then**
   a new, empty Find window opens, prefilled from the active panel, whatever windows exist.
2. **Given** Settings → Keyboard, **When** the user looks for the command, **Then** it is there without a
   default key and can be given one.
3. **Given** two Find windows with "Hide the Find window", **When** both have been hidden, **Then** Find Files
   brings back the one hidden last.

---

### Edge Cases

- Go to File while the search still runs: the search continues (hidden with the default setting); the results
  keep arriving and are there when the window comes back.
- The active panel shows an archive, a server, a results listing or a branch view: Go to File leaves it and
  shows the result's real folder, as Show in Panel does today.
- The active panel's tab is locked to its folder (spec 028): Go to File follows the rule for leaving a locked
  folder, as Show in Panel does today.
- The main window was minimized: it comes back; with several main windows, the one Find was opened from (as
  today), or the frontmost one when that was closed.
- Results of a duplicate search: Go to File and Results to Panel work the same.
- Results to Panel when the panel already shows results: they are replaced; Back returns to the previous
  listing.
- The setting is changed to "Keep the Find window open" while a window is hidden: that window stays hidden and
  Find Files still brings it back once; then the new setting applies.
- Esc while a sheet of the Find window (folder chooser, message) is open: the sheet handles Esc; the window is
  not hidden.
- A hidden window whose search finds a problem (unreadable folders): nothing pops up; the note is shown when the
  window comes back.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Double click, Return and keypad Enter on a result MUST run Go to File: the active panel of the
  main window shows the result's folder with the cursor on the result, the main window comes to the front and
  the panel has the keyboard focus.
- **FR-002**: Space and ⌘R MUST keep running Go to File; "Open" (⌘O, ⌘↓, context menu) MUST keep opening the
  result as today.
- **FR-003**: Go to File on a folder result MUST show its parent with the cursor on the folder; on a missing
  result it MUST show the folder with the cursor on the first item and beep; when the folder is missing too it
  MUST show a message and leave the panel unchanged.
- **FR-004**: The Find window MUST show, under the results, the buttons "F3 View", "F4 Edit", "New Search",
  "Go to File" (default button) and "Results to Panel", each running the same command as its key on the focused
  result, disabled when that command is unavailable, never keeping the keyboard focus.
- **FR-005**: The command now called "Show Results in Panel" MUST be called "Results to Panel" in every menu and
  in Settings → Keyboard.
- **FR-006**: "New Search" MUST stop a running search, clear the results and the status line, keep the form, and
  put the focus in the name field with its text selected; it MUST be available as a button and as a command of
  the Find window with a key.
- **FR-007**: Settings → General MUST have "After going to a file:" with "Hide the Find window" (default) and
  "Keep the Find window open"; the choice MUST be remembered and included in the settings export and import.
- **FR-008**: With "Hide the Find window", Go to File, Results to Panel and Esc (when no search runs) MUST hide
  the Find window, keeping its results, focused and marked results, scroll position, form and a running search.
- **FR-009**: With a hidden Find window, Find Files MUST bring it back as it was left; otherwise it MUST open a
  new window as today. At most one hidden window MUST be kept (the last hidden); hiding another MUST close the
  earlier one. Nothing MUST be kept across launches.
- **FR-010**: With "Keep the Find window open", the actions and Esc MUST behave as today.
- **FR-011**: "Find Files in New Window" MUST open a new, empty Find window prefilled from the active panel; it
  MUST be in the File menu next to Find Files, without a default key, assignable in Settings → Keyboard.
- **FR-012**: All new texts MUST be localized (English and Czech) and fit in both languages at the Find window's
  smallest size.

### Key Entities

- **Find window behavior setting**: "hide" (default) or "keep open".
- **Remembered Find window**: the last hidden Find window, with its form, results, cursor, marks, scroll position
  and possibly running search; at most one; not kept across launches.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a focused result, the user is on that file in the panel with one key press or one double
  click.
- **SC-002**: After Go to File, Find Files shows the same results again in 100 % of cases with the default
  setting (until the window is closed or replaced), without searching again.
- **SC-003**: Every action on results that has a key also has a visible button under the results (View, Edit,
  New Search, Go to File, Results to Panel).
- **SC-004**: With "Keep the Find window open", the Find window behaves exactly as in version 0.7.
- **SC-005**: No button text is cut off in English or Czech at the smallest window size.

## Assumptions

- "The active panel" is the main window's active panel at the moment of the action, as Show in Panel uses today.
- The existing keys of the Find window stay; only Return, keypad Enter and double click change meaning.
- The key for New Search is chosen in planning among keys free in the Find window (⌘N is preferred if free).
- The Find window's smallest size stays as today unless the button row needs more room.

## Out of Scope

- Searching within the found files (the classic commander's F2 option); postponed.
- A modal Find window; searching inside archives; changes to the search form or the search itself; named saved
  searches.

## Deviations from the reference

- The Find window stays non-modal; hiding it after an action and bringing it back with Find Files replaces the
  classic dialog that closes and keeps its last results.
- The classic behavior is the default of a setting; today's behavior remains available.
- "Find Files in New Window" replaces the classic commander's command for a Find window in a separate process.
- The results keep their columns (Name, Folder, Size, Modified) instead of a plain list of paths.
- The reference program opens the result on Enter; this follows the classic commander instead.
