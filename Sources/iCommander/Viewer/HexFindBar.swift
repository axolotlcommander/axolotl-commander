import AppKit

/// Find bar of the hex mode: text (in the current encoding) or hex bytes.
/// Text mode uses the system find bar of NSTextView instead.
final class HexFindBar: NSView, NSSearchFieldDelegate {
    let field = NSSearchField()
    private let kind = NSSegmentedControl(labels: [String(localized: "Text"), String(localized: "Hex")],
                                          trackingMode: .selectOne, target: nil, action: nil)
    private let ignoreCase = NSButton(checkboxWithTitle: String(localized: "Ignore Case"), target: nil, action: nil)

    /// Called with `backward` when the user asks for the next or previous match.
    var onFind: ((_ backward: Bool) -> Void)?
    var onClose: (() -> Void)?

    var query: String { field.stringValue }
    var isHex: Bool {
        get { kind.selectedSegment == 1 }
        set { kind.selectedSegment = newValue ? 1 : 0 }
    }
    var ignoresCase: Bool { ignoreCase.state == .on }
    /// The Markdown preview finds text only.
    var allowsHex = true {
        didSet {
            kind.isHidden = !allowsHex
            if !allowsHex { isHex = false }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.placeholderString = String(localized: "Find")
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = true
        field.delegate = self
        field.target = self
        field.action = #selector(findNext)
        kind.selectedSegment = 0
        kind.controlSize = .small
        ignoreCase.state = .on
        ignoreCase.controlSize = .small
        let previous = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: String(localized: "Find Previous"))!,
                                target: self, action: #selector(findPrevious))
        let next = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: String(localized: "Find Next"))!,
                            target: self, action: #selector(findNext))
        let done = NSButton(title: String(localized: "Done"), target: self, action: #selector(close))
        for button in [previous, next, done] {
            button.bezelStyle = .accessoryBarAction
            button.controlSize = .small
        }
        let stack = NSStackView(views: [field, kind, ignoreCase, previous, next, done])
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    @objc private func findNext() { onFind?(false) }
    @objc private func findPrevious() { onFind?(true) }
    @objc private func close() { onClose?() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(cancelOperation(_:)): close(); return true
        case #selector(insertNewline(_:)):
            onFind?(NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            return true
        default: return false
        }
    }
}
