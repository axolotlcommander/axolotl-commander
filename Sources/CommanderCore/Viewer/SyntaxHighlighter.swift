// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation

// MARK: - Public API

/// Token categories produced by `SyntaxHighlighter`. Text outside any span is plain.
public enum SyntaxTokenKind: String, Sendable, CaseIterable {
    case keyword, type, string, number, comment, preprocessor, tag, attribute, variable
}

/// A highlighted range; `range` is in UTF-16 offsets, so it maps 1:1 onto `NSString`/`NSTextStorage`.
public struct SyntaxSpan: Sendable, Equatable {
    public let range: NSRange
    public let kind: SyntaxTokenKind

    public init(range: NSRange, kind: SyntaxTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// A language the highlighter knows. Look one up with `forFile(named:)` or pick from `all`.
public struct SyntaxLanguage: Sendable, Hashable, Identifiable {
    public let id: String
    /// Display name, e.g. "Swift".
    public let name: String
}

extension SyntaxLanguage {
    /// All supported languages, sorted by display name.
    public static let all: [SyntaxLanguage] = SyntaxEngine.definitions
        .map { SyntaxLanguage(id: $0.id, name: $0.name) }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }

    /// Language by file extension (case-insensitive) or well-known full name (`Makefile`, `.bashrc`…).
    /// `nil` for unknown types and plain text (`.txt`, `.log`, no extension).
    public static func forFile(named name: String) -> SyntaxLanguage? {
        let base = (name.split(separator: "/").last.map(String.init) ?? name).lowercased()
        var id = SyntaxEngine.idsByFileName[base]
        if id == nil, base.hasPrefix("dockerfile.") || base.hasPrefix("makefile.") {
            id = base.hasPrefix("d") ? "dockerfile" : "makefile"
        }
        if id == nil, let dot = base.lastIndex(of: ".") {
            id = SyntaxEngine.idsByExtension[String(base[base.index(after: dot)...])]
        }
        guard let id, let def = SyntaxEngine.definitionsByID[id] else { return nil }
        return SyntaxLanguage(id: def.id, name: def.name)
    }

    /// Internal lookup by identifier.
    static func forID(_ id: String) -> SyntaxLanguage? {
        SyntaxEngine.definitionsByID[id].map { SyntaxLanguage(id: $0.id, name: $0.name) }
    }
}

/// Data-driven lexer producing colour spans for text viewers.
public enum SyntaxHighlighter {
    /// Spans sorted by location, never empty or overlapping. Stops early (returning what it has)
    /// when the current task is cancelled.
    public static func spans(in text: String, language: SyntaxLanguage) -> [SyntaxSpan] {
        guard let def = SyntaxEngine.definitionsByID[language.id] else { return [] }
        let utf16 = Array(text.utf16)
        if utf16.isEmpty { return [] }
        return utf16.withUnsafeBufferPointer { SyntaxEngine.lex(def, $0, 0, $0.count) }
    }
}

// MARK: - Character helpers

@inline(__always) private func ch(_ c: Unicode.Scalar) -> UInt16 { UInt16(truncatingIfNeeded: c.value) }
@inline(__always) private func isDigit(_ c: UInt16) -> Bool { c &- 48 < 10 }
@inline(__always) private func isAlpha(_ c: UInt16) -> Bool { let l = c | 0x20; return l >= 97 && l <= 122 }
@inline(__always) private func isHex(_ c: UInt16) -> Bool { let l = c | 0x20; return isDigit(c) || (l >= 97 && l <= 102) }
@inline(__always) private func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 || c == 0x0C }
@inline(__always) private func isNewline(_ c: UInt16) -> Bool { c == 0x0A || c == 0x0D }
@inline(__always) private func isWS(_ c: UInt16) -> Bool { isSpace(c) || isNewline(c) }
@inline(__always) private func lower(_ c: UInt16) -> UInt16 { (c >= 65 && c <= 90) ? c + 32 : c }

private func units(_ s: String) -> [UInt16] { Array(s.utf16) }

private func words(_ s: String) -> Set<String> { Set(s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)) }

// MARK: - Engine

/// Language definitions, registry and the lexers behind `SyntaxHighlighter`.
enum SyntaxEngine {
    typealias Buf = UnsafeBufferPointer<UInt16>

    enum Family: Sendable { case code, markup, css, json, yaml, ini, markdown, diff }

    enum CharMode: Sendable { case none, charOnly, charOrLifetime }

    struct LineCommentRule: Sendable {
        var prefix: [UInt16]
        var caseInsensitive = false
        /// Only blanks (and `@`) may precede the marker on its line.
        var lineStartOnly = false
        /// The marker must not be followed by an identifier character (`REM`).
        var wordEnd = false
        /// The marker only starts a comment at a word boundary (shell `#`).
        var needsBoundary = false
    }

    struct BlockCommentRule: Sendable {
        var open: [UInt16]
        var close: [UInt16]
        var nests = false
        var kind: SyntaxTokenKind = .comment
        var lineStartOnly = false
    }

    struct StringRule: Sendable {
        var open: [UInt16]
        var close: [UInt16]
        var escape: UInt16 = 0
        var doubled = false
        var multiline = false
        var interpolation = false
    }

    struct CodeRules: Sendable {
        var lineComments: [LineCommentRule] = []
        var blockComments: [BlockCommentRule] = []
        var strings: [StringRule] = []
        var markers: [[UInt16]] = []
        var keywords: Set<String> = []
        var types: Set<String> = []
        var lineStartKeywords: Set<String> = []
        var caseInsensitive = false
        var preprocessorLine = false
        var hashDirective = false
        var rustAttributes = false
        var atKind: SyntaxTokenKind?
        var atLineStartOnly = false
        var sigils: [UInt16] = []
        var sigilSpecials: [UInt16] = []
        var sigilSingleLetter = false
        var sigilBraced = true
        var sigilParen = false
        var sigilScope = false
        var sigilPrefixBrace = false
        var percentVariables = false
        var stringPrefixes: Set<String> = []
        var rawPrefixes: Set<String> = []
        var charMode: CharMode = .none
        var identStartExtra: [UInt16] = []
        var identContinueExtra: [UInt16] = []
        var longBrackets = false
        var haskellDashes = false
        var targetLines = false

        // Derived by `finalize()`.
        var special = [Bool](repeating: false, count: 128)
        var identFlags = [UInt8](repeating: 0, count: 128)
        var maxWord = 0
        var minWord = 1

        mutating func line(_ prefix: String, ci: Bool = false, lineStart: Bool = false, wordEnd: Bool = false,
                           boundary: Bool = false) {
            lineComments.append(LineCommentRule(
                prefix: units(ci ? prefix.lowercased() : prefix), caseInsensitive: ci,
                lineStartOnly: lineStart, wordEnd: wordEnd, needsBoundary: boundary))
        }

        mutating func block(_ open: String, _ close: String, nests: Bool = false,
                            kind: SyntaxTokenKind = .comment, lineStart: Bool = false) {
            blockComments.append(BlockCommentRule(
                open: units(open), close: units(close), nests: nests, kind: kind, lineStartOnly: lineStart))
        }

        mutating func string(_ open: String, close: String? = nil, esc: Unicode.Scalar? = "\\", doubled: Bool = false,
                             multi: Bool = false, interp: Bool = false) {
            strings.append(StringRule(
                open: units(open), close: units(close ?? open), escape: esc.map(ch) ?? 0,
                doubled: doubled, multiline: multi, interpolation: interp))
        }

        mutating func kw(_ list: String) { keywords.formUnion(words(list)) }
        mutating func ty(_ list: String) { types.formUnion(words(list)) }

        mutating func finalize() {
            if caseInsensitive {
                keywords = Set(keywords.map { $0.lowercased() })
                types = Set(types.map { $0.lowercased() })
                lineStartKeywords = Set(lineStartKeywords.map { $0.lowercased() })
            }
            keywords.subtract(types)
            let all = keywords.union(types).union(lineStartKeywords)
            maxWord = all.map { $0.utf16.count }.max() ?? 0
            minWord = all.map { $0.utf16.count }.min() ?? 1
            strings.sort { $0.open.count > $1.open.count }

            var sp = [Bool](repeating: false, count: 128)
            func mark(_ p: [UInt16]) {
                guard let f = p.first, f < 128 else { return }
                sp[Int(f)] = true
                if f >= 97 && f <= 122 { sp[Int(f) - 32] = true }
            }
            func mark(_ c: UInt16) { if c < 128 { sp[Int(c)] = true } }
            for l in lineComments { mark(l.prefix) }
            for b in blockComments { mark(b.open) }
            for s in strings { mark(s.open) }
            for m in markers { mark(m) }
            if preprocessorLine || hashDirective || rustAttributes { mark(ch("#")) }
            if atKind != nil { mark(ch("@")) }
            for c in sigils { mark(c) }
            if percentVariables { mark(ch("%")); mark(ch("!")) }
            if charMode != .none { mark(ch("'")) }
            if longBrackets { mark(ch("[")) }
            special = sp

            var f = [UInt8](repeating: 0, count: 128)
            for c in 0..<128 {
                let u = UInt16(c)
                if isAlpha(u) || u == ch("_") { f[c] = 3 } else if isDigit(u) { f[c] = 2 }
            }
            for c in identStartExtra where c < 128 { f[Int(c)] |= 3 }
            for c in identContinueExtra where c < 128 { f[Int(c)] |= 2 }
            identFlags = f
        }
    }

    struct Definition: Sendable {
        let id: String
        let name: String
        let extensions: [String]
        let fileNames: [String]
        let family: Family
        var code = CodeRules()
        /// Markup: highlight `<script>`/`<style>` contents.
        var embedScripts = false
        /// CSS: `//` line comments (SCSS, LESS).
        var cssLineComments = false
        /// CSS: unknown `@name` is a LESS variable.
        var cssLess = false

        init(_ id: String, _ name: String, ext: String, files: [String] = [], family: Family) {
            self.id = id
            self.name = name
            self.extensions = ext.split(separator: " ").map(String.init)
            self.fileNames = files
            self.family = family
        }
    }

    // MARK: Registry

    static let definitions: [Definition] = makeDefinitions()

    static let definitionsByID: [String: Definition] = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

    static let idsByExtension: [String: String] = {
        var m: [String: String] = [:]
        for d in definitions { for e in d.extensions { m[e] = d.id } }
        return m
    }()

    static let idsByFileName: [String: String] = {
        var m: [String: String] = [:]
        for d in definitions { for n in d.fileNames { m[n.lowercased()] = d.id } }
        return m
    }()

    static func lex(_ d: Definition, _ s: Buf, _ lo: Int, _ hi: Int) -> [SyntaxSpan] {
        switch d.family {
        case .code:
            var l = CodeLexer(s, lo, hi, d.code)
            return l.run()
        case .markup:
            var l = MarkupLexer(s, lo, hi, embed: d.embedScripts)
            return l.run()
        case .css:
            var l = CSSLexer(s, lo, hi, lineComments: d.cssLineComments, less: d.cssLess)
            return l.run()
        case .json:
            var l = JSONLexer(s, lo, hi)
            return l.run()
        case .yaml:
            var l = YAMLLexer(s, lo, hi)
            return l.run()
        case .ini:
            var l = INILexer(s, lo, hi)
            return l.run()
        case .markdown:
            var l = MarkdownLexer(s, lo, hi)
            return l.run()
        case .diff:
            var l = DiffLexer(s, lo, hi)
            return l.run()
        }
    }

