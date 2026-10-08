// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin
import Synchronization

/// Size and modification time of a file; tells whether an edited copy changed.
public struct FileStamp: Codable, Sendable, Equatable {
    public var size: Int64
    /// Nanoseconds since 1970.
    public var modified: Int64

    public init(size: Int64, modified: Int64) {
        self.size = size
        self.modified = modified
    }

    /// nil when the file does not exist.
    public init?(_ url: URL) {
        var st = Darwin.stat()
        guard stat(url.path, &st) == 0 else { return nil }
        size = Int64(st.st_size)
        modified = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
    }
}

/// Size and modification time of a server file as the server reports them; tells whether
/// someone changed the file after it was downloaded for editing.
public struct ServerFileStamp: Codable, Sendable, Equatable {
    public var size: Int64?
    /// Milliseconds since 1970 (servers report whole seconds at best).
    public var modified: Int64?

    public init(size: Int64?, modified: Int64?) {
        self.size = size
        self.modified = modified
    }

    /// nil when the server reports neither size nor time: then nothing can be compared.
    public init?(_ entry: RemoteEntry) {
        let modified = entry.modificationDate.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
        guard entry.size != nil || modified != nil else { return nil }
        self.init(size: entry.size, modified: modified)
    }

    /// True when the file `now` (nil = gone) is not the one stamped by `expected`. Without a
    /// stamp (an older edit, or a server that reports nothing) the file counts as unchanged.
    public static func changed(expected: ServerFileStamp?, now: RemoteEntry?) -> Bool {
        guard let expected else { return false }
        guard let now, now.kind == .file else { return true }
        return ServerFileStamp(now) != expected
    }
}

/// A copy of an archive member (or a server file) opened for editing, waiting to go back.
public struct PendingEdit: Codable, Sendable, Equatable, Identifiable {
    public enum Target: Codable, Sendable, Equatable {
        /// `path` is the member's path inside the archive file `archive`.
        case member(archive: URL, path: String)
        /// The file's address on a server (`RemoteLocation.url`, never with a password).
        case server(URL)
    }

    public let id: UUID
    public let target: Target
    /// Path of the copy relative to the edit's own folder.
    public let copyRelPath: String
    /// The copy as extracted or last saved back; a copy that differs has unsaved changes.
    public var baseline: FileStamp?
    /// The archive as it was when the member was taken out (or last saved into); nil for servers.
    public var archiveStamp: PersistentFileStamp?
    /// The server file as it was when downloaded (or last uploaded); nil for archives.
    public var serverStamp: ServerFileStamp? = nil
    /// The user chose "Not Now": keep the copy and offer it again on the next launch.
    public var declined: Bool

    /// Name shown to the user (the copy has the member's own name).
    public var name: String { (copyRelPath as NSString).lastPathComponent }
}

/// Keeps copies of archive members (and server files) opened with F4 in a folder that
/// survives quitting and restarts, together with a manifest of where each one goes back.
///
/// A copy is removed only when it has nothing unsaved: unchanged since it was extracted or
/// saved back, and not declined. Everything else stays and is offered again at the next
/// launch. Writing back is refused when the archive changed since the member was taken out.
public final class ArchiveEditStore: Sendable {
    public let root: URL
    private let edits: Mutex<[PendingEdit]>

    /// `~/Library/Application Support/Axolotl Commander/Edits`.
    public static var defaultRoot: URL {
        defaultRoot(folder: "Edits")
    }

    /// Same parent as `defaultRoot`, with another last component (e.g. for a test copy of the app).
    public static func defaultRoot(folder: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return support.appending(path: "Axolotl Commander", directoryHint: .isDirectory)
            .appending(path: folder, directoryHint: .isDirectory)
    }

    /// Reads the manifest in `root` (missing or unreadable = no edits).
    public init(root: URL) {
        self.root = root
        let manifest = root.appending(path: "manifest.json")
        let stored = (try? Data(contentsOf: manifest)).flatMap { try? JSONDecoder().decode([PendingEdit].self, from: $0) }
        edits = Mutex(stored ?? [])
    }

    // MARK: Queries

    public var all: [PendingEdit] { edits.withLock { $0 } }

