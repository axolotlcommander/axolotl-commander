# Quickstart: Validating the Function Key Bar

**Feature**: [spec.md](spec.md) | **Contract**: [contracts/function-key-bar.md](contracts/function-key-bar.md)

## Prerequisites

- macOS 15+, Swift 6.2.
- The test copy of the app (own bundle id `cz.acidek.axolotlcommander.gtest`), never the
  installed app. Both panels pointed to a scratch folder created for the test (project rule:
  no operations on real data).

## Automated

```sh
swift build 2>&1 | grep -E "warning|error"   # must print nothing
swift test --filter "FunctionKeyBar|FunctionKeyNotice|KeyMap"
swift test                                   # whole suite green, < 10 s
```

## GUI scenarios (test copy, scratch folder in both panels)

| # | Steps | Expected |
|---|---|---|
| Q1 | Fresh defaults, launch | Bar visible below the command line; F1 Help … F9 User Menu, F10/F11 empty, F12 Disconnect; View → both "Show …" items checked. |
| Q2 | Click "F7 New Folder", type a name, Return | Folder created in the active panel; focus still in the panel (AX focused element is the panel table). |
| Q3 | Cursor on a file, click "F3 View", close the viewer | Same file under the cursor, panel focused. |
| Q4 | Cursor on "..": inspect F2/F3/F4 | Grayed out (AX `enabled` false), click does nothing. |
| Q5 | Hold ⌥ | F5 Pack, F6 Unpack, F7 Find Files; release → F5 Copy again. Hold ⇧: F4 New File, F7 Go to Folder, F8 Delete. |
| Q6 | Hold ⌥ and click F5 on a file | Pack dialog for the active panel. |
| Q7 | Settings → Keyboard: bind F2 to Compare Panels | Bar shows "F2 Compare" at once; click compares. Reset afterwards. |
| Q8 | Resize the window to the minimum width | All twelve buttons visible, short names or key only, no wrapping; tooltip shows the full name. |
| Q9 | View → Show Function Key Bar; quit; relaunch | Bar hidden, panels taller; stays hidden after relaunch; right-click on the bar (after showing it) → "Hide Function Key Bar" hides it. |
| Q10 | View → Show Command Line off; press ⌃Tab | Command line appears and has focus; the setting is "shown" again. |
| Q11 | Settings → General toggles | View menu checkmarks follow, and vice versa. |
| Q12 | System setting "standard function keys" off (this machine's default), first launch | Notice sheet with "Open Keyboard Settings", "Don't Show Again", "Close". Close → shown on the next launch once more, then never. "Don't Show Again" → never. |
| Q13 | Settings → Keyboard | Line saying function keys need `fn`; "Open Keyboard Settings" opens System Settings → Keyboard. The app never writes `com.apple.keyboard.fnState` (check `defaults read -g com.apple.keyboard.fnState` before/after: unchanged). |
| Q14 | Dark mode on/off | Texts follow the appearance; no icons on the buttons. |

Notes:

- The "system setting on" path (no notice) is covered by `FunctionKeyNoticeTests`; the GUI test
  must not change the system setting.
- Commands with ⌃⇧ / ⌃⌥ may be grabbed by display-manager software on the test machine; check
  those sets by holding the modifiers and reading the labels through Accessibility, not by
  pressing the full chords.
