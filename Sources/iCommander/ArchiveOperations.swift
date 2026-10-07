import AppKit
import CommanderCore
import SwiftUI

/// Temporary copies of archive members (open, view, edit); removed when the app quits.
enum ArchiveScratch {
    static let root = FileManager.default.temporaryDirectory
        .appending(path: "iCommander-\(UUID().uuidString)", directoryHint: .isDirectory)

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
    static func extract(_ name: String, from archive: ArchivePath) async throws -> URL {
        let folder = try makeFolder()
        _ = try await ArchiveExtractor.extract(
            archive: archive.archive, members: [archive.member(name)], base: archive.inner,
            to: folder, overwrite: true, progress: { _ in })
        let copy = folder.appending(path: ArchiveExtractor.sanitize(name) ?? name)
        guard FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)) else {
            throw ArchiveError.notFound(archive.member(name))
        }
        return copy
    }
}

/// F4 on an archive member: the extracted copy is edited, and a changed copy is offered
/// back to the archive under the member's own name when the app comes to the front again.
final class ArchiveEdits {
    static let shared = ArchiveEdits()

    private final class Session {
        let archive: URL
        let member: String
        let copy: URL
        /// State of the copy when it was extracted or last saved (or declined).
        var stamp: Stamp?

        init(archive: URL, member: String, copy: URL) {
            self.archive = archive
            self.member = member
            self.copy = copy
            stamp = Stamp(copy)
        }

        var isChanged: Bool { Stamp(copy) != stamp }
    }

    private struct Stamp: Equatable {
        let date: Date?
        let size: Int64?

