# Research: Panel Behavior Options

## R1 Where the settings live and how they are read

- **Decision**: the four keys are UserDefaults booleans named in a core `PanelBehavior` type, which
  holds the keys, the defaults and `init(defaults:)`. The UI reads `PanelBehavior(defaults: .standard)`
  at the moment of the keystroke or click, so a change applies at once in every window with no
  observers. SwiftUI binds the toggles with `@AppStorage` on the same keys.
- **Rationale**: the core type is the single place for the key names. The catalog and the tests use the
  same constants. The values are read per event, which is cheap.
- **Alternatives**:
  - caching in `AppSettings` with notifications: more code, and a stale value is possible;
  - one JSON blob: it would break the per-key catalog and the compatibility rules.

## R2 Space

- **Decision**: in `PanelViewController.perform(.toggleSelectionAndSize)`, call `moveCursor(by: 1)`
  only when `spaceMovesDown` is on. `toggleSelection` (Insert) keeps moving.
- **Rationale**: Space is bound to `toggleSelectionAndSize` only, so the change cannot leak into other
  marking keys (FR-003). Quick search handles Space before any command, so FR-003's quick search rule
  holds.

## R3 Typing routing

- **Decision**: a core function `PanelTyping.route(key:modifiers:text:baseText:lineIsEmpty:quickSearchActive:isBound:)`
  returns `PanelTyping.Action`. The panel calls it first in `handleKey` when the setting is on. It acts
  on these keys:
  - an unbound character without ⌘ ⌃ ⌥ → `.append(text)`;
  - Return, Backspace, Esc, Space with text in the line → `.run` / `.deleteLast` / `.clear` /
    `.append(" ")`;
  - ⌥ + character with no command bound → `.startQuickSearch(baseText)`;
  - otherwise `.none`, and the old handling continues.
  While quick search is active, the router returns `.none` for everything, so the existing quick search
  code keeps full control.
- **Rationale**: one table, tested in the core, decides every case of FR-005–FR-010. The panel only
  turns actions into calls.
- **Text of the key**: `event.characters` for the appended text (the same as quick search today). For
  ⌥ + key, the base text is `event.characters(byApplyingModifiers: shift only)`, so the Czech number row
  gives "ě", not "2".
- **Line actions**: `MainWindowController.commandLine(_ action:)` carries them out. It shows a hidden
  line, appends without a separator (unlike `insert`, which adds a space), removes the last character,
  clears, or runs `execute(text)`, which is what Return in the line calls. The focus is never moved.
- **Alternatives**:
  - moving the focus to the line on the first character: rejected by the maintainer;
  - forwarding the NSEvent to the field editor: it needs the focus.

## R4 ⌃← / ⌃→

- **Decision**: core `OpenInPanel.plan(command:active:classic:)` returns `(source, target, focus)`
  sides.
  - Classic: target = the command's side; source = the other side; focus = active.
  - Today: source = active; target = the other side; focus = the target when the arrow points away
    from the active panel.
  `PanelModel.openTarget(parentOpensLocation:)` returns today's `otherPanelTarget`. With the flag, ".."
  returns `(location, nil)` instead of nil. The window's validation uses the source panel's
  `openTarget(parentOpensLocation: classic)`.
- **Rationale**: the side logic and the item logic are separate pure functions, both easy to test. The
  window code stays a few lines.
- **Flat listings**: `otherPanelTarget` already gives a file's own folder, because it uses the item's
  URL.

## R5 Volume buttons

- **Decision**:
  - Core `VolumeChoice.target(volume:panelVolume:otherFolder:otherVolume:remembered:exists:)` applies
    rules a–d and returns the URL to open. `panelVolume` and `otherVolume` are nil when that panel
    shows an archive, a server or Network (FR-021).
  - Core `VolumePlaces` (`visit(folder:volume:)`, `folder(on:)`) is a per-panel dictionary from the
    volume root to the last folder.
  - The panel keeps one `VolumePlaces` and records a visit in its location-change hook. The hook
    already records server places there. Disk folders only.
  - Volume buttons (`VolumeBar.onChoose` for `.volume` items) and the volume entries of the ⌥F1 / ⌥F2
    menu call one `chooseVolume(_ url:)`. Home, iCloud Drive and the place entries keep calling
    `go(to:)`.
- **Volume identity**: `Volumes.root(of:)` (the `volumeURL` resource) gives "/" for the home folder
  (checked on the maintainer's Mac), so Home counts as on the startup disk.
- **Existence**: `FileManager.fileExists(atPath:isDirectory:)` at pick time; a missing or ejected folder
  falls back to the root.
- **Rationale**: it mirrors `ConnectionPlaces`, which already remembers server folders per panel in
  memory.
- **VolumeBar change**: the bar must tell a volume pick from a Home or iCloud pick. A new
  `onChooseVolume` callback is used for `.volume` items; `onChoose` stays for Home and iCloud.

## R6 Settings UI

- **Decision**:
  - Settings → General gets a `Section("Panels")` with four toggles and a caption each, placed after
    the command line / function key bar section.
  - Settings → Keyboard gets, under the scheme picker, a caption: "Behavior such as Space, typing into
    the command line, ⌃← / ⌃→ and the volume buttons is set in General → Panels."
- **Rationale**: these are the existing places for panel chrome options and for the scheme. No new
  tab.
