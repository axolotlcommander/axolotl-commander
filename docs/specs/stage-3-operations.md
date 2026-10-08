# Stage 3 — file operations (core specification)

Rules: `../tandemcommander/docs/macos-port/05-pravidla.md` (Identity, Overwrite, Move and link).
Everything in `Sources/CommanderCore/Operations/`, Swift Testing tests in `Tests/CommanderCoreTests/`.

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

## Behavior

- File copy: `copyfile(3)` with `COPYFILE_ALL | COPYFILE_CLONE` (APFS clone), progress callback,
  cancel = `COPYFILE_QUIT` between blocks. Always write to a temporary name `.~icmd-<uuid>` in the target
  folder, then `rename(2)` onto the target (atomic over an existing target). Error/cancel → delete the
  temporary file, target unchanged.
- Folder: recursively, copy symlinks as symlinks (do not follow them).
- Move on the same volume: `rename(2)` (resolve conflicts beforehand). Between volumes: copy, then delete
  the source only if everything was copied, nothing was skipped, and the tree contained no symlink to a
  directory; otherwise the source stays and the report lists it in `keptSources`.
- A conflict is asked about only for an existing target; `overwriteAll`/`skipAll` apply to the rest of the
  operation. A target that is the same file as the source (identity) is `sameFile`, not a conflict.
- Checks before writing: target path length (PathRules), sameFile, intoItself.

## Tests (must fail on a violation)

1. Copying a file onto its hard link → `sameFile`, both links and content unchanged.
2. Copy via `/tmp/x` vs `/private/tmp/x` → `sameFile`.
3. Copy/move of a folder into its own subfolder → `intoItself`, tree unchanged.
4. Overwrite with a cancel midway (large file, cancel in progress) → target has the original content, no `.~icmd-*`.
5. Move of a folder containing a directory symlink between "volumes" (simulate by forcing the copy+delete path) → the files behind the link exist, the source stayed.
6. Conflict skip/overwrite/rename; NameMask `*.bak`; case-only rename `a.txt` → `A.txt`.
7. Two names NFC/NFD on APFS → conflict (same name), not two files.
