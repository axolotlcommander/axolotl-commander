# Contract: nové a změněné API jádra (CommanderCore)

Interní rozhraní mezi jádrem a UI. Signatury jsou závazné pro testy; těla řeší implementace.

## Síť (D1)

```swift
public protocol RemoteFileSystem: Actor {
    // nové; výchozí implementace v extension vrací false
    /// Vymění `to` za `from` jedním krokem. false = server to neumí a nic se nezměnilo.
    func replace(_ from: String, over to: String) async throws -> Bool
}
public enum RemoteError { case replaceIncomplete(target: String, newAt: String, oldAt: String) }
```

`RemoteTransfer.upload(... .overwrite)` a `renameOnServer` s přepisem používají sekvenci
replace → (záloha, výměna, úklid) z research R1. Invarianty:
- v žádném kroku není cíl smazán bez existující úplné verze pod známým jménem;
- selhání nahrávání nemění cíl a uklidí temp;
- `replaceIncomplete` nese jména, pod kterými leží nová a stará verze.

## Úpravy členů archivu (D2)

```swift
public final class ArchiveEditStore: Sendable {
    public init(root: URL)
    public static let defaultRoot: URL   // ~/Library/Application Support/Axolotl Commander/Edits
    public func begin(target: PendingEdit.Target, archiveStamp: PersistentFileStamp?,
                      makeCopy: (URL) throws -> Void) throws -> PendingEdit
    public func copyURL(_ edit: PendingEdit) -> URL
    public func changed() -> [PendingEdit]              // kopie ≠ baseline nebo declined
    public func markSaved(_ id: UUID, archiveStamp: PersistentFileStamp?) throws
    public func decline(_ id: UUID) throws               // zachovat na příště
    public func discard(_ id: UUID) throws               // smazat kopii i záznam
    public func cleanupForQuit() throws -> [PendingEdit] // uklidí nezměněné, vrátí zachované
    public func loadPending() throws -> [PendingEdit]    // při startu
    public func verifyArchiveUnchanged(_ edit: PendingEdit) throws  // ArchiveError.changedSinceRead
}
```

## Archiv do sebe (D3, D7)

```swift
public enum ArchiveTransferCheck {
    public static func validate(source: ArchivePath?, names: [String], target: ArchivePath) throws(OperationError)
    public static func validatePack(archive: URL, sources: [URL]) throws(OperationError)
}
```

## Mazání (D4)

```swift
public struct DeletePlan: Sendable { public var toTrash: [URL]; public var permanent: [URL] }
public struct TrashReport: Sendable {
    public var trashed: [(original: URL, inTrash: URL)]
    public var failed: (url: URL, reason: String)?
    public var notAttempted: [URL]
}
extension FileOperations {
    public func planDelete(_ urls: [URL]) -> DeletePlan
    public func trash(_ urls: [URL]) async -> TrashReport   // dříve async throws -> [URL]
}
```

Seamy (internal, pro testy): `FileOperations.Options.trashAvailable: @Sendable (URL) -> Bool`,
`.trashItem: @Sendable (URL) throws -> URL`, `.volumeTraits: @Sendable (URL) -> VolumeTraits`.

## Identita (D5) a přejmenování (D8)

- `FileIdentity` získá `reliable: Bool`; `FileStat` získá `linkCount`.
- `TransferPlanner.plan`/`validateNested`, `TransferRun.resolve`: existující cíl + mazání zdroje
  + `!reliable` → `.identityUnknown`.
- `FileOperations.rename`: shodná identita, jiný záznam (`st_nlink > 1`) → `.alreadyExists`.

## UI (AxolotlCommander) — chování, ne API

- F8: `planDelete` → pokud `permanent` neprázdné, jeden kritický dotaz (výchozí Zrušit) se seznamem
  → `trash(toTrash)` → při `failed == nil` trvalé smazání `permanent` → report.
- Ukončení: `cleanupForQuit`; zachované úpravy → informativní hláška s cestou.
- Start: `loadPending` neprázdné → jeden přehled (Vrátit / Zahodit / Teď ne).
- „Uložit jako“: `SafeFileWriter.write(to:)`.