    // MARK: Shared helpers

    struct SpanWriter {
        var spans: [SyntaxSpan] = []
        var lastEnd = 0

        mutating func add(_ a: Int, _ b: Int, _ kind: SyntaxTokenKind) {
            guard b > a, a >= lastEnd else { return }
            spans.append(SyntaxSpan(range: NSRange(location: a, length: b - a), kind: kind))
            lastEnd = b
        }

        mutating func append(_ more: [SyntaxSpan]) {
            for sp in more { add(sp.range.location, sp.range.location + sp.range.length, sp.kind) }
        }
    }

    static func lineEnd(_ s: Buf, _ from: Int, _ hi: Int) -> Int {
        var j = from
        while j < hi, !isNewline(s[j]) { j += 1 }
        return j
    }

    static func nextLine(_ s: Buf, _ le: Int, _ hi: Int) -> Int {
        if le + 1 < hi, s[le] == 0x0D, s[le + 1] == 0x0A { return le + 2 }
        return min(le + 1, hi)
    }
}

// MARK: - Code lexer

extension SyntaxEngine {
    /// Generic lexer for C-like, scripting and other source languages.
    struct CodeLexer {
        let s: Buf
        let lo: Int
        let hi: Int
        let r: CodeRules
        var out = SpanWriter()
        var i: Int
        var regionEnd = 0

        init(_ s: Buf, _ lo: Int, _ hi: Int, _ rules: CodeRules) {
            self.s = s
            self.lo = lo
            self.hi = hi
            self.r = rules
            self.i = lo
        }

        @inline(__always) func at(_ j: Int) -> UInt16 { (j >= lo && j < hi) ? s[j] : 0 }
        @inline(__always) func isIdentStart(_ c: UInt16) -> Bool { c >= 128 || (c != 0 && r.identFlags[Int(c)] & 1 != 0) }
        @inline(__always) func isIdentCont(_ c: UInt16) -> Bool { c >= 128 || (c != 0 && r.identFlags[Int(c)] & 2 != 0) }

        func matches(_ p: [UInt16], _ j: Int, ci: Bool = false) -> Bool {
            if j < lo || j + p.count > hi { return false }
            for k in 0..<p.count {
                let c = s[j + k]
                if (ci ? lower(c) : c) != p[k] { return false }
            }
            return true
        }

        /// Only blanks and `@` precede `j` on its line (optionally one `-` for `-include`).
        func atLineStart(_ j: Int, allowDash: Bool = false) -> Bool {
            var k = j - 1
            if allowDash, k >= lo, s[k] == ch("-") { k -= 1 }
            while k >= lo, isSpace(s[k]) || s[k] == ch("@") { k -= 1 }
            return k < lo || isNewline(s[k])
        }

        mutating func run() -> [SyntaxSpan] {
            var nextCheck = lo + 65536
            if r.targetLines { detectTarget(lo) }
            while i < hi {
                if i >= nextCheck {
                    if Task.isCancelled { break }
                    nextCheck = i + 65536
                }
                let c = s[i]
                if c == 0x20 || c == 0x09 { i += 1; continue }
                if c == 0x0A {
                    i += 1
                    if r.targetLines { detectTarget(i) }
                    continue
                }
                if i < regionEnd, lexTargetRegion(c) { continue }
                if c < 128 {
                    if r.special[Int(c)], lexSpecial(c) { continue }
                    if r.identFlags[Int(c)] & 1 != 0 { lexIdentifier(); continue }
                    if isDigit(c) { lexNumber(); continue }
                    i += 1
                } else {
                    lexIdentifier()
                }
            }
            return out.spans
        }

        // MARK: Specials

        mutating func lexSpecial(_ c: UInt16) -> Bool {
            if !r.lineComments.isEmpty, lexLineComment(c) { return true }
            if !r.blockComments.isEmpty, lexBlockComment(c) { return true }
            if !r.strings.isEmpty, lexString(at: i, start: i) { return true }
            if !r.markers.isEmpty, lexMarker() { return true }
            switch c {
            case ch("#"):
                if r.preprocessorLine, atLineStart(i) { lexPreprocessorLine(); return true }
                if r.hashDirective { return lexHashDirective() }
                if r.rustAttributes { return lexRustAttribute() }
            case ch("@"):
                if r.atKind != nil { return lexAt() }
                if r.sigils.contains(c) { return lexSigil(c) }
            case ch("$"):
                if r.sigils.contains(c) { return lexSigil(c) }
            case ch("%"), ch("!"):
                if r.percentVariables { return lexBatchVariable(c) }
            case ch("'"):
                if r.charMode != .none { return lexApostrophe() }
            case ch("["):
                if r.longBrackets, let level = longBracketLevel(i) {
                    lexLongBracket(start: i, open: i, level: level, kind: .string)
                    return true
                }
            default:
                break
            }
            return false
        }

        mutating func lexLineComment(_ c: UInt16) -> Bool {
            for lc in r.lineComments {
                let p = lc.prefix
                if (lc.caseInsensitive ? lower(c) : c) != p[0] { continue }
                if !matches(p, i, ci: lc.caseInsensitive) { continue }
                if lc.lineStartOnly, !atLineStart(i) { continue }
                if lc.wordEnd, isIdentCont(at(i + p.count)) { continue }
                if lc.needsBoundary, i > lo {
                    let prev = s[i - 1]
                    if !(isWS(prev) || prev == ch(";") || prev == ch("&") || prev == ch("|") || prev == ch("(")) { continue }
                }
                if r.haskellDashes, p.count == 2 {
                    var k = i
                    while k < hi, s[k] == ch("-") { k += 1 }
                    if isHaskellSymbol(at(k)) || (i > lo && isHaskellSymbol(s[i - 1])) { continue }
                }
                if r.longBrackets, p.count == 2, at(i + 2) == ch("["), let level = longBracketLevel(i + 2) {
                    lexLongBracket(start: i, open: i + 2, level: level, kind: .comment)
                    return true
                }
                let end = lineEnd(s, i, hi)
                out.add(i, end, .comment)
                i = end
                return true
            }
            return false
        }

        func isHaskellSymbol(_ c: UInt16) -> Bool {
            guard c != 0, c < 128 else { return false }
            return "!#$%&*+./<=>?@\\^|~:-".utf16.contains(c)
        }

        func lineEnd(_ s: Buf, _ from: Int, _ hi: Int) -> Int { SyntaxEngine.lineEnd(s, from, hi) }

        mutating func lexBlockComment(_ c: UInt16) -> Bool {
            for b in r.blockComments where b.open[0] == c {
                if !matches(b.open, i) { continue }
                if b.lineStartOnly, !atLineStart(i) { continue }
                var j = i + b.open.count
                var depth = 1
                let closeFirst = b.close[0]
                while j < hi {
                    let d = s[j]
                    if b.nests, d == b.open[0], matches(b.open, j) {
                        depth += 1
                        j += b.open.count
                        continue
                    }
                    if d == closeFirst, matches(b.close, j) {
                        depth -= 1
                        j += b.close.count
                        if depth == 0 { break }
                        continue
                    }
                    j += 1
                }
                let end = min(j, hi)
                out.add(i, end, b.kind)
                i = end
                return true
            }
            return false
        }

        mutating func lexMarker() -> Bool {
            for m in r.markers where matches(m, i) {
                out.add(i, i + m.count, .preprocessor)
                i += m.count
                return true
            }
            return false
        }

        // MARK: Strings

        mutating func lexString(at j: Int, start: Int) -> Bool {
            let c = at(j)
            for rule in r.strings where rule.open[0] == c && matches(rule.open, j) {
                lexString(rule, start: start, from: j + rule.open.count)
                return true
            }
            return false
        }

        mutating func lexString(_ rule: StringRule, start: Int, from: Int) {
            var j = from
            let close = rule.close
            let first = close[0]
            let clen = close.count
            let esc = rule.escape
            let multi = rule.multiline
            while j < hi {
                let c = s[j]
                if c == first, clen == 1 || matches(close, j) {
                    if rule.doubled, clen == 1, at(j + 1) == first { j += 2; continue }
                    j += clen
                    out.add(start, j, .string)
                    i = j
                    return
                }
                if esc != 0, c == esc {
                    if rule.interpolation, at(j + 1) == ch("(") {
                        j = skipInterpolation(j + 2, multi)
                    } else if at(j + 1) == 0x0D, at(j + 2) == 0x0A {
                        j += 3
                    } else {
                        j += 2
                    }
                    continue
                }
                if !multi, isNewline(c) { break }
                j += 1
            }
            let end = min(j, hi)
            out.add(start, end, .string)
            i = end
        }

        /// Skips a Swift `\( … )` interpolation, returning the index after its closing paren.
        func skipInterpolation(_ from: Int, _ multi: Bool) -> Int {
            var depth = 1
            var k = from
            while k < hi, depth > 0 {
                let c = s[k]
                if c == ch("(") {
                    depth += 1
                } else if c == ch(")") {
                    depth -= 1
                } else if c == ch("\"") {
                    k += 1
                    while k < hi, s[k] != ch("\""), multi || !isNewline(s[k]) {
                        if s[k] == ch("\\") { k += 1 }
                        k += 1
                    }
                } else if !multi, isNewline(c) {
                    return k
                }
                k += 1
            }
            return min(k, hi)
        }

        /// Raw string (`#"…"#`, `r#"…"#`): `quote` is the index of the opening `"`.
        mutating func lexRaw(start: Int, quote q: Int, hashes h: Int, swift: Bool) {
            let triple = swift && at(q + 1) == ch("\"") && at(q + 2) == ch("\"")
            let qlen = triple ? 3 : 1
            let multi = triple || !swift
            var j = q + qlen
            while j < hi {
                let c = s[j]
                if c == ch("\"") {
                    var ok = true
                    for k in 0..<qlen where at(j + k) != ch("\"") { ok = false }
                    if ok { for k in 0..<h where at(j + qlen + k) != ch("#") { ok = false } }
                    if ok {
                        j += qlen + h
                        out.add(start, j, .string)
                        i = j
                        return
                    }
                }
                if swift, c == ch("\\") {
                    var ok = true
                    for k in 0..<h where at(j + 1 + k) != ch("#") { ok = false }
                    if ok { j += h + 2; continue }
                }
                if !multi, isNewline(c) { break }
                j += 1
            }
            let end = min(j, hi)
            out.add(start, end, .string)
            i = end
        }

        mutating func lexApostrophe() -> Bool {
            let j = i + 1
            let c = at(j)
            if c == ch("\\") {
                var k = j + 2
                while k < hi, k < j + 12, s[k] != ch("'"), !isNewline(s[k]) { k += 1 }
                if at(k) == ch("'") {
                    out.add(i, k + 1, .string)
                    i = k + 1
                    return true
                }
            } else if c != 0, c != ch("'"), !isNewline(c) {
                let w = (c >= 0xD800 && c < 0xDC00) ? 2 : 1
                if at(j + w) == ch("'") {
                    out.add(i, j + w + 1, .string)
                    i = j + w + 1
                    return true
                }
            }
            if r.charMode == .charOrLifetime, isIdentStart(c) {
                var k = j
                while isIdentCont(at(k)) { k += 1 }
                out.add(i, k, .type)
                i = k
                return true
            }
            return false
        }

