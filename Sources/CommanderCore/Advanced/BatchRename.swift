public import Foundation

/// Settings of the batch rename dialog.
public struct BatchRenameOptions: Codable, Sendable, Hashable {
    /// New-name mask: `*`, `?`, literals and `[...]` variables (see `BatchRename`).
    public var mask: String = "*.*"
    public var counterStart: Int = 1
    public var counterStep: Int = 1
    public var counterWidth: Int = 1
    public var search: String = ""
    public var replace: String = ""
    public var useRegex = false
    public var caseSensitive = false
    public var onlyFirst = false
    /// Search and replace touches the name part only (not the extension).
    public var excludeExtension = true
    public var caseChange = CaseChange(name: .keep, ext: .keep)
    /// Selected folders also contribute everything inside them (applies only when folders are selected).
    public var includeSubfolders = false
    /// Which of the nested items join the batch; the selected items themselves always do.
    public var subfolderItems = SubfolderItems.filesAndFolders

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case mask, counterStart, counterStep, counterWidth, search, replace, useRegex, caseSensitive, onlyFirst
        case excludeExtension, caseChange, includeSubfolders, subfolderItems
    }

    /// Every key is optional, so settings saved by an older version (or with an unknown value) still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BatchRenameOptions()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        mask = value(.mask, d.mask)
        counterStart = value(.counterStart, d.counterStart)
        counterStep = value(.counterStep, d.counterStep)
        counterWidth = value(.counterWidth, d.counterWidth)
        search = value(.search, d.search)
        replace = value(.replace, d.replace)
        useRegex = value(.useRegex, d.useRegex)
        caseSensitive = value(.caseSensitive, d.caseSensitive)
        onlyFirst = value(.onlyFirst, d.onlyFirst)
        excludeExtension = value(.excludeExtension, d.excludeExtension)
        caseChange = value(.caseChange, d.caseChange)
        includeSubfolders = value(.includeSubfolders, d.includeSubfolders)
        subfolderItems = value(.subfolderItems, d.subfolderItems)
    }
}

/// Which items found inside the selected folders take part in a batch rename.
public enum SubfolderItems: String, Codable, Sendable, Hashable, CaseIterable {
    case filesAndFolders, files, folders

    func includes(isDirectory: Bool) -> Bool {
        switch self {
        case .filesAndFolders: true
        case .files: !isDirectory
        case .folders: isDirectory
        }
    }
}

/// One object of the batch with the attributes the mask variables can use.
public struct RenameSource: Sendable, Hashable {
    public var url: URL
    public var isDirectory: Bool
    public var modified: Date?
    public var size: Int64?

    public init(url: URL, isDirectory: Bool, modified: Date? = nil, size: Int64? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.modified = modified
        self.size = size
    }
}

public enum BatchRenameError: Error, Equatable {
    case invalidRegex(String)
    case unknownVariable(String)
    case unterminatedVariable
}

/// Batch rename: mask, then search and replace, then change of case.
///
/// The mask follows `NameMask` (split at the last literal dot of the mask and of the name; in each part `*`
/// takes the rest of the original part and `?` the next character; an empty extension drops the dot; folders
/// have no extension) plus bracket variables: `[N]` name part, `[E]` extension, `[F]` whole original name,
/// `[P]` parent folder name, `[C]` counter (`[C:start]`, `[C:start:step]`, `[C:start:step:width]`),
/// `[D]` date yyyy-MM-dd, `[T]` time HHmmss, `[Y]` `[M]` `[d]` year, month, day of the modification date,
/// `[[` a literal `[`. Variable values are inserted literally; they never act as wildcards or dots.
public enum BatchRename {
    public static func newName(for source: RenameSource, index: Int, options: BatchRenameOptions) throws -> String {
        try Compiled(options).newName(for: source, index: index)
    }

    /// New names for all sources (index = position), validated by `RenamePlanner`.
    public static func preview(
        _ sources: [RenameSource],
        options: BatchRenameOptions,
        rules: (URL) -> NameRules = NameRules.forVolume(containing:),
        listing: (URL) throws -> [String] = RenamePlanner.defaultListing
    ) throws -> [RenamePlanEntry] {
        let compiled = try Compiled(options)
        var items: [RenameItem] = []
        items.reserveCapacity(sources.count)
        for (i, source) in sources.enumerated() {
            items.append(RenameItem(
                url: source.url, isDirectory: source.isDirectory,
                newName: try compiled.newName(for: source, index: i)))
        }
        return RenamePlanner.plan(items, rules: rules, listing: listing)
    }

