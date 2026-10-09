# Axolotl Commander — a native macOS port of Tandem Commander

Reference behavior: [Tandem Commander](https://github.com/tandemcommander/tandemcommander)
(Windows, WinAPI), cloned next to this repository as `../tandemcommander`. Port analysis:
`../tandemcommander/docs/macos-port/` (local notes, not published).
Stage plan: `docs/PLAN.md`.
Principles: `.specify/memory/constitution.md`. New features go through Spec Kit
(`/speckit-specify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-implement`), specs in
`specs/NNN-name/`.
Private instructions for your own machine belong in `CLAUDE.local.md` (listed in `.gitignore`).

## Language (binding)

- **Everything committed to git is in English**: code, comments, documentation, specs, plans,
  tasks, commit messages, PR descriptions and issue templates. The only exception is
  localized UI text in the String Catalogs `Resources/Localizable.xcstrings` and
  `Resources/InfoPlist.xcstrings` (English source + translations).
- **Talk to each contributor in their own language.** Discussion, questions, summaries and
  reports go in the language the contributor writes in; whatever ends up in git is written
  in English.
- Input from the contributor that goes into git (a feature description, wording of a message,
  a requirement) is used **as written when it is in English**; in any other language you
  translate it into English before it goes into a spec, code comment or commit message.
- It works both ways: when you present an existing spec, plan, task list or review, or ask
  Spec Kit clarification questions, translate it into the contributor's language. Feedback
  given in their language is applied to the English documents.
- Local files that are not committed (`CLAUDE.local.md`, files listed in `.gitignore`) may be
  in any language.

## New features

New features get a spec in `specs/NNN-name/` through Spec Kit (written in English, see
above). Small changes (a bug fix, a layout tweak, a new shortcut) do not need a spec: a test and a
commit are enough.

## Versioning

- [Semantic Versioning](https://semver.org/); before 1.0 the version is `0.MINOR.PATCH`. The single
  source is the `VERSION` file: `scripts/bundle.sh` and the release workflow read it.
- Every pull request that changes the app raises the version in the same pull request with
  `scripts/bump-version.sh minor|patch` (it also moves the "Unreleased" items of `CHANGELOG.md`
  under the new version with today's date):
  - **minor**: a new feature (a merged spec) or a change in behavior or settings;
  - **patch**: a bug fix, a layout tweak, a new shortcut, a translation fix;
  - **no change**: documentation, specs, CI and scripts only.
- Pull requests from forks do not have to raise the version; the maintainer does it before merging.
- After the merge into `main`, tag the merge commit `vX.Y.Z` (the version in `VERSION`) and push the
  tag; the release workflow builds a draft release (see [docs/RELEASING.md](docs/RELEASING.md)).

## Workflow

- Commit after every completed step (build without warnings, `swift test` green).
- Do not read large files in full: `../tandemcommander/CLAUDE.md` is ~150 kB — use `grep`
  and targeted excerpts.

## File system safety (binding)

- **Never run file operations (copy, move, delete, rename, write) on the user's real
  data** — neither in GUI tests nor in unit tests.
- Tests only in an isolated directory (`FileManager.default.temporaryDirectory`) that the test
  creates and removes itself. GUI test of operations: first point both panels to such a test
  directory, only then send F5/F6/F8/F2…
- GUI tests outside the test directory may only read (browse, select, sort).
- Run GUI tests on a copy of the app with its own bundle id (not `cz.acidek.axolotlcommander`),
  so they do not touch the settings of the installed app.
- Deleting your own artifacts (`build/`) is fine.

## License and clean-room implementation (binding)

- The project is `GPL-3.0-or-later`. Every new source file starts with the header
  `// SPDX-License-Identifier: GPL-3.0-or-later` + `// Copyright (C) 2026 The Axolotl Commander Authors`.
- The reference is **behavior**: the help (`../tandemcommander/help/`), `docs/macos-port/`,
  `specs/` and the running program. **Do not read or quote the reference C++ sources
  (`../tandemcommander/src/**/*.cpp|h|rc`)** — not even in subagents. Exceptions only on an
  explicit instruction from the project maintainer, and then record in `NOTICE` what was taken
  from where.
- Do not copy help or dialog texts verbatim; write your own wording.
- New dependencies only with a GPL-3.0-compatible license; record them in `THIRD_PARTY.md`.

## Technology

- Swift + AppKit, Swift Package Manager (`swift build`, `swift test`), no Xcode project.
- Run: `swift run AxolotlCommander` or `scripts/bundle.sh` → `build/Axolotl Commander.app`.
- Core (`Sources/CommanderCore`) without AppKit → testable with `swift test`.
- UI (`Sources/AxolotlCommander`) AppKit.

## Conventions

- Commit messages: `[Area] short description` (e.g. `[Archive] Refuse moving an archive into
  itself`); work from a spec: `[Spec NNN] …`; plan stages: `[Stage N] …`. The subject line
  has at most 72 characters; details go into the body after a blank line.
- An unfinished menu command stays grayed out (disabled) and never crashes.
