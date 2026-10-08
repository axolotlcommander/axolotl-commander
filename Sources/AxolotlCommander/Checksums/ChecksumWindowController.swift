// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import UniformTypeIdentifiers

enum ChecksumDefaults {
    static let algorithmKey = "checksum.algorithm"

    static var algorithm: ChecksumAlgorithm {
        get { UserDefaults.standard.string(forKey: algorithmKey).flatMap(ChecksumAlgorithm.init(rawValue:)) ?? .sha256 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: algorithmKey) }
    }
}

/// Calculate Checksums… (selected files, folders recursively) and Verify Checksums… (a .md5/.sha*/.sfv
/// list). One window per run; it stays open next to the commander.
final class ChecksumWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var open: [ChecksumWindowController] = []

    private enum Mode {
        case calculate(base: URL)
        case verify(list: URL)
    }

    private struct Row {
        var path: String
        var url: URL?
        var digest: String?
        var status: Status
    }

    private enum Status: Equatable {
        case waiting, done, ok, mismatch, missing, failed(String)

        var isProblem: Bool {
            switch self {
            case .mismatch, .missing, .failed: true
            default: false
            }
        }
    }

    private let mode: Mode
    private var rows: [Row] = []
    private var shown: [Int] = []
    private let table = NSTableView()
    private let algorithmPopup = NSPopUpButton()
    private let problemsOnly = NSButton(checkboxWithTitle: String(localized: "Show problems only"), target: nil, action: nil)
    private let saveButton = NSButton()
    private let statusField = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let stopButton = NSButton()
    private var task: Task<Void, Never>?

    // MARK: Entry points

    /// Hashes `items` (folders recursively); the list is meant to be saved in `base`.
    static func calculate(_ items: [URL], base: URL) {
        let files: [(url: URL, path: String)]
        do {
            files = try Checksums.files(in: items, relativeTo: base)
        } catch {
            presentError(error)
            return
        }
        guard !files.isEmpty else {
            let alert = NSAlert()
            alert.messageText = String(localized: "There are no files to calculate checksums for.")
            alert.informativeText = String(localized: "Folders are searched for files; links are skipped.")
            alert.runModal()
            return
        }
        let controller = ChecksumWindowController(mode: .calculate(base: base))
        controller.rows = files.map { Row(path: $0.path, url: $0.url, digest: nil, status: .waiting) }
        controller.present()
        controller.runCalculation()
    }

    /// Checks the files named in the checksum list `list`.
    static func verify(_ list: URL) {
        let parsed: ChecksumList
        do {
            let data = try Data(contentsOf: list, options: .mappedIfSafe)
            parsed = try Checksums.parse(data, fileName: list.lastPathComponent)
        } catch {
            presentError(error)
            return
        }
        let controller = ChecksumWindowController(mode: .verify(list: list))
        controller.rows = parsed.entries.map { Row(path: $0.path, url: nil, digest: $0.digest, status: .waiting) }
        controller.present()
        controller.runVerification(parsed, invalidLines: parsed.invalidLines.count)
    }

    /// Asks for a checksum list to verify, starting in `directory`.
    static func chooseAndVerify(in directory: URL, window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.directoryURL = directory
        panel.allowedContentTypes = ChecksumAlgorithm.allCases.compactMap { UTType(filenameExtension: $0.listExtension) }
        panel.allowsOtherFileTypes = true
        panel.message = String(localized: "Choose a checksum list (.sfv, .md5, .sha1, .sha256, .sha512).")
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { verify(url) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) } else { handle(panel.runModal()) }
    }

    private static func presentError(_ error: any Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "The checksums could not be read.")
        alert.informativeText = describe(error)
        alert.runModal()
    }

    private static func describe(_ error: any Error) -> String {
        switch error as? ChecksumError {
        case .cannotRead(let message)?: message
        case .notRegularFile?: String(localized: "It is not a regular file.")
        default:
            if error is ChecksumError { String(localized: "The file is not a checksum list.") } else { Format.error(error) }
        }
    }

    // MARK: Window

    private init(mode: Mode) {
        self.mode = mode
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 480, height: 260)
        window.setFrameAutosaveName("Checksums")
        super.init(window: window)
        window.delegate = self
        switch mode {
        case .calculate(let base):
            window.title = String(localized: "Checksums – \(base.lastPathComponent)")
        case .verify(let list):
            window.title = String(localized: "Verify – \(list.lastPathComponent)")
            window.representedURL = list
        }
        build()
        if !window.setFrameUsingName("Checksums") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func present() {
        Self.open.append(self)
        showWindow(nil)
        reload()
    }

    private func build() {
        let isCalculate: Bool
        if case .calculate = mode { isCalculate = true } else { isCalculate = false }
        for (id, title, width) in [("path", String(localized: "File"), 280.0),
                                   ("digest", String(localized: "Checksum"), 300.0),
                                   ("status", String(localized: "Result"), 130.0)] {
            if id == "status", isCalculate { continue }
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.style = .fullWidth
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        for algorithm in ChecksumAlgorithm.allCases {
            algorithmPopup.addItem(withTitle: algorithm.title)
            algorithmPopup.lastItem?.representedObject = algorithm.rawValue
        }
        algorithmPopup.selectItem(at: ChecksumAlgorithm.allCases.firstIndex(of: ChecksumDefaults.algorithm) ?? 0)
        algorithmPopup.target = self
        algorithmPopup.action = #selector(algorithmChanged)
        saveButton.title = String(localized: "Save…")
        saveButton.bezelStyle = .push
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command
        problemsOnly.target = self
        problemsOnly.action = #selector(reload)
        stopButton.title = String(localized: "Stop")
        stopButton.bezelStyle = .push
        stopButton.target = self
        stopButton.action = #selector(stop)
        progress.isIndeterminate = false
        progress.style = .bar
        progress.controlSize = .small
        progress.widthAnchor.constraint(equalToConstant: 160).isActive = true
        statusField.lineBreakMode = .byTruncatingTail
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let top: NSStackView
        if isCalculate {
            top = NSStackView(views: [NSTextField(labelWithString: String(localized: "Algorithm:")), algorithmPopup, NSView(), saveButton])
        } else {
            top = NSStackView(views: [problemsOnly, NSView()])
        }
        top.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)
        let bottom = NSStackView(views: [statusField, NSView(), progress, stopButton])
        bottom.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 10, right: 12)
        let stack = NSStackView(views: [top, scroll, bottom])
        stack.orientation = .vertical
        stack.spacing = 0
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        window?.contentView = stack
        window?.initialFirstResponder = table
    }

    func windowWillClose(_ notification: Notification) {
        task?.cancel()
        Self.open.removeAll { $0 === self }
    }

    // MARK: Running

    private var algorithm: ChecksumAlgorithm {
        (algorithmPopup.selectedItem?.representedObject as? String).flatMap(ChecksumAlgorithm.init(rawValue:)) ?? .sha256
    }

    private func setRunning(_ running: Bool) {
        progress.isHidden = !running
        stopButton.isHidden = !running
        saveButton.isEnabled = !running && rows.contains { $0.status == .done }
        algorithmPopup.isEnabled = !running
    }

    private func runCalculation() {
        task?.cancel()
        let algorithm = algorithm
        for index in rows.indices { rows[index].digest = nil; rows[index].status = .waiting }
        reload()
        setRunning(true)
        progress.doubleValue = 0
        let files = rows.map(\.url)
        task = Task { [weak self] in
            let total = files.count
            for (index, url) in files.enumerated() {
                guard let url, !Task.isCancelled else { break }
                let outcome: Result<String, any Error>
                do {
                    let digests = try await Self.digest(url, algorithm)
                    outcome = .success(digests)
                } catch {
                    outcome = .failure(error)
                }
                guard let self, !Task.isCancelled else { return }
                switch outcome {
                case .success(let digest): self.rows[index].digest = digest; self.rows[index].status = .done
                case .failure(is CancellationError): return
                case .failure(let error): self.rows[index].status = .failed(Self.describe(error))
                }
                self.progress.doubleValue = Double(index + 1) / Double(total) * 100
                self.table.reloadData(forRowIndexes: [index], columnIndexes: IndexSet(integersIn: 0..<self.table.numberOfColumns))
                self.statusField.stringValue = String(localized: "\(index + 1) of \(total) files")
            }
            self?.calculationFinished()
        }
    }

    /// Off the main actor: the file is read in chunks and the task can be cancelled.
    private nonisolated static func digest(_ url: URL, _ algorithm: ChecksumAlgorithm) async throws -> String {
        try Checksums.digests(of: url, algorithms: [algorithm])[algorithm] ?? ""
    }

    private func calculationFinished() {
        task = nil
        setRunning(false)
        let failed = rows.filter { if case .failed = $0.status { true } else { false } }.count
        let done = rows.filter { $0.status == .done }.count
        statusField.stringValue = failed == 0
            ? String(localized: "\(done) files. Save the list with ⌘S.")
            : String(localized: "\(done) files, \(failed) could not be read.")
        reload()
    }

    private func runVerification(_ list: ChecksumList, invalidLines: Int) {
        guard case .verify(let listURL) = mode else { return }
        setRunning(true)
        progress.doubleValue = 0
        let directory = listURL.deletingLastPathComponent()
        task = Task { [weak self] in
            let results: [VerifyResult]
            do {
                results = try await Checksums.verify(list, listDirectory: directory) { done, total in
                    Task { @MainActor in
                        self?.progress.doubleValue = total > 0 ? Double(done) / Double(total) * 100 : 0
                        self?.statusField.stringValue = String(localized: "\(done) of \(total) files")
                    }
                }
            } catch {
                guard let self else { return }
                self.task = nil
                self.setRunning(false)
                self.statusField.stringValue = error is CancellationError ? String(localized: "Stopped.") : Self.describe(error)
                return
            }
            guard let self else { return }
            for (index, result) in results.enumerated() where index < self.rows.count {
                switch result.status {
                case .ok: self.rows[index].status = .ok
                case .mismatch: self.rows[index].status = .mismatch
                case .missing: self.rows[index].status = .missing
                case .unreadable(let message): self.rows[index].status = .failed(message)
                }
            }
            self.task = nil
            self.setRunning(false)
            let ok = self.rows.filter { $0.status == .ok }.count
            let bad = self.rows.filter { $0.status == .mismatch }.count
            let missing = self.rows.filter { $0.status == .missing }.count
            let failed = self.rows.count - ok - bad - missing
            var parts = [String(localized: "\(ok) OK")]
            if bad > 0 { parts.append(String(localized: "\(bad) do not match")) }
            if missing > 0 { parts.append(String(localized: "\(missing) missing")) }
            if failed > 0 { parts.append(String(localized: "\(failed) unreadable")) }
            if invalidLines > 0 { parts.append(String(localized: "\(invalidLines) lines not understood")) }
            self.statusField.stringValue = parts.joined(separator: ", ")
            if bad + missing + failed > 0 { self.problemsOnly.state = .on }
            self.reload()
        }
    }

    /// Esc stops a running calculation, otherwise closes the window.
    @objc override func cancelOperation(_ sender: Any?) {
        if task != nil { stop() } else { close() }
    }

    @objc private func stop() {
        task?.cancel()
        task = nil
        setRunning(false)
        statusField.stringValue = String(localized: "Stopped.")
    }

    @objc private func algorithmChanged() {
        ChecksumDefaults.algorithm = algorithm
        runCalculation()
    }

    // MARK: Saving

    @objc private func save() {
        guard case .calculate(let base) = mode, let window else { return }
        let algorithm = algorithm
        let panel = NSSavePanel()
        panel.directoryURL = base
        let stem = rows.count == 1 ? (rows[0].url?.lastPathComponent ?? "checksums") : (base.lastPathComponent.isEmpty ? "checksums" : base.lastPathComponent)
        panel.nameFieldStringValue = "\(stem).\(algorithm.listExtension)"
        panel.allowedContentTypes = UTType(filenameExtension: algorithm.listExtension).map { [$0] } ?? []
        panel.allowsOtherFileTypes = true
        panel.message = String(localized: "Paths in the list are relative to the folder it is saved in.")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let target = panel.url, let self else { return }
            self.write(to: target, algorithm: algorithm)
        }
    }

    private func write(to target: URL, algorithm: ChecksumAlgorithm) {
        let directory = target.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        let entries = rows.compactMap { row -> (path: String, digest: String)? in
            guard row.status == .done, let digest = row.digest, let url = row.url else { return nil }
            let path = url.standardizedFileURL.path(percentEncoded: false)
            return (path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path, digest)
        }
        let (data, skipped) = Checksums.listData(entries, algorithm: algorithm)
        do {
            try SafeFileWriter.write(to: target) { temp in try data.write(to: temp) }
            var text = String(localized: "\(entries.count - skipped.count) checksums saved to “\(target.lastPathComponent)”.")
            if !skipped.isEmpty {
                text += "\n" + String(localized: "Names that the format cannot hold were left out: \(skipped.joined(separator: ", "))")
            }
            statusField.stringValue = text
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "The checksum list could not be saved.")
            alert.informativeText = Format.error(error)
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    // MARK: Table

    @objc private func reload() {
        shown = problemsOnly.state == .on ? rows.indices.filter { rows[$0].status.isProblem } : Array(rows.indices)
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, row < shown.count else { return nil }
        let item = rows[shown[row]]
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = id.rawValue == "status" ? .byTruncatingTail : .byTruncatingMiddle
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let field = cell.textField
        field?.textColor = .labelColor
        field?.font = .systemFont(ofSize: NSFont.systemFontSize)
        switch id.rawValue {
        case "path":
            field?.stringValue = item.path
        case "digest":
            field?.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            if case .failed(let message) = item.status, case .calculate = mode {
                field?.stringValue = message
                field?.textColor = .systemRed
            } else {
                field?.stringValue = item.digest ?? ""
                field?.textColor = item.status == .waiting ? .tertiaryLabelColor : .labelColor
            }
        default:
            switch item.status {
            case .waiting: field?.stringValue = "…"; field?.textColor = .tertiaryLabelColor
            case .done, .ok: field?.stringValue = String(localized: "OK"); field?.textColor = .systemGreen
            case .mismatch: field?.stringValue = String(localized: "Does not match"); field?.textColor = .systemRed
            case .missing: field?.stringValue = String(localized: "Missing"); field?.textColor = .systemOrange
            case .failed(let message): field?.stringValue = message; field?.textColor = .systemRed
            }
        }
        return cell
    }

    /// ⌘C: the selected lines as "checksum  path".
    @objc func copy(_ sender: Any?) {
        let lines = table.selectedRowIndexes.compactMap { $0 < shown.count ? rows[shown[$0]] : nil }
            .map { "\($0.digest ?? "")  \($0.path)" }
        guard !lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n") + "\n", forType: .string)
    }
}
