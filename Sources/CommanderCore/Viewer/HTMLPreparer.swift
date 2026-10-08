// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import Foundation

/// An HTML file made safe for the viewer's web view, which serves it as the page under
/// `MarkdownRenderer.pageURL(for:)`, so relative links and images resolve against its folder.
///
/// A strict Content Security Policy goes in as the first element of `<head>`. Policies add up,
/// so a policy of the document's own can only restrict further. Scripts, frames, plug-ins and forms
/// stay off; images, media, styles and fonts come from the viewer's scheme and `data:` only, and
/// from the internet when `allowRemote` is set. `<meta http-equiv="refresh">`, `<base>` pointing
/// off-site and connection hints (`preconnect`, `dns-prefetch`…) are removed.
public enum HTMLPreparer {
    public static func prepare(_ html: String, allowRemote: Bool = false) -> MarkdownPage {
        let text = html.hasPrefix("\u{FEFF}") ? String(html.dropFirst()) : html
        let bytes = Array(text.utf8)
        let tokens = tokenize(bytes)
        var edits: [(range: Range<Int>, text: String)] = []
        var remote: [String] = []
        var title: String?

        func reference(_ range: Range<Int>) {
            let value = String(decoding: bytes[range], as: UTF8.self)
            guard MarkdownRenderer.isRemote(value) else { return }
            remote.append(value)
            // `//host` would resolve against the viewer's own scheme; it means https here.
            if value.hasPrefix("//") { edits.append((range.lowerBound..<range.lowerBound, "https:")) }
        }

        for token in tokens {
            switch token {
            case .tag(let tag) where !tag.isEnd:
                if removes(tag) {
                    edits.append((tag.range, ""))
                    continue
                }
                for attribute in tag.attributes {
                    guard let range = attribute.valueRange else { continue }
                    switch attribute.name {
                    case "src" where !["script", "iframe", "frame", "embed", "object"].contains(tag.name),
                         "poster", "background":
                        reference(trimmed(range, in: bytes))
                    case "href" where tag.name == "link" && tag.relations.contains("stylesheet"),
                         "href" where tag.name == "image", "xlink:href" where tag.name == "image":
                        reference(trimmed(range, in: bytes))
                    case "srcset":
                        srcsetURLs(bytes, in: range).forEach(reference)
                    case "style":
                        cssURLs(bytes, in: range).forEach(reference)
                    default:
                        break
                    }
                }
            case .rawText(let name, let range):
                if name == "style" { cssURLs(bytes, in: range).forEach(reference) }
                if name == "title", title == nil {
                    title = String(decoding: bytes[range], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            default:
                break
            }
        }

        let (position, needsHead) = insertionPoint(tokens, count: bytes.count)
        let header = """
            <meta http-equiv="Content-Security-Policy" content="\(policy(allowRemote: allowRemote))">\
            <meta charset="utf-8"><meta http-equiv="x-dns-prefetch-control" content="off">\
            <meta name="referrer" content="no-referrer">
            """
        edits.append((position..<position, (needsHead ? "<head>" : "") + header))

        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + 512)
        var cursor = 0
        // Insertions sort before a removal at the same place, so the policy is never dropped.
        let ordered = edits.sorted { ($0.range.lowerBound, $0.range.upperBound) < ($1.range.lowerBound, $1.range.upperBound) }
        for edit in ordered where edit.range.lowerBound >= cursor {
            out += bytes[cursor..<edit.range.lowerBound]
            out += Array(edit.text.utf8)
            cursor = edit.range.upperBound
        }
        out += bytes[cursor...]
        var seen = Set<String>()
        return MarkdownPage(html: String(decoding: out, as: UTF8.self), title: title?.isEmpty == false ? title : nil,
                            remoteResources: remote.filter { seen.insert($0).inserted })
    }

    static func policy(allowRemote: Bool) -> String {
        let local = "\(MarkdownRenderer.scheme): data:"
        let sources = allowRemote ? "\(local) https: http:" : local
        return "default-src 'none'; img-src \(sources); media-src \(sources); style-src 'unsafe-inline' \(sources); "
            + "font-src \(sources); base-uri \(MarkdownRenderer.scheme):; form-action 'none'"
    }

    /// Tags dropped from the page: refresh/redirect, a base pointing off-site, connection hints.
    private static func removes(_ tag: Tag) -> Bool {
        switch tag.name {
        case "meta":
            return tag.value("http-equiv")?.trimmingCharacters(in: .whitespaces).lowercased() == "refresh"
        case "base":
            guard let href = tag.value("href") else { return false }
            return !isRelative(href)
        case "link":
            return !tag.relations.isDisjoint(with: ["preconnect", "dns-prefetch", "prefetch", "prerender"])
        default:
            return false
        }
    }

    /// A path relative to the document (or its root) — no scheme, no `//host`.
    static func isRelative(_ reference: String) -> Bool {
        let cleaned = reference.filter { !"\t\n\r".contains($0) }.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("//") || cleaned.hasPrefix("\\") || cleaned.hasPrefix("/\\") { return false }
        let head = cleaned.prefix { !"/?#".contains($0) }
        return !head.contains(":")
    }

    /// Where our policy goes: right after `<head>`, or after `<html>` (opening a head), or before
    /// the first content after the doctype and leading comments.
    private static func insertionPoint(_ tokens: [Token], count: Int) -> (Int, needsHead: Bool) {
        var index = tokens.startIndex
        func skipPrologue() {
            while index < tokens.endIndex {
                switch tokens[index] {
                case .comment, .doctype: index += 1
                case .text(_, let blank) where blank: index += 1
                default: return
                }
            }
        }
        skipPrologue()
        guard index < tokens.endIndex else { return (count, true) }
        var position = tokens[index].start
        if case .tag(let tag) = tokens[index], !tag.isEnd, tag.name == "html" {
            position = tag.range.upperBound
            index += 1
            skipPrologue()
            guard index < tokens.endIndex else { return (position, true) }
        }
        if case .tag(let tag) = tokens[index], !tag.isEnd, tag.name == "head" {
            return (tag.range.upperBound, false)
        }
        return (position, true)
    }

    private static func trimmed(_ range: Range<Int>, in bytes: [UInt8]) -> Range<Int> {
        var lower = range.lowerBound, upper = range.upperBound
        while lower < upper, isSpace(bytes[lower]) { lower += 1 }
        while upper > lower, isSpace(bytes[upper - 1]) { upper -= 1 }
        return lower..<upper
    }

    // MARK: srcset, CSS

    /// The URLs of `srcset` candidates: `a.png 1x, https://x/b.png 2x`.
    static func srcsetURLs(_ bytes: [UInt8], in range: Range<Int>) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var i = range.lowerBound
        while i < range.upperBound {
            while i < range.upperBound, isSpace(bytes[i]) || bytes[i] == UInt8(ascii: ",") { i += 1 }
            let start = i
            while i < range.upperBound, !isSpace(bytes[i]) { i += 1 }
            var end = i
            while end > start, bytes[end - 1] == UInt8(ascii: ",") { end -= 1 }
            if end > start { found.append(start..<end) }
            if end < i { continue }
            while i < range.upperBound, bytes[i] != UInt8(ascii: ",") { i += 1 }
        }
        return found
    }

