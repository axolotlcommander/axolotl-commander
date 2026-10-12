# Research: Keyboard Schemes and Settings Export

## R1. Where the FR-001 chords go

**Decision**: append each chord at the **end** of its command's chord list in `CommandRegistry.all`.
`branchViewSelected` has no chord today, so ⌃⇧B becomes its only chord.

**Rationale**: a command's first menu-safe chord is the menu's key equivalent, so the menus stay as
they are (FR-003). `KeyMap` treats every chord in the list as a trigger. The existing
`noChordBoundTwice` test runs for every context and proves FR-002 against the registry.

**Checked against the registry** (none of these chords is used today in the panel context, or in
the app scope that every context includes):
- ⌃←, ⌃→ (Back / Forward are ⌃⌥←, ⌃⌥→);
- ⌥←, ⌥→;
- ⌃F1 (the volume menu is ⌥F1 / ⌃⌥F1), ⇧F2, ⇧F6;
- ⌃R, ⌃A, ⌃C, ⌃V, ⌃I, ⌃D (Disk Map is ⌃⇧D), ⌃F (Connect is also ⌃⇧F), ⌃N, ⌃J, ⌃P, ⌃⇧B;
- ⌥↩, ⌥⇧↩;
- ⌥Num+, ⌥Num−;
- ⌥F9;
- ⌃⇧↩ (⌃↩ is Insert Name), for the new command Insert Full Path.

**The panel's direct keys** (`PanelViewController.handleKey`, before the key map):
- Quick search takes characters typed without ⌃, ⌘ or ⌥. Every new chord carries ⌃ or ⌥, or is a
  function key, Return or an arrow.
- `handleMovement` with ⌥ takes only ↑, ↓, Home and End and returns false for the other keys, so ⌥←
  and ⌥→ reach the key map.
- ⌃↑ / ⌃↓ act only while a quick search runs.

A core test lists these direct chords and checks that no FR-001 chord is among them.

**AppKit**: `KeyChord(event:)` reads `charactersIgnoringModifiers`, so ⌃I, ⌃J and ⌃M arrive as
letters, not as Tab or Return. The GUI check confirms ⌃I and ⌃J.

**Alternatives considered**: putting the new chords first would change the menus, so it was
rejected.

## R2. Scheme representation

**Decision**:
- `public enum KeyScheme: String, CaseIterable, Sendable { case axolotl, classicCommander }`
  carries `changes: [Command: [KeyChord]]`.
- `chords(for:)` returns the change, or else the factory chords.
- Axolotl has no changes. Classic Commander holds the FR-006 table, with the clarifications:
  - ⌃T then ⌃⇧T, ⌃W then ⌃⇧W;
  - ⌘Q then ⌥F4.
- Later specs add entries to the dictionary.

**Rationale**: data, not code paths (FR-005). An enum keeps the set closed (no user-defined schemes,
out of scope), and the raw value is the stored and exported name.

**Alternatives considered**: a struct registry with string ids. It would be more open, but
nothing needs that openness.

## R3. Overrides on top of a scheme

**Decision**:
- `KeyBindings` gets `public var scheme: KeyScheme`.
  - `chords(for:)` = `overrides[c] ?? scheme.chords(for: c)`.
  - `isCustomized(c)` = an override exists **and** differs from `scheme.chords(for: c)`.
  - `source(for:)` returns `.user`, `.scheme` (the scheme has a change for the command) or
    `.defaults`.
  - `set` drops the override when it equals the scheme's chords (FR-011).
  - `reset` / `resetAll` remove overrides, which means "back to the scheme" (FR-014).
- **Switching the scheme never touches `overrides`** (FR-013). An override that happens to equal the
  new scheme is kept and only shown as the scheme's (`isCustomized` is false). This is the
  2026-10-12 clarification.
- **Encoding**:
  - `KeyBindings`' Codable form stays the overrides dictionary, so `keys.bindings` from 0.3.x
    decodes unchanged (FR-012, SC-006).
  - Decoding no longer drops overrides equal to the factory chords. 0.3.x never stored such
    overrides, and under another scheme they are meaningful.
  - `init(overrides:)` keeps normalizing against its scheme for direct construction.
  - The scheme is stored separately under `keys.scheme` and exported in the Keyboard section.
