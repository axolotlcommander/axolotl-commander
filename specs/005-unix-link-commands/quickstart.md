# Quickstart: Validating the Link Commands

## Prerequisites

- `swift build` without warnings, `swift test` green.
- Test copy of the app (`iCmdTest.app`, bundle id `cz.acidek.axolotlcommander.gtest`) built with
  `scripts/bundle.sh debug`.
- A scratch folder `<test>` with `a/file.txt`, `a/other.txt`, `a/dir/`, `b/`; both panels
  pointed into `<test>` before any command that writes. Never the user's data.
- Before every click batch, read the test window's frame again; keys only when the test app is
  frontmost. ⌃⇧/⌃⌥ chords are not used by this feature.

## Scenarios

| # | Steps | Expected |
|---|---|---|
| Q1 | Left `<test>/a` on `file.txt`, right `<test>/b`; ⌃⌘L, Return | `b/file.txt` → `<test>/a/file.txt` (absolute); right panel cursor on it |
| Q2 | Same, rename to `rel.txt`, "Relative path" on | `b/rel.txt` → `../a/file.txt`; next ⌃⌘L has the box on |
| Q3 | ⌃⌘L on `file.txt` again with name `b/file.txt` | inline "already exists", sheet open, `b/file.txt` unchanged |
| Q4 | Select `file.txt`, `other.txt`, `dir`; ⌃⌘L, Return | sheet shows folder `<test>/b`; `other.txt`, `dir` created, `file.txt` skipped and listed |
| Q5 | ⌃⌘L, type target `<test>/a/missing` | question; Create → dangling link; Cancel → back in the sheet |
| Q6 | Right panel on `b/file.txt`, ⌃T | panel in `<test>/a`, cursor on `file.txt`; ⌘[ back to `b` on the link |
| Q7 | ⌃T on `b/dir` (link to folder) | panel shows `<test>/a/dir` by its real path |
| Q8 | Chain `c1 → c2 → a/file.txt`, ⌃T on `c1` | panel at `a`, cursor on `file.txt` |
| Q9 | ⌃T on the dangling link | message names the stored target; panel unchanged |
| Q10 | Select `file.txt`, `other.txt` in `a`, ⌘C, go to new folder `<test>/c`, ⌃⌘V | two absolute links; repeat → both skipped, one summary |
| Q11 | ⌃F2 on `file.txt`, owner Execute on, Apply | mode gains `u+x`; ⌃F2 + Esc changes nothing |
| Q12 | New Hard Link… on `a/file.txt` with right in `b` (rename to `hard.txt`) | `b/hard.txt` same inode, link count 2 |
| Q13 | New Hard Link… on `a/dir` | "Folders cannot have hard links."; nothing created |
| Q14 | Edit Symbolic Link… on `b/rel.txt`, target `../a/other.txt` | link now → `../a/other.txt`; both files unchanged |
| Q15 | Menus with cursor on "..", on an ordinary file, in an archive, on clipboard text only | the commands are disabled as the contract says |
| Q16 | Keyboard Shortcuts, Customize Toolbar | six new commands listed; none in the default toolbar |
| Q17 | Compare `<test>` listing (`ls -laR`) before/after each step | only the expected new or edited links differ |
