# Quickstart: Tab Locking and Tab Menu — validation

Unit tests: `swift test --filter TabLock`.

GUI check on the test copy (`cz.acidek.axolotlcommander.gtest`) in Czech, browsing only a test folder in the
session scratchpad (`lock/a/a1`, `lock/b`, `lock/c`); no file operations.

1. Both panels on `lock/`. Open two more tabs (New Tab). Right-click the first tab: the menu shows New Tab,
   Duplicate Tab, Copy Tab to Other Panel; Lock Tab, Lock Tab, Allow Folder Changes; Close Tab, Close Other
   Tabs, Close Tabs to the Right, Reopen Closed Tab; no Czech text is cut.
2. Lock Tab on the first tab: the lock shows at its left end; the tooltip says "Locked" and the path.
3. In the locked tab, Return on `a`: a new tab right after it shows `lock/a` and is active; the locked tab
   still shows `lock/` with the cursor on `a`. Repeat with "..", a hot path and `cd b` in the command line:
   each opens a new tab. Refresh in the locked tab opens nothing.
4. Lock Tab, Allow Folder Changes on another tab; go into `a/a1` there (the same tab changes); switch to
   another tab and back: it shows its locked folder with the cursor on the remembered item.
5. Hover over an inactive tab: the left end shows ×; a click closes it. Hover over the locked tab: × instead
   of the lock while hovered.
6. Close Other Tabs from an unlocked tab: the locked tabs stay. Close Tabs to the Right on the first tab:
   locked tabs stay.
7. Close the locked tab with its ×: no question; Reopen Closed Tab: it is back with the lock.
8. Duplicate Tab and Copy Tab to Other Panel on the locked tab: unlocked copies (no lock mark).
9. Quit and start: the locks are there; the folder-changes-allowed tab is on its locked folder.
10. The keyboard tab list (⌘⇧\) shows the lock on locked tabs. Go menu: the lock commands show checkmarks
    for the active tab.

## GUI check record (2026-10-14, test copy in Czech)

Steps 1–10 passed, browsing only the scratchpad test folder:

- Tab menu: all items present, Czech texts not cut, the lock item checked on the locked tab, Reopen Closed
  Tab disabled before anything was closed.
- Locked tab: Return on `a`, Enclosing Folder, `cd b` in the command line and Swap Panels (⌃U) each opened
  a new tab right after it, the locked tab kept `lock/` with the cursor on `a`; Refresh opened nothing.
- Folder changes allowed: browsing into `a/a1` stayed in the tab; switching away and back, and a restart,
  showed `lock/` with the cursor on `b`.
- Strip: lock marks on both locked tabs; hovering an inactive tab or a locked one showed ×; the × closed a
  locked tab without a question and Reopen Closed Tab brought it back locked.
- Close Other Tabs and Close Tabs to the Right (from the menu of a non-active tab) kept locked tabs.
- Duplicate Tab and Copy Tab to Other Panel produced unlocked copies; the tab list showed the locks.
- Not checked visually: the tooltip text (synthetic pointer moves do not bring up tooltips).

Found and fixed: Swap Panels and Same Folder as Other of a flat listing changed a locked tab's folder in
place; they now open a new tab like every other folder change.

## "+" and "»" check (2026-10-14, clarification of the same day)

- With one tab the strip is hidden; Settings → Panels → "Always show the tab bar" showed it at once with "+"
  (the Czech caption is not cut); turning the option off hid it again for the panel with one tab.
- "+" opened tabs; with nine tabs in a half-width panel six were shown, the active one among them, and "»"
  listed the other three; choosing one made it active and it took the last visible place.
- Found and fixed: the "+"/"»" group took the strip's spare width and squeezed a single tab.
