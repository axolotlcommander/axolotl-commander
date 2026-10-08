// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Compare window settings kept in UserDefaults.
enum CompareDefaults {
    static let whitespaceKey = "compare.whitespace"
    static let ignoreCaseKey = "compare.ignoreCase"
    static let differencesOnlyKey = "compare.differencesOnly"
    static let fontSizeKey = "compare.fontSize"

    static var options: DiffOptions {
        let defaults = UserDefaults.standard
        let whitespace = defaults.string(forKey: whitespaceKey).flatMap(DiffOptions.Whitespace.init(rawValue:)) ?? .compare
        return DiffOptions(whitespace: whitespace, ignoreCase: defaults.bool(forKey: ignoreCaseKey))
    }
    static var differencesOnly: Bool { UserDefaults.standard.bool(forKey: differencesOnlyKey) }
    static var fontSize: Double {
        let size = UserDefaults.standard.double(forKey: fontSizeKey)
        let fonts = ViewerDefaults.fontSizes
        return size == 0 ? ViewerDefaults.fontSize : min(max(size, fonts.lowerBound), fonts.upperBound)
    }
}

/// Centered message in place of the diff (comparing, identical, binary, error). Takes keys so Esc still works.
final class CompareMessageView: NSView {
    var onKey: ((NSEvent) -> Bool)?
    let titleField = NSTextField(labelWithString: "")
    let detailField = NSTextField(wrappingLabelWithString: "")

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        titleField.font = .systemFont(ofSize: 15, weight: .medium)
        titleField.alignment = .center
        detailField.font = .systemFont(ofSize: NSFont.systemFontSize)
        detailField.textColor = .secondaryLabelColor
        detailField.alignment = .center
        detailField.isSelectable = true
        let stack = NSStackView(views: [titleField, detailField])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ title: String, detail: String = "") {
        titleField.stringValue = title
        detailField.stringValue = detail
        detailField.isHidden = detail.isEmpty
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
}

/// Thin notice above the diff.
final class BannerView: NSView {
    init(_ text: String) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        dirtyRect.fill()
    }
}

