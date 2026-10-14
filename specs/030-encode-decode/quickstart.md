# Quickstart: Encode and Decode Files — validation

Unit tests: `swift test --filter FileCodec`.

GUI check on the test copy (`cz.acidek.axolotlcommander.gtest`) in Czech. First point both panels to test
folders in the session scratchpad (`codec/src` with a 200 KB random file `pic.bin`, a file `Příliš.txt`, a
saved e-mail `mail.eml` with two attachments (Base64 and quoted-printable, one with an RFC 2047 name), a UUE
file `evil.uue` named `../../evil`, a UUE file `cut.uue` without `end`, and two pieces `part1.uue`,
`part2.uue` of one UUE file; `codec/out` empty); only then run the commands.

1. Cursor on `pic.bin`, File → Encode File…: the dialog shows the name, "To:" `codec/out` and the format;
   no Czech text is cut. Base64 → `codec/out/pic.bin.b64` with the MIME header; the cursor on it.
2. Mark `pic.bin` and `Příliš.txt`, Encode File… with UUE: two `.uue` files appear.
3. In `codec/out`, cursor on `pic.bin.b64`, Decode File… into `codec/src` → the conflict question for
   `pic.bin` (spec 021); Skip leaves the original; again with "Keep both" → the decoded copy equals the
   original (`cmp`).
4. Decode `mail.eml` into `codec/out`: both attachments with their names; the result lists them.
5. Decode `evil.uue`: `evil` appears inside `codec/out`; nothing outside it.
6. Decode `cut.uue`: written and reported as incomplete.
7. Mark `part1.uue` and `part2.uue`, Decode File…: one file, equal to the original.
8. Decode `small.txt` (plain text): "No encoded data was found"; nothing written.
9. Decode a large UUE file (300 MB) and cancel during progress: `codec/out` holds exactly what it held before.