    /// The selected sources, each followed (when it is a real folder) by everything inside it, depth first,
    /// names in Finder order; symbolic links are never followed. Nested items are filtered by `kinds` (folders
    /// are still descended into) and, unless `includeHidden`, hidden ones are left out together with their
    /// contents. Also returns the names found in every listed folder (keyed by path) for the planner.
    /// Returns early, with what it has, when the task is cancelled.
    public static func expand(
        _ selected: [RenameSource], kinds: SubfolderItems, includeHidden: Bool
    ) -> (sources: [RenameSource], listings: [String: [String]]) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey,
                                         .contentModificationDateKey, .fileSizeKey]
        var sources: [RenameSource] = []
        var listings: [String: [String]] = [:]
        func visit(_ folder: URL) {
            // By name, not `contentsOfDirectory(at:)`: that resolves symlinks in the path (/var → /private/var),
            // and the children must stay under the URL of their folder for depth ordering and undo.
            guard !Task.isCancelled,
                  let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
            listings[folder.path] = names
            for name in names.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                let child = folder.appendingPathComponent(name)
                let values = try? child.resourceValues(forKeys: keys)
                if !includeHidden, values?.isHidden == true || child.lastPathComponent.hasPrefix(".") { continue }
                let isDir = values?.isDirectory == true && values?.isSymbolicLink != true
                if kinds.includes(isDirectory: isDir) {
                    sources.append(RenameSource(
                        url: child, isDirectory: isDir, modified: values?.contentModificationDate,
                        size: isDir ? nil : values?.fileSize.map(Int64.init)))
                }
                if isDir { visit(child) }
            }
        }
        for source in selected {
            sources.append(source)
            let values = try? source.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true && values?.isSymbolicLink != true { visit(source.url) }
        }
        return (sources, listings)
    }
}

// MARK: - Implementation

private enum Variable {
    case name, ext, full, parent
    case counter(start: Int?, step: Int?, width: Int?)
    case date, time, year, month, day
}

private enum Token {
    case literal(Character)
    case star
    case question
    case variable(Variable)

    var isDot: Bool {
        if case .literal(".") = self { return true }
        return false
    }
}

private struct Compiled {
    let options: BatchRenameOptions
    let keepsName: Bool
    let tokens: [Token]
    let regex: NSRegularExpression?
    let template: String

    init(_ options: BatchRenameOptions) throws {
        self.options = options
        let mask = options.mask.trimmingCharacters(in: .whitespaces)
        keepsName = mask.isEmpty || mask == "*.*" || mask == "*"
        tokens = keepsName ? [] : try Self.tokenize(mask)
        if options.search.isEmpty {
            regex = nil
            template = ""
        } else {
            let caseOption: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
            do {
                if options.useRegex {
                    regex = try NSRegularExpression(pattern: options.search, options: caseOption)
                    template = options.replace
                } else {
                    regex = try NSRegularExpression(
                        pattern: NSRegularExpression.escapedPattern(for: options.search), options: caseOption)
                    template = NSRegularExpression.escapedTemplate(for: options.replace)
                }
            } catch {
                throw BatchRenameError.invalidRegex(error.localizedDescription)
            }
        }
    }

