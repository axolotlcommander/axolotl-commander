// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import UniformTypeIdentifiers

/// The path line above a panel's file list: clickable breadcrumbs (volume › … › folder) or the
/// editable path field, by the "Path bar" setting. The bar hosts the panel's field and swaps it in
/// for typing a path. It only renders; the panel decides what a click does.
final class PathBar: NSView {
    enum Style: String { case breadcrumbs, text }

    static let styleKey = "pathBar.style"
    static let iconsKey = "pathBar.showIcons"

    /// Path bar style from the settings (breadcrumbs unless the user chose the text field).
    static var savedStyle: Style {
        UserDefaults.standard.string(forKey: styleKey).flatMap(Style.init(rawValue:)) ?? .breadcrumbs
    }

    static var savedShowsIcons: Bool { UserDefaults.standard.object(forKey: iconsKey) as? Bool ?? true }

    let field: NSTextField
    private(set) var style: Style = .breadcrumbs
    private(set) var showsIcons = true
    private(set) var trail: [PathSegment] = []
    private(set) var isEditing = false
    var isActive = false { didSet { if isActive != oldValue { needsDisplay = true } } }

    /// A click on segment `index` of `trail` (with the modifiers held).
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    /// The context menu of segment `index`.
    var menuForSegment: ((Int) -> NSMenu?)?
    /// A click right of the last segment.
    var onEmptyClick: (() -> Void)?

    private var segmentViews: [PathSegmentView] = []
    private let ellipsis = PathSegmentView()
    private var hiddenRange: Range<Int>?
    private var separatorOrigins: [NSPoint] = []
    private var iconCache: [String: NSImage] = [:]

