# Feature Specification: Shortcut Conflict Checks

**Feature Branch**: `034-shortcut-conflicts`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Shortcut conflict checks in Settings → Keyboard: warn about or refuse keys that
are fixed in the app, typed as text in the panel, or taken by macOS, and make the conflict choice explicit."
Asked by the maintainer ("when we assign shortcuts, are there warnings that a key is already taken? It
probably depends on the context too"); agreed in chat on 2026-10-16 ("as you recommend": points A, B, C, D
and F of the proposal; point E later).

## Context

Settings → Keyboard lists every command per context (Panels, Viewer, Find, Compare) with a search field that
finds commands and keys. Selecting a command shows its shortcuts, each removable; "Add Shortcut" records the
next key press (Esc alone cancels); "Reset" and "Reset All…" restore the scheme's keys. When the recorded
key is already used by another command whose context overlaps (app-wide commands overlap every context), a
warning names that command and offers "Use Anyway" (the key moves to the selected command; the other command
keeps its other keys) and "Cancel". Two fixed captions under the table say that macOS may take some ⌃ and
function-key shortcuts and that ⌃← ⌃→ ⌃↑ ⌃↓ reach the app only when the Mission Control shortcuts are off.
The User Menu editor already warns when an item's shortcut is also a panel command's or another item's.

Not checked today:

1. Menu items with fixed keys that are not in the command list: Close Window ⌘W, Minimize ⌘M, Hide ⌘H,
   Undo ⌘Z, Redo ⇧⌘Z. Two menu items with the same key make it unclear which one runs.
2. Keys a context handles itself before any command: in the panel the movement keys (arrows, Page Up / Page
   Down, Home / End, alone or with ⇧) never reach a command.
3. Keys that type text in the panel. The recorder accepts a character without modifiers. With "Typing goes
   to the command line" on, a character bound to a command runs it and can no longer be typed into the
   command line, and ⌥ + character no longer starts quick search. With the setting off, quick search takes
   plain characters before any shortcut, so such a shortcut never runs.
4. macOS system shortcuts (Mission Control, Spotlight, screenshots, input sources and others): the app never
   receives them while they are on.
5. Global shortcuts of other apps (on the maintainer's Mac ⌘D, and a display utility taking ⌃⇧ and ⌃⌥
   chords). macOS does not reveal them; the only symptom is that recording sees nothing.
6. User Menu items' shortcuts are not considered in Settings → Keyboard, although in the panel a User Menu
   item's shortcut runs before a command with the same key.

The reference program's help documents no rule for this (its main shortcuts cannot be changed), so the
behavior follows usual Mac practice: show the conflict in words and let the user decide.

## Clarifications

### Session 2026-10-16

- Q: Which points of the proposal go into this spec? → A: Refusing fixed keys (A), warning about text keys
  (B), naming macOS shortcuts (C), the recording hint (D) and explicit conflict buttons (F). Showing how other
  contexts use the key (E) comes later.
- Q: A letter shortcut while typing goes to quick search (setting off)? → A: Refused, because it would
  never run; the message names the setting that makes letter keys usable.
- Q: A conflict with a User Menu item? → A: Reported; the key is not taken from the item (it belongs to the
  User Menu settings), and the warning says the item runs first in the panel.
- Q: Which fixed keys exist beyond the ones named? → A: Minimize All ⌥⌘M (added to the Window menu by
  macOS) and Log Out ⇧⌘Q (Apple menu) are refused too (plan, 2026-10-16).
- Q: Fixed keys of the Viewer, Find and Compare windows? → A: None: those windows look up their shortcuts
  first and use their own keys only as a fallback, so nothing is refused there (plan, 2026-10-16).
- Q: Mission Control F3 and Launchpad F4? → A: They are media keys of the function row, already covered by
  the F1–F12 (fn) note, so they are not in the macOS list (plan, 2026-10-16).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fixed keys are refused (Priority: P1)

The user tries to give a command a key that the app or macOS keeps for itself, and the app says so instead
of storing a shortcut that would never work or would clash with a fixed menu item.

**Why this priority**: Today such a key is stored silently and then does nothing or something else; this is
the most confusing outcome of assigning a shortcut.

**Independent Test**: In Settings → Keyboard, Panels, record ⌘W and ↓ for any command; neither is added and
a message explains why.

**Acceptance Scenarios**:

