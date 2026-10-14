// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Brief mode (⌃⌥2): names in columns that fill top to bottom, then left to right,
/// scrolling horizontally. ←/→ jump a whole column.
final class BriefGridView: PanelGridView {
    /// Whether `point` is on the icon or the name text of the item (where drag & drop starts).
    override func isOnName(_ point: NSPoint, index: Int) -> Bool {
        guard let cell = item(at: index)?.view as? BriefCellView else { return false }
        return isOnIconOrText(cell.convert(point, from: self), in: cell, icon: cell.icon, label: cell.label)
    }

    /// Columns of equal height filled top to bottom, so a large rectangle costs one range per column.
    override func geometry() -> GridGeometry? {
        let count = itemCount
        guard count > 0 else { return nil }
        let first = frameForItem(at: 0)
        var rows = 1
        while rows < count, frameForItem(at: rows).minX == first.minX { rows += 1 }
        let stride = count > rows ? frameForItem(at: rows).minX - first.minX : first.width + 8
        return GridGeometry(origin: first.origin, cell: first.size, stride: NSSize(width: stride, height: first.height),
                            perLine: rows, order: .columnsFirst, count: count)
    }
}

final class BriefCellView: NSView {
    typealias CursorStyle = GridCursorStyle

    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    var cursorStyle = CursorStyle.none { didSet { if cursorStyle != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.lineBreakMode = .byTruncatingMiddle
        // An image view takes drops for itself; the grid handles them (a drop onto a folder's icon).
        icon.unregisterDraggedTypes()
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
        briefView.register(BriefItem.self, forItemWithIdentifier: BriefItem.identifier)
        connectGridView(briefView)
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
        if collectionView === thumbnailView { return thumbnailItem(at: indexPath) }
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
