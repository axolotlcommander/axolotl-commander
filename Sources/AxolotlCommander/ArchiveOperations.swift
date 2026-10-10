// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import SwiftUI

/// Temporary copies of archive members and server files (open, view, compare); removed when
/// the app quits. Copies being edited (F4) live in `ArchiveEdits.store` instead.
enum ArchiveScratch {
    static let root = FileManager.default.temporaryDirectory
        .appending(path: "Axolotl-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// A new empty folder below `root`.
    static func makeFolder() throws -> URL {
        let url = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Extracts the member `name` of the folder `archive` into a fresh folder; returns the copy.
    /// An encrypted member asks for the password on `window` (the key window by default).
    /// `folder` is the (empty) folder to extract into; a fresh one below `root` by default.
    static func extract(_ name: String, from archive: ArchivePath, into folder: URL? = nil,
                        in window: NSWindow? = nil) async throws -> URL {
        let folder = try folder ?? makeFolder()
        let members = [archive.member(name)]
        try await ArchivePasswords.run(archive.archive, members: members, in: window) { passphrases in
            _ = try await ArchiveExtractor.extract(
                archive: archive.archive, members: members, base: archive.inner,
                to: folder, overwrite: true, passphrases: passphrases, progress: { _ in })
        }
        let copy = folder.appending(path: ArchiveExtractor.sanitize(name) ?? name)
        guard FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)) else {
            throw ArchiveError.notFound(archive.member(name))
        }
        return copy
    }
}

/// F4 on an archive member (or a server file): the extracted copy is edited, and a changed
/// copy is offered back under the member's own name when the app comes to the front again.
///
/// The copies live in `ArchiveEditStore` (Application Support), not in the temporary folder:
/// a copy with unsaved changes, or one the user said "Not Now" to, survives quitting and is
/// offered again at the next launch. A copy is never thrown away because saving it failed.
final class ArchiveEdits {
    static let shared = ArchiveEdits()

    let store: ArchiveEditStore
    private var isAsking = false

    init() {
        // A test copy of the app (own bundle id) keeps its edits apart from the real app's.
        let id = Bundle.main.bundleIdentifier ?? "unbundled"
        store = ArchiveEditStore(root: ArchiveEditStore.defaultRoot(folder: id == "cz.acidek.axolotlcommander" ? "Edits" : "Edits-\(id)"))
    }

    func edit(_ name: String, in archive: ArchivePath) async throws {
        let target = PendingEdit.Target.member(archive: archive.archive, path: archive.member(name))
        try await edit(target, archiveStamp: PersistentFileStamp(archive.archive)) { folder in
            try await ArchiveScratch.extract(name, from: archive, into: folder)
        }
    }

    /// F4 on a server file: the downloaded copy is edited and offered back to the server.
    /// The file is stamped before it is downloaded, so a change in between counts as a change.
    func edit(_ remote: RemoteLocation) async throws {
        try await edit(.server(remote.url), archiveStamp: nil, serverStamp: { try await Self.serverStamp(remote) }) { folder in
            try await ArchiveScratch.download(remote, into: folder)
        }
    }

    private static func serverEntry(_ remote: RemoteLocation) async throws -> RemoteEntry? {
        try await RemoteConnections.shared.perform(on: remote.endpoint) { try await $0.info(remote.path) }
    }

    private static func serverStamp(_ remote: RemoteLocation) async throws -> ServerFileStamp? {
        try await serverEntry(remote).flatMap(ServerFileStamp.init)
    }

    private func edit(_ target: PendingEdit.Target, archiveStamp: PersistentFileStamp?,
                      serverStamp: () async throws -> ServerFileStamp? = { nil },
                      makeCopy: (URL) async throws -> URL) async throws {
        // Editing the same item again reuses its copy, so changes not yet saved stay.
        if let existing = store.edit(for: target), FileManager.default.fileExists(atPath: store.copyURL(existing).path) {
            try await Launcher.edit(store.copyURL(existing))
            return
        }
        if let stale = store.edit(for: target) { try? store.discard(stale.id) }
        let stamp = try await serverStamp()
        let edit = try await store.begin(target: target, archiveStamp: archiveStamp, serverStamp: stamp, makeCopy: makeCopy)
        try await Launcher.edit(store.copyURL(edit))
    }

