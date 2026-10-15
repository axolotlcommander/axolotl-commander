// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// A sheet window that offers key presses to a handler before its controls see them.
final class KeySheetWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    /// The controller of the sheet, kept alive while the sheet is shown.
    var owner: AnyObject?

    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isReleasedWhenClosed = false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

/// The replace question for one operation (spec 021): the policy answers what the user already
/// decided for the rest of the operation, the sheet asks the rest.
@MainActor
final class ConflictAsker {
    private var policy = ConflictPolicy()
    private weak var window: NSWindow?

    init(window: NSWindow?) {
        self.window = window
    }

    func ask(_ conflict: Conflict) async -> ConflictResolution {
        if case .answer(let resolution) = policy.decide(conflict) { return resolution }
        guard let window else { return .cancel }
        let choice = await ConflictSheet.run(conflict, in: window)
        return policy.choose(choice, for: conflict)
    }
}

/// "“x.txt” already exists.": both files with the newer and the larger marked; F3 / ⇧F3 show the
/// existing / new file, ⌥F3 compares them; More… holds the less common choices.
@MainActor
final class ConflictSheet: NSObject {
    private let conflict: Conflict
    private let sheet: KeySheetWindow
    private var continuation: CheckedContinuation<ConflictPolicy.Choice, Never>?
    private var moreButton: NSButton!

    private init(_ conflict: Conflict) {
        self.conflict = conflict
        sheet = KeySheetWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                               styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        build()
        sheet.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    }

    /// Shows the question on the deepest sheet of `window` (the progress sheet of a long operation),
    /// so the viewer and Compare Files stay usable while it waits.
    static func run(_ conflict: Conflict, in window: NSWindow) async -> ConflictPolicy.Choice {
        let question = ConflictSheet(conflict)
        var host = window
        while let attached = host.attachedSheet { host = attached }
        return await withCheckedContinuation { continuation in
            question.continuation = continuation
            question.sheet.owner = question
            host.beginSheet(question.sheet, completionHandler: nil)
        }
    }

    private var bothFiles: Bool { !conflict.source.isDirectory && !conflict.destination.isDirectory }

    // MARK: Layout

