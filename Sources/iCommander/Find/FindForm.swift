import AppKit
import CommanderCore
import Observation

/// The find dialog's fields. The last options and the three histories are kept
/// in UserDefaults; the folder to search comes from the active panel.
@Observable
final class FindForm {
    enum SizeUnit: Int64, CaseIterable, Identifiable {
        case bytes = 1, kilobytes = 1024, megabytes = 1_048_576, gigabytes = 1_073_741_824
        var id: Int64 { rawValue }
        var title: String {
            switch self {
            case .bytes: String(localized: "bytes")
            case .kilobytes: "KB"
            case .megabytes: "MB"
            case .gigabytes: "GB"
            }
        }
    }

    var name = ""
    var lookIn = ""
    var subdirectories = true
    var includeHidden = false
    var searchPackages = false
    var containing = ""
    var caseSensitive = false
    var wholeWords = false
    var hex = false { didSet { if hex { regex = false } } }
    var regex = false { didSet { if regex { hex = false } } }

    var showAdvanced = false
    var useMinSize = false
    var minSize: Int64 = 0
    var minUnit = SizeUnit.kilobytes
    var useMaxSize = false
    var maxSize: Int64 = 0
    var maxUnit = SizeUnit.kilobytes
    var useFrom = false
    var from = Calendar.current.startOfDay(for: .now)
    var useTo = false
    var to = Date.now
    var kind = SearchCriteria.Kind.all
    var excluded = ""

    var findDuplicates = false
    var duplicateName = true
    var duplicateSize = true
    var duplicateContent = false { didSet { if duplicateContent { duplicateSize = true } } }

    private(set) var nameHistory: CommandHistory
    private(set) var lookInHistory: CommandHistory
    private(set) var textHistory: CommandHistory

    /// Set by the window: whether a search runs, and what the buttons do.
    var isSearching = false
    @ObservationIgnored var onFind: () -> Void = {}
    @ObservationIgnored var onStop: () -> Void = {}
    @ObservationIgnored var onChooseFolder: () -> Void = {}

    private static let optionsKey = "find.options"

    init(directory: URL, showHidden: Bool) {
        nameHistory = Self.history("name")
        lookInHistory = Self.history("lookIn")
        textHistory = Self.history("text")
        lookIn = directory.displayPath
        includeHidden = showHidden
        if let data = UserDefaults.standard.data(forKey: Self.optionsKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            apply(saved)
        }
    }

    // MARK: Criteria

    /// Fails with a message when a field is invalid.
    func criteria() throws(FindFormError) -> SearchCriteria {
        let roots = SearchCriteria.parseRoots(lookIn)
        guard !roots.isEmpty else { throw .message(String(localized: "Enter the folder to search in.")) }
        var criteria = SearchCriteria(roots: roots)
        criteria.namePattern = name
        criteria.subdirectories = subdirectories
        criteria.includeHidden = includeHidden
        criteria.searchPackages = searchPackages
        if !containing.isEmpty {
            criteria.content = SearchCriteria.ContentQuery(text: containing, caseSensitive: caseSensitive,
                                            wholeWords: wholeWords, isHex: hex, isRegex: regex)
        }
        if showAdvanced {
            if useMinSize { criteria.minSize = minSize * minUnit.rawValue }
            if useMaxSize { criteria.maxSize = maxSize * maxUnit.rawValue }
            if useFrom { criteria.modifiedFrom = from }
            if useTo { criteria.modifiedTo = to }
            criteria.kind = kind
            criteria.excludedDirectories = excluded
        }
        if findDuplicates {
            guard duplicateName || duplicateSize else {
                throw .message(String(localized: "Choose what duplicates have in common."))
            }
            criteria.kind = .files
        }
        return criteria
    }

    var duplicateCriteria: DuplicateCriteria? {
        guard findDuplicates else { return nil }
        return DuplicateCriteria(sameName: duplicateName, sameSize: duplicateSize || duplicateContent,
                                 sameContent: duplicateContent)
    }

    /// Remembers the fields after a search starts.
    func commit() {
        if !name.isEmpty { nameHistory.add(name); Self.save(nameHistory, "name") }
        if !lookIn.isEmpty { lookInHistory.add(lookIn); Self.save(lookInHistory, "lookIn") }
        if !containing.isEmpty { textHistory.add(containing); Self.save(textHistory, "text") }
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.optionsKey) }
    }

    // MARK: Storage

    private static func history(_ key: String) -> CommandHistory {
        CommandHistory(entries: UserDefaults.standard.stringArray(forKey: "find.history.\(key)") ?? [])
    }

    private static func save(_ history: CommandHistory, _ key: String) {
        UserDefaults.standard.set(history.entries, forKey: "find.history.\(key)")
    }

    /// Options restored in the next find window (not the folder: that follows the panel).
    private struct Saved: Codable {
        var name: String
        var subdirectories: Bool
        var searchPackages: Bool
        var containing: String
        var caseSensitive: Bool
        var wholeWords: Bool
        var hex: Bool
        var regex: Bool
        var showAdvanced: Bool
        var kind: SearchCriteria.Kind
        var excluded: String
        var findDuplicates: Bool
        var duplicateName: Bool
        var duplicateSize: Bool
        var duplicateContent: Bool
    }

    private var saved: Saved {
        Saved(name: name, subdirectories: subdirectories, searchPackages: searchPackages, containing: containing,
              caseSensitive: caseSensitive, wholeWords: wholeWords, hex: hex, regex: regex,
              showAdvanced: showAdvanced, kind: kind, excluded: excluded, findDuplicates: findDuplicates,
              duplicateName: duplicateName, duplicateSize: duplicateSize, duplicateContent: duplicateContent)
    }

    private func apply(_ s: Saved) {
        name = s.name
        subdirectories = s.subdirectories
        searchPackages = s.searchPackages
        containing = s.containing
        caseSensitive = s.caseSensitive
        wholeWords = s.wholeWords
        hex = s.hex
        regex = s.regex
        showAdvanced = s.showAdvanced
        kind = s.kind
        excluded = s.excluded
        findDuplicates = s.findDuplicates
        duplicateName = s.duplicateName
        duplicateSize = s.duplicateSize
        duplicateContent = s.duplicateContent
    }
}

enum FindFormError: Error {
    case message(String)
}
