# Quickstart: App Updates — validation

Unit tests: `swift test --filter Update`.

GUI check on the test copy (`cz.acidek.axolotlcommander.gtest`, in the session scratchpad). Never against the
real server, never over the installed app.

1. Start a local server in the scratchpad on 127.0.0.1 (not port 8765) serving `releases/latest` (JSON per
   [contracts/release.md](contracts/release.md)) with version 9.9.9, its zip, `SHA256SUMS.txt` and both
   changelogs (with a 9.9.9 section). `defaults write cz.acidek.axolotlcommander.gtest updates.feedURL
   http://127.0.0.1:PORT/releases/latest`; clear `updates.lastCheck`.
2. Start the test copy: ~5 s after the main window the title bar shows "↑ Version 9.9.9" and no window
   opens; a click on it opens the update window (0.6.0 → 9.9.9, the Czech notes); the default button is
   Download… with the reason "not signed with the project's certificate" (the test copy is ad-hoc signed).
3. Remind Me Later (Esc) → the window closes, the title-bar button goes, `updates.remindAfter` is a day
   later.
4. App menu → Check for Updates… → the window again (manual check ignores remind-later).
5. Skip This Version → restart with `updates.lastCheck` cleared: no button; serve 9.9.10 → the button.
6. Serve version 0.6.0 → Check for Updates…: "Axolotl Commander 0.6.0 is the latest version."
7. Stop the server → Check for Updates…: the failure reason with Try Again; the automatic check is silent.
8. Settings → General: the option, the last result and its date, Check Now; clearing the option and
   restarting with `updates.lastCheck` cleared makes no request (the server log stays empty).
9. About: the status line and Check Now (Install… when a version waits); opening About makes no request.
10. Install path: unit tests (`UpdateInstallerTests`) replace a fake app in a temporary folder and roll back
    on each failure; the real verifier accepts a copy of a system app and refuses another one.

## GUI check record (2026-10-14)

Test copy, Czech, local server on 127.0.0.1:8471: steps 1–9 passed. The automatic check made one request and
showed only the title-bar button; the click opened the window from the found release without a new request;
Remind Me Later, Esc and Skip This Version hid the button; 9.9.10 after the skip showed it again; with the
option off a restart made no request; About and Settings showed the state without requests; Install… in
About ran a check and opened the window; the "latest version" and "check failed" (port closed) messages
appeared with OK / Try Again. Found and fixed: the window opened on the screen with the keyboard focus, not
over the main window.
