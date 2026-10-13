// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The find bar's view of the viewer text: it searches the source text, so a match is found across a
/// line break that exists only on screen (`SplitText`), and maps every range to the text view.
@MainActor
final class ViewerFindClient: NSObject, NSTextFinderClient {
    private let textView: NSTextView
    private var shown = SplitText("")
    /// The source as an immutable `NSString` of its own, built on the first search: a native Swift
    /// string is slow to index by UTF-16 offset, and the text view's storage is mutable, so handing it
    /// out would copy all of it on every call.
    private var sourceString: String?

    init(textView: NSTextView) {
        self.textView = textView
    }

    /// The text now in the text view; call `NSTextFinder.noteClientStringWillChange()` first.
    func show(_ text: SplitText) {
        shown = text
        sourceString = nil
    }

    private func display(_ range: NSRange) -> NSRange { shown.displayRange(ofSource: range) }

    private func source(_ range: NSRange) -> NSRange {
        let start = shown.sourceOffset(ofDisplay: range.location)
        return NSRange(location: start, length: max(0, shown.sourceOffset(ofDisplay: NSMaxRange(range)) - start))
    }

    // MARK: NSTextFinderClient

    var string: String {
        if let sourceString { return sourceString }
        let copy = NSMutableString(string: shown.source).copy() as! NSString as String
        sourceString = copy
        return copy
    }

    // isSelectable is left out: its selector clashes with an NSObject category, and the finder
    // assumes a selectable client without it.
    var allowsMultipleSelection: Bool { false }
    var isEditable: Bool { false }

    var firstSelectedRange: NSRange { source(textView.selectedRange()) }

    var selectedRanges: [NSValue] {
        get { textView.selectedRanges.map { NSValue(range: source($0.rangeValue)) } }
        set { textView.selectedRanges = newValue.map { NSValue(range: display($0.rangeValue)) } }
    }

    func scrollRangeToVisible(_ range: NSRange) {
        textView.scrollRangeToVisible(display(range))
    }

    var visibleCharacterRanges: [NSValue] {
        let visible = textView.visibleRect
        let first = textView.characterIndexForInsertion(at: visible.origin)
        let last = textView.characterIndexForInsertion(at: NSPoint(x: visible.maxX, y: visible.maxY))
        return [NSValue(range: source(NSRange(location: first, length: max(0, last - first))))]
    }

    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        outRange.pointee = NSRange(location: 0, length: (string as NSString).length)
        return textView
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        guard let layout = textView.textLayoutManager, let textRange = textRange(ofSource: range) else { return nil }
        let origin = textView.textContainerOrigin
        var rects: [NSValue] = []
        layout.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            rects.append(NSValue(rect: frame.offsetBy(dx: origin.x, dy: origin.y)))
            return true
        }
        return rects
    }

    /// The match text for the find indicator: the lines under the match, clipped to its rectangles.
    func drawCharacters(in range: NSRange, forContentView view: NSView) {
        guard let layout = textView.textLayoutManager, let textRange = textRange(ofSource: range),
              let context = NSGraphicsContext.current?.cgContext,
              let rects = rects(forCharacterRange: range)?.map(\.rectValue), !rects.isEmpty else { return }
        context.saveGState()
        context.clip(to: rects)
        let origin = textView.textContainerOrigin
        layout.enumerateTextLayoutFragments(from: textRange.location, options: [.ensuresLayout]) { fragment in
            guard fragment.rangeInElement.location.compare(textRange.endLocation) == .orderedAscending else {
                return false
            }
            let frame = fragment.layoutFragmentFrame
            fragment.draw(at: NSPoint(x: frame.minX + origin.x, y: frame.minY + origin.y), in: context)
            return true
        }
        context.restoreGState()
    }

    private func textRange(ofSource range: NSRange) -> NSTextRange? {
        guard let content = textView.textLayoutManager?.textContentManager else { return nil }
        let shown = display(range)
        guard let start = content.location(content.documentRange.location, offsetBy: shown.location),
              let end = content.location(start, offsetBy: shown.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }
}
