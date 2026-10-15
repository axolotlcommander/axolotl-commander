# Research: Panel and Bar Fonts

## R1 Where the choice is stored

- **Decision**: Two optional `FontChoice` fields in `PanelAppearance` (the `appearance` preference).
- **Rationale**: `AppSettings` already saves it, posts `.appearanceChanged` and the settings export / import
  carries it; missing keys decode as the defaults, so older settings files stay valid (FR-010).
- **Alternatives**: separate `UserDefaults` keys — would need their own export handling and notification.

## R2 Choosing in the Fonts panel

- **Decision**: `FontChooser` sets `NSFontManager.shared.target` to itself for one role, presets
  `setSelectedFont(_:isMultiple:)` and orders the Fonts panel front; `changeFont(_:)` converts the current
  font with `convert(_:)`, clamps the size and stores the choice. Closing Settings, or "Default" /
  "Restore Default Fonts", sets the target back to nil (the responder chain again), so the Fonts panel stops
  changing the panels (spec clarification 2026-10-15).
- **Rationale**: an explicit target avoids depending on the SwiftUI responder chain and never changes a
  text field elsewhere; resetting it on close keeps the Fonts panel usable for other text.
- **Alternatives**: the responder chain of the Settings window — SwiftUI hosting makes it fragile.

## R3 Identifying a font

- **Decision**: the PostScript name (`fontName`) plus the size; nil means the system font. The display text
  is the family and the face name (`displayName`), or "System font", and the size.
- **Rationale**: the PostScript name names family and face together and is stable across launches;
  `NSFont(name:size:)` returning nil detects a removed font (FR-011).

## R4 Row height and the file list

- **Decision**: `rowHeight = max(18, ceil(lineHeight + padding))` where `padding = 18 − lineHeight(system 13
  pt)` and `lineHeight` comes from `NSLayoutManager.defaultLineHeight(for:)`. The brief view's item height
  and the thumbnail label height use the same line height; the brief column width is measured with the list
  font.
- **Rationale**: with the default font the result is exactly today's 18 pt (SC-002).

## R5 Bars

- **Decision**: each bar computes its height from the bar font's line height (today's heights at 11 pt as
  the minimum); the bordered volume buttons (their own font role since the clarification of 2026-10-15) use `.small` up to 11.5 pt, `.regular` up to 14 pt and `.large`
  above, with the font set explicitly. Bar content keeps compression resistance below the split items'
  holding priority, so a panel never widens (FR-007).
- **Rationale**: the accessory bar bezel has a fixed height per control size; switching the size keeps the
  text inside the bezel.

## R6 Bold for marked items

- **Decision**: `NSFontManager.convert(_:toHaveTrait: .boldFontMask)`; when the result has no bold trait the
  regular face is used (edge case).
