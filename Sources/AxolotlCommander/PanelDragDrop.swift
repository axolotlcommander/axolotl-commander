// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Drag & drop for both panel views, with the rules of F5/F6: Option copies, Command moves, otherwise
/// a move within a volume and a copy across volumes (Finder convention). Files on disk travel as file
/// URLs (Finder and other apps take them); archive members and server items travel as our own type
/// that only the other panel understands.
extension PanelViewController {
    static let itemsType = NSPasteboard.PasteboardType("cz.acidek.axolotlcommander.items")

    func dragItem(for item: FileItem) -> NSPasteboardItem {
        let entry = NSPasteboardItem()
        entry.setString(item.url.absoluteString, forType: Self.itemsType)
        if model.archive == nil, model.remote == nil, item.url.isFileURL {
            entry.setString(item.url.absoluteString, forType: .fileURL)
        }
        return entry
    }

    /// Where a drop at `index` goes: a folder row, ".." (the parent) or the panel's folder.
    func dropTarget(row index: Int?) -> URL? {
        // Nothing can be dropped into the Network folder (FR-012).
        guard !model.isNetwork else { return nil }
        if let index, model.items.indices.contains(index) {
            let item = model.items[index]
            if item.isParent { return model.results == nil ? model.location.deletingLastPathComponent() : nil }
            if item.isDirectory && !item.isPackage { return item.url }
        }
        // Find results and branch view have no folder of their own to drop into.
        return isFlatListing ? nil : model.location
    }

    func dragOperation(_ info: any NSDraggingInfo, target: URL) -> NSDragOperation {
        let urls = Self.draggedURLs(info)
        guard !urls.isEmpty else { return [] }
        // Into the folder the items already are in, or into one of the dragged folders: nothing to do.
        let targetPath = target.standardizedFileURL.path
        if urls.contains(where: {
            $0.deletingLastPathComponent().standardizedFileURL.path == targetPath
                || targetPath.hasPrefix($0.standardizedFileURL.path + "/") || $0.standardizedFileURL.path == targetPath
        }) { return [] }
        return operation(info, sources: urls, target: target)
    }

    func performDrop(_ info: any NSDraggingInfo, target: URL) -> Bool {
        let urls = Self.draggedURLs(info)
        guard !urls.isEmpty, let router else { return false }
        let op = operation(info, sources: urls, target: target)
        // The panel the items came from keeps its marks only when the drop failed.
        let other = router.otherPanel(than: self)
        let source = info.draggingSource as? NSView
        let from = source != nil && (source === other.tableView || source === other.briefView) ? other : self
        router.operations.transfer(op == .move ? .move : .copy, sources: urls, from: from, to: target)
        return true
    }

    private func operation(_ info: any NSDraggingInfo, sources: [URL], target: URL) -> NSDragOperation {
        let mask = info.draggingSourceOperationMask
        if mask == .copy { return .copy } // Option held
        // Into an archive only copies: a move would put the originals in the Trash.
        if ArchivePath.split(target) != nil { return .copy }
        if mask == .generic || mask == .move { return .move } // Command held
        // Archives and servers: copy unless Command asks for a move.
        if sources.contains(where: { RemoteURL.isRemote($0) || ArchivePath.split($0.deletingLastPathComponent()) != nil })
            || RemoteURL.isRemote(target) { return .copy }
        let sameVolume = sources.allSatisfy { Volumes.root(of: $0) == Volumes.root(of: target) }
        return sameVolume ? .move : .copy
    }

    /// Our own items first (they may be archive members or server items), else plain file URLs.
    static func draggedURLs(_ info: any NSDraggingInfo) -> [URL] {
        let pasteboard = info.draggingPasteboard
        let own = (pasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: itemsType).flatMap(URL.init(string:)) }
        if !own.isEmpty { return own }
        return pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// Items a drag from row `index` carries: the marked items when it is marked, else that item.
    func draggedItems(from index: Int) -> [FileItem] {
        guard model.items.indices.contains(index), !model.items[index].isParent else { return [] }
        return model.isSelected(model.items[index]) ? model.selectedItems : [model.items[index]]
    }
}
