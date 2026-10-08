<!--
Sync Impact Report
- Version: 1.0.0 → 1.1.0 (translated to English; new principle VII Language; stage commit
  prefix renamed to `[Stage N]`)
- Principles: I User data safety, II Faithful reference behavior, III Native macOS,
  IV Testable core, V Clean-room implementation and GPL, VI Incremental delivery, VII Language
- Templates: plan/spec/tasks-template.md unchanged (Constitution Check reads this file)
- Deferred: none
-->

# Axolotl Commander Constitution

This constitution governs all work, inside Spec Kit (`/speckit-*`) and outside it. Operational
details (paths, scripts, test app) are in `CLAUDE.md`, the stage plan in `docs/PLAN.md`.

## Core Principles

### I. User data safety (NON-NEGOTIABLE)

- No file operation (copy, move, delete, rename, write) on the user's real data — not in unit
  tests, not in GUI tests, not while debugging.
- Tests work only in a directory they create themselves in `temporaryDirectory`/a scratch
  directory and remove afterwards. A GUI test of operations first points both panels to the
  test directory.
- Destructive commands in the app ask first, delete to the Trash (if the volume supports it)
  and report errors; they never overwrite silently.

*Why:* nobody keeps using a file manager that has lost their data once.

### II. Faithful reference behavior

- Keys, commands, dialogs and the results of operations match Tandem Commander / Open
  Salamander (help in `../tandemcommander/help/`, `../tandemcommander/docs/macos-port/`).
- A deviation is allowed only where macOS has a strong convention (⌘ shortcuts, Trash, volumes
  instead of drive letters, menu bar) or where the system intercepts the key; every deviation
  is recorded in the spec.
- An unfinished command is grayed out in the menu, it never crashes.

### III. Native macOS, done the modern way

- Swift 6 (strict concurrency), AppKit, SwiftPM without `.xcodeproj`; minimum system macOS 15.
- System services instead of custom ones (Trash, Finder, Quick Look, Keychain, Terminal,
  NSWorkspace).
- No blocking of the main thread on I/O; long operations can be cancelled and show progress.
- Localization through the String Catalog (en, cs); UI texts are never hard-coded without
  `String(localized:)`.

### IV. Testable core

- `CommanderCore` does not depend on AppKit; logic (panel model, masks, operations, parsers)
  lives in the core and is covered by `swift test` (Swift Testing).
- Every bug fix in the core adds a test that catches the bug.
- A build without warnings and green tests are a precondition for every commit.

### V. Clean-room implementation and GPL

- License `GPL-3.0-or-later`; every source file carries the SPDX header.
- The reference is behavior and documentation, not code: the reference C++ sources
  (`../tandemcommander/src/`) are not read or quoted (exceptions only on the maintainer's
  explicit instruction, recorded in `NOTICE`). Help and dialog texts are written anew.
- Dependencies only with a GPL-3.0-compatible license, recorded in `THIRD_PARTY.md`.

### VI. Incremental delivery

- Work proceeds by the stages in `docs/PLAN.md` and by specs; every feature can be finished and
  used on its own.
- The simpler solution wins (YAGNI); optimize only after measuring.
- Commit after every step: `[Stage N] …`, `[Spec NNN] …` or `[Area] …`.

### VII. Language

- Everything committed to git is in English: code, comments, documentation, specs, plans,
  tasks and commit messages. Localized UI text lives only in the String Catalog.
- Contributors discuss in their own language. Agents talk to each contributor in that
  language, translate existing documents for them on request, and write the agreed result
  into git in English.

## Development workflow (Spec Kit)

1. Discussion in the contributor's language, ending with a summary they confirm.
2. `/speckit-specify` — the feature spec in `specs/NNN-name/spec.md`, in English (what and why,
   behavior following the reference, macOS deviations, keyboard-driven acceptance scenarios).
3. `/speckit-clarify` (optional) — resolve open questions before the plan.
4. `/speckit-plan` — technical plan; the *Constitution Check* section verifies principles I–VII.
5. `/speckit-tasks` → `/speckit-analyze` (optional) → `/speckit-implement`.
6. Done = build without warnings, `swift test` green, keyboard scenario verified in the test
   copy of the app.

Small fixes (a bug, a layout tweak) do not have to go through the whole cycle; a test and a
commit are enough.

## Governance

- The constitution takes precedence over other practices; a conflict is resolved by amending
  the constitution, not by an exception.
- Amendment: edit this file with a rationale, bump the version (MAJOR = a principle removed or
  changed, MINOR = a new principle or section, PATCH = a clarification), update the affected
  templates.
- Compliance review: every plan (`plan.md`) and every code review.

**Version**: 1.1.0 | **Ratified**: 2026-10-08 | **Last Amended**: 2026-10-08
