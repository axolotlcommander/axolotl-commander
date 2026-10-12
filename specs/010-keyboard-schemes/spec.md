# Feature Specification: Keyboard Schemes and Settings Export

**Feature Branch**: `010-keyboard-schemes`

**Created**: 2026-10-12

**Status**: Draft

**Input**: User description: "Keyboard schemes and settings export/import: extra default chords from
classic two-panel file manager habits where they collide with nothing, an opt-in "Classic Commander"
key scheme for the colliding ones, and export/import of the complete app settings."

## Context

Axolotl Commander is promoted as "keyboard first". Many of its users come from classic Windows
two-panel file managers, and they bring strong key habits:
- Ctrl+arrow sends a folder to the other panel.
- Ctrl+T and Ctrl+W open and close tabs.
- Alt+arrow moves through history.
- Ctrl+F1 and Ctrl+F2 switch between the brief and the full view.

The maintainer is one of them and wants these habits available. Two constraints apply:
- Users who are used to today's keys must not lose them.
- The product does not name any other file manager. The opt-in key set is called **"Classic
  Commander"** (Czech UI: "Klasický Commander").

A comparison of the keys was made beforehand (a local research note, not published).

**What the app has today:**
- Every command has its factory chords.
- The user can replace the chords of any command in Settings → Keyboard, with a conflict warning.
- The function key bar shows the commands of the current key map.
- There is no way to switch between sets of keys.
- There is no way to save or move the app's settings.

**This spec is the first of several** that ship together in one release:
- 011: panel behavior options;
- 012: tabs from the keyboard;
- 013: quick filter;
- 014: folder history list;
- 015: small commands;
- 016: quick view panel.

This spec lays the foundation. The later specs add their own default chords and Classic Commander
chords to it.

**Platform facts that shape the design:**
- ⌃←, ⌃→, ⌃↑ and ⌃↓ are Mission Control shortcuts by default. The app receives them only when the user
  turns those shortcuts off in System Settings.
- Function keys need fn unless the system "standard function keys" option is on.
- Third-party display utilities can take some ⌃⇧ and ⌃⌥ chords.

## Clarifications

### Session 2026-10-12

- Q: Do New Tab and Close Tab lose their factory chords ⌃⇧T / ⌃⇧W in Classic Commander? → A: No.
  The scheme adds ⌃T / ⌃W in front of them, so the menu shows ⌃T / ⌃W and ⌃⇧T / ⌃⇧W keep working.
- Q: Which Quit chord does the menu show in Classic Commander? → A: ⌘Q stays first (the menu chord);
  ⌥F4 is added after it.
- Q: What happens to a user change that equals the newly selected scheme after a scheme switch? → A:
  It is kept (FR-013) but shown as coming from the scheme, not as the user's change (FR-011). It
  shows as the user's change again when the scheme changes back.
- Q: Which sections does the settings file have? → A: Keyboard, Preferences, Appearance (the mark
  color and the highlighting rules), Hot paths, User menu, Saved servers and Toolbar. The Compare
  Panels options are part of Preferences. Recently visited folders are history and are not exported.
