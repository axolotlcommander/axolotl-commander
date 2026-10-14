// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import WebKit

/// The release notes from the changelog bundled into the app (spec 026): once after an update, and from
/// Help → What's New…, the About window and Settings. Nothing is loaded from the internet.
@MainActor
enum WhatsNew {
    private static var controller: WhatsNewWindowController?

    /// The changelog inside the app bundle; nil for a development build run without a bundle.
    static var bundledNotes: [ReleaseNote]? {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return ReleaseNotes.parse(text)
    }

    static var runningVersion: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    /// Every version of the bundled changelog.
    static func show() {
        show(bundledNotes ?? [])
    }

    static func show(_ notes: [ReleaseNote]) {
        let controller = controller ?? WhatsNewWindowController()
        self.controller = controller
        controller.show(notes)
    }

    /// At a start: remembers the running version and, after an update, shows the versions that came since the
    /// one that ran before (FR-001 – FR-003). The setting is written first, so a second copy shows nothing.
    static func showAfterStart(_ defaults: UserDefaults = .standard) {
        guard let running = runningVersion else { return }
        let decision = WhatsNewStart.decide(lastRun: defaults.string(forKey: WhatsNewStart.lastRunKey),
                                            running: running, notes: bundledNotes ?? [])
        defaults.set(decision.remember, forKey: WhatsNewStart.lastRunKey)
        guard !decision.show.isEmpty else { return }
        showWhenFree(decision.show, attempts: 120)
    }

    /// Waits while a dialog or a sheet is up, so the window does not take the focus from it.
    private static func showWhenFree(_ notes: [ReleaseNote], attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let busy = NSApp.modalWindow != nil || NSApp.windows.contains { $0.attachedSheet != nil }
            if busy, attempts > 0 { showWhenFree(notes, attempts: attempts - 1) } else { show(notes) }
        }
    }
}

final class WhatsNewWindowController: NSWindowController, WKNavigationDelegate {
    private let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        let window = WhatsNewPanelWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                         backing: .buffered, defer: false)
        window.title = String(localized: "What's New in Axolotl Commander")
        window.minSize = NSSize(width: 360, height: 260)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false

        let close = NSButton(title: String(localized: "Close"), target: window, action: #selector(NSWindow.performClose(_:)))
        close.keyEquivalent = "\r"
        let content = NSView()
        for view in [webView, close] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        window.contentView = content
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            close.topAnchor.constraint(equalTo: webView.bottomAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            close.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        window.center()
        window.setFrameAutosaveName("WhatsNewWindow")
        window.webView = webView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ notes: [ReleaseNote]) {
        let markdown = notes.isEmpty
            ? String(localized: "No release notes are available.") : ReleaseNotes.markdown(notes)
        webView.loadHTMLString(MarkdownRenderer.render(markdown).html, baseURL: nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        // The page itself and jumps inside it; a link goes to the browser, nothing loads here.
        if action.navigationType == .other || (url.scheme == "about" && url.fragment != nil) { return .allow }
        if action.navigationType == .linkActivated, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }
}

/// Esc and ⌘W close the window; ⌘C and ⌘A work on the notes (the menu's keys belong to the panels).
private final class WhatsNewPanelWindow: NSWindow {
    weak var webView: WKWebView?

    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "w": performClose(nil)
        case "c": NSApp.sendAction(#selector(NSText.copy(_:)), to: webView, from: self)
        case "a": NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: webView, from: self)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
