# Feature Specification: Basic Commands

**Feature Branch**: `033-basic-commands`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "Basic commands: cut files to the clipboard, Mac-style tab keys, Duplicate, and
standard folders." Reported by the maintainer ("the Cut File command is missing", "check the other basic
functions too"); agreed in chat on 2026-10-16 ("as you recommend").

## Context

Today the clipboard works only the Finder way: Copy Files (⌘C) puts the files on the clipboard, Paste Files
(⌘V) copies them into the active panel's folder (a path stored as text goes to that folder instead), Move
Files Here (⌥⌘V) moves them and Paste as Symbolic Link (⌃⌘V) links them. There is no Cut.

The tab commands have keys only with ⌃⇧ (New Tab ⌃⇧T, Close Tab ⌃⇧W, Next / Previous Tab ⌃⇧Page Down /
Page Up). Some display utilities take ⌃⇧ chords for themselves, so on those machines the tabs have no
working keys at all; the opt-in classic key scheme adds ⌃T, ⌃W and ⌃Tab.

Home (⇧⌘H) is the only standard folder with a command. There is no Duplicate.

The reference program (behavior from its help) has Cut: it puts references to the selected items on the
clipboard and nothing moves until Paste; the cut items are shown ghosted until they are pasted or until
another Copy or Cut replaces the clipboard; Paste moves the cut items into the panel's current folder
(the selection in that panel does not matter) and removes them from the clipboard, while copied items stay
on the clipboard after a paste.

## Clarifications

### Session 2026-10-16

- Q: Which basic functions go into this spec? → A: Cut, Mac keys for tabs, Duplicate and the standard
  folders; Undo of file operations and Open With an arbitrary application come later, each on its own.
