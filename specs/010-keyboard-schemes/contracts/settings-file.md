# Contract: Settings File

One UTF-8 JSON object, pretty-printed with sorted keys. Default file name:
"Axolotl Commander Settings.json".

```json
{
  "appVersion" : "0.4.0",
  "appearance" : { "highlights" : [ … ], "markColor" : "red" },
  "connections" : [
    { "encoding" : "auto", "endpoint" : { "host" : "example.org", "proto" : "sftp", "user" : "me" },
      "id" : "…uuid…", "initialPath" : "/srv", "name" : "Example", "passiveMode" : true }
  ],
  "exported" : "2026-10-12T20:15:00Z",
  "format" : "axolotl-commander-settings",
  "formatVersion" : 1,
  "hotPaths" : { "slots" : [ … ] },
  "keyboard" : {
    "bindings" : { "rename" : [ "F2", "shift+F6" ] },
    "scheme" : "classicCommander"
  },
  "preferences" : {
    "checksum.algorithm" : "sha256",
    "comparison" : { "compareDate" : true, … },
    "pathBar.style" : "breadcrumbs",
    "showFunctionKeyBar" : true,
    "viewer.fontSize" : 13
  },
  "toolbar" : { "TB Display Mode" : 2, "TB Item Identifiers" : [ … ], … },
  "userMenu" : [ … ]
}
```

## Rules

- **Header**:
  - `format` must be exactly `"axolotl-commander-settings"`, else the file is rejected;
  - `formatVersion` is an integer; 1 for this spec; a greater value means "newer", and the known
    parts are imported with a warning;
  - `appVersion` and `exported` are informational.
- **Sections**: every section is optional. An absent section is not offered on import and changes
  nothing.
- **keyboard**:
  - `scheme` is a `KeyScheme` raw value;
  - `bindings` uses the same form as `keys.bindings`: command raw value → chord storage strings;
    `[]` = no shortcut.
- **preferences**: only catalog keys, with values of the catalog kind. `json`-kind values are
  embedded objects.
- **List sections** (`connections`, `userMenu`): arrays whose elements use their type's Codable form.
- **Whole-value sections** (`appearance`, `hotPaths`): the type's Codable form.
- **toolbar**: the AppKit toolbar configuration dictionary, converted to JSON.
- **Never present**:
  - passwords, passphrases, keys, tokens;
  - session state (folders, tabs, window frames, history);
  - dialog memory, notices.

  The exporter writes only catalog keys, so these cannot appear.
- **Determinism**: two exports of the same settings differ only in `exported` and `appVersion`.

## Compatibility across versions

Settings files must keep working while the app grows. Tests enforce these rules:

- **Newer app, older file.** Every later version imports a format-1 file without skipping anything
  and keeps every value. `SettingsFormatCompatibilityTests` imports the frozen
  `Tests/CommanderCoreTests/Fixtures/settings-format-1.json`, which has every catalog key, every
  command name of its time and every section filled. The fixture is never edited.
- **Never renamed:** UserDefaults keys, command names, scheme names, section names and the Codable
  fields of the sections. New fields are optional with a default, so old files still decode.
- **New preferences are exported.** A new UserDefaults key goes into `SettingsCatalog.app`, or into
  `SettingsCatalog.notExported` when it is session state. `SettingsCatalogCoverageTests` scans the
  sources and fails for a key that is in neither list.
- **Older app, newer file.** The older app imports what it knows. It reports the unknown parts and
  warns when `formatVersion` is higher.
- **Incompatible change.** Raise `SettingsArchive.formatVersion`, convert older files in
  `SettingsArchive.read`, and add a frozen fixture for the new format, keeping the old one.
