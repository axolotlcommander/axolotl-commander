# Quickstart: Split and Combine Files — validation

Unit tests: `swift test --filter SplitCombine`.

GUI check on the test copy (`cz.acidek.axolotlcommander.gtest`) in Czech. First point both panels to test
folders in the session scratchpad (`split/src` with a 60 MB random file `data.bin` and a 5 KB `small.txt`,
`split/out` empty); only then run the commands.

1. Cursor on `data.bin`, File → Split File…: the dialog shows the name, the size, "To:" `split/out`, the part
   size and "Creates N parts"; no Czech text is cut.
2. Pick 25 MB: 3 parts. Custom `10M` → 6, `1,5 G` → "not larger than one part", `abc` → invalid, `1k` →
   too many parts; OK disabled for the last three.
3. 25 MB, checksum on, OK: `split/out` shows `data.bin.001` … `.003` and `data.bin.crc`, the cursor on
   `.001`; `data.bin` unchanged (`cmp` with a copy made before).
4. Split again into `split/out`: one question lists the four existing names; Cancel leaves them unchanged
   (modification dates); Replace writes the new set.
5. Cursor on `data.bin.002` in `split/out`, File → Combine Files…, target `split/src/joined.bin`: the
   dialog says 3 parts and that the result is checked; OK → "matches the checksum file"; `cmp` equal.
6. Combine from `data.bin.crc`: the proposed name is `data.bin`; target `split/src` → conflict question
   (spec 021); Skip leaves the original.
7. Mark `.001`–`.003` (without the `.crc`) and combine: not checked; result equal.
8. Change one byte of `.002` (a test file, by a script) and combine with the `.crc`: the mismatch warning with
   expected and actual values; the file is kept.
9. Remove `.002` and combine: the message names `data.bin.002`; nothing written.
10. Split a larger file (300 MB) and cancel during progress: `split/out` holds exactly what it held before.
