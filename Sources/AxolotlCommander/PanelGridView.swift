// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The keyboard, mouse, drag source and drop target handling shared by the grid views of a panel (Brief and
/// Thumbnails). A subclass tells where an item's name zone is and which items a rectangle covers.
class PanelGridView: NSCollectionView {
    var onKey: ((NSEvent) -> Bool)?
    var onFocus: (() -> Void)?
    var onClick: ((Int, Int) -> Void)?   // item index, click count
    var onMenu: ((Int?) -> NSMenu?)?
    /// Drag source: pasteboard items for a drag that starts on the item at the index.
    var onDrag: ((Int) -> [NSPasteboardItem])?
    /// Drop target: the operation for a drop over the item at the index (nil = empty space)…
    var onValidateDrop: ((any NSDraggingInfo, Int?) -> NSDragOperation)?
    /// …and performing it.
    var onDrop: ((any NSDraggingInfo, Int?) -> Bool)?
    /// The panel that runs mouse marking (spec 024).
    weak var panel: PanelViewController?

    private var dragStart: (point: NSPoint, index: Int)?
    /// The item of a plain press on a name, until the release or a drag.
    private var pendingRelease: Int?

    override var acceptsFirstResponder: Bool { true }

    var itemCount: Int { numberOfSections > 0 ? numberOfItems(inSection: 0) : 0 }

    /// Whether `point` is on the part of the item that counts as the item (where drag & drop starts).
    func isOnName(_ point: NSPoint, index: Int) -> Bool { false }

    /// The cells of the grid laid out with equal cells, or nil before there is anything to lay out.
    func geometry() -> GridGeometry? { nil }

    /// The items a rectangle touches, from the grid's geometry.
    func items(in rect: NSRect) -> IndexSet { geometry()?.indices(in: rect) ?? [] }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // ⌃ + left click marks (spec 024); AppKit would show the context menu for it.
        if event.type == .leftMouseDown { return nil }
        return onMenu?(indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let index = indexPathForItem(at: point)?.item
        dragStart = nil
        pendingRelease = nil
        guard let panel else { return }
        let hit = MouseHit(index: index, onName: index.map { isOnName(point, index: $0) } ?? false)
        let result = panel.mousePressed(event, hit: hit, in: self) { [unowned self] in items(in: $0) }
        guard result == .dragOrClick, let index else { return }
        dragStart = (point, index)
        pendingRelease = index
        if event.clickCount == 2 { onClick?(index, 2) }
    }

    override func rightMouseDown(with event: NSEvent) {
        let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item
        let handled = panel?.rightMousePressed(event, index: index, in: self) { [unowned self] in
            indexPathForItem(at: $0)?.item
        } ?? false
        if !handled { super.rightMouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.point.x, point.y - start.point.y) > 4 else { return }
        dragStart = nil
        pendingRelease = nil
        let entries = onDrag?(start.index) ?? []
        guard !entries.isEmpty else { return }
        let frame = frameForItem(at: start.index)
        let image = item(at: start.index).flatMap { item -> NSImage? in
            guard let rep = item.view.bitmapImageRepForCachingDisplay(in: item.view.bounds) else { return nil }
            item.view.cacheDisplay(in: item.view.bounds, to: rep)
            let image = NSImage(size: item.view.bounds.size)
            image.addRepresentation(rep)
            return image
        }
        let items = entries.enumerated().map { offset, entry in
            let dragging = NSDraggingItem(pasteboardWriter: entry)
            dragging.setDraggingFrame(frame.offsetBy(dx: CGFloat(offset) * 3, dy: CGFloat(offset) * 3), contents: image)
            return dragging
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        if let index = pendingRelease { panel?.mouseReleasedAfterPlainPress(at: index) }
        pendingRelease = nil
    }

    // MARK: Dropping

    private func dropIndex(_ info: any NSDraggingInfo) -> Int? {
        indexPathForItem(at: convert(info.draggingLocation, from: nil))?.item
    }

    override func draggingEntered(_ info: any NSDraggingInfo) -> NSDragOperation {
        onValidateDrop?(info, dropIndex(info)) ?? []
    }

    override func draggingUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
        onValidateDrop?(info, dropIndex(info)) ?? []
    }

    override func prepareForDragOperation(_ info: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ info: any NSDraggingInfo) -> Bool {
        onDrop?(info, dropIndex(info)) ?? false
    }
}

extension PanelGridView {
    // NSCollectionView is already a dragging source; offer copy and move like the detailed table.
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .generic]
    }
}

/// How a grid cell draws the cursor.
enum GridCursorStyle { case none, active, inactive }

extension PanelViewController {
    /// Connects a grid view's callbacks to the panel (the same for Brief and Thumbnails).
    func connectGridView(_ grid: PanelGridView) {
        grid.dataSource = self
        grid.isSelectable = false
        grid.backgroundColors = [.controlBackgroundColor]
        grid.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        grid.onFocus = { [weak self] in
            guard let self else { return }
            router?.panelDidBecomeFirstResponder(self)
        }
        grid.onMenu = { [weak self] index in self?.contextMenu(at: index) }
        grid.onDrag = { [weak self] index in
            guard let self, !model.isNetwork else { return [] }
            return draggedItems(from: index).map(dragItem(for:))
        }
        grid.onValidateDrop = { [weak self] info, index in
            guard let self, let target = dropTarget(row: index) else { return [] }
            return dragOperation(info, target: target)
        }
        grid.onDrop = { [weak self] info, index in
            guard let self, let target = dropTarget(row: index) else { return false }
            return performDrop(info, target: target)
        }
        grid.registerForDraggedTypes([.fileURL, Self.itemsType])
        grid.onClick = { [weak self] index, clicks in
            guard let self else { return }
            model.moveCursor(to: index)
            if clicks == 2 { perform(.open) }
        }
        grid.panel = self
    }
}
