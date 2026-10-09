// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import NetFS

/// Opening a server listed in the Network folder: SMB and AFP are mounted through macOS (its own
/// login and share dialog, passwords from the Keychain) and the panel enters the share; SFTP opens
/// the Connect to Server dialog with the address filled in.
enum NetworkPlacesUI {
    @MainActor static func open(_ service: NetworkPlaces.Service, from panel: PanelViewController) {
        Task { @MainActor in
            do {
                let (host, port) = try await BonjourResolver.resolve(service)
                switch service.kind {
                case .sftp:
                    var draft = ConnectSheet.Draft()
                    draft.proto = .sftp
                    draft.host = host
                    draft.port = port == 22 ? "" : String(port)
                    ConnectSheet.show(for: panel, prefill: draft)
                case .smb, .afp:
                    let defaultPort = service.kind == .smb ? 445 : 548
                    var components = URLComponents()
                    components.scheme = service.kind.rawValue
                    components.host = host
                    if port != defaultPort { components.port = port }
                    guard let url = components.url else { return }
                    if let share = try await mount(url) { panel.go(to: share) }
                }
            } catch is CancellationError {
            } catch {
                NSSound.beep()
                panel.router?.operations.report(error)
            }
        }
    }

    /// Mounts `url` (no share: macOS asks for one) with the system's dialogs; the first mount point,
    /// or nil when the user cancelled.
    @MainActor private static func mount(_ url: URL) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            // kNAUIOptionKey / kNAUIOptionAllowUI (C macros, not imported into Swift).
            let openOptions = NSMutableDictionary(dictionary: ["UIOption": "AllowUI"])
            var request: AsyncRequestID?
            let status = NetFSMountURLAsync(url as CFURL, nil, nil, nil, openOptions, nil, &request, .main) { status, _, mountpoints in
                if status == 0, let first = (mountpoints as? [String])?.first {
                    continuation.resume(returning: URL(fileURLWithPath: first, isDirectory: true))
                } else if status == 0 || status == ECANCELED || status == Int32(userCanceledErr) {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(throwing: mountError(status))
                }
            }
            if status != 0 { continuation.resume(throwing: mountError(status)) }
        }
    }

    private static func mountError(_ status: Int32) -> NSError {
        status > 0 ? NSError(domain: NSPOSIXErrorDomain, code: Int(status)) : NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}
