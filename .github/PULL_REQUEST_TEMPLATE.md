<!-- Thanks! Pull requests are welcome; discussion may be in Czech or English, but everything committed (code, comments, docs, commit messages) is in English. -->

## What and why

<!-- Briefly: what the change does and what problem it solves. Link the issue: "Closes #123". -->

## How I verified it

- [ ] `swift build` without warnings
- [ ] `swift test` green
- [ ] Manually in the app (describe what and where — **only in a test directory**, never on real data)

## Checklist

- [ ] New files have the SPDX header (`GPL-3.0-or-later`)
- [ ] I did not read or copy the C++ sources of Tandem Commander / Open Salamander
      (the reference is behavior and documentation only — see [CONTRIBUTING.md](../CONTRIBUTING.md))
- [ ] Logic is in `CommanderCore` and has a test; the UI only calls into it
- [ ] New UI strings are in `Resources/Localizable.xcstrings` (with a Czech translation, if you can)
- [ ] Commits are signed off (`git commit -s`, Developer Certificate of Origin)
- [ ] Commit messages are in English, formatted `[Area] short description`
