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
        switch error as? PathError {
        case .empty?: "Enter a path."
        case .tooLong?: "The path is too long; nothing was changed."
        case .nameTooLong(let name)?: "The name “\(name.prefix(40))…” is too long."
        case .notFound?: "The folder does not exist."
        case .notADirectory?: "The path is not a folder."
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
            make = { NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: "Parent folder")! }
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

/// Sheet with one text field; returns nil on Cancel/Esc.
enum TextPrompt {
    static func ask(title: String, message: String, initial: String, in window: NSWindow?) async -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: initial)
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
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
