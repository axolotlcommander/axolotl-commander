# Data Model: Panel Behavior Options

All types are in `Sources/CommanderCore/PanelBehavior.swift` unless noted.

## PanelBehavior (struct, Sendable, Equatable)

| Field | Key | Default |
|---|---|---|
| `spaceMovesDown: Bool` | `panel.spaceMovesDown` | true |
| `typingToCommandLine: Bool` | `panel.typingToCommandLine` | false |
| `arrowsTargetPointedPanel: Bool` | `panel.arrowsTargetPointedPanel` | false |
| `volumeButtonsFollow: Bool` | `panel.volumeButtonsFollow` | false |

- `static let spaceKey`, `typingKey`, `arrowsKey`, `volumesKey`: the keys above.
- `init(defaults: UserDefaults)`: a missing key gives the default.
- `init()`: all defaults.
- The keys MUST NOT be renamed (settings file compatibility).

## PanelTyping

`enum Action: Equatable { case none, append(String), deleteLast, clear, run, startQuickSearch(String) }`

`static func route(key: KeyChord.Key, modifiers: KeyChord.Modifiers, text: String?, baseText: String?,
lineIsEmpty: Bool, quickSearchActive: Bool, isBound: Bool) -> Action`

Callers invoke it only when the setting is on. Rules, first match wins:

1. quick search active → `.none`;
2. `isBound` → `.none` (a chord with a command keeps it);
3. `.character`, modifiers ⊆ {⇧}, `text` non-empty → `.append(text)`;
4. `.character`, modifiers contain ⌥ and no ⌘/⌃, `baseText` non-empty → `.startQuickSearch(baseText)`;
5. line non-empty and no modifiers:
   - `.enter` / `.numEnter` → `.run`;
   - `.backspace` → `.deleteLast`;
   - `.escape` → `.clear`;
   - `.space` → `.append(" ")`;
6. otherwise `.none`.

## OpenInPanel

`struct Plan: Equatable { source: Side; target: Side; focus: Side }`

`static func plan(target command: Side, active: Side, classic: Bool) -> Plan`:
- classic: `Plan(source: command.other, target: command, focus: active)`;
- today: `Plan(source: active, target: active.other, focus: command == active.other ? active.other : active)`.

`Side.other` is a new core extension on the existing `Side`.

## PanelModel.openTarget(parentOpensLocation: Bool) -> (url: URL, focus: String?)?

- Same as `otherPanelTarget` for every item except "..".
- On "..": `(location, nil)` when `parentOpensLocation`, else nil.
- `otherPanelTarget` stays as a wrapper with `false`.

## VolumeChoice

`static func target(volume: URL, panelVolume: URL?, otherFolder: URL?, otherVolume: URL?,
remembered: URL?, exists: (URL) -> Bool) -> URL`:
- a. `panelVolume == volume` → `volume`;
- b. `otherVolume == volume`, `otherFolder != nil` → `otherFolder`;
- c. `remembered` non-nil and `exists(remembered)` → `remembered`;
- d. `volume`.

Volume URLs are compared by their standardized paths.

## VolumePlaces (struct, Sendable)

- `mutating func visit(_ folder: URL, volume: URL)`;
- `func folder(on volume: URL) -> URL?`.
- One instance per `PanelViewController`, in memory only.