- **`KeyMap(context:bindings:)`** is unchanged:
  - customized commands claim their chords first, so a user's chord wins over a scheme chord
    (FR-010);
  - the other commands follow in declaration order;
  - schemes are collision-free by test (FR-007), so the order among them does not matter.
- **Conflicts** (`conflicts(_:for:)`) already use `chords(for:)`, so they see the effective map
  (FR-015).

**Alternatives considered**: normalizing overrides against the scheme on every switch. It would
silently drop user changes that equal one scheme, which breaks FR-013, so it was rejected.

## R4. ⌃⇥ in Classic Commander

**Problem**: AppKit uses ⌃⇥ / ⌃⇧⇥ for key-view cycling before the panel's `keyDown` sees them. Today
`MainWindowController.interceptKey` catches ⌃⇥ only when the key map says `.focusCommandLine`.

**Decision**: generalize the intercept. While a panel has focus, a ⌃⇥ / ⌃⇧⇥ chord that the panel
key map binds is performed on the panel (Next Tab / Previous Tab in Classic Commander, Focus Command
Line in Axolotl). While the command line edits, the existing handling stays: ⌃↑ / ⌃↓ walk the
history, and the focus and insert commands run.

## R5. Function key bar names

The bar already reads the key map. The bar names come from `barTitle` (the title without "…") or
from `shortTitles`. New entries:
- `barTitles[.quit] = "Quit"` (the title is "Quit Axolotl Commander");
- `shortTitles[.newSymbolicLink] = "Link"`;
- `shortTitles[.viewWith] = "View With"` is not needed, because `barTitle` already drops "…".

Brief, Detailed, Rename, Unpack and Compare need nothing new.

## R6. Settings file format

**Decision**: JSON, written with `JSONEncoder` `[.prettyPrinted, .sortedKeys]`, so key order is
stable (FR-019). [contracts/settings-file.md](contracts/settings-file.md) defines it. Its parts:
- the header: `format = "axolotl-commander-settings"`, `formatVersion = 1`, `appVersion`,
  `exported` (ISO 8601);
- one top-level object per section, **embedded as JSON** (not base64 data), so the file stays
  readable and editable.

**Sections**:

| Section | Stored today as | Applies by |
|---|---|---|
| `keyboard` | `keys.scheme` + `keys.bindings` | `KeyMaps.reload()` |
| `preferences` | plain keys, plus the `comparison` JSON blob | KVO / `UserDefaults.didChangeNotification` (already observed), `AppSettings.reload()` |
| `appearance` | `appearance` JSON blob (mark color, highlighting) | `AppSettings.reload()` + `.appearanceChanged` |
| `hotPaths` | `hotPaths` JSON blob | `AppSettings.reload()` |
| `userMenu` | `userMenu.items` (`UserMenuStore`) | post `UserMenuDefaults.didChange` |
| `connections` | `connections` JSON blob | `AppSettings.reload()` |
| `toolbar` | `NSToolbar Configuration MainToolbar` (plist dictionary) | `toolbar.setConfiguration(_:)` on each main window |

**Preference keys** (the allowlist; spec 011 adds its own):
- `showCommandLine`, `showFunctionKeyBar`;
- `terminal.bundleID`, `editor.bundleID`;
- `viewer.encoding`, `viewer.wrap`, `viewer.highlight`, `viewer.fontSize`;
- `pathBar.style`, `pathBar.showIcons`;
- `size.display`, `size.units`;
- `volumeBar.showHome`, `volumeBar.showICloud`, `volumeBar.showNetwork`, `volumeBar.showServers`;
- `compare.whitespace`, `compare.ignoreCase`, `compare.differencesOnly`, `compare.fontSize`;
- `checksum.algorithm`;
- `links.relativePath`;
- `ssh.extraArguments`;
- `comparison`.

**Never exported** (session, history, dialog memory, notices):
- `settings.tab`, `window.layout`;
- `panel.*.path`, `panel.*.sort`;
- `recentPaths`, `commandLine.history`, `find.history.*`, `find.options`;
- `batchRename.last`, `changeCase.last`;
- `functionKeyNotice`;
- every key that is not in the catalog.

