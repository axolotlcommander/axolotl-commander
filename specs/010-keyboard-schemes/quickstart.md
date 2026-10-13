# Quickstart: validating spec 010

## Automated

```sh
swift build 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3
```

Expected: no warnings, and all tests pass, including `KeySchemeTests` and `SettingsArchiveTests`.

## GUI check (test copy only)

**Setup**:
- Build `scripts/bundle.sh`.
- Copy the app to the session scratchpad as `iCmdTest.app`.
- Set the bundle id to `cz.acidek.axolotlcommander.gtest` and re-sign ad hoc.
- Launch it.
- Point both panels to a scratchpad test folder with a few files and a subfolder.

**US1, default chords**:
1. Open the subfolder, then press ⌥←: the panel goes back. ⌥→ goes forward.
2. Press ⇧F6 on a file, and the inline rename starts. Esc cancels it.
3. Press ⌃F1, and the view is Brief. ⌃⌥1 returns to Detailed.
4. Hold ⌃: F1 shows "Brief". Hold ⇧: F2 shows "Compare" and F6 "Rename". Hold ⌥: F9 shows
   "Unpack".
5. Press ⌃R, and the panel refreshes. ⌃A marks everything.

**US2, Classic Commander**:
1. In Settings → Keyboard, pick "Classic Commander".
2. The Go menu shows ⌃T for New Tab and ⌃W for Close Tab.
3. Press ⌃T and a tab opens. ⌃⇥ switches tabs, and ⌃W closes the tab.
4. Hold ⌥: F3 shows "View With" and F4 "Quit". Do not press ⌥F4.
5. Press F2, and the rename still starts.
6. Switch back to "Axolotl". The Go menu shows ⌃⇧T again, and ⌃T goes to the link target.

**US3, user changes**:
1. Under Classic Commander, give Go to Link Target the chord ⌃T.
2. New Tab shows its ⌃T as taken.
3. Switch the scheme twice. The change stays.
4. Reset it, and New Tab gets ⌃T back.

**US4, export and import**:
1. Export to `scratchpad/settings.json`. Check that the file has the sections and no password.
2. Change the scheme, a preference and a hot path.
3. Import the file with all parts checked. Everything returns at once.
4. Edit a copy so it has an unknown command, the chord `"ctrl+bogus"` and `"viewer.fontSize": 999`.
   Import it, and the summary lists all three.
5. Import a text file that is not JSON. An error appears, and nothing changes.

Screenshots are taken only of the test app's windows (`screencapture -l<id>`). Keys are sent only
while the test app is frontmost.