        init?(_ url: URL) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)) else { return nil }
            date = attributes[.modificationDate] as? Date
            size = (attributes[.size] as? NSNumber)?.int64Value
        }
    }

    private var sessions: [Session] = []
    private var isAsking = false

    func edit(_ name: String, in archive: ArchivePath) async throws {
        let member = archive.member(name)
        // Editing the member again reuses its copy, so changes not yet saved stay.
        if let session = sessions.first(where: { $0.archive == archive.archive && $0.member == member }) {
            try await Launcher.edit(session.copy)
            return
        }
        let copy = try await ArchiveScratch.extract(name, from: archive)
        sessions.append(Session(archive: archive.archive, member: member, copy: copy))
        try await Launcher.edit(copy)
    }

    var hasChanges: Bool { sessions.contains { $0.isChanged } }

    /// Asks about every changed copy. A declined change is asked about again only after a
    /// further change; a failed save keeps the member as it was and asks again next time.
    func offerChanges() async {
        guard !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        for session in sessions where session.isChanged {
            let alert = NSAlert()
            alert.messageText = String(localized: "“\(session.copy.lastPathComponent)” was changed.")
            alert.informativeText = String(localized: "Update it in the archive “\(session.archive.lastPathComponent)”?")
            alert.addButton(withTitle: String(localized: "Update"))
            alert.addButton(withTitle: String(localized: "Not Now"))
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else {
                session.stamp = Stamp(session.copy)
                continue
            }
            let saved = Stamp(session.copy)
            do {
                try await ArchiveWriter.update(
                    session.archive, adding: [ArchiveWriter.Source(file: session.copy, path: session.member)], progress: { _ in })
                await ArchiveCatalog.shared.invalidate(session.archive)
                session.stamp = saved
            } catch {
                let failure = NSAlert()
                failure.messageText = String(localized: "The archive was not updated.")
                failure.informativeText = OperationsController.describe(error)
                failure.runModal()
            }
        }
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
        let source = ArchivePath.split(sources[0].deletingLastPathComponent())
        let names = sources.map(\.lastPathComponent)
        if let target = ArchivePath.split(destination) {
            addToArchive(kind, sources: sources, names: names, from: source, to: target, panel: panel)
        } else if let source {
            extractOut(kind, names: names, from: source, to: destination, mask: mask, panel: panel)
        }
    }

    /// Unpacks into a hidden folder inside the destination (same volume), then moves the
    /// items into place with the usual conflict questions. A move removes from the archive
    /// only the members whose copy fully arrived.
    private func extractOut(_ kind: TransferKind, names: [String], from source: ArchivePath, to destination: URL,
                            mask: String, panel: PanelViewController) {
        let state = OperationState(title: kind == .copy ? String(localized: "Copying…") : String(localized: "Moving…"))
        let members = names.map { source.member($0) }
        perform(state) { [operations] in
            let staging = try await self.unpack(source.archive, members: members, base: source.inner, into: destination, state: state)
            defer { try? FileManager.default.removeItem(at: staging) }
            let staged = (try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
            guard !staged.isEmpty else { return }
            let request = TransferRequest(kind: .move, sources: staged, destinationDirectory: destination, nameMask: mask)
            let report = try await operations.transfer(
                request,
                progress: { p in Task { @MainActor in state.progress = p } },
                conflict: { conflict in await self.askConflict(conflict) })
            if kind == .move {
                let blocked = (report.skipped + report.keptSources).map { $0.standardizedFileURL.path(percentEncoded: false) }
                let arrived = zip(names, members).filter { name, _ in
                    guard let top = ArchiveExtractor.sanitize(name) else { return false }
                    let path = staging.appending(path: top).standardizedFileURL.path(percentEncoded: false)
                    return !FileManager.default.fileExists(atPath: path)
                        && !blocked.contains { $0 == path || $0.hasPrefix(path + "/") }
                }.map(\.1)
                if !arrived.isEmpty {
                    try await ArchiveWriter.update(source.archive, removing: Set(arrived), progress: { _ in })
                    await ArchiveCatalog.shared.invalidate(source.archive)
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
        let staging = destination.appending(path: ".icommander-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            _ = try await ArchiveExtractor.extract(
                archive: archive, members: members, base: base, to: staging, overwrite: true,
                progress: { done in Task { @MainActor in state.progress.doneBytes = done } })
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
        if let source, source.archive.standardizedFileURL == target.archive.standardizedFileURL {
            let into = names.map { source.member($0) }.first { target.inner == $0 || target.inner.hasPrefix($0 + "/") }
            if let into { return report(OperationError.intoItself(URL(filePath: into))) }
        }
        let state = OperationState(title: kind == .copy ? String(localized: "Copying…") : String(localized: "Moving…"))
        perform(state) { [operations] in
            var files = sources
            var staging: URL?
            defer { if let staging { try? FileManager.default.removeItem(at: staging) } }
            if let source {
                let folder = try ArchiveScratch.makeFolder()
                staging = folder
                _ = try await ArchiveExtractor.extract(
                    archive: source.archive, members: names.map { source.member($0) }, base: source.inner,
                    to: folder, overwrite: true, progress: { _ in })
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
                    _ = try await operations.trash(done)
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
        switch await alert.beginSheetModal(for: window) {
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
                try await ArchiveWriter.update(archive.archive, removing: Set(urls.map { archive.member($0.lastPathComponent) }),
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

    func rename(_ name: String, to newName: String, in archive: ArchivePath, panel: PanelViewController) {
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
            panel.focus(name: newName)
        }
    }

    // MARK: Pack, unpack

    /// ⌃⌥F5: packs local items into a new archive (or adds them to an existing one) in the other panel.
    func pack(_ items: [FileItem], from panel: PanelViewController) {
        guard !isBusy, !items.isEmpty else { return }
        let other = windowController.otherPanel(than: panel)
        let folder = other.model.archive == nil && other.model.results == nil ? other.model.location : panel.model.location
        let base = items.count == 1 ? items[0].baseName : panel.model.location.lastPathComponent
        let initial = folder.appending(path: (base.isEmpty ? "Archive" : base) + ".zip").displayPath
        showTargetSheet(title: String(localized: "Pack \(Self.describe(items.map(\.url))) to:"), path: initial, showsFormat: true) { path in
            let url = try PathRules.resolve(path, relativeTo: panel.model.location)
            guard let format = ArchiveFormat.detect(fileName: url.lastPathComponent) else { throw ArchiveError.unsupportedFormat }
            guard format.isWritable else { throw ArchiveError.readOnly }
            let sources = items.map { ArchiveWriter.Source(file: $0.url, path: $0.name) }
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
        let folder = other.model.archive == nil && other.model.results == nil ? other.model.location : panel.model.location
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
