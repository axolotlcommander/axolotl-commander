// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
internal import Markdown

/// A Markdown file rendered to a standalone HTML page for the viewer's web view.
public struct MarkdownPage: Sendable, Equatable {
    public var html: String
    /// Text of the first level 1 heading.
    public var title: String?
    /// Internet addresses of images and other resources the page refers to (http, https, //host).
    /// The page loads them only when rendered with `allowRemote`.
    public var remoteResources: [String]
}

/// Markdown (CommonMark with GitHub tables, task lists and strikethrough) → HTML.
///
/// The page never runs scripts and never reaches the network on its own: a Content Security
/// Policy allows images only from the viewer's own scheme and `data:` unless `allowRemote` is set,
/// and forbids scripts, frames, forms and `<base>` regardless.
public enum MarkdownRenderer {
    /// URL scheme the viewer serves the page and local files under: `icmd-doc://local/<absolute path>`.
    public static let scheme = "icmd-doc"
    public static let host = "local"

    /// The page URL for a file on disk; relative links and images resolve against it.
    public static func pageURL(for file: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = file.standardizedFileURL.path
        return components.url!
    }

    /// The file on disk a viewer URL refers to; nil for other URLs.
    public static func fileURL(for url: URL) -> URL? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/") else { return nil }
        return URL(filePath: path).standardizedFileURL
    }

    public static func render(_ markdown: String, allowRemote: Bool = false) -> MarkdownPage {
        let text = markdown.hasPrefix("\u{FEFF}") ? String(markdown.dropFirst()) : markdown
        let (frontMatter, body) = splitFrontMatter(text)
        let document = Document(parsing: body, options: [.disableSmartOpts])
        var writer = HTMLWriter(allowRemote: allowRemote)
        if let frontMatter {
            writer.result += "<pre class=\"front-matter\"><code>\(escape(frontMatter))</code></pre>\n"
        }
        writer.visit(document)
        let html = """
            <!doctype html>
            <html><head>
            <meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="\(policy(allowRemote: allowRemote))">
            <meta http-equiv="x-dns-prefetch-control" content="off">
            <meta name="referrer" content="no-referrer">
            <meta name="color-scheme" content="light dark">
            <style>\(stylesheet)</style>
            </head><body><article>
            \(writer.result)</article></body></html>
            """
        var seen = Set<String>()
        let remote = writer.remote.filter { seen.insert($0).inserted }
        return MarkdownPage(html: html, title: writer.title, remoteResources: remote)
    }

    static func policy(allowRemote: Bool) -> String {
        let local = "\(scheme): data:"
        let images = allowRemote ? "\(local) https: http:" : local
        return "default-src 'none'; img-src \(images); media-src \(images); style-src 'unsafe-inline' \(scheme):; "
            + "font-src \(local); base-uri 'none'; form-action 'none'"
    }

    /// YAML front matter (`---` … `---` at the very start) is shown as a block, not as Markdown.
    static func splitFrontMatter(_ text: String) -> (String?, String) {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return (nil, text) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---"
                                                               || $0.trimmingCharacters(in: .whitespaces) == "..." })
        else { return (nil, text) }
        let front = lines[1..<end].joined(separator: "\n").trimmingCharacters(in: .newlines)
        return (front, lines[(end + 1)...].joined(separator: "\n"))
    }

    static func escape(_ text: some StringProtocol) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for c in text.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }

    /// Internet addresses in `src`, `srcset`, `poster`, `background`, `data` attributes and CSS `url()` of raw HTML.
    static func remoteReferences(inHTML html: String) -> [String] {
        var found: [String] = []
        let attribute = /(?i)(?:src|srcset|poster|background|data|href)\s*=\s*["']?\s*((?:https?:)?\/\/[^"'\s>]+)/
        let css = /(?i)url\(\s*["']?\s*((?:https?:)?\/\/[^"')\s]+)/
        for match in html.matches(of: attribute) where !isLinkTag(html, before: match.range) {
            found.append(String(match.output.1))
        }
        for match in html.matches(of: css) { found.append(String(match.output.1)) }
        return found
    }

    /// `href` loads something only on `<link>`; on `<a>` it is a link the user clicks.
    private static func isLinkTag(_ html: String, before range: Range<String.Index>) -> Bool {
        let head = html[..<range.lowerBound]
        guard let open = head.lastIndex(of: "<") else { return false }
        let tag = head[head.index(after: open)...].prefix { $0.isLetter }.lowercased()
        let isHref = html[range].lowercased().hasPrefix("href")
        return isHref && tag != "link"
    }

    static func isRemote(_ source: String) -> Bool {
        let lower = source.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("//")
    }

    /// GitHub-style heading anchor: lowercase, spaces to dashes, punctuation dropped.
    static func slug(_ text: String) -> String {
        var out = ""
        for c in text.lowercased() {
            if c.isLetter || c.isNumber || c == "-" || c == "_" {
                out.append(c)
            } else if c == " " {
                out.append("-")
            }
        }
        return out
    }

    private struct HTMLWriter: MarkupWalker {
        let allowRemote: Bool
        var result = ""
        var title: String?
        var remote: [String] = []
        var slugs: [String: Int] = [:]
        var inTableHead = false
        var alignments: [Table.ColumnAlignment?] = []
        var column = 0

        init(allowRemote: Bool) { self.allowRemote = allowRemote }

        mutating func visitBlockQuote(_ node: BlockQuote) {
            result += "<blockquote>\n"
            descendInto(node)
            result += "</blockquote>\n"
        }

        mutating func visitCodeBlock(_ node: CodeBlock) {
            let language = node.language?.split(separator: " ").first.map(String.init)
            let attr = language.map { " class=\"language-\(escape($0))\"" } ?? ""
            result += "<pre><code\(attr)>\(CodeMarkup.html(node.code, language: language))</code></pre>\n"
        }

        mutating func visitHeading(_ node: Heading) {
            let text = node.plainText
            if node.level == 1, title == nil { title = text }
            var id = slug(text)
            if let count = slugs[id] {
                slugs[id] = count + 1
                id += "-\(count + 1)"
            } else {
                slugs[id] = 0
            }
            result += "<h\(node.level) id=\"\(escape(id))\">"
            descendInto(node)
            result += "</h\(node.level)>\n"
        }

        mutating func visitThematicBreak(_ node: ThematicBreak) { result += "<hr>\n" }

        mutating func visitHTMLBlock(_ node: HTMLBlock) {
            remote += remoteReferences(inHTML: node.rawHTML)
            result += node.rawHTML
        }

        mutating func visitListItem(_ node: ListItem) {
            if let checkbox = node.checkbox {
                result += "<li class=\"task\"><input type=\"checkbox\" disabled\(checkbox == .checked ? " checked" : "")> "
            } else {
                result += "<li>"
            }
            descendInto(node)
            result += "</li>\n"
        }

        mutating func visitOrderedList(_ node: OrderedList) {
            result += node.startIndex != 1 ? "<ol start=\"\(node.startIndex)\">\n" : "<ol>\n"
            descendInto(node)
            result += "</ol>\n"
        }

        mutating func visitUnorderedList(_ node: UnorderedList) {
            result += "<ul>\n"
            descendInto(node)
            result += "</ul>\n"
        }

        mutating func visitParagraph(_ node: Paragraph) {
            // Tight list items render their text without <p>, as on GitHub.
            let tight = node.parent is ListItem && !isLoose(node.parent?.parent)
            if !tight { result += "<p>" }
            descendInto(node)
            result += tight ? "\n" : "</p>\n"
        }

        mutating func visitTable(_ node: Table) {
            result += "<table>\n"
            alignments = node.columnAlignments
            descendInto(node)
            result += "</table>\n"
        }

        mutating func visitTableHead(_ node: Table.Head) {
            result += "<thead><tr>\n"
            inTableHead = true
            column = 0
            descendInto(node)
            inTableHead = false
            result += "</tr></thead>\n"
        }

        mutating func visitTableBody(_ node: Table.Body) {
            guard !node.isEmpty else { return }
            result += "<tbody>\n"
            descendInto(node)
            result += "</tbody>\n"
        }

        mutating func visitTableRow(_ node: Table.Row) {
            result += "<tr>\n"
            column = 0
            descendInto(node)
            result += "</tr>\n"
        }

        mutating func visitTableCell(_ node: Table.Cell) {
            guard node.colspan > 0, node.rowspan > 0 else { return }
            let element = inTableHead ? "th" : "td"
            result += "<\(element)"
            if column < alignments.count, let alignment = alignments[column] {
                let value = switch alignment {
                case .left: "left"
                case .center: "center"
                case .right: "right"
                }
                result += " style=\"text-align: \(value)\""
            }
            column += 1
            if node.rowspan > 1 { result += " rowspan=\"\(node.rowspan)\"" }
            if node.colspan > 1 { result += " colspan=\"\(node.colspan)\"" }
            result += ">"
            descendInto(node)
            result += "</\(element)>\n"
        }

        mutating func visitInlineCode(_ node: InlineCode) { result += "<code>\(escape(node.code))</code>" }

        mutating func visitEmphasis(_ node: Emphasis) { wrap("em", node) }
        mutating func visitStrong(_ node: Strong) { wrap("strong", node) }
        mutating func visitStrikethrough(_ node: Strikethrough) { wrap("del", node) }

        mutating func visitImage(_ node: Image) {
            var source = node.source ?? ""
            if isRemote(source) {
                remote.append(source)
                if source.hasPrefix("//") { source = "https:" + source }
            }
            result += "<img src=\"\(escape(source))\" alt=\"\(escape(node.plainText))\""
            if let title = node.title, !title.isEmpty { result += " title=\"\(escape(title))\"" }
            result += ">"
        }

        mutating func visitInlineHTML(_ node: InlineHTML) {
            remote += remoteReferences(inHTML: node.rawHTML)
            result += node.rawHTML
        }

        mutating func visitLineBreak(_ node: LineBreak) { result += "<br>\n" }
        mutating func visitSoftBreak(_ node: SoftBreak) { result += "\n" }

        mutating func visitLink(_ node: Link) {
            result += "<a"
            if let destination = node.destination { result += " href=\"\(escape(destination))\"" }
            if let title = node.title, !title.isEmpty { result += " title=\"\(escape(title))\"" }
            result += ">"
            descendInto(node)
            result += "</a>"
        }

        mutating func visitText(_ node: Text) { result += escape(node.string) }

        mutating func visitSymbolLink(_ node: SymbolLink) {
            if let destination = node.destination { result += "<code>\(escape(destination))</code>" }
        }

        /// CommonMark: a list is loose when its items are separated by blank lines
        /// or an item holds blocks separated by one.
        private func isLoose(_ list: (any Markup)?) -> Bool {
            guard let list else { return false }
            let items = Array(list.children)
            for (previous, next) in zip(items, items.dropFirst()) {
                // An item's own range may run into the blank line, so measure from its last block.
                let last = previous.child(at: previous.childCount - 1) ?? previous
                if let end = last.range?.upperBound.line, let start = next.range?.lowerBound.line, start > end + 1 {
                    return true
                }
            }
            return items.contains { item in
                let blocks = Array(item.children)
                return zip(blocks, blocks.dropFirst()).contains { a, b in
                    guard let end = a.range?.upperBound.line, let start = b.range?.lowerBound.line else { return false }
                    return start > end + 1
                }
            }
        }

        private mutating func wrap(_ tag: String, _ node: any Markup) {
            result += "<\(tag)>"
            descendInto(node)
            result += "</\(tag)>"
        }
    }

    static let stylesheet = """
        :root { color-scheme: light dark; --fg: #1f2328; --muted: #59636e; --border: #d1d9e0; --code-bg: rgba(129,139,152,.12);
          --link: #0969da; --quote: #59636e; --row: #f6f8fa;
          --tk-keyword: #cf222e; --tk-type: #8250df; --tk-string: #0a3069; --tk-number: #0550ae; --tk-comment: #59636e;
          --tk-preprocessor: #953800; --tk-tag: #116329; --tk-attribute: #0550ae; --tk-variable: #953800; }
        @media (prefers-color-scheme: dark) { :root { --fg: #e6edf3; --muted: #9198a1; --border: #3d444d; --code-bg: rgba(101,108,118,.25);
          --link: #4493f8; --quote: #9198a1; --row: #151b23;
          --tk-keyword: #ff7b72; --tk-type: #d2a8ff; --tk-string: #a5d6ff; --tk-number: #79c0ff; --tk-comment: #9198a1;
          --tk-preprocessor: #ffa657; --tk-tag: #7ee787; --tk-attribute: #79c0ff; --tk-variable: #ffa657; } }
        html { -webkit-text-size-adjust: 100%; }
        body { margin: 0; background: Canvas; color: var(--fg); font: 15px/1.6 -apple-system, system-ui, sans-serif; }
        article { max-width: 880px; margin: 0 auto; padding: 24px 32px 48px; overflow-wrap: break-word; }
        h1, h2, h3, h4, h5, h6 { margin: 1.5em 0 .6em; line-height: 1.25; font-weight: 600; }
        h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
        h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
        h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; } h6 { font-size: .85em; color: var(--muted); }
        article > :first-child { margin-top: 0; }
        p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
        a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
        ul, ol { padding-left: 2em; } li + li { margin-top: .25em; }
        li.task { list-style: none; } li.task input { margin: 0 .3em 0 -1.4em; vertical-align: middle; }
        blockquote { padding: 0 1em; color: var(--quote); border-left: .25em solid var(--border); }
        code { font: .875em ui-monospace, Menlo, monospace; background: var(--code-bg); padding: .2em .4em; border-radius: 6px; }
        pre { background: var(--code-bg); padding: 16px; border-radius: 6px; overflow: auto; line-height: 1.45; }
        pre code { background: none; padding: 0; font-size: 13px; white-space: pre; }
        pre.front-matter { font-size: 13px; color: var(--muted); }
        table { border-collapse: collapse; display: block; width: max-content; max-width: 100%; overflow: auto; }
        th, td { border: 1px solid var(--border); padding: 6px 13px; }
        th { font-weight: 600; } tr:nth-child(2n) td { background: var(--row); }
        img { max-width: 100%; } hr { height: .25em; margin: 1.5em 0; border: 0; background: var(--border); }
        .tk-keyword { color: var(--tk-keyword); } .tk-type { color: var(--tk-type); } .tk-string { color: var(--tk-string); }
        .tk-number { color: var(--tk-number); } .tk-comment { color: var(--tk-comment); font-style: italic; }
        .tk-preprocessor { color: var(--tk-preprocessor); } .tk-tag { color: var(--tk-tag); }
        .tk-attribute { color: var(--tk-attribute); } .tk-variable { color: var(--tk-variable); }
        """
}

/// Code blocks: escaped text, colored by `SyntaxHighlighter` when the fence names a known language.
enum CodeMarkup {
    static func html(_ code: String, language name: String?) -> String {
        guard let name, let language = SyntaxLanguage.named(name) else { return MarkdownRenderer.escape(code) }
        let text = code as NSString
        var out = ""
        var position = 0
        for span in SyntaxHighlighter.spans(in: code, language: language) where span.range.location >= position {
            out += MarkdownRenderer.escape(text.substring(with: NSRange(location: position, length: span.range.location - position)))
            out += "<span class=\"tk-\(span.kind.rawValue)\">\(MarkdownRenderer.escape(text.substring(with: span.range)))</span>"
            position = NSMaxRange(span.range)
        }
        out += MarkdownRenderer.escape(text.substring(from: position))
        return out
    }
}

extension SyntaxLanguage {
    /// A fenced code block's language: an id ("swift"), a display name ("Python") or an extension ("js", "sh").
    static func named(_ name: String) -> SyntaxLanguage? {
        let key = name.lowercased()
        let aliases = ["bash": "sh", "zsh": "sh", "shell": "sh", "console": "sh", "js": "js", "ts": "ts", "objective-c": "m",
                       "objc": "m", "c++": "cpp", "c#": "cs", "golang": "go", "yml": "yaml", "md": "md", "plaintext": "",
                       "text": "", "txt": ""]
        if let ext = aliases[key] { return ext.isEmpty ? nil : forFile(named: "x." + ext) }
        return all.first { $0.id == key || $0.name.lowercased() == key } ?? forFile(named: "x." + key)
    }
}
