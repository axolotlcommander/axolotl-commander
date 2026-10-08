// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import CommanderCore

// MARK: Markdown

@Suite struct MarkdownRendererTests {
    private func body(_ markdown: String, allowRemote: Bool = false) -> String {
        let html = MarkdownRenderer.render(markdown, allowRemote: allowRemote).html
        let start = html.range(of: "<article>")!.upperBound
        let end = html.range(of: "</article>")!.lowerBound
        return html[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func blocksAndInline() {
        let html = body("# Nadpis\n\nText *důležitý* a **tučný** a `kód`.\n\n- jedna\n- dvě\n")
        #expect(html.contains("<h1 id=\"nadpis\">Nadpis</h1>"))
        #expect(html.contains("<p>Text <em>důležitý</em> a <strong>tučný</strong> a <code>kód</code>.</p>"))
        #expect(html.contains("<ul>\n<li>jedna\n</li>\n<li>dvě\n</li>\n</ul>"))
    }

    @Test func escapesText() {
        let html = body("a < b & \"c\"\n\n```\n<script>alert(1)</script>\n```\n")
        #expect(html.contains("<p>a &lt; b &amp; &quot;c&quot;</p>"))
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(!html.contains("<script>"))
    }

    @Test func titleAndHeadingIDs() {
        let page = MarkdownRenderer.render("Intro\n\n# Žluťoučký kůň!\n\n## Kroky\n\n## Kroky\n")
        #expect(page.title == "Žluťoučký kůň!")
        #expect(page.html.contains("id=\"žluťoučký-kůň\""))
        #expect(page.html.contains("id=\"kroky\""))
        #expect(page.html.contains("id=\"kroky-1\""))
    }

    @Test func tablesTasksStrikethrough() {
        let html = body("| A | B |\n|:--|--:|\n| 1 | 2 |\n\n- [x] hotovo\n- [ ] zbývá\n\n~~pryč~~\n")
        #expect(html.contains("<th style=\"text-align: left\">A</th>"))
        #expect(html.contains("<td style=\"text-align: right\">2</td>"))
        #expect(html.contains("<input type=\"checkbox\" disabled checked> hotovo"))
        #expect(html.contains("<input type=\"checkbox\" disabled> zbývá"))
        #expect(html.contains("<del>pryč</del>"))
    }

    @Test func looseListKeepsParagraphs() {
        let html = body("- a\n\n- b\n")
        #expect(html.contains("<li><p>a</p>"))
    }

    @Test func remoteImagesAreReportedAndBlockedByPolicy() {
        let markdown = """
            ![logo](https://example.com/logo.png) ![local](img/a.png) ![cdn](//cdn.example.com/x.png)

            <p align="center"><img src="http://example.org/badge.svg" width=20></p>

            <a href="https://example.com/page">a link is not a load</a>
            """
        let page = MarkdownRenderer.render(markdown)
        #expect(page.remoteResources == ["https://example.com/logo.png", "//cdn.example.com/x.png",
                                         "http://example.org/badge.svg"])
        #expect(page.html.contains("img-src icmd-doc: data:;"))
        #expect(!page.html.contains("https: http:"))
        #expect(page.html.contains("src=\"https://cdn.example.com/x.png\""))
        #expect(page.html.contains("src=\"img/a.png\""))
        let allowed = MarkdownRenderer.render(markdown, allowRemote: true)
        #expect(allowed.html.contains("img-src icmd-doc: data: https: http:;"))
    }

    @Test func policyForbidsScriptsFramesAndBase() {
        let policy = MarkdownRenderer.policy(allowRemote: true)
        #expect(policy.hasPrefix("default-src 'none';"))
        #expect(!policy.contains("script-src"))
        #expect(policy.contains("base-uri 'none'"))
        #expect(policy.contains("form-action 'none'"))
    }

    @Test func rawHTMLReferences() {
        let refs = MarkdownRenderer.remoteReferences(inHTML: """
            <img srcset="https://a.example/x.png 2x"><div style="background: url('https://b.example/y.jpg')">
            <link rel="stylesheet" href="https://c.example/s.css"><a href="https://d.example">d</a>
            """)
        #expect(refs == ["https://a.example/x.png", "https://c.example/s.css", "https://b.example/y.jpg"])
    }

    @Test func frontMatterAndBOM() {
        let html = body("\u{FEFF}---\ntitle: Ahoj\n---\n# Text\n")
        #expect(html.hasPrefix("<pre class=\"front-matter\"><code>title: Ahoj</code></pre>"))
        #expect(html.contains("<h1 id=\"text\">Text</h1>") || html.contains("<h1"))
    }

