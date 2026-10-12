# Contract: Behavior Settings UI

## Settings → General → "Panels"

| Toggle (en) | Default | Caption (en) |
|---|---|---|
| Space moves the cursor down | on | Off: Space marks the item and the cursor stays on it. |
| Typing goes to the command line | off | Characters typed in a panel go to the command line; ⌥ + a character starts quick search. |
| ⌃← / ⌃→ change the panel the arrow points to | off | Off: the item always goes to the other panel. |
| Volume buttons open the other panel's folder or the last folder used there | off | Off: a volume button always opens the volume root. |

The section sits after the command line / function key bar section. Czech texts are in
`Localizable.xcstrings`.

## Settings → Keyboard

Under the key scheme picker, a caption: "Space, typing into the command line, ⌃← / ⌃→ and the volume
buttons are set in General → Panels."

## Keys in a panel with "Typing goes to the command line" on

| Key | Line empty | Line has text |
|---|---|---|
| character (no ⌘⌃⌥, ⇧ ok) | appended to the line | appended to the line |
| ⌥ + character | starts quick search | starts quick search |
| Return | opens the item (today) | runs the line |
| Backspace | parent folder (today) | removes the last character |
| Esc | today's Esc | clears the line |
| Space | marks (today) | appends a space |
| arrows, Page Up/Down, Home/End, Insert, F-keys, chords with a command | today | today |

During quick search every key behaves as in quick search today.
