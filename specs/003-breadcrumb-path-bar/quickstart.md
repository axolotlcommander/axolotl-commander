# Quickstart: Validating the Breadcrumb Path Bar

## Prerequisites

- `swift build` without warnings, `swift test` green.
- Test copy of the app (`iCmdTest.app`, bundle id `cz.acidek.axolotlcommander.gtest`) built with
  `scripts/bundle.sh debug`, settings of the test copy reset.
- Scratch folder `<test>` in the session scratchpad with `a/b/c`, a ten-level deep folder
  `deep/1/2/…/10`, and `pack.zip` containing `inner/deep/file.txt`. Both panels start in `<test>`.

## Scenarios

| # | Steps | Expected |
|---|---|---|
| Q1 | Launch with default settings | Both panels show breadcrumbs "Macintosh HD › … › <test>" with icons; active panel tinted |
| Q2 | Left panel to `<test>/a/b/c`, click "a" | Panel shows `<test>/a`, cursor on "b", focus in list; Back returns to `c` |
| Q3 | Click "c" (current) | Nothing changes |
| Q4 | Right panel active, click a segment in the left bar | Left panel becomes active and navigates |
| Q5 | ⌘L, type `<test>/a`, Enter | Panel goes to `<test>/a`, bar shows breadcrumbs, focus in list |
| Q6 | ⌘L, type `/nonexistent`, Enter | Beep, status line error, panel unchanged, breadcrumbs back |
| Q7 | ⌘L, Esc | No change, breadcrumbs back, focus in list |
| Q8 | Click empty area right of the last segment | Field opens with full path selected |
| Q9 | Right-click "a" → Open in Other Panel / Open in New Tab / Copy Path / Set as Hot Path 3 | Right panel at `a` / new left tab at `a` / clipboard = path / ⌃3 goes to `a` |
| Q10 | ⌘-click "a" | New tab in the left panel at `<test>/a` |
| Q11 | Open `deep/1/…/10`, narrow the window to minimum | "Macintosh HD › … › 9 › 10" style; click "…" lists hidden folders; choosing one goes there |
| Q12 | Enter `pack.zip`, then `inner/deep`; click "pack.zip", then the `<test>` segment | Archive root; then `<test>` with cursor on `pack.zip` |
| Q13 | Find files in `<test>` (results), look at the bar, click the root segment | Title segment (not clickable) + root trail; click leaves results |
| Q14 | Settings → Appearance: Path bar = Text field; then icons off with breadcrumbs | Text field in both panels at once, survives relaunch; icons disappear at once |
| Q15 | VoiceOver / AX inspection | Bar = group "Path", segments = buttons with folder names |
| Q16 | Dark mode (if the maintainer switches it) | Text, icons, separators, highlight readable |

Remote (SFTP) segments are covered by unit tests; a GUI check needs a real server and is done
only if the maintainer provides a test server.
