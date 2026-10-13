# Quickstart: Volumes in the Go Menu and Ejecting Volumes

Everything runs on the test copy of the app (own bundle id). The only volume ever ejected is a disk
image created in the session's scratch folder.

## Setup

```sh
T=<scratchpad>/gt/data/c22; mkdir -p $T/src
hdiutil create -size 20m -fs APFS -volname AxTest $T/axtest.dmg
hdiutil attach $T/axtest.dmg            # mounts /Volumes/AxTest
mkfile 200m $T/src/big.bin              # for the refusal test (copy takes a moment)
```

At the end: `hdiutil detach /Volumes/AxTest` if it is still mounted, and remove `$T`.

## Menus (US2)

1. The menu bar has no Left and Right menus; Go has "Left Volume…" (⌥F1) and "Right Volume…" (⌥F2).
2. ⌥F1 / ⌥F2 open the volume pickers.

## ⌘E (US1)

1. Left panel on the startup disk: Commands → "Eject Volume" is greyed out.
2. Left panel on `/Volumes/AxTest`, right panel too, a second tab on it: Commands shows
   "Eject “AxTest”"; ⌘E → both panels and the tab show the home folder; AxTest disappears from the
   volume bar and from `/Volumes`.
3. Attach again; F5 `big.bin` into AxTest and press ⌘E during the copy → a message names the copy;
   AxTest stays; the copy finishes.
4. Open a file of AxTest in another process (`tail -f /Volumes/AxTest/x.txt &`), ⌘E → panels go home,
   the system's reason is shown, AxTest stays mounted; stop `tail`.

## Volume bar (US3)

1. Hover the AxTest button → ⏏ appears; the Macintosh HD button shows none.
2. Right click AxTest → "Eject “AxTest”", "Volume Information…"; Volume Information shows AxTest.
3. Click ⏏ → AxTest is ejected.

## F12 (US4)

1. With no server connected and AxTest attached: F12 lists AxTest under Disks; with the active panel
   on AxTest it is checked; the button reads "Eject".
2. ↓/↑ move, Space toggles, Esc cancels; Return ejects AxTest.
3. With AxTest detached and no server: "Disconnect…" is greyed out.
