// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Brief mode (⌃⌥2): names in columns that fill top to bottom, then left to right,
/// scrolling horizontally. ←/→ jump a whole column.
final class BriefGridView: NSCollectionView {
    var onKey: ((NSEvent) -> Bool)?
    var onFocus: (() -> Void)?
    var onClick: ((Int, Int) -> Void)?   // item index, click count

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    var onMenu: ((Int?) -> NSMenu?)?
    /// Drag source: pasteboard items for a drag that starts on the item at the index.
    var onDrag: ((Int) -> [NSPasteboardItem])?
    /// Drop target: the operation for a drop over the item at the index (nil = empty space)…
    var onValidateDrop: ((any NSDraggingInfo, Int?) -> NSDragOperation)?
    /// …and performing it.
    var onDrop: ((any NSDraggingInfo, Int?) -> Bool)?
    private var dragStart: (point: NSPoint, index: Int)?

    override func menu(for event: NSEvent) -> NSMenu? {
        // ⌃ + left click marks (spec 024); AppKit would show the context menu for it.
        if event.type == .leftMouseDown { return nil }
        return onMenu?(indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item)
    }

    /// The panel that runs mouse marking (spec 024).
    weak var panel: PanelViewController?
    /// The item of a plain press on a name, until the release or a drag.
    private var pendingRelease: Int?

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

    /// Whether `point` is on the icon or the name text of the item (where drag & drop starts).
    private func isOnName(_ point: NSPoint, index: Int) -> Bool {
        guard let cell = item(at: index)?.view as? BriefCellView else { return false }
        return isOnIconOrText(cell.convert(point, from: self), in: cell, icon: cell.icon, label: cell.label)
    }

    /// The items a rectangle touches, from the grid's geometry: columns of equal height filled top to
    /// bottom, so a large rectangle costs one range per column.
    func items(in rect: NSRect) -> IndexSet {
        let count = numberOfSections > 0 ? numberOfItems(inSection: 0) : 0
        guard count > 0 else { return [] }
        let first = frameForItem(at: 0)
        var rows = 1
        while rows < count, frameForItem(at: rows).minX == first.minX { rows += 1 }
        let stride = count > rows ? frameForItem(at: rows).minX - first.minX : first.width + 8
        guard stride > 0, first.height > 0 else { return [] }
        let firstColumn = max(0, Int(floor((rect.minX - first.minX) / stride)))
        let lastColumn = Int(floor((rect.maxX - first.minX) / stride))
        let firstRow = max(0, Int(floor((rect.minY - first.minY) / first.height)))
        let lastRow = min(rows - 1, Int(floor((rect.maxY - first.minY) / first.height)))
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return [] }
        var result = IndexSet()
        for column in firstColumn...lastColumn {
            let x = first.minX + CGFloat(column) * stride
            // The rectangle may lie in the gap between two columns only.
            guard rect.maxX >= x, rect.minX <= x + first.width else { continue }
            let low = column * rows + firstRow
            guard low < count else { break }
            result.insert(integersIn: low..<min(column * rows + lastRow + 1, count))
        }
        return result
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

extension BriefGridView {
    // NSCollectionView is already a dragging source; offer copy and move like the detailed table.
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .generic]
    }
}

final class BriefCellView: NSView {
    enum CursorStyle { case none, active, inactive }

    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    var cursorStyle = CursorStyle.none { didSet { if cursorStyle != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.lineBreakMode = .byTruncatingMiddle
        for view in [icon, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        switch cursorStyle {
        case .none: break
        case .active:
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        case .inactive:
            NSColor.secondaryLabelColor.setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).stroke()
        }
    }
}

final class BriefItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("BriefItem")
    var cell: BriefCellView { view as! BriefCellView }
    override func loadView() { view = BriefCellView() }
}

extension PanelViewController: NSCollectionViewDataSource {
    static let briefRowHeight: CGFloat = 18