        // MARK: Long brackets (Lua)

        func longBracketLevel(_ j: Int) -> Int? {
            guard at(j) == ch("[") else { return nil }
            var k = j + 1
            while at(k) == ch("=") { k += 1 }
            return at(k) == ch("[") ? k - j - 1 : nil
        }

        mutating func lexLongBracket(start: Int, open: Int, level: Int, kind: SyntaxTokenKind) {
            var j = open + level + 2
            while j < hi {
                if s[j] == ch("]") {
                    var k = j + 1
                    while at(k) == ch("="), k - j - 1 < level { k += 1 }
                    if k - j - 1 == level, at(k) == ch("]") {
                        j = k + 1
                        out.add(start, j, kind)
                        i = j
                        return
                    }
                }
                j += 1
            }
            out.add(start, hi, kind)
            i = hi
        }

        // MARK: Preprocessor, attributes, variables

        mutating func lexPreprocessorLine() {
            var j = i
            while j < hi {
                if isNewline(s[j]) {
                    if j > lo, s[j - 1] == ch("\\") {
                        if s[j] == 0x0D, at(j + 1) == 0x0A { j += 1 }
                        j += 1
                        continue
                    }
                    break
                }
                j += 1
            }
            out.add(i, j, .preprocessor)
            i = j
        }

        mutating func lexHashDirective() -> Bool {
            var h = 0
            while at(i + h) == ch("#") { h += 1 }
            if at(i + h) == ch("\"") {
                lexRaw(start: i, quote: i + h, hashes: h, swift: true)
                return true
            }
            if h == 1, isIdentStart(at(i + 1)) {
                var k = i + 2
                while isIdentCont(at(k)) { k += 1 }
                out.add(i, k, .preprocessor)
                i = k
                return true
            }
            return false
        }

        mutating func lexRustAttribute() -> Bool {
            var j = i + 1
            if at(j) == ch("!") { j += 1 }
            guard at(j) == ch("[") else { return false }
            var depth = 0
            var k = j
            while k < hi, k - i < 2000 {
                let c = s[k]
                if c == ch("[") {
                    depth += 1
                } else if c == ch("]") {
                    depth -= 1
                    if depth == 0 {
                        out.add(i, k + 1, .preprocessor)
                        i = k + 1
                        return true
                    }
                } else if c == ch("\"") {
                    k += 1
                    while k < hi, s[k] != ch("\""), !isNewline(s[k]) {
                        if s[k] == ch("\\") { k += 1 }
                        k += 1
                    }
                }
                k += 1
            }
            return false
        }

        mutating func lexAt() -> Bool {
            guard let kind = r.atKind else { return false }
            if r.atLineStartOnly, !atLineStart(i) { return false }
            var j = i + 1
            if kind == .variable, at(j) == ch("@") { j += 1 }
            guard isIdentStart(at(j)) else { return false }
            while isIdentCont(at(j)) || (kind != .variable && at(j) == ch(".") && isIdentStart(at(j + 1))) { j += 1 }
            out.add(i, j, kind)
            i = j
            return true
        }

        mutating func lexSigil(_ c: UInt16) -> Bool {
            var j = i + 1
            var d = at(j)
            if c == ch("@"), d == ch("@") { j += 1; d = at(j) }
            if d == ch("{"), r.sigilBraced {
                var k = j + 1
                while k < hi, s[k] != ch("}"), !isNewline(s[k]) { k += 1 }
                if at(k) == ch("}") {
                    out.add(i, k + 1, .variable)
                    i = k + 1
                    return true
                }
                return false
            }
            if d == ch("("), r.sigilParen {
                var k = j + 1
                var depth = 1
                while k < hi, !isNewline(s[k]) {
                    if s[k] == ch("(") {
                        depth += 1
                    } else if s[k] == ch(")") {
                        depth -= 1
                        if depth == 0 { break }
                    }
                    k += 1
                }
                if at(k) == ch(")"), depth == 0 {
                    out.add(i, k + 1, .variable)
                    i = k + 1
                    return true
                }
                return false
            }
            if isIdentStart(d) {
                j += 1
                if !r.sigilSingleLetter {
                    while isIdentCont(at(j)) || (r.sigilScope && at(j) == ch(":") && isIdentStart(at(j + 1))) { j += 1 }
                }
                if r.sigilPrefixBrace, at(j) == ch("{") {
                    var k = j + 1
                    while k < hi, s[k] != ch("}"), !isNewline(s[k]) { k += 1 }
                    if at(k) == ch("}") { j = k + 1 }
                }
                out.add(i, j, .variable)
                i = j
                return true
            }
            if isDigit(d) {
                j += 1
                if !r.sigilSingleLetter { while isDigit(at(j)) { j += 1 } }
                out.add(i, j, .variable)
                i = j
                return true
            }
            if d != 0, r.sigilSpecials.contains(d) {
                j += 1
                if d == ch("#") || d == ch("$"), isIdentStart(at(j)) {
                    while isIdentCont(at(j)) { j += 1 }
                }
                out.add(i, j, .variable)
                i = j
                return true
            }
            return false
        }

        mutating func lexBatchVariable(_ c: UInt16) -> Bool {
            var j = i + 1
            if c == ch("%") {
                let d = at(j)
                if d == ch("%") {
                    j += 1
                    if isAlpha(at(j)) || isDigit(at(j)) { j += 1 }
                    out.add(i, j, .variable)
                    i = j
                    return true
                }
                if d == ch("~") {
                    j += 1
                    while isIdentCont(at(j)) { j += 1 }
                    out.add(i, j, .variable)
                    i = j
                    return true
                }
                if isDigit(d) || d == ch("*") {
                    out.add(i, j + 1, .variable)
                    i = j + 1
                    return true
                }
            }
            guard isIdentStart(at(j)) else { return false }
            var k = j
            while k < hi, k - j < 64 {
                let e = s[k]
                if e == c { break }
                if isWS(e) || e == ch("\"") { return false }
                k += 1
            }
            guard at(k) == c, k > j else { return false }
            out.add(i, k + 1, .variable)
            i = k + 1
            return true
        }

        // MARK: Makefile targets

        mutating func detectTarget(_ ls: Int) {
            guard ls < hi else { return }
            let first = s[ls]
            if isWS(first) || first == ch("#") { return }
            var j = ls
            var depth = 0
            while j < hi {
                let d = s[j]
                if isNewline(d) || d == ch("#") { return }
                if d == ch("(") || d == ch("{") {
                    depth += 1
                } else if d == ch(")") || d == ch("}") {
                    depth = max(0, depth - 1)
                } else if d == ch("="), depth == 0 {
                    return
                } else if d == ch(":"), depth == 0 {
                    if at(j + 1) == ch("=") || (at(j + 1) == ch(":") && at(j + 2) == ch("=")) { return }
                    var end = j
                    while end > ls, isSpace(s[end - 1]) { end -= 1 }
                    regionEnd = end
                    return
                }
                j += 1
            }
        }

        mutating func lexTargetRegion(_ c: UInt16) -> Bool {
            if isSpace(c) { i += 1; return true }
            if c == ch("$") { return false }
            let a = i
            while i < regionEnd, !isWS(s[i]), s[i] != ch("$") { i += 1 }
            out.add(a, i, .attribute)
            return true
        }

        // MARK: Numbers and identifiers

        mutating func lexNumber() {
            var j = i
            let c = s[j]
            let n = lower(at(j + 1))
            if c == ch("0"), n == ch("x"), isHex(at(j + 2)) {
                j += 2
                while isHex(at(j)) || at(j) == ch("_") { j += 1 }
            } else if c == ch("0"), n == ch("b"), at(j + 2) == ch("0") || at(j + 2) == ch("1") {
                j += 2
                while at(j) == ch("0") || at(j) == ch("1") || at(j) == ch("_") { j += 1 }
            } else if c == ch("0"), n == ch("o"), at(j + 2) >= ch("0"), at(j + 2) <= ch("7") {
                j += 2
                while (at(j) >= ch("0") && at(j) <= ch("7")) || at(j) == ch("_") { j += 1 }
            } else {
                while isDigit(at(j)) || at(j) == ch("_") { j += 1 }
                if at(j) == ch("."), isDigit(at(j + 1)) {
                    j += 1
                    while isDigit(at(j)) || at(j) == ch("_") { j += 1 }
                }
                if lower(at(j)) == ch("e") {
                    var k = j + 1
                    if at(k) == ch("+") || at(k) == ch("-") { k += 1 }
                    if isDigit(at(k)) {
                        j = k
                        while isDigit(at(j)) || at(j) == ch("_") { j += 1 }
                    }
                }
            }
            while isIdentCont(at(j)) { j += 1 }
            out.add(i, j, .number)
            i = j
        }

        mutating func lexIdentifier() {
            let a = i
            var j = i + 1
            while j < hi, isIdentCont(s[j]) { j += 1 }
            let len = j - a
            let next = at(j)
            if next == ch("\"") || next == ch("'") || next == ch("#") {
                if !r.stringPrefixes.isEmpty, len <= 3, next != ch("#"), hasWord(a, j, in: r.stringPrefixes),
                   lexString(at: j, start: a) {
                    return
                }
                if !r.rawPrefixes.isEmpty, len <= 2, next != ch("'"), hasWord(a, j, in: r.rawPrefixes) {
                    var h = 0
                    while at(j + h) == ch("#") { h += 1 }
                    if at(j + h) == ch("\"") {
                        lexRaw(start: a, quote: j + h, hashes: h, swift: false)
                        return
                    }
                }
            }
            i = j
            guard len >= r.minWord, len <= r.maxWord else { return }
            if a > lo, s[a - 1] == ch("."), a - 1 == lo || s[a - 2] != ch(".") { return }
            var word = String(decoding: UnsafeBufferPointer(rebasing: s[a..<j]), as: UTF16.self)
            if r.caseInsensitive { word = word.lowercased() }
            if r.keywords.contains(word) {
                out.add(a, j, .keyword)
            } else if r.types.contains(word) {
                out.add(a, j, .type)
            } else if !r.lineStartKeywords.isEmpty, r.lineStartKeywords.contains(word), atLineStart(a, allowDash: true) {
                out.add(a, j, .keyword)
            }
        }

        func hasWord(_ a: Int, _ b: Int, in set: Set<String>) -> Bool {
            let w = String(decoding: UnsafeBufferPointer(rebasing: s[a..<b]), as: UTF16.self).lowercased()
            return set.contains(w)
        }
    }
}

// MARK: - Markup (HTML, XML)

extension SyntaxEngine {
    struct MarkupLexer {
        let s: Buf
        let lo: Int
        let hi: Int
        let embed: Bool
        var out = SpanWriter()

        init(_ s: Buf, _ lo: Int, _ hi: Int, embed: Bool) {
            self.s = s
            self.lo = lo
            self.hi = hi
            self.embed = embed
        }

        @inline(__always) func at(_ j: Int) -> UInt16 { (j >= lo && j < hi) ? s[j] : 0 }

