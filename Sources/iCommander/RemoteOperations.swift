import AppKit
import CommanderCore

extension RemoteError {
    var message: String {
        switch self {
        case .connectionFailed(let message): String(localized: "Could not connect: \(message)")
        case .authenticationFailed: String(localized: "The server refused the user name or password.")
        case .hostKeyRejected(let message): String(localized: "The server’s identity was not accepted. \(message)")
        case .notFound(let path): String(localized: "“\(RemotePath.name(path))” was not found on the server.")
        case .permissionDenied(let path): String(localized: "You don’t have permission to access “\(RemotePath.name(path))” on the server.")
        case .alreadyExists(let path): String(localized: "“\(RemotePath.name(path))” already exists on the server.")
        case .invalidName(let name): String(localized: "“\(name)” can’t be used on the server.")
        case .server(let message): String(localized: "The server reported an error: \(message)")
        case .disconnected: String(localized: "The connection to the server was lost.")
        case .cancelled: String(localized: "Cancelled.")
        }
    }
}

/// Opens server sessions for `RemoteConnections`.
enum RemoteSetup {
    static func configure() {
        RemoteConnections.shared.configure(
            connector: connect,
            prompter: { prompt in await RemotePrompts.ask(prompt) },
            passwords: KeychainPasswordStore())
    }

    private static let connect: RemoteConnections.Connector = { endpoint, options, prompter in
        switch endpoint.proto {
        case .sftp:
            var ssh = SSHOptions()
            // Hidden setting for tests: e.g. ["-F", "/path/to/test_config"].
            if let extra = UserDefaults.standard.stringArray(forKey: "ssh.extraArguments") { ssh.extraArguments = extra }
            return try await SFTPClient.connect(endpoint: endpoint, transport: .ssh(ssh), prompter: prompter)
        case .ftp, .ftps:
            var ftp = FTPOptions()
            ftp.passive = options.passiveMode
            return try await FTPClient.connect(endpoint: endpoint, password: nil, prompter: prompter, options: ftp)
        }
    }
}

/// Password, passphrase and host key questions while connecting.
@MainActor
enum RemotePrompts {
    static func ask(_ prompt: AuthPrompt) async -> PromptReply? {
        let alert = NSAlert()
        var field: NSTextField?
        var remember: NSButton?
        switch prompt {
        case .password(let endpoint, let attempt, let message):
            alert.messageText = attempt > 1
                ? String(localized: "The password for \(RemoteURL.displayName(endpoint)) was not accepted.")
                : String(localized: "Password for \(RemoteURL.displayName(endpoint))")
            alert.informativeText = attempt > 1 ? String(localized: "Enter it again.") : message
            field = NSSecureTextField()
            remember = NSButton(checkboxWithTitle: String(localized: "Remember in Keychain"), target: nil, action: nil)
            remember?.state = .on
            alert.addButton(withTitle: String(localized: "Connect"))
        case .passphrase(let endpoint, let message):
            alert.messageText = String(localized: "Key passphrase for \(RemoteURL.displayName(endpoint))")
            alert.informativeText = message
            field = NSSecureTextField()
            alert.addButton(withTitle: String(localized: "Connect"))
        case .hostKey(let endpoint, let message):
            alert.alertStyle = .warning
            alert.messageText = String(localized: "The identity of \(endpoint.host) can’t be verified.")
            alert.informativeText = message
            alert.addButton(withTitle: String(localized: "Connect"))
        case .other(let endpoint, let message):
            alert.messageText = RemoteURL.displayName(endpoint)
            alert.informativeText = message
            field = NSTextField()
            alert.addButton(withTitle: String(localized: "OK"))
        }
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        if let field {
            field.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
            let stack = NSStackView(views: [field] + (remember.map { [$0] } ?? []))
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.frame = NSRect(x: 0, y: 0, width: 280, height: remember == nil ? 24 : 48)
            field.widthAnchor.constraint(equalToConstant: 280).isActive = true
            alert.accessoryView = stack
            alert.window.initialFirstResponder = field
        }
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        if case .hostKey = prompt { return PromptReply("yes") }
        return PromptReply(field?.stringValue ?? "", remember: remember?.state == .on)
    }
}

