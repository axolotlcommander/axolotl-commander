public import Foundation

public enum SearchError: Error, Sendable, Equatable {
    /// Invalid content pattern (empty text, bad hex, bad regular expression).
    case invalidPattern(String)
    /// No search root given.
    case noRoots
    /// A file could not be read; the payload is a short system message.
    case cannotRead(String)
}

/// Everything the "Find files" dialog collects.
public struct SearchCriteria: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case all, files, folders }

    public struct ContentQuery: Codable, Sendable, Hashable {
        public var text: String
        public var caseSensitive: Bool
        public var wholeWords: Bool
        public var isHex: Bool
        public var isRegex: Bool

        public init(text: String, caseSensitive: Bool = false, wholeWords: Bool = false,
                    isHex: Bool = false, isRegex: Bool = false) {
            self.text = text
            self.caseSensitive = caseSensitive
            self.wholeWords = wholeWords
            self.isHex = isHex
            self.isRegex = isRegex
        }
    }

    public var namePattern: String
    public var roots: [String]
    public var subdirectories: Bool
    public var includeHidden: Bool
    public var searchPackages: Bool
    public var kind: Kind
    public var content: ContentQuery?
    /// Inclusive; when set, directories never match.
    public var minSize: Int64?
    public var maxSize: Int64?
    /// Inclusive modification time range.
    public var modifiedFrom: Date?
    public var modifiedTo: Date?
    /// `;` separated. An entry starting with `/` or `~` is an absolute path (that directory and
    /// everything below it is skipped); other entries are masks matched against directory names.
    public var excludedDirectories: String

    public init(
        namePattern: String = "",
        roots: [String] = [],
        subdirectories: Bool = true,
        includeHidden: Bool = false,
        searchPackages: Bool = false,
        kind: Kind = .all,
        content: ContentQuery? = nil,
        minSize: Int64? = nil,
        maxSize: Int64? = nil,
        modifiedFrom: Date? = nil,
        modifiedTo: Date? = nil,
        excludedDirectories: String = ""
    ) {
        self.namePattern = namePattern
        self.roots = roots
        self.subdirectories = subdirectories
        self.includeHidden = includeHidden
        self.searchPackages = searchPackages
        self.kind = kind
        self.content = content
        self.minSize = minSize
        self.maxSize = maxSize
        self.modifiedFrom = modifiedFrom
        self.modifiedTo = modifiedTo
        self.excludedDirectories = excludedDirectories
    }

    /// "a; ~/b ;a" → ["a", "<home>/b"]: split by `;`, trimmed, leading `~` expanded,
    /// empty entries and duplicates dropped (order kept).
    public static func parseRoots(_ text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in text.split(separator: ";", omittingEmptySubsequences: true) {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let path = expandTilde(trimmed)
            if seen.insert(path).inserted { result.append(path) }
        }
        return result
    }

    static func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return (path as NSString).expandingTildeInPath
    }
}
