// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import Observation
import SwiftUI

/// ⌃M: renames the selected items by a mask with counters, search and replace and change of case,
/// with a live preview. Names that would collide, are invalid or would contain a new `*`/`?` are
/// skipped and shown.
enum BatchRenameSheet {
    private static let defaultsKey = "batchRename.last"

    static func show(for panel: PanelViewController) {
        let targets = panel.targets().filter { !$0.isParent }
        guard !targets.isEmpty, let window = panel.view.window else { return }
        guard panel.router?.operations.isBusy != true else {
            NSSound.beep()
            return
        }
        var options = UserDefaults.standard.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode(BatchRenameOptions.self, from: $0) } ?? BatchRenameOptions()
        // The counter restarts with every run; the mask and the rest are remembered.
        if options.mask.isEmpty { options.mask = "*.*" }
        let model = BatchRenameModel(
            selected: targets.map {
                RenameSource(url: $0.url, isDirectory: $0.isDirectory, modified: $0.modificationDate, size: $0.size)
            },
            hasFolders: targets.contains { $0.isDirectory && !$0.isSymlink },
            includeHidden: panel.showsHidden, options: options)
        var sheet: NSWindow?
        let view = BatchRenameView(model: model) { plan in
            model.stop()
            if let sheet { window.endSheet(sheet) }
            UserDefaults.standard.set(try? JSONEncoder().encode(model.options), forKey: defaultsKey)
            guard let plan else { return }
            RenameRunner.run(plan, title: String(localized: "Renaming…"), in: panel)
        }
        let host = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = host
        window.beginSheet(host, completionHandler: nil)
    }
}

@Observable final class BatchRenameModel {
    struct Row: Identifiable {
        var id: Int
        var original: String
        var folder: String
        var newName: String
        var status: RenameStatus
    }

    /// The selected items; `sources` adds the items inside selected folders when that is on.
    let selected: [RenameSource]
    /// The selection contains real folders, so "Include items in subfolders" applies.
    let hasFolders: Bool
    private let includeHidden: Bool
    private(set) var sources: [RenameSource]
    var options: BatchRenameOptions {
        didSet {
            guard options != oldValue else { return }
            if expansionKey(options) != expansionKey(oldValue) { expand() } else { schedule() }
        }
    }
    private(set) var rows: [Row] = []
    private(set) var plan: [RenamePlanEntry] = []
    private(set) var error: String?
    /// Folders are being read for "Include items in subfolders".
    private(set) var isReading = false
    private var listings: [String: [String]] = [:]
    private var pending: Task<Void, Never>?
    private var expansion: Task<Void, Never>?

    init(selected: [RenameSource], hasFolders: Bool, includeHidden: Bool, options: BatchRenameOptions) {
        self.selected = selected
        self.hasFolders = hasFolders
        self.includeHidden = includeHidden
        self.sources = selected
        self.options = options
        if expansionKey(options) == nil { update() } else { expand() }
    }

    /// What the expanded sources depend on; nil when only the selected items take part.
    private func expansionKey(_ options: BatchRenameOptions) -> SubfolderItems? {
        hasFolders && options.includeSubfolders ? options.subfolderItems : nil
    }

    /// Reads the selected folders off the main thread, then recomputes the preview.
    private func expand() {
        expansion?.cancel()
        pending?.cancel()
        guard let kinds = expansionKey(options) else {
            isReading = false
            sources = selected
            update()
            return
        }
        isReading = true
        let selected = selected, includeHidden = includeHidden
        expansion = Task {
            let work = Task.detached(priority: .userInitiated) {
                BatchRename.expand(selected, kinds: kinds, includeHidden: includeHidden)
            }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            sources = result.sources
            listings.merge(result.listings) { _, new in new }
            isReading = false
            update()
        }
    }

    /// The sheet closed: stops reading folders and recomputing.
    func stop() {
        expansion?.cancel()
        pending?.cancel()
    }

    /// The plan for the options as they are now: the preview may still lag behind typing, so it
    /// is recomputed first. nil when there is nothing valid to rename (the sheet then shows why).
    func currentPlan() -> [RenamePlanEntry]? {
        guard !isReading else { return nil }
        pending?.cancel()
        update()
        return error == nil && renameCount > 0 ? plan : nil
    }

    var renameCount: Int { plan.filter { $0.status == .rename }.count }
    var skipCount: Int { plan.filter { if case .skipped = $0.status { true } else { false } }.count }

    /// Recomputes shortly after typing stops.
    private func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, !isReading else { return }
            update()
        }
    }

    func update() {
        do {
            plan = try BatchRename.preview(sources, options: options, listing: { [self] folder in
                if let names = listings[folder.path] { return names }
                let names = try RenamePlanner.defaultListing(folder)
                listings[folder.path] = names
                return names
            })
            error = nil
        } catch let failure as BatchRenameError {
            plan = []
            error = switch failure {
            case .invalidRegex(let message): String(localized: "The regular expression is not valid: \(message)")
            case .unknownVariable(let name): String(localized: "Unknown variable [\(name)].")
            case .unterminatedVariable: String(localized: "A variable is missing its closing ].")
            }
        } catch {
            plan = []
            self.error = Format.error(error)
        }
        let base = selected.first.map { $0.url.deletingLastPathComponent().displayPath } ?? ""
        rows = sources.indices.map { index in
            let source = sources[index]
            let entry = index < plan.count ? plan[index] : nil
            // Items in subfolders show their folder below the panel's folder (“2024/”), others nothing.
            let folder = source.url.deletingLastPathComponent().displayPath
            let relative = folder.hasPrefix(base + "/") ? String(folder.dropFirst(base.count + 1)) + "/"
                : folder == base ? "" : folder
            return Row(id: index, original: source.url.lastPathComponent,
                       folder: relative,
                       newName: entry?.item.newName ?? "", status: entry?.status ?? .unchanged)
        }
    }
}