**Rationale**: an allowlist, not a blocklist. A key added later is not exported until someone
adds it to the catalog, so a secret can never leak by accident (SC-005). Passwords live in the
Keychain, and `ConnectionProfile` has no password field.

**Alternatives considered**:
- `UserDefaults.dictionaryRepresentation()` dumps everything, including system and session keys;
  rejected.
- A property-list file is not as readable or as easy to edit as JSON; rejected.

## R7. Validation and the import report

**Decision**: the core validates each entry and never guesses:
- **Preferences**: each key has a kind:
  - `bool`;
  - `string`, optionally with a set of allowed values;
  - `number` with a closed range;
  - `stringArray`;
  - `json`, with a decode check against the Codable type.

  Unknown keys, wrong types and out-of-range values are skipped and reported.
- **Keyboard**:
  - an unknown scheme is reported, and the current scheme is kept;
  - per command, an unknown command name or any malformed chord skips that command's entry.
- **Lists** (`connections`, `userMenu`): each element is decoded alone. A bad element is skipped and
  reported, and the rest is applied. The section replaces the current list as a whole (out of scope:
  merging).
- **Whole-value sections** (`appearance`, `hotPaths`, `toolbar`): applied if they decode, else
  skipped and reported.
- **Unknown top-level sections** are listed as skipped.
- **Header**:
  - a missing or wrong `format` → error "not a settings file", nothing changes;
  - invalid JSON → error, nothing changes;
  - `formatVersion` > 1 → warning, the known parts are applied (FR-022).
- The report has the applied sections plus the skipped entries, each with a reason.

All validation happens before any write, so a damaged file changes nothing (SC-007).

## R8. Applying live

The core writes only to the injected `UserDefaults` and returns the sections it changed. The app
then refreshes what caches those values:
- `KeyMaps.reload()` reads the scheme and the overrides again and calls the existing update path,
  which rebuilds the maps and the menus and posts `didChange`;
- `AppSettings.shared.reload()` loads its JSON values again, which fires the `@Observable` updates
  and `.appearanceChanged`;
- `UserMenuDefaults.didChange` is posted;
- the toolbar configuration is set on each main window;
- plain preferences need nothing more, because `@AppStorage` and the existing
  `UserDefaults.didChangeNotification` observers pick them up.

## R9. UI

- **Commands**: `exportSettings` ("Export Settings…") and `importSettings` ("Import Settings…"), both
  app scope, in the app menu right after "Settings…". They have no chord, but they can be bound in
  Settings → Keyboard.
- **Export**: an `NSSavePanel` with the default name "Axolotl Commander Settings.json".
- **Import**:
  1. an `NSOpenPanel` limited to JSON files;
  2. the core reads the file; an error shows an alert and stops;
  3. otherwise an `NSAlert` with an accessory view of checkboxes, one per section present and all
     checked, the newer-version warning when needed, and the buttons "Import" / "Cancel";
  4. apply, then the reload;
  5. a summary alert: what was applied and, if anything was skipped, the list of skipped entries.
- **Sheet guard**: Import Settings… is disabled while any main window has an attached sheet.
- **Settings → General** gets the two buttons, which run the same flows.
- **Settings → Keyboard**:
  - a "Key scheme" picker above the table ("Axolotl", "Classic Commander");
  - a source column or badge per command: "Default", "Scheme", "Changed";
  - a chord another command took is shown as lost, with the name of the command that uses it
    (US3-1);
  - Reset and Reset All… go back to the scheme; Reset All's alert text says so;
  - a footer hint about the Mission Control shortcuts in System Settings.

## R10. Risks

- **Mission Control and display utilities swallow ⌃←, ⌃→ and ⌃↓, and some ⌃⇧ chords.** This is
  documented in the hint and the assumptions. The GUI test sends those chords only through menu
  items or checks the key map in unit tests.
- **`toolbar.setConfiguration(_:)` with a dictionary from another macOS version.** If an identifier
  is unknown, AppKit ignores it. Only an exact-type mismatch is skipped.