/// Compare Files: two files side by side with their line differences.
final class CompareWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private static var open: [CompareWindowController] = []

    static func show(left: URL, right: URL, leftTitle: String, rightTitle: String) {
        let controller = CompareWindowController(left: File(url: left, title: leftTitle),
                                                 right: File(url: right, title: rightTitle))
        open.append(controller)
        controller.showWindow(nil)
        controller.compare(anchor: nil)
    }

    private struct File {
        var url: URL
        /// Original display path (may be a server URL or an archive path).
        var title: String
    }

    /// Comparison result read off the main actor.
    private nonisolated struct Prepared: Sendable {
        var result: FileComparison.Result
        var columns = 0
        var leftSize: Int64 = 0

        init(left: URL, right: URL, options: DiffOptions, fallback: TextEncoding, textLimit: Int) throws {
            result = try FileComparison.compare(left, right, options: options, fallback: fallback, textLimit: textLimit)
            if case .text(_, let leftLines, let rightLines, _, _) = result {
                for lines in [leftLines, rightLines] {
                    for (index, line) in lines.enumerated() {
                        if index & 0xFFF == 0 { try Task.checkCancellation() }
                        columns = max(columns, TabStops.columns(of: line))
                    }
                }
            }
            leftSize = (try? left.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
    }

    private var left: File
    private var right: File
    private var options = CompareDefaults.options
    private var differencesOnly = CompareDefaults.differencesOnly
    private var fontSize = CompareDefaults.fontSize
    private var compareTask: Task<Prepared, any Error>?
    /// Bumped with every comparison; stale results are dropped.
    private var generation = 0
    private var comparing = false
    private var showsDiff = false

    private let diffArea = NSStackView()
    private let banner = BannerView(String(localized: "No differences (with the current options)."))
    private let titleFields = [NSTextField(labelWithString: ""), NSTextField(labelWithString: "")]
    private let encodingFields = [NSTextField(labelWithString: ""), NSTextField(labelWithString: "")]
    private let scrollView = NSScrollView()
    private let diffView = DiffView()
    private let overview = DiffOverview()
    private let messageView = CompareMessageView()
    private let differencesField = NSTextField(labelWithString: "")
    private let currentField = NSTextField(labelWithString: "")
    private let optionsField = NSTextField(labelWithString: "")
    private let linesField = NSTextField(labelWithString: "")
    private static let overviewWidth: CGFloat = 14

    private init(left: File, right: File) {
        self.left = left
        self.right = right
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.minSize = NSSize(width: 560, height: 300)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        if let last = Self.open.last?.window {
            window.setFrame(last.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else if !window.setFrameUsingName("Compare") {
            window.center()
        }
        window.setFrameAutosaveName("Compare")
        updateTitles()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildContent(in window: NSWindow) {
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        banner.isHidden = true

        var columns = [NSView]()
        for (title, encoding) in zip(titleFields, encodingFields) {
            title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            title.lineBreakMode = .byTruncatingMiddle
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            title.setContentHuggingPriority(.defaultLow, for: .horizontal)
            encoding.font = small
            encoding.textColor = .secondaryLabelColor
            encoding.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            encoding.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            let column = NSStackView(views: [title, encoding])
            column.distribution = .fill
            column.spacing = 8
            column.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
            columns.append(column)
        }
        let spacer = NSView()
        let header = NSStackView(views: columns + [spacer])
        header.distribution = .fill
        header.spacing = 1
        columns[0].widthAnchor.constraint(equalTo: columns[1].widthAnchor).isActive = true
        spacer.widthAnchor.constraint(equalToConstant: Self.overviewWidth).isActive = true
        let headerSeparator = NSBox()
        headerSeparator.boxType = .separator

        diffView.onKey = { [weak self] in self?.handleKey($0) ?? false }
        diffView.onStateChange = { [weak self] in
            self?.overview.needsDisplay = true
            self?.updateStatus()
        }
        diffView.onScroll = { [weak self] in self?.overview.needsDisplay = true }
        diffView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        diffView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        scrollView.documentView = diffView
        scrollView.borderType = .noBorder
        // The overview strip is the vertical scroller; the halves stay aligned with the header.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .textBackgroundColor
        overview.diffView = diffView
        overview.widthAnchor.constraint(equalToConstant: Self.overviewWidth).isActive = true
        let body = NSStackView(views: [scrollView, overview])
        body.spacing = 0
        body.alignment = .height
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)

        diffArea.setViews([banner, header, headerSeparator, body], in: .top)
        diffArea.orientation = .vertical
        diffArea.distribution = .fill
        diffArea.spacing = 0
        diffArea.alignment = .leading
        for view in diffArea.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: diffArea.widthAnchor).isActive = true
        }
        body.setContentHuggingPriority(.init(1), for: .vertical)
        body.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        diffArea.isHidden = true

        messageView.onKey = { [weak self] in self?.handleKey($0) ?? false }
        let content = NSView()
        for view in [diffArea, messageView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                view.topAnchor.constraint(equalTo: content.topAnchor),
                view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }

        for field in [differencesField, currentField, optionsField, linesField] {
            field.font = small
            field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byTruncatingTail
        }
        optionsField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        optionsField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let status = NSStackView(views: [differencesField, currentField, optionsField, linesField])
        status.spacing = 14
        status.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 5, right: 12)
        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(views: [content, separator, status])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        content.setContentHuggingPriority(.defaultLow, for: .vertical)
        content.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        window.contentView = stack
    }

    private func updateTitles() {
        let (leftName, leftFolder) = Self.split(left.title), (rightName, rightFolder) = Self.split(right.title)
        window?.title = "\(leftName) ↔ \(rightName)"
        window?.subtitle = leftFolder == rightFolder ? leftFolder : "\(leftFolder) ↔ \(rightFolder)"
        for (field, file) in zip(titleFields, [left, right]) {
            field.stringValue = file.title
            field.toolTip = file.title
        }
    }

    /// Name and folder of a display path; plain string splitting keeps `scheme://` intact.
    private static func split(_ path: String) -> (name: String, folder: String) {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let slash = trimmed.lastIndex(of: "/") else { return (String(trimmed), "") }
        let name = trimmed[trimmed.index(after: slash)...]
        let folder = slash == trimmed.startIndex ? "/" : String(trimmed[..<slash])
        return (name.isEmpty ? String(trimmed) : String(name), folder)
    }

    // MARK: Comparing

    private func compare(anchor: DiffView.Anchor?) {
        compareTask?.cancel()
        generation += 1
        let current = generation
        let (leftURL, rightURL, options) = (left.url, right.url, options)
        let (fallback, limit) = (ViewerDefaults.encoding, ViewerDefaults.textLimit)
        let task = Task.detached(priority: .userInitiated) {
            try Prepared(left: leftURL, right: rightURL, options: options, fallback: fallback, textLimit: limit)
        }
        compareTask = task
        comparing = true
        if !showsDiff { showMessage(String(localized: "Comparing…")) }
        updateStatus()
        Task { [weak self] in
            let outcome = await task.result
            guard let self, current == self.generation else { return }
            self.comparing = false
            self.compareTask = nil
            switch outcome {
            case .success(let prepared): self.apply(prepared, anchor: anchor)
            case .failure(let error):
                if error is CancellationError { return }
                self.showMessage(String(localized: "The files could not be compared."), detail: Format.error(error))
            }
            self.updateStatus()
        }
    }

    private func apply(_ prepared: Prepared, anchor: DiffView.Anchor?) {
        switch prepared.result {
        case .identical:
            let size = prepared.leftSize
            showMessage(String(localized: "The files are identical."),
                        detail: String(localized: "Size: \(Format.bytes(size)) (\(Format.grouped(size)) bytes)"))
        case .binaryDifferent(let offset, let leftSize, let rightSize):
            let hex = HexFormat.offsetText(offset, fileSize: max(leftSize, rightSize))
            let detail = String(localized: "First difference at offset \(hex) (\(Format.grouped(offset)))") + "\n"
                + String(localized: "Left: \(Format.bytes(leftSize)) (\(Format.grouped(leftSize)) bytes)") + "\n"
                + String(localized: "Right: \(Format.bytes(rightSize)) (\(Format.grouped(rightSize)) bytes)")
            showMessage(String(localized: "The files are different."), detail: detail)
        case .text(let diff, let leftLines, let rightLines, let leftEncoding, let rightEncoding):
            encodingFields[0].stringValue = leftEncoding.title
            encodingFields[1].stringValue = rightEncoding.title
            banner.isHidden = !diff.isIdentical
            let wasFocused = window?.firstResponder === diffView
            showsDiff = true
            diffArea.isHidden = false
            messageView.isHidden = true
            window?.layoutIfNeeded()
            diffView.setContent(.init(diff: diff, left: leftLines, right: rightLines, options: options,
                                      columns: prepared.columns),
                                differencesOnly: differencesOnly, anchor: anchor)
            if !wasFocused { window?.makeFirstResponder(diffView) }
        }
    }

    private func showMessage(_ title: String, detail: String = "") {
        showsDiff = false
        diffView.setContent(nil, differencesOnly: differencesOnly, anchor: nil)
        diffArea.isHidden = true
        messageView.isHidden = false
        messageView.show(title, detail: detail)
        window?.makeFirstResponder(messageView)
    }

    private func updateStatus() {
        var differences = "", current = "", lines = ""
        if comparing {
            differences = String(localized: "Comparing…")
        }
        if showsDiff, let content = diffView.content {
            let count = content.diff.blocks.count
            if !comparing {
                differences = count == 0 ? String(localized: "No differences") : String(localized: "\(count) differences")
            }
            if let block = diffView.currentBlock { current = String(localized: "Difference \(block + 1) of \(count)") }
            lines = String(localized: "Left: \(content.left.count) lines, right: \(content.right.count) lines")
        }
        var parts = [String]()
        switch options.whitespace {
        case .compare: break
        case .ignoreChanges: parts.append(String(localized: "Ignoring whitespace changes"))
        case .ignoreAll: parts.append(String(localized: "Ignoring all whitespace"))
        }
        if options.ignoreCase { parts.append(String(localized: "Ignoring case")) }
        if differencesOnly { parts.append(String(localized: "Differences only")) }
        differencesField.stringValue = differences
        currentField.stringValue = current
        optionsField.stringValue = parts.joined(separator: " · ")
        linesField.stringValue = lines
    }

    // MARK: Commands

    @objc func performCommand(_ sender: Any?) {
        guard let command = (sender as? NSMenuItem)?.command else { return }
        perform(command)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord(event: event),
              let command = KeyMaps.compare.command(for: chord), CommandRegistry.spec(command).scope == .compare,
              !KeyMaps.menuHandles(chord, for: command, in: .compare) else { return false }
        perform(command)
        return true
    }

    func perform(_ command: Command) {
        switch command {
        case .compareNextDifference: move(.next)
        case .comparePreviousDifference: move(.previous)
        case .compareFirstDifference: move(.first)
        case .compareLastDifference: move(.last)
        case .compareDifferencesOnly:
            differencesOnly.toggle()
            UserDefaults.standard.set(differencesOnly, forKey: CompareDefaults.differencesOnlyKey)
            diffView.setDifferencesOnly(differencesOnly)
            updateStatus()
        case .compareIgnoreWhitespace: toggleWhitespace(.ignoreChanges)
        case .compareIgnoreAllWhitespace: toggleWhitespace(.ignoreAll)
        case .compareIgnoreCase:
            options.ignoreCase.toggle()
            UserDefaults.standard.set(options.ignoreCase, forKey: CompareDefaults.ignoreCaseKey)
            compare(anchor: diffView.topAnchor())
        case .compareSwap:
            swap(&left, &right)
            updateTitles()
            compare(anchor: diffView.topAnchor()?.swapped)
        case .compareReload: compare(anchor: diffView.topAnchor())
        case .compareCopy: if showsDiff { diffView.copy(nil) }
        case .compareZoomIn: zoom(to: fontSize + 1)
        case .compareZoomOut: zoom(to: fontSize - 1)
        case .compareActualSize: zoom(to: ViewerDefaults.defaultFontSize)
        case .compareClose: window?.close()
        default:
            if CommandRegistry.spec(command).scope == .app { (NSApp.delegate as? AppDelegate)?.perform(command) }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.command else { return true }
        switch command {
        case .compareNextDifference, .comparePreviousDifference, .compareFirstDifference, .compareLastDifference:
            return showsDiff && diffView.blockCount > 0
        case .compareDifferencesOnly: menuItem.state = differencesOnly ? .on : .off
        case .compareIgnoreWhitespace: menuItem.state = options.whitespace == .ignoreChanges ? .on : .off
        case .compareIgnoreAllWhitespace: menuItem.state = options.whitespace == .ignoreAll ? .on : .off
        case .compareIgnoreCase: menuItem.state = options.ignoreCase ? .on : .off
        case .compareCopy: return showsDiff && diffView.hasSelection
        case .compareZoomIn: return fontSize < ViewerDefaults.fontSizes.upperBound
        case .compareZoomOut: return fontSize > ViewerDefaults.fontSizes.lowerBound
        case .compareActualSize: return fontSize != ViewerDefaults.defaultFontSize
        default:
            if CommandRegistry.spec(command).scope == .app {
                return (NSApp.delegate as? AppDelegate)?.canPerform(command) ?? false
            }
        }
        return true
    }

    private func move(_ step: DiffView.Step) {
        if !(showsDiff && diffView.move(step)) { NSSound.beep() }
    }

    /// The two whitespace modes exclude each other; choosing the active one compares whitespace again.
    private func toggleWhitespace(_ mode: DiffOptions.Whitespace) {
        options.whitespace = options.whitespace == mode ? .compare : mode
        UserDefaults.standard.set(options.whitespace.rawValue, forKey: CompareDefaults.whitespaceKey)
        compare(anchor: diffView.topAnchor())
    }

    private func zoom(to size: Double) {
        fontSize = min(max(size, ViewerDefaults.fontSizes.lowerBound), ViewerDefaults.fontSizes.upperBound)
        UserDefaults.standard.set(fontSize, forKey: CompareDefaults.fontSizeKey)
        diffView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        compareTask?.cancel()
        compareTask = nil
        generation += 1
        Self.open.removeAll { $0 === self }
    }
}
