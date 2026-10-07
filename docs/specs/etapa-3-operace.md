# Etapa 3 — souborové operace (zadání jádra)

Pravidla: `../tandemcommander/docs/macos-port/05-pravidla.md` (Identita, Přepsání, Přesun a odkaz).
Vše v `Sources/CommanderCore/Operations/`, testy Swift Testing v `Tests/CommanderCoreTests/`.

## API

```swift
public struct FileIdentity: Hashable, Sendable   // st_dev + st_ino (stat, follows links) / lstat variant
  static func of(_ url: URL, followingLinks: Bool = true) -> FileIdentity?   // nil = unknown → treat as "maybe same"

public enum OperationError: Error, Equatable {
  case sameFile(URL)            // copy/move onto itself (hard link, symlink, /tmp vs /private/tmp…)
  case intoItself(URL)          // folder into itself or its descendant (checked by identity of dest ancestors + realpath)
  case identityUnknown(URL)     // cannot prove different → refuse destructive part
  case sourceKeptBecauseOfLink(URL) // move would follow a dir symlink / traversal incomplete → source not deleted
  case path(PathError)
  case io(String)
  case cancelled
}

public enum ConflictResolution: Sendable { case overwrite, overwriteAll, skip, skipAll, rename(String), cancel }
public struct Conflict: Sendable { source: FileItemInfo; destination: FileItemInfo }  // name, size, date

public struct OperationProgress: Sendable {
  totalBytes, doneBytes: Int64; totalItems, doneItems: Int; currentName: String
}

public enum TransferKind: Sendable { case copy, move }

public struct TransferRequest: Sendable {
  kind; sources: [URL]; destinationDirectory: URL
  nameMask: String = "*.*"      // Windows-style target mask (e.g. "*.bak"), see NameMask
}

public actor FileOperations {
  public init()
  /// Validates first (all errors before any write), then runs. Progress via callback on any thread.
  public func transfer(_ request: TransferRequest,
                       progress: @Sendable (OperationProgress) -> Void,
                       conflict: @Sendable (Conflict) async -> ConflictResolution) async throws -> TransferReport
  public func trash(_ urls: [URL]) async throws -> [URL]          // FileManager.trashItem, returns trashed URLs
  public func deletePermanently(_ urls: [URL], progress: ...) async throws
  public func makeDirectory(named: String, in: URL) throws -> URL  // PathRules name validation
  public func rename(_ url: URL, to newName: String) throws -> URL // case-only rename allowed (same identity)
}
public struct TransferReport: Sendable { copied: Int; skipped: [URL]; keptSources: [URL] (move kept because of link rule) }

public enum NameMask { static func apply(_ mask: String, to name: String) -> String }  // "*.*" identity, "*.bak", "new_*.*"
```

## Chování

- Kopie souboru: `copyfile(3)` s `COPYFILE_ALL | COPYFILE_CLONE` (APFS clone), progress callback,
  storno = `COPYFILE_QUIT` mezi bloky. Zápis vždy do dočasného jména `.~icmd-<uuid>` v cílové složce,
  pak `rename(2)` na cíl (přes existující cíl atomicky). Chyba/storno → dočasný soubor smazat, cíl beze změny.
- Složka: rekurzivně, symlinky kopírovat jako symlinky (nesledovat).
- Přesun na stejném svazku: `rename(2)` (konflikt řešit předem). Mezi svazky: kopie, pak smazání zdroje
  jen když vše zkopírováno, nic přeskočeno a ve stromu nebyl symlink na adresář; jinak zdroj zůstane a
  report ho uvede v `keptSources`.
- Konflikt se ptá jen u existujícího cíle; `overwriteAll`/`skipAll` platí pro zbytek operace.
  Cíl, který je stejný soubor jako zdroj (identita), je `sameFile`, ne konflikt.
- Kontroly před zápisem: délka cesty cíle (PathRules), sameFile, intoItself.

## Testy (musí padnout při porušení)

1. Kopie souboru na jeho hard link → `sameFile`, oba odkazy a obsah beze změny.
2. Kopie přes `/tmp/x` vs `/private/tmp/x` → `sameFile`.
3. Kopie/přesun složky do vlastní podsložky → `intoItself`, strom beze změny.
4. Přepsání se stornem uprostřed (velký soubor, cancel v progress) → cíl má původní obsah, žádný `.~icmd-*`.
5. Přesun složky se symlinkem na adresář mezi „svazky" (simulovat vynucením copy+delete cesty) → soubory za odkazem existují, zdroj zůstal.
6. Konflikt skip/overwrite/rename; NameMask `*.bak`; case-only rename `a.txt` → `A.txt`.
7. Dvě jména NFC/NFD na APFS → konflikt (stejné jméno), ne dva soubory.