        func isNameStart(_ c: UInt16) -> Bool { isAlpha(c) || c == ch("_") || c == ch(":") || c >= 128 }
        func isNameChar(_ c: UInt16) -> Bool { isNameStart(c) || isDigit(c) || c == ch("-") || c == ch(".") }
        func isAttrChar(_ c: UInt16) -> Bool {
            c > 32 && c != ch("\"") && c != ch("'") && c != ch("<") && c != ch(">") && c != ch("/") && c != ch("=")
        }

        func find(_ pattern: String, from: Int, ci: Bool = false) -> Int? {
            let p = units(pattern)
            guard p.count > 0, hi - p.count >= from else { return nil }
            var j = from
            while j <= hi - p.count {
                var ok = true
                for k in 0..<p.count where (ci ? lower(s[j + k]) : s[j + k]) != p[k] { ok = false; break }
                if ok { return j }
                j += 1
            }
            return nil
        }

        func starts(_ pattern: String, at j: Int) -> Bool {
            let p = units(pattern)
            for k in 0..<p.count where at(j + k) != p[k] { return false }
            return true
        }

        mutating func run() -> [SyntaxSpan] {
            var i = lo
            var nextCheck = lo + 65536
            while i < hi {
                if i >= nextCheck {
                    if Task.isCancelled { break }
                    nextCheck = i + 65536
                }
                let c = s[i]
                if c == ch("<") {
                    i = lexAngle(i)
                } else if c == ch("&") {
                    i = lexEntity(i)
                } else {
                    i += 1
                }
            }
            return out.spans
        }

        mutating func lexEntity(_ i: Int) -> Int {
            var j = i + 1
            if at(j) == ch("#") {
                j += 1
                if lower(at(j)) == ch("x") { j += 1 }
                let digits = j
                while isHex(at(j)) { j += 1 }
                if j == digits { return i + 1 }
            } else {
                let nameStart = j
                while isAlpha(at(j)) || isDigit(at(j)), j - nameStart < 32 { j += 1 }
                if j == nameStart { return i + 1 }
            }
            guard at(j) == ch(";") else { return i + 1 }
            out.add(i, j + 1, .keyword)
            return j + 1
        }

        mutating func lexAngle(_ i: Int) -> Int {
            if starts("<!--", at: i) {
                let end = find("-->", from: i + 4).map { $0 + 3 } ?? hi
                out.add(i, end, .comment)
                return end
            }
            if starts("<![CDATA[", at: i) {
                let end = find("]]>", from: i + 9).map { $0 + 3 } ?? hi
                out.add(i, end, .string)
                return end
            }
            if at(i + 1) == ch("!") {
                var j = i + 2
                while j < hi, s[j] != ch(">") { j += 1 }
                let end = min(j + 1, hi)
                out.add(i, end, .preprocessor)
                return end
            }
            if at(i + 1) == ch("?") {
                let end = find("?>", from: i + 2).map { $0 + 2 } ?? hi
                out.add(i, end, .preprocessor)
                return end
            }
            var j = i + 1
            let closing = at(j) == ch("/")
            if closing { j += 1 }
            guard isNameStart(at(j)) else { return i + 1 }
            let nameStart = j
            while isNameChar(at(j)) { j += 1 }
            let nameEnd = j
            out.add(i, j, .tag)
            var selfClosing = false
            tag: while j < hi {
                let c = s[j]
                if isWS(c) { j += 1; continue }
                if c == ch(">") {
                    out.add(j, j + 1, .tag)
                    j += 1
                    break
                }
                if c == ch("/"), at(j + 1) == ch(">") {
                    out.add(j, j + 2, .tag)
                    j += 2
                    selfClosing = true
                    break
                }
                if c == ch("<") { break tag }
                if c == ch("\"") || c == ch("'") {
                    j = lexQuoted(j)
                    continue
                }
                if isAttrChar(c) {
                    let a = j
                    while isAttrChar(at(j)) { j += 1 }
                    out.add(a, j, .attribute)
                    var k = j
                    while isWS(at(k)) { k += 1 }
                    if at(k) == ch("=") {
                        k += 1
                        while isWS(at(k)) { k += 1 }
                        let q = at(k)
                        if q == ch("\"") || q == ch("'") {
                            j = lexQuoted(k)
                        } else {
                            let v = k
                            while k < hi, !isWS(s[k]), s[k] != ch(">") { k += 1 }
                            out.add(v, k, .string)
                            j = k
                        }
                    }
                    continue
                }
                j += 1
            }
            if embed, !closing, !selfClosing, j > nameEnd {
                let name = String(decoding: UnsafeBufferPointer(rebasing: s[nameStart..<nameEnd]), as: UTF16.self).lowercased()
                if name == "script" || name == "style" {
                    let end = find("</" + name, from: j, ci: true) ?? hi
                    if end > j, let def = SyntaxEngine.definitionsByID[name == "script" ? "javascript" : "css"] {
                        out.append(SyntaxEngine.lex(def, s, j, end))
                    }
                    return end
                }
            }
            return max(j, i + 1)
        }

        /// Quoted attribute value starting at the quote; returns the index after it.
        mutating func lexQuoted(_ j: Int) -> Int {
            let q = s[j]
            var k = j + 1
            while k < hi, s[k] != q { k += 1 }
            var end = k < hi ? k + 1 : hi
            if k >= hi {
                end = SyntaxEngine.lineEnd(s, j, hi)
                if end <= j { end = j + 1 }
            }
            out.add(j, end, .string)
            return end
        }
    }
}

// MARK: - CSS / SCSS / LESS

extension SyntaxEngine {
    struct CSSLexer {
        let s: Buf
        let lo: Int
        let hi: Int
        let lineComments: Bool
        let less: Bool
        var out = SpanWriter()

        static let knownAtRules: Set<String> = words("""
            media import charset font-face keyframes supports mixin include extend function return if else each for \
            while use forward layer container page namespace document content plugin at-root debug warn error \
            property counter-style font-feature-values viewport scope starting-style
            """)

        init(_ s: Buf, _ lo: Int, _ hi: Int, lineComments: Bool, less: Bool) {
            self.s = s
            self.lo = lo
            self.hi = hi
            self.lineComments = lineComments
            self.less = less
        }

        @inline(__always) func at(_ j: Int) -> UInt16 { (j >= lo && j < hi) ? s[j] : 0 }
        func isIdentStart(_ c: UInt16) -> Bool { isAlpha(c) || c == ch("_") || c >= 128 }
        func isIdentCont(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) || c == ch("-") }

        mutating func run() -> [SyntaxSpan] {
            var i = lo
            var depth = 0
            var nextCheck = lo + 65536
            while i < hi {
                if i >= nextCheck {
                    if Task.isCancelled { break }
                    nextCheck = i + 65536
                }
                let c = s[i]
                if isWS(c) { i += 1; continue }
                switch c {
                case ch("/"):
                    if at(i + 1) == ch("*") {
                        var j = i + 2
                        while j < hi, !(s[j] == ch("*") && at(j + 1) == ch("/")) { j += 1 }
                        let end = min(j + 2, hi)
                        out.add(i, end, .comment)
                        i = end
                    } else if lineComments, at(i + 1) == ch("/") {
                        let end = SyntaxEngine.lineEnd(s, i, hi)
                        out.add(i, end, .comment)
                        i = end
                    } else {
                        i += 1
                    }
                case ch("\""), ch("'"):
                    i = lexString(i)
                case ch("{"):
                    depth += 1
                    i += 1
                case ch("}"):
                    depth = max(0, depth - 1)
                    i += 1
                case ch("#"):
                    i = lexHash(i, depth)
                case ch("@"):
                    i = lexAt(i)
                case ch("$"):
                    var j = i + 1
                    while isIdentCont(at(j)) { j += 1 }
                    if j > i + 1 { out.add(i, j, .variable) }
                    i = max(j, i + 1)
                case ch("!"):
                    var j = i + 1
                    while isSpace(at(j)) { j += 1 }
                    let a = j
                    while isAlpha(at(j)) { j += 1 }
                    if j > a { out.add(i, j, .keyword) }
                    i = max(j, i + 1)
                default:
                    if startsNumber(i) {
                        i = lexNumber(i)
                    } else if isIdentStart(c) || (c == ch("-") && (isIdentStart(at(i + 1)) || at(i + 1) == ch("-"))) {
                        i = lexIdentifier(i, depth)
                    } else {
                        i += 1
                    }
                }
            }
            return out.spans
        }

        func startsNumber(_ i: Int) -> Bool {
            let c = s[i]
            if isDigit(c) { return true }
            let prevIdent = i > lo && (isIdentCont(s[i - 1]) || s[i - 1] == ch(")"))
            if c == ch("."), isDigit(at(i + 1)) { return !prevIdent }
            if c == ch("-") || c == ch("+") {
                let n = at(i + 1)
                return !prevIdent && (isDigit(n) || (n == ch(".") && isDigit(at(i + 2))))
            }
            return false
        }

        mutating func lexNumber(_ i: Int) -> Int {
            var j = i
            if s[j] == ch("-") || s[j] == ch("+") { j += 1 }
            while isDigit(at(j)) { j += 1 }
            if at(j) == ch("."), isDigit(at(j + 1)) {
                j += 1
                while isDigit(at(j)) { j += 1 }
            }
            if lower(at(j)) == ch("e") {
                var k = j + 1
                if at(k) == ch("+") || at(k) == ch("-") { k += 1 }
                if isDigit(at(k)) {
                    j = k
                    while isDigit(at(j)) { j += 1 }
                }
            }
            if at(j) == ch("%") {
                j += 1
            } else {
                while isAlpha(at(j)) { j += 1 }
            }
            out.add(i, j, .number)
            return j
        }

        mutating func lexString(_ i: Int) -> Int {
            let q = s[i]
            var j = i + 1
            while j < hi, s[j] != q, !isNewline(s[j]) {
                if s[j] == ch("\\") { j += 1 }
                j += 1
            }
            if j < hi, s[j] == q { j += 1 }
            let end = min(j, hi)
            out.add(i, end, .string)
            return end
        }

        mutating func lexHash(_ i: Int, _ depth: Int) -> Int {
            var j = i + 1
            while isHex(at(j)) { j += 1 }
            let n = j - i - 1
            if depth > 0, n == 3 || n == 4 || n == 6 || n == 8, !isIdentCont(at(j)) {
                var k = j
                while isWS(at(k)) { k += 1 }
                if at(k) != ch("{") {
                    out.add(i, j, .number)
                    return j
                }
            }
            return i + 1
        }

        mutating func lexAt(_ i: Int) -> Int {
            var j = i + 1
            while isIdentCont(at(j)) { j += 1 }
            guard j > i + 1 else { return i + 1 }
            let name = String(decoding: UnsafeBufferPointer(rebasing: s[(i + 1)..<j]), as: UTF16.self).lowercased()
            let known = CSSLexer.knownAtRules.contains(name) || name.hasPrefix("-")
            out.add(i, j, (less && !known) ? .variable : .preprocessor)
            return j
        }

