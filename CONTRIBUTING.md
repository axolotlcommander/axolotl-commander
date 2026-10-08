# Contributing to Axolotl Commander

Thanks for your interest! Bug fixes, new features, translations, tests, and problem reports are
all welcome.

## Language

Everything committed to the repository is in English: code, comments, documentation, specs,
commit messages, and the texts in issue and pull request templates. You are welcome to discuss
issues and pull requests in Czech or English.

## Before you start

- Send small fixes straight away as a pull request.
- For a larger change or a new feature, start with a discussion: open an
  [issue](https://github.com/axolotlcommander/axolotl-commander/issues) or a thread in
  [Discussions](https://github.com/axolotlcommander/axolotl-commander/discussions), so we can agree
  on the behavior before you write a lot of code. Once the idea is agreed, the feature gets a spec
  in `specs/NNN-name/`, written in English via Spec Kit (see [Pull requests](#pull-requests)).
- Behavior follows the reference programs, [Tandem Commander](https://github.com/tandemcommander/tandemcommander)
  and [Open Salamander](https://github.com/OpenSalamander/salamander), adapted to macOS conventions.
  The development plan is in [docs/PLAN.md](docs/PLAN.md), the principles in
  [.specify/memory/constitution.md](.specify/memory/constitution.md).

## Building and testing

Requires macOS 15+ and Swift 6.2 (Xcode 26 or the Command Line Tools). No Xcode project is needed.

```sh
swift build                  # build (must pass without warnings)
swift test                   # core tests
swift run AxolotlCommander   # run
scripts/bundle.sh            # build/Axolotl Commander.app
```

Layout:

- `Sources/CommanderCore` — the AppKit-free core (operations, archives, network, search, ...).
  All decision logic belongs here and has tests.
- `Sources/AxolotlCommander` — the AppKit user interface; only dialogs and calls into the core.
- `Tests/CommanderCoreTests` — tests (Swift Testing).
- `specs/` — feature specifications ([Spec Kit](https://github.com/github/spec-kit)).

## Binding rules

### 1. Data safety

A file manager must never lose data. Therefore:

- Tests work **only in a temporary directory** that they create themselves
  (`FileManager.default.temporaryDirectory`) and clean up afterwards — see
  `Tests/CommanderCoreTests/TestSupport.swift`. They never touch real files, the real Trash, the
  Keychain, or real servers (network tests use a local `sftp-server` and
  `scripts/ftp-test-server.py`).
- Do manual checks of operations (copy, move, delete, ...) only in a test directory.
- An operation that could destroy data is refused with a clear message instead.
- Every behavior fix comes with a test that fails without the fix.

### 2. Clean-room implementation

The project is a new implementation of the reference programs' **behavior**, not a port of their
code.

- **Do not read or copy the C++ sources** of Tandem Commander or Open Salamander
  (`src/**/*.cpp|h|rc`). The reference is the behavior of the running program, its user help, and
  its documentation.
- Do not copy help and dialog texts verbatim; write your own.
- A new dependency needs a license compatible with GPL-3.0; record it in
  [THIRD_PARTY.md](THIRD_PARTY.md).

## Conventions

- Code, identifiers, comments, documentation, and specs (`specs/`) are in English.
- Every new source file starts with this header:

  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 The Axolotl Commander Authors
  ```

- New UI strings go into `Resources/Localizable.xcstrings` (English is the source, Czech a translation).
- A command that is not finished yet stays grayed out in the menu; it must not crash.
- Commit message format: `[Area] short description` in English
  (e.g. `[Archive] Refuse moving an archive into itself`). Work on a feature from a spec uses
  `[Spec NNN] ...` (e.g. `[Spec 001] ...`).

## Pull requests

1. Fork the repository and branch from `main`.
2. Keep the change small and focused on one topic; add tests.
3. `swift build` without warnings and `swift test` green (CI checks the same).
4. Open a pull request and fill in the template. Every PR needs maintainer approval
   (see [CODEOWNERS](.github/CODEOWNERS)) and green CI; PRs are merged into `main` by *squash*.

Larger features go through Spec Kit: `/speckit-specify` → `/speckit-plan` → `/speckit-tasks` →
`/speckit-implement`. The spec is written in English in `specs/NNN-name/` and belongs in the
pull request.

Releasing new versions is described in [docs/RELEASING.md](docs/RELEASING.md).

## Origin of contributions (DCO)

Sign off every commit with the `-s` option (`git commit -s`). This certifies the
[Developer Certificate of Origin](https://developercertificate.org/): the contribution is yours
(or you are allowed to submit it), and you agree to its release under the GPL-3.0-or-later license.

If you use an AI assistant while writing, you are as responsible for the result as for your own
code — including the clean-room rule above.

## Community conduct

The [Code of Conduct](CODE_OF_CONDUCT.md) applies. Report security vulnerabilities privately as
described in [SECURITY.md](SECURITY.md).