    @Test func pageURLRoundTrip() {
        let file = URL(fileURLWithPath: "/Users/x/Dokumenty a věci/READ ME#1.md")
        let url = MarkdownRenderer.pageURL(for: file)
        #expect(url.scheme == "icmd-doc")
        #expect(MarkdownRenderer.fileURL(for: url) == file)
        let image = URL(string: "img/a%20b.png", relativeTo: url)!.absoluteURL
        #expect(MarkdownRenderer.fileURL(for: image)?.path == "/Users/x/Dokumenty a věci/img/a b.png")
        #expect(MarkdownRenderer.fileURL(for: URL(string: "icmd-doc://cdn.example.com/x.png")!) == nil)
        #expect(MarkdownRenderer.fileURL(for: URL(string: "https://local/etc/hosts")!) == nil)
    }

    @Test func codeBlockHighlighting() {
        let html = body("```swift\nlet x = \"a<b\" // ok\n```\n")
        #expect(html.contains("<code class=\"language-swift\">"))
        #expect(html.contains("<span class=\"tk-keyword\">let</span>"))
        #expect(html.contains("<span class=\"tk-string\">&quot;a&lt;b&quot;</span>"))
        #expect(html.contains("<span class=\"tk-comment\">// ok</span>"))
        let plain = body("```nesmysl\na<b\n```\n")
        #expect(plain.contains("a&lt;b"))
    }
}

// MARK: HTML

@Suite struct HTMLPreparerTests {
    private let csp = #"<meta http-equiv="Content-Security-Policy""#

    private func prepared(_ html: String, allowRemote: Bool = false) -> String {
        HTMLPreparer.prepare(html, allowRemote: allowRemote).html
    }

    @Test func policyGoesFirstInHead() {
        let html = prepared("<!DOCTYPE html>\n<HTML lang=cs>\n<!-- c -->\n<HEAD><Meta Charset=windows-1250><title>T</title></HEAD><body>x</body></HTML>")
        #expect(html.hasPrefix("<!DOCTYPE html>\n<HTML lang=cs>\n<!-- c -->\n<HEAD>" + csp))
        #expect(html.contains("<Meta Charset=windows-1250><title>T</title></HEAD>"))
        #expect(HTMLPreparer.prepare("<html><head><title> Název </title></head></html>").title == "Název")
    }

    @Test func createsHeadWhenMissing() {
        #expect(prepared("<html><body>x</body></html>").hasPrefix("<html><head>" + csp))
        #expect(prepared("<!doctype html><p>x").hasPrefix("<!doctype html><head>" + csp))
        let xhtml = #"<?xml version="1.0"?>"# + "\n<!DOCTYPE html>\n" + #"<html xmlns="http://www.w3.org/1999/xhtml">"#
        #expect(prepared("\u{FEFF}" + xhtml + "<body/></html>").hasPrefix(xhtml + "<head>" + csp))
        #expect(prepared("just text").hasPrefix("<head>" + csp))
        #expect(prepared("").hasPrefix("<head>" + csp))
        // A <head> in a comment or a <header> is not the head.
        #expect(prepared("<!-- <head> --><header>h</header>").hasPrefix("<!-- <head> --><head>" + csp))
    }

