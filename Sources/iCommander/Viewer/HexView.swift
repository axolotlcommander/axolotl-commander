import AppKit
import CommanderCore

/// Virtualized hex dump: offset, 16 bytes, characters. Draws only the visible
/// lines, so a memory-mapped file of any size opens instantly.
final class HexView: NSView {
    var data = Data() { didSet { caret = 0; anchor = nil; relayout() } }
    var encoding: TextEncoding = .utf8 { didSet { needsDisplay = true } }
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
    private var hexX: CGFloat { inset + CGFloat(offsetDigits + 2) * charWidth }
    private var charsX: CGFloat { hexX + CGFloat(48 + 2) * charWidth }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    private func relayout() {
        charWidth = ceil(("0" as NSString).size(withAttributes: [.font: font]).width)
        lineHeight = ceil(font.ascender - font.descender + font.leading) + 2
        offsetDigits = HexFormat.offsetText(0, fileSize: Int64(data.count)).count
        let width = charsX + CGFloat(HexFormat.bytesPerLine) * charWidth + inset
        let height = CGFloat(lineCount) * lineHeight + 2 * inset
        setFrameSize(NSSize(width: width, height: max(height, superview?.bounds.height ?? 0)))
        needsDisplay = true
        onSelectionChange?()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        relayout()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        let first = max(0, Int((dirtyRect.minY - inset) / lineHeight))
        let last = min(lineCount - 1, Int((dirtyRect.maxY - inset) / lineHeight))
        guard first <= last else { return }
        let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        let focused = window?.firstResponder === self && window?.isKeyWindow == true
        let selected = selection
        let base = data.startIndex
        for line in first...last {
            let y = inset + CGFloat(line) * lineHeight
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

    private func scrollTo(_ offset: Int) {
        let line = offset / HexFormat.bytesPerLine
        scrollToVisible(NSRect(x: 0, y: inset + CGFloat(line) * lineHeight - lineHeight,
                               width: 1, height: lineHeight * 3))
    }

    private func changed() {
        needsDisplay = true
        onSelectionChange?()
    }

    /// First byte of the top visible line.
    var topOffset: Int {
        let y = max(0, visibleRect.minY - inset)
        return min(Int(y / lineHeight) * HexFormat.bytesPerLine, max(0, data.count - 1))
    }

    func scrollToTop(offset: Int) {
        let line = offset / HexFormat.bytesPerLine
        scroll(NSPoint(x: 0, y: inset + CGFloat(line) * lineHeight))
    }

    private var pageLines: Int { max(1, Int(visibleRect.height / lineHeight) - 1) }

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
        let line = max(0, Int((point.y - inset) / lineHeight))
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
            autoscroll(with: next)
            let target = offset(at: convert(next.locationInWindow, from: nil))
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
