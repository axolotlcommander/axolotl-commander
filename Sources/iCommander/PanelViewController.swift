import AppKit
import CommanderCore
import OSLog

/// Table that sends every key through the key map before default handling.
final class PanelTableView: NSTableView {
    var onKey: ((NSEvent) -> Bool)?
    var onFocus: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }
}

final class PanelViewController: NSViewController {
    let side: PanelSide
    weak var router: MainWindowController?
    let tableView = PanelTableView()
    private let pathField = NSTextField()
    private let statusField = NSTextField(labelWithString: "")

    var showsHidden = false
    var isActive = false { didSet { updateActiveAppearance() } }

    init(side: PanelSide) {
        self.side = side
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        pathField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathField.isBordered = false
        pathField.drawsBackground = true
        pathField.lineBreakMode = .byTruncatingHead
        pathField.placeholderString = "Path"

        for (id, title, width) in [("name", "Name", 260.0), ("ext", "Ext", 60.0),
                                   ("size", "Size", 90.0), ("date", "Date", 140.0)] {
            let column = NSTableColumn(identifier: .init(id))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        tableView.onFocus = { [weak self] in
            guard let self else { return }
            router?.panelDidBecomeFirstResponder(self)
        }

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        statusField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusField.textColor = .secondaryLabelColor
        statusField.stringValue = "Stage 0"

        let stack = NSStackView(views: [pathField, scroll, statusField])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        updateActiveAppearance()
    }

    private func updateActiveAppearance() {
        pathField.backgroundColor = isActive ? .controlAccentColor.withAlphaComponent(0.25) : .clear
    }

    // MARK: Keys and commands

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord(event: event) else { return false }
        if let command = KeyMap.standard.command(for: chord) {
            log.info("key \(chord.description) → \(command.rawValue)")
            router?.perform(command)
            return true
        }
        return false
    }

    func canPerform(_ command: Command) -> Bool { false }

    func perform(_ command: Command) {}
}
