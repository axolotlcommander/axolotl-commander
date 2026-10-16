# Implementation Plan: Shortcut Conflict Checks

**Branch**: `034-shortcut-conflicts` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (unit tested), `Sources/CommanderCore/ShortcutCheck.swift` (NEW):
  - `FixedKey`: the keys no command can get. Menu items outside the command list (Close Window ⌘W,
    Minimize ⌘M, Minimize All ⌥⌘M, Hide ⌘H, Undo ⌘Z, Redo ⇧⌘Z), macOS keys that never reach apps (⌘Tab,
    ⇧⌘Tab, ⌥⌘Esc, ⌃⌘Q, ⇧⌘Q) and, in the Panels context, the movement keys (↑ ↓ ← → Page Up, Page Down,
    Home, End, alone or with ⇧) (R1, R2).
  - `SystemShortcut`: a macOS shortcut (feature, chord, on/off). `SystemShortcuts.defaults` is the built-in
    list; `SystemShortcuts.current(from:)` applies the user's entries of the system preference
    `com.apple.symbolichotkeys` / `AppleSymbolicHotKeys` (`enabled`, `value.parameters` = character code,
    virtual key code, modifier mask); missing entries keep the default, malformed ones are ignored, entries
    without a key are dropped (R3, R4).
  - `ShortcutCheck.check(_:for:context:bindings:userMenu:typingToCommandLine:system:)` → `.clean`,
    `.refused(Refusal)` or `.warnings([Warning])`. Refusals: fixed menu item, macOS key, panel movement key,
    plain character in the panel (typed into the command line or quick search). Warnings: commands that lose
    the key, User Menu items, a macOS shortcut that is on, ⌥ + character (no quick search start).
  - `ShortcutCheck.problem(_:context:typingToCommandLine:system:)` → the reason an assigned chord cannot run
    (for the row marks): a refusal reason or a macOS shortcut that is on.
  - `ShortcutCheck.reasons(...)` for the User Menu editor: the same reasons, never refusing.
- **Settings → Keyboard** (`KeyboardSettings.swift`): the recorded chord goes through the check; a refusal
  shows its message (no change); warnings show every reason, "Move to This Command" when commands lose the
  key, otherwise "Assign Anyway", "Open Keyboard Settings" when macOS takes the key, and "Cancel"; the hint
  while recording; a warning mark with a tooltip next to every chord that cannot run; the macOS list is read
  on appear and on `NSApplication.didBecomeActiveNotification`; the two captions about macOS keys go.
- **User Menu editor** (`UserMenuSettings.swift`): its warnings gain the reasons of `ShortcutCheck.reasons`.
- **Wording** (`ShortcutCheckText.swift`, NEW, AppKit target): localized messages for refusals, warnings,
  marks and macOS feature names with their System Settings section.
- Czech strings; CHANGELOG entries under Unreleased; version bump minor (0.10.0) when the PR is prepared.

## Technical Context

Swift 6, AppKit + SwiftUI settings, SwiftPM; tests with Swift Testing in `Tests/CommanderCoreTests`. The app
is not sandboxed; the system preference is read with `CFPreferencesCopyAppValue` (read only).

## Constitution Check

| Principle | Status |
|---|---|
| Data safety | ✅ No file operations. The macOS preference is only read; nothing in System Settings changes. Existing shortcuts are never removed by the checks. |
| Clean room | ✅ The reference documents nothing here; Mac conventions only. |
| Keyboard first | ✅ Recording, the warning buttons and the hint all work from the keyboard; no key loses its function silently. |
| Testable core | ✅ Fixed keys, text-key rule, macOS list and its merge, and the combined check in CommanderCore with tests. |
| Incremental | ✅ Core → Keyboard settings → marks → User Menu → strings, each committed. |

## Research

- **R1** Main menu items with keys that are not commands: `MainMenuBuilder` adds Undo ⌘Z, Redo ⇧⌘Z, Hide
  ⌘H, Minimize ⌘M, Close Window ⌘W; AppKit adds Minimize All ⌥⌘M to the Window menu. These are refused in
  every context. ⇧⌘Q (Log Out) belongs to the Apple menu and is refused with the other macOS keys.
- **R2** Keys handled before the key map: only the panel has them — `handleMovement` takes ↑ ↓ ← → Page Up,
  Page Down, Home, End without modifiers or with ⇧ only; ⌥↑ / ⌥↓ / ⌥Home / ⌥End yield to a bound command
  (not refused). With "Typing goes to the command line" off, `handleQuickSearch` takes every character
  without ⌃ ⌘ ⌥ (⇧ included) before the key map; with it on, `PanelTyping.route` appends such characters to
  the command line whether bound or not, and lets only a bound ⌥ + character through. So plain characters
  are refused with either setting (clarification).
  Viewer, Find and Compare look up their key map first; their own keys (hex/table/diff scrolling, media
  controls, Esc in the Find form) are fallbacks or depend on the focus, so nothing is refused there.
- **R3** `AppleSymbolicHotKeys` stores only entries the user changed (others keep the macOS default), each as
  `{ enabled = 0|1; value = { parameters = (char, keyCode, modifierMask); type = standard } }`. Char 65535
  means no character (use the key code). Mask bits: ⇧ 0x20000, ⌃ 0x40000, ⌥ 0x80000, ⌘ 0x100000; 0x800000
  (fn) marks arrows and F-keys and is ignored.
- **R4** Defaults (id: chord): 7 ⌃F2 menu bar, 8 ⌃F3 Dock, 9 ⌃F4 active window, 10 ⌃F5 toolbar, 11 ⌃F6
  floating window, 12 ⌃F7 Tab moves focus, 13 ⌃F1 keyboard navigation, 57 ⌃F8 status menus, 27 ⌘` next
  window, 28 ⇧⌘3, 29 ⌃⇧⌘3, 30 ⇧⌘4, 31 ⌃⇧⌘4, 184 ⇧⌘5 screenshots, 32 ⌃↑ Mission Control, 33 ⌃↓
  application windows, 79 ⌃← / 81 ⌃→ spaces, 36 F11 Show Desktop, 52 ⌥⌘D Dock hiding, 60 ⌃Space / 61 ⌃⌥Space
  input sources, 64 ⌘Space Spotlight, 65 ⌥⌘Space Finder search window, 98 ⇧⌘/ Help menu, 162 ⌥⌘F5
  accessibility controls. Mission Control F3 and Launchpad F4 are media keys of the function row, already
  covered by the F1–F12 (fn) note, so they are not in the list (clarification).
- **R5** Context labels: a command's scope names its context; app-scope commands are "All windows". User
  Menu items count in the Panels context only (they run from the panel).

## Project Structure

```text
Sources/CommanderCore/ShortcutCheck.swift                NEW fixed keys, macOS list, check
Sources/AxolotlCommander/ShortcutCheckText.swift         NEW localized wording
Sources/AxolotlCommander/KeyboardSettings.swift          check, warnings, buttons, hint, marks
Sources/AxolotlCommander/UserMenu/UserMenuSettings.swift extra warnings
Resources/Localizable.xcstrings                          Czech
Tests/CommanderCoreTests/ShortcutCheckTests.swift        NEW
```
