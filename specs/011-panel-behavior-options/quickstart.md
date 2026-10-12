# Quickstart: Panel Behavior Options

## Automated

```sh
swift build 2>&1 | grep -E "warning|error"   # nothing
swift test                                     # all green, PanelBehaviorTests included
```

## GUI check (test copy only)

Prerequisites:
- the test copy of the app with its own bundle id;
- both panels on scratchpad test folders, each with a few files and subfolders;
- browse only. Never press Return on a command line that changes files; use `ls` or `echo`, or clear
  the line with Esc.

1. **Space**:
   - General → Panels → Space moves the cursor down off;
   - Space on a file marks it and the cursor stays; Space again unmarks it;
   - switch it back on and Space moves down.
2. **Typing**:
   - switch Typing goes to the command line on;
   - type `echo ` in a panel: the line shows it and ↓ moves the panel cursor;
   - ⌃↩ adds the cursor name;
   - Backspace removes a character, Esc clears the line;
   - with the line empty, Backspace goes to the parent folder;
   - ⌥ + a letter starts quick search;
   - hide the command line (View menu), type a letter, and the line appears;
   - switch the setting off and letters start quick search again.
3. **Arrows**:
   - switch ⌃← / ⌃→ change the panel the arrow points to on;
   - from the left panel on a folder: Go → Open in Right Panel opens it on the right and the focus
     stays left;
   - Open in Left Panel makes the left panel open the right panel's cursor item;
   - with the right cursor on "..", the left panel opens the right panel's folder;
   - switch it off and check today's behavior.
4. **Volumes**:
   - switch Volume buttons… on;
   - right panel on a test folder, left panel elsewhere on another volume, if one is mounted, or use
     the startup disk:
     - click the startup disk button above the left panel: it opens the right panel's folder;
     - click it again: the root;
   - check the ⌥F1 menu the same way;
   - switch it off and a volume button opens the root.
5. **Settings**:
   - Keyboard shows the note under the key scheme;
   - export the settings to the scratchpad and check the four `panel.*` keys in the file.