1. **Given** Settings → Keyboard shows Panels and a command is selected, **When** the user presses Add
   Shortcut and then ⌘W, **Then** no shortcut is added and the message "⌘W closes the window (Window menu)
   and cannot be assigned." appears under the editor.
2. **Given** the same, **When** the user records ↓ (or ⇧↓, Page Down, Home…), **Then** no shortcut is added
   and the message says that the key moves the cursor in the panel and cannot be assigned.
3. **Given** the same, **When** the user records ⌘Tab (if it reaches the app), **Then** the message says
   that ⌘Tab switches apps in macOS and cannot be assigned.
4. **Given** a refusal message is shown, **When** the user selects another command, records another key or
   changes the context, **Then** the message disappears.

---

### User Story 2 - Keys that type text in the panel (Priority: P1)

The user tries to give a panel command a plain letter (or digit, or punctuation) and learns what that costs:
the letter will run the command instead of being typed, or, when letters start quick search, the shortcut
would never run.

**Why this priority**: A plain letter shortcut silently breaks typing into the command line or does nothing
at all; users coming from other commanders try such keys.

**Independent Test**: Panels context; record "q" with "Typing goes to the command line" on and off.

**Acceptance Scenarios**:

1. **Given** "Typing goes to the command line" is on, **When** the user records "q" for a panel command,
   **Then** a warning says "Typing “q” in the panel will run this command instead of writing to the command
   line." with "Assign Anyway" and "Cancel"; Assign Anyway adds the shortcut.
2. **Given** the same setting is on, **When** the user records ⌥Q, **Then** the warning says that ⌥Q will run
   the command instead of starting quick search, with the same buttons.
3. **Given** the setting is off, **When** the user records "q" or ⇧Q, **Then** nothing is added and the
   message says "“q” starts quick search in the panel, so the shortcut would never run. Turn on Typing goes
   to the command line on the Panels tab to use letter keys."
4. **Given** any setting, **When** the user records Space, Return, Backspace, Tab or Esc without modifiers,
   **Then** no text-key warning appears (only the usual conflict check of story 4 applies).
5. **Given** the Viewer, Find or Compare context, **When** the user records a plain letter, **Then** no
   text-key warning appears.

---

### User Story 3 - macOS system shortcuts are named (Priority: P2)

The user records a key that macOS uses for a system feature, and the app names the feature and where to turn
it off; shortcuts already assigned that macOS takes are marked in the list.

**Why this priority**: It replaces two vague captions with specific information, but such keys are rarer
than the cases of stories 1, 2 and 4.

**Independent Test**: With the screenshot shortcuts on in macOS, record ⇧⌘4; in the default scheme look at a
command with ⌃↑ while Mission Control's ⌃↑ is on.

**Acceptance Scenarios**:

1. **Given** the macOS screenshot shortcut ⇧⌘4 is on, **When** the user records ⇧⌘4 (and the key reaches
   the app), **Then** a warning says "⇧⌘4 takes a screenshot in macOS (System Settings → Keyboard → Keyboard
   Shortcuts → Screenshots). The app does not receive it while it is on." with "Open Keyboard Settings",
   "Assign Anyway" and "Cancel".
2. **Given** the default key scheme and Mission Control's ⌃↑ is on, **When** the user views the Panels list,
   **Then** every command row with ⌃↑ shows a small warning mark whose tooltip names the macOS shortcut.
3. **Given** the user turned that macOS shortcut off in System Settings, **When** they come back to the app,
   **Then** the mark is gone without restarting the app.
4. **Given** the user changed a macOS shortcut to another key in System Settings, **When** they record the
   new key, **Then** the warning names that shortcut; the old key is no longer reported.
5. **Given** the two former captions about ⌃/function keys and Mission Control, **When** the user opens the
   Keyboard tab, **Then** they are gone; the note about F1–F12 and fn stays.

---

### User Story 4 - Explicit choice on a conflict (Priority: P1)

The user records a key that another command or a User Menu item already uses, sees who uses it and in which
context, and chooses with a button that says what will happen.

**Why this priority**: "Use Anyway" today does not say that the other command loses the key, and User Menu
items are not checked at all.

**Independent Test**: Panels, select Copy Files, record ⌘D.

**Acceptance Scenarios**:

