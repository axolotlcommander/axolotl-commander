// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import AppKit
import CommanderCore
import SwiftUI

/// ⌘K / ⌃⇧F: saved connections on the left, the connection being edited on the right.
/// Pasting an address (`sftp://user:password@host:port/path`) fills in the fields.
struct ConnectSheet: View {
    struct Draft: Equatable {
        var name = ""
        var proto: RemoteProtocol = .sftp
        var host = ""
        var port = ""
        var user = ""
        var password = ""
        var remember = true
        var initialPath = ""
        var passive = true
        var encoding = ServerEncoding.auto

        init() {}

        init(_ profile: ConnectionProfile) {
            name = profile.name
            proto = profile.endpoint.proto
            host = profile.endpoint.host
            port = profile.endpoint.port.map(String.init) ?? ""
            user = profile.endpoint.user ?? ""
            initialPath = profile.initialPath
            passive = profile.passiveMode
            encoding = profile.encoding
        }

        var endpoint: RemoteEndpoint? {
            let host = host.trimmingCharacters(in: .whitespaces)
            guard !host.isEmpty else { return nil }
            let port = Int(port.trimmingCharacters(in: .whitespaces))
            guard port.map({ (1...65535).contains($0) }) ?? self.port.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return RemoteEndpoint(proto: proto, host: host, port: port, user: user.trimmingCharacters(in: .whitespaces))
        }

        func profile(id: UUID) -> ConnectionProfile? {
            endpoint.map {
                ConnectionProfile(id: id, name: name.trimmingCharacters(in: .whitespaces), endpoint: $0,
                                  initialPath: initialPath.trimmingCharacters(in: .whitespaces), passiveMode: passive,
                                  encoding: encoding)
            }
        }
    }

    @State private var profiles: [ConnectionProfile]
    @State private var selection: UUID?
    @State private var draft = Draft()
    @State private var address = ""
    @FocusState private var addressFocused: Bool
    let onConnect: (_ profile: ConnectionProfile, _ password: String?, _ remember: Bool) -> Void
    let onCancel: () -> Void

    init(onConnect: @escaping (ConnectionProfile, String?, Bool) -> Void, onCancel: @escaping () -> Void) {
        let saved = AppSettings.shared.connections
        _profiles = State(initialValue: saved)
        _selection = State(initialValue: saved.first?.id)
        _draft = State(initialValue: saved.first.map(Draft.init) ?? Draft())
        self.onConnect = onConnect
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to Server").font(.headline)
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(profiles) { profile in
                            Label(profile.title, systemImage: profile.endpoint.proto == .sftp ? "lock.shield" : "network")
                                .tag(profile.id)
                        }
                    }
                    .frame(width: 190)
                    HStack(spacing: 0) {
                        Button { newConnection() } label: { Image(systemName: "plus") }
                            .help(Text("New Connection"))
                        Button { deleteSelected() } label: { Image(systemName: "minus") }
                            .help(Text("Delete Connection"))
                            .disabled(selection == nil)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .padding(4)
                }
                .border(Color(nsColor: .separatorColor))

