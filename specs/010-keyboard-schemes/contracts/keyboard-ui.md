# Contract: Keyboard and Settings Transfer UI

## Commands (registry)

| Command | Title | Menu | Scope | Chords |
|---|---|---|---|---|
| exportSettings | Export Settings… | app, after Settings… | app | none |
| importSettings | Import Settings… | app, after Export Settings… | app | none |

Import Settings… is disabled while a main window shows a sheet.

## Settings → Keyboard

- **"Key scheme:" picker** with "Axolotl" and "Classic Commander" (cs: "Klasický Commander").
  Changing it applies at once to the key maps, menus, function key bar and the table.
- **Each command row shows its source**: "Default", "Scheme" or "Changed" (cs: "Výchozí",
  "Schéma", "Změněno").
- **A chord that another command took** is shown as not active, with the name of the command that
  uses it.
- **Reset** returns the command to the selected scheme. **Reset All…** asks "Reset all shortcuts to
  the selected key scheme?" and keeps the scheme.
- **Hint** under the table: "⌃←, ⌃→, ⌃↑ and ⌃↓ reach the app only when the Mission Control
  shortcuts for them are turned off in System Settings → Keyboard → Keyboard Shortcuts."

## Settings → General

The buttons "Export Settings…" and "Import Settings…" run the same flows as the menu commands.

## Export flow

1. A save panel with the default name "Axolotl Commander Settings.json", file type JSON.
2. The file is written. An error shows an alert with the reason.

## Import flow

1. An open panel, JSON files only.
2. An unreadable, damaged or foreign file shows the alert "This file is not an Axolotl Commander
   settings file." Nothing changes.
3. A confirmation alert:
   - the message "Import settings?";
   - the text "The checked parts replace your current settings.";
   - plus the line "The file comes from a newer version; parts this version does not know are
     skipped." when it applies;
   - one checkbox per section present, all checked: Keyboard, Preferences, Appearance, Hot Paths,
     User Menu, Saved Servers, Toolbar;
   - the buttons "Import" and "Cancel". "Import" is disabled when nothing is checked.
4. Apply and reload live.
5. A summary alert:
   - "Settings imported.";
   - if anything was skipped, the line "Skipped:" with one line per item (section, item,
     reason), shown in a scrollable text view when it is long.