1. **Given** Duplicate has ⌘D, **When** the user records ⌘D for Copy Files, **Then** the warning says "⌘D
   is used by Duplicate (Panels)." with "Move to This Command" and "Cancel"; Move to This Command gives ⌘D
   to Copy Files and Duplicate no longer shows ⌘D.
2. **Given** a User Menu item "Terminal" has ⌘1, **When** the user records ⌘1 for a panel command, **Then**
   the warning says "⌘1 is used by the User Menu item “Terminal”; in the panel the User Menu item runs
   first." with "Assign Anyway" and "Cancel"; the User Menu item keeps ⌘1.
3. **Given** the recorded key is both used by another command and taken by macOS (or a text key), **When**
   the warning appears, **Then** it lists every reason and offers one assign button ("Move to This Command"
   when another command loses the key, otherwise "Assign Anyway").
4. **Given** an app-wide command uses the key (for example ⌘, for Settings), **When** the user records it in
   any context, **Then** the conflict is reported with that command's context named "All windows".

---

### User Story 5 - Recording hint (Priority: P2)

While the app waits for a key, the user learns why nothing may happen.

**Why this priority**: Shortcuts taken by other apps cannot be detected; telling the user is the only help.

**Independent Test**: Press Add Shortcut and read the line under the editor.

**Acceptance Scenarios**:

1. **Given** the user pressed Add Shortcut, **When** the recorder waits, **Then** a line says "Press the
   shortcut; Esc cancels. If nothing happens, macOS or another app (for example a display or window
   utility) has taken that shortcut, and the app cannot receive it."
2. **Given** the hint is shown, **When** a key is recorded or recording is cancelled, **Then** the hint
   disappears.

---

### User Story 6 - Same checks in the User Menu editor (Priority: P3)

The User Menu shortcut field tells the user about fixed keys, text keys and macOS shortcuts too.

**Why this priority**: User Menu shortcuts are less common; the field already warns about conflicts.

**Independent Test**: Settings → User Menu, give an item ⌘W, then "q", then ⇧⌘4.

**Acceptance Scenarios**:

1. **Given** a User Menu item is edited, **When** its shortcut is a key refused in story 1, a text key of
   story 2 or a macOS shortcut of story 3, **Then** the same wording appears as a warning next to the
   existing warnings; the shortcut is kept (the User Menu editor never refuses, as today).

---

### Edge Cases

- macOS takes some system keys before the app sees them: nothing is recorded; story 5's hint explains it.
- The macOS shortcut settings are missing, unreadable or in an unknown format: the macOS defaults are used
  and no error is shown.
- A macOS shortcut without a key (unassigned) is ignored.
- The recorded key is one the selected command already has: nothing happens, as today.
- Classic Commander scheme defaults with ⌃⇧ chords get no mark: other apps' shortcuts are unknown.
- Layouts where a character needs ⌥ (for example "@"): the key is checked as recorded.
- An imported settings file or an existing shortcut that would now be refused is kept as it is; its row
  shows the warning mark when it cannot run (macOS takes it, or a letter while quick search takes letters);
  nothing is removed silently.
- "Typing goes to the command line" is switched later: existing letter shortcuts stay; the mark follows the
  current setting.
- Reset and Reset All are not affected by the checks.
- Search by key in the table finds marked keys as before.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Recording MUST refuse, with a message that names the reason, a key that is a fixed menu item
  outside the command list (Close Window ⌘W, Minimize ⌘M, Minimize All ⌥⌘M, Hide ⌘H, Undo ⌘Z, Redo ⇧⌘Z) in
  every context.
- **FR-002**: Recording MUST refuse keys macOS never passes to apps (⌘Tab, ⇧⌘Tab, ⌥⌘Esc, ⌃⌘Q, ⇧⌘Q) with a
  message naming what macOS does with them.
- **FR-003**: Recording MUST refuse, in the Panels context, the movement keys the panel handles itself
  (arrows, Page Up, Page Down, Home, End, alone or with ⇧); the Viewer, Find and Compare contexts have no
  such keys (clarification).
- **FR-004**: In the Panels context, a character key without modifiers or with ⇧ only MUST produce a warning
  with "Assign Anyway" when "Typing goes to the command line" is on, and MUST be refused with a message that
  names the setting when it is off. Space, Return, Backspace, Tab and Esc are not text keys.
