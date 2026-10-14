// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import UniformTypeIdentifiers

/// Thumbnails mode (⌃⌥3, spec 025): cells with a picture and the name below, in rows that wrap at the panel
/// width and scroll vertically. A layout of its own keeps every cell the same size and finds the cells in a
/// rectangle by arithmetic, so a folder of 100 000 items lays out at once.
final class ThumbnailGridLayout: NSCollectionViewLayout {
    static let inset: CGFloat = 4
    static let spacing: CGFloat = 4

    var size = ThumbnailSize.default { didSet { if size != oldValue { invalidateLayout() } } }
    private var count = 0
    private var columns = 1
    private var slot: CGFloat = 0
    private var width: CGFloat = 0

    var cellSize: NSSize {
        // Small pictures get a wider cell, so short names still fit on a line.
        NSSize(width: max(CGFloat(size.points) + 16, 100), height: CGFloat(size.points) + ThumbnailCellView.textHeight + 10)
    }
    private var rowStride: CGFloat { cellSize.height + Self.spacing }
    private var rows: Int { (count + columns - 1) / columns }

    /// Cells in one row.
    var columnCount: Int { columns }

    override func prepare() {
        super.prepare()
        guard let view = collectionView else { return }
        count = view.numberOfSections > 0 ? view.numberOfItems(inSection: 0) : 0
        width = view.enclosingScrollView?.contentView.bounds.width ?? view.bounds.width
        let available = max(0, width - 2 * Self.inset)
        columns = max(1, Int((available + Self.spacing) / (cellSize.width + Self.spacing)))
        // The free width is spread over the columns; a panel narrower than one cell scrolls sideways.
        slot = max(cellSize.width + Self.spacing, available / CGFloat(columns))
    }

    override var collectionViewContentSize: NSSize {
        let height = rows == 0 ? 0 : CGFloat(rows) * rowStride - Self.spacing
        return NSSize(width: max(width, 2 * Self.inset + cellSize.width), height: 2 * Self.inset + height)
    }

    private func frame(of index: Int) -> NSRect {
        let column = index % columns, row = index / columns
        return NSRect(x: Self.inset + CGFloat(column) * slot + (slot - cellSize.width) / 2,
                      y: Self.inset + CGFloat(row) * rowStride, width: cellSize.width, height: cellSize.height)
    }

    func geometry() -> GridGeometry? {
        guard count > 0 else { return nil }
        return GridGeometry(origin: frame(of: 0).origin, cell: cellSize, stride: NSSize(width: slot, height: rowStride),
                            perLine: columns, order: .rowsFirst, count: count)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard count > 0 else { return [] }
        let firstRow = max(0, Int(floor((rect.minY - Self.inset) / rowStride)))
        let lastRow = min(rows - 1, Int(floor((rect.maxY - Self.inset) / rowStride)))
        guard firstRow <= lastRow else { return [] }
        let indices = (firstRow * columns)..<min((lastRow + 1) * columns, count)
        return indices.map { attributes(at: $0) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        indexPath.item < count ? attributes(at: indexPath.item) : nil
    }

    private func attributes(at index: Int) -> NSCollectionViewLayoutAttributes {
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
        attributes.frame = frame(of: index)
        return attributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != width
    }
}

final class ThumbnailGridView: PanelGridView {
    /// A step to the next larger (+1) or smaller (−1) size from ⌘ + wheel or a pinch.
    var onSizeStep: ((Int) -> Void)?
    private var wheel: CGFloat = 0
    private var pinch: CGFloat = 0

    override func isOnName(_ point: NSPoint, index: Int) -> Bool {
        guard let cell = item(at: index)?.view as? ThumbnailCellView else { return false }
        return cell.nameZoneContains(cell.convert(point, from: self))
    }

    override func geometry() -> GridGeometry? { (collectionViewLayout as? ThumbnailGridLayout)?.geometry() }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            wheel = 0
            super.scrollWheel(with: event)
            return
        }
        wheel += event.scrollingDeltaY
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 40 : 1
        if abs(wheel) >= step {
            onSizeStep?(wheel > 0 ? 1 : -1)
            wheel = 0
        }
        if event.phase == .ended || event.momentumPhase == .ended { wheel = 0 }
    }

    override func magnify(with event: NSEvent) {
        if event.phase == .began { pinch = 0 }
        pinch += event.magnification
        if abs(pinch) >= 0.25 {
            onSizeStep?(pinch > 0 ? 1 : -1)
            pinch = 0
        }
    }
}

final class ThumbnailCellView: NSView {
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let textHeight: CGFloat = (2 * NSLayoutManager().defaultLineHeight(for: font)).rounded(.up) + 2

