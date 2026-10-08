# Research: Function Key Bar and Hideable Command Line

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md) | **Date**: 2026-10-08

The spec left no `NEEDS CLARIFICATION` markers. The questions below are the technical unknowns
found while reading the current code (`CommandRegistry`, `KeyMaps`, `MainWindowController`,
`MainToolbar`, `AppSettings`, `KeyboardSettings`).

## R1. Where the bar gets its commands

- **Decision**: A pure function in the core, `FunctionKeyBar.slots(in: KeyMap, modifiers:)`,
  returns twelve `Command?` values: `map.command(for: KeyChord(.function(n), modifiers))` for
  n = 1…12. The UI uses `KeyMaps.panel`, which already merges the factory chords with the
  user's overrides and contains only `.app` and `.panel` scope commands.
- **Rationale**: The key press and the bar then read the same lookup, so SC-002 ("the bar shows
  what the key runs") holds by construction and is still checked by a test over all 12 × 8
  combinations, with and without a remap. Viewer, find and compare commands are not in the
  panel map, so FR-009 ("not usable in the main window → empty") needs no extra rule.
- **Alternatives considered**: Listing commands per F-key in the bar code (rejected: hard-coded,
  violates FR-003); asking each command for "its" F-key (rejected: commands have several chords,
  and a chord can be overridden by another command).

## R2. Names and short names

- **Decision**: Full name = `CommandSpec.localizedTitle` without a trailing "…". The core gets
  an optional English `shortTitle` per command (`CommandRegistry.shortTitle(_:)`), set only
  where the full name is long, e.g. "Move to Trash" → "Trash", "Delete Immediately…" →
  "Delete", "Apply Remembered Selection" → "Apply Selection", "Show Context Menu" → "Menu",
  "Volume…" (left/right) → "Left"/"Right" volume. Short titles are translated in
  `Resources/Localizable.xcstrings` like the full titles (looked up by their English text).
- **Bar titles**: where the menu title is not clear without its menu (both volume menus are
  "Volume…" under Left/Right), the core gives a bar title (`CommandRegistry.barTitle(_:)`:
  "Left Volume", "Right Volume"); found in the GUI check.
- **Rationale**: Matches the spec assumption ("short names come with the command
  definitions"). Keeping English keys in the core follows the existing localization pattern.
- **Alternatives considered**: Automatic abbreviation (rejected: unreadable in Czech); a
  separate table in the UI (rejected: names belong to the command, like titles).

## R3. Fitting labels into narrow buttons

- **Decision**: On every layout pass the bar computes the width available per button and, for
  each button, picks the first variant that fits: (1) key + full name, (2) key + short name,
  (3) key + short name truncated with "…" at the tail, (4) key only.
  Text is single-line (`lineBreakMode = .byTruncatingTail`, `usesSingleLineMode`). The tooltip
  always holds the full name and the shortcut (e.g. "Copy… (F5)").
- **Rationale**: Covers FR-011/SC-007. The window minimum width is 600 pt, i.e. about 50 pt per
  button, which still fits "F12" and a few letters.
- **Alternatives considered**: Let AppKit truncate the full name only (rejected: "Move to T…"
  is worse than "Trash"); hiding buttons at small widths (rejected: SC-007 wants all twelve).

## R4. Icons

- **Decision**: Withdrawn (spec Clarification 2026-10-08): the buttons show text only, as in
  Tandem Commander. The toolbar keeps its own symbol table in `MainToolbar`; nothing moves to the
  core.

## R5. Following the held modifiers

- **Decision**: The main window controller adds a local event monitor for `.flagsChanged` (only
  events of its window) and recomputes the slots when the ⇧⌃⌥⌘ part of the flags changes.
  On `windowDidBecomeKey`/`windowDidResignKey` it reads `NSEvent.modifierFlags` (the real
  current state), so the bar never stays stuck after ⌘Tab (FR-015). `fn` (`.function`),
  Caps Lock and numeric-pad flags are ignored: holding `fn` to press F5 must show the plain
  set. While the window is not key, flag changes are ignored.
- **Rationale**: `flagsChanged` is delivered immediately and recomputing twelve dictionary
  lookups is far below the 100 ms of SC-003.
- **Alternatives considered**: A global monitor (rejected: needs Accessibility permission and
  is not needed while the window is inactive); polling `NSEvent.modifierFlags` (rejected:
  wasteful and laggy).

## R6. Clicking a button

- **Decision**: Buttons are `NSButton`s with `refusesFirstResponder = true`, so a click never
  moves keyboard focus (FR-007). The action runs the command stored on the button for the
  modifier set currently shown (the set that the user sees is the set that runs, FR-014).
  It calls a new `MainWindowController.performFromBar(_:)` that checks
  `canPerformIgnoringFocus` and then routes like `perform` without moving focus: when the
  command line edits, a panel command runs for the active panel and the command line keeps
  focus, unless the command itself moves focus (e.g. in-place rename). Clicks while a sheet is
  open never reach the window (AppKit blocks them), which covers that edge case.
- **Control-click**: AppKit turns ⌃-click into a context-menu click. The bar's `menu(for:)`
  returns the context menu only for a real right click (`.rightMouseDown`), not for a
  ⌃-left-click, so the ⌃ set can be clicked (e.g. ⌃F3 Sort by Name).
- **Rationale**: Matches the spec ("as the key would", "focus stays"). The toolbar's
  "activate the panel first" approach was rejected because the spec requires focus to stay.
- **Alternatives considered**: Synthesizing a key event (rejected: fragile, bypasses
  validation); making the panel first responder before running (rejected: FR-007).

## R7. Enabled state

- **Decision**: The bar re-validates its buttons on `NSWindow.didUpdateNotification` of the main
  window (the same moment AppKit validates toolbar items) and whenever its slots change.
  Enabled = `canPerformIgnoringFocus(command)` (the existing rules shared with the menu and the
  toolbar: `.app` via `AppDelegate`, `.panel` via the window and the active panel).
  Unimplemented commands such as "Working Directories…" are already disabled there.
- **Rationale**: FR-008 requires the menu's rules; reusing the existing function adds no rule of
  its own. Twelve checks per window update are cheap (the toolbar already does the same).
- **Alternatives considered**: Observing the panel model (rejected: many sources of change —
  cursor, selection, focus, archive/server state).

## R8. Showing and hiding the bar and the command line

- **Decision**: Two new commands, `.toggleCommandLine` ("Show Command Line") and
  `.toggleFunctionKeyBar` ("Show Function Key Bar"), in the View menu, panel scope, no default
  chord, checkmarked by `validateMenuItem`. They are window commands that work regardless of
  focus (added to a small "focus-independent" set in `MainWindowController.canPerform`), so the
  command line can be hidden while it edits. The state is two Booleans in `UserDefaults`
  (`showCommandLine`, `showFunctionKeyBar`, default `true`); Settings → General binds them with
  `@AppStorage`, and the window observes `UserDefaults.didChangeNotification` and applies the
  values, so the menu, Settings and the window always agree (FR-017). Hidden views in the
  vertical `NSStackView` are detached, so the panels get the space (FR-019); the separator
  above each element hides with it.
- **Command line commands**: `focusCommandLine` and the four `insert…ToCommandLine` commands
  first set `showCommandLine = true` (which shows it) and then do their work (FR-021). Hiding
  the command line while it edits returns focus to the active panel.
- **Rationale**: Panel scope keeps the commands out of the viewer/find/compare menus (app-scope
  items appear in every context's View menu). Defaults keys without dots make them easy to bind.
- **Alternatives considered**: Storing them in `WindowLayout` (rejected: it is per-window state
  written with a delay; these are app preferences shown in Settings); `.app` scope (rejected:
  would show in the viewer's View menu).

## R9. Reading the system function-key setting

- **Decision**: Read `com.apple.keyboard.fnState` from the global preferences domain with
  `CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)` +
  `CFPreferencesCopyAppValue(…, kCFPreferencesAnyApplication)`; missing = `false` (the system
  default: media keys). Never write it (FR-025). Settings → Keyboard re-reads it on appear and
  on `NSApplication.didBecomeActiveNotification` (returning from System Settings, FR-023).
  "Open Keyboard Settings" opens `x-apple.systempreferences:com.apple.Keyboard-Settings.extension`
  through `NSWorkspace.open`.
- **Rationale**: The key is the documented-in-practice storage of "Use F1, F2, etc. keys as
  standard function keys" on current macOS; reading it needs no permission. The Function Keys
  sheet itself has no stable deep link, so the notice text tells the user where to click
  ("Keyboard Shortcuts… → Function Keys").
- **Alternatives considered**: IOKit HID parameters (rejected: lower level, same value);
  detecting media-key presses (rejected: the system consumes them, FR-025).

## R10. The one-time notice

- **Decision**: The decision logic is in the core: `FunctionKeyNotice` (Codable state
  `timesShown`, `suppressed`) with `shouldShow(standardFunctionKeys:)` = not standard and not
  suppressed and `timesShown < 2`, `recordShown()` and `suppress()`. Stored in UserDefaults as
  JSON (`functionKeyNotice`). The UI shows an `NSAlert` sheet on the main window shortly after
  it appears, with "Open Keyboard Settings" (default), "Don't Show Again" and "Close" (Esc).
  "Open Keyboard Settings" opens System Settings and counts as shown. Sheets queue, so the
  notice and the archive-edit offer from the last session do not collide.
- **Rationale**: FR-024 ("never on every launch", at most twice in total — SC-006) becomes a
  unit-tested rule.
- **Alternatives considered**: Show on every launch until dismissed (rejected by the spec);
  a banner in the window (rejected: more UI for a one-time message).

## R11. Look of the bar

- **Decision**: A view below the command line (separator above it), height of a small control
  row (~24 pt), twelve equal-width `NSButton`s in a horizontal stack (`.fillEqually`), bezel
  style `.recessed` with `showsBorderOnlyWhileMouseInside` (flat like the reference, hover and
  press feedback like macOS), small system font, key number in the secondary label color,
  command name in the primary color, no icon. Empty positions keep their
  place (disabled, title only "F10" in tertiary color, no tooltip). Accessibility label
  "F5, Copy" so the bar is usable with VoiceOver and with AX-driven GUI tests.
- **Rationale**: Familiar from Tandem/Total Commander (text-only buttons), native look,
  testable through Accessibility.
