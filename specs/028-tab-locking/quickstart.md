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
