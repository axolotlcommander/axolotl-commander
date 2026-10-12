// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import Quartz

/// The quick view panel (⌃Q): laid over the panel opposite the active one, it shows the system
/// preview of the active panel's cursor item and never takes the keyboard focus.
@MainActor
final class QuickViewPane: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let note = NSTextField(wrappingLabelWithString: "")
    private let preview: QLPreviewView?
    private var shown: QuickViewSubject?
    private var pending: Task<Void, Never>?
    /// A click on the pane: the covered panel takes over, which ends the quick view.
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        preview = QLPreviewView(frame: .zero, style: .normal)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        nameLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        note.textColor = .secondaryLabelColor
        note.alignment = .center
        note.stringValue = String(localized: "Items in archives, on servers and in the Network folder have no preview.")
        note.isHidden = true
        preview?.shouldCloseWithWindow = true
        registerForDraggedTypes([.fileURL, .URL, .string])
        preview?.autostarts = true

        let views: [NSView] = [nameLabel, note] + (preview.map { [$0] } ?? [])
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        var constraints = [
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            note.centerYAnchor.constraint(equalTo: centerYAnchor),
            note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            note.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ]
        if let preview {
            constraints += [
                preview.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
                preview.leadingAnchor.constraint(equalTo: leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: trailingAnchor),
                preview.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }

    /// The wheel scrolls the preview; every other mouse event stays with the pane, so nothing of the
    /// covered panel underneath is clicked, and the preview never holds the keyboard focus.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return NSApp.currentEvent?.type == .scrollWheel ? hit : self
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }

    // Drops are refused here instead of reaching the covered folder.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }

    /// Shows `subject`, after a short pause so that holding an arrow key does not queue previews.
    func show(_ subject: QuickViewSubject) {
        guard subject != shown else { return }
        shown = subject
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            self?.apply(subject)
        }
    }

    private func apply(_ subject: QuickViewSubject) {
        switch subject {
        case .item(let url):
            nameLabel.stringValue = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            note.isHidden = true
            preview?.isHidden = false
            preview?.previewItem = url as NSURL
        case .unavailable:
            nameLabel.stringValue = ""
            note.isHidden = false
            preview?.isHidden = true
            preview?.previewItem = nil
        case .nothing:
            nameLabel.stringValue = ""
            note.isHidden = true
            preview?.previewItem = nil
        }
    }

    /// Stops the preview before the pane goes away.
    func close() {
        pending?.cancel()
        preview?.close()
        removeFromSuperview()
    }
}
