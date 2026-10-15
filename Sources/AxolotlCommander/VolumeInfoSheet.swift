// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// ⌃L: name, format, capacity and free space of the volume holding the panel's folder.
enum VolumeInfoSheet {
    static func show(for folder: URL, in window: NSWindow?) {
        // Read off the main thread: the volume may be a disk that is asleep or a server that stopped answering.
        Task {
            let values = await Task.detached { Values(read(folder)) }.value.values
            guard let values else { return NSSound.beep() }
            show(values, folder: folder, in: window)
        }
    }

    /// Resource values are only read after they arrived.
    private nonisolated struct Values: @unchecked Sendable {
        let values: URLResourceValues?
        init(_ values: URLResourceValues?) { self.values = values }
    }

    private nonisolated static func read(_ folder: URL) -> URLResourceValues? {
        let keys: Set<URLResourceKey> = [
            .volumeURLKey, .volumeLocalizedNameKey, .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeIsInternalKey,
            .volumeIsRemovableKey, .volumeIsReadOnlyKey, .volumeIsLocalKey, .volumeUUIDStringKey,
        ]
        return try? folder.resourceValues(forKeys: keys)
    }

    private static func show(_ values: URLResourceValues, folder: URL, in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = values.volumeLocalizedName ?? folder.lastPathComponent
        if let url = values.volume { alert.icon = FileIcons.shared.icon(forVolume: url, network: values.volumeIsLocal == false) }
        var lines: [String] = []
        func add(_ title: String, _ value: String?) { if let value, !value.isEmpty { lines.append("\(title): \(value)") } }
        add(String(localized: "Mounted at"), values.volume?.displayPath)
        add(String(localized: "Format"), values.volumeLocalizedFormatDescription)
        let total = values.volumeTotalCapacity.map(Int64.init)
        let free = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init)
        add(String(localized: "Capacity"), total.map { "\(Format.bytes($0)) (\(Format.grouped($0)))" })
        add(String(localized: "Available"), free.map { "\(Format.bytes($0)) (\(Format.grouped($0)))" })
        if let total, let free, total > 0 {
            add(String(localized: "Used"), "\(Format.bytes(total - free)) (\(Int((Double(total - free) / Double(total) * 100).rounded())) %)")
        }
        let kind = values.volumeIsLocal == false ? String(localized: "network")
            : values.volumeIsInternal == true ? String(localized: "internal")
            : values.volumeIsRemovable == true ? String(localized: "removable") : String(localized: "external")
        add(String(localized: "Kind"), kind + (values.volumeIsReadOnly == true ? ", " + String(localized: "read-only") : ""))
        add(String(localized: "UUID"), values.volumeUUIDString)
        alert.informativeText = lines.joined(separator: "\n")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
