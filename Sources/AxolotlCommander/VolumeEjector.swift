// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Ejects volumes and disconnects servers (spec 022), the one path behind ⌘E, the ⏏ of the volume
/// bar, its context menu and Disconnect…: nothing is ejected while the app's own work uses the
/// volume; the other volumes of the same disk are named first; panels and tabs leave the volume
/// before the eject; the system's reason is shown when it refuses.
@MainActor
enum VolumeEjector {
    /// Mount points being ejected now; the volume bar shows a spinner for them.
    private(set) static var busy: Set<URL> = []
    static let busyChanged = Notification.Name("VolumeEjectorBusyChanged")

    static func eject(_ targets: [EjectTarget], window: NSWindow?) {
        Task { await run(targets, window: window) }
    }

    private static func run(_ targets: [EjectTarget], window: NSWindow?) async {
        var servers: Set<RemoteEndpoint> = []
        var failures: [(name: String, reason: String)] = []
        for target in targets {
            switch target {
            case .server(let endpoint): servers.insert(endpoint)
            case .volume(let volume):
                if let reason = await eject(volume, window: window, askingFor: targets) {
                    failures.append((volume.name, reason))
                }
            }
        }
        if !servers.isEmpty { await ServerConnectionsUI.shared.disconnect(servers) }
        report(failures, window: window)
    }

    /// Nil when the volume is gone (ejected or cancelled count as done); otherwise why it is still
    /// mounted.
    private static func eject(_ volume: VolumeInfo, window: NSWindow?, askingFor targets: [EjectTarget]) async -> String? {
        let mounted = Volumes.mounted()
        // Gone meanwhile, or already being ejected: nothing to do.
        guard mounted.contains(where: { $0.url == volume.url }), !busy.contains(volume.url) else { return nil }
        guard Ejectability.canEject(volume) else { return String(localized: "This volume can’t be ejected.") }
        if let user = VolumeUse.blocking(volume.url, users: users()) {
            return String(localized: "It is in use: \(user.title)")
        }
        let chosen = Set(targets.compactMap { if case .volume(let v) = $0 { v.url } else { nil } })
        let others = Ejectability.otherVolumes(onDiskOf: volume, in: mounted).filter { !chosen.contains($0.url) }
        if !others.isEmpty {
            guard await confirmWholeDisk(volume, others: others, window: window) else { return nil }
            for other in others {
                if let user = VolumeUse.blocking(other.url, users: users()) {
                    return String(localized: "“\(other.name)” on the same disk is in use: \(user.title)")
                }
            }
        }
        for root in [volume] + others { leave(root.url) }
        busy.insert(volume.url)
        NotificationCenter.default.post(name: busyChanged, object: nil)
        defer {
            busy.remove(volume.url)
            NotificationCenter.default.post(name: busyChanged, object: nil)
        }
        let url = volume.url
        do {
            try await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }.value
            return nil
        } catch {
            let ns = error as NSError
            return [ns.localizedDescription, ns.localizedFailureReason].compactMap { $0 }.joined(separator: " ")
        }
    }

    /// The app's own work that reads or writes files: operations, searches, disk maps, folder sizes.
    private static func users() -> [VolumeUser] {
        NSApp.windows.flatMap { window -> [VolumeUser] in
            switch window.windowController {
            case let main as MainWindowController:
                main.operations.running.map { VolumeUser(title: $0.title, urls: $0.urls) }
                    + main.left.volumeUsers + main.right.volumeUsers
            case let find as FindWindowController: find.volumeUser.map { [$0] } ?? []
            case let map as DiskMapWindowController: map.volumeUser.map { [$0] } ?? []
            default: []
            }
        }
    }

    /// Every panel and tab of every window on the volume goes home and stops watching it.
    private static func leave(_ root: URL) {
        for case let main as MainWindowController in NSApp.windows.map(\.windowController) {
            main.left.leave(volume: root)
            main.right.leave(volume: root)
        }
    }

    private static func confirmWholeDisk(_ volume: VolumeInfo, others: [VolumeInfo], window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Eject all volumes of this disk?")
        let names = others.map { "“\($0.name)”" }.formatted(.list(type: .and))
        alert.informativeText = String(localized: "\(names) are on the same disk as “\(volume.name)” and will be ejected too.")
        alert.addButton(withTitle: String(localized: "Eject"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if let window { return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn }
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func report(_ failures: [(name: String, reason: String)], window: NSWindow?) {
        guard !failures.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if failures.count == 1 {
            alert.messageText = String(localized: "“\(failures[0].name)” could not be ejected.")
            alert.informativeText = failures[0].reason
        } else {
            alert.messageText = String(localized: "Some volumes could not be ejected.")
            alert.informativeText = failures.map { "“\($0.name)”: \($0.reason)" }.joined(separator: "\n")
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: nil) } else { alert.runModal() }
    }
}