        mutating func lexIdentifier(_ i: Int, _ depth: Int) -> Int {
            var j = i + 1
            while isIdentCont(at(j)) { j += 1 }
            if at(j) == ch("("), j - i == 3, lower(s[i]) == ch("u"), lower(s[i + 1]) == ch("r"), lower(s[i + 2]) == ch("l") {
                var k = j + 1
                while isWS(at(k)) { k += 1 }
                if at(k) != ch("\""), at(k) != ch("'") {
                    while k < hi, s[k] != ch(")"), !isNewline(s[k]) { k += 1 }
                    return min(k + 1, hi)
                }
                return j + 1
            }
            if depth > 0 {
                var k = j
                while isSpace(at(k)) { k += 1 }
                if at(k) == ch(":"), at(k + 1) != ch(":"), isDeclaration(from: k + 1) {
                    out.add(i, j, .attribute)
                }
            }
            return j
        }

        /// After `name:` — a declaration ends with `;` or `}`, a nested selector with `{`.
        func isDeclaration(from start: Int) -> Bool {
            var k = start
            let limit = min(hi, start + 4000)
            while k < limit {
                let c = s[k]
                if c == ch(";") || c == ch("}") { return true }
                if c == ch("{") { return false }
                if c == ch("\"") || c == ch("'") {
                    k += 1
                    while k < limit, s[k] != c, !isNewline(s[k]) { k += 1 }
                }
                k += 1
            }
            return true
        }
    }
}

// MARK: - JSON

extension SyntaxEngine {
    struct JSONLexer {
        let s: Buf
        let lo: Int
        let hi: Int
        var out = SpanWriter()

        init(_ s: Buf, _ lo: Int, _ hi: Int) {
            self.s = s
            self.lo = lo
            self.hi = hi
        }

        @inline(__always) func at(_ j: Int) -> UInt16 { (j >= lo && j < hi) ? s[j] : 0 }

        func followedByColon(_ j: Int) -> Bool {
            var k = j
            while k < hi, isWS(s[k]) { k += 1 }
            return at(k) == ch(":")
        }

        mutating func run() -> [SyntaxSpan] {
            var i = lo
            var nextCheck = lo + 65536
            while i < hi {
                if i >= nextCheck {
                    if Task.isCancelled { break }
                    nextCheck = i + 65536
                }
                let c = s[i]
                if isWS(c) { i += 1; continue }
                if c == ch("\"") || c == ch("'") {
                    var j = i + 1
                    while j < hi, s[j] != c, !isNewline(s[j]) {
                        if s[j] == ch("\\") { j += 1 }
                        j += 1
                    }
                    if j < hi, s[j] == c { j += 1 }
                    let end = min(j, hi)
                    out.add(i, end, followedByColon(end) ? .attribute : .string)
                    i = end
                } else if c == ch("/"), at(i + 1) == ch("*") {
                    var j = i + 2
                    while j < hi, !(s[j] == ch("*") && at(j + 1) == ch("/")) { j += 1 }
                    let end = min(j + 2, hi)
                    out.add(i, end, .comment)
                    i = end
                } else if c == ch("/"), at(i + 1) == ch("/") {
                    let end = SyntaxEngine.lineEnd(s, i, hi)
                    out.add(i, end, .comment)
                    i = end
                } else if isDigit(c) || ((c == ch("-") || c == ch("+") || c == ch(".")) && (isDigit(at(i + 1)) || at(i + 1) == ch("."))) {
                    var j = i + 1
                    while isHex(at(j)) || at(j) == ch(".") || at(j) == ch("x") || at(j) == ch("X")
                        || ((at(j) == ch("+") || at(j) == ch("-")) && lower(s[j - 1]) == ch("e")) { j += 1 }
                    out.add(i, j, .number)
                    i = j
                } else if isAlpha(c) || c == ch("_") || c == ch("$") {
                    var j = i + 1
                    while isAlpha(at(j)) || isDigit(at(j)) || at(j) == ch("_") || at(j) == ch("$") { j += 1 }
                    if followedByColon(j) {
                        out.add(i, j, .attribute)
                    } else {
                        let w = String(decoding: UnsafeBufferPointer(rebasing: s[i..<j]), as: UTF16.self)
                        if w == "true" || w == "false" || w == "null" { out.add(i, j, .keyword) }
                    }
                    i = j
                } else {
                    i += 1
                }
            }
            return out.spans
        }
    }
}

// MARK: - YAML

extension SyntaxEngine {
    struct YAMLLexer {
        let s: Buf
        let lo: Int
        let hi: Int
        var out = SpanWriter()
        var blockParent: Int?

        init(_ s: Buf, _ lo: Int, _ hi: Int) {
            self.s = s
            self.lo = lo
            self.hi = hi
        }

        @inline(__always) func at(_ j: Int) -> UInt16 { (j >= lo && j < hi) ? s[j] : 0 }

        mutating func run() -> [SyntaxSpan] {
            var i = lo
            while i < hi {
                if Task.isCancelled { break }
                let le = SyntaxEngine.lineEnd(s, i, hi)
                let next = SyntaxEngine.nextLine(s, le, hi)
                var p = i
                while p < le, isSpace(s[p]) { p += 1 }
                let indent = p - i
                if let parent = blockParent {
                    if p == le || indent > parent {
                        i = next
                        continue
                    }
                    blockParent = nil
                }
                if p < le { lexLine(p, le, indent) }
                i = next
            }
            return out.spans
        }

        mutating func lexLine(_ start: Int, _ le: Int, _ indent: Int) {
            var q = start
            if indent == 0, le - q >= 3, (s[q] == ch("-") && at(q + 1) == ch("-") && at(q + 2) == ch("-"))
                || (s[q] == ch(".") && at(q + 1) == ch(".") && at(q + 2) == ch(".")),
                q + 3 == le || isWS(at(q + 3)) {
                out.add(q, q + 3, .preprocessor)
                lexValue(q + 3, le, indent)
                return
            }
            if indent == 0, s[q] == ch("%") {
                out.add(q, le, .preprocessor)
                return
            }
            if s[q] == ch("#") {
                out.add(q, le, .comment)
                return
            }
            while q < le, s[q] == ch("-"), q + 1 == le || isWS(at(q + 1)) {
                q += 1
                while q < le, isSpace(s[q]) { q += 1 }
            }
            if q >= le { return }
            if s[q] == ch("#") {
                out.add(q, le, .comment)
                return
            }
            if let (keyEnd, colon) = findKey(q, le) {
                out.add(q, keyEnd, .attribute)
                lexValue(colon + 1, le, indent)
            } else {
                lexValue(q, le, indent)
            }
        }

        /// Returns the end of the key text and the index of its colon.
        func findKey(_ q: Int, _ le: Int) -> (Int, Int)? {
            let c = s[q]
            if c == ch("\"") || c == ch("'") {
                var j = q + 1
                while j < le {
                    if c == ch("\""), s[j] == ch("\\") { j += 2; continue }
                    if s[j] == c {
                        if c == ch("'"), at(j + 1) == ch("'") { j += 2; continue }
                        break
                    }
                    j += 1
                }
                guard j < le else { return nil }
                let keyEnd = j + 1
                var k = keyEnd
                while k < le, isSpace(s[k]) { k += 1 }
                if k < le, s[k] == ch(":"), k + 1 == le || isWS(at(k + 1)) { return (keyEnd, k) }
                return nil
            }
            if "[{|>&*!%@`".utf16.contains(c) { return nil }
            var j = q
            while j < le {
                let d = s[j]
                if d == ch(":"), j + 1 == le || isWS(at(j + 1)) {
                    var end = j
                    while end > q, isSpace(s[end - 1]) { end -= 1 }
                    return end > q ? (end, j) : nil
                }
                if d == ch("#"), j > q, isSpace(s[j - 1]) { return nil }
                j += 1
            }
            return nil
        }

        mutating func lexValue(_ from: Int, _ le: Int, _ parentIndent: Int) {
            var j = from
            while j < le, isSpace(s[j]) { j += 1 }
            if j >= le { return }
            if s[j] == ch("|") || s[j] == ch(">") {
                var k = j + 1
                while k < le, s[k] == ch("+") || s[k] == ch("-") || isDigit(s[k]) { k += 1 }
                while k < le, isSpace(s[k]) { k += 1 }
                if k == le || s[k] == ch("#") {
                    blockParent = parentIndent
                    if k < le { out.add(k, le, .comment) }
                    return
                }
            }
            // Anchors, aliases and tags.
            while j < le, s[j] == ch("&") || s[j] == ch("*") || s[j] == ch("!") {
                let a = j
                while j < le, !isWS(s[j]) { j += 1 }
                out.add(a, j, s[a] == ch("!") ? .type : .variable)
                while j < le, isSpace(s[j]) { j += 1 }
            }
            if j >= le { return }
            if s[j] == ch("[") || s[j] == ch("{") {
                lexFlow(j, le)
                return
            }
            if s[j] == ch("\"") || s[j] == ch("'") {
                j = lexQuoted(j, le)
                while j < le, isSpace(s[j]) { j += 1 }
                if j < le, s[j] == ch("#") { out.add(j, le, .comment) }
                return
            }
            // Plain scalar up to an optional comment.
            var e = j
            var comment: Int?
            while e < le {
                if s[e] == ch("#"), e > j, isSpace(s[e - 1]) { comment = e; break }
                e += 1
            }
            var end = comment ?? le
            while end > j, isSpace(s[end - 1]) { end -= 1 }
            classify(j, end)
            if let comment { out.add(comment, le, .comment) }
        }

        mutating func lexFlow(_ from: Int, _ le: Int) {
            var j = from
            while j < le {
                let c = s[j]
                if isSpace(c) || c == ch(",") || c == ch("[") || c == ch("]") || c == ch("{") || c == ch("}") {
                    j += 1
                } else if c == ch("#"), j == from || isSpace(s[j - 1]) {
                    out.add(j, le, .comment)
                    return
                } else if c == ch("\"") || c == ch("'") {
                    j = lexQuoted(j, le, keyIfColon: true)
                } else {
                    var k = j
                    while k < le, !isWS(s[k]), s[k] != ch(","), s[k] != ch("]"), s[k] != ch("}"), s[k] != ch("[") || k == j { k += 1 }
                    if k > j + 1, s[k - 1] == ch(":") {
                        out.add(j, k - 1, .attribute)
                    } else {
                        classify(j, k)
                    }
                    j = max(k, j + 1)
                }
            }
        }

        /// Quoted scalar; returns the index after the closing quote (or line end).
        mutating func lexQuoted(_ j: Int, _ le: Int, keyIfColon: Bool = false) -> Int {
            let q = s[j]
            var k = j + 1
            while k < le {
                if q == ch("\""), s[k] == ch("\\") { k += 2; continue }
                if s[k] == q {
                    if q == ch("'"), at(k + 1) == ch("'") { k += 2; continue }
                    break
                }
                k += 1
            }
            let end = k < le ? k + 1 : le
            var kind = SyntaxTokenKind.string
            if keyIfColon {
                var m = end
                while m < le, isSpace(s[m]) { m += 1 }
                if m < le, s[m] == ch(":") { kind = .attribute }
            }
            out.add(j, end, kind)
            return end
        }

        mutating func classify(_ a: Int, _ b: Int) {
            guard b > a else { return }
            let w = String(decoding: UnsafeBufferPointer(rebasing: s[a..<b]), as: UTF16.self)
            if SyntaxEngine.isKeywordLiteral(w) {
                out.add(a, b, .keyword)
            } else if SyntaxEngine.isNumberLike(s, a, b) {
                out.add(a, b, .number)
            }
        }
    }

