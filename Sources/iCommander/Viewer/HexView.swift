import AppKit
import CommanderCore

/// Virtualized hex dump: offset, 16 bytes, characters. Draws only the visible
/// lines, so a memory-mapped file of any size opens instantly.
///
/// The view is the scroll view's document but its height is capped (`maxHeight`): view and layer
/// coordinates lose precision far below the height of a large file. The position in the content
/// (`contentTop`, a Double) maps linearly onto the capped height; a canvas that follows the visible
/// area draws the lines from it, and the wheel and keys move it by exact lines.
final class HexView: NSView {
    var data = Data() { didSet { caret = 0; anchor = nil; relayout() } }
    var encoding: TextEncoding = .utf8 { didSet { redraw() } }
    var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) { didSet { relayout() } }

    /// Viewer keys (next file, Esc…) get the first chance at every key press.
    var onKey: ((NSEvent) -> Bool)?
    var onSelectionChange: (() -> Void)?

    private(set) var caret = 0
    private var anchor: Int?

    /// Selected byte range; the caret byte alone when nothing is selected.
    var selection: Range<Int> {
        guard !data.isEmpty else { return 0..<0 }
        guard let anchor else { return caret..<(caret + 1) }
        return min(anchor, caret)..<(max(anchor, caret) + 1)
    }
    var hasSelection: Bool { anchor != nil }

    private let inset: CGFloat = 6
    private var charWidth: CGFloat = 7
    private var lineHeight: CGFloat = 15
    private var offsetDigits = 8
    private var lineCount: Int { max(1, (data.count + HexFormat.bytesPerLine - 1) / HexFormat.bytesPerLine) }
    /// Content y at the top of the unobscured area (below the title bar; unscaled: the view's y there).
    private var contentTop: Double = 0
    private let canvas = HexCanvas()
    private static let maxHeight: Double = 1_000_000
    private var hexX: CGFloat { inset + CGFloat(offsetDigits + 2) * charWidth }
    private var charsX: CGFloat { hexX + CGFloat(48 + 2) * charWidth }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { redraw(); return true }
    override func resignFirstResponder() -> Bool { redraw(); return true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        canvas.owner = self
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func relayout() {
        // Exact advance: rounding up would drift the selection away from the text across a line.
        charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        offsetDigits = HexFormat.offsetText(0, fileSize: Int64(data.count)).count
        resize()
        setContentTop(contentTop)
        onSelectionChange?()
    }

    private func resize() {
        let width = charsX + CGFloat(HexFormat.bytesPerLine) * charWidth + inset
        setFrameSize(NSSize(width: width, height: max(min(naturalHeight, Self.maxHeight), viewHeight)))
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let clip = superview as? NSClipView {
            clip.postsFrameChangedNotifications = true
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipFrameChanged),
                                                   name: NSView.frameDidChangeNotification, object: clip)
            NotificationCenter.default.addObserver(self, selector: #selector(clipBoundsChanged),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
        }
        relayout()
    }

    @objc private func clipFrameChanged(_ note: Notification) {
        resize()
        setContentTop(contentTop)
    }

    /// A scroll by the scroller (or anything else that is not ours) moves the content to match.
    @objc private func clipBoundsChanged(_ note: Notification) {
        let y = Double(visibleRect.minY) + topInset
        if !isScaled || abs(y - scrollY(for: contentTop)) > 1 { contentTop = min(max(content(forScrollY: y), 0), maxContentTop) }
        placeCanvas()
    }

    // MARK: Content position

    /// The clip's insets: a full-size content view scrolls under the title bar and toolbar.
    private var topInset: Double { Double((superview as? NSClipView)?.contentInsets.top ?? 0) }
    /// The unobscured height of the clip.
    private var viewHeight: Double {
        guard let clip = superview as? NSClipView else { return 0 }
        return max(0, Double(clip.bounds.height - clip.contentInsets.top - clip.contentInsets.bottom))
    }
    private var naturalHeight: Double { Double(lineCount) * lineHeight + 2 * inset }
    private var isScaled: Bool { naturalHeight > Self.maxHeight }
    private var maxContentTop: Double { max(0, naturalHeight - viewHeight) }
    private var maxScrollY: Double { max(0, Double(bounds.height) - viewHeight) }

    private func content(forScrollY y: Double) -> Double {
        guard isScaled else { return y }
        return maxScrollY > 0 ? y / maxScrollY * maxContentTop : 0
    }

    private func scrollY(for content: Double) -> Double {
        guard isScaled else { return content }
        return maxContentTop > 0 ? content / maxContentTop * maxScrollY : 0
    }

    private func setContentTop(_ top: Double) {
        contentTop = min(max(top, 0), maxContentTop)
        if let clip = superview as? NSClipView {
            let target = NSPoint(x: clip.bounds.minX, y: scrollY(for: contentTop) - topInset)
            if abs(clip.bounds.minY - target.y) > 0.01 {
                clip.scroll(to: target)
                enclosingScrollView?.reflectScrolledClipView(clip)
            }
        }
        placeCanvas()
    }

    private func placeCanvas() {
        let visible = visibleRect
        canvas.frame = NSRect(x: 0, y: visible.minY, width: bounds.width, height: max(visible.height, 1))
        canvas.needsDisplay = true
    }

    private func redraw() { canvas.needsDisplay = true }

    /// When scaled, a wheel step would move many lines; the content moves by the wheel's distance.
    override func scrollWheel(with event: NSEvent) {
        guard isScaled, abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else { return super.scrollWheel(with: event) }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * lineHeight * 3
        setContentTop(contentTop - delta)
    }

    // MARK: Drawing

    /// Content y at the top of the canvas, which also covers the area under the title bar.
    private var canvasTop: Double { contentTop + Double(canvas.frame.minY) - scrollY(for: contentTop) }

    /// Draws the lines visible in the canvas (`rect` in canvas coordinates; its top is `canvasTop`).
    fileprivate func drawLines(_ rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        let top = canvasTop
        let first = max(0, Int((top + rect.minY - inset) / lineHeight))
        let last = min(lineCount - 1, Int((top + rect.maxY - inset) / lineHeight))
        guard first <= last else { return }
        let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        let focused = window?.firstResponder === self && window?.isKeyWindow == true
        let selected = selection
        let base = data.startIndex
        for line in first...last {
            let y = inset + Double(line) * lineHeight - top
            let start = line * HexFormat.bytesPerLine
            let end = min(start + HexFormat.bytesPerLine, data.count)
            drawSelection(line: start..<end, selected: selected, y: y, focused: focused)
            HexFormat.offsetText(Int64(start), fileSize: Int64(data.count))
                .draw(at: NSPoint(x: inset, y: y + 1), withAttributes: dim)
            guard start < end else { continue }
            let bytes = data[(base + start)..<(base + end)]
            HexFormat.hexText(bytes).draw(at: NSPoint(x: hexX, y: y + 1), withAttributes: plain)
            HexFormat.charText(bytes, encoding: encoding).draw(at: NSPoint(x: charsX, y: y + 1), withAttributes: plain)
        }
    }

    private func drawSelection(line: Range<Int>, selected: Range<Int>, y: CGFloat, focused: Bool) {
        let overlap = line.clamped(to: selected)
        guard !overlap.isEmpty else { return }
        let color: NSColor = focused ? .selectedTextBackgroundColor : .unemphasizedSelectedTextBackgroundColor
        color.setFill()
        let from = overlap.lowerBound - line.lowerBound, to = overlap.upperBound - line.lowerBound - 1
        let hexFrom = hexColumn(from), hexTo = hexColumn(to) + 2
        NSRect(x: hexX + CGFloat(hexFrom) * charWidth, y: y, width: CGFloat(hexTo - hexFrom) * charWidth, height: lineHeight).fill()
        NSRect(x: charsX + CGFloat(from) * charWidth, y: y, width: CGFloat(to - from + 1) * charWidth, height: lineHeight).fill()
        if !hasSelection, focused {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(rect: NSRect(x: charsX + CGFloat(from) * charWidth + 0.5, y: y + 0.5,
                                      width: charWidth - 1, height: lineHeight - 1)).stroke()
        }
    }

    /// Character column of byte `index` (0…15) inside the hex area.
    private func hexColumn(_ index: Int) -> Int { index * 3 + (index >= 8 ? 1 : 0) }

    // MARK: Caret and selection

    func select(_ range: Range<Int>) {
        guard !data.isEmpty else { return }
        let lower = min(max(range.lowerBound, 0), data.count - 1)
        let upper = min(max(range.upperBound - 1, lower), data.count - 1)
        anchor = range.count > 1 ? lower : nil
        caret = upper
        scrollTo(lower)
        changed()
    }

    private func moveCaret(to offset: Int, extend: Bool) {
        guard !data.isEmpty else { return }
        let target = min(max(offset, 0), data.count - 1)
        if extend { if anchor == nil { anchor = caret } } else { anchor = nil }
        caret = target
        scrollTo(caret)
        changed()
    }

    /// Scrolls so the line of `offset` is visible with a line of context.
    private func scrollTo(_ offset: Int) {
        let top = inset + Double(offset / HexFormat.bytesPerLine) * lineHeight
        if top - lineHeight < contentTop {
            setContentTop(top - lineHeight)
        } else if top + 2 * lineHeight > contentTop + viewHeight {
            setContentTop(top + 2 * lineHeight - viewHeight)
        }
    }

    private func changed() {
        redraw()
        onSelectionChange?()
    }

    /// First byte of the top visible line (the inset above the first line counts as part of it, so
    /// the first line keeps the view at its very top).
    var topOffset: Int {
        min(Int(contentTop / lineHeight) * HexFormat.bytesPerLine, max(0, data.count - 1))
    }

    func scrollToTop(offset: Int) {
        setContentTop(Double(offset / HexFormat.bytesPerLine) * lineHeight)
    }

    private var pageLines: Int { max(1, Int(viewHeight / lineHeight) - 1) }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        guard let chord = KeyChord(event: event) else { return super.keyDown(with: event) }
        let extend = chord.modifiers.contains(.shift)
        let mods = chord.modifiers.subtracting(.shift)
        let row = HexFormat.bytesPerLine
        switch (chord.key, mods) {
        case (.left, []): moveCaret(to: caret - 1, extend: extend)
        case (.right, []): moveCaret(to: caret + 1, extend: extend)
        case (.up, []): moveCaret(to: caret - row, extend: extend)
        case (.down, []): moveCaret(to: caret + row, extend: extend)
        case (.pageUp, []): moveCaret(to: caret - row * pageLines, extend: extend)
        case (.pageDown, []): moveCaret(to: caret + row * pageLines, extend: extend)
        case (.home, []), (.left, .command): moveCaret(to: caret - caret % row, extend: extend)
        case (.end, []), (.right, .command): moveCaret(to: caret - caret % row + row - 1, extend: extend)
        case (.home, .control), (.up, .command): moveCaret(to: 0, extend: extend)
        case (.end, .control), (.down, .command): moveCaret(to: data.count - 1, extend: extend)
        default: super.keyDown(with: event)
        }
    }

    private func offset(at point: NSPoint) -> Int {
        let line = max(0, Int((contentTop + point.y - scrollY(for: contentTop) - inset) / lineHeight))
        let index: Int
        if point.x >= charsX - charWidth {
            index = Int((point.x - charsX) / charWidth)
        } else {
            let column = Int((point.x - hexX) / charWidth)
            index = column < 24 ? column / 3 : (column - 1) / 3
        }
        let clamped = min(max(index, 0), HexFormat.bytesPerLine - 1)
        return min(line * HexFormat.bytesPerLine + clamped, max(0, data.count - 1))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        moveCaret(to: offset(at: point), extend: event.modifierFlags.contains(.shift))
        let start = anchor ?? caret
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
            let point = convert(next.locationInWindow, from: nil)
            if point.y < visibleRect.minY + topInset { setContentTop(contentTop - lineHeight) }
            if point.y > visibleRect.maxY { setContentTop(contentTop + lineHeight) }
            let target = offset(at: point)
            anchor = target == start ? nil : start
            caret = target
            changed()
        }
    }

    @objc func copy(_ sender: Any?) {
        guard !data.isEmpty else { return }
        let range = selection
        let bytes = data[(data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(HexFormat.plainHex(bytes), forType: .string)
    }

    @objc override func selectAll(_ sender: Any?) {
        guard !data.isEmpty else { return }
        anchor = 0
        caret = data.count - 1
        changed()
    }
}

/// Follows the visible area of its `HexView` and draws the lines there; clicks go to the view.
private final class HexCanvas: NSView {
    weak var owner: HexView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { owner?.drawLines(dirtyRect) }
}