    private static let height: CGFloat = 20
    private static let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    private static let separator = NSAttributedString(string: "›", attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.tertiaryLabelColor,
    ])
    private static let separatorGap: CGFloat = 2
    private static var separatorWidth: CGFloat { ceil(separator.size().width) + 2 * separatorGap }
    private static let inset: CGFloat = 2

    init(field: NSTextField) {
        self.field = field
        super.init(frame: .zero)
        field.drawsBackground = false
        addSubview(field)
        ellipsis.configure(name: "…", image: nil, emphasized: false, clickable: true)
        ellipsis.setAccessibilityLabel(String(localized: "Hidden folders"))
        ellipsis.onClick = { [weak self] _ in self?.showHiddenMenu() }
        addSubview(ellipsis)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Path"))
        apply(style: Self.savedStyle, showsIcons: Self.savedShowsIcons)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    override var isFlipped: Bool { true }

    // MARK: Content

    func show(trail: [PathSegment]) {
        guard trail != self.trail else { return }
        self.trail = trail
        rebuildSegments()
    }

    func apply(style: Style, showsIcons: Bool) {
        let iconsChanged = showsIcons != self.showsIcons
        self.style = style
        self.showsIcons = showsIcons
        if iconsChanged { rebuildSegments() }
        updateVisibility()
    }

    /// Breadcrumb mode: the field replaces the row until editing ends.
    func beginEditing() {
        guard style == .breadcrumbs else { return }
        isEditing = true
        updateVisibility()
    }

    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        updateVisibility()
    }

    private var showsRow: Bool { style == .breadcrumbs && !isEditing }

    private func updateVisibility() {
        field.isHidden = showsRow
        for view in segmentViews { view.isHidden = !showsRow }
        ellipsis.isHidden = !showsRow
        needsLayout = true
        needsDisplay = true
    }

    private func rebuildSegments() {
        segmentViews.forEach { $0.removeFromSuperview() }
        segmentViews = trail.enumerated().map { index, segment in
            let view = PathSegmentView()
            view.configure(name: segment.name, image: showsIcons ? icon(for: segment) : nil,
                           emphasized: index == trail.count - 1, clickable: segment.isClickable)
            view.onClick = { [weak self] flags in self?.onClick?(index, flags) }
            view.onMenu = { [weak self] in self?.menuForSegment?(index) }
            addSubview(view)
            return view
        }
        updateVisibility()
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let fieldHeight = min(field.intrinsicContentSize.height, bounds.height)
        field.frame = NSRect(x: Self.inset, y: ((bounds.height - fieldHeight) / 2).rounded(),
                             width: max(bounds.width - 2 * Self.inset, 0), height: fieldHeight)
        layoutRow()
    }

    private func layoutRow() {
        separatorOrigins = []
        guard showsRow, !segmentViews.isEmpty else { return }
        let widths = segmentViews.map { Double($0.naturalWidth) }
        let fit = Breadcrumbs.fit(widths: widths, available: Double(bounds.width - 2 * Self.inset),
                                  ellipsis: Double(ellipsis.naturalWidth), separator: Double(Self.separatorWidth))
        hiddenRange = fit.hidden
        let shown = Set(fit.visible)
        var x = Self.inset
        let sepY = ((bounds.height - Self.separator.size().height) / 2).rounded()
        func place(_ view: PathSegmentView, width: CGFloat) {
            if x > Self.inset {
                separatorOrigins.append(NSPoint(x: x + Self.separatorGap, y: sepY))
                x += Self.separatorWidth
            }
            view.frame = NSRect(x: x, y: 1, width: width, height: bounds.height - 2)
            x += width
        }
        for (index, view) in segmentViews.enumerated() {
            view.isHidden = !shown.contains(index)
            guard shown.contains(index) else { continue }
            let isLast = index == segmentViews.count - 1
            place(view, width: isLast ? fit.lastWidth.map { CGFloat($0) } ?? view.naturalWidth : view.naturalWidth)
            if index == 0, fit.hidden != nil { place(ellipsis, width: ellipsis.naturalWidth) }
        }
        ellipsis.isHidden = fit.hidden == nil
    }

    // MARK: Drawing and events

    override func draw(_ dirtyRect: NSRect) {
        (isActive ? NSColor.controlAccentColor.withAlphaComponent(0.28) : NSColor.quaternarySystemFill).setFill()
        bounds.fill()
        for origin in separatorOrigins { Self.separator.draw(at: origin) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// A click on the bar outside the segments: right of the last one starts typing a path.
    override func mouseDown(with event: NSEvent) {
        guard showsRow else { return super.mouseDown(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        let end = segmentViews.last.map(\.frame.maxX) ?? 0
        if point.x > end { onEmptyClick?() }
    }

    private func showHiddenMenu() {
        guard let hidden = hiddenRange else { return }
        let menu = NSMenu()
        for index in hidden {
            let item = NSMenuItem(title: trail[index].name, action: #selector(hiddenChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = icon(for: trail[index])
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: ellipsis.frame.minX, y: bounds.maxY + 2), in: self)
    }

    @objc private func hiddenChosen(_ sender: NSMenuItem) { onClick?(sender.tag, []) }

    // MARK: Icons

    /// Finder's icons for local folders and volumes; generic ones inside archives and on servers.
    func icon(for segment: PathSegment) -> NSImage {
        let key = "\(segment.kind)|\(segment.url.absoluteString)"
        if let cached = iconCache[key] { return cached }
        let image: NSImage
        switch segment.kind {
        case .volume, .home, .folder, .archive:
            image = NSWorkspace.shared.icon(forFile: segment.url.path(percentEncoded: false))
        case .archiveFolder, .remoteFolder:
            image = NSImage(named: NSImage.folderName) ?? NSWorkspace.shared.icon(for: .folder)
        case .server:
            image = NSImage(systemSymbolName: "network", accessibilityDescription: nil) ?? NSImage()
        case .results:
            image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage()
        }
        let sized = image.copy() as? NSImage ?? image
        sized.size = NSSize(width: 16, height: 16)
        if iconCache.count > 256 { iconCache.removeAll() }
        iconCache[key] = sized
        return sized
    }
}

/// One breadcrumb: icon and name, highlighted under the mouse. It never takes keyboard focus.
private final class PathSegmentView: NSView {
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onMenu: (() -> NSMenu?)?

    private var name = ""
    private var image: NSImage?
    private var emphasized = false
    private var clickable = true
    private var hovering = false { didSet { if hovering != oldValue { needsDisplay = true } } }
    private var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }
    /// Modifiers of the mouse down that the next mouse up completes.
    private var pressedFlags: NSEvent.ModifierFlags?

    private static let padding: CGFloat = 4
    private static let iconGap: CGFloat = 3

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(name: String, image: NSImage?, emphasized: Bool, clickable: Bool) {
        self.name = name
        self.image = image
        self.emphasized = emphasized
        self.clickable = clickable
        setAccessibilityElement(true)
        setAccessibilityRole(clickable ? .button : .staticText)
        setAccessibilityLabel(name)
        needsDisplay = true
    }

    private var title: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let font = emphasized ? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            : NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return NSAttributedString(string: name, attributes: [
            .font: font, .foregroundColor: clickable ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ])
    }

    var naturalWidth: CGFloat {
        let icon = image == nil ? 0 : 16 + Self.iconGap
        return ceil(title.size().width) + icon + 2 * Self.padding
    }

    override func draw(_ dirtyRect: NSRect) {
        if clickable, hovering || pressed {
            NSColor.labelColor.withAlphaComponent(pressed ? 0.16 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        var x = Self.padding
        if let image {
            image.draw(in: NSRect(x: x, y: ((bounds.height - 16) / 2).rounded(), width: 16, height: 16),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            x += 16 + Self.iconGap
        }
        let text = title
        let height = ceil(text.size().height)
        text.draw(with: NSRect(x: x, y: ((bounds.height - height) / 2).rounded(),
                               width: max(bounds.width - x - Self.padding, 0), height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    // A shortened name shows in full as a tooltip.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        toolTip = newSize.width + 0.5 < naturalWidth ? name : nil
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(for: event)
            return
        }
        pressedFlags = event.modifierFlags
        pressed = clickable
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressedFlags != nil else { return }
        pressed = clickable && bounds.contains(convert(event.locationInWindow, from: nil))
    }

    /// The click counts only when the button goes up inside the segment.
    override func mouseUp(with event: NSEvent) {
        guard let flags = pressedFlags else { return }
        pressedFlags = nil
        pressed = false
        if clickable, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?(flags) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }

    private func showMenu(for event: NSEvent) {
        guard let menu = onMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func accessibilityPerformPress() -> Bool {
        guard clickable else { return false }
        onClick?([])
        return true
    }
}
