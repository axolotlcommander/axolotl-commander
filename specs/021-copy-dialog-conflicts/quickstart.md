# Quickstart: Copy Dialog and Replace Question

Everything runs on the test copy of the app (own bundle id) with both panels in a scratch folder.

## Setup

```sh
T=<scratchpad>/gt/data/c21
mkdir -p $T/a $T/b
printf 'new\n' > $T/a/x.txt; printf 'old text\n' > $T/b/x.txt; touch -t 202601010101 $T/b/x.txt
for i in 1 2 3; do printf "n$i\n" > $T/a/p$i.jpg; printf "o$i\n" > $T/b/p$i.jpg; done
touch -t 202601010101 $T/b/p1.jpg; touch -t 203001010101 $T/b/p2.jpg   # p1 older, p2 newer, p3 same day
```

Point the left panel to `a` and the right panel to `b` (`window.layout` deleted, `panel.*.path` set).

## Replace question (US1, US2)

1. F5 on x.txt, Return: the question shows "newer" and "larger" on the right sides and the hint line.
2. F3 → viewer with "old text"; close it → the question is back. ⇧F3 → "new". ⌥F3 → Compare Files.
3. Esc: nothing copied.

## More… (US5)

1. Mark p1–p3, F5, Return; More… → Overwrite All Older: p1 replaced, p2 and p3 skipped, no more
   questions.
2. Again with x.txt: More… → Rename Automatically → `b/x 2.txt`; once more → `b/x 3.txt`.
3. More… → Rename… → type `x.txt` → refused; type `y.txt` → `b/y.txt`.

## Copy dialog (US3, US4)

1. F5 on x.txt: "To:" is `…/b/x.txt` with `x` selected; F5 → `txt`; F5 → folder part; F5 → all.
2. Type `x-copy` over the name, Return → `b/x-copy.txt`.
3. F5, ⌥↓: the menu lists b, the tab folders, hot paths and the recent destination `b`; ⌃D lists the hot
   paths only.

## Unit tests

```sh
swift test --filter 'ConflictPolicy|TransferTarget|DestinationMenu|AutoName|ConflictMarks'
```
