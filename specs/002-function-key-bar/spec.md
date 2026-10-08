# Feature Specification: Function Key Bar and Hideable Command Line

**Feature Branch**: `002-function-key-bar`

**Created**: 2026-10-08

**Status**: Draft

**Input**: User description: "Function key bar and hideable command line for the main window. Users
coming from Windows two-panel file managers (Tandem Commander, Total Commander, Salamander) expect a
row of function key buttons at the bottom of the window. Classic Windows behavior is the default;
deviations only where macOS forces them, and each deviation is listed in the spec."

## Clarifications

### Session 2026-10-08

- Q: Should the function key buttons show icons? → A: No. The maintainer reviewed the first
  build and decided that the buttons show only the key number and the command name (e.g. "F5
  Copy", "F3 View"), as in Tandem Commander; no icons. This replaces the earlier wording "icon,
  key number and short label" (FR-004, FR-011, FR-012, D-003, SC-007 updated). The toolbar at the
  top keeps its icons; it is not part of this spec.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Function key buttons at the bottom of the window (Priority: P1)

A user who comes from Tandem Commander or Total Commander sees, at the bottom of the main window
below the command line, a row of twelve buttons F1–F12. Each button shows the key number
and the name of the command that the key runs, e.g. "F5 Copy", "F7 New Folder", "F8 Move to
Trash". Clicking a button does exactly what pressing the key does, for the active panel. The bar
is shown by default.

**Why this priority**: This is the feature itself. It tells newcomers what the function keys do
without opening a menu, and it lets mouse users and users of keyboards where function keys need
`fn` run the main commands with one click.

**Independent Test**: Launch the test copy of the app with default settings, point both panels
to a test folder, click "F7 New Folder", type a name and confirm; the folder appears in the
active panel. Click "F5 Copy" with a file under the cursor; the copy dialog for the active panel
opens. Neither click moves keyboard focus away from the panel.

**Acceptance Scenarios**:

1. **Given** a fresh installation, **When** the main window opens, **Then** the function key bar
   is visible at the bottom, below the command line, with buttons F1–F12 in this order.
2. **Given** the default key map, **When** the user looks at the bar, **Then** each button shows
   the command bound to the plain key (F1 Help, F2 Rename, F3 View, F4 Edit, F5 Copy, F6 Move,
   F7 New Folder, F8 Move to Trash, F9 User Menu, F12 Disconnect); positions without a command (F10, F11 in the default map) are empty.
3. **Given** the cursor on a file in the left panel and the left panel active, **When** the user
   clicks "F3 View", **Then** the file opens in the viewer, exactly as with the F3 key, and after
   closing the viewer the left panel still has keyboard focus with the cursor on the same file.
4. **Given** the user remapped F2 to "Compare Panels" in Settings → Keyboard, **When** the
   settings change is applied, **Then** the F2 button immediately shows "Compare Panels" without restarting the app, and clicking it compares the panels.
5. **Given** the cursor on the ".." row, **When** the user looks at the bar, **Then** commands
   that are unavailable there (e.g. F3 View, F4 Edit, F2 Rename) are grayed out and do nothing
   when clicked, following the same rules as the corresponding menu items.
6. **Given** the window is made narrow, **When** the buttons no longer fit with full names,
   **Then** the names are shortened, and at the smallest width only the key number
   remains; hovering a button shows the full command name and its shortcut in a tooltip; text
   never wraps to a second line.
7. **Given** dark mode is switched on or off, **When** the bar is visible, **Then** the text
   follows the system appearance like the rest of the window.

---

### User Story 2 - The bar follows the held modifier keys (Priority: P1)

While the user holds ⇧, ⌃, ⌥ or ⌘ (alone or combined), the bar immediately shows the commands
bound to that modifier plus each function key, as Total Commander and Tandem Commander do. For
example, holding ⌥ shows "F5 Pack" and "F6 Unpack", holding ⇧ shows "F4 New File", "F7 Go to
Folder" and "F8 Delete Immediately", holding ⌃ shows the sort commands on F3–F6. Releasing the
modifier restores the plain set. Clicking while the modifier is held runs that variant.

**Why this priority**: Without it the bar would only show a third of the function key commands;
discovering the modifier variants is one of the main reasons the bar exists in the reference
programs.

**Independent Test**: In the test copy of the app, hold ⌥ and check that F5 reads "Pack" and F6
"Unpack"; while still holding ⌥, click F5 with a file under the cursor and check that the pack
dialog opens; release ⌥ and check that F5 reads "Copy" again.

**Acceptance Scenarios**:

1. **Given** the main window is active, **When** the user presses and holds ⇧, **Then** within
   a moment that is not perceptible as a delay every button shows the command bound to ⇧ + its
   key (F3 Show in Finder, F4 New File, F7 Go to Folder, F8 Delete Immediately, F9 Hot Paths,
   F10 Show Context Menu in the default map), and positions without a ⇧ binding are empty.
2. **Given** the user holds ⌃⇧, **When** the bar updates, **Then** it shows the commands bound
   to exactly ⌃⇧ + key (e.g. F3 View With…, F4 Edit With…, F5 Remember Selection), not the ⌃ or
   ⇧ variants.
3. **Given** the user holds ⌥, **When** they click the F5 button, **Then** "Pack…" runs for the
   active panel, as if ⌥F5 had been pressed.
4. **Given** the user releases all modifiers, **When** the bar updates, **Then** the plain set is
   shown again.
5. **Given** a position is empty for the held modifiers, **When** the user clicks it, **Then**
   nothing happens.
6. **Given** the user holds a modifier and switches to another app (⌘Tab) and back, **When** the
   main window is active again with no modifier held, **Then** the bar shows the plain set (it
   never stays stuck on a modifier set).

---

### User Story 3 - Hide or show the function key bar and the command line (Priority: P2)

A user who does not want the bar, or who never uses the command line, hides either of them to
gain room for the panels. Both are visible by default. Each can be toggled from the View menu
(and so from a keyboard shortcut the user assigns), from Settings, and the bar also from its own
right-click menu. The choice is remembered across launches.

**Why this priority**: Experienced users and users on small screens want the space back; the
bar must not be forced on anyone. It is secondary to having the bar at all.

**Independent Test**: Choose View → "Show Function Key Bar" to hide the bar, quit and relaunch
the test copy; the bar stays hidden and the panels use the freed space. Repeat with "Show Command
Line".

**Acceptance Scenarios**:

1. **Given** a fresh installation, **When** the main window opens, **Then** both the command line
   and the function key bar are visible, and View shows both "Show Command Line" and "Show
   Function Key Bar" checked.
2. **Given** the bar is visible, **When** the user chooses View → "Show Function Key Bar",
   **Then** the bar disappears, the panels grow into its space, and the menu item is unchecked;
   choosing it again shows the bar.
3. **Given** the bar is visible, **When** the user right-clicks the bar and chooses "Hide
   Function Key Bar", **Then** the bar is hidden as in scenario 2.
4. **Given** the user hid the command line, **When** they use a command that works with the
   command line (e.g. "Command Line" ⌃Tab, or a command that inserts a file name into it),
   **Then** the command line is shown again and receives the input, so no such command silently
   fails; the setting is then "shown".
5. **Given** the user changed either setting in Settings, **When** they look at the View menu,
   **Then** it shows the same state, and vice versa.
6. **Given** the user hid either element, **When** they quit and launch the app again, **Then**
   it stays hidden.
7. **Given** the user assigns a shortcut to "Show Function Key Bar" in Settings → Keyboard,
   **When** they press it, **Then** the bar toggles.

---

### User Story 4 - Help when function keys need `fn` (Priority: P3)

On Apple keyboards, F1–F12 control brightness, volume and media unless the system setting "Use
F1, F2, etc. keys as standard function keys" is on; then the user has to hold `fn` for every
function key command. The app cannot change or intercept this (it is a system-wide setting and
the system handles these keys before any app sees them), and it must not change it. Instead it
tells the user where to switch it and takes them there.

**Why this priority**: Users coming from Windows expect F5 to copy; without a hint they may
think the app is broken. The bar itself (stories 1–2) already makes the commands reachable, so
this is a helpful addition, not a blocker.

**Independent Test**: With the system setting off, launch the test copy for the first time; a
notice explains the situation with "Open Keyboard Settings" and "Don't Show Again". Settings →
Keyboard shows the current state and the same button. Clicking the button opens the keyboard
section of System Settings; the app never changes the setting itself.

**Acceptance Scenarios**:

1. **Given** the system setting is off and the notice has never been shown, **When** the app is
   launched, **Then** after the main window appears a single notice explains that function keys
   currently need `fn` (or the system setting), with buttons "Open Keyboard Settings", "Don't
   Show Again" and a way to close it.
2. **Given** the notice was dismissed with "Don't Show Again", **When** the app is launched
   again, **Then** no notice is shown. Closing the notice without that choice shows it at most
   once more on a later launch, never on every launch.
3. **Given** the system setting is on, **When** the app is launched, **Then** no notice is shown.
4. **Given** any state, **When** the user opens Settings → Keyboard, **Then** a line states
   whether function keys currently act as standard function keys, and a button "Open Keyboard
   Settings" opens the keyboard section of System Settings.
5. **Given** the user switched the system setting while the app is running, **When** they open
   Settings → Keyboard again (or return to it), **Then** the line shows the new state.
6. **Given** any state, **When** the notice or the Settings line is used, **Then** the app never
   writes or changes the system setting.

### Edge Cases

- A command is bound to several function key chords (e.g. Pack on ⌥F5 and ⌃⌥F5): it appears at
  every position/modifier combination it is bound to.
- A function key chord bound to a command that is not usable in the main window (e.g. a
  viewer-only command) is not shown in the bar; the position is empty.
- A command that exists in the menu but has no implementation yet (e.g. "Working Directories…"
  on ⌥F12) is shown grayed out, like its menu item.
- Some modifier combinations are taken by macOS or by other software (e.g. a display manager
  that grabs ⌃⇧ or ⌃⌥ shortcuts) and never reach the app: the bar simply shows what the app's key
  map says for the modifiers the app sees; it does not try to detect such conflicts.
- Clicking a button while the command line or another control of the main window has keyboard
  focus runs the command for the active panel, as the menu item would; focus stays where it was.
- Clicking a button while a sheet or dialog of the main window is open does nothing (the window
  is blocked as for the menu).
- Only one modifier set is shown at a time; holding modifiers while the window is inactive does
  not change the bar.
- Very long command names (e.g. "Apply Remembered Selection") are shortened in the button and
  shown in full in the tooltip.
- The panels are maximized (⌃F11) or one panel is hidden: the bar keeps its full width and keeps
  working for the active panel.
- The user's language is Czech: button names use the localized command names, the same as in
  the menus.
- Full-screen mode and window resizing: the bar stays attached to the bottom edge and never
  overlaps the panels or the command line.

## Requirements *(mandatory)*

### Functional Requirements

**Function key bar**

- **FR-001**: The main window MUST show a function key bar along its bottom edge, below the
  command line, with twelve buttons for F1–F12 in order, sharing the width equally.
- **FR-002**: The bar MUST be visible by default (fresh installation, no saved setting).
- **FR-003**: Each button MUST show the key number and the localized name of the command bound
  to that key for the currently held modifiers, taken from the current key map (default bindings
  plus the user's remapping). The bar MUST NOT contain hard-coded command names.
- **FR-004**: Buttons MUST show text only (key number and command name), no icons
  (Clarification 2026-10-08).
- **FR-005**: Changing the key map in Settings → Keyboard MUST update the bar immediately,
  without restarting the app or reopening the window.
- **FR-006**: Clicking a button MUST run the command exactly as the corresponding key press
  would, for the active panel, including the dialogs and confirmations that command shows.
- **FR-007**: Buttons MUST NOT take keyboard focus; after a click, focus and the panel cursor are
  where they were before (unless the command itself moves them).
- **FR-008**: A button whose command is unavailable in the current state MUST be shown grayed
  out and MUST do nothing when clicked; availability MUST follow the same rules as the command's
  menu item.
- **FR-009**: A position with no command for the current modifier combination, or with a command
  that is not usable in the main window, MUST be shown empty and MUST do nothing when clicked.
- **FR-010**: Every non-empty button MUST show a tooltip with the full command name and its
  shortcut.
- **FR-011**: When the window is too narrow for full names, names MUST be shortened first; at the
  smallest width only the key number remains. Text MUST never wrap.
- **FR-012**: The text MUST follow the system appearance (light/dark) and the system's
  accessibility contrast settings, like other controls in the window.

**Modifier keys**

- **FR-013**: While the main window is active, holding any combination of ⇧, ⌃, ⌥ and ⌘ MUST
  switch the bar to the commands bound to exactly that combination plus each function key, and
  releasing them MUST switch back to the plain set. The switch MUST happen with no perceptible
  delay.
- **FR-014**: Clicking a button while modifiers are held MUST run the command shown for those
  modifiers.
- **FR-015**: When the window becomes inactive or active again, the bar MUST show the set that
  matches the modifiers actually held at that moment (normally the plain set); it MUST never
  stay stuck on a modifier set.

**Hiding the bar and the command line**

- **FR-016**: The View menu MUST contain "Show Command Line" and "Show Function Key Bar" as
  checkable commands reflecting the current state; both MUST be available in Settings → Keyboard
  for assigning shortcuts, like any other command.
- **FR-017**: Settings MUST offer the same two options; Settings and the View menu MUST always
  show the same state.
- **FR-018**: Right-clicking the bar MUST offer "Hide Function Key Bar".
- **FR-019**: The command line MUST be visible by default; hiding it or the bar MUST give the
  freed space to the panels.
- **FR-020**: Both choices MUST be remembered across launches.
- **FR-021**: Any command that needs the command line (focusing it, inserting text into it)
  MUST show the command line first if it is hidden, update the setting to "shown", and then do
  its work; no such command may silently do nothing.

**Function keys and `fn`**

- **FR-022**: Settings → Keyboard MUST state whether function keys currently act as standard
  function keys (based on the system setting) and MUST offer "Open Keyboard Settings", which
  opens the keyboard section of System Settings.
- **FR-023**: The state shown in Settings MUST be read when the Settings window is shown or
  becomes active again, so a change made in System Settings is reflected without restarting.
- **FR-024**: When the system setting is off, the app MUST show a notice about it after the main
  window appears, with "Open Keyboard Settings" and "Don't Show Again" and a way to just close
  it. After "Don't Show Again" it MUST never be shown again; after just closing it, it MAY be
  shown on one later launch, then never again. When the system setting is on, no notice is
  shown.
- **FR-025**: The app MUST NOT change, write or try to override the system function key setting,
  and MUST NOT try to intercept brightness, volume or media keys.

**General**

- **FR-026**: All new user-visible texts MUST be localized (English source, Czech translation).
- **FR-027**: The bar MUST NOT appear in the viewer, find, compare or other secondary windows.

### Deviations from the reference program

- **D-001 (FR-022–025)**: On Windows, function keys always reach the program. On Mac keyboards
  they may need `fn`; the app can only explain this and open System Settings.
- **D-002 (FR-003, FR-013)**: The reference programs show Alt, Ctrl and Shift variants. On macOS
  the modifiers are ⇧, ⌃, ⌥ and ⌘ (⌥ takes the role of Alt), and the bar shows whatever the
  app's key map binds for each combination.
- **D-003**: Withdrawn (Clarification 2026-10-08): the buttons have no icons, as in the reference.

### Key Entities

- **Function key slot**: one of F1–F12; for a given set of held modifiers it shows at most one
  command (from the key map) or nothing.
- **Command presentation**: the localized name, short name and availability of
  a command, shared by the menu, the tooltip and the bar.
- **Window layout settings**: two remembered choices, "show command line" and "show function key
  bar", both on by default.
- **Function key notice state**: whether the `fn` notice was shown, dismissed for good, or not
  yet shown.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On first launch with default settings, a user can run Copy, Move, New Folder and
  Move to Trash for the active panel by mouse alone, with one click each, without opening a menu.
- **SC-002**: For every one of F1–F12 and every combination of ⇧, ⌃, ⌥ (8 combinations), the
  command shown in the bar matches the command the key press runs, in 100 % of cases, including
  after the user remaps a key.
- **SC-003**: Holding or releasing a modifier updates all twelve buttons with no delay a user
  can notice (well under a tenth of a second).
- **SC-004**: After clicking any button, keyboard focus is still in the panel that had it (unless
  the command opens a window or dialog), verified for all default plain-key commands.
- **SC-005**: Hiding the bar or the command line gives all of its height to the panels, and the
  choice survives a quit and relaunch in 100 % of attempts.
- **SC-006**: A user whose function keys need `fn` sees an explanation at most twice in total,
  and can reach the right place in System Settings with one click from the notice or Settings.
- **SC-007**: At the minimum window width, all twelve buttons are still visible, identifiable
  (key number) and clickable; no text wraps or overlaps.

## Assumptions

- The bar lives only in the main window; secondary windows keep their own keyboard handling.
- The existing key map, command availability rules (menu validation) and localization are the
  single source for names, shortcuts and enabled state; the bar adds no rules of its own.
- Short names for long commands come with the command definitions (a localized short name where
  the full name is too long); without one, the full name is truncated.
- "Show Command Line" and "Show Function Key Bar" have no default shortcut; users can assign one.
- Default key map positions mentioned in the scenarios are those of the current version; the
  scenarios check the bar against the key map, not against a fixed list.
- The `fn` state is read from the system's function key preference; external keyboards that
  send function keys directly are covered by the notice being shown at most twice.
- Verification follows the project rules: unit tests for the key-map-to-bar logic in the core,
  GUI checks only in the test copy of the app with both panels in a test folder.
