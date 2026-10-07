import AppKit
import CommanderCore

/// ⇧F7 / ⌘⇧G: path dialog with a history of entered folders (newest first).
enum GoToFolder {
    /// Returns the entered text, or nil on Cancel / Esc.
    static func ask(initial: String, in window: NSWindow?) async -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Go to Folder")
        alert.informativeText = String(localized: "Path (absolute, relative to this folder, or starting with ~):")
        alert.addButton(withTitle: String(localized: "Go"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: 380, height: 26))
        combo.stringValue = initial
        combo.addItems(withObjectValues: AppSettings.shared.recentPaths.paths)
        combo.completes = true
        combo.numberOfVisibleItems = 12
        combo.usesDataSource = false
        alert.accessoryView = combo
        alert.window.initialFirstResponder = combo
        let response: NSApplication.ModalResponse
        if let window {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        let text = combo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return response == .alertFirstButtonReturn && !text.isEmpty ? text : nil
    }
}
