// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The free space of a disk as a small label (spec 020): the longest text that fits its width,
/// the full text with the used share as tooltip; a click opens Volume Info.
final class FreeSpaceLabel: NSView {
    var onClick: (() -> Void)?
    var space: DiskSpace? {
        didSet {
            guard space != oldValue else { return }
            variants = space.map { FreeSpaceText.variants($0, bytes: Format.bytes) } ?? []
            toolTip = space.map { FreeSpaceText.toolTip($0, bytes: Format.bytes) }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    private let label = NSTextField(labelWithString: "")
    private var variants: [String] = []
    /// The volume buttons' font next to them, the bar font in the status line.
    var fontRole = FontRole.volumeButtons { didSet { applyFont() } }
    private var font: NSFont { PanelFont.faces(fontRole).regular }
    private static let padding: CGFloat = 4

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = font
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byClipping
        label.alignment = .right
        addSubview(label)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Takes the font of its role chosen in Settings.
    func applyFont() {
        label.font = font
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    /// The width of the full text.
    override var intrinsicContentSize: NSSize {
        NSSize(width: variants.first.map(width) ?? 0, height: label.intrinsicContentSize.height)
    }

    /// The width the label takes in `available` points (0 when no text fits).
    func width(fitting available: CGFloat) -> CGFloat {
        FreeSpaceText.fitting(variants, available: available) { self.width($0) }.map(width) ?? 0
    }

    override func layout() {
        super.layout()
        let text = FreeSpaceText.fitting(variants, available: bounds.width) { self.width($0) } ?? ""
        if label.stringValue != text { label.stringValue = text }
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: ((bounds.height - height) / 2).rounded(), width: bounds.width, height: height)
    }

    override func mouseDown(with event: NSEvent) {
        if label.stringValue.isEmpty { return super.mouseDown(with: event) }
        onClick?()
    }

    override func resetCursorRects() {
        if !label.stringValue.isEmpty { addCursorRect(bounds, cursor: .pointingHand) }
    }

    private func width(_ text: String) -> CGFloat {
        ((text as NSString).size(withAttributes: [.font: font]).width + Self.padding).rounded(.up)
    }
}

/// The row below the volume bar: a drive combo (the panel's volume menu) and the free space.
final class DriveRowView: NSView {
    /// Opens the volume menu below `anchor`.
    var onOpenMenu: ((NSView) -> Void)?
    let freeSpace = FreeSpaceLabel()
    private let combo = NSButton()
    private var shown: (title: String, icon: NSImage?)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        combo.bezelStyle = .accessoryBarAction
        combo.controlSize = PanelFont.buttonControlSize
        combo.font = PanelFont.button
        combo.imagePosition = .imageLeading
        combo.refusesFirstResponder = true
        combo.lineBreakMode = .byTruncatingTail
        combo.target = self
        combo.action = #selector(openMenu)
        combo.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        combo.setAccessibilityRole(.popUpButton)
        let stack = NSStackView(views: [combo, freeSpace])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 20 + PanelFont.growth(.volumeButtons))
    }

    /// Takes the volume button font chosen in Settings.
    func applyFont() {
        combo.controlSize = PanelFont.buttonControlSize
        combo.font = PanelFont.button
        if let shown { show(title: shown.title, icon: shown.icon) }
        freeSpace.applyFont()
        invalidateIntrinsicContentSize()
    }

    /// Shows `title` and `icon` in the combo, with a chevron after the title.
    func show(title: String, icon: NSImage?) {
        shown = (title, icon)
        let text = NSMutableAttributedString(string: title + " ", attributes: [.font: combo.font ?? .systemFont(ofSize: 11)])
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)) {
            let attachment = NSTextAttachment()
            attachment.image = chevron
            text.append(NSAttributedString(attachment: attachment))
        }
        combo.attributedTitle = text
        icon?.size = NSSize(width: 14, height: 14)
        combo.image = icon
        combo.setAccessibilityTitle(title)
    }

    @objc private func openMenu() { onOpenMenu?(combo) }
}

/// Reads the capacity of the disk holding a folder off the main thread; one read at a time.
@MainActor
final class DiskSpaceMonitor {
    var onChange: ((DiskSpace?) -> Void)?
    private(set) var folder: URL?
    private(set) var space: DiskSpace?
    private var reading = false
    private var timer: Timer?

    /// Follows `folder` (nil: no disk, as for servers); reads at once.
    func watch(_ folder: URL?) {
        guard folder != self.folder else { return }
        self.folder = folder
        if folder == nil { publish(nil) }
        refresh()
    }

    /// Reads again every `interval` seconds while `isWanted` says so.
    func start(interval: TimeInterval, isWanted: @escaping @MainActor () -> Bool) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if isWanted() { self?.refresh() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard let folder, !reading else { return }
        reading = true
        Task {
            let space = await Self.read(folder)
            reading = false
            // The panel moved on while this was read: read the new folder.
            guard folder == self.folder else { return refresh() }
            publish(space)
        }
    }

    private func publish(_ space: DiskSpace?) {
        guard space != self.space else { return }
        self.space = space
        onChange?(space)
    }

    @concurrent
    private static func read(_ folder: URL) async -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey, .volumeIsReadOnlyKey]
        guard let values = try? folder.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity, total > 0 else {
            return nil
        }
        // Network volumes may not report the space for important use.
        let important = values.volumeAvailableCapacityForImportantUsage.flatMap { $0 > 0 ? $0 : nil }
        guard let available = important ?? values.volumeAvailableCapacity.map(Int64.init) else { return nil }
        return DiskSpace(total: Int64(total), available: available, isReadOnly: values.volumeIsReadOnly ?? false)
    }
}