                Form {
                    TextField("Address:", text: $address, prompt: Text(verbatim: "sftp://user@server/path"))
                        .focused($addressFocused)
                        .onSubmit { applyAddress(); connect() }
                        .onChange(of: address) { _, _ in applyAddress() }
                    Divider()
                    TextField("Name:", text: $draft.name, prompt: Text("Optional"))
                    Picker("Protocol:", selection: $draft.proto) {
                        Text(verbatim: "SFTP").tag(RemoteProtocol.sftp)
                        Text(verbatim: "FTP").tag(RemoteProtocol.ftp)
                        Text("FTP with TLS").tag(RemoteProtocol.ftps)
                    }
                    .fixedSize()
                    TextField("Server:", text: $draft.host)
                    TextField("Port:", text: $draft.port, prompt: Text(verbatim: String(draft.proto.defaultPort)))
                        .frame(maxWidth: 160)
                        .help(draft.proto == .ftps ? String(localized: "Port 990 uses implicit TLS; other ports start TLS with AUTH TLS.") : "")
                    TextField("User:", text: $draft.user,
                              prompt: Text(draft.proto == .sftp ? "From SSH settings" : "Anonymous"))
                    SecureField("Password:", text: $draft.password, prompt: Text("Ask or use Keychain"))
                    Toggle("Remember password in Keychain", isOn: $draft.remember)
                    TextField("Folder:", text: $draft.initialPath, prompt: Text("Login folder"))
                    if draft.proto != .sftp {
                        Toggle("Passive mode", isOn: $draft.passive)
                        Picker("Encoding:", selection: $draft.encoding) {
                            ForEach(ServerEncoding.allCases, id: \.self) { encoding in
                                Text(encoding.localizedTitle).tag(encoding)
                            }
                        }
                        .fixedSize()
                    }
                }
                .frame(minWidth: 360)
            }
            HStack {
                Button("Save") { save() }.disabled(draft.endpoint == nil)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.endpoint == nil)
            }
        }
        .padding(20)
        .frame(width: 640, height: 450)
        .onAppear { addressFocused = true }
        .onChange(of: selection) { _, id in
            if let profile = profiles.first(where: { $0.id == id }) {
                draft = Draft(profile)
                address = ""
            }
        }
    }

    private func applyAddress() {
        guard let parsed = RemoteURL.parse(typed: address) else { return }
        let endpoint = parsed.location.endpoint
        draft.proto = endpoint.proto
        draft.host = endpoint.host
        draft.port = endpoint.port.map(String.init) ?? ""
        draft.user = endpoint.user ?? ""
        if let password = parsed.password { draft.password = password }
        draft.initialPath = parsed.location.path
    }

    private func newConnection() {
        selection = nil
        draft = Draft()
        address = ""
    }

    private func deleteSelected() {
        guard let selection else { return }
        profiles.removeAll { $0.id == selection }
        AppSettings.shared.connections = profiles
        newConnection()
    }

    private func save() {
        let id = selection ?? UUID()
        guard let profile = draft.profile(id: id) else { return }
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        AppSettings.shared.connections = profiles
        selection = id
        if draft.remember, !draft.password.isEmpty {
            try? KeychainPasswordStore().save(draft.password, for: profile.endpoint)
        }
    }

    private func connect() {
        guard let profile = draft.profile(id: selection ?? UUID()) else { return }
        onConnect(profile, draft.password.isEmpty ? nil : draft.password, draft.remember)
    }

    @MainActor
    static func show(for panel: PanelViewController) {
        guard let window = panel.view.window else { return }
        var sheetWindow: NSWindow?
        let close = {
            if let sheetWindow { window.endSheet(sheetWindow) }
        }
        let sheet = ConnectSheet(
            onConnect: { profile, password, remember in
                close()
                panel.connect(to: profile.location, password: password,
                              options: profile.connectOptions) { url in
                    if remember, let password {
                        try? KeychainPasswordStore().save(password, for: profile.endpoint)
                    }
                    AppSettings.shared.recentPaths.add(url.displayPath)
                }
            },
            onCancel: close)
        let host = NSWindow(contentViewController: NSHostingController(rootView: sheet))
        sheetWindow = host
        window.beginSheet(host, completionHandler: nil)
    }
}

/// F12: choose which open server connections to close.
struct DisconnectSheet: View {
    let endpoints: [RemoteEndpoint]
    @State var chosen: Set<RemoteEndpoint>
    let onDisconnect: (Set<RemoteEndpoint>) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disconnect").font(.headline)
            List(endpoints, id: \.self) { endpoint in
                Toggle(isOn: Binding(
                    get: { chosen.contains(endpoint) },
                    set: { if $0 { chosen.insert(endpoint) } else { chosen.remove(endpoint) } }
                )) {
                    Text(verbatim: "\(endpoint.proto.rawValue)://\(RemoteURL.displayName(endpoint))")
                }
            }
            .frame(height: 150)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Disconnect") { onDisconnect(chosen) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @MainActor
    static func show(for panel: PanelViewController) {
        guard let window = panel.view.window else { return }
        Task {
            let endpoints = await RemoteConnections.shared.connected
            guard !endpoints.isEmpty else {
                let alert = NSAlert()
                alert.messageText = String(localized: "No servers are connected.")
                _ = await alert.beginSheetModal(for: window)
                return
            }
            let current = panel.model.remote?.endpoint
            var sheetWindow: NSWindow?
            let close = {
                if let sheetWindow { window.endSheet(sheetWindow) }
            }
            let sheet = DisconnectSheet(
                endpoints: endpoints,
                chosen: current.map { endpoints.contains($0) ? [$0] : Set(endpoints) } ?? Set(endpoints),
                onDisconnect: { chosen in
                    close()
                    Task {
                        for endpoint in chosen { await RemoteConnections.shared.disconnect(endpoint) }
                        // Panels on a closed connection go home.
                        let panels = panel.router.map { [$0.left, $0.right] } ?? [panel]
                        for p in panels where p.model.remote.map({ chosen.contains($0.endpoint) }) == true {
                            p.go(to: FileManager.default.homeDirectoryForCurrentUser)
                        }
                    }
                },
                onCancel: close)
            let host = NSWindow(contentViewController: NSHostingController(rootView: sheet))
            sheetWindow = host
            await window.beginSheet(host)
        }
    }
}