- Q: Is there a key for the full path of the cursor item in the command line? → A: Yes, a new command
  "Insert Full Path" on ⌃⇧↩ joins FR-001 (maintainer's request). ⌃↩ keeps inserting the name only.
  The full path is quoted like the name and followed by a space. On ".." it inserts the folder's path.
  It is the one new command of this spec. The other new commands stay in specs 012–016.
- Q: How do settings files stay usable as the app grows? → A: (maintainer's request) Automated
  guards:
  - a frozen format-1 file that every later version must import without loss;
  - a source scan that fails when a new UserDefaults key is neither exported nor explicitly
    excluded;
  - written rules: no renames, a version bump with conversion for incompatible changes. See
    contracts/settings-file.md.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Familiar keys work out of the box (Priority: P1)

A user coming from a classic two-panel file manager presses the keys they know: ⌥← for back, ⌃R to
refresh, ⇧F6 to rename, ⌃F1 for the brief view, ⌃C / ⌃V to copy and paste files, ⌥↩ for properties.
They work without any setup, as extra keys next to the ones the app already had. Nothing the
existing users know stops working.

**Why this priority**: it is the cheapest, most visible win for keyboard users and costs nobody
anything; every later spec builds on the same rule (a free key from the habits becomes a default).

**Independent Test**: on a fresh install, press each new chord in a panel and see its command run;
press each old chord and see it still run.

**Acceptance Scenarios**:

1. **Given** a panel with history, **When** the user presses ⌥←, **Then** the panel goes back; ⌥→
   goes forward; ⌘[ and ⌘] still work.
2. **Given** a file under the cursor, **When** the user presses ⇧F6, **Then** the in-place rename starts,
   exactly as with F2.
3. **Given** the Detailed view, **When** the user presses ⌃F1, **Then** the panel switches to the Brief
   view; ⌃⌥2 still works.
4. **Given** marked files, **When** the user presses ⌃C, **Then** the files are on the pasteboard as with
   ⌘C; ⌃V in another folder pastes them as with ⌘V.
5. **Given** a running quick search, **When** the user presses ⌃↑ or ⌃↓, **Then** the quick search
   still moves between matches (the new chords do not take keys the panel already uses).
6. **Given** the function key bar, **When** the user holds ⌃, **Then** F1 shows "Brief"; holding ⇧ shows
   "Compare" on F2 and "Rename" on F6; holding ⌥ shows "Unpack" on F9.

---

### User Story 2 - Opt in to the Classic Commander scheme (Priority: P1)

A user who wants the classic habits in full opens Settings → Keyboard and picks the key scheme
"Classic Commander". Keys that mean something else in the app change meaning, and the change
applies at once: ⌃T opens a tab, ⌃W closes it, ⌃⇥ moves to the next tab, ⌃F2 shows the full view, ⌃⇧F
disconnects. Every command that loses a key keeps a way to run it (another chord or its menu
item). Switching back to "Axolotl" restores the app's own keys.

**Why this priority**: the colliding keys are the habits users miss most (tabs, view modes); without a
scheme they could only be had by changing many keys one by one.

**Independent Test**: switch the scheme, press the scheme's chords and check the menus and the
function key bar; switch back and check again.

**Acceptance Scenarios**:

1. **Given** the scheme "Classic Commander", **When** the user presses ⌃T, **Then** a new tab opens;
   ⌃W closes it; ⌃⇥ / ⌃⇧⇥ move to the next / previous tab.
2. **Given** the scheme "Classic Commander", **When** the user opens the Go menu, **Then** New Tab
   shows ⌃T and Close Tab shows ⌃W, and Go to Link Target is still in the menu (without ⌃T).
3. **Given** the scheme "Classic Commander", **When** the user presses ⌃F2, **Then** the panel switches
   to the Detailed view, and Change Attributes is still reachable from the File menu.
4. **Given** the scheme "Classic Commander", **When** the user holds ⌥, **Then** the function key bar shows
   "View With" on F3 and "Quit" on F4.
5. **Given** the scheme "Classic Commander", **When** the user switches back to "Axolotl", **Then**
   every key means what it meant before, at once, without restarting.
6. **Given** either scheme, **When** the user presses F2, **Then** the rename starts (F2 is Rename in both
   schemes).

---

### User Story 3 - Personal changes on top of a scheme (Priority: P1)

A user picks a scheme and then changes a few keys to their liking. Their changes win over the scheme
and survive switching the scheme back and forth. Settings → Keyboard shows, for each command, whether
its keys come from the app's defaults, from the scheme, or from the user. "Reset" returns a command to
what the selected scheme says.

**Why this priority**: a scheme is only useful if the user can still adjust it; users who already
changed keys must keep their changes after the update.

**Independent Test**: change one key, switch schemes twice, check that the change is still in effect;
reset it and check that the scheme's key returns.

**Acceptance Scenarios**:

1. **Given** a user who assigned ⌃T to Go to Link Target, **When** they switch to "Classic
   Commander", **Then** ⌃T still runs Go to Link Target, New Tab does not get ⌃T, and Settings →
   Keyboard shows that New Tab's scheme key is taken by the user's change.
2. **Given** a changed command, **When** the user presses Reset on it, **Then** it gets the keys of the
   selected scheme.
3. **Given** several changes, **When** the user presses Reset All, **Then** all keys are those of the
   selected scheme and the scheme stays selected.
4. **Given** a user who changed keys in the previous app version, **When** they start the new version,
   **Then** the scheme is "Axolotl" and all their changes still apply.
5. **Given** the user sets a command's keys to exactly what the scheme gives it, **Then** it is not
   shown as the user's change.

---

### User Story 4 - Export and import the complete settings (Priority: P1)

A user who has set the app up the way they like saves the whole setup to one file. It holds the keys,
preferences, hot paths, user menu and saved servers, but never passwords. On another Mac, or after a
reinstall, they import the file and get the same setup at once. They can choose which parts of the
file to apply. Anything in the file the app does not understand is skipped and reported, never
guessed.

**Why this priority**: "keyboard first" users invest time in their keys and settings; losing them or
redoing them on a second Mac is the main pain the maintainer named.

**Independent Test**: export, change several settings, import the file and check that everything is
back; edit the file to contain an unknown command and a bad value and check that import reports
them and applies the rest.

**Acceptance Scenarios**:

1. **Given** customized settings, **When** the user chooses Export Settings… and saves a file,
   **Then** the file contains the key scheme, the user's key changes, all preferences from the Settings
   window, the hot paths, the user menu and the saved server connections. It contains no password or
   other secret.
2. **Given** an exported file, **When** the user chooses Import Settings… and picks it, **Then** the app
   lists the parts the file contains, all checked, and asks for confirmation that they replace the
   current ones.
3. **Given** the user confirms the import, **Then** the settings apply at once (panels, menus, the
   function key bar, the Settings window) without restarting.
4. **Given** the user unchecks "Saved servers", **Then** the current saved servers stay as they are.
5. **Given** a file with an unknown command, a malformed key and an out-of-range value, **When** it is
   imported, **Then** the rest is applied and a summary lists what was skipped.
6. **Given** a file that is not a settings file (or is damaged), **When** it is imported, **Then** a
   clear error says so and nothing changes.
7. **Given** a saved server connection was imported, **When** the user connects, **Then** the password is
   asked for (or taken from the Keychain if it is already there), because the file never carries it.

---

### Edge Cases

- **A user key that the scheme gives to another command.** The user's assignment wins. The scheme's
  command loses that key, and Settings → Keyboard shows the conflict.
- **Switching the scheme back and forth** never changes or drops the user's own changes.
- **⌃←, ⌃→ or ⌃↓ do nothing because macOS takes them** (Mission Control). Settings → Keyboard shows a
  short hint that these system shortcuts must be turned off in System Settings. The app never changes
  system settings.
- **Keyboards without a numeric keypad or an Insert key.** The existing alternative keys stay in both
  schemes. The scheme moves Restore Selection to Num/, so it also keeps a menu item.
- **A command with no key left** in a scheme stays in its menu and on the function key bar's other
  layers. Nothing is lost.
- **Export when nothing was customized** still writes a complete file of the current values, so it can
  be used as a template.
- **Import of a file from a newer app version.** The app applies the parts it understands and says that
  the file comes from a newer version.
- **Import of a file from an older version** applies what the file has. Parts it does not contain stay
  unchanged.
- **Import while a sheet or dialog is open in the main window** waits until the user closes it, or is
  not offered then (the menu item is disabled).
- **Import of saved servers that already exist** (same name and address): the imported list replaces the
  current list. Passwords already in the Keychain keep working for matching servers.
- **The function key bar and menus** never show a key that does not work in the current scheme.

## Requirements *(mandatory)*

### Functional Requirements

#### Additional default chords

- **FR-001**: The app MUST add these chords to its factory defaults, next to the existing chords of the
  same commands (no existing default chord is removed or changed):

  | Chord | Command |
  |---|---|
  | ⌃← / ⌃→ | Open in Left Panel / Open in Right Panel (today's behavior) |
  | ⌥← / ⌥→ | Back / Forward |
  | ⌃F1 | Brief view mode |
  | ⇧F2 | Compare Panels |
  | ⇧F6 | Rename |
  | ⌃R | Refresh |
  | ⌃A | Select All |
  | ⌃C / ⌃V | Copy Files / Paste Files |
  | ⌃I | Switch Panel |
  | ⌃D | Hot Paths… |
  | ⌃F and ⌃N | Connect to Server… |
  | ⌃J | Insert the cursor name into the command line |
  | ⌃P | Insert the panel path into the command line |
  | ⌃⇧B | Branch View of Selected Items |
  | ⌥↩ | Get Info |
  | ⌥⇧↩ | Calculate Folder Sizes |
  | ⌥Num+ / ⌥Num− | Select / Deselect Same Extension |
  | ⌥F9 | Unpack |
  | ⌃⇧↩ | Insert Full Path: the full path of the cursor item, name included, into the command line (new command) |

- **FR-002**: None of the chords in FR-001 MAY collide with a factory chord of another command in the
  same context, or with a key the panel handles directly. The direct keys are:
  - quick search typing;
  - ⌥↑ / ⌥↓ / ⌥Home / ⌥End, which move between marked items;
  - ⌃↑ / ⌃↓ during a quick search;
  - the movement keys.

  An automated check MUST guard this for every context (panel, viewer, find, compare).
- **FR-003**: Menus MUST keep showing each command's first (primary) chord. The function key bar MUST
  show the new function key chords in the matching modifier layer.

#### Key schemes

- **FR-004**: Settings → Keyboard MUST offer a key scheme choice with two schemes: **Axolotl** (the
  default) and **Classic Commander**.
- **FR-005**: A scheme MUST be defined as data: a list of commands with the chords that replace their
  factory chords. Later features can add entries without changing how schemes work. "Axolotl" has no
  changes.
- **FR-006**: The Classic Commander scheme MUST contain these changes. Commands not listed keep their
  factory chords, including the ones from FR-001.

  | Command | Chords in Classic Commander |
  |---|---|
  | New Tab | ⌃T, plus the factory ⌃⇧T |
  | Close Tab | ⌃W, plus the factory ⌃⇧W |
  | Next Tab / Previous Tab | ⌃⇥ / ⌃⇧⇥ (the factory ⌃⇧PgDn / ⌃⇧PgUp stay as well) |
  | Focus Command Line | ⌃↓ |
  | Go to Link Target | no chord (menu item only) |
  | Restore Selection | Num/ |
  | Open Terminal Here | ⌃/ only |
  | Detailed view mode | ⌃F2, plus the factory ⌃⌥1 |
  | Change Attributes | no chord (menu item only) |
  | Disconnect | ⌃⇧F, plus F12 |
  | Connect to Server | ⌘K, ⌃F, ⌃N |
  | New Symbolic Link | ⌃⇧F5, plus ⌃⌘L |
  | Remember Selection | no chord (menu item only) |
  | View With… | ⌥F3, plus ⌃⇧F3 |
  | Quick Look | ⌘Y only |
  | Quit | ⌘Q (still the menu chord), plus ⌥F4 |

  F2 MUST stay Rename in both schemes.
- **FR-007**: Within one context, no two commands MAY share a chord in any scheme before user changes
  are applied. An automated check MUST guard this for both schemes.
- **FR-008**: Changing the scheme MUST take effect at once everywhere: key handling in panels and
  windows, menu key equivalents, the function key bar and Settings → Keyboard. No restart is needed.
- **FR-009**: The selected scheme MUST be remembered across launches. On the first launch after the
  update the scheme MUST be "Axolotl".

#### The user's own changes

- **FR-010**: The user's chord changes MUST apply on top of the selected scheme and win over it. A
  chord the user assigns to one command MUST be removed from any other command that would get it from
  the factory defaults or from the scheme.
- **FR-011**: A user change that equals what the selected scheme gives the command MUST NOT be kept as
  a user change.
- **FR-012**: The user's changes from earlier app versions MUST keep working unchanged, on top of
  "Axolotl".
- **FR-013**: Switching the scheme MUST NOT change or drop the user's changes.
- **FR-014**: "Reset" for one command and "Reset All" MUST return to the chords of the selected scheme.
  The scheme stays selected.
- **FR-015**: Settings → Keyboard MUST show, for each command, whether its chords come from the
  defaults, from the scheme or from the user. It MUST show conflicts against the effective key map:
  factory, then scheme, then user.
- **FR-016**: Settings → Keyboard MUST show a short hint that ⌃← / ⌃→ / ⌃↑ / ⌃↓ reach the app only when
  the Mission Control shortcuts are turned off in System Settings. The app MUST NOT change system
  settings.

#### Export and import

- **FR-017**: The app MUST offer "Export Settings…" and "Import Settings…":
  - in the app menu, below "Settings…";
  - as buttons in the General tab of the Settings window.
- **FR-018**: Export MUST write one human-readable file with a format name, a format version, the app
  version and the export date, and sections for:
  - **Keyboard**: the selected scheme and the user's chord changes.
  - **Preferences**: every user preference shown in the Settings window. That includes appearance, the
    path bar, size display and units, panels, the chosen editor and terminal apps, viewer and compare
    defaults, the checksum algorithm, links and the visibility of the function key bar and the command
    line. Preferences added later (for example the behavior options of spec 011) are included
    automatically.
  - **Hot paths**.
  - **User menu**.
  - **Saved server connections**: name, protocol, address, port, user name, folder and connection
    options. No password or other secret.

  Highlighting rules, toolbar layout and similar user-made configuration MUST be included when the app
  stores them.
- **FR-019**: Export MUST NOT include:
  - session state: open folders, tabs, window positions, navigation history;
  - the find and command line history;
  - the last inputs of dialogs;
  - one-time notices;
  - any password, passphrase, key or token.

  The file MUST be written with stable key order, so two exports of the same settings are identical
  apart from the date.
- **FR-020**: Import MUST read a file the user picks, check that it is an Axolotl Commander settings
  file and list the sections it contains as checkboxes, all checked. The chosen sections MUST replace
  the current ones only after the user confirms.
- **FR-021**: Import MUST apply the chosen sections at once (live), with the same effect as changing
  them in the Settings window.
- **FR-022**: Import MUST skip and then list in a summary everything it cannot apply:
  - unknown commands, malformed chords;
  - unknown preference keys, values of the wrong type or out of range;
  - entries of unknown sections.

  A file from a newer format version MUST be imported as far as it is understood, with a warning. A
  damaged or foreign file MUST be rejected with a clear message, and nothing changes.
- **FR-023**: Import MUST NOT read or change anything other than the chosen file and the app's own
  settings. It MUST never import or store a password.
- **FR-024**: All new texts MUST be localized (English source, Czech translation). The scheme is named
  "Classic Commander" in English and "Klasický Commander" in Czech.

### Key Entities

- **Key scheme**: a named set of chord changes over the factory defaults (Axolotl: none; Classic
  Commander: the FR-006 list). Built in, chosen by the user, extended by later specs.
- **Effective key map**: per context, the chord → command lookup made from the factory chords, then the
  selected scheme's changes, then the user's changes.
- **User key changes**: per command, the chords the user chose; kept only where they differ from the
  selected scheme.
- **Settings file**: one exported document with a format name and version, the app version, the date and
  the sections Keyboard, Preferences, Hot paths, User menu and Saved servers (plus other user-made
  configuration the app stores). It never carries secrets.
- **Import report**: what was applied per section and what was skipped and why.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 24 chords of FR-001 work in a panel on a fresh install, and every chord that worked
  before the update still works (100 %, checked automatically).
- **SC-002**: Switching the scheme changes the meaning of all its keys, the menus and the function key
  bar within 1 second, without a restart.
- **SC-003**: A user can move their complete setup to another Mac in under 1 minute: one export, one
  import, no manual re-entry of keys, hot paths or servers.
- **SC-004**: An export followed by an import on the same Mac restores 100 % of the exported settings.
  Exporting again gives the same file apart from the date.
- **SC-005**: No exported file ever contains a password or other secret (checked automatically,
  including with saved servers that have passwords stored).
- **SC-006**: Every key change from the previous app version still applies after the update (checked
  automatically with the previous format).
- **SC-007**: A damaged or foreign file never changes any setting.

## Assumptions

- Mission Control shortcuts are the user's business; the app only explains them. On the maintainer's
  machine they are already turned off.
- A third-party display utility on the maintainer's machine takes ⌃⇧ and ⌃⌥ chords. The new defaults
  avoid relying on those modifiers. The Classic Commander scheme uses a few of them (⌃⇧⇥, ⌃⇧F, ⌃⇧F5),
  which work once that utility's shortcuts are off.
- ⌃C, ⌃V, ⌃A, ⌃P and the other new ⌃ letter chords act on the panel only. While a text field is being
  edited they keep their standard text meaning, as panel commands already do today.
- The settings file is JSON. One file holds everything, and there is one file per export.
- The behavior options of spec 011 are preferences, so they join the Preferences section without
  changes to this feature.
- Saved server connections are matched by name and address when Keychain passwords are looked up after
  an import.

## Out of Scope

- More than the two built-in schemes, or user-defined named schemes (export and import cover personal
  setups).
- Behavior differences from classic managers: the Ctrl+arrow logic, a volume button taking over the
  other panel's path, Space not moving the cursor, letters typing into the command line (spec 011).
- New commands (except Insert Full Path, see Clarifications) such as quick filter, a history list, opening in a new tab or the quick view panel. Specs
  012–016 add them with their chords.
- Syncing settings through iCloud or any service.
- Exporting passwords, even encrypted.
- A generated keyboard reference document.
- Merging an imported section with the current one item by item (a chosen section replaces the current
  one as a whole).