- Q: Keys for switching tabs? → A: ⇧⌘] and ⇧⌘[ as in Safari and Finder; ⌃Tab stays Command Line in the
  default scheme and Next Tab in the classic scheme.
- Q: Key for Applications? → A: None by default, because ⇧⌘A is Deselect All; it can be assigned in
  Settings → Keyboard.
- Q: A cut set after the app is quit and started again? → A: It is no longer a cut set: Paste copies the
  files (moving files the user may have forgotten about is the riskier choice), and nothing is dimmed.
- Q: Where is Cut available? → A: Where moving with F6 is available today; elsewhere it is disabled.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cut and paste files (Priority: P1)

The user cuts files in one folder and pastes them in another, and they are moved, the way it works in the
reference program and in other file managers.

**Why this priority**: It is the missing basic command reported by the maintainer; users coming from other
file managers reach for ⌘X / ⌘V first.

**Independent Test**: In a test folder mark two files, press ⌘X, go to another test folder, press ⌘V: the
two files are moved there.

**Acceptance Scenarios**:

1. **Given** two marked files, **When** the user presses ⌘X (or chooses Edit → Cut Files or Cut Files in
   the context menu), **Then** nothing moves, and both files are drawn dimmed (icon and name) in every panel
   and window of the app that shows them.
2. **Given** no marked items and the cursor on a file, **When** the user presses ⌘X, **Then** that file is
   cut.
3. **Given** cut files, **When** the user goes to another folder and presses ⌘V (or another key of Paste
   Files), **Then** the files are moved there with the usual move progress, conflict questions and error
   reports; afterwards the dimming is gone and the clipboard no longer holds them.
4. **Given** a cut set that was just pasted, **When** the user presses ⌘V again, **Then** nothing happens
   and the app beeps.
5. **Given** cut files, **When** part of the move fails or the user cancels it, **Then** the files that were
   not moved stay where they were, stay on the clipboard and stay dimmed; pasting again moves them.
6. **Given** cut files, **When** the user copies or cuts something else (in this app or any other) or copies
   text, **Then** the earlier cut ends: its files are no longer dimmed and pasting gives the new clipboard
   content.
7. **Given** cut files, **When** the user pastes them into the folder they came from, **Then** nothing
   happens, the app beeps and the files stay cut.
8. **Given** a cut folder, **When** the user pastes it into itself or one of its subfolders, **Then** the
   paste is refused the same way as moving a folder into itself is refused today.
9. **Given** files copied with ⌘C, **When** the user pastes them, **Then** they are copied as today and stay
   on the clipboard; ⌥⌘V still moves them.
10. **Given** cut files, **When** the user chooses Paste as Symbolic Link, **Then** links are created and the
    files stay cut.
11. **Given** the active panel shows an archive, a server or another place where F6 is unavailable,
    **When** the user looks at Cut Files, **Then** it is disabled (grayed in the menus, a beep from its
    key).
12. **Given** the classic key scheme, **When** the user presses ⌃X, **Then** the files are cut as with ⌘X.

---

### User Story 2 - Tabs with Mac keys (Priority: P1)

The user opens and switches tabs with the keys every Mac app uses for tabs.

**Why this priority**: On machines where ⌃⇧ chords are taken, the tabs have no working keys today.

**Independent Test**: Press ⌘T: a new tab opens in the active panel; press ⇧⌘[ and ⇧⌘]: the panel moves
between its tabs.

**Acceptance Scenarios**:

1. **Given** the panel has the focus, **When** the user presses ⌘T, **Then** a new tab opens in the active
   panel, exactly as New Tab does.
2. **Given** a panel with several tabs, **When** the user presses ⇧⌘] or ⇧⌘[, **Then** the next or previous
   tab becomes active, wrapping around at the ends as Next Tab and Previous Tab do.
3. **Given** any window, **When** the user presses ⌘W, **Then** the window closes as today (no change).
4. **Given** the earlier keys (⌃⇧T, ⌃⇧W, ⌃⇧Page Down / Page Up) and the classic scheme's ⌃T / ⌃W / ⌃Tab,
   **When** the user presses them, **Then** they work as before.
5. **Given** Settings → Keyboard, **When** the user looks at New Tab, Next Tab and Previous Tab, **Then** the
   new keys are listed and can be changed or removed.

---

### User Story 3 - Duplicate (Priority: P2)

The user makes a copy of a file or folder next to it in one step, the way Finder does.

**Why this priority**: A common everyday step that otherwise takes F5 plus typing a new name.

**Independent Test**: With the cursor on "report.pdf" in a test folder press ⌘D: "report copy.pdf" appears
(Czech UI: "report kopie.pdf") with the cursor on it.

**Acceptance Scenarios**:

1. **Given** the cursor on "report.pdf", **When** the user presses ⌘D (or chooses File → Duplicate or
   Duplicate in the context menu), **Then** a copy named "report copy.pdf" (in the Czech UI "report
   kopie.pdf") appears in the same folder and the cursor is on it.
2. **Given** "report copy.pdf" exists, **When** the user duplicates "report.pdf" again, **Then** the copy is
   named "report copy 2.pdf", then "report copy 3.pdf", and so on.
3. **Given** a folder "Photos", **When** the user duplicates it, **Then** "Photos copy" with all its content
   appears.
4. **Given** a file without an extension ("Makefile") or a name starting with a dot (".env"), **When** the
   user duplicates it, **Then** the word is added at the end ("Makefile copy", ".env copy").
5. **Given** several marked items, **When** the user presses ⌘D, **Then** each one is duplicated next to
   itself and the cursor is on the first new copy.
6. **Given** the copy fails (no space, no permission), **When** the error comes, **Then** it is reported as
   any copy error today.
7. **Given** the cursor on "..", **When** the user presses ⌘D, **Then** nothing happens and the app beeps.
8. **Given** the active panel shows an archive, a server or a results listing, **When** the user looks at
   Duplicate, **Then** it is disabled.

---

### User Story 4 - Standard folders (Priority: P2)

The user goes to the Desktop, Documents, Downloads or Applications with one key or from the Go menu, as in
Finder.

**Why this priority**: Everyday destinations; only Home has a command today.

**Independent Test**: Press ⇧⌘D: the active panel shows the user's Desktop.

**Acceptance Scenarios**:

1. **Given** the panel has the focus, **When** the user presses ⇧⌘D, ⇧⌘O or ⌥⌘L, **Then** the active panel
   shows the user's Desktop, Documents or Downloads folder.
2. **Given** the Go menu, **When** the user chooses Desktop, Documents, Downloads or Applications (listed
   after Home), **Then** the active panel shows that folder; Applications is the system Applications folder.
3. **Given** a tab locked to its folder, **When** the user runs one of these commands, **Then** the same
   rule applies as for Home today (the folder opens in a new tab).
4. **Given** Settings → Keyboard, **When** the user looks at the four commands, **Then** Applications has no
   key and the others have the keys above; all can be changed.

---

### Edge Cases

- Cut files deleted or renamed by another app before the paste: the move reports the missing ones as a move
  of missing files does today; the others are moved; the missing ones are no longer on the clipboard.
- Cut in one main window, paste in another: works, the clipboard is shared.
- Cut, quit the app, start it again: the files are no longer cut; Paste copies them; nothing is dimmed.
- Cut files pasted in Finder or another app: that app copies them (macOS has no common cut flag for files);
  the files stay cut in this app until the clipboard changes.
- Cut, then Copy Path as Text or Copy Name as Text: the clipboard changes, so the cut ends.
- Cut files shown in the results listing or in a branch view: dimmed there too.
- Cut from the results listing (files from several folders): allowed, as F6 is; the paste moves all of them.
- Paste of cut files while the active panel shows an archive, a server or a results listing: refused the same
  way as Paste Files there today.
- Duplicate when "copy", "copy 2", … up to any number are taken: keeps counting to the first free name.
- Duplicate of a very long name: the name stays within the file system's limit by shortening the base name
  before the added word, never the extension.
- The keyboard focus is in the command line or another text field: ⌘X, ⌘D, ⌘T and the folder keys act on
  the text field (cut text, or nothing), never on files, as ⌘C does today.
- A standard folder that does not exist (for example Downloads removed): the panel stays where it was and
  the app shows the same message as when any folder cannot be opened.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A command "Cut Files" MUST exist in the Edit menu and the panel's context menu, with ⌘X by
  default (and ⌃X in the classic key scheme), acting on the marked items or, when none are marked, on the
  item under the cursor.
- **FR-002**: Cut Files MUST put the items on the clipboard as an ordinary file list (other apps can paste it
  as copied files) and remember them as cut in this app; it MUST NOT move anything by itself.
- **FR-003**: Cut items MUST be drawn dimmed (icon and name) in every panel and window of the app that shows
  them, for as long as the cut lasts.
- **FR-004**: A cut MUST end when the clipboard changes for any reason (another Copy, Cut, text copied in any
  app) or when the app quits; then nothing is dimmed and pasting treats the clipboard content as copied.
- **FR-005**: Paste Files on a cut set MUST move the items into the active panel's folder with the existing
  move operation (progress, conflicts, errors, refusals); after the move the moved items MUST leave the
  clipboard and lose the dimming; items that were not moved MUST stay cut.
- **FR-006**: Paste Files on a cut set whose items all come from the active panel's folder MUST do nothing
  and beep.
- **FR-007**: Paste Files on copied files, Move Files Here and Paste as Symbolic Link MUST keep today's
  behavior; Paste as Symbolic Link MUST NOT end a cut.
- **FR-008**: Cut Files MUST be available exactly where moving with F6 is available today and disabled
  elsewhere.
- **FR-009**: New Tab MUST also have ⌘T, Next Tab ⇧⌘] and Previous Tab ⇧⌘[ by default; the existing keys
  of these commands and of the classic scheme MUST stay; ⌘W MUST keep closing the window.
- **FR-010**: A command "Duplicate" MUST exist in the File menu and the panel's context menu, with ⌘D by
  default, copying each marked item (or the item under the cursor) into its own folder under a free name
  formed as in Finder: the localized word "copy" (Czech "kopie") added after the base name, before the
  extension, then " 2", " 3", … for further copies; the cursor MUST end on the first new copy.
- **FR-011**: Duplicate MUST be available only where copying inside the same folder is possible (local and
  network folders) and MUST beep on "..".
- **FR-012**: Commands "Desktop" (⇧⌘D), "Documents" (⇧⌘O), "Downloads" (⌥⌘L) and "Applications" (no key)
  MUST exist in the Go menu after Home and take the active panel to the user's folder of that name (the
  system Applications folder for Applications), following the same navigation rules as Home.
- **FR-013**: All new commands and keys MUST appear in Settings → Keyboard, be reassignable and be included
  in the settings export and import as the other keys are.
- **FR-014**: The new default keys MUST NOT collide with any other default key of the panel.
- **FR-015**: All new texts MUST be localized (English and Czech).

### Key Entities

- **Cut set**: the items put on the clipboard by Cut Files, together with the clipboard state they belong
  to; it lasts until the clipboard changes, the items are moved or the app quits.
- **Duplicate name**: the base name, the localized word "copy", an optional number and the extension.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Moving files with the clipboard takes two key presses (⌘X in the source, ⌘V in the target)
  plus navigation.
- **SC-002**: The user can see which files are cut in every panel that shows them, at a glance, without
  opening anything.
- **SC-003**: No file is moved by a paste unless the user cut it in this app during the current run; files
  copied with ⌘C or in another app are never moved by ⌘V.
- **SC-004**: Opening and switching tabs works with ⌘T and ⇧⌘] / ⇧⌘[ on every Mac, including those where ⌃⇧
  chords are taken by another utility.
- **SC-005**: A duplicate is created with one key press and its name never overwrites an existing item.
- **SC-006**: Desktop, Documents and Downloads are one key press away; Applications is in the Go menu.

## Assumptions

- The cut set lives in memory for the current run of the app; that is enough, because a cut ends when the
  app quits.
- Dimming uses the same look as hidden files in the panel.
- The word added by Duplicate follows the app's language, as the rest of its UI does (not the Finder's
  language if they differ).
- Duplicate names are formed the same way for files and folders; for a folder the "extension" is not
  separated (a folder "Project.v2" becomes "Project.v2 copy").

## Out of Scope

- Undo of file operations (a later spec).
- Open With an arbitrary application (later).
- Finder aliases; Utilities and other standard folders.
- Changing what ⌘W does.
- Cutting inside archives or on servers.

## Deviations from the reference

- The Mac keys (⌘X, ⌘D, ⌘T, ⇧⌘] / ⇧⌘[, ⇧⌘D, ⇧⌘O, ⌥⌘L) are the defaults; the reference's ⌃X is in the
  classic scheme.
- Cut files pasted in Finder are copied, not moved, because macOS has no cut flag for files that Finder
  honors.
- A cut does not survive quitting the app.
