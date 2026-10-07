import AppKit
import CommanderCore

/// Tab expansion to 4-column stops, counted in UTF-16 units (one column each).
nonisolated enum TabStops {
    static let width = 4

    /// Display columns of `line` once its tabs are expanded.
    static func columns(of line: String) -> Int {
        var column = 0
        for unit in line.utf16 { column = unit == 9 ? column + width - column % width : column + 1 }
        return column
    }

    /// `line` with tabs expanded, plus the map from UTF-16 offsets in `line` (0…count) to offsets
    /// in the result; nil when the line has no tabs.
    static func expand(_ line: String) -> (text: String, map: [Int]?) {
        guard line.utf16.contains(9) else { return (line, nil) }
        var out = [UInt16]()
        out.reserveCapacity(line.utf16.count + 16)
        var map = [Int]()
        map.reserveCapacity(line.utf16.count + 1)
        for unit in line.utf16 {
            map.append(out.count)
            if unit == 9 {
                out.append(contentsOf: repeatElement(32, count: width - out.count % width))
            } else {
                out.append(unit)
            }
        }
        map.append(out.count)
        return (String(decoding: out, as: UTF16.self), map)
    }
}

/// Row tints of the compare window, light and dark.
nonisolated enum DiffColors {
    private static func dynamic(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let (r, g, b) = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
    }

    static let changed = dynamic((1.00, 0.95, 0.82), (0.29, 0.25, 0.12))
    static let changedStrong = dynamic((1.00, 0.84, 0.50), (0.52, 0.41, 0.13))
    static let deleted = dynamic((1.00, 0.91, 0.91), (0.33, 0.15, 0.15))
    static let deletedStrong = dynamic((0.96, 0.62, 0.62), (0.62, 0.24, 0.24))
    static let inserted = dynamic((0.89, 0.97, 0.89), (0.14, 0.29, 0.16))
    static let insertedStrong = dynamic((0.60, 0.88, 0.60), (0.22, 0.50, 0.26))
    static let placeholder = dynamic((0.93, 0.93, 0.93), (0.19, 0.19, 0.20))
    static let gap = dynamic((0.95, 0.95, 0.97), (0.17, 0.17, 0.19))
}

/// Side-by-side line diff. Draws only the visible rows: each half has a line-number gutter and the text.
/// Both halves are laid out inside the visible area and share one horizontal offset (the clip view's x),
/// so the sides always scroll together; the document is as wide as the visible area plus the overflow
/// of the longest line.
final class DiffView: NSView, NSMenuItemValidation {
    enum Side { case left, right }
    enum Step { case next, previous, first, last }
    enum BlockKind { case changed, deleted, inserted }

    /// One row on screen: an aligned diff row, or a run of hidden identical rows (Show Differences Only).
    enum DisplayRow: Equatable {
        case row(Int)
        case gap(Int)
    }

    struct Content {
        var diff: LineDiff
        var left: [String]
        var right: [String]
        var options: DiffOptions
        /// Widest line of both sides in columns (tabs expanded).
        var columns: Int
    }

    /// A line to come back to after a recompute.
    struct Anchor {
        var side: Side
        var line: Int
        var swapped: Anchor { Anchor(side: side == .left ? .right : .left, line: line) }
    }

    /// Window keys (next difference, Esc…) get the first chance at every key press.
    var onKey: ((NSEvent) -> Bool)?
    /// Current block or selection changed.
    var onStateChange: (() -> Void)?
    /// The visible area moved or resized.
    var onScroll: (() -> Void)?

