# Quickstart: File Sizes Like Finder

## Unit tests

```sh
swift test --filter SizeFormatTests
swift test
```

The tests cover:
- `rounded` in both bases for cs_CZ and en_US: 0, 1, 402, 999, 1 000, 1 023, 1 024, 4 300 000,
  46 000 000 and 1.2 × 10¹² bytes, against the table in research.md R1;
- `columnVariants` in both modes;
- `roundedIsExact`;
- the defaults when the keys are missing or unknown.

## GUI check (test copy only)

1. Build the test copy (own bundle id `cz.acidek.axolotlcommander.gtest`).
2. Create a test folder in the scratchpad with files of the sizes above (`mkfile -n`).
3. Point both panels to it before launch: the `panel.left.path` and `panel.right.path` defaults of
   the test bundle id.
4. Default settings. **Expected**:
   - the Size column reads "402 bajtů", "4,3 MB", "1,2 TB"…;
   - the status bar on the 4 300 000-byte file reads "4,3 MB (4 300 000 bajtů)";
   - the tooltip of its cell reads "4 300 000".
5. Settings (⌘,) → Vzhled → Velikost v panelech: V bajtech. **Expected**: both panels show
   "4 300 000" at once; the cursor and selection are kept.
6. Jednotky: 1024. **Expected**:
   - in the "In bytes" mode with a narrow column, the fallback reads "4,1 MB";
   - with "Like Finder" the column reads "4,1 MB";
   - the status bar total uses 1024.
7. Narrow the Size column to its minimum. **Expected**: "…" and never a cut number.
8. Quit and relaunch. **Expected**: both settings are kept.