    var hasChanges: Bool { !store.changed().isEmpty }

    /// Asks about every changed copy. A declined change is asked about again only after a
    /// further change; a failed save keeps the copy and asks again next time.
    func offerChanges() async {
        guard !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        for edit in store.changed() {
            let alert = NSAlert()
            alert.messageText = String(localized: "“\(edit.name)” was changed.")
            alert.informativeText = Self.question(edit)
            alert.addButton(withTitle: String(localized: "Update"))
            alert.addButton(withTitle: String(localized: "Not Now"))
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else {
                try? store.decline(edit.id)
                continue
            }
            await saveBack(edit)
        }
    }

    private static func question(_ edit: PendingEdit) -> String {
        switch edit.target {
        case .member(let archive, _):
            String(localized: "Update it in the archive “\(archive.lastPathComponent)”?")
        case .server(let url):
            String(localized: "Upload it to \(RemoteURL.parse(url).map { RemoteURL.displayName($0.endpoint) } ?? url.absoluteString)?")
        }
    }

    /// Writes the copy back; on an error the copy stays and the message says where it is.
    @discardableResult
    private func saveBack(_ edit: PendingEdit) async -> Bool {
        let copy = store.copyURL(edit)
        do {
            switch edit.target {
            case .member(let archive, let path):
                try store.verifyArchiveUnchanged(edit)
                try await ArchiveWriter.update(archive, adding: [ArchiveWriter.Source(file: copy, path: path)],
                                               expecting: edit.archiveStamp, progress: { _ in })
                await ArchiveCatalog.shared.invalidate(archive)
                try store.markSaved(edit.id, archiveStamp: PersistentFileStamp(archive))
            case .server(let url):
                guard let remote = RemoteURL.parse(url) else { throw RemoteError.invalidName(url.absoluteString) }
                // The copy has the file's own name, so it replaces the file (complete upload first).
                let folder = RemoteLocation(endpoint: remote.endpoint, path: RemotePath.parent(remote.path))
                // Someone else may have saved the file meanwhile; their version is replaced only on request.
                if ServerFileStamp.changed(expected: edit.serverStamp, now: try await Self.serverEntry(remote)),
                   await !Self.confirmOverwrite(edit) {
                    try? store.decline(edit.id)
                    return false
                }
                _ = try await RemoteTransfer().upload([copy], to: folder, kind: .copy, progress: { _ in },
                                                      conflict: { _ in .overwrite })
                let uploaded = try? await Self.serverStamp(remote)
                try store.markSaved(edit.id, archiveStamp: nil, serverStamp: uploaded)
            }
            return true
        } catch {
            let failure = NSAlert()
            failure.messageText = {
                if case .server = edit.target { return String(localized: "The file on the server was not updated.") }
                return String(localized: "The archive was not updated.")
            }()
            failure.informativeText = OperationsController.describe(error) + "\n\n"
                + String(localized: "Your edited copy is kept in “\(copy.path(percentEncoded: false))”.")
            NSApp.activate()
            failure.runModal()
            return false
        }
    }