    let imageView = NSImageView()
    let label = NSTextField(wrappingLabelWithString: "")
    var side: CGFloat = CGFloat(ThumbnailSize.default.points) { didSet { if side != oldValue { needsLayout = true } } }
    var cursorStyle = GridCursorStyle.none { didSet { if cursorStyle != oldValue { needsDisplay = true } } }
    var marked = false { didSet { if marked != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        // An image view takes drops for itself; the grid handles them (a drop onto a folder's picture).
        imageView.unregisterDraggedTypes()
        label.alignment = .center
        label.isSelectable = false   // a wrapping label is selectable and would keep the clicks
        label.maximumNumberOfLines = 2
        // `show(name:font:)` makes the two lines; this only guards against a line that still does not fit.
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        label.font = Self.font
        addSubview(imageView)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var shown: (name: String, font: NSFont, width: CGFloat)?

    /// Shows the name on at most two lines: words wrap, and a name longer than that loses the middle of its
    /// second line, so the start and the extension stay visible (the full name is in the tooltip).
    func show(name: String, font: NSFont, width: CGFloat) {
        if let shown, shown.name == name, shown.font == font, shown.width == width { return }
        shown = (name, font, width)
        label.font = font
        label.stringValue = Self.twoLines(name, font: font, width: width - 6)
    }

    static func twoLines(_ name: String, font: NSFont, width: CGFloat) -> String {
        let text = wrappable(name)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let storage = NSTextStorage(string: text, attributes: attributes)
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        var lines: [NSRange] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, range, _ in
            lines.append(range)
        }
        guard lines.count > 2 else { return text }
        let first = manager.characterRange(forGlyphRange: lines[0], actualGlyphRange: nil)
        let all = text as NSString
        let head = all.substring(with: first).trimmingCharacters(in: .whitespaces)
        let rest = Array(all.substring(from: NSMaxRange(first)))
        func fits(_ line: String) -> Bool { (line as NSString).size(withAttributes: attributes).width <= width }
        // Keep `kept` characters around "…", a little more of the end (the extension).
        func line(_ kept: Int) -> String { String(rest.prefix(kept / 2)) + "…" + String(rest.suffix(kept - kept / 2)) }
        var low = 0, high = rest.count
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(line(mid)) { low = mid } else { high = mid - 1 }
        }
        return head + "\n" + line(low)
    }

    /// The name with break opportunities before the extension and after underscores, so "photo.jpeg" wraps
    /// as "photo" / ".jpeg" rather than inside a word.
    static func wrappable(_ name: String) -> String {
        var text = name.replacingOccurrences(of: "_", with: "_\u{200B}")
        if let dot = text.lastIndex(of: "."), dot != text.startIndex { text.insert("\u{200B}", at: dot) }
        return text
    }

    private var square: NSRect { NSRect(x: (bounds.width - side) / 2, y: 4, width: side, height: side) }

    override func layout() {
        super.layout()
        imageView.frame = square
        label.preferredMaxLayoutWidth = bounds.width - 8
        label.frame = NSRect(x: 4, y: square.maxY + 4, width: bounds.width - 8, height: Self.textHeight)
    }

    /// The picture as drawn (fitted into the square, at least 4 points thick) and the lines of the name.
    func nameZoneContains(_ point: NSPoint) -> Bool {
        if let image = imageView.image, image.size.width > 0, image.size.height > 0 {
            var drawn = square.size
            if imageView.imageScaling == .scaleProportionallyDown,
               image.size.width <= side, image.size.height <= side {
                drawn = image.size
            } else {
                let scale = min(side / image.size.width, side / image.size.height)
                drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            }
            drawn = NSSize(width: max(drawn.width, 4), height: max(drawn.height, 4))
            let rect = NSRect(x: square.midX - drawn.width / 2, y: square.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height)
            if rect.insetBy(dx: -2, dy: -2).contains(point) { return true }
        }
        guard let cell = label.cell else { return false }
        let text = cell.cellSize(forBounds: NSRect(origin: .zero, size: label.frame.size))
        let zone = NSRect(x: label.frame.midX - min(text.width, label.frame.width) / 2 - 2, y: label.frame.minY,
                          width: min(text.width, label.frame.width) + 4, height: min(text.height, label.frame.height))
        return zone.contains(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        if marked, cursorStyle != .active {
            AppSettings.shared.appearance.markColor.nsColor.withAlphaComponent(0.15).setFill()
            path.fill()
        }
        switch cursorStyle {
        case .none: break
        case .active:
            NSColor.selectedContentBackgroundColor.setFill()
            path.fill()
        case .inactive:
            NSColor.secondaryLabelColor.setStroke()
            path.stroke()
        }
    }
}

final class ThumbnailItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailItem")
    var cell: ThumbnailCellView { view as! ThumbnailCellView }
    /// The preview the cell shows or waits for; nil for items without previews.
    var key: ThumbnailKey?
    override func loadView() { view = ThumbnailCellView() }
}