    /// The URLs in CSS `url(…)` and `@import "…"`.
    static func cssURLs(_ bytes: [UInt8], in range: Range<Int>) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var i = range.lowerBound
        while i < range.upperBound {
            var quoteOnly = false
            if matches(bytes, "url(", at: i, limit: range.upperBound) {
                i += 4
            } else if matches(bytes, "@import", at: i, limit: range.upperBound) {
                i += 7
                quoteOnly = true
            } else {
                i += 1
                continue
            }
            while i < range.upperBound, isSpace(bytes[i]) { i += 1 }
            guard i < range.upperBound else { break }
            let quote = bytes[i]
            let quoted = quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'")
            if quoteOnly && !quoted { continue }
            if quoted { i += 1 }
            while i < range.upperBound, isSpace(bytes[i]) { i += 1 }
            let start = i
            while i < range.upperBound, quoted ? bytes[i] != quote : !(isSpace(bytes[i]) || bytes[i] == UInt8(ascii: ")")) {
                i += 1
            }
            if i > start { found.append(start..<i) }
        }
        return found
    }

    // MARK: Tokenizer

    /// A start or end tag; attribute names are lowercased, values as written (entities not decoded).
    struct Tag {
        var name: String
        var isEnd: Bool
        var range: Range<Int>
        var attributes: [(name: String, valueRange: Range<Int>?, value: String)]

        func value(_ name: String) -> String? { attributes.first { $0.name == name }?.value }

        var relations: Set<String> {
            Set((value("rel") ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
        }
    }

    enum Token {
        case tag(Tag)
        case comment(Range<Int>)
        case doctype(Range<Int>)
        /// Text between tags; `blank` when it is only whitespace.
        case text(Range<Int>, blank: Bool)
        /// Contents of `<script>`, `<style>`, `<title>`…, which hold no tags.
        case rawText(String, Range<Int>)

        var start: Int {
            switch self {
            case .tag(let tag): tag.range.lowerBound
            case .comment(let range), .doctype(let range), .text(let range, _), .rawText(_, let range): range.lowerBound
            }
        }
    }

    private static let rawTextElements: Set<String> = ["script", "style", "title", "textarea", "xmp", "iframe",
                                                       "noembed", "noframes"]

    /// A forgiving HTML tokenizer: enough to find tags and their attributes the way a browser does.
    static func tokenize(_ b: [UInt8]) -> [Token] {
        var tokens: [Token] = []
        let n = b.count
        var i = 0
        var textStart: Int?
        var blank = true

        func flushText(_ end: Int) {
            if let start = textStart, start < end { tokens.append(.text(start..<end, blank: blank)) }
            textStart = nil
            blank = true
        }
        func find(_ needle: String, from: Int) -> Int? {
            var j = from
            while j < n {
                if matches(b, needle, at: j, limit: n) { return j }
                j += 1
            }
            return nil
        }

        while i < n {
            guard b[i] == UInt8(ascii: "<"), i + 1 < n else {
                if textStart == nil { textStart = i }
                if !isSpace(b[i]) { blank = false }
                i += 1
                continue
            }
            let next = b[i + 1]
            if matches(b, "<!--", at: i, limit: n) {
                flushText(i)
                let end = find("-->", from: i + 2).map { $0 + 3 } ?? n
                tokens.append(.comment(i..<end))
                i = end
                continue
            }
            if next == UInt8(ascii: "!") || next == UInt8(ascii: "?") {
                flushText(i)
                let end = find(">", from: i).map { $0 + 1 } ?? n
                tokens.append(matches(b, "<!doctype", at: i, limit: n) ? .doctype(i..<end) : .comment(i..<end))
                i = end
                continue
            }
            let isEnd = next == UInt8(ascii: "/")
            let nameStart = i + (isEnd ? 2 : 1)
            guard nameStart < n, isLetter(b[nameStart]) else {
                if textStart == nil { textStart = i }
                blank = false
                i += 1
                continue
            }
            flushText(i)
            let start = i
            i = nameStart
            while i < n, !isSpace(b[i]), b[i] != UInt8(ascii: "/"), b[i] != UInt8(ascii: ">") { i += 1 }
            let name = String(decoding: b[nameStart..<i], as: UTF8.self).lowercased()
            var attributes: [(name: String, valueRange: Range<Int>?, value: String)] = []
            while i < n {
                while i < n, isSpace(b[i]) || b[i] == UInt8(ascii: "/") { i += 1 }
                guard i < n, b[i] != UInt8(ascii: ">") else { break }
                let attrStart = i
                i += 1  // A name may start with "=".
                while i < n, !isSpace(b[i]), b[i] != UInt8(ascii: "/"), b[i] != UInt8(ascii: ">"),
                      b[i] != UInt8(ascii: "=") { i += 1 }
                let attrName = String(decoding: b[attrStart..<i], as: UTF8.self).lowercased()
                var j = i
                while j < n, isSpace(b[j]) { j += 1 }
                guard j < n, b[j] == UInt8(ascii: "=") else {
                    attributes.append((attrName, nil, ""))
                    continue
                }
                j += 1
                while j < n, isSpace(b[j]) { j += 1 }
                var valueRange: Range<Int>
                if j < n, b[j] == UInt8(ascii: "\"") || b[j] == UInt8(ascii: "'") {
                    let quote = b[j]
                    var k = j + 1
                    while k < n, b[k] != quote { k += 1 }
                    valueRange = (j + 1)..<k
                    i = min(k + 1, n)
                } else {
                    var k = j
                    while k < n, !isSpace(b[k]), b[k] != UInt8(ascii: ">") { k += 1 }
                    valueRange = j..<k
                    i = k
                }
                attributes.append((attrName, valueRange, String(decoding: b[valueRange], as: UTF8.self)))
            }
            i = min(i + 1, n)
            tokens.append(.tag(Tag(name: name, isEnd: isEnd, range: start..<i, attributes: attributes)))
            if !isEnd, rawTextElements.contains(name) {
                let contentStart = i
                var end = n
                var j = i
                while j < n {
                    if b[j] == UInt8(ascii: "<"), matches(b, "</" + name, at: j, limit: n) {
                        let after = j + 2 + name.utf8.count
                        if after >= n || isSpace(b[after]) || b[after] == UInt8(ascii: ">") || b[after] == UInt8(ascii: "/") {
                            end = j
                            break
                        }
                    }
                    j += 1
                }
                tokens.append(.rawText(name, contentStart..<end))
                i = end
            }
        }
        flushText(n)
        return tokens
    }

    /// Case-insensitive ASCII match of `needle` at `index`.
    private static func matches(_ b: [UInt8], _ needle: String, at index: Int, limit: Int) -> Bool {
        let needle = needle.utf8
        guard index + needle.count <= limit else { return false }
        var j = index
        for c in needle {
            var x = b[j]
            if x >= 0x41 && x <= 0x5A { x += 0x20 }
            if x != c { return false }
            j += 1
        }
        return true
    }

    private static func isSpace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D
    }

    private static func isLetter(_ c: UInt8) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }
}