extension ArchiveScratch {
    /// Downloads a server file into a fresh folder; returns the copy.
    static func download(_ remote: RemoteLocation) async throws -> URL {
        let folder = try makeFolder()
        let copy = folder.appending(path: RemotePath.name(remote.path))
        try await RemoteConnections.shared.perform(on: remote.endpoint) { fs in
            try await fs.download(remote.path, to: copy, progress: { _ in })
        }
        return copy
    }
}

extension OperationsController {
    /// F5/F6 when the source or the destination is on a server.
    func transferRemote(_ kind: TransferKind, sources: [URL], destination: URL, mask: String, panel: PanelViewController) {
        if ArchivePath.split(sources[0].deletingLastPathComponent()) != nil || ArchivePath.split(destination) != nil {
            Task {
                await inform(String(localized: "The operation could not be completed."),
                             String(localized: "Copying between an archive and a server is not supported. Copy to a folder on disk first."))
            }
            return
        }
        let state = OperationState(title: kind == .copy ? String(localized: "Copying…") : String(localized: "Moving…"))
        let transfer = RemoteTransfer()
        perform(state) {
            let progress: RemoteTransfer.Progress = { p in Task { @MainActor in state.progress = p } }
            let conflict: RemoteTransfer.ConflictHandler = { conflict in await self.askConflict(conflict) }
            let report: TransferReport
            switch (RemoteURL.parse(sources[0]), RemoteURL.parse(destination)) {
            case (nil, let target?):
                report = try await transfer.upload(sources, to: target, kind: kind, nameMask: mask, progress: progress, conflict: conflict)
            case (_?, nil):
                report = try await transfer.download(sources.compactMap(RemoteURL.parse), to: destination, kind: kind,
                                                     nameMask: mask, progress: progress, conflict: conflict)
            case (_?, let target?):
                let scratch = try ArchiveScratch.makeFolder()
                defer { try? FileManager.default.removeItem(at: scratch) }
                report = try await transfer.transfer(sources.compactMap(RemoteURL.parse), to: target, kind: kind,
                                                     scratch: scratch, progress: progress, conflict: conflict)
            case (nil, nil):
                return
            }
            if !report.keptSources.isEmpty {
                await self.inform(String(localized: "Some sources were kept"),
                                  String(localized: "\(report.keptSources.count) item(s) were not removed, because they contain a link to a folder, were skipped or did not arrive completely."))
            }
            panel.model.deselectAll()
        }
    }

    /// F8 on a server: always permanent, so Cancel is the default button.
    func deleteOnServer(_ urls: [URL]) {
        let items = urls.compactMap(RemoteURL.parse)
        guard let endpoint = items.first?.endpoint else { return }
        Task {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = String(localized: "Delete \(Self.describe(urls)) on \(RemoteURL.displayName(endpoint))?")
            alert.informativeText = String(localized: "Files deleted on a server can’t be put back.")
            let confirm = alert.addButton(withTitle: String(localized: "Delete"))
            confirm.hasDestructiveAction = true
            confirm.keyEquivalent = ""
            alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\r"
            guard let window, await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
            let state = OperationState(title: String(localized: "Deleting…"))
            perform(state) {
                try await RemoteTransfer().delete(items, progress: { p in Task { @MainActor in state.progress = p } })
            }
        }
    }

    func makeDirectory(named name: String, on folder: RemoteLocation, panel: PanelViewController) {
        Task {
            do {
                guard !name.contains("/"), name != ".", name != ".." else { throw RemoteError.invalidName(name) }
                let path = RemotePath.join(folder.path, name)
                try await RemoteConnections.shared.perform(on: folder.endpoint) { try await $0.makeDirectory(path) }
                await panel.model.refresh()
                panel.focus(name: name)
            } catch {
                report(error)
            }
        }
    }

    func rename(_ item: RemoteLocation, to newName: String, panel: PanelViewController) {
        Task {
            do {
                guard !newName.contains("/"), newName != ".", newName != ".." else { throw RemoteError.invalidName(newName) }
                let target = RemotePath.join(RemotePath.parent(item.path), newName)
                try await RemoteConnections.shared.perform(on: item.endpoint) { try await $0.rename(item.path, to: target) }
                await panel.model.refresh()
                panel.focus(name: newName)
            } catch {
                report(error)
            }
        }
    }
}