/// Large type icons for the cells, shown until (or instead of) a preview; one image per type and size.
@MainActor
enum LargeIcons {
    private static var byKey: [String: NSImage] = [:]

    static func icon(for item: FileItem, points: Int) -> NSImage {
        let key: String
        let make: () -> NSImage
        if item.isParent {
            key = "#parent"
            make = {
                let symbol = NSImage(systemSymbolName: "arrow.turn.left.up",
                                     accessibilityDescription: String(localized: "Parent folder"))!
                return symbol.withSymbolConfiguration(.init(pointSize: 64, weight: .light)) ?? symbol
            }
        } else if NetworkPlaces.isNetwork(item.url) {
            key = "#server"
            make = {
                let symbol = NSImage(systemSymbolName: "server.rack", accessibilityDescription: String(localized: "Server"))!
                return symbol.withSymbolConfiguration(.init(pointSize: 64, weight: .light)) ?? symbol
            }
        } else if item.isDirectory, !item.isPackage {
            key = item.isSymlink ? "#dirlink" : "#dir"
            make = { NSWorkspace.shared.icon(for: .folder) }
        } else {
            let ext = item.fileExtension.lowercased()
            key = "." + ext
            make = { NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? (item.isPackage ? .package : .data)) }
        }
        let sized = "\(key)@\(points)"
        if let cached = byKey[sized] { return cached }
        let image = make().copy() as! NSImage
        if !item.isParent, !NetworkPlaces.isNetwork(item.url) { image.size = NSSize(width: points, height: points) }
        byKey[sized] = image
        return image
    }
}

