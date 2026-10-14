# Research: Mouse Selection

## R1. Where the marking rules live

- **Decision**: An extension of `PanelModel` in the core (`Sources/CommanderCore/PanelMouse.swift`) with
  one method per gesture step: left press and left release on an item, a press on empty space, the rubber
  band (begin, update), right click, right drag (begin, over an item). The views only find out what is under
  the pointer and which buttons and keys are held, and call these methods.
- **Rationale**: Every rule of the spec (FR-001 to FR-005, FR-007, FR-011, FR-015, FR-016, FR-018 to
  FR-020) is then covered by `swift test` (constitution IV). Marks are kept by name key in
  `PanelModel.selection`, so the methods work on keys directly and never convert the whole set.
- **Alternatives considered**: A pure index-based reducer (marks as `Set<Int>`) is easier to test in
  isolation, but converting to and from name keys on every mouse move costs O(n) for 100 000 items, and
  it would duplicate the ".." rule that `PanelModel` already applies.

## R2. ⌃W after a mouse gesture

- **Decision**: A gesture that removes marks (a plain click, ⇧+click, a plain rubber band) first stores the
  current marks in `previousSelection` when they are not empty. Today `previousSelection` is set only when
  the marks become empty, which misses "a plain click on a marked item leaves only that item".
- **Rationale**: FR-020. ⌃W keeps its meaning (mark again what was marked before).

## R3. Detailed view: taking over the table's mouse handling

- **Decision**: `PanelTableView.mouseDown` decides by the hit:
  - **Empty space below the rows**: the panel's own tracking loop. No movement → a plain click on empty
    space (FR-007); movement over 3 points → rubber band.
  - **A row outside the icon and the name text** (FR-010, FR-013): own tracking loop; a drag → rubber band,
    no drag → the click rules on that row; a double click opens the item.
  - **The icon or the name text with ⌃, ⌘ or ⇧**: the click rules only, `super` is not called, so no drag
    and no row selection by AppKit (FR-006).
  - **The icon or the name text without a modifier**: the press rule (FR-001, FR-002), then
    `super.mouseDown`, which runs AppKit's drag & drop and double-click handling as today. When it returns
    and no drag session began (a flag set in the table's `beginDraggingSession(with:event:source:)`, which AppKit calls while tracking
    the press; `draggingSession(_:willBeginAt:)` only comes after `mouseDown` returns), the release rule.
    The row writer is returned for marked rows too, otherwise no drag starts; the session then puts every
    marked item on the pasteboard.
- The name zone is the `FileCellView` icon frame plus the label's frame cut to the width of its text.
- **Rationale**: Keeps the working drag & drop code (`pasteboardWriterForRow`, writing all marked items when
  the session begins) and the double-click action; only the cases that need new behavior get their own
  tracking.
- **Alternatives considered**: `allowsMultipleSelection = true` with AppKit's own ⌘/⇧ selection — that would
  make the table's selection the marks, but the panel's cursor is the table's single selected row, and the
  Windows rules (⇧ starts a new range, ⌃⇧ adds one, ".." never marked) differ from AppKit's.

## R4. Brief view

- **Decision**: `BriefGridView.mouseDown` (already custom, does not call `super`) gets the same decision
  tree. Its own drag start (`mouseDragged`, 4 points) runs only for a plain press on an item's icon or name.
  The name zone comes from the `BriefItem` view's icon and label.
- Items under a rectangle are computed from the grid geometry (the frames of the first item and of the
  first item of the second column give the item size, the column stride and the rows per column), not by
  asking the layout for every element: O(columns touched).

## R5. ⌃+click versus the system context menu

- **Decision**: AppKit treats a ⌃-left-click as a request for the context menu and asks the view's
  `menu(for:)` before `mouseDown`. Both views return nil from `menu(for:)` when the event is a left mouse
  down, so the click reaches `mouseDown` and toggles the mark (FR-005). Verify in the GUI check. If AppKit
  still opens a menu, the fallback is to turn the event into a plain left mouse down with the control flag
  in `CommanderApplication.sendEvent` (the app already intercepts the Help key there).

## R6. Rubber band

- **Decision**: An overlay view (`RubberBandView`) in the document view draws the rectangle in the system
  selection color (translucent fill, solid border). The tracking loop runs with periodic events so the list
  keeps scrolling (`autoscroll(with:)`) while the pointer rests outside the list (FR-012).
- The marks update during the drag (FR-011) incrementally: the band remembers the marks at its start and the
  items it covered in the last step; only items entering or leaving the rectangle change. Plain: the start
  clears the marks (stored for ⌃W), covered items are marked. ⇧: covered items are marked, items that leave
  get their start state back. ⌃/⌘: covered items get the opposite of their start state.
- After each step only the visible rows or items are redrawn and the info line updated (no full
  `reloadData`), so 100 000 items stay responsive (SC-003).

## R7. Norton-style right button

- **Decision**: New setting `PanelBehavior.rightButtonMarks` (key `panel.rightButtonMarks`, default off) in
  Settings → General → Panels, read on each press like the other behavior settings. With it on,
  `rightMouseDown` in both views runs its own loop:
  - ⌃ held → the context menu at once (today's path).
  - Otherwise wait up to 0.5 s for a right drag (more than 3 points) or the release:
    - the release first → toggle the mark (FR-015);
    - a drag → right drag: the first item decides mark or unmark, every item passed over (including those
      skipped by a fast move, filled in between the last and the current row) gets that state, with
      autoscroll (FR-016);
    - the time runs out without movement → the context menu (FR-017).
- **Menu in Norton mode**: marks are the point of this mode, so a long press does not clear them; the cursor
  moves to the item and the menu acts on the marked items, or on the pressed item when none are marked.
  `contextMenu(at:)` keeps the marks whenever the setting is on (also for ⌃+right click and ⇧F10). In the
  default mode the right click keeps today's behavior (FR-008).
- With the setting on, a plain left press only moves the cursor (FR-018); drag & drop from a marked item
  carries all marked items, from an unmarked one only that item (today's drag rule).

## R8. Redrawing marks

- **Decision**: A new `marksChanged()` in `PanelViewController` redraws the visible rows (Detailed) or
  items (Brief) and the info line, and syncs the table's selected row to the cursor. Mouse gestures call it
  instead of `modelChanged()`, which reloads the whole table and also updates the path bar, the volume bar
  and the tabs.

## R9. Testing

- Unit tests on a `PanelModel` listing a temporary folder with files a…j and one folder (the existing
  fixture pattern in `PanelModelTests`), one test per rule.
- GUI check on the test copy with a scratch folder of 50 files (both panels pointed to it): every click kind
  in both views, the rubber band past the bottom edge, a drag of marked items cancelled with Esc, the right
  click menu, the Norton setting on and off. Mouse events only inside the test window, modifiers always
  released.

## R10. Measured (2026-10-14)

- `NameRules.key` did NFC and case folding for every name; marking 100 000 items took about 0.7 s in a
  debug build. ASCII names now skip that work (NFC leaves them alone, folding is lowercasing; a test
  compares all 127 ASCII characters with the Unicode path).
- Release build (`swift test -c release -Xswiftc -enable-testing`): a rubber band covering 100 000 items in
  one step 31 ms, a ⇧+click range over them 26 ms (SC-003: under 0.1 s).