    private func build() {
        let title = NSTextField(wrappingLabelWithString: String(localized: "“\(conflict.destination.name)” already exists."))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let marks = ConflictMarks(conflict)
        let info = NSTextField(wrappingLabelWithString: [
            Self.line(String(localized: "Existing: \(Self.describe(conflict.destination))"), side: .existing, marks),
            Self.line(String(localized: "New: \(Self.describe(conflict.source))"), side: .new, marks),
        ].joined(separator: "\n"))
        var rows: [NSView] = [title, info]
        if bothFiles {
            let hint = NSTextField(wrappingLabelWithString: String(localized: "F3 existing · ⇧F3 new · ⌥F3 compare"))
            hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            hint.textColor = .secondaryLabelColor
            rows.append(hint)
        }
        let choices: [(String, ConflictPolicy.Choice?)] = [
            (String(localized: "Overwrite"), .overwrite), (String(localized: "Overwrite All"), .overwriteAll),
            (String(localized: "Skip"), .skip), (String(localized: "Skip All"), .skipAll),
            (String(localized: "More…"), nil), (String(localized: "Cancel"), .cancel),
        ]
        let buttons = NSStackView()
        buttons.orientation = .vertical
        buttons.spacing = 6
        for (index, (text, choice)) in choices.enumerated() {
            let button = NSButton(title: text, target: self, action: #selector(pressed(_:)))
            button.bezelStyle = .push
            button.controlSize = .large
            button.tag = index
            if choice == nil {
                button.action = #selector(showMore(_:))
                moreButton = button
            }
            if choice == .overwrite { button.keyEquivalent = "\r" }
            if choice == .cancel { button.keyEquivalent = "\u{1b}" }
            buttons.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: buttons.widthAnchor).isActive = true
        }
        rows.append(buttons)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(16, after: rows[rows.count - 2])
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 300),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        for label in [title, info] { label.preferredMaxLayoutWidth = 260 }
        sheet.contentView = content
        sheet.setContentSize(content.fittingSize)
    }

    private static func describe(_ item: FileItemInfo) -> String {
        let size = item.isDirectory ? String(localized: "folder") : Format.bytes(item.size ?? 0)
        guard let date = item.modificationDate else { return size }
        return size + ", " + Format.date(date)
    }

    /// The info line of one side with its marks ("newer", "larger").
    private static func line(_ text: String, side: ConflictMarks.Side, _ marks: ConflictMarks) -> String {
        var words: [String] = []
        if marks.newer == side { words.append(String(localized: "newer")) }
        if marks.larger == side { words.append(String(localized: "larger")) }
        return words.isEmpty ? text : text + " — " + words.joined(separator: ", ")
    }

    // MARK: Choices

    @objc private func pressed(_ sender: NSButton) {
        let choices: [ConflictPolicy.Choice] = [.overwrite, .overwriteAll, .skip, .skipAll, .cancel, .cancel]
        finish(choices[sender.tag])
    }

    @objc private func showMore(_ sender: NSButton) {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        add(String(localized: "Overwrite All Older"), #selector(overwriteAllOlder))
        menu.addItem(.separator())
        add(String(localized: "Rename…"), #selector(renameByHand), enabled: conflict.canRename)
        add(String(localized: "Rename Automatically"), #selector(renameAutomatically), enabled: conflict.canRename)
        add(String(localized: "Rename All Automatically"), #selector(renameAllAutomatically), enabled: conflict.canRename)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func overwriteAllOlder() { finish(.overwriteAllOlder) }
    @objc private func renameAutomatically() { finish(.renameAutomatically) }
    @objc private func renameAllAutomatically() { finish(.renameAllAutomatically) }

    @objc private func renameByHand() {
        Task {
            // The first free automatic name; on a server the question comes back if it is taken.
            let name = conflict.destination.name, isDirectory = conflict.source.isDirectory
            let taken = takenCheck()
            let first = await Task.detached {
                var attempt = 2
                var first = AutoName.name(for: name, isDirectory: isDirectory, attempt: attempt)
                while taken(first), attempt < 1000 {
                    attempt += 1
                    first = AutoName.name(for: name, isDirectory: isDirectory, attempt: attempt)
                }
                return first
            }.value
            // Another button answered meanwhile.
            guard continuation != nil else { return }
            if let name = await askName(initial: first) { finish(.rename(name)) }
        }
    }

    /// Asks until the name is usable or the user cancels (nil: back to the question).
    private func askName(initial: String) async -> String? {
        var text = initial
        while true {
            let alert = NSAlert()
            alert.messageText = String(localized: "Rename")
            alert.informativeText = String(localized: "New name for “\(conflict.source.name)”:")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            let field = NSTextField(string: text)
            field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            let isDirectory = conflict.source.isDirectory
            DispatchQueue.main.async {
                // The base of the name is selected, as in Finder.
                if let range = TransferTarget.range(of: .name, in: field.stringValue, isDirectory: isDirectory) {
                    field.currentEditor()?.selectedRange = range
                }
            }
            guard await alert.beginSheetModal(for: sheet) == .alertFirstButtonReturn else { return nil }
            text = field.stringValue
            guard let problem = await problem(with: text) else { return text }
            let refusal = NSAlert()
            refusal.messageText = problem
            _ = await refusal.beginSheetModal(for: sheet)
        }
    }

    /// Why a typed name cannot be used; nil when it can. A taken name is checked on disk only; on a
    /// server the question comes back for it.
    private func problem(with name: String) async -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "The name can’t be empty.") }
        if name.contains("/") { return String(localized: "The name can’t contain “/”.") }
        let taken = takenCheck()
        if await Task.detached(operation: { taken(name) }).value { return String(localized: "“\(name)” already exists.") }
        return nil
    }

    /// Whether a name exists next to the destination; known for local destinations only. Asked off
    /// the main thread: the destination may be a disk that is asleep.
    private func takenCheck() -> @Sendable (String) -> Bool {
        let destination = conflict.destination.url
        guard destination.isFileURL, !RemoteURL.isRemote(destination) else { return { _ in false } }
        let folder = destination.deletingLastPathComponent()
        return { name in FileManager.default.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false)) }
    }

    private func finish(_ choice: ConflictPolicy.Choice) {
        guard let continuation else { return }
        self.continuation = nil
        sheet.sheetParent?.endSheet(sheet)
        sheet.owner = nil
        continuation.resume(returning: choice)
    }

    // MARK: Looking into the files

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 99, sheet.attachedSheet == nil else { return false }  // F3
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags.isEmpty || flags == .shift || flags == .option else { return false }
        guard bothFiles else {
            NSSound.beep()
            return true
        }
        let existing = conflict.destination.url, new = conflict.source.url
        Task {
            do {
                switch flags {
                case .shift: try await Self.view(new)
                case .option:
                    async let left = CompareFiles.localCopy(of: existing)
                    async let right = CompareFiles.localCopy(of: new)
                    let (a, b) = try await (left, right)
                    CompareWindowController.show(left: a, right: b, leftTitle: existing.displayPath,
                                                 rightTitle: new.displayPath)
                default: try await Self.view(existing)
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "The file could not be opened.")
                alert.informativeText = OperationsController.describe(error)
                _ = await alert.beginSheetModal(for: sheet)
            }
        }
        return true
    }

    /// The viewer, from a temporary copy for archive members and server files.
    private static func view(_ url: URL) async throws {
        let copy = try await CompareFiles.localCopy(of: url)
        if let sequence = FileSequence(entries: [.init(url: copy, isSelected: false)], current: copy) {
            ViewerWindowController.show(sequence)
        }
    }
}