    var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) {
        didSet {
            let top = topAnchor()
            updateMetrics()
            cache.removeAll()
            relayout()
            if let top { restore(top) }
        }
    }

    private(set) var content: Content?
    private(set) var differencesOnly = false
    private(set) var currentBlock: Int?
    private(set) var displayBlocks: [Range<Int>] = []
    private(set) var blockKinds: [BlockKind] = []
    private(set) var rowHeight: CGFloat = 16
    /// nil: every diff row in order.
    private var display: [DisplayRow]?

    var displayCount: Int { display?.count ?? content?.diff.rows.count ?? 0 }
    var blockCount: Int { displayBlocks.count }

    private struct Selection {
        var side: Side
        var anchor: Int
        var caret: Int
        var rows: ClosedRange<Int> { min(anchor, caret)...max(anchor, caret) }
    }
    private var selection: Selection?
    var hasSelection: Bool { selection != nil }

    /// Attributed text of both sides of one diff row (tabs expanded, inline changes marked).
    private struct Rendered {
        var left: NSAttributedString?
        var right: NSAttributedString?
    }
    private var cache: [Int: Rendered] = [:]

    private static let contextLines = 3
    private let dividerWidth: CGFloat = 1
    private let gutterPad: CGFloat = 6
    private let textPad: CGFloat = 6
    private var charWidth: CGFloat = 7
    private var gutterWidth: CGFloat = 40

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override class var isCompatibleWithResponsiveScrolling: Bool { false }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        updateMetrics()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Content

    /// Shows a new diff; scrolls back to `anchor`, or to the first difference when nil.
    func setContent(_ newContent: Content?, differencesOnly: Bool, anchor: Anchor?) {
        content = newContent
        self.differencesOnly = differencesOnly
        cache.removeAll()
        selection = nil
        blockKinds = newContent.map(Self.kinds) ?? []
        rebuildDisplay()
        relayout()
        if let anchor {
            restore(anchor)
            currentBlock = firstBlock(from: topRow)
        } else {
            currentBlock = displayBlocks.isEmpty ? nil : 0
            if let currentBlock { reveal(currentBlock) } else { scroll(toY: 0, x: 0) }
        }
        changed()
    }

    func setDifferencesOnly(_ on: Bool) {
        guard on != differencesOnly else { return }
        let top = topAnchor()
        differencesOnly = on
        selection = nil
        rebuildDisplay()
        relayout()
        if let top { restore(top) }
        changed()
    }

    private static func kinds(_ content: Content) -> [BlockKind] {
        content.diff.blocks.map { block in
            var deleted = false, inserted = false
            for row in content.diff.rows[block] {
                switch row.kind {
                case .changed: return .changed
                case .deleted: deleted = true
                case .inserted: inserted = true
                case .same: break
                }
            }
            return deleted == inserted ? .changed : deleted ? .deleted : .inserted
        }
    }

    /// Show Differences Only keeps `contextLines` around each block; the rest collapse into gap rows.
    private func rebuildDisplay() {
        guard let content else { display = nil; displayBlocks = []; return }
        let blocks = content.diff.blocks
        guard differencesOnly else { display = nil; displayBlocks = blocks; return }
        let count = content.diff.rows.count
        var kept = [Range<Int>]()
        var keptIndex = [Int]()
        for block in blocks {
            let range = max(0, block.lowerBound - Self.contextLines)..<min(count, block.upperBound + Self.contextLines)
            if let last = kept.last, range.lowerBound <= last.upperBound {
                kept[kept.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                kept.append(range)
            }
            keptIndex.append(kept.count - 1)
        }
        var rows = [DisplayRow]()
        var base = [Int]()
        var next = 0
        for range in kept {
            if range.lowerBound > next { rows.append(.gap(range.lowerBound - next)) }
            base.append(rows.count)
            rows.append(contentsOf: range.map(DisplayRow.row))
            next = range.upperBound
        }
        if next < count { rows.append(.gap(count - next)) }
        display = rows
        displayBlocks = blocks.indices.map { i in
            let k = keptIndex[i], start = base[k] + blocks[i].lowerBound - kept[k].lowerBound
            return start..<(start + blocks[i].count)
        }
    }

    private func displayRow(_ index: Int) -> DisplayRow { display?[index] ?? .row(index) }

    // MARK: Layout

    private func updateMetrics() {
        charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        rowHeight = ceil(font.ascender - font.descender + font.leading) + 2
    }

    private func halfWidth(_ width: CGFloat) -> CGFloat { floor((width - dividerWidth) / 2) }

    private func relayout() {
        guard let clip = superview as? NSClipView else { return }
        let size = clip.bounds.size
        let lines = max(content?.left.count ?? 0, content?.right.count ?? 0)
        gutterWidth = CGFloat(max(3, String(lines).count)) * charWidth + 2 * gutterPad
        let textWidth = halfWidth(size.width) - gutterWidth
        let overflow = max(0, CGFloat(content?.columns ?? 0) * charWidth + 2 * textPad - textWidth)
        setFrameSize(NSSize(width: size.width + ceil(overflow), height: max(CGFloat(displayCount) * rowHeight, size.height)))
        needsDisplay = true
        onScroll?()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let clip = superview as? NSClipView else { return }
        clip.postsFrameChangedNotifications = true
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipFrameChanged),
                                               name: NSView.frameDidChangeNotification, object: clip)
        NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged),
                                               name: NSView.boundsDidChangeNotification, object: clip)
        relayout()
    }

    @objc private func clipFrameChanged(_ note: Notification) { relayout() }

    /// The halves follow the visible area, so any scroll repaints everything visible.
    @objc private func clipBoundsChanged(_ note: Notification) {
        needsDisplay = true
        onScroll?()
    }

    // MARK: Scrolling

    private var topRow: Int { max(0, Int(visibleRect.minY / rowHeight)) }

    private func scroll(toY y: CGFloat, x: CGFloat? = nil) {
        guard let clip = superview as? NSClipView else { return }
        let maxX = max(0, bounds.width - clip.bounds.width), maxY = max(0, bounds.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: min(max(x ?? clip.bounds.minX, 0), maxX), y: min(max(y, 0), maxY)))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    /// Centers the visible area on `y` (overview clicks).
    func scrollToCenter(y: CGFloat) { scroll(toY: y - visibleRect.height / 2) }

    /// Scrolls block `index` to about a third from the top.
    private func reveal(_ index: Int) {
        scroll(toY: CGFloat(displayBlocks[index].lowerBound) * rowHeight - visibleRect.height / 3)
    }

    /// The first line shown at the top of the visible area.
    func topAnchor() -> Anchor? {
        guard let content else { return nil }
        for index in topRow..<max(topRow, displayCount) {
            guard case .row(let r) = displayRow(index) else { continue }
            let row = content.diff.rows[r]
            if let line = row.left { return Anchor(side: .left, line: line) }
            if let line = row.right { return Anchor(side: .right, line: line) }
        }
        return nil
    }

    private func restore(_ anchor: Anchor) {
        guard let content else { return }
        var target = max(0, displayCount - 1)
        for index in 0..<displayCount {
            guard case .row(let r) = displayRow(index) else { continue }
            let row = content.diff.rows[r]
            if let line = anchor.side == .left ? row.left : row.right, line >= anchor.line { target = index; break }
        }
        scroll(toY: CGFloat(target) * rowHeight)
    }

    // MARK: Blocks

    private func firstBlock(from row: Int) -> Int? {
        guard !displayBlocks.isEmpty else { return nil }
        return displayBlocks.firstIndex { $0.upperBound > row } ?? displayBlocks.count - 1
    }

    private func block(containing row: Int) -> Int? {
        var lo = 0, hi = displayBlocks.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if displayBlocks[mid].upperBound <= row { lo = mid + 1 } else { hi = mid }
        }
        return lo < displayBlocks.count && displayBlocks[lo].contains(row) ? lo : nil
    }

    /// Makes another block current and scrolls to it; false when there is none in that direction.
    func move(_ step: Step) -> Bool {
        let count = displayBlocks.count
        guard count > 0 else { return false }
        let target: Int
        switch step {
        case .first: target = 0
        case .last: target = count - 1
        case .next:
            if let currentBlock {
                guard currentBlock + 1 < count else { return false }
                target = currentBlock + 1
            } else {
                target = displayBlocks.firstIndex { $0.lowerBound >= topRow } ?? count - 1
            }
        case .previous:
            if let currentBlock {
                guard currentBlock > 0 else { return false }
                target = currentBlock - 1
            } else {
                target = displayBlocks.lastIndex { $0.lowerBound < topRow } ?? 0
            }
        }
        currentBlock = target
        reveal(target)
        changed()
        return true
    }

    private func changed() {
        needsDisplay = true
        onStateChange?()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        let visible = visibleRect
        let leftWidth = halfWidth(visible.width)
        let leftX = visible.minX, rightX = visible.minX + leftWidth + dividerWidth
        let rightWidth = visible.width - leftWidth - dividerWidth
        defer {
            NSColor.separatorColor.setFill()
            NSRect(x: leftX + leftWidth, y: dirtyRect.minY, width: dividerWidth, height: dirtyRect.height).fill()
        }
        guard let content else { return }
        let shift = max(0, min(visible.minX, bounds.width - visible.width))
        let first = max(0, Int(dirtyRect.minY / rowHeight))
        let last = min(displayCount - 1, Int(dirtyRect.maxY / rowHeight))
        guard first <= last else { return }
        let focused = window?.firstResponder === self && window?.isKeyWindow == true
        let selectionColor: NSColor = focused ? .selectedTextBackgroundColor : .unemphasizedSelectedTextBackgroundColor
        for index in first...last {
            let y = CGFloat(index) * rowHeight
            switch displayRow(index) {
            case .gap(let count):
                drawGap(count, y: y, x: visible.minX, width: visible.width)
            case .row(let r):
                let row = content.diff.rows[r]
                let rendered = self.rendered(r, content)
                for (side, x, width) in [(Side.left, leftX, leftWidth), (.right, rightX, rightWidth)] {
                    let selected = selection.map { $0.side == side && $0.rows.contains(index) } ?? false
                    drawHalf(side: side, row: row, text: side == .left ? rendered.left : rendered.right,
                             x: x, width: width, y: y, shift: shift, selection: selected ? selectionColor : nil)
                }
            }
        }
        if let currentBlock, displayBlocks.indices.contains(currentBlock) {
            drawMarker(displayBlocks[currentBlock], leftX: leftX, rightX: rightX, width: visible.width)
        }
    }

    private func drawHalf(side: Side, row: DiffRow, text: NSAttributedString?,
                          x: CGFloat, width: CGFloat, y: CGFloat, shift: CGFloat, selection: NSColor?) {
        let rect = NSRect(x: x, y: y, width: width, height: rowHeight)
        let line = side == .left ? row.left : row.right
        let tint: NSColor? = switch row.kind {
        case .same: nil
        case .changed: DiffColors.changed
        case .deleted: side == .left ? DiffColors.deleted : DiffColors.placeholder
        case .inserted: side == .right ? DiffColors.inserted : DiffColors.placeholder
        }
        if let tint { tint.setFill(); rect.fill() }
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        NSRect(x: x, y: y, width: gutterWidth, height: rowHeight).fill(using: .sourceOver)
        let textRect = NSRect(x: x + gutterWidth, y: y, width: max(0, width - gutterWidth), height: rowHeight)
        if let selection { selection.setFill(); textRect.fill() }
        guard let line else { return }
        let number = String(line + 1)
        number.draw(at: NSPoint(x: x + gutterWidth - gutterPad - CGFloat(number.utf16.count) * charWidth, y: y + 1),
                    withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        guard let text, text.length > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        textRect.clip()
        let origin = textRect.minX + textPad - shift
        if text.length > 2000 {
            // Long lines: lay out only the columns around the visible part.
            let start = max(0, Int(shift / charWidth) - 16)
            let length = Int(textRect.width / charWidth) + 32
            if start < text.length {
                let range = (text.string as NSString).rangeOfComposedCharacterSequences(
                    for: NSRange(location: start, length: min(length, text.length - start)))
                text.attributedSubstring(from: range)
                    .draw(at: NSPoint(x: origin + CGFloat(range.location) * charWidth, y: y + 1))
            }
        } else {
            text.draw(at: NSPoint(x: origin, y: y + 1))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGap(_ count: Int, y: CGFloat, x: CGFloat, width: CGFloat) {
        let rect = NSRect(x: x, y: y, width: width, height: rowHeight)
        DiffColors.gap.setFill()
        rect.fill()
        let label = String(localized: "⋯ \(count) identical lines")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(9, font.pointSize - 1)), .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: y + (rowHeight - size.height) / 2), withAttributes: attributes)
    }

    /// Current block: accent bars at the gutters and lines above and below it.
    private func drawMarker(_ block: Range<Int>, leftX: CGFloat, rightX: CGFloat, width: CGFloat) {
        let top = CGFloat(block.lowerBound) * rowHeight, bottom = CGFloat(block.upperBound) * rowHeight
        NSColor.controlAccentColor.setFill()
        for x in [leftX, rightX] { NSRect(x: x, y: top, width: 3, height: bottom - top).fill() }
        NSColor.controlAccentColor.withAlphaComponent(0.7).setFill()
        NSRect(x: leftX, y: top, width: width, height: 1).fill(using: .sourceOver)
        NSRect(x: leftX, y: bottom - 1, width: width, height: 1).fill(using: .sourceOver)
    }

    private func rendered(_ index: Int, _ content: Content) -> Rendered {
        if let hit = cache[index] { return hit }
        if cache.count > 4000 { cache.removeAll() }
        let row = content.diff.rows[index]
        let left = row.left.map { content.left[$0] }, right = row.right.map { content.right[$0] }
        var marks: (left: [NSRange], right: [NSRange]) = ([], [])
        if row.kind == .changed, let left, let right {
            marks = InlineDiff.ranges(left: left, right: right, options: content.options)
        }
        let value = Rendered(left: left.map { attributed($0, marks.left) }, right: right.map { attributed($0, marks.right) })
        cache[index] = value
        return value
    }

    private func attributed(_ line: String, _ marks: [NSRange]) -> NSAttributedString {
        let (text, map) = TabStops.expand(line)
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.textColor])
        for mark in marks {
            var range = mark
            if let map {
                guard NSMaxRange(mark) < map.count else { continue }
                range = NSRange(location: map[mark.location], length: map[NSMaxRange(mark)] - map[mark.location])
            }
            guard NSMaxRange(range) <= result.length else { continue }
            result.addAttribute(.backgroundColor, value: DiffColors.changedStrong, range: range)
        }
        return result
    }

    // MARK: Mouse and keys

    private func row(at point: NSPoint) -> Int {
        min(max(0, Int(point.y / rowHeight)), max(0, displayCount - 1))
    }

    private func side(at point: NSPoint) -> Side {
        point.x - visibleRect.minX < halfWidth(visibleRect.width) + dividerWidth / 2 ? .left : .right
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard displayCount > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let side = side(at: point), index = row(at: point)
        if event.modifierFlags.contains(.shift), var extended = selection, extended.side == side {
            extended.caret = index
            selection = extended
        } else {
            selection = Selection(side: side, anchor: index, caret: index)
        }
        if let block = block(containing: index) { currentBlock = block }
        changed()
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            autoscroll(with: next)
            selection?.caret = row(at: convert(next.locationInWindow, from: nil))
            changed()
        }
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        guard let chord = KeyChord(event: event) else { return super.keyDown(with: event) }
        let page = max(1, visibleRect.height - rowHeight)
        let y = visibleRect.minY
        switch (chord.key, chord.modifiers) {
        case (.up, []): scroll(toY: y - rowHeight)
        case (.down, []): scroll(toY: y + rowHeight)
        case (.pageUp, []): scroll(toY: y - page)
        case (.pageDown, []): scroll(toY: y + page)
        case (.home, []): scroll(toY: 0)
        case (.end, []): scroll(toY: bounds.height)
        case (.left, []): scroll(toY: y, x: visibleRect.minX - 4 * charWidth)
        case (.right, []): scroll(toY: y, x: visibleRect.minX + 4 * charWidth)
        default: super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) {
        guard let selection, let content else { return }
        let lines = selection.side == .left ? content.left : content.right
        var out = [String]()
        for index in selection.rows {
            guard index < displayCount, case .row(let r) = displayRow(index) else { continue }
            let row = content.diff.rows[r]
            if let line = selection.side == .left ? row.left : row.right { out.append(lines[line]) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out.joined(separator: "\n"), forType: .string)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(copy(_:)) ? hasSelection : true
    }
}

