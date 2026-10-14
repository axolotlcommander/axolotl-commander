# Data Model: Mouse Selection

All types are in `CommanderCore` (no AppKit). Marks stay in `PanelModel.selection` (name keys); the cursor
in `PanelModel.cursor`.

## MouseSelectionMode

```swift
public enum MouseSelectionMode: Sendable { case standard, rightButtonMarks }
```

From `PanelBehavior.rightButtonMarks` (key `panel.rightButtonMarks`, default `false` → `.standard`).

## MouseModifiers

```swift
public struct MouseModifiers: OptionSet, Sendable {
    public static let toggle   // ⌃ or ⌘
    public static let range    // ⇧
}
```

| Held | Value | Meaning |
|---|---|---|
| none | `[]` | plain click |
| ⌃ or ⌘ | `.toggle` | toggle one item |
| ⇧ | `.range` | new range |
| ⌃⇧ or ⌘⇧ | `[.toggle, .range]` | add a range |

## PanelModel mouse methods (`PanelMouse.swift`)

| Method | Rule |
|---|---|
| `mousePressed(at:modifiers:mode:) -> Bool` | Left press on an item. Applies FR-001 (plain, unmarked: clear, cursor), FR-003 (⇧: clear, mark cursor…index), FR-004 (⌃⇧: add cursor…index), FR-005 (⌃/⌘: toggle); in `.rightButtonMarks` a plain press only moves the cursor (FR-018). Returns whether drag & drop may start (plain press only, FR-006). |
| `mouseReleased(at:mode:)` | Left release on the same item without a drag after a plain press in `.standard`: when the item is marked, it becomes the only marked item (FR-002). |
| `mousePressedOnEmptySpace(mode:)` | `.standard`: clear the marks; cursor unchanged (FR-007). |
| `beginRubberBand(modifiers:) -> RubberBand` | Plain: clears the marks (stored for ⌃W). |
| `updateRubberBand(_:covering:)` | Applies the band to the items now covered (`IndexSet`), changing only items that entered or left (FR-011). |
| `toggleMarkByRightClick(at:)` | Norton: toggle the mark, move the cursor (FR-015). |
| `beginRightDrag(at:) -> Bool` | Norton: the state the first item decides (unmarked → `true`) and applies it to that item (FR-016). |
| `rightDrag(from:to:marking:)` | Applies the state to every item between the last and the current row and moves the cursor there. |

Every method skips ".." (FR-019) and stores the old marks in `previousSelection` before removing any
(FR-020). A range is `min(cursor, index)…max(cursor, index)`.

## RubberBand

```swift
public struct RubberBand: Sendable {
    let operation: Operation        // replace, add, toggle (from the modifiers)
    let start: Set<String>          // marks when the band began
    var covered: IndexSet           // items covered in the last step
}
```

## PanelBehavior

New field `rightButtonMarks: Bool` (key `panel.rightButtonMarks`, default `false`), a `PreferenceSpec` in
`AppSettingsCatalog`, a toggle in Settings → General → Panels.
