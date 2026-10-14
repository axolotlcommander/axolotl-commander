# Quickstart: Mouse Selection

## Build and unit tests

```sh
swift build 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3
```

Expected: no warnings, all tests pass, among them `PanelMouseTests` (every rule in
[data-model.md](data-model.md)).

## GUI check (test copy only)

Prerequisites: the test copy of the app (own bundle id `cz.acidek.axolotlcommander.gtest`), a scratch folder
with files `f01`…`f50` and one folder, both panels pointed to it. Only browsing and marking; drags are
cancelled with Esc before dropping. Mouse events only inside the test window, modifiers always released.

1. Detailed view: ⌃-click f03 and f05 → both marked; ⌘-click f05 → only f03.
2. Cursor on f02, ⇧-click f04 → f02…f04 only; ⌃-click f08, ⌃⇧-click f10 → f02…f04 and f08…f10.
3. Plain click f20 → nothing marked; ⌃W → previous marks back.
4. Mark f02…f04, plain click f03 → only f03; mark again, press on f03 and drag a little → drag starts with
   three items; Esc → marks unchanged.
5. Drag in the Size column from f05 to f09 → f05…f09; with ⇧ over f20…f22 → added; with ⌃ over f08…f11 →
   toggled; drag past the bottom edge → list scrolls, items marked.
6. Click below the last row → marks cleared, cursor stays.
7. Right click a marked item → menu for all marked; right click an unmarked one → marks cleared, menu for
   it; ⌃-click never opens a menu.
8. Brief view (⌃⌥2): steps 1–6 again.
9. Settings → Panels → "Right mouse button marks" on: right click toggles; right drag marks f05…f09 and then
   unmarks from a marked start; hold the right button 0.5 s → menu, marks unchanged; ⌃+right click → menu
   at once; plain left click keeps the marks. Turn it off → right click opens the menu again.