    @Test func ownPolicyComesBeforeTheDocuments() {
        let html = prepared(#"<html><head><meta http-equiv="Content-Security-Policy" content="default-src *"></head></html>"#)
        let first = html.range(of: "Content-Security-Policy")!
        #expect(html[first.upperBound...].hasPrefix(#"" content="default-src 'none';"#))
        #expect(html.contains(#"content="default-src *""#))
    }

    @Test func policy() {
        let strict = HTMLPreparer.policy(allowRemote: false)
        #expect(strict.hasPrefix("default-src 'none';"))
        #expect(!strict.contains("http"))
        #expect(!strict.contains("script-src"))
        #expect(strict.contains("form-action 'none'"))
        #expect(strict.contains("base-uri icmd-doc:"))
        let open = HTMLPreparer.policy(allowRemote: true)
        #expect(open.hasPrefix("default-src 'none';"))
        #expect(open.contains("img-src icmd-doc: data: https: http:;"))
        #expect(open.contains("style-src 'unsafe-inline' icmd-doc: data: https: http:;"))
        #expect(prepared("<p>x", allowRemote: true).contains(open))
        #expect(prepared("<p>x").contains(strict))
    }

    @Test func countsRemoteResources() {
        let page = HTMLPreparer.prepare("""
            <html><head>
            <link rel="stylesheet" href="https://a.example/s.css"><link rel=canonical href="https://a.example/page">
            <LINK REL="alternate stylesheet" HREF='//b.example/t.css'>
            <style>@import "https://c.example/i.css"; body { background: url( 'https://d.example/bg.png' ) }</style>
            <script src="https://e.example/x.js"></script>
            </head><body background="http://f.example/b.gif">
            <img src="https://g.example/1.png" srcset="local.png 1x, https://g.example/2.png 2x,//h.example/3.png 3x">
            <img src="https://g.example/1.png"> <img src="pic/local.png"> <img src="data:image/png;base64,AAAA">
            <video poster="https://i.example/p.jpg"><source src="https://i.example/v.mp4"></video>
            <div style="background-image:url(https://j.example/k.png)">text</div>
            <a href="https://k.example/">a link is not a load</a>
            <iframe src="https://l.example/frame"></iframe>
            </body></html>
            """)
        #expect(page.remoteResources == [
            "https://a.example/s.css", "//b.example/t.css", "https://c.example/i.css", "https://d.example/bg.png",
            "http://f.example/b.gif", "https://g.example/1.png", "https://g.example/2.png", "//h.example/3.png",
            "https://i.example/p.jpg", "https://i.example/v.mp4", "https://j.example/k.png",
        ])
        // Protocol-relative addresses would resolve against the viewer's scheme.
        #expect(page.html.contains("HREF='https://b.example/t.css'"))
        #expect(page.html.contains(",https://h.example/3.png 3x"))
        #expect(page.html.contains(#"<script src="https://e.example/x.js"></script>"#))
    }

    @Test func removesRefreshBaseAndHints() {
        let html = prepared("""
            <head><META HTTP-EQUIV=Refresh CONTENT="0; url=https://evil.example/">\
            <meta content="5;url=x>y" http-equiv='refresh'>\
            <base href="https://evil.example/"><base href=" //evil.example/"><BASE HREF="file:///etc/">\
            <base href="sub/" target=_self><link rel="preconnect dns-prefetch" href="https://cdn.example">\
            <meta name="viewport" content="width=device-width"></head><body><p>x</p></body>
            """)
        #expect(!html.lowercased().contains("refresh"))
        #expect(!html.contains("evil"))
        #expect(!html.contains("file:"))
        #expect(!html.contains("cdn.example"))
        #expect(html.contains(#"<base href="sub/" target=_self>"#))
        #expect(html.contains(#"<meta name="viewport" content="width=device-width"></head><body><p>x</p></body>"#))
        #expect(html.hasPrefix("<head>" + csp))
    }

    @Test func relativeReferences() {
        #expect(HTMLPreparer.isRelative("sub/dir/"))
        #expect(HTMLPreparer.isRelative("/root/"))
        #expect(HTMLPreparer.isRelative("a.html?x=http://y"))
        #expect(!HTMLPreparer.isRelative("https://x/"))
        #expect(!HTMLPreparer.isRelative("ht\ttps://x/"))
        #expect(!HTMLPreparer.isRelative("//x/"))
        #expect(!HTMLPreparer.isRelative(#"\\x\"#))
        #expect(!HTMLPreparer.isRelative("javascript:alert(1)"))
    }

    @Test func scriptsAndCommentsAreNotParsedAsTags() {
        let page = HTMLPreparer.prepare("""
            <html><head><script>var s = '<img src="https://a.example/x.png"> <base href="https://b.example/">';</script>
            <!-- <img src="https://c.example/y.png"> --></head></html>
            """)
        #expect(page.remoteResources.isEmpty)
        #expect(page.html.contains(#"<base href="https://b.example/">"#))
    }
}

// MARK: Safe writes, image export

/// A fresh folder under the temporary directory, removed by `remove()`.
private struct Scratch {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "icmd-preview-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: url) }
    func names() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.sorted() ?? [] }
}

private func writePNG(_ url: URL, width: Int = 8, height: Int = 4) throws {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    #expect(CGImageDestinationFinalize(destination))
}

@Suite struct SafeWriteTests {
    @Test func replacesOnlyWithCompleteFile() throws {
        let dir = try Scratch()
        defer { dir.remove() }
        let target = dir.url.appending(path: "a.txt")
        try Data("old".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
        try SafeFileWriter.write(to: target) { try Data("new".utf8).write(to: $0) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "new")
        #expect(try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int == 0o640)
        #expect(dir.names() == ["a.txt"])
    }

    @Test func failureLeavesTargetAndNoTemp() throws {
        let dir = try Scratch()
        defer { dir.remove() }
        let target = dir.url.appending(path: "a.txt")
        try Data("old".utf8).write(to: target)
        struct Broken: Error {}
        #expect(throws: Broken.self) {
            try SafeFileWriter.write(to: target) { temp in
                try Data("half".utf8).write(to: temp)
                throw Broken()
            }
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "old")
        #expect(dir.names() == ["a.txt"])
    }