/// Overview strip beside the diff: every block scaled to the strip's height and a frame for the
/// visible area. Clicking or dragging jumps there.
final class DiffOverview: NSView {
    weak var diffView: DiffView?
    private let inset: CGFloat = 3

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var scale: CGFloat {
        guard let diffView, diffView.bounds.height > 0 else { return 0 }
        return (bounds.height - 2 * inset) / diffView.bounds.height
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        guard let diffView, diffView.content != nil else { return }
        let scale = self.scale, rowHeight = diffView.rowHeight
        let x: CGFloat = 3, width = bounds.width - 5
        var lastPixel = -1, lastKind: DiffView.BlockKind?
        func rect(_ block: Range<Int>) -> NSRect {
            let y = inset + CGFloat(block.lowerBound) * rowHeight * scale
            return NSRect(x: x, y: y, width: width, height: max(2, CGFloat(block.count) * rowHeight * scale))
        }
        for (index, block) in diffView.displayBlocks.enumerated() {
            let mark = rect(block), kind = diffView.blockKinds[index]
            // Thousands of blocks often share a pixel: draw each pixel row once per kind.
            let pixel = Int(mark.minY)
            if pixel == lastPixel, kind == lastKind { continue }
            lastPixel = pixel
            lastKind = kind
            let color = switch kind {
            case .changed: DiffColors.changedStrong
            case .deleted: DiffColors.deletedStrong
            case .inserted: DiffColors.insertedStrong
            }
            color.setFill()
            mark.fill()
        }
        if let current = diffView.currentBlock, diffView.displayBlocks.indices.contains(current) {
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: rect(diffView.displayBlocks[current]).insetBy(dx: -1, dy: -1))
            path.lineWidth = 1.5
            path.stroke()
        }
        let visible = diffView.visibleRect
        let frame = NSRect(x: 1.5, y: inset + visible.minY * scale, width: bounds.width - 2.5,
                           height: max(6, visible.height * scale)).integral.insetBy(dx: 0.5, dy: 0.5)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        frame.fill(using: .sourceOver)
        NSColor.secondaryLabelColor.setStroke()
        NSBezierPath(rect: frame).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        jump(to: event)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            jump(to: next)
        }
    }

    private func jump(to event: NSEvent) {
        let scale = self.scale
        guard let diffView, scale > 0 else { return }
        let point = convert(event.locationInWindow, from: nil)
        diffView.scrollToCenter(y: (point.y - inset) / scale)
    }
}