    static func tokenize(_ mask: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(mask)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            i += 1
            switch c {
            case "*": tokens.append(.star)
            case "?": tokens.append(.question)
            case "[":
                if i < chars.count, chars[i] == "[" {
                    tokens.append(.literal("["))
                    i += 1
                    continue
                }
                guard let close = chars[i...].firstIndex(of: "]") else {
                    throw BatchRenameError.unterminatedVariable
                }
                tokens.append(.variable(try variable(String(chars[i..<close]))))
                i = close + 1
            default: tokens.append(.literal(c))
            }
        }
        return tokens
    }

    private static func variable(_ body: String) throws -> Variable {
        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let name = parts[0]
        if name == "C" {
            guard parts.count <= 4 else { throw BatchRenameError.unknownVariable(body) }
            var values: [Int?] = []
            for p in parts.dropFirst() {
                if p.isEmpty { values.append(nil); continue }
                guard let v = Int(p) else { throw BatchRenameError.unknownVariable(body) }
                values.append(v)
            }
            func at(_ i: Int) -> Int? { i < values.count ? values[i] : nil }
            return .counter(start: at(0), step: at(1), width: at(2))
        }
        guard parts.count == 1 else { throw BatchRenameError.unknownVariable(body) }
        switch name {
        case "N": return .name
        case "E": return .ext
        case "F": return .full
        case "P": return .parent
        case "D": return .date
        case "T": return .time
        case "Y": return .year
        case "M": return .month
        case "d": return .day
        default: throw BatchRenameError.unknownVariable(body)
        }
    }

    func newName(for source: RenameSource, index: Int) throws -> String {
        let original = source.url.lastPathComponent
        let isDir = source.isDirectory
        var result = keepsName ? original : render(source, original: original, index: index)
        if let regex {
            result = replace(in: result, regex: regex, isDirectory: isDir)
        }
        return options.caseChange.apply(to: result, isDirectory: isDir)
    }

    private func render(_ source: RenameSource, original: String, index: Int) -> String {
        let (base, ext, _) = source.isDirectory ? (original, "", false) : NameParts.split(original)
        let context = Context(source: source, original: original, base: base, ext: ext, index: index, options: options)
        guard let dot = tokens.lastIndex(where: \.isDot) else {
            return context.render(tokens[...], from: Array(original))
        }
        let renderedBase = context.render(tokens[..<dot], from: Array(base))
        let renderedExt = context.render(tokens[(dot + 1)...], from: Array(ext))
        return renderedExt.isEmpty ? renderedBase : renderedBase + "." + renderedExt
    }

    private func replace(in name: String, regex: NSRegularExpression, isDirectory: Bool) -> String {
        let (base, ext, hasDot) = (options.excludeExtension && !isDirectory)
            ? NameParts.split(name) : (name, "", false)
        let replaced = substitute(in: base, regex: regex)
        return hasDot ? replaced + "." + ext : replaced
    }

    private func substitute(in text: String, regex: NSRegularExpression) -> String {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        if options.onlyFirst {
            guard let match = regex.firstMatch(in: text, options: [], range: full) else { return text }
            let replacement = regex.replacementString(for: match, in: text, offset: 0, template: template)
            return ns.replacingCharacters(in: match.range, with: replacement)
        }
        return regex.stringByReplacingMatches(in: text, options: [], range: full, withTemplate: template)
    }
}

private struct Context {
    let source: RenameSource
    let original: String
    let base: String
    let ext: String
    let index: Int
    let options: BatchRenameOptions

    /// Renders tokens against the original part: `*` takes the rest, `?` the next character,
    /// variable values are inserted literally.
    func render(_ tokens: ArraySlice<Token>, from part: [Character]) -> String {
        var out = ""
        var i = 0
        for token in tokens {
            switch token {
            case .literal(let c): out.append(c)
            case .star:
                if i < part.count { out.append(contentsOf: part[i...]) }
                i = part.count
            case .question:
                if i < part.count {
                    out.append(part[i])
                    i += 1
                }
            case .variable(let v): out += value(of: v)
            }
        }
        return out
    }

    private func value(of variable: Variable) -> String {
        switch variable {
        case .name: return base
        case .ext: return ext
        case .full: return original
        case .parent:
            let parent = source.url.deletingLastPathComponent().lastPathComponent
            return parent == "/" ? "" : parent
        case .counter(let start, let step, let width):
            let s = start ?? options.counterStart
            let st = step ?? options.counterStep
            let w = min(max(width ?? options.counterWidth, 1), 64)
            let value = s &+ index &* st
            let digits = String(value.magnitude)
            let padded = String(repeating: "0", count: max(0, w - digits.count)) + digits
            return value < 0 ? "-" + padded : padded
        case .date: return dateParts { String(format: "%04d-%02d-%02d", $0.year, $0.month, $0.day) }
        case .time: return dateParts { String(format: "%02d%02d%02d", $0.hour, $0.minute, $0.second) }
        case .year: return dateParts { String(format: "%04d", $0.year) }
        case .month: return dateParts { String(format: "%02d", $0.month) }
        case .day: return dateParts { String(format: "%02d", $0.day) }
        }
    }

    private struct Parts {
        var year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0
    }

    /// Modification date in the current time zone (empty when unknown). Digits are ASCII, as en_US_POSIX.
    private func dateParts(_ format: (Parts) -> String) -> String {
        guard let date = source.modified else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return format(Parts(
            year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0,
            hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0))
    }
}
