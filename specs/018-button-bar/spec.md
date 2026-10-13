# Feature Specification: Button Bar

**Feature Branch**: `018-button-bar`

**Created**: 2026-10-13

**Status**: Implemented

**Input**: User description: "An optional bar of buttons at the very top; any function can be put on it — a
user button bar, with icons the user picks. Icons only, no labels; maybe it could also go at the bottom,
after the F-keys."

## Context

The window has a macOS toolbar (customizable through Customize Toolbar, about thirty commands with fixed
icons) and, at the bottom, the function key bar F1–F12 (spec 002, layers spec 010, choice of buttons spec
017). Classic two-panel file managers also have a button bar the user fills with anything: app commands
and external programs, each shown as an icon. The user menu (F2, spec of stage 6) already runs programs
with `$(Variables)` such as the file under the cursor.

Since spec 017 the function key buttons are at most 140 points wide, so a wide window leaves room at the
right end of the bottom row; that is where the button bar can go.

It ships with specs 010–017 in release 0.4.0 (maintainer, 2026-10-13).

## Clarifications

### Session 2026-10-13

- Q: Labels? → A: Icons only; the name shows as a tooltip.
- Q: Where is the bar? → A: One setting: off, at the top (above the panels) or at the bottom (after the
  function keys). One set of buttons.
- Q: What can a button run? → A: Any app command, or a program with arguments, exactly like a user menu
  command (same variables, same directory and terminal options).
- Q: How is it edited? → A: A "Button Bar" tab in Settings (add, remove, reorder, separators, icon
  choice) and a right click on the bar (Edit, Remove, Add, Customize…).
- Q: Default? → A: Off, with a few sample buttons, so turning it on shows something useful at once.
- The answers below were *decided while writing the spec; to review*:
  - Q: Which icons? → A: SF Symbols: a searchable grid of a built-in list of suitable symbols, plus a field
    for any symbol name. A program button can also use the program's own app icon.
  - Q: Default icon? → A: A command uses the icon it has in the toolbar, otherwise a generic one; a program
    uses its app icon when it is an app, otherwise a terminal icon.
  - Q: Sample buttons? → A: Open Terminal Here, Find, Compare Panels, Hot Paths, Calculate Sizes, Reveal in
    Finder.
  - Q: The bottom bar when the function key bar is hidden? → A: The bottom row shows the buttons alone.
  - Q: Not enough room? → A: Buttons that do not fit go into a » menu at the end of the bar. At the bottom
    the function keys shrink first (as in spec 017), down to a minimum, before buttons move into »
    (to review: minimum = key-only width).
  - Q: A menu command? → A: View → Show Button Bar turns the bar on (at the last place used, top by
    default) and off.
  - Q: Export? → A: The buttons are a new "buttonBar" section of the settings file; the placement is a
    preference. A file without them keeps the current buttons.
- *Decided during implementation; to review*:
  - Edit Button… and Add Button… open Settings → Button Bar with that button selected (Add first
    puts a new command button after the clicked one) instead of a separate sheet: one editor only.
  - The placement is three choices (Off, Top, "Bottom, after the function keys"); Restore Samples
    is in the + menu of the list.
  - The frozen format-1 fixture has no buttonBar section; the compatibility test lists it as added
    later.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Turn the bar on and click a button (Priority: P1)

A user turns the button bar on in Settings → Button Bar (or View → Show Button Bar). A row of icons
appears above the panels. Pointing at an icon shows its name; clicking runs the command on the active
panel, and the keyboard focus stays in the panel.

**Why this priority**: the bar itself.

**Independent Test**: turn the bar on, point at each sample button, click Find and Compare Panels, check
the focus.

**Acceptance Scenarios**:

1. **Given** the bar is off, **When** the user chooses View → Show Button Bar, **Then** the sample buttons
   appear at the top in every window and the menu item is checked.
2. **Given** the bar is shown, **When** the pointer rests on a button, **Then** a tooltip shows its name
   (and the shortcut of a command that has one).
3. **Given** the bar is shown, **When** the user clicks Find, **Then** Find opens for the active panel and
   afterwards the focus is back in the panel.
4. **Given** a command is unavailable (for example Disconnect on a local folder), **Then** its button is
   disabled, as the menu item is.

---

### User Story 2 - Put any command or program on the bar (Priority: P1)

In Settings → Button Bar the user adds a button for any app command (searchable list, as in Settings →
Keyboard) or for a program (program, arguments with variables, directory, run in terminal — the same
fields as the user menu), picks an icon, moves it in the list, adds separators and removes buttons.

**Why this priority**: without it the bar holds only the samples.

**Independent Test**: add a command button and a program button that runs `open -a TextEdit $(FullName)`,
reorder, add a separator, remove a sample; check the bar after each step.

**Acceptance Scenarios**:

1. **Given** Settings → Button Bar, **When** the user adds a command button for Sort by Size, **Then** the
   bar shows it at once with the command's default icon.
2. **Given** a program button with `$(FullName)`, **When** the user clicks it with the cursor on a file,
   **Then** the program runs on that file, as the same user menu command would.
