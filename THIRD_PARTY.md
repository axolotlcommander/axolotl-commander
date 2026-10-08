# Software třetích stran

| Komponenta | Použití | Licence | Jak se dodává |
|---|---|---|---|
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | náhled Markdownu v prohlížeči | Apache-2.0 (s Runtime Library Exception) | staticky přilinkováno |
| [swift-cmark](https://github.com/swiftlang/swift-cmark) | parser pro swift-markdown | BSD-2-Clause | staticky přilinkováno |
| libarchive | archivy | BSD-2-Clause | systémová knihovna macOS (nedodává se) |
| libcurl | FTP | curl (MIT-like) | systémová knihovna macOS (nedodává se) |
| OpenSSH (`ssh`, `sftp`) | SFTP | BSD | systémové nástroje macOS (nedodávají se) |

Apache-2.0 je slučitelná s GPL-3.0 (ne s GPL-2.0-only), proto Axolotl Commander používá
GPL-3.0-or-later. Systémové knihovny a nástroje macOS spadají pod výjimku GPL pro
„System Libraries“.