    static func isKeywordLiteral(_ w: String) -> Bool {
        if w == "~" { return true }
        guard w.utf16.count <= 5 else { return false }
        switch w.lowercased() {
        case "true", "false", "null", "yes", "no", "on", "off": return true
        default: return false
        }
    }

    /// Plain numbers, hex/octal, `.inf`/`.nan` and date/time-like tokens (`2024-01-31`, `12:30:00`).
    static func isNumberLike(_ s: Buf, _ a: Int, _ b: Int) -> Bool {
        var j = a
        if s[j] == ch("-") || s[j] == ch("+") { j += 1 }
        guard j < b else { return false }
        if s[j] == ch(".") {
            let rest = String(decoding: UnsafeBufferPointer(rebasing: s[(j + 1)..<b]), as: UTF16.self).lowercased()
            if rest == "inf" || rest == "nan" { return true }
            guard j + 1 < b else { return false }
            j += 1
        }
        guard isDigit(s[j]) else { return false }
        if s[j] == ch("0"), j + 2 < b, lower(s[j + 1]) == ch("x") || lower(s[j + 1]) == ch("o") {
            return (j + 2..<b).allSatisfy { isHex(s[$0]) || s[$0] == ch("_") }
        }
        for k in j..<b {
            let c = s[k]
            let ok = isDigit(c) || c == ch("_") || c == ch(".") || c == ch("-") || c == ch(":") || c == ch("+")
                || lower(c) == ch("e") || lower(c) == ch("t") || lower(c) == ch("z")
            if !ok { return false }
        }
        return true
    }
}

// MARK: - INI / TOML / properties

extension SyntaxEngine {
    struct INILexer {
        let s: Buf
        let lo: Int
        let hi: Int
        var out = SpanWriter()

        init(_ s: Buf, _ lo: Int, _ hi: Int) {
            self.s = s
            self.lo = lo
            self.hi = hi
        }

        @inline(__always) func at(_ j: Int) -> UInt16 { (j >= lo && j < hi) ? s[j] : 0 }

        mutating func run() -> [SyntaxSpan] {
            var i = lo
            while i < hi {
                if Task.isCancelled { break }
                let le = SyntaxEngine.lineEnd(s, i, hi)
                let next = SyntaxEngine.nextLine(s, le, hi)
                var p = i
                while p < le, isSpace(s[p]) { p += 1 }
                if p < le { lexLine(p, le) }
                i = next
            }
            return out.spans
        }

        mutating func lexLine(_ p: Int, _ le: Int) {
            let c = s[p]
            if c == ch(";") || c == ch("#") {
                out.add(p, le, .comment)
                return
            }
            if c == ch("[") {
                var k = p + 1
                while k < le, s[k] != ch("]") { k += 1 }
                if k < le {
                    while k + 1 < le, s[k + 1] == ch("]") { k += 1 }
                    out.add(p, k + 1, .tag)
                    lexValue(k + 1, le)
                    return
                }
            }
            if c == ch("\"") || c == ch("'") {
                var k = p + 1
                while k < le, s[k] != c { k += 1 }
                if k < le {
                    var m = k + 1
                    while m < le, isSpace(s[m]) { m += 1 }
                    if at(m) == ch("=") {
                        out.add(p, k + 1, .attribute)
                        lexValue(m + 1, le)
                        return
                    }
                }
                lexValue(p, le)
                return
            }
            var j = p
            while j < le {
                let d = s[j]
                if d == ch("=") || d == ch(":") { break }
                if d == ch("#") || d == ch(";") || d == ch("\"") || d == ch("'") || d == ch("[") { j = le; break }
                j += 1
            }
            if j < le {
                var end = j
                while end > p, isSpace(s[end - 1]) { end -= 1 }
                if end > p {
                    out.add(p, end, .attribute)
                    lexValue(j + 1, le)
                    return
                }
            }
            lexValue(p, le)
        }

        mutating func lexValue(_ from: Int, _ le: Int) {
            var j = from
            while j < le {
                let c = s[j]
                if isSpace(c) { j += 1; continue }
                if (c == ch("#") || c == ch(";")), j > lo, isSpace(s[j - 1]) {
                    out.add(j, le, .comment)
                    return
                }
                if c == ch("\"") || c == ch("'") {
                    let prev = j > lo ? s[j - 1] : 0
                    if j == from || isSpace(prev) || "[{,=(".utf16.contains(prev) {
                        var k = j + 1
                        while k < le, s[k] != c {
                            if c == ch("\""), s[k] == ch("\\") { k += 1 }
                            k += 1
                        }
                        if k < le || c == ch("\"") {
                            let end = min(k + 1, le)
                            out.add(j, end, .string)
                            j = end
                            continue
                        }
                    }
                    j += 1
                    continue
                }
                var k = j
                while k < le, !isWS(s[k]), s[k] != ch(","), s[k] != ch("]"), s[k] != ch("["), s[k] != ch("{"),
                      s[k] != ch("}"), s[k] != ch("=") { k += 1 }
                if k == j { j += 1; continue }
                let w = String(decoding: UnsafeBufferPointer(rebasing: s[j..<k]), as: UTF16.self)
                if SyntaxEngine.isKeywordLiteral(w) && w != "~" {
                    out.add(j, k, .keyword)
                } else if SyntaxEngine.isNumberLike(s, j, k) {
                    out.add(j, k, .number)
                }
                j = k
            }
        }
    }
}

// MARK: - Markdown

extension SyntaxEngine {
    struct MarkdownLexer {
        let s: Buf
        let lo: Int
        let hi: Int
        var out = SpanWriter()

        init(_ s: Buf, _ lo: Int, _ hi: Int) {
            self.s = s
            self.lo = lo
            self.hi = hi
        }

        @inline(__always) func at(_ j: Int) -> UInt16 { (j >= lo && j < hi) ? s[j] : 0 }

        mutating func run() -> [SyntaxSpan] {
            var i = lo
            var fence: (char: UInt16, length: Int)?
            while i < hi {
                if Task.isCancelled { break }
                let le = SyntaxEngine.lineEnd(s, i, hi)
                let next = SyntaxEngine.nextLine(s, le, hi)
                var p = i
                while p < le, s[p] == ch(" "), p - i < 3 { p += 1 }
                let fenceRun = fenceLength(p, le)
                if let f = fence {
                    out.add(i, le, .string)
                    if fenceRun >= f.length, s[p] == f.char, onlyBlanks(p + fenceRun, le) { fence = nil }
                } else if fenceRun >= 3 {
                    out.add(i, le, .string)
                    fence = (s[p], fenceRun)
                } else if p < le, s[p] == ch("#") {
                    var k = p
                    while k < le, s[k] == ch("#") { k += 1 }
                    if k - p <= 6, k == le || isSpace(s[k]) { out.add(p, le, .keyword) } else { inline(p, le) }
                } else {
                    inline(i, le)
                }
                i = next
            }
            return out.spans
        }

        func fenceLength(_ p: Int, _ le: Int) -> Int {
            guard p < le, s[p] == ch("`") || s[p] == ch("~") else { return 0 }
            var k = p
            while k < le, s[k] == s[p] { k += 1 }
            return k - p
        }

        func onlyBlanks(_ from: Int, _ le: Int) -> Bool {
            var k = from
            while k < le { if !isSpace(s[k]) { return false }; k += 1 }
            return true
        }

        mutating func inline(_ from: Int, _ le: Int) {
            var j = from
            while j < le {
                let c = s[j]
                if c == ch("\\") {
                    j += 2
                } else if c == ch("`") {
                    var k = j
                    while k < le, s[k] == ch("`") { k += 1 }
                    let n = k - j
                    var m = k
                    var found = -1
                    while m < le {
                        if s[m] == ch("`") {
                            var e = m
                            while e < le, s[e] == ch("`") { e += 1 }
                            if e - m == n { found = e; break }
                            m = e
                        } else {
                            m += 1
                        }
                    }
                    if found >= 0 {
                        out.add(j, found, .string)
                        j = found
                    } else {
                        j = k
                    }
                } else if c == ch("]"), at(j + 1) == ch("(") {
                    var k = j + 2
                    while k < le, s[k] != ch(")") { k += 1 }
                    if k < le {
                        out.add(j + 2, k, .attribute)
                        j = k + 1
                    } else {
                        j += 1
                    }
                } else {
                    j += 1
                }
            }
        }
    }
}

// MARK: - Diff

extension SyntaxEngine {
    struct DiffLexer {
        let s: Buf
        let lo: Int
        let hi: Int
        var out = SpanWriter()

        init(_ s: Buf, _ lo: Int, _ hi: Int) {
            self.s = s
            self.lo = lo
            self.hi = hi
        }

        func starts(_ pattern: String, at j: Int) -> Bool {
            var k = j
            for u in pattern.utf16 {
                if k >= hi || s[k] != u { return false }
                k += 1
            }
            return true
        }

        static let headerPrefixes = [
            "index ", "new file", "deleted file", "old mode", "new mode", "similarity", "dissimilarity",
            "rename ", "copy ", "Binary files",
        ]

        mutating func run() -> [SyntaxSpan] {
            var i = lo
            var inHunk = false
            var afterMinusHeader = false
            while i < hi {
                if Task.isCancelled { break }
                let le = SyntaxEngine.lineEnd(s, i, hi)
                let next = SyntaxEngine.nextLine(s, le, hi)
                let c = s[i]
                var kind: SyntaxTokenKind?
                var wasMinusHeader = false
                if starts("@@", at: i) {
                    kind = .preprocessor
                    inHunk = true
                } else if starts("diff ", at: i) {
                    kind = .comment
                    inHunk = false
                } else if starts("--- ", at: i) {
                    if !inHunk || starts("+++ ", at: next) {
                        kind = .comment
                        wasMinusHeader = true
                        inHunk = false
                    } else {
                        kind = .keyword
                    }
                } else if starts("+++ ", at: i), afterMinusHeader || !inHunk {
                    kind = .comment
                } else if c == ch("+") {
                    kind = .type
                } else if c == ch("-") {
                    kind = .keyword
                } else if c == ch("\\") || (!inHunk && Self.headerPrefixes.contains { starts($0, at: i) }) {
                    kind = .comment
                }
                if let kind { out.add(i, le, kind) }
                afterMinusHeader = wasMinusHeader
                i = next
            }
            return out.spans
        }
    }
}

// MARK: - Language definitions

extension SyntaxEngine {
    private static func code(_ id: String, _ name: String, ext: String, files: [String] = [],
                             _ configure: (inout CodeRules) -> Void) -> Definition {
        var d = Definition(id, name, ext: ext, files: files, family: .code)
        var r = CodeRules()
        configure(&r)
        r.finalize()
        d.code = r
        return d
    }

    private static func slashComments(_ r: inout CodeRules) {
        r.line("//")
        r.block("/*", "*/")
    }

    private static func quotes(_ r: inout CodeRules, multi: Bool = false) {
        r.string("\"", multi: multi)
        r.string("'", multi: multi)
    }

    private static let cKeywords = """
        auto break case const continue default do else enum extern for goto if inline register restrict return \
        sizeof static struct switch typedef union volatile while _Alignas _Alignof _Atomic _Bool _Complex _Generic \
        _Noreturn _Static_assert _Thread_local NULL true false
        """

