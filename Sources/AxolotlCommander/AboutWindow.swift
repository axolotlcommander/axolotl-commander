// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The About window: the standard panel's content (icon, name, version, credits, copyright) plus a
/// "What's New…" link (spec 026). The standard panel cannot run an action from a link.
@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow() -> NSWindow {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleName"] as? String ?? "Axolotl Commander"
        let version = info["CFBundleShortVersionString"] as? String ?? "–"

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.unregisterDraggedTypes()
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 96),
                                     icon.heightAnchor.constraint(equalToConstant: 96)])
        let title = label(name, font: .boldSystemFont(ofSize: 15))
        let versionLabel = label(String(localized: "Version \(version)"), font: .systemFont(ofSize: 11))
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.isSelectable = true

        let whatsNew = NSButton(title: String(localized: "What's New…"), target: Actions.shared,
                                action: #selector(Actions.whatsNew))
        whatsNew.isBordered = false
        whatsNew.attributedTitle = NSAttributedString(string: whatsNew.title, attributes: [
            .foregroundColor: NSColor.linkColor, .font: NSFont.systemFont(ofSize: 11),
        ])
        whatsNew.setAccessibilityIdentifier("about.whatsNew")

        let credits = NSTextView()
        credits.isEditable = false
        credits.isSelectable = true
        credits.drawsBackground = false
        credits.textContainerInset = .zero
        if let url = Bundle.main.url(forResource: "Credits", withExtension: "html"),
           let data = try? Data(contentsOf: url),
           let text = try? NSMutableAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                           .characterEncoding: String.Encoding.utf8.rawValue],
                                                     documentAttributes: nil) {
            // Follow the appearance: HTML gives plain text a fixed black.
            text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: text.length))
            credits.textStorage?.setAttributedString(text)
        }
        credits.translatesAutoresizingMaskIntoConstraints = false
        let width: CGFloat = 300
        credits.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        credits.layoutManager?.ensureLayout(for: credits.textContainer!)
        let height = credits.layoutManager?.usedRect(for: credits.textContainer!).height ?? 0
        NSLayoutConstraint.activate([credits.widthAnchor.constraint(equalToConstant: width),
                                     credits.heightAnchor.constraint(equalToConstant: ceil(height) + 4)])

        let copyright = label(info["NSHumanReadableCopyright"] as? String ?? "", font: .systemFont(ofSize: 10))
        copyright.textColor = .secondaryLabelColor

        let updates = UpdateStatusRow()

        let stack = NSStackView(views: [icon, title, versionLabel, whatsNew, updates, credits, copyright])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(2, after: versionLabel)
        stack.setCustomSpacing(6, after: whatsNew)
        stack.setCustomSpacing(14, after: updates)
        stack.setCustomSpacing(12, after: credits)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        let window = AboutPanelWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        return window
    }

    private static func label(_ text: String, font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.alignment = .center
        return field
    }

    @MainActor
    private final class Actions: NSObject {
        static let shared = Actions()
        @objc func whatsNew() { WhatsNew.show() }
    }
}

/// The last update check in About (FR-014): its result and Check Now, or Install… when a version waits. Opening
/// About sends no request; only the button does.
private final class UpdateStatusRow: NSStackView {
    private let status = NSTextField(labelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)
    private var observer: (any NSObjectProtocol)?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .centerX
        spacing = 4
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        button.bezelStyle = .push
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.target = self
        button.action = #selector(act)
        button.setAccessibilityIdentifier("about.updates")
        addArrangedSubview(status)
        addArrangedSubview(button)
        observer = NotificationCenter.default.addObserver(forName: UpdateController.stateChanged, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var available: Bool { UpdateController.shared.state.lastResult == .available }

    private func refresh() {
        status.stringValue = UpdateController.shared.statusText()
        button.title = available ? String(localized: "Install…") : String(localized: "Check Now")
    }

    @objc private func act() {
        if available { UpdateController.shared.showFound() } else { UpdateController.shared.checkNow() }
    }
}

/// Esc and ⌘W close the About window.
private final class AboutPanelWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
