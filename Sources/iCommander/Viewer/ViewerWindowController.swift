import AppKit
import CommanderCore
import UniformTypeIdentifiers

/// Viewer settings kept in UserDefaults (shared with Settings → Viewer & Editor).
enum ViewerDefaults {
    static let encodingKey = "viewer.encoding"
    static let wrapKey = "viewer.wrap"
    static let fontSizeKey = "viewer.fontSize"
    static let defaultFontSize: Double = 12
    static let fontSizes: ClosedRange<Double> = 8...36
    /// Text mode decodes at most this much; hex mode always shows the whole file.
    static let textLimit = 64 << 20

    /// Encoding for text that has no BOM and is not UTF-8: Central European for
    /// Czech and its neighbours (Windows-1250 as in the Windows version), Western otherwise.
    static var fallbackEncoding: TextEncoding {
        let language = Locale.current.language.languageCode?.identifier ?? ""
        return ["cs", "sk", "pl", "hu", "sl", "hr", "ro"].contains(language) ? .windows1250 : .windows1252
    }
    static var encoding: TextEncoding {
        UserDefaults.standard.string(forKey: encodingKey).flatMap(TextEncoding.init(rawValue:)) ?? fallbackEncoding
    }
    static var wrap: Bool { UserDefaults.standard.object(forKey: wrapKey) as? Bool ?? true }
    static var fontSize: Double {
        let size = UserDefaults.standard.double(forKey: fontSizeKey)
        return size == 0 ? defaultFontSize : min(max(size, fontSizes.lowerBound), fontSizes.upperBound)
    }

    /// Types F3 hands to Quick Look until the type viewers of stage 10 exist.
    static func prefersQuickLook(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return [UTType.image, .pdf, .audiovisualContent, .font].contains { type.conforms(to: $0) }
    }
}

/// Text view of the viewer: viewer keys (Space, ⌫, Esc…) first, then normal selection keys.
final class ViewerTextView: NSTextView {
    var onKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// The F3 viewer: one window per file, text or hex, with the panel's other files a key away.
final class ViewerWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private static var open: [ViewerWindowController] = []

    static func show(_ sequence: FileSequence) {
        let controller = ViewerWindowController(sequence: sequence)
        open.append(controller)
        controller.showWindow(nil)
        controller.load()
    }

    enum Mode { case text, hex }