extension PanelViewController {
    func configureThumbnailView() {
        let layout = ThumbnailGridLayout()
        layout.size = ThumbnailSize.saved()
        thumbnailView.collectionViewLayout = layout
        thumbnailView.register(ThumbnailItem.self, forItemWithIdentifier: ThumbnailItem.identifier)
        connectGridView(thumbnailView)
        thumbnailView.onSizeStep = { [weak self] step in self?.stepThumbnailSize(step) }
        thumbnailScroll.documentView = thumbnailView
        thumbnailScroll.hasVerticalScroller = true
        thumbnailScroll.hasHorizontalScroller = true
        thumbnailScroll.autohidesScrollers = true
        thumbnailScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(thumbnailsScrolled),
                                               name: NSView.boundsDidChangeNotification, object: thumbnailScroll.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(thumbnailSizeSettingChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        thumbnailLoader.onImage = { [weak self] key, image in self?.showThumbnail(image, for: key) }
    }

    var thumbnailLayout: ThumbnailGridLayout? { thumbnailView.collectionViewLayout as? ThumbnailGridLayout }

    /// Cells in one row and full rows visible at once (for the cursor keys).
    var thumbnailColumns: Int { thumbnailLayout?.columnCount ?? 1 }
    var thumbnailVisibleRows: Int {
        guard let layout = thumbnailLayout else { return 1 }
        let row = layout.cellSize.height + ThumbnailGridLayout.spacing
        return max(1, Int((thumbnailScroll.contentView.bounds.height + ThumbnailGridLayout.spacing) / row))
    }

    func reloadThumbnails() {
        thumbnailView.reloadData()
        thumbnailView.layoutSubtreeIfNeeded()
        scrollThumbnailsToCursor()
        requestThumbnails()
    }

    func scrollThumbnailsToCursor() {
        guard model.items.indices.contains(model.cursor) else { return }
        let frame = thumbnailView.frameForItem(at: model.cursor)
        guard !frame.isEmpty else { return }
        thumbnailView.scrollToVisible(frame.insetBy(dx: 0, dy: -ThumbnailGridLayout.spacing))
    }

    /// Redraws the cursor and the marks of the visible cells without reloading (cursor moves are frequent).
    func updateThumbnailCursor() {
        for case let item as ThumbnailItem in thumbnailView.visibleItems() {
            guard let index = thumbnailView.indexPath(for: item)?.item, model.items.indices.contains(index) else { continue }
            styleThumbnailCell(item.cell, for: model.items[index], at: index)
        }
    }

    private func styleThumbnailCell(_ cell: ThumbnailCellView, for file: FileItem, at index: Int) {
        let marked = model.isSelected(file)
        cell.marked = marked
        cell.cursorStyle = index == model.cursor ? (isActive ? .active : .inactive) : .none
        cell.show(name: file.isParent ? ".." : model.branch != nil ? file.fileName : file.name,
                  font: textFont(marked: marked), width: (thumbnailLayout?.cellSize.width ?? cell.bounds.width) - 8)
        cell.label.textColor = index == model.cursor && isActive && !marked
            ? .alternateSelectedControlTextColor : textColor(for: file, marked: marked)
    }

    func thumbnailItem(at indexPath: IndexPath) -> NSCollectionViewItem {
        let item = thumbnailView.makeItem(withIdentifier: ThumbnailItem.identifier, for: indexPath)
        guard let thumb = item as? ThumbnailItem, model.items.indices.contains(indexPath.item) else { return item }
        let file = model.items[indexPath.item]
        let size = thumbnailLayout?.size ?? .default
        thumb.cell.side = CGFloat(size.points)
        thumb.cell.toolTip = file.isParent ? ".." : file.name
        styleThumbnailCell(thumb.cell, for: file, at: indexPath.item)
        thumb.key = thumbnailKey(for: file, size: size)
        let preview = thumb.key.flatMap { ThumbnailLoader.cached($0) }
        setThumbnailImage(preview ?? LargeIcons.icon(for: file, points: size.points), of: thumb.cell,
                          isSymbol: preview == nil && (file.isParent || NetworkPlaces.isNetwork(file.url)))
        thumb.cell.imageView.alphaValue = file.isHidden ? 0.5 : 1
        return thumb
    }

    private func setThumbnailImage(_ image: NSImage, of cell: ThumbnailCellView, isSymbol: Bool) {
        // Symbols keep their own size; icons and previews fill the square.
        cell.imageView.imageScaling = isSymbol ? .scaleProportionallyDown : .scaleProportionallyUpOrDown
        cell.imageView.contentTintColor = isSymbol ? .secondaryLabelColor : nil
        cell.imageView.image = image
    }

    /// Previews only for files the system can read directly (FR-015).
    var panelAllowsThumbnails: Bool {
        ThumbnailPolicy.allowsPreviews(inArchive: model.archive != nil, onServer: model.remote != nil,
                                       isNetwork: model.isNetwork)
    }

    private func thumbnailKey(for file: FileItem, size: ThumbnailSize) -> ThumbnailKey? {
        // An empty file has nothing to show: it keeps its icon.
        guard !file.isParent, panelAllowsThumbnails, file.isDirectory || file.size != 0 else { return nil }
        // Find results and branch view list items from several places.
        if model.results != nil || model.branch != nil, !ThumbnailPolicy.allowsPreview(of: file.url) { return nil }
        return ThumbnailKey(path: file.url.path, modified: file.modificationDate, size: size)
    }

    /// Asks for the previews of the visible cells first, then of one screen above and below them.
    func requestThumbnails() {
        guard viewMode == .thumbnails, panelAllowsThumbnails, let geometry = thumbnailView.geometry(),
              let size = thumbnailLayout?.size else {
            thumbnailLoader.want([])
            return
        }
        let visible = thumbnailScroll.contentView.bounds
        let shown = geometry.indices(in: visible)
        let margin = geometry.indices(in: visible.insetBy(dx: 0, dy: -visible.height)).subtracting(shown)
        var wanted: [(key: ThumbnailKey, url: URL)] = []
        for index in Array(shown) + Array(margin) where model.items.indices.contains(index) {
            let file = model.items[index]
            if let key = thumbnailKey(for: file, size: size) { wanted.append((key, file.url)) }
        }
        thumbnailLoader.scale = view.window?.backingScaleFactor ?? 2
        thumbnailLoader.want(wanted)
    }

    private func showThumbnail(_ image: NSImage, for key: ThumbnailKey) {
        for case let item as ThumbnailItem in thumbnailView.visibleItems() where item.key == key {
            setThumbnailImage(image, of: item.cell, isSymbol: false)
        }
    }

    @objc private func thumbnailsScrolled() {
        if viewMode == .thumbnails { requestThumbnails() }
    }

    @objc private func thumbnailSizeSettingChanged() {
        let size = ThumbnailSize.saved()
        guard let layout = thumbnailLayout, layout.size != size else { return }
        layout.size = size
        if viewMode == .thumbnails { reloadThumbnails() }
    }

    /// ⌘+ / ⌘−, ⌘ + wheel and pinch: the next size for every Thumbnails view (FR-017, FR-018).
    func stepThumbnailSize(_ step: Int) {
        let current = ThumbnailSize.saved()
        guard let next = step > 0 ? current.larger : current.smaller else { return }
        UserDefaults.standard.set(next.rawValue, forKey: ThumbnailSize.key)
    }
}
