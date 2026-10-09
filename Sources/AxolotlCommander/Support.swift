// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import UniformTypeIdentifiers

enum Format {
    private static let groupedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f
    }()

    static func grouped(_ value: Int64) -> String {
        groupedFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    static func error(_ error: any Error) -> String {
        if let remote = error as? RemoteError { return remote.message }
        return switch error as? PathError {
        case .empty?: String(localized: "Enter a path.")
        case .tooLong?: String(localized: "The path is too long; nothing was changed.")
        case .nameTooLong(let name)?: String(localized: "The name “\(name.prefix(40))…” is too long.")
        case .notFound?: String(localized: "The folder does not exist.")
        case .notADirectory?: String(localized: "The path is not a folder.")
        case nil: error.localizedDescription
        }
    }
}

/// Icons by type, not by file, so large folders stay fast.
enum IconCache {
    private static var byKey: [String: NSImage] = [:]

    static func icon(for item: FileItem) -> NSImage {
        let key: String
        let make: () -> NSImage
        if item.isParent {
            key = "#parent"
            make = { NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: String(localized: "Parent folder"))! }
        } else if NetworkPlaces.isNetwork(item.url) {
            key = "#server"
            make = { NSImage(systemSymbolName: "server.rack", accessibilityDescription: String(localized: "Server"))! }
        } else if item.isDirectory, item.url.deletingLastPathComponent().path == "/Volumes" {
            // Network volumes in the Network folder (and anything else listed from /Volumes).
            key = item.url.path
            make = { NSWorkspace.shared.icon(forFile: item.url.path) }
        } else if item.isPackage {
            key = item.url.path
            make = { NSWorkspace.shared.icon(forFile: item.url.path) }
        } else if item.isDirectory {
            key = item.isSymlink ? "#dirlink" : "#dir"
            make = { NSWorkspace.shared.icon(for: .folder) }
        } else {
            let ext = item.fileExtension.lowercased()
            key = "." + ext
            make = { NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data) }
        }
        if let cached = byKey[key] { return cached }
        let image = make()
        image.size = NSSize(width: 16, height: 16)
        byKey[key] = image
        return image
    }
}

/// Sheet with one text field (`secure`: a password field); returns nil on Cancel/Esc.
enum TextPrompt {
    static func ask(title: String, message: String, initial: String, secure: Bool = false,
                    in window: NSWindow?) async -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = secure ? NSSecureTextField(string: initial) : NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response: NSApplication.ModalResponse
        if let window {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        return response == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

extension URL {
    /// File path for display and storage, without the trailing "/" a directory URL carries.
    var displayPath: String {
        if NetworkPlaces.isNetwork(self) { return String(localized: "Network") }
        if let remote = RemoteURL.parse(self) { return RemoteURL.displayText(remote) }
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

enum PathInput {
    /// Typed location: a server address (`sftp://…`, any password ignored), a path on the
    /// server `base` is on, or a local path. With `absoluteIsLocal` (transfer targets, hot paths)
    /// "/…" is always on disk and only relative text stays on the server.
    static func resolve(_ text: String, relativeTo base: URL, absoluteIsLocal: Bool = false) throws -> URL {
        if let typed = RemoteURL.parse(typed: text) { return typed.location.url }
        if absoluteIsLocal, text.hasPrefix("/") { return try PathRules.resolve(text, relativeTo: base) }
        if let remote = RemoteURL.parse(base), !text.hasPrefix("~") {
            let path = text.hasPrefix("/") ? text : RemotePath.join(remote.path, text)
            return RemoteURL.make(remote.endpoint, path: RemotePath.normalize(path))
        }
        return try PathRules.resolve(text, relativeTo: base)
    }
}