3. **Given** a program button with a file variable, **When** the cursor is on ".." and nothing is marked,
   **Then** the same message as from the user menu explains why it did not run.
4. **Given** the icon picker, **When** the user types "star", **Then** the grid shows the matching
   symbols; choosing one changes the button's icon.
5. **Given** a program button for an app, **Then** "App icon" is offered and shows that app's icon.
6. **Given** buttons in the list, **When** the user drags one to another place or adds a separator,
   **Then** the bar follows.

---

### User Story 3 - The bar at the bottom, after the function keys (Priority: P2)

The user sets the place to "Bottom". The buttons stand in the bottom row right after the function keys,
separated by a thin line; the function keys keep their own rules (spec 017).

**Acceptance Scenarios**:

1. **Given** the place is Bottom and the function key bar is shown, **Then** the buttons follow the last
   function key, after a separator.
2. **Given** the place is Bottom and the function key bar is hidden, **Then** the bottom row shows the
   buttons alone.
3. **Given** a narrow window, **Then** the function keys shrink first; when they reach their minimum,
   the buttons that do not fit go into the » menu.

---

### User Story 4 - Edit the bar from the bar (Priority: P3)

Right-clicking a button offers Edit Button…, Remove Button, Add Button… and Customize Button Bar… (the
Settings tab); right-clicking the empty part of the bar offers Add Button…, Customize Button Bar… and Hide
Button Bar.

**Acceptance Scenarios**:

1. **Given** the bar, **When** the user right-clicks a button and chooses Remove Button, **Then** the
   button goes away in every window.
2. **When** the user chooses Edit Button…, **Then** Settings → Button Bar opens with the button selected;
   a change there changes the bar at once.

---

### Edge Cases

- **The window toolbar** stays as it is; the button bar is independent of Customize Toolbar.
- **An empty bar** (every button removed) still shows its row with a hint to add buttons, so the right
  click keeps working.
- **A command removed in a later version** or an unknown symbol in an imported file: the button stays
  with a generic icon and is disabled; the editor shows why.
- **A program that does not exist**: clicking shows the user menu's error.
- **Quick view, maximized panel, archives, servers**: commands follow the same availability rules as in
  the menu; programs follow the user menu rules.
- **Dark mode and accents**: icons are template symbols and follow the system colors; app icons stay in
  color.
- **Keyboard**: the buttons never take focus; they are reachable with the mouse and with VoiceOver (each
  button has its name as accessibility label).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The app MUST offer a button bar with a placement setting: Off (default), Top (between the
  window toolbar and the panels) or Bottom (in the row of the function key bar, after the function keys).
- **FR-002**: A button MUST be one of: an app command, a program (the user menu command fields), or a
  separator; buttons show only an icon, with the name (and a command's shortcut) as tooltip and
  accessibility label.
- **FR-003**: Clicking a command button MUST run the command as its menu item does, on the active panel;
  clicking a program button MUST run it as the user menu does. The focus MUST stay where it was.
- **FR-004**: A command button MUST be disabled when its command is unavailable.
- **FR-005**: Settings MUST have a Button Bar tab: placement, the list of buttons (add command, add
  program, add separator, remove, drag to reorder) and an editor with the icon picker.
- **FR-006**: The icon picker MUST offer a searchable grid of SF Symbols from a built-in list, a field for
  any symbol name, and for program buttons the program's app icon.
- **FR-007**: A right click on the bar MUST offer Edit Button…, Remove Button, Add Button…, Customize
  Button Bar… and Hide Button Bar (the button items only on a button).
- **FR-008**: View → Show Button Bar MUST turn the bar on (last place used, Top by default) and off.
- **FR-009**: Buttons that do not fit MUST be reachable from a » menu at the end of the bar; at the bottom
  the function keys MUST shrink first, down to their minimum.
- **FR-010**: The default content MUST be the sample buttons; the buttons MUST be exported as a settings
  section and the placement as a preference, with the existing compatibility guards.
- **FR-011**: Every change MUST apply at once in every window.

### Key Entities

- **Button**: id, kind (command, program, separator), command name or program fields (as a user menu
  command), icon (symbol name, app icon or default), title (for program buttons; a command's title comes
  from the command).
- **Button bar placement**: off, top, bottom; plus the last place used for View → Show Button Bar.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Turning the bar on and running a command from it takes two clicks from the View menu.
- **SC-002**: The model (buttons, defaults, decoding of old or broken data, default icons) and the layout
  rule (what fits, what goes into », how the function keys shrink) have automated tests.

## Assumptions

- Icon buttons are about 28 × 22 points; the built-in symbol list has a few hundred names fit for file
  manager actions.

## Out of Scope

- Dropping files on a button to run a program on them.
- Several bars, or a separate set of buttons per window.
- Text labels or a choice between icon and text.
- Changing the window toolbar or merging the two.
- Keyboard shortcuts for buttons (commands have their own; programs get one in the user menu).

## Deviations from the classic reference

- Icons are SF Symbols or app icons, not icons taken from program files.
- One bar, either at the top or after the function keys, not a free-floating or vertical bar.
