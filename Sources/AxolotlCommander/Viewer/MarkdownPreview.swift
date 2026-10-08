// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import UniformTypeIdentifiers
import WebKit

/// Serves the rendered page and the local files it refers to under `icmd-doc://local/<path>`.
/// Nothing else is reachable: other hosts fail, and internet addresses are blocked by the
/// page's Content Security Policy and a content rule list until the user allows them.
final class MarkdownSchemeHandler: NSObject, WKURLSchemeHandler {
    var page: (url: URL, html: Data)?
    private var stopped: Set<ObjectIdentifier> = []

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return fail(task) }
        var bare = URLComponents(url: url, resolvingAgainstBaseURL: false)
        bare?.fragment = nil
        if let page, bare?.url == page.url {
            return respond(task, url: url, data: page.html, mime: "text/html", encoding: "utf-8")
        }
        guard let file = MarkdownRenderer.fileURL(for: url) else { return fail(task) }
        let id = ObjectIdentifier(task)
        Task {
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return nil }
                return try? Data(contentsOf: file, options: .mappedIfSafe)
            }.value
            guard stopped.remove(id) == nil else { return }
            guard let data else { return fail(task) }
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            respond(task, url: url, data: data, mime: mime, encoding: nil)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        stopped.insert(ObjectIdentifier(task))
    }

    private func respond(_ task: any WKURLSchemeTask, url: URL, data: Data, mime: String, encoding: String?) {
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: encoding))
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: any WKURLSchemeTask) {
        task.didFailWithError(URLError(.fileDoesNotExist))
    }
}

/// Web view whose keys go to the viewer first (Space = next file, Esc = close…).
final class PreviewWebView: WKWebView {
    var onKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// Rendered Markdown, or an HTML file, with a bar offering to load images from the internet.
final class MarkdownPreview: NSView, WKNavigationDelegate {
    private static let blockRuleID = "axolotl.block-remote"
    private static var blockRules: WKContentRuleList?

    let webView: PreviewWebView
    private let handler = MarkdownSchemeHandler()
    private let bar = NSStackView()
    private let barLabel = NSTextField(labelWithString: "")
    private var document: URL?
    /// Opens a local file the user clicked a link to.
    var onOpenFile: ((URL) -> Void)?
    var onAllowRemote: (() -> Void)?
    private(set) var remoteCount = 0
    private(set) var allowsRemote = false

    override init(frame: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(handler, forURLScheme: MarkdownRenderer.scheme)
        configuration.suppressesIncrementalRendering = true
        webView = PreviewWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false

        barLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        barLabel.lineBreakMode = .byTruncatingTail
        barLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let icon = NSImageView(image: NSImage(systemSymbolName: "photo.badge.exclamationmark",
                                              accessibilityDescription: nil) ?? NSImage())
        let load = NSButton(title: CommandRegistry.spec(.viewerLoadRemote).localizedTitle, target: self,
                            action: #selector(allowRemote))
        load.controlSize = .small
        load.bezelStyle = .push
        bar.setViews([icon, barLabel, load], in: .leading)
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        bar.isHidden = true

        let stack = NSStackView(views: [bar, webView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Shows `text` (the decoded file) as a page; `allowRemote` lets it load internet images.
    /// `isHTML`: the text is an HTML page of its own, not Markdown.
    func show(_ text: String, of file: URL, isHTML: Bool = false, allowRemote: Bool) async {
        let page = await Task.detached(priority: .userInitiated) {
            isHTML ? HTMLPreparer.prepare(text, allowRemote: allowRemote)
                   : MarkdownRenderer.render(text, allowRemote: allowRemote)
        }.value
        await setBlocking(!allowRemote)
        document = file
        allowsRemote = allowRemote
        remoteCount = page.remoteResources.count
        let url = MarkdownRenderer.pageURL(for: file)
        handler.page = (url, Data(page.html.utf8))
        webView.load(URLRequest(url: url))
        bar.isHidden = allowRemote || remoteCount == 0
        barLabel.stringValue = isHTML
            ? String(localized: "This page refers to \(remoteCount) file(s) on the internet. They have not been loaded.")
            : String(localized: "This document refers to \(remoteCount) image(s) on the internet. They have not been loaded.")
    }

    func clear() {
        handler.page = nil
        document = nil
        remoteCount = 0
        webView.loadHTMLString("", baseURL: nil)
        bar.isHidden = true
    }

    @objc private func allowRemote() { onAllowRemote?() }

    /// Belt and braces next to the page's policy: a rule list that blocks every http(s) load.
    private func setBlocking(_ block: Bool) async {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        guard block else { return }
        if Self.blockRules == nil {
            let rules = #"[{"trigger":{"url-filter":"^(https?|wss?|ftp)://"},"action":{"type":"block"}}]"#
            Self.blockRules = try? await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: Self.blockRuleID, encodedContentRuleList: rules)
        }
        if let rules = Self.blockRules { controller.add(rules) }
    }

    // MARK: Find, zoom

    func find(_ text: String, backward: Bool, ignoreCase: Bool) async -> Bool {
        let configuration = WKFindConfiguration()
        configuration.backwards = backward
        configuration.caseSensitive = !ignoreCase
        configuration.wraps = true
        return (try? await webView.find(text, configuration: configuration))?.matchFound ?? false
    }

    var zoom: Double {
        get { webView.pageZoom }
        set { webView.pageZoom = min(max(newValue, 0.5), 3) }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        let page = handler.page?.url
        var bare = URLComponents(url: url, resolvingAgainstBaseURL: false)
        bare?.fragment = nil
        if bare?.url == page {
            // The page itself, or a jump to a heading in it.
            return action.navigationType == .other || url.fragment != nil ? .allow : .cancel
        }
        guard action.navigationType == .linkActivated else { return .cancel }
        if let file = MarkdownRenderer.fileURL(for: url) {
            onOpenFile?(file)
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }
}
