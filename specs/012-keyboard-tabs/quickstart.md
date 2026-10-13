# Quickstart: Tabs from the Keyboard

## Automated

`swift build` gives no warnings and `swift test` is green (`KeyboardTabTests`, `TabChordTests`,
`stateEnteringCursorLeavesThePanelAlone`).

## GUI check (test copy, scratchpad folders, browsing only)

1. With the cursor on a folder, use Go → Open in New Tab: a new active tab shows the folder, and the old
   tab keeps its place. Repeat on a file and on "..".
2. Go → Open in Background Tab: the tab strip gains a tab, and the panel stays.
3. Go → Open in New Tab of Other Panel: the other panel gains an active tab, and the focus stays.
4. Close a tab, then Go → Reopen Closed Tab: it comes back.
5. Go → Tab List…: the open tabs are listed (the active one checked) and the closed tabs appear under
   "Recently Closed". Choose each kind of entry, and Esc closes the list.
6. Go → Close Other Tabs: one tab is left, and the others are in the tab list.
7. View → Swap Panels with All Tabs: the tab strips change sides.
8. Classic Commander: ⌃⇧W closes the other tabs, ⌃W closes the current tab (use the menu when a
   display utility takes ⌃⇧).
