# Contract: New and Changed Core API (CommanderCore)

Internal interface between the core and the UI. Signatures are binding for tests; bodies are up to the implementation.

## Network (D1)

```swift
public protocol RemoteFileSystem: Actor {
    // new; the default implementation in an extension returns false
    /// Replaces `to` with `from` in a single step. false = the server cannot do it and nothing changed.
    func replace(_ from: String, over to: String) async throws -> Bool
}
public enum RemoteError { case replaceIncomplete(target: String, newAt: String, oldAt: String) }
```

`RemoteTransfer.upload(... .overwrite)` and `renameOnServer` with overwrite use the sequence
replace → (backup, swap, cleanup) from research R1. Invariants:
- at no step is the target deleted without a complete version existing under a known name;
- an upload failure leaves the target unchanged and cleans up the temp file;
- `replaceIncomplete` carries the names under which the new and the old version are stored.

## Archive Member Edits (D2)

```swift
public final class ArchiveEditStore: Sendable {
    public init(root: URL)
    public static let defaultRoot: URL   // ~/Library/Application Support/Axolotl Commander/Edits
    public func begin(target: PendingEdit.Target, archiveStamp: PersistentFileStamp?,
                      makeCopy: (URL) throws -> Void) throws -> PendingEdit
    public func copyURL(_ edit: PendingEdit) -> URL
    public func changed() -> [PendingEdit]              // copy ≠ baseline or declined
    public func markSaved(_ id: UUID, archiveStamp: PersistentFileStamp?) throws
    public func decline(_ id: UUID) throws               // keep for next time
    public func discard(_ id: UUID) throws               // delete both the copy and the record
    public func cleanupForQuit() throws -> [PendingEdit] // cleans up unchanged, returns the kept ones
    public func loadPending() throws -> [PendingEdit]    // at startup
    public func verifyArchiveUnchanged(_ edit: PendingEdit) throws  // ArchiveError.changedSinceRead
}
```

## Archive Into Itself (D3, D7)

```swift
public enum ArchiveTransferCheck {
    public static func validate(source: ArchivePath?, names: [String], target: ArchivePath) throws(OperationError)
    public static func validatePack(archive: URL, sources: [URL]) throws(OperationError)
}
```

## Deletion (D4)

```swift
public struct DeletePlan: Sendable { public var toTrash: [URL]; public var permanent: [URL] }
public struct TrashReport: Sendable {
    public var trashed: [(original: URL, inTrash: URL)]
    public var failed: (url: URL, reason: String)?
    public var notAttempted: [URL]
}
extension FileOperations {
    public func planDelete(_ urls: [URL]) -> DeletePlan
    public func trash(_ urls: [URL]) async -> TrashReport   // previously async throws -> [URL]
}
```

Seams (internal, for tests): `FileOperations.Options.trashAvailable: @Sendable (URL) -> Bool`,
`.trashItem: @Sendable (URL) throws -> URL`, `.volumeTraits: @Sendable (URL) -> VolumeTraits`.

## Identity (D5) and Rename (D8)

- `FileIdentity` gains `reliable: Bool`; `FileStat` gains `linkCount`.
- `TransferPlanner.plan`/`validateNested`, `TransferRun.resolve`: existing target + deleting the
  source + `!reliable` → `.identityUnknown`.
- `FileOperations.rename`: same identity, different directory entry (`st_nlink > 1`) → `.alreadyExists`.

## UI (AxolotlCommander) — behavior, not API

- F8: `planDelete` → if `permanent` is non-empty, a single critical prompt (default Cancel) with a list
  → `trash(toTrash)` → when `failed == nil`, permanent deletion of `permanent` → report.
- Quit: `cleanupForQuit`; kept edits → an informational message with the path.
- Startup: a non-empty `loadPending` → a single overview (Save Back / Not Now / Discard…).
- "Save As": `SafeFileWriter.write(to:)`.
