## Installing this build

This build is **not notarized by Apple** (the project has no Apple Developer ID yet), so macOS
blocks it on first launch. It is meant for users who are comfortable with the steps below; if
you prefer, [build the app from source](https://github.com/axolotlcommander/axolotl-commander#from-source).

1. **Check the download** (optional): put `SHA256SUMS.txt` next to the file and run
   `shasum -a 256 -c SHA256SUMS.txt --ignore-missing`.
2. **Unpack and move** `Axolotl Commander.app` to `/Applications` (or `~/Applications`).
   Requires macOS 15 Sequoia or later; the app runs on Apple silicon and Intel.
3. **Allow it once:** open the app; macOS says it cannot verify the developer. Click *Done*,
   open *System Settings → Privacy & Security*, scroll down and click *Open Anyway* next to
   Axolotl Commander, then confirm with your password.
   Alternatively, in Terminal: `xattr -dr com.apple.quarantine "/Applications/Axolotl Commander.app"`.
4. **Folder access:** the first time you open Desktop, Documents, Downloads, iCloud Drive or an
   external or network disk, macOS asks whether to allow access, once per place. To allow
   everything at once, add the app to *System Settings → Privacy & Security → Full Disk Access*.

**Updating:** replace the app with the new one and allow it once more (step 3). The folder access
you granted stays, because every release is signed with the same project certificate.
