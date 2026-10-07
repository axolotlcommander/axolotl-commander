import AppKit
import CommanderCore

/// Passwords of encrypted archives, kept in memory only and only while a panel shows the
/// archive (never on disk, in defaults or logs).
enum ArchivePasswords {
    private struct Viewer {
        weak var panel: AnyObject?
        var archive: URL
    }

    private static var known: [URL: String] = [:]
    private static var viewers: [Viewer] = []

    private static func key(_ archive: URL) -> URL { archive.standardizedFileURL }

    /// A panel now shows `archive` (nil: no archive); a password is forgotten once no panel shows its archive.
    static func panel(_ panel: AnyObject, showsArchive archive: URL?) {
        viewers.removeAll { $0.panel == nil || $0.panel === panel }
        if let archive { viewers.append(Viewer(panel: panel, archive: key(archive))) }
        let shown = Set(viewers.map(\.archive))
        known = known.filter { shown.contains($0.key) }
    }

    /// Runs `body` with the passphrases for `members` of `archive`. When an encrypted member
    /// needs a password (or the one given is wrong), asks for it on `window` and tries again.
    /// Cancel throws `ArchiveError.cancelled`, which callers treat as a silent abort.
    static func run<T>(_ archive: URL, members: [String], in window: NSWindow?,
                       _ body: ([String]) async throws -> T) async throws -> T {
        // The cached index tells cheaply whether anything needs a password at all.
        let index = try await ArchiveCatalog.shared.index(of: archive)
        guard index.hasEncryptedEntries, index.entries(under: members).contains(where: \.isEncrypted) else {
            return try await body([])
        }
        let key = key(archive)
        var password = known[key]
        var wrong = false
        while true {
            let passphrases = password.map { [$0] } ?? []
            do {
                try await ArchiveExtractor.verifyPassphrase(archive: archive, members: members, passphrases: passphrases)
                let result = try await body(passphrases)
                if let password, viewers.contains(where: { $0.panel != nil && $0.archive == key }) {
                    known[key] = password
                }
                return result
            } catch ArchiveError.passwordRequired {
                wrong = false
            } catch ArchiveError.wrongPassword {
                wrong = true
            }
            known[key] = nil
            password = await ask(archive.lastPathComponent, wrong: wrong, in: window)
            guard password != nil else { throw ArchiveError.cancelled }
        }
    }

    private static func ask(_ name: String, wrong: Bool, in window: NSWindow?) async -> String? {
        // On top of a progress sheet, if one is showing.
        var target = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        while let sheet = target?.attachedSheet { target = sheet }
        return await TextPrompt.ask(
            title: wrong
                ? String(localized: "The password for “\(name)” is wrong.")
                : String(localized: "“\(name)” is encrypted."),
            message: String(localized: "Password:"), initial: "", secure: true, in: target)
    }
}