- **FR-005**: In the Panels context with "Typing goes to the command line" on, ⌥ + character MUST produce a
  warning that it will no longer start quick search, with "Assign Anyway".
- **FR-006**: The app MUST know the macOS default system shortcuts (Mission Control ⌃↑, Application windows
  ⌃↓, moving between spaces ⌃← / ⌃→, Spotlight ⌘Space, Finder search window ⌥⌘Space, input sources ⌃Space /
  ⌃⌥Space, screenshots ⇧⌘3 / ⇧⌘4 / ⇧⌘5 / ⌃⇧⌘3 / ⌃⇧⌘4, Show Desktop F11, Dock hiding ⌥⌘D, next window ⌘`,
  Help menu search ⇧⌘/, keyboard navigation ⌃F1–⌃F8, accessibility controls ⌥⌘F5) and MUST apply the
  user's changes from the macOS keyboard shortcut settings (turned off, changed key), read only, never
  written.
- **FR-007**: Recording a key taken by a macOS shortcut that is on MUST produce a warning that names the
  system feature and its place in System Settings, with "Open Keyboard Settings", "Assign Anyway" and
  "Cancel".
- **FR-008**: The command table MUST mark every shortcut of the current context that cannot run (taken by a
  macOS shortcut that is on, or a text key while quick search takes letters), with a tooltip naming the
  reason.
- **FR-009**: The macOS shortcut information MUST be refreshed when the Keyboard tab appears and when the app
  becomes active.
- **FR-010**: The two fixed captions about macOS taking ⌃/function keys and about Mission Control MUST be
  removed; the F1–F12 (fn) note stays.
- **FR-011**: A conflict with other commands MUST name each command and its context (Panels, Viewer, Find,
  Compare, or "All windows" for app-wide commands) and MUST offer "Move to This Command" (the other commands
  lose the key and keep their other keys) and "Cancel".
- **FR-012**: In the Panels context a conflict with a User Menu item MUST be reported, naming the item and
  saying that it runs first in the panel; the button is "Assign Anyway" and the item keeps its key.
- **FR-013**: When several reasons apply, one warning MUST list all of them with a single assign button
  ("Move to This Command" if another command would lose the key, otherwise "Assign Anyway") and "Cancel";
  a refusal (FR-001 to FR-003, or FR-004 with the setting off) wins and only its message is shown.
- **FR-014**: While recording, a hint MUST explain that Esc cancels and that a key that does nothing has been
  taken by macOS or another app.
- **FR-015**: The User Menu shortcut field MUST show the reasons of FR-001 to FR-007 as warnings with the same
  wording, without refusing the key.
- **FR-016**: Existing shortcuts MUST never be removed or changed by the checks; refused or marked keys in
  imported settings stay as they are.
- **FR-017**: All new texts MUST be localized (English and Czech).

### Key Entities

- **Shortcut check result**: for a key in a context and for a command: refused (with one reason) or a list
  of warnings (other commands that would lose the key, User Menu items, a macOS shortcut, a text key), or
  clean.
- **System shortcut**: a macOS feature name, its place in System Settings, its key, and whether it is on.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: No shortcut that can never run (fixed menu key, panel movement key, letter while quick search
  takes letters) can be added in Settings → Keyboard.
- **SC-002**: Every warning names who or what uses the key in plain words; the user never has to search the
  list to find the other command.
- **SC-003**: After turning a macOS shortcut off in System Settings and returning, the warning mark is gone
  within one switch back to the app.
- **SC-004**: The assign button's title says what happens to the other command in 100 % of conflicts.

## Assumptions

- The macOS shortcut settings can be read by the app without any permission prompt; if not, the defaults are
  used.
- The list of macOS defaults matches current macOS versions; a shortcut missing from it is simply not named
  (the recording hint still applies).
- The Czech wording follows the app's existing Czech UI and System Settings' Czech names.

## Out of Scope

- Showing which other contexts use the key (point E, later).
- Detecting other apps' global shortcuts.
- Changing or turning off macOS shortcuts.
- A Swap button.
- Changing the keys of the fixed menu items (⌘W stays Close Window).
- Services menu shortcuts and App Shortcuts from System Settings.
- Changing how keys are dispatched in the panel: the text-key rule only describes and enforces today's
  behavior.

## Deviations from the reference

- The reference has no shortcut editor for its main commands; Mac practice is the model.