    func configureBriefView() {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        layout.itemSize = NSSize(width: 160, height: Self.briefRowHeight)
        briefView.collectionViewLayout = layout
        briefView.dataSource = self
        briefView.isSelectable = false
        briefView.backgroundColors = [.controlBackgroundColor]
        briefView.register(BriefItem.self, forItemWithIdentifier: BriefItem.identifier)
        briefView.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        briefView.onFocus = { [weak self] in
            guard let self else { return }
            router?.panelDidBecomeFirstResponder(self)
        }
        briefView.onMenu = { [weak self] index in self?.contextMenu(at: index) }
        briefView.onDrag = { [weak self] index in
            guard let self, !model.isNetwork else { return [] }
            return draggedItems(from: index).map(dragItem(for:))
        }
        briefView.onValidateDrop = { [weak self] info, index in
            guard let self, let target = dropTarget(row: index) else { return [] }
            return dragOperation(info, target: target)
        }
        briefView.onDrop = { [weak self] info, index in
            guard let self, let target = dropTarget(row: index) else { return false }
            return performDrop(info, target: target)
        }
        briefView.registerForDraggedTypes([.fileURL, Self.itemsType])
        briefView.onClick = { [weak self] index, clicks in
            guard let self else { return }
            model.moveCursor(to: index)
            if clicks == 2 { perform(.open) }
        }
        briefView.panel = self
        briefScroll.documentView = briefView
        briefScroll.hasHorizontalScroller = true
        briefScroll.autohidesScrollers = true
    }

    /// Rows that fit in one column.
    var briefRows: Int {
        let height = briefScroll.contentView.bounds.height - 4
        return max(1, Int(height / Self.briefRowHeight))
    }

    /// Full columns visible at once.
    var briefVisibleColumns: Int {
        guard let layout = briefView.collectionViewLayout as? NSCollectionViewFlowLayout else { return 1 }
        return max(1, Int(briefScroll.contentView.bounds.width / (layout.itemSize.width + layout.minimumLineSpacing)))
    }

    func reloadBrief() {
        if let layout = briefView.collectionViewLayout as? NSCollectionViewFlowLayout {
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let ownNames = model.branch != nil
            let widest = model.items.prefix(2000).map { ((ownNames ? $0.fileName : $0.name) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            let width = min(max(widest + 30, 110), 300).rounded()
            if layout.itemSize.width != width { layout.itemSize = NSSize(width: width, height: Self.briefRowHeight) }
        }
        briefView.reloadData()
        scrollBriefToCursor()
    }

    func scrollBriefToCursor() {
        guard model.items.indices.contains(model.cursor) else { return }
        briefView.scrollToItems(at: [IndexPath(item: model.cursor, section: 0)], scrollPosition: .nearestVerticalEdge)
    }

    /// Redraws the cursor without reloading (cursor moves are frequent).
    func updateBriefCursor() {
        for case let item as BriefItem in briefView.visibleItems() {
            guard let index = briefView.indexPath(for: item)?.item else { continue }
            item.cell.cursorStyle = index == model.cursor ? (isActive ? .active : .inactive) : .none
            if model.items.indices.contains(index) {
                item.cell.label.textColor = briefTextColor(for: model.items[index], at: index)
                item.cell.label.font = textFont(marked: model.isSelected(model.items[index]))
            }
        }
    }

    private func briefTextColor(for item: FileItem, at index: Int) -> NSColor {
        let marked = model.isSelected(item)
        if index == model.cursor, isActive, !marked { return .alternateSelectedControlTextColor }
        return textColor(for: item, marked: marked)
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        model.items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: BriefItem.identifier, for: indexPath)
        guard let brief = item as? BriefItem, model.items.indices.contains(indexPath.item) else { return item }
        let file = model.items[indexPath.item]
        let marked = model.isSelected(file)
        // Branch view shows the file's own name; the tooltip has its path below the folder.
        brief.cell.label.stringValue = file.isParent ? ".." : model.branch != nil ? file.fileName : file.name
        brief.cell.label.font = textFont(marked: marked)
        brief.cell.label.textColor = briefTextColor(for: file, at: indexPath.item)
        brief.cell.icon.image = IconCache.icon(for: file)
        brief.cell.cursorStyle = indexPath.item == model.cursor ? (isActive ? .active : .inactive) : .none
        brief.cell.toolTip = file.name
        return brief
    }
}
