# Data Model: Function Key Bar and Hideable Command Line

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Function key slot (core, computed)

| Field | Type | Notes |
|---|---|---|
| `number` | Int 1…12 | Position in the bar, left to right. |
| `chord` | `KeyChord` | `.function(number)` + the shown modifiers. |
| `command` | `Command?` | `KeyMap.command(for: chord)`; nil = empty slot. |

- Derived for a `(KeyMap, KeyChord.Modifiers)` pair; never stored.
- Modifiers are only ⇧⌃⌥⌘ (`KeyChord.Modifiers`); `fn`, Caps Lock and numeric pad are not part
  of the set.
- Validation: exactly twelve slots; a slot's command, if any, is in scope `.app` or `.panel`
  (guaranteed by the panel `KeyMap`).

## Command presentation (core strings + UI)

| Field | Source | Notes |
|---|---|---|
| `title` | `CommandSpec.title` (English) → `localizedTitle` | Full name; the bar drops a trailing "…". |
| `shortTitle` | `CommandRegistry.shortTitle(command)` → localized | Optional; only for long names. |
| `symbolName` | `CommandRegistry.symbolName(command)` | Optional SF Symbol name; shared with the toolbar. |
| `tooltip` | UI | Full localized title + " (" + chord description + ")". |
| `enabled` | `MainWindowController.canPerformIgnoringFocus` | Same rules as the menu item / toolbar. |

Label variants in order of preference (R3): full → short → short truncated → key only.

## Window chrome settings (UserDefaults)

| Key | Type | Default | Written by |
|---|---|---|---|
| `showCommandLine` | Bool | `true` | View menu, Settings → General, command-line commands (set to true) |
| `showFunctionKeyBar` | Bool | `true` | View menu, Settings → General, bar context menu |

- A missing key means `true` (fresh installation, FR-002/FR-019).
- The main window applies both on launch and on `UserDefaults.didChangeNotification`.

## Function key notice state (core, UserDefaults JSON `functionKeyNotice`)

| Field | Type | Default |
|---|---|---|
| `timesShown` | Int | 0 |
| `suppressed` | Bool | false |

Transitions:

```text
            shouldShow(standard: false) && !suppressed && timesShown < 2
 launch ──────────────────────────────────────────────────────────────▶ notice shown
                                                                         │ recordShown(): timesShown += 1
               ┌────────────── "Close" / Esc / "Open Keyboard Settings" ─┤
               ▼                                                         │ "Don't Show Again"
   next launch may show it once more (timesShown < 2)                    ▼
                                                                  suppress(): suppressed = true
standard function keys on  ──▶ never shown (state unchanged)
```

- At most two showings in total (SC-006); never after `suppressed`.
- The system setting itself is read-only input (`standardFunctionKeys: Bool`).
