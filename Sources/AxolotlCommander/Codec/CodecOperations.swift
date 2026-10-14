// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Encode File… and Decode File… (spec 030).
extension OperationsController {
    /// The files to work on: the marked items or the cursor item, without folders (counted).
    private func codecSources(_ panel: PanelViewController) -> (files: [FileItem], folders: Int) {
        let items = panel.targets().filter { !$0.isParent }
        let files = items.filter { !$0.isDirectory && !$0.isPackage }
        return (files, items.count - files.count)
    }

    private static func foldersLeftOut(_ count: Int) -> String {
        String(localized: "Folders are left out (\(count)).")
    }

    /// Names for a result message: at most ten, then "and N more".
    private static func list(_ names: [String]) -> String {
        var lines = names.prefix(10).map { "• " + $0 }
        if names.count > 10 { lines.append(String(localized: "and \(names.count - 10) more")) }
        return lines.joined(separator: "\n")
    }

    /// Moves the staged files into `folder` with the conflict question of spec 021; returns the names that
    /// were not saved because the user kept the existing files.
    private func moveIn(_ staged: [URL], to folder: URL) async throws -> [String] {
        guard !staged.isEmpty else { return [] }
        let moved = try await operations.transfer(
            TransferRequest(kind: .move, sources: staged, destinationDirectory: folder),
            progress: { _ in },
            conflict: { [asker = ConflictAsker(window: window)] conflict in await asker.ask(conflict) })
        return moved.skipped.map(\.lastPathComponent)
    }

    // MARK: Encode

    func encodeFiles(from panel: PanelViewController) {
        guard !isBusy, let window else { return }
        let (files, folders) = codecSources(panel)
        guard !files.isEmpty else { return }
        var sizes: [Int64] = []
        for file in files {
            guard let size = Self.regularFileSize(file.url) else {
                report(SplitCombineError.notRegularFile(file.name))
                return
            }
            sizes.append(size)
        }
        let heading = files.count == 1
            ? String(localized: "Encode “\(files[0].name)” as text")
            : String(localized: "Encode \(files.count) files as text")
        var details = [files.count == 1
            ? String(localized: "Size: \(Format.bytes(sizes[0]))")
            : String(localized: "Each file gets its own text file; total size \(Format.bytes(sizes.reduce(0, +))).")]
        if folders > 0 { details.append(Self.foldersLeftOut(folders)) }
        let folder = defaultTargetFolder(for: panel, source: files[0].url)
        Task {
            guard let result = await CodecDialog.run(
                mode: .encode, heading: heading, details: details, folder: folder.displayPath,
                entries: { [weak self] in self?.destinationEntries(for: panel) ?? [] }, in: window) else { return }
            do {
                let target = try targetFolder(result.target, panel: panel)
                let needed = zip(files, sizes).reduce(Int64(0)) {
                    $0 + FileCodec.encodedSize($1.1, name: $1.0.name, format: result.format)
                }
                try Self.checkSpace(needed, at: target)
                try Self.createIfMissing(target)
                AppSettings.shared.recentDestinations.add(target.displayPath)
                let staging = try FileCodec.makeStaging(in: target)
                let total = sizes.reduce(0, +)
                let state = OperationState(title: String(localized: "Encoding…"), urls: files.map(\.url) + [target])
                state.progress = OperationProgress(totalBytes: total, doneBytes: 0, totalItems: files.count,
                                                   doneItems: 0, currentName: files[0].name)
                let format = result.format
                perform(state) {
                    defer { try? FileManager.default.removeItem(at: staging) }
                    var staged: [URL] = []
                    var base: Int64 = 0
                    for (index, (file, size)) in zip(files, sizes).enumerated() {
                        state.progress.currentName = file.name
                        state.progress.doneItems = index
                        let start = base
                        staged.append(try await FileCodec.encode(source: file.url, name: file.name, format: format, into: staging,
                                                                 progress: { done in
                                                                     Task { @MainActor in state.progress.doneBytes = start + done }
                                                                 }))
                        base += size
                    }
                    state.progress.doneItems = files.count
                    let kept = try await self.moveIn(staged, to: target)
                    try? FileManager.default.removeItem(at: staging)
                    panel.model.deselectAll()
                    await self.show(staged.first?.lastPathComponent, in: target, from: panel)
                    var notes: [String] = []
                    if !kept.isEmpty {
                        notes.append(String(localized: "Not saved, the existing files were kept:") + "\n" + Self.list(kept))
                    }
                    if folders > 0 { notes.append(Self.foldersLeftOut(folders)) }
                    if !notes.isEmpty {
                        await self.inform(String(localized: "Encoded \(staged.count - kept.count) of \(staged.count) files."),
                                          notes.joined(separator: "\n\n"))
                    }
                }
            } catch {
                report(error)
            }
        }
    }

