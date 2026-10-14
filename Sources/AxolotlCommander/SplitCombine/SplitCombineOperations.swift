// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

extension OperationsController {
    static func describe(_ error: SplitCombineError) -> String {
        switch error {
        case .cannotRead(let message): String(localized: "Can’t read: \(message)")
        case .cannotWrite(let message): String(localized: "Can’t write: \(message)")
        case .notRegularFile(let name): String(localized: "“\(name)” is not a file.")
        case .sourceChanged(let name):
            String(localized: "“\(name)” changed while it was split. Nothing was written; try again when the file no longer changes.")
        case .noParts:
            String(localized: "No parts to combine were found. Parts are named like “name.001”, “name.002”, …; or mark the files to combine.")
        case .missingParts(let names):
            String(localized: "These parts are missing: \(names.joined(separator: ", ")). Nothing was written.")
        case .folderInTheWay(let name):
            String(localized: "A folder named “\(name)” is in the target folder; it can’t be replaced by a part.")
        case .alreadyExists(let name):
            String(localized: "“\(name)” appeared in the target folder while the file was split. Nothing was written.")
        }
    }
}

/// Target problems found before anything is written; the message is made on the main actor.
private struct SplitTargetError: LocalizedError {
    let errorDescription: String?

    static var notLocal: Self {
        Self(errorDescription: String(localized: "Split and Combine work only with folders on this Mac’s disks, not on servers or inside archives."))
    }

    static func notAFolder(_ path: String) -> Self {
        Self(errorDescription: String(localized: "“\(path)” is not a folder."))
    }

    @MainActor static func notEnoughSpace(needed: Int64, available: Int64) -> Self {
        Self(errorDescription: String(localized: "There is not enough space in the target: \(Format.bytes(needed)) is needed, \(Format.bytes(available)) is available. Nothing was written."))
    }

    static var invalidName: Self { Self(errorDescription: String(localized: "Enter a name for the combined file.")) }
}

/// Split File… and Combine Files… (spec 029).
extension OperationsController {
    // MARK: Split

    func splitFile(from panel: PanelViewController) {
        guard !isBusy, let window else { return }
        let marked = panel.model.selectedItems
        if marked.count > 1 {
            Task {
                await inform(String(localized: "Split works on one file at a time."),
                             String(localized: "Mark one file, or put the cursor on it with nothing marked."))
            }
            return
        }
        guard let item = marked.first ?? panel.model.cursorItem, !item.isParent, !item.isDirectory, !item.isPackage else { return }
        let source = item.url
        let name = item.name
        guard let size = Self.regularFileSize(source) else {
            report(SplitCombineError.notRegularFile(name))
            return
        }
        Task {
            guard let result = await SplitDialog.run(
                name: name, size: size, folder: defaultTargetFolder(for: panel, source: source).displayPath,
                entries: { [weak self] in self?.destinationEntries(for: panel) ?? [] }, in: window) else { return }
            do {
                let folder = try targetFolder(result.target, panel: panel)
                let count = PartSize.count(fileSize: size, partSize: result.partSize)
                try Self.checkSpace(size + (result.writeChecksum ? 4096 : 0), at: folder)
                let existing = Self.exists(folder)
                    ? try FileSplitter.existingNames(base: name, count: count, checksum: result.writeChecksum, in: folder)
                    : []
                if !existing.isEmpty, await !confirmReplace(existing, in: folder) { return }
                try Self.createIfMissing(folder)
                AppSettings.shared.recentDestinations.add(folder.displayPath)
                let state = OperationState(title: String(localized: "Splitting “\(name)”…"), urls: [source, folder])
                state.progress = OperationProgress(totalBytes: size, doneBytes: 0, totalItems: count, doneItems: 0,
                                                   currentName: name)
                let partSize = result.partSize
                perform(state) {
                    let written = try await FileSplitter.split(
                        source: source, name: name, partSize: partSize, writeChecksum: result.writeChecksum,
                        into: folder, replacing: Set(existing),
                        progress: { done in
                            Task { @MainActor in
                                state.progress.doneBytes = done
                                state.progress.doneItems = Int(done / partSize)
                            }
                        })
                    panel.model.deselectAll()
                    await self.show(written.first?.lastPathComponent, in: folder, from: panel)
                }
            } catch {
                report(error)
            }
        }
    }

