# Data Model: Keyboard Schemes and Settings Export

## Core (`CommanderCore`)

### KeyScheme (new, `KeyScheme.swift`)

| Member | Type | Notes |
|---|---|---|
| cases | `axolotl`, `classicCommander` | `String` raw values. These are stored in `keys.scheme` and exported. |
| `changes` | `[Command: [KeyChord]]` | Axolotl: empty. Classic Commander: the FR-006 table (see below). |
| `chords(for:)` | `[KeyChord]` | `changes[command] ?? CommandRegistry.spec(command).chords` |

Classic Commander `changes` (in chord order; the first menu-safe chord is the menu's):

| Command | Chords |
|---|---|
| newTab | ⌃T, ⌃⇧T |
| closeTab | ⌃W, ⌃⇧W |
| nextTab | ⌃⇥, ⌃⇧PgDn |
| previousTab | ⌃⇧⇥, ⌃⇧PgUp |
| focusCommandLine | ⌃↓ |
| goToLinkTarget | (none) |
| restoreSelection | Num/ |
| openTerminal | ⌃/ |
| viewModeDetailed | ⌃F2, ⌃⌥1 |
| changeAttributes | (none) |
| disconnect | ⌃⇧F, F12 |
| connectToServer | ⌘K, ⌃F, ⌃N |
| newSymbolicLink | ⌃⇧F5, ⌃⌘L |
| saveSelection | (none) |
| viewWith | ⌥F3, ⌃⇧F3 |
| quickLook | ⌘Y |
| quit | ⌘Q, ⌥F4 |

**Invariant (tested)**: for every scheme and every context, no chord belongs to two commands
(FR-007).

### ChordSource (new)

`enum ChordSource { case defaults, scheme, user }`: where a command's effective chords come from.

### KeyBindings (changed, `Command.swift`)

| Member | Change |
|---|---|
| `scheme: KeyScheme` | new, default `.axolotl`; not part of the Codable form |
| `overrides` | unchanged meaning and encoding |
| `init(scheme:overrides:)` | new; drops overrides equal to `scheme.chords(for:)`. `init(overrides:)` = Axolotl. |
| `init(from:)` | keeps all valid overrides (no normalization); unknown commands and bad chords are skipped as before |
| `chords(for:)` | `overrides[c] ?? scheme.chords(for: c)` |
| `isCustomized(_:)` | `overrides[c] != nil && overrides[c] != scheme.chords(for: c)` |
| `source(for:)` | `.user` if customized; else `.scheme` if `scheme.changes[c] != nil`; else `.defaults` |
| `set(_:for:)` | removes the override when the chords equal the scheme's |
| `reset`, `resetAll` | unchanged (back to the scheme) |
| `conflicts(_:for:)` | unchanged code; sees the scheme through `chords(for:)` |
| `factory` | `KeyBindings()` = Axolotl, no overrides |

State transitions:
- **Switch the scheme**: assign `scheme`; `overrides` is untouched.
- **Reset**: remove the override.
- **Set**: store the override, or remove it when it equals the scheme's chords.

### JSONValue (new, `Settings/JSONValue.swift`)

`indirect enum JSONValue: Codable, Hashable, Sendable`:
- `null`;
- `bool(Bool)`;
- `number(Double)`;
- `string(String)`;
- `array([JSONValue])`;
- `object([String: JSONValue])`.

It also has helpers to convert to and from `Data` and from `UserDefaults` plist values (Bool,
NSNumber, String, [String], Dictionary).

### PreferenceKind / PreferenceSpec (new)

| Kind | Valid value | Stored as |
|---|---|---|
| `bool` | JSON bool | `Bool` |
| `string(allowed: Set<String>?)` | a string, in `allowed` when given | `String` |
| `number(ClosedRange<Double>)` | a number in range | `Double` |
| `stringArray` | an array of strings | `[String]` |
| `json(validate: (Data) -> Bool)` | any JSON that the validator accepts | `Data` (JSON) |

`PreferenceSpec { key: String, kind: PreferenceKind }`.

### SettingsSection (new)

`enum SettingsSection: String, CaseIterable`:
- `keyboard`, `preferences`, `appearance`, `hotPaths`, `userMenu`, `connections`, `toolbar`;
- the order is the display order in the import dialog.

### SettingsCatalog (new)

| Field | Type | Notes |
|---|---|---|
| `preferences` | `[PreferenceSpec]` | the allowlist of R6 |
| `keyboardKeys` | `(scheme: String, bindings: String)` | `keys.scheme`, `keys.bindings` |
| `blobs` | `[SettingsSection: BlobSpec]` | appearance, hotPaths, userMenu, connections, toolbar |

`BlobSpec`:
- `defaultsKey`;
- `storage`: `.jsonData` or `.propertyList`;
- `elementwise: Bool`: lists are validated element by element;
- `validate: (JSONValue) -> Bool`: per element when elementwise.

The core builds the parts that depend only on core types (hot paths, appearance, connections, user
menu, comparison). The app supplies the allowed values of its own enums (path bar style, encodings,
checksum algorithm) and the toolbar key.

### SettingsFile / SettingsContents (new)

- `read(_ data: Data) throws(SettingsArchiveError) -> SettingsContents`;
- `SettingsContents`:
  - `formatVersion: Int`, `appVersion: String?`, `exported: String?`;
  - `sections: [SettingsSection: JSONValue]`;
  - `unknownSections: [String]`;
  - `isNewer: Bool`;
- `SettingsArchiveError`: `.notJSON`, `.notSettingsFile`.

### ImportReport (new)

| Field | Type |
|---|---|
| `applied` | `[SettingsSection]` |
| `skipped` | `[SkippedEntry]`, each `{ section: String, item: String, reason: SkipReason }` |
| `newerFormat` | `Bool` |

`SkipReason`:
- `unknownSection`, `unknownKey`, `unknownCommand`;
- `malformedChord`, `wrongType`, `outOfRange`;
- `unknownScheme`, `invalidEntry`.

### SettingsArchive (new)

- `export(from: UserDefaults, catalog:, appVersion:, date:) -> Data`;
- `read(_:) throws -> SettingsContents`;
- `apply(_ contents:, sections: Set<SettingsSection>, to: UserDefaults, catalog:) -> ImportReport`.

`apply` validates first and writes after. A chosen section replaces its current values: a
preference that is missing from the file stays as it is (older files, FR-022), while a list
section replaces the whole list.
