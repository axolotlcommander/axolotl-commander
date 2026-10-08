# Contract: Function Key Bar

**Feature**: [../spec.md](../spec.md) | **Plan**: [../plan.md](../plan.md)

## Core API (`CommanderCore`)

```swift
public enum FunctionKeyBar {
    /// Number of buttons.
    public static let count = 12

    /// The command each of F1…F12 runs with exactly `modifiers` held, in order; nil = empty.
    public static func slots(in map: KeyMap, modifiers: KeyChord.Modifiers) -> [Command?]
}

extension CommandRegistry {
    /// English short name for the bar when the title is too long; nil = use the title.
    public static func shortTitle(_ command: Command) -> String?
    /// SF Symbol name of the command (bar and toolbar); nil = no icon.
    public static func symbolName(_ command: Command) -> String?
}

extension Command {
    // View menu, panel scope, no default chord, focus-independent:
    case toggleCommandLine      // "Show Command Line"
    case toggleFunctionKeyBar   // "Show Function Key Bar"
}

public struct FunctionKeyNotice: Codable, Equatable, Sendable {
    public var timesShown: Int        // 0
    public var suppressed: Bool       // false
    public static let maxShowings = 2
    public func shouldShow(standardFunctionKeys: Bool) -> Bool
    public mutating func recordShown()
    public mutating func suppress()
}
```

Guarantees checked by tests:

1. `slots(in: map, modifiers: m)[n - 1] == map.command(for: KeyChord(.function(n), m))` for every
   n in 1…12 and every m in the 8 combinations of ⇧⌃⌥ (and with ⌘), for the factory map and
   for a map with user overrides (SC-002).
2. Factory plain set: F1 help, F2 rename, F3 view, F4 edit, F5 copy, F6 move, F7 makeDirectory,
   F8 delete, F9 userMenu, F10 nil, F11 nil, F12 disconnect.
3. A command with several F-key chords appears in every matching slot.
4. Every `symbolName` resolves to an existing SF Symbol (test imports AppKit), and every command
   with a factory F-key chord in the panel map has a symbol.
5. `shortTitle` is never longer than the title; titles and short titles of the new commands are
   in `Localizable.xcstrings` with a Czech translation.
6. `FunctionKeyNotice`: shown at most `maxShowings` times, never after `suppress()`, never when
   `standardFunctionKeys` is true.

## UI behavior (`AxolotlCommander`)

| Trigger | Result |
|---|---|
| Main window opens, fresh settings | Bar and command line visible; View shows both items checked. |
| `.flagsChanged` in the key main window | Bar shows `slots(in: KeyMaps.panel, modifiers: held)`. |
| Window becomes key / resigns key | Bar re-reads `NSEvent.modifierFlags`. |
| `KeyMaps.didChange` | Bar recomputes slots, titles, icons, tooltips. |
| Window update | Each button enabled = `canPerformIgnoringFocus(command)`. |
| Click on a non-empty, enabled button | `performFromBar(command)`; first responder unchanged. |
| Click on an empty or disabled button | Nothing. |
| Right click on the bar | Menu with "Hide Function Key Bar". ⌃-left-click is a normal click. |
| View → Show Function Key Bar / Show Command Line | Toggles `showFunctionKeyBar` / `showCommandLine`. |
| Settings → General toggles | Same keys; window updates immediately. |
| `.focusCommandLine`, `.insert…ToCommandLine` with the command line hidden | `showCommandLine = true`, then the command runs. |
| Launch with fn keys not standard and `shouldShow` | Sheet: "Open Keyboard Settings" / "Don't Show Again" / "Close". |
| Settings → Keyboard appears or app becomes active | fn state line re-read; button opens System Settings → Keyboard. |

Accessibility: each button's label is "F<n>, <full localized title>" (empty slot: "F<n>"), role
button, so AX-driven GUI tests can find and press it.
