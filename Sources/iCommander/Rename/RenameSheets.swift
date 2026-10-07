import AppKit
import CommanderCore
import SwiftUI

/// Shared by Change Case and Batch Rename: runs a plan with the progress sheet, then says which
/// names were skipped or failed.
enum RenameRunner {
    static func run(_ plan: [RenamePlanEntry], title: String, in panel: PanelViewController) {
        guard let operations = panel.router?.operations else { return }
        let count = plan.filter { $0.status == .rename }.count
        let skipped = plan.compactMap { entry -> String? in
            guard case .skipped(let reason) = entry.status else { return nil }
            return "\(entry.item.url.lastPathComponent) → \(entry.item.newName): \(describe(reason))"
        }
        let focus = plan.first { $0.status == .rename && $0.item.url.deletingLastPathComponent() == panel.model.location }
        let state = OperationState(title: title)
        state.progress.totalItems = count
        operations.perform(state) {
            var outcome = RenameOutcome()
            if count > 0 {
                outcome = try await RenameExecutor.run(plan) { done, total in
                    Task { @MainActor in
                        state.progress.doneItems = done
                        state.progress.totalItems = total
                    }
                }
            }
            if let focus { panel.focus(name: focus.item.newName) }
            let failures = outcome.failures.map { "\($0.url.lastPathComponent): \($0.message)" }
            guard !skipped.isEmpty || !failures.isEmpty else { return }
            var text = ""
            if !skipped.isEmpty {
                text += String(localized: "Skipped:") + "\n" + skipped.prefix(30).joined(separator: "\n")
                if skipped.count > 30 { text += "\n" + String(localized: "…and \(skipped.count - 30) more") }
            }
            if !failures.isEmpty {
                if !text.isEmpty { text += "\n\n" }
                text += String(localized: "Not renamed:") + "\n" + failures.prefix(30).joined(separator: "\n")
            }
            await operations.inform(String(localized: "\(outcome.renamed.count) of \(plan.count) items renamed."), text)
        }
    }

    static func describe(_ reason: RenameSkip) -> String {
        switch reason {
        case .invalidName: String(localized: "not a valid name")
        case .wildcardIntroduced: String(localized: "the new name would contain * or ?")
        case .existsOnVolume(let name): String(localized: "“\(name)” already exists")
        case .duplicateInBatch(let name): String(localized: "another item would also be named “\(name)”")
        }
    }
}

// MARK: Change Case

enum ChangeCaseSheet {
    private static let defaultsKey = "changeCase.last"

    static func show(for panel: PanelViewController) {
        let targets = panel.targets()
        guard !targets.isEmpty, let window = panel.view.window else { return }
        let saved = UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(CaseChange.self, from: $0) }
        var sheet: NSWindow?
        let view = ChangeCaseView(count: targets.count, hasFolders: targets.contains { $0.isDirectory },
                                  change: saved ?? .lower) { change, recursive in
            if let sheet { window.endSheet(sheet) }
            guard let change else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(change), forKey: defaultsKey)
            apply(change, recursive: recursive, to: targets, in: panel)
        }
        let host = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = host
        window.beginSheet(host, completionHandler: nil)
    }

    private static func apply(_ change: CaseChange, recursive: Bool, to targets: [FileItem], in panel: PanelViewController) {
        Task {
            let urls = targets.map(\.url)
            let plan = await Task.detached(priority: .userInitiated) {
                let items = RenameExecutor.expand(urls, recursive: recursive).map {
                    RenameItem(url: $0.url, isDirectory: $0.isDirectory,
                               newName: change.apply(to: $0.url.lastPathComponent, isDirectory: $0.isDirectory))
                }
                return RenamePlanner.plan(items)
            }.value
            RenameRunner.run(plan, title: String(localized: "Changing case…"), in: panel)
        }
    }
}

private struct ChangeCaseView: View {
    let count: Int
    let hasFolders: Bool
    @State var change: CaseChange
    @State private var recursive = false
    let done: (CaseChange?, Bool) -> Void

    init(count: Int, hasFolders: Bool, change: CaseChange, done: @escaping (CaseChange?, Bool) -> Void) {
        self.count = count
        self.hasFolders = hasFolders
        _change = State(initialValue: change)
        self.done = done
    }

    private let example = "Můj Dokument-final.Txt"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Change Case").font(.headline)
            Text(count == 1 ? "1 item" : "\(count) items").foregroundStyle(.secondary)
            Form {
                Picker("Preset:", selection: preset) {
                    Text("lowercase").tag(0)
                    Text("UPPERCASE").tag(1)
                    Text("Mixed Name, lowercase extension").tag(2)
                    Text("Mixed Name And Extension").tag(3)
                    if presetIndex == nil { Text("Custom").tag(-1) }
                }
                Picker("Name:", selection: $change.name) { styles }
                Picker("Extension:", selection: $change.ext) { styles }
                if hasFolders { Toggle("Include subfolders", isOn: $recursive) }
                LabeledContent("Example:") {
                    Text(change.apply(to: example, isDirectory: false)).monospaced()
                }
            }
            Text("Folders have no extension; their whole name follows the Name setting.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { done(nil, false) }.keyboardShortcut(.cancelAction)
                Button("Change") { done(change, recursive) }.keyboardShortcut(.defaultAction)
                    .disabled(change.name == .keep && change.ext == .keep)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    @ViewBuilder private var styles: some View {
        Text("Keep").tag(CaseStyle.keep)
        Text("lowercase").tag(CaseStyle.lower)
        Text("UPPERCASE").tag(CaseStyle.upper)
        Text("Mixed Case").tag(CaseStyle.mixed)
    }

    private static let presets: [CaseChange] = [.lower, .upper, .partiallyMixed, .mixed]
    private var presetIndex: Int? { Self.presets.firstIndex(of: change) }
    private var preset: Binding<Int> {
        Binding(get: { presetIndex ?? -1 }, set: { if $0 >= 0 { change = Self.presets[$0] } })
    }
}