    @Test func cancelledWriteLeavesTarget() async throws {
        let dir = try Scratch()
        defer { dir.remove() }
        let target = dir.url.appending(path: "a.txt")
        try Data("old".utf8).write(to: target)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try SafeFileWriter.write(to: target) { try Data("new".utf8).write(to: $0) }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try String(contentsOf: target, encoding: .utf8) == "old")
        #expect(dir.names() == ["a.txt"])
    }

    @Test func newFileAndSymlinkTarget() throws {
        let dir = try Scratch()
        defer { dir.remove() }
        let fresh = dir.url.appending(path: "new.txt")
        try SafeFileWriter.write(to: fresh) { try Data("x".utf8).write(to: $0) }
        #expect(try String(contentsOf: fresh, encoding: .utf8) == "x")
        let link = dir.url.appending(path: "link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fresh)
        try SafeFileWriter.write(to: link) { try Data("y".utf8).write(to: $0) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == fresh.path)
        #expect(try String(contentsOf: fresh, encoding: .utf8) == "y")
    }
}

@Suite struct ImageExportTests {
    @Test func pngToJPEGOverExistingFile() throws {
        let dir = try Scratch()
        defer { dir.remove() }
        let png = dir.url.appending(path: "obrázek.png")
        let jpeg = dir.url.appending(path: "obrázek.jpg")
        try writePNG(png)
        try Data("old".utf8).write(to: jpeg)
        try ImageExport.export(png, to: jpeg, format: .jpeg, quality: 0.8)
        let bytes = try Data(contentsOf: jpeg)
        #expect(bytes.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
        let info = try #require(ImageInfo.read(jpeg))
        #expect(info.width == 8 && info.height == 4)
        #expect(info.type == UTType.jpeg.identifier)
        #expect(dir.names() == ["obrázek.jpg", "obrázek.png"])
    }

    @Test func unreadableSourceKeepsTarget() throws {
        let dir = try Scratch()
        defer { dir.remove() }
        let fake = dir.url.appending(path: "fake.png")
        let target = dir.url.appending(path: "out.jpg")
        try Data("not an image".utf8).write(to: fake)
        try Data("old".utf8).write(to: target)
        #expect(throws: ImageExportError.unreadable) {
            try ImageExport.export(fake, to: target, format: .jpeg)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "old")
        #expect(dir.names() == ["fake.png", "out.jpg"])
    }

    @Test func readOnlyFolderReportsWriteErrorAndKeepsTarget() throws {
        let dir = try Scratch()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.url.appending(path: "ro").path)
            dir.remove()
        }
        let png = dir.url.appending(path: "a.png")
        try writePNG(png)
        let folder = dir.url.appending(path: "ro")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let target = folder.appending(path: "x.jpg")
        try Data("old".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        #expect(throws: CocoaError.self) { try ImageExport.export(png, to: target, format: .jpeg) }
        #expect(try String(contentsOf: target, encoding: .utf8) == "old")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["x.jpg"])
    }

    @Test func saveOverItself() throws {
        let dir = try Scratch()
        defer { dir.remove() }
        let png = dir.url.appending(path: "a.png")
        try writePNG(png, width: 5, height: 3)
        try ImageExport.export(png, to: png, format: .png)
        #expect(ImageInfo.read(png)?.width == 5)
        #expect(dir.names() == ["a.png"])
    }

    @Test func formatsAndReadability() {
        #expect(ImageFormat.forFile(named: "foto.JPG") == .jpeg)
        #expect(ImageFormat.forFile(named: "a.jpeg") == .jpeg)
        #expect(ImageFormat.forFile(named: "a.tif") == .tiff)
        #expect(ImageFormat.forFile(named: "a.txt") == nil)
        #expect(ImageFormat.jpeg.hasQuality && !ImageFormat.png.hasQuality)
        #expect(ImageExport.canRead(URL(fileURLWithPath: "/x/a.png")))
        #expect(ImageExport.canRead(URL(fileURLWithPath: "/x/a.HEIC")))
        #expect(!ImageExport.canRead(URL(fileURLWithPath: "/x/a.md")))
        #expect(!ImageExport.canRead(URL(fileURLWithPath: "/x/a.pdf")))
    }
}
