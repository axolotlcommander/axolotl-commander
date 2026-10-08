// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Entry points of the file comparison: F3 on exactly two selected files, or
/// Commands → Compare Files… with a file from each panel.
enum CompareFiles {
    /// The two selected files of the panel, when exactly two files (no folders) are selected.
    static func selectedPair(in panel: PanelViewController) -> (URL, URL)? {
        let selected = panel.model.items.filter { panel.model.isSelected($0) }
        guard selected.count == 2, selected.allSatisfy({ !$0.isDirectory && !$0.isParent }) else { return nil }
        return (selected[0].url, selected[1].url)
    }

    /// Asks for the two files: the selected pair, else the file under the cursor here and the
    /// file of the same name in the other panel (or the one under its cursor).
    static func ask(from panel: PanelViewController) async {
        var left: URL?, right: URL?
        if let (a, b) = selectedPair(in: panel) {
            (left, right) = (a, b)
        } else if let item = panel.model.cursorItem, !item.isParent, !item.isDirectory {
            left = item.url
            if let other = panel.router?.otherPanel(than: panel) {
                let match = other.model.items.first { !$0.isDirectory && $0.name == item.name }
                    ?? other.model.cursorItem.flatMap { $0.isParent || $0.isDirectory ? nil : $0 }
                right = match?.url
            }
            if panel.router?.left !== panel, let r = right { (left, right) = (r, item.url) }
        }
        let leftField = NSTextField(string: left?.displayPath ?? "")
        let rightField = NSTextField(string: right?.displayPath ?? "")
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "First file:")), leftField],
            [NSTextField(labelWithString: String(localized: "Second file:")), rightField],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for field in [leftField, rightField] { field.widthAnchor.constraint(equalToConstant: 460).isActive = true }
        grid.frame = NSRect(x: 0, y: 0, width: 560, height: 60)
        let alert = NSAlert()
        alert.messageText = String(localized: "Compare Files")
        alert.informativeText = String(localized: "Paths may be on disk, in an archive or on a server.")
        alert.accessoryView = grid
        alert.addButton(withTitle: String(localized: "Compare"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = leftField.stringValue.isEmpty || !rightField.stringValue.isEmpty ? leftField : rightField
        guard let window = panel.view.window, await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
        do {
            let base = panel.model.location
            let a = try PathInput.resolve(leftField.stringValue, relativeTo: base, absoluteIsLocal: true)
            let b = try PathInput.resolve(rightField.stringValue, relativeTo: base, absoluteIsLocal: true)
            await open(a, b, from: panel)
        } catch {
            panel.router?.operations.report(error)
        }
    }

    /// Compares two files; members of archives and server files are compared from temporary copies.
    static func open(_ left: URL, _ right: URL, from panel: PanelViewController) async {
        do {
            async let a = localCopy(of: left)
            async let b = localCopy(of: right)
            let (leftCopy, rightCopy) = try await (a, b)
            CompareWindowController.show(left: leftCopy, right: rightCopy,
                                         leftTitle: left.displayPath, rightTitle: right.displayPath)
        } catch {
            panel.router?.operations.report(error)
        }
    }

    private static func localCopy(of url: URL) async throws -> URL {
        if let remote = RemoteURL.parse(url) { return try await ArchiveScratch.download(remote) }
        if let archive = ArchivePath.split(url.deletingLastPathComponent()) {
            return try await ArchiveScratch.extract(url.lastPathComponent, from: archive)
        }
        return url
    }
}