    // MARK: Decode

    func decodeFiles(from panel: PanelViewController) {
        guard !isBusy, let window else { return }
        var (files, folders) = codecSources(panel)
        guard !files.isEmpty else { return }
        files.sort { NameRules(caseSensitive: false).order($0.name, $1.name) == .orderedAscending }
        var sizes: [Int64] = []
        for file in files {
            guard let size = Self.regularFileSize(file.url) else {
                report(SplitCombineError.notRegularFile(file.name))
                return
            }
            sizes.append(size)
        }
        let heading = files.count == 1
            ? String(localized: "Decode “\(files[0].name)”")
            : String(localized: "Decode \(files.count) files")
        var details: [String] = []
        if files.count > 1 {
            details.append(String(localized: "The files are read in name order as one text, so a file encoded in several pieces is joined."))
        }
        if folders > 0 { details.append(Self.foldersLeftOut(folders)) }
        let folder = defaultTargetFolder(for: panel, source: files[0].url)
        Task {
            guard let result = await CodecDialog.run(
                mode: .decode, heading: heading, details: details, folder: folder.displayPath,
                entries: { [weak self] in self?.destinationEntries(for: panel) ?? [] }, in: window) else { return }
            do {
                let target = try targetFolder(result.target, panel: panel)
                let total = sizes.reduce(0, +)
                // Decoded data is never larger than the encoded text.
                try Self.checkSpace(total, at: target)
                try Self.createIfMissing(target)
                AppSettings.shared.recentDestinations.add(target.displayPath)
                let staging = try FileCodec.makeStaging(in: target)
                let state = OperationState(title: String(localized: "Decoding…"), urls: files.map(\.url) + [target])
                state.progress = OperationProgress(totalBytes: total, doneBytes: 0, totalItems: files.count,
                                                   doneItems: 0, currentName: files[0].name)
                let ends = sizes.reduce(into: [Int64]()) { $0.append(($0.last ?? 0) + $1) }
                let names = files.map(\.name)
                let urls = files.map(\.url)
                perform(state) {
                    defer { try? FileManager.default.removeItem(at: staging) }
                    let decoded = try await FileCodec.decode(urls, into: staging, progress: { done in
                        Task { @MainActor in
                            state.progress.doneBytes = done
                            let index = ends.prefix { $0 <= done }.count
                            state.progress.doneItems = index
                            state.progress.currentName = names[min(index, names.count - 1)]
                        }
                    })
                    guard !decoded.isEmpty else {
                        await self.inform(String(localized: "No encoded data was found."),
                                          String(localized: "Nothing was written. Decode File reads MIME messages (.eml), UUE, XXE, BinHex and Base64 text."))
                        return
                    }
                    let kept = try await self.moveIn(decoded.map(\.url), to: target)
                    try? FileManager.default.removeItem(at: staging)
                    panel.model.deselectAll()
                    let written = decoded.filter { !kept.contains($0.name) }
                    await self.show(written.first?.name, in: target, from: panel)
                    await self.reportDecoded(decoded, kept: kept, folders: folders)
                }
            } catch {
                report(error)
            }
        }
    }

    private func reportDecoded(_ decoded: [DecodedFile], kept: [String], folders: Int) async {
        let written = decoded.filter { !kept.contains($0.name) }
        let title = written.count == 1
            ? String(localized: "“\(written[0].name)” was decoded.")
            : String(localized: "Decoded files: \(written.count)")
        var notes: [String] = []
        if written.count > 1 { notes.append(Self.list(written.map(\.name))) }
        let incomplete = written.filter { $0.state == .incomplete }.map(\.name)
        if !incomplete.isEmpty {
            notes.append(String(localized: "Incomplete — the data ended before its end marker:") + "\n" + Self.list(incomplete))
        }
        let damaged = written.filter { $0.state == .damaged }.map(\.name)
        if !damaged.isEmpty {
            notes.append(String(localized: "Damaged — the checksum does not match:") + "\n" + Self.list(damaged))
        }
        if !kept.isEmpty {
            notes.append(String(localized: "Not saved, the existing files were kept:") + "\n" + Self.list(kept))
        }
        if folders > 0 { notes.append(Self.foldersLeftOut(folders)) }
        await inform(written.isEmpty ? String(localized: "No decoded file was saved.") : title, notes.joined(separator: "\n\n"))
    }
}