    /// File contents read off the main actor.
    private nonisolated struct Loaded: Sendable {
        var data = Data()
        var isBinary = false
        var detection: EncodingDetection?
        var error: String?

        init(url: URL, fallback: TextEncoding) {
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
                isBinary = EncodingDetector.looksBinary(data)
                detection = EncodingDetector.detect(data, fallback: fallback)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private var sequence: FileSequence
    private var data = Data()
    private var isBinary = false
    private var detection: EncodingDetection?
    private var encodingOverride: TextEncoding?
    private var modeOverride: Mode?
    private var mode: Mode = .text
    private var loadError: String?
    /// Encoding the text view currently shows; nil = not decoded yet.
    private var decodedAs: TextEncoding?
    private var truncated = false
    private var wrap = ViewerDefaults.wrap
    private var fontSize = ViewerDefaults.fontSize
    private var loadTask: Task<Void, Never>?
    private var decodeTask: Task<Void, Never>?
    private var findTask: Task<Void, Never>?

    private let textScroll = NSScrollView()
    private let textView = ViewerTextView(usingTextLayoutManager: true)
    private let hexScroll = NSScrollView()
    private let hexView = HexView()
    private let findBar = HexFindBar()
    private let modeControl = NSSegmentedControl(labels: [String(localized: "Text"), String(localized: "Hex")],
                                                 trackingMode: .selectOne, target: nil, action: nil)
    private let encodingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let wrapBox = NSButton(checkboxWithTitle: String(localized: "Wrap Lines"), target: nil, action: nil)
    private let infoField = NSTextField(labelWithString: "")
    private let positionField = NSTextField(labelWithString: "")

    private var encoding: TextEncoding { encodingOverride ?? detection?.encoding ?? ViewerDefaults.encoding }
    private var font: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }

    init(sequence: FileSequence) {
        self.sequence = sequence
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.minSize = NSSize(width: 520, height: 280)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        if let last = Self.open.last?.window {
            window.setFrame(last.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else if !window.setFrameUsingName("Viewer") {
            window.center()
        }
        window.setFrameAutosaveName("Viewer")
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildContent(in window: NSWindow) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.onKey = { [weak self] in self?.handleKey($0) ?? false }
        textScroll.documentView = textView
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.findBarPosition = .aboveContent

        hexView.onKey = { [weak self] in self?.handleKey($0) ?? false }
        hexView.onSelectionChange = { [weak self] in self?.updateInfo() }
        hexScroll.documentView = hexView
        hexScroll.hasVerticalScroller = true
        hexScroll.hasHorizontalScroller = true
        hexScroll.autohidesScrollers = true
        hexScroll.backgroundColor = .textBackgroundColor

        findBar.isHidden = true
        findBar.onFind = { [weak self] in self?.findInHex(backward: $0) }
        findBar.onClose = { [weak self] in self?.closeFindBar() }

        let lists = NSView()
        for scroll in [textScroll, hexScroll] {
            scroll.borderType = .noBorder
            scroll.translatesAutoresizingMaskIntoConstraints = false
            lists.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: lists.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: lists.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: lists.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: lists.bottomAnchor),
            ])
        }

        modeControl.controlSize = .small
        modeControl.target = self
        modeControl.action = #selector(modeControlChanged)
        encodingPopup.controlSize = .small
        encodingPopup.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for (index, encoding) in TextEncoding.allCases.enumerated() {
            encodingPopup.addItem(withTitle: encoding.title)
            encodingPopup.lastItem?.tag = index
        }
        encodingPopup.menu?.addItem(.separator())
        encodingPopup.addItem(withTitle: CommandRegistry.spec(.viewerAutoEncoding).localizedTitle)
        encodingPopup.lastItem?.tag = -1
        encodingPopup.target = self
        encodingPopup.action = #selector(encodingPopupChanged)
        wrapBox.controlSize = .small
        wrapBox.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        wrapBox.target = self
        wrapBox.action = #selector(wrapBoxChanged)
        for field in [infoField, positionField] {
            field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byTruncatingTail
        }
        infoField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        infoField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let status = NSStackView(views: [modeControl, encodingPopup, wrapBox, infoField, positionField])
        status.spacing = 10
        status.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 5, right: 12)
        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(views: [findBar, lists, separator, status])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        lists.setContentHuggingPriority(.defaultLow, for: .vertical)
        lists.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        window.contentView = stack
        applyWrap()
        applyFont()
    }

    // MARK: Loading

    private func load(keepingPosition: Bool = false) {
        loadTask?.cancel()
        decodeTask?.cancel()
        findTask?.cancel()
        let url = sequence.current
        let position = keepingPosition ? positionFraction() : 0
        window?.title = url.lastPathComponent
        window?.subtitle = url.deletingLastPathComponent().displayPath
        window?.representedURL = url
        positionField.stringValue = sequence.entries.count > 1 ? "\(sequence.index + 1) / \(sequence.entries.count)" : ""
        infoField.stringValue = String(localized: "Loading…")
        let fallback = ViewerDefaults.encoding
        loadTask = Task {
            let loaded = await Task.detached(priority: .userInitiated) { Loaded(url: url, fallback: fallback) }.value
            guard !Task.isCancelled, url == sequence.current else { return }
            data = loaded.data
            isBinary = loaded.isBinary
            detection = loaded.detection
            loadError = loaded.error
            decodedAs = nil
            hexView.data = data
            hexView.encoding = encoding
            mode = loadError != nil ? .text : modeOverride ?? (isBinary ? .hex : .text)
            show(at: position)
        }
    }

    /// Shows the current mode; `position` is the fraction of the file to scroll to.
    private func show(at position: Double) {
        textScroll.isHidden = mode != .text
        hexScroll.isHidden = mode != .hex
        if mode == .text { findBar.isHidden = true }
        modeControl.selectedSegment = mode == .text ? 0 : 1
        updateStatus()
        switch mode {
        case .hex:
            hexView.scrollToTop(offset: Int(position * Double(data.count)))
            window?.makeFirstResponder(hexView)
        case .text:
            window?.makeFirstResponder(textView)
            if let loadError {
                setText(String(localized: "The file could not be read.") + "\n\n" + loadError)
                return
            }
            if decodedAs == encoding {
                scrollText(to: position)
                return
            }
            decode(restoring: .fraction(position))
        }
    }

    /// Where to put the text after decoding: a fraction of the text, or the same scroll origin.
    private enum Restore { case fraction(Double), origin(NSPoint) }

    private func decode(restoring restore: Restore) {
        decodeTask?.cancel()
        let data = data, encoding = encoding, limit = ViewerDefaults.textLimit
        let bom = EncodingDetector.bom(in: data)
        let skip = bom?.encoding == encoding ? bom?.length ?? 0 : 0
        truncated = data.count - skip > limit
        decodeTask = Task {
            let text = await Task.detached(priority: .userInitiated) {
                TextDecoding.decode(data, as: encoding, skip: skip, limit: limit)
            }.value
            guard !Task.isCancelled else { return }
            setText(text)
            decodedAs = encoding
            switch restore {
            case .fraction(let position): scrollText(to: position)
            case .origin(let origin): textView.scroll(origin)
            }
            updateStatus()
        }
    }

    private func setText(_ text: String) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.textColor,
        ]))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    // MARK: Position

    /// Where the view is, as a fraction of the file (text: characters, hex: bytes).
    private func positionFraction() -> Double {
        switch mode {
        case .hex:
            return data.isEmpty ? 0 : Double(hexView.topOffset) / Double(data.count)
        case .text:
            let length = textView.string.utf16.count
            guard length > 0 else { return 0 }
            let index = textView.characterIndexForInsertion(at: NSPoint(x: textView.visibleRect.minX + 4,
                                                                         y: textView.visibleRect.minY + 4))
            return Double(min(index, length)) / Double(length)
        }
    }

    private func scrollText(to position: Double) {
        let length = textView.string.utf16.count
        scrollText(toCharacter: Int(position * Double(length)))
    }

    /// Scrolls so the line holding `index` (UTF-16 offset) is at the top.
    private func scrollText(toCharacter index: Int) {
        guard index > 0 else { textView.scroll(.zero); return }
        guard let layout = textView.textLayoutManager, let content = layout.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: index) else { return }
        layout.ensureLayout(for: NSTextRange(location: location))
        if let fragment = layout.textLayoutFragment(for: location) {
            textView.scroll(NSPoint(x: 0, y: fragment.layoutFragmentFrame.minY))
        }
    }

    // MARK: Status

    private func updateStatus() {
        encodingPopup.selectItem(withTag: TextEncoding.allCases.firstIndex(of: encoding) ?? 0)
        encodingPopup.lastItem?.state = encodingOverride == nil ? .on : .off
        wrapBox.state = wrap ? .on : .off
        wrapBox.isEnabled = mode == .text
        updateInfo()
    }

    private func updateInfo() {
        var parts = [Format.grouped(Int64(data.count)) + " B"]
        if let source = sourceText { parts.append(source) }
        if mode == .text, truncated {
            parts.append(String(localized: "text shows the first \(Format.bytes(Int64(ViewerDefaults.textLimit))), Hex shows all"))
        }
        if mode == .hex, !data.isEmpty {
            let range = hexView.selection
            let offset = HexFormat.offsetText(Int64(range.lowerBound), fileSize: Int64(data.count))
            parts.append(String(localized: "offset \(offset) (\(Format.grouped(Int64(range.lowerBound))))"))
            if hexView.hasSelection { parts.append(String(localized: "\(Format.grouped(Int64(range.count))) B selected")) }
        }
        infoField.stringValue = parts.joined(separator: " · ")
    }

    private var sourceText: String? {
        if encodingOverride != nil { return String(localized: "encoding chosen manually") }
        switch detection?.source {
        case .bom?: return String(localized: "byte order mark")
        case .validUTF8?: return String(localized: "valid UTF-8")
        case .utf16Heuristic?, .legacyHeuristic?: return String(localized: "encoding detected")
        case .fallback?: return String(localized: "default encoding")
        case .manual?: return String(localized: "encoding chosen manually")
        case nil: return nil
        }
    }

    // MARK: Commands

    @objc func performCommand(_ sender: Any?) {
        guard let command = (sender as? NSMenuItem)?.command else { return }
        perform(command)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord(event: event), !chord.isMenuSafe,
              let command = KeyMap.viewer.command(for: chord), CommandRegistry.spec(command).scope == .viewer else { return false }
        perform(command)
        return true
    }

    func perform(_ command: Command) {
        switch command {
        case .viewerNextFile: step(.next)
        case .viewerPreviousFile: step(.previous)
        case .viewerNextSelected: step(.nextSelected)
        case .viewerPreviousSelected: step(.previousSelected)
        case .viewerFirstFile: step(.first)
        case .viewerLastFile: step(.last)
        case .viewerSaveAs: Task { await saveCopy() }
        case .viewerClose: window?.close()
        case .viewerFind: find(.showFindInterface)
        case .viewerFindNext: find(.nextMatch)
        case .viewerFindPrevious: find(.previousMatch)
        case .viewerUseSelectionForFind: find(.setSearchString)
        case .viewerGoTo: Task { await goTo() }
        case .viewerText: setMode(.text)
        case .viewerHex: setMode(.hex)
        case .viewerWrap:
            wrap.toggle()
            UserDefaults.standard.set(wrap, forKey: ViewerDefaults.wrapKey)
            applyWrap()
            updateStatus()
        case .viewerAutoEncoding: setEncoding(nil)
        case .viewerNextEncoding: cycleEncoding(by: 1)
        case .viewerPreviousEncoding: cycleEncoding(by: -1)
        case .viewerSetDefaultEncoding: UserDefaults.standard.set(encoding.rawValue, forKey: ViewerDefaults.encodingKey)
        case .viewerZoomIn: zoom(to: fontSize + 1)
        case .viewerZoomOut: zoom(to: fontSize - 1)
        case .viewerActualSize: zoom(to: ViewerDefaults.defaultFontSize)
        case .viewerReload: load(keepingPosition: true)
        default:
            if CommandRegistry.spec(command).scope == .app { (NSApp.delegate as? AppDelegate)?.perform(command) }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectEncoding(_:)) {
            menuItem.state = TextEncoding.allCases[menuItem.tag] == encoding ? .on : .off
            return true
        }
        guard let command = menuItem.command else { return true }
        let several = sequence.entries.count > 1
        switch command {
        case .viewerText: menuItem.state = mode == .text ? .on : .off
        case .viewerHex: menuItem.state = mode == .hex ? .on : .off
        case .viewerWrap:
            menuItem.state = wrap ? .on : .off
            return mode == .text
        case .viewerAutoEncoding: menuItem.state = encodingOverride == nil ? .on : .off
        case .viewerGoTo:
            menuItem.title = mode == .text ? String(localized: "Go to Line…") : String(localized: "Go to Offset…")
            return loadError == nil
        case .viewerNextFile, .viewerPreviousFile, .viewerFirstFile, .viewerLastFile: return several
        case .viewerNextSelected, .viewerPreviousSelected: return several && sequence.entries.contains(where: \.isSelected)
        case .viewerZoomIn: return fontSize < ViewerDefaults.fontSizes.upperBound
        case .viewerZoomOut: return fontSize > ViewerDefaults.fontSizes.lowerBound
        case .viewerSaveAs: return loadError == nil
        default:
            if CommandRegistry.spec(command).scope == .app {
                return (NSApp.delegate as? AppDelegate)?.canPerform(command) ?? false
            }
        }
        return true
    }

    private func step(_ step: FileSequence.Step) {
        guard sequence.move(step) != nil else { NSSound.beep(); return }
        // Another file opens fresh: automatic mode and encoding again.
        encodingOverride = nil
        modeOverride = nil
        textView.textStorage?.setAttributedString(NSAttributedString())
        load()
    }

    private func setMode(_ newMode: Mode) {
        guard loadError == nil else { return }
        modeOverride = newMode
        guard newMode != mode else { return }
        let position = positionFraction()
        mode = newMode
        show(at: position)
    }

    @objc private func modeControlChanged() { setMode(modeControl.selectedSegment == 0 ? .text : .hex) }
    @objc private func wrapBoxChanged() { perform(.viewerWrap) }

    @objc func selectEncoding(_ sender: NSMenuItem) { setEncoding(TextEncoding.allCases[sender.tag]) }

    @objc private func encodingPopupChanged() {
        let tag = encodingPopup.selectedTag()
        setEncoding(tag < 0 ? nil : TextEncoding.allCases[tag])
    }

    private func cycleEncoding(by delta: Int) {
        let all = TextEncoding.allCases
        let index = all.firstIndex(of: encoding) ?? 0
        setEncoding(all[(index + delta + all.count) % all.count])
    }

    /// Re-decodes the same bytes; the file on disk is never touched.
    private func setEncoding(_ newEncoding: TextEncoding?) {
        encodingOverride = newEncoding
        hexView.encoding = encoding
        if mode == .text, loadError == nil, decodedAs != encoding {
            decode(restoring: .origin(textScroll.contentView.bounds.origin))
        }
        updateStatus()
    }

    private func applyWrap() {
        textView.isHorizontallyResizable = !wrap
        textScroll.hasHorizontalScroller = !wrap
        textView.autoresizingMask = wrap ? [.width] : []
        textView.textContainer?.widthTracksTextView = wrap
        let big = CGFloat.greatestFiniteMagnitude
        if wrap {
            let width = textScroll.contentSize.width
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
            textView.textContainer?.containerSize = NSSize(width: width, height: big)
        } else {
            textView.textContainer?.containerSize = NSSize(width: big, height: big)
        }
    }

    private func applyFont() {
        let font = font
        textView.font = font
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))
        }
        hexView.font = font
    }

    private func zoom(to size: Double) {
        fontSize = min(max(size, ViewerDefaults.fontSizes.lowerBound), ViewerDefaults.fontSizes.upperBound)
        UserDefaults.standard.set(fontSize, forKey: ViewerDefaults.fontSizeKey)
        applyFont()
    }

    // MARK: Find

    private func find(_ action: NSTextFinder.Action) {
        switch mode {
        case .text:
            let item = NSMenuItem()
            item.tag = action.rawValue
            textView.performTextFinderAction(item)
        case .hex:
            switch action {
            case .showFindInterface:
                showFindBar()
            case .setSearchString:
                let range = hexView.selection
                let bytes = data[(data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)]
                findBar.field.stringValue = HexFormat.plainHex(bytes.prefix(256))
                findBar.isHex = true
            default:
                if findBar.query.isEmpty { showFindBar() } else { findInHex(backward: action == .previousMatch) }
            }
        }
    }

    private func showFindBar() {
        findBar.isHidden = false
        window?.makeFirstResponder(findBar.field)
        findBar.field.currentEditor()?.selectAll(nil)
    }

    private func closeFindBar() {
        findBar.isHidden = true
        window?.makeFirstResponder(hexView)
    }

    private func findInHex(backward: Bool) {
        let query = findBar.query
        guard !query.isEmpty else { return }
        guard let pattern = findBar.isHex ? ByteSearch.parseHex(query) : encoding.encode(query), !pattern.isEmpty else {
            NSSound.beep()
            infoField.stringValue = findBar.isHex ? String(localized: "Enter hex bytes, for example 4A 6F.")
                                                  : String(localized: "The text cannot be written in \(encoding.title).")
            return
        }
        let data = data, ignoreCase = findBar.ignoresCase && !findBar.isHex
        let current = hexView.selection.lowerBound
        let start = backward ? current : current + 1
        findTask?.cancel()
        findTask = Task {
            let found = await Task.detached(priority: .userInitiated) { () -> Int? in
                ByteSearch.find(pattern, in: data, from: start, backward: backward, ignoringASCIICase: ignoreCase)
                    ?? ByteSearch.find(pattern, in: data, from: backward ? data.count : 0, backward: backward,
                                       ignoringASCIICase: ignoreCase)
            }.value
            guard !Task.isCancelled else { return }
            if let found {
                hexView.select(found..<(found + pattern.count))
            } else {
                NSSound.beep()
                infoField.stringValue = String(localized: "Not found.")
            }
        }
    }

    // MARK: Go to, copy to file

    private func goTo() async {
        switch mode {
        case .hex:
            guard let text = await TextPrompt.ask(title: String(localized: "Go to Offset"),
                                                  message: String(localized: "Offset (decimal, or hex as 0x1F, $1F or 1Fh):"),
                                                  initial: "", in: window) else { return }
            guard let offset = OffsetInput.parse(text), !data.isEmpty else { NSSound.beep(); return }
            let target = Int(min(offset, Int64(data.count - 1)))
            hexView.select(target..<(target + 1))
        case .text:
            guard let text = await TextPrompt.ask(title: String(localized: "Go to Line"), message: String(localized: "Line number:"),
                                                  initial: "", in: window),
                  let line = Int(text.trimmingCharacters(in: .whitespaces)), line > 0 else { return }
            let string = textView.string as NSString
            var start = 0
            for _ in 1..<line where start < string.length {
                start = NSMaxRange(string.lineRange(for: NSRange(location: start, length: 0)))
            }
            let range = string.lineRange(for: NSRange(location: min(start, string.length), length: 0))
            scrollText(toCharacter: range.location)
            textView.setSelectedRange(range)
            textView.showFindIndicator(for: range)
        }
    }

    /// Writes the selection (or everything) to a file the user picks: text as UTF-8, hex as raw bytes.
    private func saveCopy() async {
        guard let window else { return }
        let payload: Data
        switch mode {
        case .text:
            let range = textView.selectedRange()
            let string = textView.string as NSString
            let text = range.length > 0 ? string.substring(with: range) : string as String
            payload = Data(text.utf8)
        case .hex:
            let range = hexView.hasSelection ? hexView.selection : 0..<data.count
            payload = data[(data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound)]
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sequence.current.lastPathComponent
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
        do {
            try payload.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            await alert.beginSheetModal(for: window)
        }
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        loadTask?.cancel()
        decodeTask?.cancel()
        findTask?.cancel()
        Self.open.removeAll { $0 === self }
    }
}
