# Quickstart: Branch View

## Unit tests

```sh
swift test --filter "BranchScannerTests|PanelModelBranchTests"
swift test
```

The tests cover:
- **`BranchScanner`** on a temporary folder the test creates and removes:
  - files only;
  - the names relative to the folder;
  - duplicate names;
  - hidden files with and without `includeHidden`;
  - a link to a folder, not entered;
  - a package, listed as a file;
  - an unreadable folder (permissions `000`, restored after the test), counted;
  - cancellation;
  - progress calls;
  - marked items.
- **`BranchScanner` with an in-memory `FileSource`**, for archive-like and server-like URLs.
- **`PanelModel`**:
  - `showBranch`;
  - ⌃B back, with the cursor kept;
  - `goParent`;
  - name sorting and quick search by the file name;
  - `refresh` rescanning;
  - `branch` not encoded in `PanelState`.
- **Grouping of archive sources by folder.**

## GUI check (test copy only)

1. Build the test copy with `gt/rebuild.sh` (bundle id `cz.acidek.axolotlcommander.gtest`).
2. Create a scratchpad test tree:
   - `a.txt`, `notes.txt`, `docs/notes.txt`, `docs/deep/d.txt`, `.hidden/h.txt`;
   - a link `loop -> .`;
   - a ZIP of the tree;
   - a big tree of 100 000 empty files, made with a script.
3. Point both panels to the test tree before launch (`gt/setlayout.sh`). Also create an empty
   target folder.
4. ⌃B. **Expected**:
   - five files, no folders, and no files through `loop`;
   - the status bar on `d.txt` reads "docs/deep/d.txt …";
   - the path bar ends with "Větev".
5. ⇧⌘. (show hidden). **Expected**: `h.txt` appears after the rescan.
6. Mark both `notes.txt` files and press F5 to the target. **Expected**: one copy, then the conflict
   question for the second.
7. ⌃B. **Expected**: the normal listing, with the cursor kept.
8. Enter the ZIP, then ⌃B. **Expected**: the archive's files; F3 works.
9. On the big tree, ⌃B then Esc. **Expected**: the scan stops at once, and the normal listing stays.
10. F8 on a file in the test tree only. **Expected**: it is deleted, and the branch is rescanned.
