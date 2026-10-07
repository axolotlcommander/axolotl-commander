import AppKit
import CommanderCore
import Observation
import SwiftUI

/// Live state of a running operation, shown by `ProgressSheet`.
@Observable final class OperationState {
    var title: String
    var progress = OperationProgress(totalBytes: 0, doneBytes: 0, totalItems: 0, doneItems: 0, currentName: "")
    var task: Task<Void, Never>?

    init(title: String) { self.title = title }

    var fraction: Double {
        progress.totalBytes > 0 ? Double(progress.doneBytes) / Double(progress.totalBytes)
            : progress.totalItems > 0 ? Double(progress.doneItems) / Double(progress.totalItems) : 0
    }
}

struct ProgressSheet: View {
    let state: OperationState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.title).font(.headline)
            Text(state.progress.currentName)
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.secondary)
            ProgressView(value: state.fraction)
            HStack {
                Text("\(state.progress.doneItems) of \(state.progress.totalItems) items")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { state.task?.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Target dialog for F5/F6: destination prefilled with the other panel, plus a name mask.
struct TransferSheet: View {
    let title: String
    @State var destination: String
    @State var mask: String
    let onDone: (_ destination: String, _ mask: String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form {
                TextField("To:", text: $destination)
                TextField("Name mask:", text: $mask)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("OK") { onDone(destination, mask) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

/// Runs copy/move/delete/mkdir/rename for the window, with sheets for every question.
final class OperationsController {
    let operations = FileOperations()
    unowned let windowController: MainWindowController
    var isBusy = false

    init(windowController: MainWindowController) {
        self.windowController = windowController
    }

    var window: NSWindow? { windowController.window }

    // MARK: Copy / move

    func transfer(_ kind: TransferKind, sources: [URL], from panel: PanelViewController, to destination: URL? = nil) {
        guard !isBusy, !sources.isEmpty else { return }
        let names = Self.describe(sources)
        if let destination {
            run(kind, sources: sources, destination: destination, mask: "*.*", panel: panel)
            return
        }
        let other = windowController.otherPanel(than: panel)
        var sheetWindow: NSWindow?
        let close = { [weak self] in
            if let sheetWindow { self?.window?.endSheet(sheetWindow) }
        }
        let sheet = TransferSheet(
            title: kind == .copy ? String(localized: "Copy \(names) to:") : String(localized: "Move \(names) to:"),
            destination: other.model.location.displayPath,
            mask: "*.*",
            onDone: { [weak self] path, mask in
                close()
                guard let self else { return }
                do {
                    let url = try PathInput.resolve(path, relativeTo: panel.model.location, absoluteIsLocal: true)
                    run(kind, sources: sources, destination: url, mask: mask.isEmpty ? "*.*" : mask, panel: panel)
                } catch {
                    report(error)
                }
            },
            onCancel: close)
        let host = NSWindow(contentViewController: NSHostingController(rootView: sheet))
        sheetWindow = host
        window?.beginSheet(host, completionHandler: nil)
    }

    private func run(_ kind: TransferKind, sources: [URL], destination: URL, mask: String, panel: PanelViewController) {
        if RemoteURL.isRemote(sources[0]) || RemoteURL.isRemote(destination) {
            return transferRemote(kind, sources: sources, destination: destination, mask: mask, panel: panel)
        }
        if ArchivePath.split(sources[0].deletingLastPathComponent()) != nil || ArchivePath.split(destination) != nil {
            return transferArchive(kind, sources: sources, destination: destination, mask: mask, panel: panel)
        }
        let state = OperationState(title: kind == .copy ? String(localized: "Copying…") : String(localized: "Moving…"))
        let request = TransferRequest(kind: kind, sources: sources, destinationDirectory: destination, nameMask: mask)
        perform(state) { [operations] in
            let report = try await operations.transfer(
                request,
                progress: { p in Task { @MainActor in state.progress = p } },
                conflict: { conflict in await self.askConflict(conflict) })
            if !report.keptSources.isEmpty {
                await self.inform(String(localized: "Some sources were kept"),
                                  String(localized: "\(report.keptSources.count) item(s) were copied but not removed, because they contain a link to a folder or could not be checked completely."))
            }
            panel.model.deselectAll()
        }
    }

    @MainActor
    func askConflict(_ conflict: Conflict) async -> ConflictResolution {
        let alert = NSAlert()
        alert.messageText = String(localized: "“\(conflict.destination.name)” already exists.")
        let existing = String(localized: "Existing: \(Format.bytes(conflict.destination.size ?? 0)), \(conflict.destination.modificationDate.map(Format.date) ?? "")")
        let new = String(localized: "New: \(Format.bytes(conflict.source.size ?? 0)), \(conflict.source.modificationDate.map(Format.date) ?? "")")
        alert.informativeText = existing + "\n" + new
        let buttons = [String(localized: "Overwrite"), String(localized: "Overwrite All"), String(localized: "Skip"),
                       String(localized: "Skip All"), String(localized: "Cancel")]
        for title in buttons { alert.addButton(withTitle: title) }
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        guard let window else { return .cancel }
        let response = await alert.beginSheetModal(for: window)
        switch response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue {
        case 0: return .overwrite
        case 1: return .overwriteAll
        case 2: return .skip
        case 3: return .skipAll
        default: return .cancel
        }
    }

    // MARK: Delete

    func delete(_ urls: [URL], permanently: Bool) {
        guard !isBusy, !urls.isEmpty else { return }
        if let archive = ArchivePath.split(urls[0].deletingLastPathComponent()) {
            return deleteInArchive(urls, archive: archive)
        }
        if RemoteURL.isRemote(urls[0]) { return deleteOnServer(urls) }
        Task {
            let names = Self.describe(urls)
            let alert = NSAlert()
            alert.alertStyle = permanently ? .critical : .warning
            alert.messageText = permanently ? String(localized: "Delete \(names) immediately?") : String(localized: "Move \(names) to the Trash?")
            alert.informativeText = permanently ? String(localized: "This can’t be undone.") : String(localized: "You can put them back from the Trash.")
            let confirm = alert.addButton(withTitle: permanently ? String(localized: "Delete") : String(localized: "Move to Trash"))
            confirm.hasDestructiveAction = permanently
            alert.addButton(withTitle: String(localized: "Cancel"))
            if permanently {
                // Return must not delete by accident: Cancel is the default.
                confirm.keyEquivalent = ""
                alert.buttons[1].keyEquivalent = "\r"
            }
            guard let window, await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
            let state = OperationState(title: permanently ? String(localized: "Deleting…") : String(localized: "Moving to Trash…"))
            perform(state) { [operations] in
                if permanently {
                    try await operations.deletePermanently(urls, progress: { p in Task { @MainActor in state.progress = p } })
                } else {
                    _ = try await operations.trash(urls)
                }
            }
        }
    }

    // MARK: Folder, rename

    func makeDirectory(in panel: PanelViewController) {
        Task {
            guard let name = await TextPrompt.ask(title: String(localized: "New Folder"), message: String(localized: "Name:"),
                                           initial: "", in: window),
                  !name.isEmpty else { return }
            if let archive = panel.model.archive { return makeDirectory(named: name, in: archive, panel: panel) }
            if let remote = panel.model.remote { return makeDirectory(named: name, on: remote, panel: panel) }
            do {
                let url = try await operations.makeDirectory(named: name, in: panel.model.location)
                await panel.model.refresh()
                panel.focus(name: url.lastPathComponent)
            } catch {
                report(error)
            }
        }
    }

    /// ⇧F4: asks for a name, creates an empty file (an existing one is just opened) and hands it to `open`.
    func makeFile(in panel: PanelViewController, open: @escaping (URL) -> Void) {
        Task {
            let initial = panel.model.cursorItem.flatMap { $0.isParent || $0.isDirectory ? nil : $0.name } ?? ""
            guard let name = await TextPrompt.ask(title: String(localized: "Edit New File"), message: String(localized: "Name:"),
                                                  initial: initial, in: window),
                  !name.isEmpty else { return }
            do {
                let made = try await operations.makeFile(named: name, in: panel.model.location)
                if made.created { await panel.model.refresh() }
                panel.focus(name: made.url.lastPathComponent)
                open(made.url)
            } catch {
                report(error)
            }
        }
    }

    func rename(_ url: URL, to newName: String, in panel: PanelViewController) {
        guard newName != url.lastPathComponent, !newName.isEmpty else { return }
        if let archive = panel.model.archive { return rename(url.lastPathComponent, to: newName, in: archive, panel: panel) }
        if let remote = RemoteURL.parse(url) { return rename(remote, to: newName, panel: panel) }
        Task {
            do {
                let renamed = try await operations.rename(url, to: newName)
                panel.model.replaceResult(url, with: renamed)
                await panel.model.refresh()
                panel.focus(name: panel.model.results?.relativeName(of: renamed) ?? renamed.lastPathComponent)
            } catch {
                report(error)
            }
        }
    }

    // MARK: Running

    func perform(_ state: OperationState, _ body: @escaping () async throws -> Void) {
        isBusy = true
        let host = NSWindow(contentViewController: NSHostingController(rootView: ProgressSheet(state: state)))
        // Show the sheet only for operations that take a noticeable time.
        let showTimer = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { window?.beginSheet(host, completionHandler: nil) }
        }
        state.task = Task {
            do {
                try await body()
            } catch OperationError.cancelled {
            } catch ArchiveError.cancelled {
            } catch RemoteError.cancelled {
            } catch is CancellationError {
            } catch {
                showTimer.cancel()
                if host.sheetParent != nil { window?.endSheet(host) }
                report(error)
            }
            showTimer.cancel()
            if host.sheetParent != nil { window?.endSheet(host) }
            isBusy = false
            await windowController.refreshPanels()
        }
    }

    func inform(_ title: String, _ text: String) async {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        if let window { _ = await alert.beginSheetModal(for: window) }
    }

    func report(_ error: any Error) {
        // E.g. a password prompt that was cancelled.
        if case ArchiveError.cancelled? = error as? ArchiveError { return }
        Task { await inform(String(localized: "The operation could not be completed."), OperationsController.describe(error)) }
    }

    /// Quoted name of a single item, or the item count.
    static func describe(_ urls: [URL]) -> String {
        urls.count == 1 ? String(localized: "“\(urls[0].lastPathComponent)”") : String(localized: "\(urls.count) items")
    }

    static func describe(_ error: any Error) -> String {
        switch error as? OperationError {
        case .sameFile(let url)?: String(localized: "“\(url.lastPathComponent)” would be copied onto itself.")
        case .intoItself(let url)?: String(localized: "“\(url.lastPathComponent)” can’t be copied or moved into itself.")
        case .identityUnknown(let url)?: String(localized: "Can’t verify that “\(url.lastPathComponent)” is a different file; nothing was removed.")
        case .sourceKeptBecauseOfLink(let url)?: String(localized: "“\(url.lastPathComponent)” was kept because it contains a link to a folder.")
        case .alreadyExists(let url)?: String(localized: "“\(url.lastPathComponent)” already exists.")
        case .invalidName(let name)?: String(localized: "“\(name)” is not a valid name.")
        case .path(let e)?: Format.error(e)
        case .io(let message)?: message
        case .cancelled?: String(localized: "Cancelled.")
        case nil: Format.error(error)
        }
    }
}