    /// Cancel is the default: the other version must not be lost to a stray Return.
    private static func confirmOverwrite(_ edit: PendingEdit) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "“\(edit.name)” was changed on the server after you opened it.")
        alert.informativeText = String(localized: "Uploading your copy replaces the newer version on the server. If you cancel, your copy is kept and offered again after your next change or the next launch.")
        let overwrite = alert.addButton(withTitle: String(localized: "Overwrite"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        overwrite.keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        NSApp.activate()
        return await OperationsController.present(alert, in: NSApp.mainWindow) == .alertFirstButtonReturn
    }

    /// When the app quits: copies with nothing unsaved go; the user is told where the kept ones are.
    func finishForQuit() {
        guard let kept = try? store.cleanupForQuit(), !kept.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Edited files that were not saved back are kept.")
        alert.informativeText = Self.list(kept) + "\n\n"
            + String(localized: "They are offered again the next time Axolotl Commander starts. The copies are in “\(store.root.path(percentEncoded: false))”.")
        NSApp.activate()
        alert.runModal()
    }

    /// At launch: edits kept from last time are offered together.
    func offerPendingFromLastTime() async {
        guard let pending = try? store.loadPending(), !pending.isEmpty else { return }
        isAsking = true
        defer { isAsking = false }
        let alert = NSAlert()
        alert.messageText = String(localized: "\(pending.count) edited file(s) were not saved back last time.")
        alert.informativeText = Self.list(pending)
        alert.addButton(withTitle: String(localized: "Save Back"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        alert.addButton(withTitle: String(localized: "Discard…"))
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for edit in pending { await saveBack(edit) }
        case .alertThirdButtonReturn:
            let confirm = NSAlert()
            confirm.alertStyle = .critical
            confirm.messageText = String(localized: "Discard the edited copies?")
            confirm.informativeText = String(localized: "The changes in them will be lost.")
            confirm.addButton(withTitle: String(localized: "Cancel"))
            confirm.addButton(withTitle: String(localized: "Discard")).hasDestructiveAction = true
            if confirm.runModal() == .alertSecondButtonReturn {
                for edit in pending { try? store.discard(edit.id) }
            } else {
                for edit in pending { try? store.decline(edit.id) }
            }
        default:
            // Kept for the next launch, not asked about again until changed further.
            for edit in pending { try? store.decline(edit.id) }
        }
    }

    private static func list(_ edits: [PendingEdit]) -> String {
        edits.prefix(10).map { edit in
            switch edit.target {
            case .member(let archive, let path): "• \(path) — \(archive.path(percentEncoded: false))"
            case .server(let url): "• \(url.absoluteString)"
            }
        }.joined(separator: "\n") + (edits.count > 10 ? "\n…" : "")
    }
}

/// Unpack destination (⌃⌥F6) and pack target (⌃⌥F5).
struct ArchiveTargetSheet: View {
    let title: String
    @State var path: String
    @State var format: ArchiveFormat
    let showsFormat: Bool
    let onDone: (_ path: String) -> Void
    let onCancel: () -> Void

    static let formats: [ArchiveFormat] = [.zip, .sevenZip, .tar, .tarGzip, .tarBzip2, .tarXz]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form {
                TextField(showsFormat ? "Archive:" : "To:", text: $path)
                if showsFormat {
                    Picker("Format:", selection: $format) {
                        ForEach(Self.formats, id: \.self) { Text($0.preferredExtension).tag($0) }
                    }
                    .fixedSize()
                    .onChange(of: format) { _, new in path = Self.replacingExtension(of: path, with: new) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("OK") { onDone(path) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    /// "x/a.zip" → "x/a.7z"; a name without an archive extension gets one appended.
    static func replacingExtension(of path: String, with format: ArchiveFormat) -> String {
        let name = (path as NSString).lastPathComponent
        var base = name
        if let old = ArchiveFormat.detect(fileName: name) {
            let lower = name.lowercased()
            let suffix = [old.preferredExtension, "tgz", "tbz", "tbz2", "txz", "jar"].first { lower.hasSuffix("." + $0) }
            if let suffix { base = String(name.dropLast(suffix.count + 1)) }
        }
        return (path as NSString).deletingLastPathComponent.appendingPathComponentKeepingEmpty(base + "." + format.preferredExtension)
    }
}

private extension String {
    func appendingPathComponentKeepingEmpty(_ component: String) -> String {
        isEmpty ? component : (self as NSString).appendingPathComponent(component)
    }
}

extension OperationsController {
    private enum MemberConflict { case overwrite, skip, cancel }

    // MARK: Copy / move with archives

    /// F5/F6 when the sources or the destination are inside an archive.
    func transferArchive(_ kind: TransferKind, sources: [URL], destination: URL, mask: String, panel: PanelViewController) {
        // Branch view lists members of several archive folders; each folder is one group.
        let groups = SourceGroups.byFolder(sources).compactMap { group in
            ArchivePath.split(group.folder).map { (source: $0, names: group.names) }
        }
        if let target = ArchivePath.split(destination) {
            guard groups.count <= 1 else {
                Task {
                    await inform(String(localized: "The operation could not be completed."),
                                 String(localized: "Members of several archive folders cannot be added to an archive at once. Copy them to a folder on disk first."))
                }
                return
            }
            let source = ArchivePath.split(sources[0].deletingLastPathComponent())
            addToArchive(kind, sources: sources, names: sources.map(\.lastPathComponent), from: source, to: target, panel: panel)
        } else if !groups.isEmpty {
            extractOut(kind, groups: groups, to: destination, mask: mask, panel: panel)
        }
    }

    /// Unpacks into a hidden folder inside the destination (same volume), then moves the
    /// items into place with the usual conflict questions. A move removes from the archive
    /// only the members whose copy fully arrived.
    private func extractOut(_ kind: TransferKind, groups: [(source: ArchivePath, names: [String])], to destination: URL,
                            mask: String, panel: PanelViewController) {
        let state = OperationState(title: kind == .copy ? String(localized: "Copying…") : String(localized: "Moving…"))
        perform(state) { [operations] in
            // One staging folder per archive folder, so members of subfolders arrive flat.
            var staged: [(source: ArchivePath, names: [String], members: [String], staging: URL)] = []
            defer { for group in staged { try? FileManager.default.removeItem(at: group.staging) } }
            for group in groups {
                let members = group.names.map { group.source.member($0) }
                let staging = try await self.unpack(group.source.archive, members: members, base: group.source.inner,
                                                    into: destination, state: state)
                staged.append((group.source, group.names, members, staging))
            }
            let items = staged.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0.staging, includingPropertiesForKeys: nil)) ?? [] }
            guard !items.isEmpty else { return }
            let request = TransferRequest(kind: .move, sources: items, destinationDirectory: destination, nameMask: mask)
            let report = try await operations.transfer(
                request,
                progress: { p in Task { @MainActor in state.progress = p } },
                conflict: { conflict in await self.askConflict(conflict) })
            if kind == .move {
                let blocked = (report.skipped + report.keptSources).map { $0.standardizedFileURL.path(percentEncoded: false) }
                var arrived: [URL: Set<String>] = [:]
                for group in staged {
                    for (name, member) in zip(group.names, group.members) {
                        guard let top = ArchiveExtractor.sanitize(name) else { continue }
                        let path = group.staging.appending(path: top).standardizedFileURL.path(percentEncoded: false)
                        if !FileManager.default.fileExists(atPath: path), !blocked.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) {
                            arrived[group.source.archive, default: []].insert(member)
                        }
                    }
                }
                for (archive, members) in arrived where !members.isEmpty {
                    try await ArchiveWriter.update(archive, removing: members, progress: { _ in })
                    await ArchiveCatalog.shared.invalidate(archive)
                }
            }
            panel.model.deselectAll()
        }
    }

    /// Extracts `members` into a new hidden folder inside `destination` and returns it.
    private func unpack(_ archive: URL, members: [String], base: String, into destination: URL,
                        state: OperationState) async throws -> URL {
        let index = try await ArchiveCatalog.shared.index(of: archive)
        state.title = String(localized: "Unpacking “\(archive.lastPathComponent)”…")
        state.progress = OperationProgress(
            totalBytes: index.totalSize(under: members), doneBytes: 0, totalItems: members.count, doneItems: 0,
            currentName: archive.lastPathComponent)
        let staging = destination.appending(path: ".axolotl-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try await ArchivePasswords.run(archive, members: members, in: window) { passphrases in
                _ = try await ArchiveExtractor.extract(
                    archive: archive, members: members, base: base, to: staging, overwrite: true, passphrases: passphrases,
                    progress: { done in Task { @MainActor in state.progress.doneBytes = done } })
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return staging
    }

    /// Adds local files (or members of another archive, extracted first) to an archive.
    /// A move removes the originals only after they are found in the rewritten archive;
    /// local originals go to the Trash.
    private func addToArchive(_ kind: TransferKind, sources: [URL], names: [String], from source: ArchivePath?,
                              to target: ArchivePath, panel: PanelViewController) {
        guard target.format.isWritable else { return report(ArchiveError.readOnly) }
        do {
            // Same archive by identity (also through a symlink or another letter case).
            try ArchiveTransferCheck.validate(source: source, names: names, target: target)
            if source == nil { try ArchiveTransferCheck.validatePack(archive: target.archive, sources: sources) }
        } catch {
            return report(error)
        }
        let state = OperationState(title: kind == .copy ? String(localized: "Copying…") : String(localized: "Moving…"))
        perform(state) { [operations] in
            var files = sources
            var staging: URL?
            defer { if let staging { try? FileManager.default.removeItem(at: staging) } }
            if let source {
                let folder = try ArchiveScratch.makeFolder()
                staging = folder
                let members = names.map { source.member($0) }
                try await ArchivePasswords.run(source.archive, members: members, in: self.window) { passphrases in
                    _ = try await ArchiveExtractor.extract(
                        archive: source.archive, members: members, base: source.inner,
                        to: folder, overwrite: true, passphrases: passphrases, progress: { _ in })
                }
                files = names.map { folder.appending(path: ArchiveExtractor.sanitize($0) ?? $0) }
            }
            let index = try await ArchiveCatalog.shared.index(of: target.archive)
            var pairs = zip(sources, files).filter { FileManager.default.fileExists(atPath: $0.1.path(percentEncoded: false)) }
                .map { (original: $0.0, source: ArchiveWriter.Source(file: $0.1, path: target.member($0.1.lastPathComponent))) }
            let existing = pairs.filter { index.entry(at: $0.source.path) != nil }
            if !existing.isEmpty {
                switch await self.askMemberConflict(existing.map(\.source.path), archive: target.archive) {
                case .overwrite: break
                case .skip: pairs.removeAll { index.entry(at: $0.source.path) != nil }
                case .cancel: return
                }
            }
            guard !pairs.isEmpty else { return }
            state.title = String(localized: "Packing into “\(target.archive.lastPathComponent)”…")
            state.progress = OperationProgress(totalBytes: 0, doneBytes: 0, totalItems: pairs.count, doneItems: 0,
                                               currentName: target.archive.lastPathComponent)
            try await ArchiveWriter.update(target.archive, adding: pairs.map(\.source),
                                           progress: { done in Task { @MainActor in state.progress.doneBytes = done } })
            await ArchiveCatalog.shared.invalidate(target.archive)
            if kind == .move {
                let stored = try await ArchiveCatalog.shared.index(of: target.archive)
                let done = pairs.filter { stored.entry(at: $0.source.path) != nil }.map(\.original)
                if let source {
                    try await ArchiveWriter.update(source.archive, removing: Set(done.map { source.member($0.lastPathComponent) }),
                                                   progress: { _ in })
                    await ArchiveCatalog.shared.invalidate(source.archive)
                } else if !done.isEmpty {
                    // The originals go to the Trash; on a volume without one only after asking.
                    let plan = await operations.planDelete(done)
                    let go = plan.toTrash.count == done.count ? true : await Self.confirmTrash(plan, in: self.window)
                    if go {
                        let outcome = try await Self.runTrash(plan, with: operations, progress: { _ in })
                        if let text = Self.describe(outcome) { await self.inform(String(localized: "Not everything was deleted"), text) }
                    } else {
                        await self.inform(String(localized: "Some sources were kept"),
                                          String(localized: "The items were copied into the archive; the originals were left where they were."))
                    }
                }
            }
            panel.model.deselectAll()
        }
    }

    private func askMemberConflict(_ paths: [String], archive: URL) async -> MemberConflict {
        let alert = NSAlert()
        alert.messageText = paths.count == 1
            ? String(localized: "“\(paths[0])” already exists in “\(archive.lastPathComponent)”.")
            : String(localized: "\(paths.count) items already exist in “\(archive.lastPathComponent)”.")
        alert.addButton(withTitle: String(localized: "Overwrite"))
        alert.addButton(withTitle: String(localized: "Skip"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        guard let window else { return .cancel }
        switch await Self.present(alert, in: window) {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .skip
        default: return .cancel
        }
    }

    // MARK: Delete, folder, rename inside an archive

    func deleteInArchive(_ urls: [URL], archive: ArchivePath) {
        guard archive.format.isWritable else { return report(ArchiveError.readOnly) }
        Task {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = String(localized: "Delete \(Self.describe(urls)) from “\(archive.archive.lastPathComponent)”?")
            alert.informativeText = String(localized: "This can’t be undone.")
            let confirm = alert.addButton(withTitle: String(localized: "Delete"))
            confirm.hasDestructiveAction = true
            alert.addButton(withTitle: String(localized: "Cancel"))
            // Return must not delete by accident: Cancel is the default.
            confirm.keyEquivalent = ""
            alert.buttons[1].keyEquivalent = "\r"
            guard let window, await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
            let state = OperationState(title: String(localized: "Deleting…"))
            perform(state) {
                // Branch view lists members of subfolders too: each URL names its own member.
                try await ArchiveWriter.update(archive.archive, removing: Set(urls.map { ArchivePath.split($0)?.inner ?? archive.member($0.lastPathComponent) }),
                                               progress: { _ in })
                await ArchiveCatalog.shared.invalidate(archive.archive)
            }
        }
    }

    func makeDirectory(named name: String, in archive: ArchivePath, panel: PanelViewController) {
        guard archive.format.isWritable else { return report(ArchiveError.readOnly) }
        guard !name.contains("/"), name != ".", name != ".." else { return report(OperationError.invalidName(name)) }
        let state = OperationState(title: String(localized: "Creating folder…"))
        perform(state) {
            let index = try await ArchiveCatalog.shared.index(of: archive.archive)
            if index.entry(at: archive.member(name)) != nil { throw ArchiveError.alreadyExists(name) }
            let empty = try ArchiveScratch.makeFolder()
            defer { try? FileManager.default.removeItem(at: empty) }
            try await ArchiveWriter.update(archive.archive, adding: [ArchiveWriter.Source(file: empty, path: archive.member(name))],
                                           progress: { _ in })
            await ArchiveCatalog.shared.invalidate(archive.archive)
            await panel.model.refresh()
            panel.focus(name: name)
        }
    }

    func rename(_ name: String, to newName: String, in archive: ArchivePath, panel: PanelViewController, focusing old: URL) {
        guard archive.format.isWritable else { return report(ArchiveError.readOnly) }
        guard !newName.contains("/"), newName != ".", newName != ".." else { return report(OperationError.invalidName(newName)) }
        let state = OperationState(title: String(localized: "Renaming…"))
        perform(state) {
            let index = try await ArchiveCatalog.shared.index(of: archive.archive)
            if index.entry(at: archive.member(newName)) != nil { throw ArchiveError.alreadyExists(newName) }
            try await ArchiveWriter.update(archive.archive, renaming: [archive.member(name): archive.member(newName)],
                                           progress: { _ in })
            await ArchiveCatalog.shared.invalidate(archive.archive)
            await panel.model.refresh()
            panel.focusRenamed(old, to: newName)
        }
    }

    // MARK: Pack, unpack

    /// ⌃⌥F5: packs local items into a new archive (or adds them to an existing one) in the other panel.
    func pack(_ items: [FileItem], from panel: PanelViewController) {
        guard !isBusy, !items.isEmpty else { return }
        let other = windowController.otherPanel(than: panel)
        let folder = other.model.archive == nil && other.model.results == nil && !other.model.isNetwork
            ? other.model.location : panel.model.location
        let base = items.count == 1 ? items[0].baseName : panel.model.location.lastPathComponent
        let initial = folder.appending(path: (base.isEmpty ? "Archive" : base) + ".zip").displayPath
        showTargetSheet(title: String(localized: "Pack \(Self.describe(items.map(\.url))) to:"), path: initial, showsFormat: true) { path in
            let url = try PathRules.resolve(path, relativeTo: panel.model.location)
            guard let format = ArchiveFormat.detect(fileName: url.lastPathComponent) else { throw ArchiveError.unsupportedFormat }
            guard format.isWritable else { throw ArchiveError.readOnly }
            let sources = items.map { ArchiveWriter.Source(file: $0.url, path: $0.name) }
            // Not into one of its own source folders, and not the archive among its sources.
            try ArchiveTransferCheck.validatePack(archive: url, sources: items.map(\.url))
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                // An existing archive gets the items added, like F5 into it.
                self.addToArchive(.copy, sources: items.map(\.url), names: items.map(\.name), from: nil,
                                  to: ArchivePath(archive: url, format: format), panel: panel)
                return
            }
            let state = OperationState(title: String(localized: "Packing into “\(url.lastPathComponent)”…"))
            self.perform(state) {
                try await ArchiveWriter.create(url, format: format, adding: sources,
                                               progress: { done in Task { @MainActor in state.progress.doneBytes = done } })
                panel.model.deselectAll()
                await other.model.refresh()
                if other.model.location.standardizedFileURL == url.deletingLastPathComponent().standardizedFileURL {
                    other.focus(name: url.lastPathComponent)
                }
            }
        }
    }

    /// ⌃⌥F6: unpacks the archives into a folder (the other panel's by default), asking before replacing files.
    func unpack(_ archives: [URL], from panel: PanelViewController) {
        guard !isBusy, !archives.isEmpty else { return }
        let other = windowController.otherPanel(than: panel)
        let folder = other.model.archive == nil && other.model.results == nil && !other.model.isNetwork
            ? other.model.location : panel.model.location
        showTargetSheet(title: String(localized: "Unpack \(Self.describe(archives)) to:"), path: folder.displayPath, showsFormat: false) { path in
            let destination = try PathRules.resolve(path, relativeTo: panel.model.location)
            guard ArchivePath.split(destination) == nil else { throw ArchiveError.unsupportedFormat }
            let state = OperationState(title: String(localized: "Unpacking…"))
            self.perform(state) { [operations = self.operations] in
                for archive in archives {
                    let staging = try await self.unpack(archive, members: [""], base: "", into: destination, state: state)
                    defer { try? FileManager.default.removeItem(at: staging) }
                    let staged = (try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
                    guard !staged.isEmpty else { continue }
                    let request = TransferRequest(kind: .move, sources: staged, destinationDirectory: destination, nameMask: "*.*")
                    _ = try await operations.transfer(
                        request,
                        progress: { p in Task { @MainActor in state.progress = p } },
                        conflict: { conflict in await self.askConflict(conflict) })
                }
                panel.model.deselectAll()
            }
        }
    }

    private func showTargetSheet(title: String, path: String, showsFormat: Bool, onDone: @escaping (String) throws -> Void) {
        var sheetWindow: NSWindow?
        let close = { [weak self] in
            if let sheetWindow { self?.window?.endSheet(sheetWindow) }
        }
        let sheet = ArchiveTargetSheet(
            title: title, path: path, format: ArchiveFormat.detect(fileName: path) ?? .zip, showsFormat: showsFormat,
            onDone: { [weak self] path in
                close()
                do { try onDone(path) } catch { self?.report(error) }
            },
            onCancel: close)
        let host = NSWindow(contentViewController: NSHostingController(rootView: sheet))
        sheetWindow = host
        window?.beginSheet(host, completionHandler: nil)
    }
}