    public func edit(for target: PendingEdit.Target) -> PendingEdit? {
        edits.withLock { $0.first { $0.target == target } }
    }

    public func copyURL(_ edit: PendingEdit) -> URL {
        folder(edit.id).appending(path: edit.copyRelPath)
    }

    /// The copy differs from what was extracted or last saved back.
    public func isChanged(_ edit: PendingEdit) -> Bool {
        FileStamp(copyURL(edit)) != edit.baseline
    }

    /// Copies with changes not yet saved back (declined ones only after a further change).
    public func changed() -> [PendingEdit] {
        all.filter { isChanged($0) }
    }

    /// Copies that must not be removed: changed or declined.
    public func unsaved() -> [PendingEdit] {
        all.filter { $0.declined || isChanged($0) }
    }

    // MARK: Changes

    /// Makes a new edit: `makeCopy` gets an empty folder of its own and returns the copy it
    /// created inside. On an error nothing is recorded and the folder is removed.
    nonisolated(nonsending) public func begin(
        target: PendingEdit.Target,
        archiveStamp: PersistentFileStamp?,
        serverStamp: ServerFileStamp? = nil,
        makeCopy: nonisolated(nonsending) (_ folder: URL) async throws -> URL
    ) async throws -> PendingEdit {
        let id = UUID()
        let folder = folder(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let copy = try await makeCopy(folder).standardizedFileURL
            let base = folder.standardizedFileURL.path + "/"
            guard copy.path.hasPrefix(base), FileManager.default.fileExists(atPath: copy.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: copy])
            }
            let edit = PendingEdit(id: id, target: target, copyRelPath: String(copy.path.dropFirst(base.count)),
                                   baseline: FileStamp(copy), archiveStamp: archiveStamp, serverStamp: serverStamp,
                                   declined: false)
            try change { $0.append(edit) }
            return edit
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// The copy went back: its current state becomes the baseline, and the archive's (or the
    /// server file's) new stamp is what later saves expect.
    public func markSaved(_ id: UUID, archiveStamp: PersistentFileStamp?, serverStamp: ServerFileStamp? = nil) throws {
        try change { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].baseline = FileStamp(copyURL(list[i]))
            list[i].archiveStamp = archiveStamp
            list[i].serverStamp = serverStamp
            list[i].declined = false
        }
    }

    /// "Not Now": not asked again until a further change, kept when the app quits.
    public func decline(_ id: UUID) throws {
        try change { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].baseline = FileStamp(copyURL(list[i]))
            list[i].declined = true
        }
    }

    /// Removes the copy and its record.
    public func discard(_ id: UUID) throws {
        try change { $0.removeAll { $0.id == id } }
        try? FileManager.default.removeItem(at: folder(id))
    }

    /// Removes copies with nothing unsaved; returns the ones kept.
    public func cleanupForQuit() throws -> [PendingEdit] {
        let all = all
        let keep = all.filter { FileStamp(copyURL($0)) != nil && ($0.declined || isChanged($0)) }
        for edit in all where !keep.contains(edit) { try discard(edit.id) }
        return keep
    }

    /// At launch: drops records whose copy is gone and copies with nothing unsaved (left
    /// by a crash); returns the edits to offer back.
    public func loadPending() throws -> [PendingEdit] {
        try cleanupForQuit()
    }

    /// Throws `ArchiveError.changedSinceRead` when the edit's archive is no longer the one
    /// the member was taken from (changed, replaced, moved away or removed).
    public func verifyArchiveUnchanged(_ edit: PendingEdit) throws {
        guard case .member(let archive, _) = edit.target, let expected = edit.archiveStamp else { return }
        guard PersistentFileStamp(archive) == expected else {
            throw ArchiveError.changedSinceRead(archive.path)
        }
    }

    // MARK: Storage

    private func folder(_ id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// Applies `body` and writes the manifest; on a write error the list stays as it was.
    private func change(_ body: (inout [PendingEdit]) -> Void) throws {
        try edits.withLock { list in
            var updated = list
            body(&updated)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(updated)
            try SafeFileWriter.write(to: root.appending(path: "manifest.json")) { try data.write(to: $0) }
            list = updated
        }
    }
}