    /// One question for all the names that exist: replace them (after the new parts are complete) or stop.
    private func confirmReplace(_ names: [String], in folder: URL) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "These files already exist in “\(folder.lastPathComponent)”:")
        let shown = names.prefix(10).joined(separator: "\n")
        alert.informativeText = (names.count > 10 ? shown + "\n" + String(localized: "and \(names.count - 10) more") : shown)
            + "\n\n" + String(localized: "They are replaced only after all new parts have been written.")
        alert.addButton(withTitle: String(localized: "Replace"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return await Self.present(alert, in: window) == .alertFirstButtonReturn
    }

    // MARK: Combine

    func combineFiles(from panel: PanelViewController) {
        guard !isBusy, let window else { return }
        let marked = panel.model.selectedItems.filter { !$0.isParent }
        let set: PartSet
        let partSizes: [Int64]
        do {
            if marked.count > 1 {
                if let folder = marked.first(where: { $0.isDirectory || $0.isPackage }) {
                    throw SplitCombineError.notRegularFile(folder.name)
                }
                set = try PartSet.marked(marked.map(\.url))
            } else {
                guard let item = marked.first ?? panel.model.cursorItem, !item.isParent, !item.isDirectory else { return }
                set = try PartSet.find(around: item.name, in: item.url.deletingLastPathComponent())
            }
            partSizes = try set.partSizes()
        } catch {
            report(error)
            return
        }
        let totalSize = partSizes.reduce(0, +)
        // Where each part ends in the joined file, for the "N of M items" line.
        let ends = partSizes.reduce(into: [Int64]()) { $0.append(($0.last ?? 0) + $1) }
        let folder = defaultTargetFolder(for: panel, source: set.parts[0])
        Task {
            guard let text = await CombineDialog.run(
                set: set, totalSize: totalSize, text: TransferTarget.text(folder: folder.displayPath, name: set.defaultName),
                entries: { [weak self] in self?.destinationEntries(for: panel) ?? [] }, in: window) else { return }
            do {
                let (folder, name) = try combineTarget(text, defaultName: set.defaultName, panel: panel)
                try Self.checkSpace(totalSize, at: folder)
                try Self.createIfMissing(folder)
                AppSettings.shared.recentDestinations.add(folder.displayPath)
                let state = OperationState(title: String(localized: "Combining into “\(name)”…"), urls: set.parts + [folder])
                state.progress = OperationProgress(totalBytes: totalSize, doneBytes: 0, totalItems: set.parts.count,
                                                   doneItems: 0, currentName: name)
                perform(state) {
                    let output = try await FileSplitter.combine(set, name: name, into: folder, progress: { done in
                        Task { @MainActor in
                            state.progress.doneBytes = done
                            state.progress.doneItems = ends.prefix { $0 <= done }.count
                        }
                    })
                    defer { try? FileManager.default.removeItem(at: output.staging) }
                    // The joined file goes in like an unpacked one: the conflict question of spec 021.
                    let moved = try await self.operations.transfer(
                        TransferRequest(kind: .move, sources: [output.staged], destinationDirectory: folder),
                        progress: { _ in },
                        conflict: { [asker = ConflictAsker(window: self.window)] conflict in await asker.ask(conflict) })
                    // Gone before the panel is refreshed, so the hidden folder never shows up there.
                    try? FileManager.default.removeItem(at: output.staging)
                    panel.model.deselectAll()
                    await self.show(name, in: folder, from: panel)
                    if moved.skipped.contains(output.staged) || moved.copied == 0 {
                        await self.inform(String(localized: "The combined file was not saved."),
                                          String(localized: "“\(name)” already exists and was kept."))
                        return
                    }
                    await self.reportCheck(output, name: name)
                }
            } catch {
                report(error)
            }
        }
    }

    private func reportCheck(_ output: FileSplitter.CombineOutput, name: String) async {
        let result = String(localized: "Size: \(Format.grouped(output.size)) bytes, CRC32: \(SplitChecksum.hex(output.crc32))")
        switch output.check {
        case .passed:
            await inform(String(localized: "“\(name)” was combined and matches the checksum file."), result)
        case .notChecked:
            await inform(String(localized: "“\(name)” was combined."),
                         String(localized: "There was no checksum file, so the result was not checked.") + "\n" + result)
        case .mismatch(let expectedSize, let expectedCRC, _, _):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "“\(name)” does not match the checksum file.")
            let expectedSizeText = expectedSize.map(Format.grouped) ?? "–"
            let expectedCRCText = expectedCRC.map(SplitChecksum.hex) ?? "–"
            let expected = String(localized: "Expected: size \(expectedSizeText) bytes, CRC32 \(expectedCRCText)")
            let actual = String(localized: "Result: size \(Format.grouped(output.size)) bytes, CRC32 \(SplitChecksum.hex(output.crc32))")
            alert.informativeText = expected + "\n" + actual + "\n\n"
                + String(localized: "The file was kept. A part may be damaged or missing; check the parts and combine again.")
            _ = await Self.present(alert, in: window)
        }
    }

    /// "To:" of Combine: an existing folder gets the default name, otherwise the last component is the name.
    private func combineTarget(_ text: String, defaultName: String, panel: PanelViewController) throws -> (URL, String) {
        let whole = try PathInput.resolve(text, relativeTo: panel.model.location, absoluteIsLocal: true)
        guard Self.isLocal(whole) else { throw SplitTargetError.notLocal }
        var isDirectory: ObjCBool = false
        if text.hasSuffix("/") || (FileManager.default.fileExists(atPath: whole.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue) {
            return (whole, defaultName)
        }
        let name = whole.lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != ".." else { throw SplitTargetError.invalidName }
        let folder = whole.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory), !isDirectory.boolValue {
            throw SplitTargetError.notAFolder(folder.displayPath)
        }
        return (folder, name)
    }

    // MARK: Shared

    /// The other panel's folder when it is a local folder, otherwise the folder of the file.
    private func defaultTargetFolder(for panel: PanelViewController, source: URL) -> URL {
        let other = windowController.otherPanel(than: panel).model
        if other.archive == nil, other.results == nil, other.remote == nil, !other.isNetwork { return other.location }
        return panel.isFlatListing ? source.deletingLastPathComponent() : panel.model.location
    }

    private func targetFolder(_ text: String, panel: PanelViewController) throws -> URL {
        let url = try PathInput.resolve(text, relativeTo: panel.model.location, absoluteIsLocal: true)
        guard Self.isLocal(url) else { throw SplitTargetError.notLocal }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), !isDirectory.boolValue {
            throw SplitTargetError.notAFolder(url.displayPath)
        }
        return url
    }

    private static func isLocal(_ url: URL) -> Bool {
        RemoteURL.parse(url) == nil && ArchivePath.split(url) == nil && !NetworkPlaces.isNetwork(url)
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// A missing target folder is created, as the Copy dialog does.
    private static func createIfMissing(_ folder: URL) throws {
        guard !exists(folder) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private static func checkSpace(_ needed: Int64, at folder: URL) throws {
        if let available = FreeSpace.available(at: folder), available < needed {
            throw SplitTargetError.notEnoughSpace(needed: needed, available: available)
        }
    }

    /// Size of the file `url` points to; nil when it is not a regular file.
    private static func regularFileSize(_ url: URL) -> Int64? {
        var st = stat()
        guard stat(url.path(percentEncoded: false), &st) == 0, st.st_mode & S_IFMT == S_IFREG else { return nil }
        return Int64(st.st_size)
    }

    /// Refreshes the panels showing `folder` and puts the cursor on `name`.
    private func show(_ name: String?, in folder: URL, from panel: PanelViewController) async {
        let other = windowController.otherPanel(than: panel)
        for target in [other, panel] where target.model.location.standardizedFileURL == folder.standardizedFileURL {
            await target.model.refresh()
            if let name { target.focus(name: name) }
        }
    }
}
