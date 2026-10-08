# Quickstart: Validating Server Buttons, iCloud Drive and Network

## Prerequisites

- `swift build` without warnings, `swift test` green.
- Test copy of the app (`iCmdTest.app`, bundle id `cz.acidek.axolotlcommander.gtest`) built with
  `scripts/bundle.sh debug`, settings of the test copy reset, toolbar not customized.
- Local test servers only: the test SFTP server on `127.0.0.1:2222` and the FTP test server
  (`scripts/ftp-test-server.py`) on a free local port, each serving a scratch folder with `data/sub`.
  Never real servers.
- Both panels start in a scratch folder `<test>`.
- Before every click batch, read the test window's frame again; keys only when the test app is
  frontmost.

## Scenarios

| # | Steps | Expected |
|---|---|---|
| Q1 | Launch | Toolbar has "Connect to Server"; volume bars: volumes, iCloud Drive (if set up), Network |
| Q2 | Click "Connect to Server" in the toolbar | Connect dialog for the active panel, as ⌘K |
| Q3 | Connect the left panel to SFTP `127.0.0.1:2222` | Button "127.0.0.1" at the end of both volume bars; pressed in the left one |
| Q4 | Left panel into `data/sub`, then Backspace to `<test>` via history (local), click the server button | Left panel back in `data/sub`; Back returns to `<test>` |
| Q5 | Click the server button in the right volume bar | Right panel in `data/sub` too |
| Q6 | Also connect FTP to `127.0.0.1` with another user | Labels change to `user@127.0.0.1` for both (or protocol prefix when equal) |
| Q7 | Hover a server button, click ⏏ | Connection closed without a dialog; button gone in both bars; panels on it go home |
| Q8 | Right-click a server button: Open in Other Panel; Copy Address | Other panel at the last folder and active; clipboard = `sftp://user@127.0.0.1:2222/data/sub` (no password) — Copy Address only if the maintainer allows touching the clipboard |
| Q9 | Stop the SFTP test server, click its button | Error as today, button stays; start the server, click again → reconnects |
| Q10 | ⌥F1 | Volume menu has "Servers" with the connections; choosing one = button click |
| Q11 | Click "iCloud Drive" (read only) | Left panel at the top of iCloud Drive; iCloud Drive pressed, Macintosh HD not |
| Q12 | Click "Network" | Menu: mounted network volumes (if any), servers, Connect to Server… |
| Q13 | Settings → Appearance: Home on, Network off, Server connections off | All bars update at once: Home shown, Network and server buttons gone; servers still in ⌥F1 and survive relaunch |
| Q14 | Narrow the window to its minimum | Items disappear from the end; volumes stay |
| Q15 | F12 dialog with a dropped connection | The dropped connection is listed and can be closed; its button disappears |
| Q16 | AX inspection | Server button = button with label; eject = "Disconnect <label>" |
