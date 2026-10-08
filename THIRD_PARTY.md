# Third-party software

| Component | Used for | License | How it is shipped |
|---|---|---|---|
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | Markdown preview in the viewer | Apache-2.0 (with Runtime Library Exception) | statically linked |
| [swift-cmark](https://github.com/swiftlang/swift-cmark) | parser for swift-markdown | BSD-2-Clause | statically linked |
| libarchive | archives | BSD-2-Clause | macOS system library (not bundled) |
| libcurl | FTP | curl (MIT-like) | macOS system library (not bundled) |
| OpenSSH (`ssh`, `sftp`) | SFTP | BSD | macOS system tools (not bundled) |
| [Spec Kit](https://github.com/github/spec-kit) | spec-driven workflow (`.specify/`, `.claude/skills/speckit-*`) | MIT | development tooling in the repository, not part of the app |

Apache-2.0 is compatible with GPL-3.0 (but not with GPL-2.0-only), which is why Axolotl Commander
uses GPL-3.0-or-later. The macOS system libraries and tools fall under the GPL's "System
Libraries" exception.

The full license texts and notices of the components above are in
[THIRD_PARTY_LICENSES.txt](THIRD_PARTY_LICENSES.txt), which is also copied into the app bundle.