    private static let cTypes = """
        void char short int long float double signed unsigned bool size_t ssize_t ptrdiff_t intptr_t uintptr_t \
        int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t FILE wchar_t va_list
        """

    static func makeDefinitions() -> [Definition] {
        var d: [Definition] = []

        d.append(code("swift", "Swift", ext: "swift") { r in
            r.line("//")
            r.block("/*", "*/", nests: true)
            r.string("\"\"\"", multi: true, interp: true)
            r.string("\"", interp: true)
            r.hashDirective = true
            r.atKind = .preprocessor
            r.kw("""
                associatedtype class deinit enum extension fileprivate func import init inout internal let open operator \
                private precedencegroup protocol public rethrows static struct subscript typealias var break case catch \
                continue default defer do else fallthrough for guard if in repeat return throw switch where while Any as \
                await false is nil self Self super throws true try async actor some any nonisolated isolated consuming \
                borrowing get set willSet didSet indirect lazy mutating nonmutating override required convenience final \
                dynamic weak unowned optional macro
                """)
            r.ty("""
                Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Float Double Bool String Character Substring \
                Array Dictionary Set Optional Result Void Never AnyObject Data Date URL UUID Error Range ClosedRange \
                Sequence Collection Equatable Hashable Comparable Codable Encodable Decodable Identifiable Sendable \
                CGFloat CGPoint CGSize CGRect NSObject NSString NSRange
                """)
        })

        d.append(code("c", "C", ext: "c h") { r in
            slashComments(&r)
            quotes(&r)
            r.preprocessorLine = true
            r.kw(cKeywords)
            r.ty(cTypes)
        })

        d.append(code("cpp", "C++", ext: "cpp cc cxx hpp hh hxx inl ino") { r in
            slashComments(&r)
            quotes(&r)
            r.preprocessorLine = true
            r.kw(cKeywords)
            r.ty(cTypes)
            r.kw("""
                alignas alignof and and_eq asm bitand bitor catch class compl concept consteval constexpr constinit \
                const_cast co_await co_return co_yield decltype delete dynamic_cast explicit export friend mutable \
                namespace new noexcept not not_eq nullptr operator or or_eq private protected public reinterpret_cast \
                requires static_assert static_cast template this thread_local throw try typeid typename using virtual \
                xor xor_eq override final
                """)
            r.ty("""
                string wstring string_view vector map set unordered_map unordered_set list deque array pair tuple \
                optional variant shared_ptr unique_ptr weak_ptr nullptr_t char8_t char16_t char32_t
                """)
        })

        d.append(code("objc", "Objective-C", ext: "m mm") { r in
            slashComments(&r)
            r.string("@\"")
            quotes(&r)
            r.preprocessorLine = true
            r.atKind = .keyword
            r.kw(cKeywords)
            r.ty(cTypes)
            r.kw("""
                self super nil Nil YES NO in out inout bycopy byref oneway nonatomic atomic strong weak assign copy \
                retain readonly readwrite nullable nonnull __block __weak __strong __unsafe_unretained class namespace \
                new delete this try catch throw
                """)
            r.ty("BOOL id SEL IMP Class instancetype NSString NSArray NSDictionary NSObject NSNumber NSInteger NSUInteger CGFloat")
        })

        d.append(code("csharp", "C#", ext: "cs") { r in
            slashComments(&r)
            r.string("$@\"", close: "\"", esc: nil, doubled: true, multi: true)
            r.string("@$\"", close: "\"", esc: nil, doubled: true, multi: true)
            r.string("@\"", close: "\"", esc: nil, doubled: true, multi: true)
            r.string("\"\"\"", esc: nil, multi: true)
            r.string("$\"")
            quotes(&r)
            r.preprocessorLine = true
            r.kw("""
                abstract as base break case catch checked class const continue default delegate do else enum event \
                explicit extern false finally fixed for foreach goto if implicit in interface internal is lock namespace \
                new null operator out override params private protected public readonly ref return sealed sizeof \
                stackalloc static struct switch this throw true try typeof unchecked unsafe using virtual volatile \
                while async await var yield get set init value record partial where when with global nameof required \
                file scoped
                """)
            r.ty("""
                bool byte char decimal double float int long object sbyte short string uint ulong ushort void dynamic \
                nint nuint String Int32 Int64 List Dictionary Task Action Func IEnumerable IList Guid DateTime TimeSpan \
                Exception Console Math
                """)
        })

        d.append(code("java", "Java", ext: "java") { r in
            slashComments(&r)
            r.string("\"\"\"", multi: true)
            quotes(&r)
            r.atKind = .preprocessor
            r.identStartExtra = [ch("$")]
            r.kw("""
                abstract assert break case catch class const continue default do else enum extends final finally for \
                goto if implements import instanceof interface native new package private protected public return \
                static strictfp super switch synchronized this throw throws transient try volatile while true false \
                null var record sealed permits yield
                """)
            r.ty("""
                boolean byte char double float int long short void String Object Integer Long Double Float Boolean \
                Character Byte Short List Map Set ArrayList HashMap HashSet Optional Exception RuntimeException Class \
                System Math StringBuilder Thread Iterable Collection
                """)
        })

        d.append(code("kotlin", "Kotlin", ext: "kt kts") { r in
            r.line("//")
            r.block("/*", "*/", nests: true)
            r.string("\"\"\"", esc: nil, multi: true)
            quotes(&r)
            r.atKind = .preprocessor
            r.kw("""
                as break class continue do else false for fun if in interface is null object package return super this \
                throw true try typealias typeof val var when while by catch constructor delegate dynamic field file \
                finally get import init param property receiver set setparam value where abstract actual annotation \
                companion const crossinline data enum expect external final infix inline inner internal lateinit \
                noinline open operator out override private protected public reified sealed suspend tailrec vararg
                """)
            r.ty("""
                Int Long Short Byte Float Double Boolean Char String Unit Any Nothing Array List MutableList Map \
                MutableMap Set MutableSet Pair Triple Sequence Collection Iterable Result UInt ULong UByte UShort
                """)
        })

        let jsKeywords = """
            async await break case catch class const continue debugger default delete do else export extends false \
            finally for function if import in instanceof let new null of return static super switch this throw true \
            try typeof undefined var void while with yield from as NaN Infinity
            """
        let jsTypes = """
            Object Array String Number Boolean Symbol BigInt Map Set WeakMap WeakSet Promise Date RegExp Error Math \
            JSON Function console window document
            """

        d.append(code("javascript", "JavaScript", ext: "js mjs cjs jsx") { r in
            slashComments(&r)
            r.string("`", multi: true)
            quotes(&r)
            r.identStartExtra = [ch("$")]
            r.kw(jsKeywords)
            r.ty(jsTypes)
        })

        d.append(code("typescript", "TypeScript", ext: "ts tsx mts cts") { r in
            slashComments(&r)
            r.string("`", multi: true)
            quotes(&r)
            r.atKind = .preprocessor
            r.identStartExtra = [ch("$")]
            r.kw(jsKeywords)
            r.kw("""
                abstract any asserts declare enum implements interface is keyof module namespace never override \
                private protected public readonly satisfies type unique unknown infer accessor
                """)
            r.ty(jsTypes)
            r.ty("string number boolean any void never unknown object symbol bigint")
        })

        d.append(code("python", "Python", ext: "py pyw pyi") { r in
            r.line("#")
            r.string("\"\"\"", multi: true)
            r.string("'''", multi: true)
            quotes(&r)
            r.stringPrefixes = words("r b u f br rb fr rf ur")
            r.atKind = .preprocessor
            r.atLineStartOnly = true
            r.kw("""
                False None True and as assert async await break class continue def del elif else except finally for \
                from global if import in is lambda nonlocal not or pass raise return try while with yield
                """)
            r.ty("""
                int float str bool list dict set tuple frozenset bytes bytearray complex object type range property \
                staticmethod classmethod Exception ValueError TypeError KeyError RuntimeError OSError IOError
                """)
        })

        d.append(code("ruby", "Ruby", ext: "rb", files: ["Gemfile", "Podfile", "Rakefile"]) { r in
            r.line("#")
            r.block("=begin", "=end", lineStart: true)
            quotes(&r)
            r.string("`")
            r.sigils = [ch("@"), ch("$")]
            r.sigilSpecials = units("!&~;,./\\*?")
            r.kw("""
                BEGIN END alias and begin break case class def do else elsif end ensure false for if in module next \
                nil not or redo rescue retry return self super then true undef unless until when while yield require \
                require_relative include extend attr_accessor attr_reader attr_writer private protected public raise \
                lambda proc puts loop
                """)
            r.ty("""
                String Integer Float Array Hash Symbol Object Class Module Proc Range Regexp Struct Comparable \
                Enumerable Kernel NilClass TrueClass FalseClass Time File Dir IO Exception StandardError
                """)
        })

        d.append(code("go", "Go", ext: "go") { r in
            slashComments(&r)
            r.string("`", esc: nil, multi: true)
            quotes(&r)
            r.kw("""
                break case chan const continue default defer else fallthrough for func go goto if import interface map \
                package range return select struct switch type var true false nil iota
                """)
            r.ty("""
                bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 \
                uint16 uint32 uint64 uintptr any comparable
                """)
        })

        d.append(code("rust", "Rust", ext: "rs") { r in
            r.line("//")
            r.block("/*", "*/", nests: true)
            r.string("\"", multi: true)
            r.charMode = .charOrLifetime
            r.rawPrefixes = words("r br cr")
            r.stringPrefixes = words("b c")
            r.rustAttributes = true
            r.kw("""
                as async await break const continue crate dyn else enum extern false fn for if impl in let loop match \
                mod move mut pub ref return self static struct super trait true type unsafe use where while union
                """)
            r.ty("""
                i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box \
                Rc Arc RefCell Cell HashMap HashSet BTreeMap BTreeSet VecDeque Self Some None Ok Err
                """)
        })

        d.append(code("php", "PHP", ext: "php") { r in
            slashComments(&r)
            r.line("#")
            r.string("\"", multi: true)
            r.string("'", multi: true)
            r.markers = [units("<?php"), units("<?="), units("?>")]
            r.sigils = [ch("$")]
            r.caseInsensitive = true
            r.kw("""
                abstract and array as break callable case catch class clone const continue declare default do echo else \
                elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for \
                foreach function global goto if implements include include_once instanceof insteadof interface isset \
                list match namespace new or print private protected public readonly require require_once return static \
                switch throw trait try unset use var while xor yield true false null self parent
                """)
            r.ty("int float string bool array object callable iterable mixed void never")
        })

        d.append(code("perl", "Perl", ext: "pl pm") { r in
            r.line("#")
            quotes(&r)
            r.sigils = [ch("$"), ch("@")]
            r.sigilSpecials = units("!&$.,;/\\#")
            r.kw("""
                my our local use no package sub if elsif else unless while until for foreach do last next redo return \
                goto require and or not xor eq ne lt gt le ge cmp print say die warn defined undef ref bless scalar \
                shift unshift push pop splice keys values each delete exists wantarray BEGIN END __PACKAGE__ __FILE__ \
                __LINE__
                """)
            r.ty("STDIN STDOUT STDERR ARGV ENV")
        })

        d.append(code("shell", "Shell", ext: "sh bash zsh fish command bashrc zshrc profile bash_profile") { r in
            r.line("#", boundary: true)
            r.string("\"")
            r.string("'", esc: nil)
            r.sigils = [ch("$")]
            r.sigilSpecials = units("@*#?$!-")
            r.kw("""
                if then else elif fi for while until do done case esac in function select time return exit break \
                continue local export readonly declare typeset unset shift source alias unalias eval exec set trap \
                wait cd echo printf read test true false let begin end
                """)
        })

        d.append(code("powershell", "PowerShell", ext: "ps1 psm1") { r in
            r.line("#")
            r.block("<#", "#>")
            r.string("@\"", close: "\"@", esc: nil, multi: true)
            r.string("@'", close: "'@", esc: nil, multi: true)
            r.string("\"", esc: "`", doubled: true)
            r.string("'", esc: nil, doubled: true)
            r.sigils = [ch("$")]
            r.sigilScope = true
            r.sigilSpecials = units("?$^")
            r.caseInsensitive = true
            r.kw("""
                begin break catch class continue data do dynamicparam else elseif end enum exit filter finally for \
                foreach from function if in param process return switch throw trap try until using var while \
                workflow hidden static parallel sequence inlinescript
                """)
            r.ty("string int long bool double float decimal byte char array hashtable object datetime void xml regex psobject")
        })

        d.append(code("batch", "Batch", ext: "bat cmd") { r in
            r.line("rem", ci: true, lineStart: true, wordEnd: true)
            r.line("::", lineStart: true)
            r.string("\"", esc: nil)
            r.percentVariables = true
            r.caseInsensitive = true
            r.kw("""
                if else for in do goto call exit set echo not exist defined errorlevel equ neq lss leq gtr geq setlocal \
                endlocal enabledelayedexpansion enableextensions pause start shift cd chdir md mkdir rd rmdir del copy \
                xcopy move ren rename type cls title color pushd popd verify ver on off nul con prn aux
                """)
        })

        d.append(code("sql", "SQL", ext: "sql") { r in
            r.line("--")
            r.block("/*", "*/")
            r.string("'", esc: nil, doubled: true, multi: true)
            r.string("\"", esc: nil, doubled: true)
            r.string("`", esc: nil, doubled: true)
            r.atKind = .variable
            r.caseInsensitive = true
            r.kw("""
                select from where and or not in is null like between exists distinct as join inner left right full outer \
                cross on using group by order having limit offset union all intersect except insert into values update \
                set delete create alter drop table view index database schema trigger procedure function begin end \
                commit rollback transaction savepoint grant revoke primary key foreign references unique default check \
                constraint add column asc desc case when then else if while return returns declare cursor fetch open \
                close with recursive explain truncate rename to temporary temp cascade restrict replace merge top over \
                partition window rows range preceding following unbounded current row true false auto_increment \
                autoincrement engine charset collate pragma vacuum analyze use show describe
                """)
            r.ty("""
                int integer smallint bigint tinyint mediumint decimal numeric float real double precision boolean bool \
                bit char varchar nchar nvarchar text ntext tinytext mediumtext longtext blob tinyblob mediumblob \
                longblob clob date time datetime datetime2 timestamp timestamptz interval year json jsonb uuid serial \
                bigserial money binary varbinary xml enum array
                """)
        })

        d.append(code("lua", "Lua", ext: "lua") { r in
            r.line("--")
            r.longBrackets = true
            quotes(&r)
            r.kw("and break do else elseif end false for function goto if in local nil not or repeat return then true until while")
            r.ty("string table math io os coroutine debug utf8")
        })

        d.append(code("pascal", "Pascal", ext: "pas pp dpr lpr") { r in
            r.line("//")
            r.block("{$", "}", kind: .preprocessor)
            r.block("{", "}")
            r.block("(*", "*)")
            r.string("'", esc: nil, doubled: true)
            r.caseInsensitive = true
            r.kw("""
                and array as asm begin case class const constructor destructor div do downto else end except exports file \
                finalization finally for function goto if implementation in inherited initialization inline interface \
                is label library mod nil not object of on operator or out packed private procedure program property \
                protected public published raise record repeat resourcestring set shl shr then threadvar to try type \
                unit until uses var while with xor true false
                """)
            r.ty("""
                integer cardinal byte word longint longword shortint smallint int64 qword boolean char widechar ansichar \
                string ansistring widestring shortstring real single double extended currency pointer variant tobject \
                exception pchar text tstringlist tstrings
                """)
        })

        d.append(code("basic", "Visual Basic", ext: "vb vbs bas") { r in
            r.line("'")
            r.line("rem", ci: true, wordEnd: true)
            r.string("\"", esc: nil, doubled: true)
            r.preprocessorLine = true
            r.caseInsensitive = true
            r.kw("""
                addhandler addressof alias and andalso as byref byval call case catch class const continue declare \
                default delegate dim directcast do each else elseif end endif enum erase error event exit false finally \
                for friend function get gettype global gosub goto handles if implements imports in inherits interface is \
                isnot let lib like loop me mod module mustinherit mustoverride mybase myclass namespace narrowing new \
                next not nothing notinheritable notoverridable of on operator option optional or orelse overloads \
                overridable overrides paramarray partial private property protected public raiseevent readonly redim \
                removehandler resume return select set shadows shared static step stop structure sub synclock then \
                throw to true try trycast typeof using wend when while widening with withevents writeonly xor async \
                await yield
                """)
            r.ty("""
                boolean byte char date decimal double integer long object sbyte short single string uinteger ulong \
                ushort variant
                """)
        })

        var html = Definition("html", "HTML", ext: "html htm xhtml", family: .markup)
        html.embedScripts = true
        d.append(html)
        d.append(Definition("xml", "XML",
                            ext: "xml plist svg xsd xsl xslt xaml csproj vcxproj storyboard xib resx", family: .markup))

        var css = Definition("css", "CSS", ext: "css scss less", family: .css)
        css.cssLineComments = true
        d.append(css)
        d.append(Definition("json", "JSON", ext: "json jsonc json5 geojson xcstrings", family: .json))
        d.append(Definition("yaml", "YAML", ext: "yml yaml", family: .yaml))
        d.append(Definition("ini", "INI", ext: "ini cfg conf properties toml editorconfig gitconfig", family: .ini))
        d.append(Definition("markdown", "Markdown", ext: "md markdown mdown", family: .markdown))
        d.append(Definition("diff", "Diff", ext: "diff patch", family: .diff))

        d.append(code("makefile", "Makefile", ext: "mk mak", files: ["Makefile", "GNUmakefile"]) { r in
            r.line("#")
            r.string("\"")
            r.string("'", esc: nil)
            r.sigils = [ch("$")]
            r.sigilParen = true
            r.sigilSingleLetter = true
            r.sigilSpecials = units("@<^?*+%|$")
            r.targetLines = true
            r.lineStartKeywords = words("""
                ifeq ifneq ifdef ifndef else endif include sinclude define endef export unexport override vpath undefine
                """)
        })

        d.append(code("cmake", "CMake", ext: "cmake", files: ["CMakeLists.txt"]) { r in
            r.block("#[[", "]]")
            r.line("#")
            r.string("\"", multi: true)
            r.sigils = [ch("$")]
            r.sigilPrefixBrace = true
            r.caseInsensitive = true
            r.kw("""
                if elseif else endif foreach endforeach while endwhile function endfunction macro endmacro return break \
                continue block endblock set unset option project add_executable add_library add_subdirectory \
                add_custom_command add_custom_target add_definitions add_compile_options add_test include \
                include_directories link_directories link_libraries target_link_libraries target_include_directories \
                target_compile_definitions target_compile_options target_sources find_package find_library find_path \
                find_program file message string list math install cmake_minimum_required cmake_policy configure_file \
                execute_process get_property set_property set_target_properties get_target_property enable_testing \
                export try_compile mark_as_advanced and or not strequal equal less greater matches defined exists \
                command target policy version_less version_greater version_equal in_list is_directory
                """)
            r.ty("""
                public private interface required components static shared module object optional quiet cache force \
                parent_scope status fatal_error warning version
                """)
        })

        d.append(code("dockerfile", "Dockerfile", ext: "dockerfile", files: ["Dockerfile"]) { r in
            r.line("#", lineStart: true)
            r.string("\"")
            r.string("'", esc: nil)
            r.sigils = [ch("$")]
            r.sigilSpecials = units("@*#?$!-")
            r.caseInsensitive = true
            r.kw("as")
            r.lineStartKeywords = words("""
                from run cmd label maintainer expose env add copy entrypoint volume user workdir arg onbuild stopsignal \
                healthcheck shell
                """)
        })

        d.append(code("r", "R", ext: "r") { r in
            r.line("#")
            quotes(&r)
            r.identContinueExtra = [ch(".")]
            r.kw("""
                if else repeat while function for next break TRUE FALSE NULL NA NA_integer_ NA_real_ NA_character_ Inf \
                NaN in library require return
                """)
            r.ty("character numeric integer logical complex list data.frame matrix factor vector double raw environment")
        })

        d.append(code("scala", "Scala", ext: "scala") { r in
            r.line("//")
            r.block("/*", "*/", nests: true)
            r.string("\"\"\"", esc: nil, multi: true)
            r.string("\"")
            r.charMode = .charOnly
            r.atKind = .preprocessor
            r.kw("""
                abstract case catch class def do else extends false final finally for forSome if implicit import lazy \
                match new null object override package private protected return sealed super this throw trait true try \
                type val var while with yield given using enum export then extension opaque inline transparent open end
                """)
            r.ty("""
                Int Long Short Byte Float Double Boolean Char String Unit Any AnyRef AnyVal Nothing Null List Map Set Seq \
                Vector Array Option Some None Either Left Right Try Success Failure Future
                """)
        })

        d.append(code("dart", "Dart", ext: "dart") { r in
            slashComments(&r)
            r.string("'''", multi: true)
            r.string("\"\"\"", multi: true)
            quotes(&r)
            r.stringPrefixes = ["r"]
            r.atKind = .preprocessor
            r.kw("""
                abstract as assert async await break case catch class const continue covariant default deferred do \
                else enum export extends extension external factory false final finally for get hide if implements \
                import in interface is late library mixin new null of on operator part required rethrow return sealed \
                set show static super switch sync this throw true try typedef var while with yield base
                """)
            r.ty("""
                int double num bool String List Map Set Iterable Future Stream Object dynamic void Never Null Type Symbol \
                Duration DateTime Uri RegExp Function
                """)
        })

        d.append(code("haskell", "Haskell", ext: "hs") { r in
            r.line("--")
            r.block("{-#", "#-}", kind: .preprocessor)
            r.block("{-", "-}", nests: true)
            r.string("\"")
            r.charMode = .charOnly
            r.haskellDashes = true
            r.identContinueExtra = [ch("'")]
            r.kw("""
                case class data default deriving do else foreign if import in infix infixl infixr instance let module \
                newtype of then type where forall qualified as hiding mdo proc rec
                """)
            r.ty("""
                Int Integer Float Double Char String Bool Maybe Either IO Ordering Word Rational Show Eq Ord Enum Bounded \
                Num Read Functor Applicative Monad Monoid Semigroup Foldable Traversable True False Nothing Just Left \
                Right LT EQ GT
                """)
        })

        return d
    }
}
