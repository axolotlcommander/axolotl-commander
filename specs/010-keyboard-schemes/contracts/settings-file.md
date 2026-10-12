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