private struct BatchRenameView: View {
    @Bindable var model: BatchRenameModel
    let done: ([RenamePlanEntry]?) -> Void

    private static let variables: [(token: String, title: LocalizedStringKey)] = [
        ("[N]", "Name without extension"), ("[E]", "Extension"), ("[F]", "Whole name"),
        ("[P]", "Enclosing folder name"), ("[C]", "Counter"), ("[C:1:1:3]", "Counter (start, step, digits)"),
        ("[D]", "Modification date (yyyy-MM-dd)"), ("[T]", "Modification time (HHmmss)"),
        ("[Y]", "Year"), ("[M]", "Month"), ("[d]", "Day"),
        ("*", "Rest of the original name part"), ("?", "One character of the original name"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch Rename").font(.headline)
            Form {
                HStack {
                    TextField("New name:", text: $model.options.mask, prompt: Text("*.*"))
                        .font(.body.monospaced())
                    Menu("Insert") {
                        ForEach(Self.variables, id: \.token) { variable in
                            Button { model.options.mask += variable.token } label: {
                                Text("\(variable.token)   ") + Text(variable.title)
                            }
                        }
                    }
                    .fixedSize()
                }
                HStack(spacing: 16) {
                    Stepper("Counter start: \(model.options.counterStart)", value: $model.options.counterStart)
                    Stepper("Step: \(model.options.counterStep)", value: $model.options.counterStep)
                    Stepper("Digits: \(model.options.counterWidth)", value: $model.options.counterWidth, in: 1...10)
                }
                HStack {
                    TextField("Find:", text: $model.options.search)
                    TextField("Replace with:", text: $model.options.replace)
                }
                HStack(spacing: 16) {
                    Toggle("Regular expression", isOn: $model.options.useRegex)
                    Toggle("Match case", isOn: $model.options.caseSensitive)
                }
                HStack(spacing: 16) {
                    Toggle("First match only", isOn: $model.options.onlyFirst)
                    Toggle("Leave extension alone", isOn: $model.options.excludeExtension)
                }
                HStack {
                    Picker("Name case:", selection: $model.options.caseChange.name) { caseStyles }
                    Picker("Extension case:", selection: $model.options.caseChange.ext) { caseStyles }
                }
                if model.hasFolders {
                    HStack(spacing: 16) {
                        Toggle("Include items in subfolders", isOn: $model.options.includeSubfolders)
                        Picker("Items in subfolders:", selection: $model.options.subfolderItems) {
                            Text("Files and folders").tag(SubfolderItems.filesAndFolders)
                            Text("Files only").tag(SubfolderItems.files)
                            Text("Folders only").tag(SubfolderItems.folders)
                        }
                        .fixedSize()
                        .disabled(!model.options.includeSubfolders)
                    }
                }
            }
            Table(model.rows) {
                TableColumn("Original Name") { row in
                    Text(row.original).foregroundStyle(row.status == .unchanged ? .secondary : .primary)
                }
                TableColumn("New Name") { row in
                    Text(row.newName).foregroundStyle(color(row.status))
                }
                TableColumn("Note") { row in
                    Text(note(row)).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 220)
            .overlay {
                if model.isReading {
                    ProgressView("Reading folders…").padding().background(.regularMaterial, in: .rect(cornerRadius: 8))
                }
            }
            HStack {
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else {
                    Text(summary).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { done(nil) }.keyboardShortcut(.cancelAction)
                Button("Rename") { if let plan = model.currentPlan() { done(plan) } }.keyboardShortcut(.defaultAction)
                    .disabled(model.isReading || model.error != nil || model.renameCount == 0)
            }
        }
        .padding(20)
        .frame(width: 780, height: model.hasFolders ? 610 : 580)
    }

    @ViewBuilder private var caseStyles: some View {
        Text("Keep").tag(CaseStyle.keep)
        Text("lowercase").tag(CaseStyle.lower)
        Text("UPPERCASE").tag(CaseStyle.upper)
        Text("Mixed Case").tag(CaseStyle.mixed)
    }

    private var summary: String {
        var text = String(localized: "\(model.renameCount) of \(model.sources.count) items will be renamed.")
        if model.skipCount > 0 { text += " " + String(localized: "\(model.skipCount) skipped.") }
        return text
    }

    private func color(_ status: RenameStatus) -> Color {
        switch status {
        case .rename: .primary
        case .unchanged: .secondary
        case .skipped: .red
        }
    }

    private func note(_ row: BatchRenameModel.Row) -> String {
        var parts: [String] = []
        if case .skipped(let reason) = row.status { parts.append(RenameRunner.describe(reason)) }
        if row.status == .unchanged { parts.append(String(localized: "unchanged")) }
        if !row.folder.isEmpty { parts.append(row.folder) }
        return parts.joined(separator: " · ")
    }
}
