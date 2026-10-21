// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit

/// The name field of in-place renaming in Brief and Thumbnails (`specs/035-click-rename`). It lies over the
/// item's name label in the grid: Brief edits one line that widens with the text, Thumbnails wraps the name
/// and grows downwards, as Finder does. It never leaves `limit` (the visible part of the grid when editing
/// began).
final class GridRenameField: NSTextField {
    private let wraps: Bool
    private let anchor: NSRect
    private let limit: NSRect
    private static let padding: CGFloat = 6

    init(name: String, font: NSFont, wraps: Bool, anchor: NSRect, limit: NSRect) {
        self.wraps = wraps
        self.anchor = anchor
        self.limit = limit
        super.init(frame: anchor)
        stringValue = name
        self.font = font
        isEditable = true
        isSelectable = true
        isBordered = false
        isBezeled = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        textColor = .textColor
        focusRingType = .exterior
        alignment = wraps ? .center : .natural
        usesSingleLineMode = !wraps
        cell?.wraps = wraps
        cell?.isScrollable = !wraps
        lineBreakMode = wraps ? .byCharWrapping : .byClipping
        maximumNumberOfLines = 0
        fit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Sizes the field to the text typed so far.
    func fit() {
        let text = (currentEditor()?.string ?? stringValue) as NSString
        let lineHeight = ceil((font ?? .systemFont(ofSize: 13)).boundingRectForFont.height)
        var frame = anchor
        if wraps {
            frame.size.width = min(max(anchor.width, 60), limit.width)
            let bounds = text.boundingRect(with: NSSize(width: frame.width - Self.padding, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading],
                                           attributes: [.font: font as Any])
            frame.size.height = max(ceil(bounds.height) + 4, lineHeight + 4)
            frame.origin.x = anchor.midX - frame.width / 2
        } else {
            let width = ceil(text.size(withAttributes: [.font: font as Any]).width) + Self.padding * 2
            frame.size.width = min(max(anchor.width, width), limit.width)
            frame.size.height = max(anchor.height, lineHeight + 2)
            frame.origin.y = anchor.midY - frame.height / 2
        }
        frame.origin.x = min(max(frame.minX, limit.minX), limit.maxX - frame.width)
        if frame != self.frame { self.frame = frame.integral }
    }
}
