# Quickstart: App Updates — validation

Unit tests: `swift test --filter Update`.

GUI check on the test copy (`cz.acidek.axolotlcommander.gtest`, in the session scratchpad). Never against the
real server, never over the installed app.

1. Start a local server in the scratchpad on 127.0.0.1 (not port 8765) serving `releases/latest` (JSON per
   [contracts/release.md](contracts/release.md)) with version 9.9.9, its zip, `SHA256SUMS.txt` and both
   changelogs (with a 9.9.9 section). `defaults write cz.acidek.axolotlcommander.gtest updates.feedURL
   http://127.0.0.1:PORT/releases/latest`; clear `updates.lastCheck`.
2. Start the test copy: ~5 s after the main window the update window shows 0.6.0 → 9.9.9 with the Czech
   notes; the default button is Download… with the reason "development or ad-hoc build" (the test copy is
   ad-hoc signed).
3. Remind Me Later (Esc) → restart: no window. `updates.remindAfter` is a day later.
4. App menu → Check for Updates… → the window again (manual check ignores remind-later).
5. Skip This Version → restart with `updates.lastCheck` cleared: no window; serve 9.9.10 → the window.
6. Serve version 0.6.0 → Check for Updates…: "Axolotl Commander 0.6.0 is the latest version."
7. Stop the server → Check for Updates…: the failure reason with Try Again; the automatic check is silent.
8. Settings → General: the option, the last result and its date, Check Now; clearing the option and
   restarting with `updates.lastCheck` cleared makes no request (the server log stays empty).
9. About: the status line and Check Now; opening About makes no request.
10. Install path: unit tests (`UpdateInstallerTests`) replace a fake app in a temporary folder and roll back
    on each failure; the real verifier accepts a copy of a system app and refuses another one.
