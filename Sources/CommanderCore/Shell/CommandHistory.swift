import Foundation

/// Command line history, newest first. Passwords are scrubbed before storing.
public struct CommandHistory: Codable, Equatable, Sendable {
    public static let limit = 30
    public private(set) var entries: [String]

    public init(entries: [String] = []) {
        self.entries = Array(entries.prefix(Self.limit))
    }

    /// Trims whitespace; ignores empty; stores `Credentials.scrub(command)`; an equal older entry
    /// moves to the front (no duplicates); keeps at most `limit`.
    public mutating func add(_ command: String) {
        let text = Credentials.scrub(command.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else { return }
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }
}

/// Shell-like ↑/↓ browsing over a history snapshot.
public struct HistoryBrowser: Sendable {
    private let entries: [String]
    private var index: Int?
    private var draft = ""

    public init(_ history: CommandHistory) {
        entries = history.entries
    }

    /// First call saves `current` as draft and returns the newest entry; then older ones; nil at the end.
    public mutating func older(current: String) -> String? {
        guard !entries.isEmpty else { return nil }
        guard let i = index else {
            draft = current
            index = 0
            return entries[0]
        }
        guard i + 1 < entries.count else { return nil }
        index = i + 1
        return entries[i + 1]
    }

    /// Goes back towards newest; past the newest returns the saved draft; nil when not browsing.
    public mutating func newer() -> String? {
        guard let i = index else { return nil }
        if i == 0 {
            index = nil
            return draft
        }
        index = i - 1
        return entries[i - 1]
    }
}
