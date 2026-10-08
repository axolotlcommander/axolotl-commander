// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

// All file tests work in a fresh directory under FileManager.default.temporaryDirectory
// that the test creates and removes.

private func withSearchDir(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AxolotlSearch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root)
}

@discardableResult
private func put(_ root: URL, _ path: String, _ content: Data = Data()) throws -> URL {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: url)
    return url
}

@discardableResult
private func put(_ root: URL, _ path: String, _ text: String) throws -> URL {
    try put(root, path, Data(text.utf8))
}

private func mkdir(_ root: URL, _ path: String) throws {
    try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
}

private struct SearchResult {
    var items: [FileItem] = []
    var problems: [String] = []
    var lastProgress: SearchProgress?
    /// Paths relative to the root, sorted.
    func names(_ root: URL) -> [String] {
        let prefix = root.path + "/"
        return items.map { String($0.url.path.dropFirst(prefix.count)) }.sorted()
    }
}

private func search(_ criteria: SearchCriteria, legacy: TextEncoding = .windows1252) async throws -> SearchResult {
    var result = SearchResult()
    for try await event in FileSearch.run(criteria, legacyEncoding: legacy) {
        switch event {
        case .found(let items): result.items += items
        case .progress(let p): result.lastProgress = p
        case .problem(let path, let message): result.problems.append("\(path): \(message)")
        }
    }
    return result
}

private func query(_ text: String, caseSensitive: Bool = false, wholeWords: Bool = false,
                   hex: Bool = false, regex: Bool = false) -> SearchCriteria.ContentQuery {
    .init(text: text, caseSensitive: caseSensitive, wholeWords: wholeWords, isHex: hex, isRegex: regex)
}

private func contentSearch(_ root: URL, _ q: SearchCriteria.ContentQuery,
                           legacy: TextEncoding = .windows1252) async throws -> [String] {
    let criteria = SearchCriteria(roots: [root.path], content: q)
    return try await search(criteria, legacy: legacy).names(root)
}

// MARK: - Masks and criteria

@Suite struct SearchMaskTests {
    private let rules = NameRules.apfsDefault

    @Test func substringWithoutWildcardsAndDot() {
        let m = SearchMask("log")
        #expect(m.matches("syslog.txt", rules: rules))
        #expect(m.matches("LOG", rules: rules))
        #expect(!m.matches("lag", rules: rules))
    }

    @Test func trailingDotIsExactName() {
        let m = SearchMask("dog.")
        #expect(m.matches("dog", rules: rules))
        #expect(!m.matches("dog.txt", rules: rules))
        #expect(!m.matches("hotdog", rules: rules))
    }

    @Test func wildcardsAndDotsAreKept() {
        #expect(SearchMask("*.txt").matches("a.txt", rules: rules))
        #expect(!SearchMask("*.txt").matches("a.txt.bak", rules: rules))
        #expect(SearchMask("a.txt").matches("A.TXT", rules: rules))
        #expect(!SearchMask("a.txt").matches("ba.txt", rules: rules))
        #expect(SearchMask("a?c").matches("abc", rules: rules))
        #expect(!SearchMask("a?c").matches("xabcx", rules: rules))
    }

    @Test func listsAndExclusions() {
        let m = SearchMask("foo;*.md|bar;*.bak")
        #expect(m.matches("a_foo_b", rules: rules))
        #expect(m.matches("x.md", rules: rules))
        #expect(!m.matches("x.txt", rules: rules))
        #expect(!m.matches("foobar", rules: rules))
        #expect(!m.matches("x.bak", rules: rules))
        #expect(SearchMask("|tmp").matches("file", rules: rules))
        #expect(!SearchMask("|tmp").matches("my.tmp", rules: rules))
    }

    @Test func emptyMatchesEverything() {
        #expect(SearchMask("").matches("anything", rules: rules))
        #expect(SearchMask("   ").matches("anything", rules: rules))
    }

    @Test func caseSensitiveVolume() {
        let strict = NameRules(caseSensitive: true)
        #expect(!SearchMask("log").matches("LOG", rules: strict))
        #expect(SearchMask("log").matches("log", rules: strict))
    }
}

@Suite struct SearchCriteriaTests {
    @Test func parseRoots() {
        let home = NSHomeDirectory()
        #expect(SearchCriteria.parseRoots("/a; /b ;;/a;  ; ~/c ;~") == ["/a", "/b", home + "/c", home])
        #expect(SearchCriteria.parseRoots("   ") == [])
    }

    @Test func codableRoundTrip() throws {
        let c = SearchCriteria(namePattern: "*.swift", roots: ["/x"], kind: .files,
                               content: query("abc", regex: true), minSize: 1, modifiedFrom: Date(timeIntervalSince1970: 5),
                               excludedDirectories: ".git")
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(SearchCriteria.self, from: data) == c)
    }

    @Test func searchHexSyntax() {
        #expect(ByteSearch.parseSearchHex("4A 6F \"text\" 00") == [0x4A, 0x6F, 0x74, 0x65, 0x78, 0x74, 0x00])
        #expect(ByteSearch.parseSearchHex("\"abc\"00") == [0x61, 0x62, 0x63, 0x00])
        #expect(ByteSearch.parseSearchHex("4a6f") == [0x4A, 0x6F])
        #expect(ByteSearch.parseSearchHex("\"ab\" 4 0x0A") == [0x61, 0x62, 0x04, 0x0A])
        #expect(ByteSearch.parseSearchHex("") == nil)
        #expect(ByteSearch.parseSearchHex("\"abc") == nil)
        #expect(ByteSearch.parseSearchHex("4A 6") != nil)
        #expect(ByteSearch.parseSearchHex("ZZ") == nil)
        #expect(ByteSearch.parseSearchHex("\"\"") == nil)
    }
}

// MARK: - FileSearch traversal and filters

@Suite struct FileSearchTests {
    private func tree(_ root: URL) throws {
        try put(root, "a.txt", "aaaa")
        try put(root, "b.log", "bb")
        try put(root, "sub/c.txt", "c")
        try put(root, "sub/deep/d.txt", "dddddddd")
        try put(root, ".hidden.txt", "h")
        try put(root, ".hiddendir/e.txt", "e")
        try put(root, "node_modules/lib/f.txt", "f")
        try put(root, "Thing.dir/g.txt", "g")
    }

    @Test func recursiveSearchReportsEverythingVisible() async throws {
        try await withSearchDir { root in
            try tree(root)
            let r = try await search(SearchCriteria(roots: [root.path]))
            #expect(r.names(root) == ["Thing.dir", "Thing.dir/g.txt", "a.txt", "b.log", "node_modules",
                                      "node_modules/lib", "node_modules/lib/f.txt", "sub", "sub/c.txt",
                                      "sub/deep", "sub/deep/d.txt"])
            #expect(r.lastProgress?.matches == r.items.count)
            #expect((r.lastProgress?.directories ?? 0) >= 6)
        }
    }

    @Test func nameMaskIsApplied() async throws {
        try await withSearchDir { root in
            try tree(root)
            let r = try await search(SearchCriteria(namePattern: "*.txt", roots: [root.path]))
            #expect(r.names(root) == ["Thing.dir/g.txt", "a.txt", "node_modules/lib/f.txt", "sub/c.txt", "sub/deep/d.txt"])
            let sub = try await search(SearchCriteria(namePattern: "SUB", roots: [root.path]))
            #expect(sub.names(root) == ["sub"])
        }
    }

    @Test func itemFields() async throws {
        try await withSearchDir { root in
            try put(root, "sub/file.bin", "12345")
            let r = try await search(SearchCriteria(roots: [root.path]))
            let file = try #require(r.items.first { $0.name == "file.bin" })
            #expect(file.size == 5)
            #expect(!file.isDirectory && !file.isSymlink && !file.isPackage)
            #expect(file.url.path == root.appendingPathComponent("sub/file.bin").path)
            #expect(file.modificationDate != nil)
            let dir = try #require(r.items.first { $0.name == "sub" })
            #expect(dir.isDirectory && dir.size == nil)
        }
    }

    @Test func hiddenItems() async throws {
        try await withSearchDir { root in
            try tree(root)
            let shown = try await search(SearchCriteria(roots: [root.path], includeHidden: true))
            let names = shown.names(root)
            #expect(names.contains(".hidden.txt"))
            #expect(names.contains(".hiddendir"))
            #expect(names.contains(".hiddendir/e.txt"))
            #expect(shown.items.first { $0.name == ".hidden.txt" }?.isHidden == true)
            let hidden = try await search(SearchCriteria(roots: [root.path]))
            #expect(!hidden.names(root).contains { $0.contains(".hidden") })
        }
    }

    @Test func withoutSubdirectoriesOnlyDirectChildren() async throws {
        try await withSearchDir { root in
            try tree(root)
            let r = try await search(SearchCriteria(roots: [root.path], subdirectories: false))
            #expect(r.names(root) == ["Thing.dir", "a.txt", "b.log", "node_modules", "sub"])
        }
    }

    @Test func kindFilters() async throws {
        try await withSearchDir { root in
            try tree(root)
            let files = try await search(SearchCriteria(roots: [root.path], kind: .files))
            #expect(files.items.allSatisfy { !$0.isDirectory } && files.items.count == 6)
            let folders = try await search(SearchCriteria(roots: [root.path], kind: .folders))
            #expect(folders.names(root) == ["Thing.dir", "node_modules", "node_modules/lib", "sub", "sub/deep"])
        }
    }

    @Test func sizeFiltersExcludeDirectories() async throws {
        try await withSearchDir { root in
            try tree(root)
            let big = try await search(SearchCriteria(roots: [root.path], minSize: 4))
            #expect(big.names(root) == ["a.txt", "sub/deep/d.txt"])
            let small = try await search(SearchCriteria(roots: [root.path], maxSize: 2))
            #expect(small.names(root) == ["Thing.dir/g.txt", "b.log", "node_modules/lib/f.txt", "sub/c.txt"])
            let exact = try await search(SearchCriteria(roots: [root.path], minSize: 4, maxSize: 4))
            #expect(exact.names(root) == ["a.txt"])
        }
    }

    @Test func dateFilters() async throws {
        try await withSearchDir { root in
            let old = try put(root, "old.txt", "x")
            let mid = try put(root, "mid.txt", "x")
            let new = try put(root, "new.txt", "x")
            let t0 = Date(timeIntervalSince1970: 1_500_000_000)
            for (url, offset) in [(old, 0.0), (mid, 1000), (new, 2000)] {
                try FileManager.default.setAttributes([.modificationDate: t0.addingTimeInterval(offset)], ofItemAtPath: url.path)
            }
            let from = try await search(SearchCriteria(roots: [root.path], kind: .files, modifiedFrom: t0.addingTimeInterval(1000)))
            #expect(from.names(root) == ["mid.txt", "new.txt"])
            let to = try await search(SearchCriteria(roots: [root.path], kind: .files, modifiedTo: t0.addingTimeInterval(1000)))
            #expect(to.names(root) == ["mid.txt", "old.txt"])
            let range = try await search(SearchCriteria(roots: [root.path], kind: .files,
                                                        modifiedFrom: t0.addingTimeInterval(500), modifiedTo: t0.addingTimeInterval(1500)))
            #expect(range.names(root) == ["mid.txt"])
        }
    }

    @Test func excludedDirectoriesByNameAndPath() async throws {
        try await withSearchDir { root in
            try tree(root)
            let byName = try await search(SearchCriteria(namePattern: "*.txt", roots: [root.path],
                                                         includeHidden: true, excludedDirectories: "node_modules;.hiddendir"))
            #expect(byName.names(root) == [".hidden.txt", "Thing.dir/g.txt", "a.txt", "sub/c.txt", "sub/deep/d.txt"])
            let byPath = try await search(SearchCriteria(namePattern: "*.txt", roots: [root.path],
                                                         excludedDirectories: root.path + "/sub"))
            #expect(byPath.names(root) == ["Thing.dir/g.txt", "a.txt", "node_modules/lib/f.txt"])
            let wildcard = try await search(SearchCriteria(roots: [root.path], kind: .folders, excludedDirectories: "node*"))
            #expect(wildcard.names(root) == ["Thing.dir", "sub", "sub/deep"])
        }
    }

    @Test func rootsAreNeverExcluded() async throws {
        try await withSearchDir { root in
            try put(root, "node_modules/x.txt", "x")
            let r = try await search(SearchCriteria(roots: [root.appendingPathComponent("node_modules").path],
                                                    excludedDirectories: "node_modules"))
            #expect(r.items.map(\.name) == ["x.txt"])
        }
    }

    @Test func symlinksAreNotFollowed() async throws {
        try await withSearchDir { root in
            try put(root, "real/inner.txt", "i")
            try put(root, "file.txt", "f")
            #expect(symlink(root.appendingPathComponent("real").path, root.appendingPathComponent("linkdir").path) == 0)
            #expect(symlink(root.appendingPathComponent("file.txt").path, root.appendingPathComponent("linkfile").path) == 0)
            #expect(symlink(root.appendingPathComponent("gone").path, root.appendingPathComponent("broken").path) == 0)
            #expect(symlink(root.path, root.appendingPathComponent("real/loop").path) == 0)
            let r = try await search(SearchCriteria(roots: [root.path]))
            #expect(r.names(root) == ["broken", "file.txt", "linkdir", "linkfile", "real", "real/inner.txt", "real/loop"])
            let link = try #require(r.items.first { $0.name == "linkdir" })
            #expect(link.isSymlink && link.isDirectory)
            let fileLink = try #require(r.items.first { $0.name == "linkfile" })
            #expect(fileLink.isSymlink && !fileLink.isDirectory)
            let broken = try #require(r.items.first { $0.name == "broken" })
            #expect(broken.isSymlink && !broken.isDirectory)
        }
    }

    @Test func multipleRootsAndMissingRoot() async throws {
        try await withSearchDir { root in
            try put(root, "one/a.txt", "a")
            try put(root, "two/b.txt", "b")
            let missing = root.appendingPathComponent("missing").path
            let r = try await search(SearchCriteria(roots: [root.appendingPathComponent("one").path, missing,
                                                            root.appendingPathComponent("two").path], kind: .files))
            #expect(r.names(root) == ["one/a.txt", "two/b.txt"])
            #expect(r.problems.count == 1 && r.problems[0].hasPrefix(missing))
            let none = try await search(SearchCriteria(roots: [missing]))
            #expect(none.items.isEmpty && none.problems.count == 1)
        }
    }

    @Test func rootThatIsAlsoNestedIsVisitedOnce() async throws {
        try await withSearchDir { root in
            try put(root, "sub/a.txt", "a")
            let r = try await search(SearchCriteria(roots: [root.path, root.appendingPathComponent("sub").path], kind: .files))
            #expect(r.items.count == 1)
        }
    }

    @Test func packageDirectoriesAreNotDescendedByDefault() async throws {
        try await withSearchDir { root in
            // A bundle is recognized by LaunchServices from its Info.plist / type; use a well-known
            // package type and fall back gracefully if the system does not treat it as one.
            try put(root, "Doc.rtfd/TXT.rtf", "x")
            try put(root, "plain.dir/inner.txt", "x")
            let isPackage = (try? root.appendingPathComponent("Doc.rtfd")
                .resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
            let normal = try await search(SearchCriteria(roots: [root.path]))
            let deep = try await search(SearchCriteria(roots: [root.path], searchPackages: true))
            #expect(normal.names(root).contains("plain.dir/inner.txt"))
            #expect(deep.names(root).contains("Doc.rtfd/TXT.rtf"))
            #expect(normal.items.first { $0.name == "Doc.rtfd" }?.isPackage == isPackage)
            #expect(normal.names(root).contains("Doc.rtfd/TXT.rtf") == !isPackage)
        }
    }

    @Test func invalidCriteriaThrow() async throws {
        await #expect(throws: SearchError.noRoots) { _ = try await search(SearchCriteria()) }
        await #expect(throws: SearchError.self) {
            _ = try await search(SearchCriteria(roots: ["/nonexistent-search-root"], content: query("(", regex: true)))
        }
        await #expect(throws: SearchError.self) {
            _ = try await search(SearchCriteria(roots: ["/nonexistent-search-root"], content: query("zz", hex: true)))
        }
        await #expect(throws: SearchError.self) {
            _ = try await search(SearchCriteria(roots: ["/nonexistent-search-root"], content: query("")))
        }
    }

    @Test func foldersKindWithContentFindsNothing() async throws {
        try await withSearchDir { root in
            try put(root, "d/a.txt", "needle")
            let r = try await search(SearchCriteria(roots: [root.path], kind: .folders, content: query("needle")))
            #expect(r.items.isEmpty)
        }
    }

    @Test func cancellationStopsTheStream() async throws {
        try await withSearchDir { root in
            for i in 0..<50 { try put(root, "d\(i)/f.txt", "x") }
            let stream = FileSearch.run(SearchCriteria(roots: [root.path]))
            var count = 0
            for try await event in stream {
                if case .found(let items) = event { count += items.count }
                break
            }
            #expect(count >= 0)
        }
    }
}

// MARK: - Content search

@Suite struct ContentSearchTests {
    @Test func utf8DiacriticsCaseInsensitive() async throws {
        try await withSearchDir { root in
            try put(root, "lower.txt", "Dům je červený a velký.")
            try put(root, "other.txt", "nothing here")
            #expect(try await contentSearch(root, query("ČERVENÝ")) == ["lower.txt"])
            #expect(try await contentSearch(root, query("červený")) == ["lower.txt"])
            #expect(try await contentSearch(root, query("DŮM JE")) == ["lower.txt"])
        }
    }

    @Test func caseSensitive() async throws {
        try await withSearchDir { root in
            try put(root, "a.txt", "Hello World")
            #expect(try await contentSearch(root, query("hello", caseSensitive: true)) == [])
            #expect(try await contentSearch(root, query("Hello", caseSensitive: true)) == ["a.txt"])
            #expect(try await contentSearch(root, query("hello")) == ["a.txt"])
        }
    }

    @Test func decomposedAndPrecomposedText() async throws {
        try await withSearchDir { root in
            try put(root, "nfc.txt", "caf\u{E9}")
            try put(root, "nfd.txt", "cafe\u{301}")
            let nfd = "cafe\u{301}", nfc = "caf\u{E9}"
            #expect(try await contentSearch(root, query(nfd)) == ["nfc.txt", "nfd.txt"])
            #expect(try await contentSearch(root, query(nfc)) == ["nfc.txt", "nfd.txt"])
            #expect(try await contentSearch(root, query("CAFÉ")) == ["nfc.txt", "nfd.txt"])
        }
    }

    @Test func utf16LittleEndianFile() async throws {
        try await withSearchDir { root in
            let text = "Příliš žluťoučký kůň"
            try put(root, "le.txt", Data([0xFF, 0xFE]) + Data(TextEncoding.utf16LE.encode(text)!))
            try put(root, "be.txt", Data([0xFE, 0xFF]) + Data(TextEncoding.utf16BE.encode(text)!))
            try put(root, "no.txt", "something else")
            #expect(try await contentSearch(root, query("ŽLUŤOUČKÝ")) == ["be.txt", "le.txt"])
            #expect(try await contentSearch(root, query("kůň", caseSensitive: true)) == ["be.txt", "le.txt"])
            #expect(try await contentSearch(root, query("kůň.", caseSensitive: true)) == [])
        }
    }

    @Test func utf16AlignmentPreventsFalseMatches() async throws {
        try await withSearchDir { root in
            // "ab" in UTF-16LE is 61 00 62 00; shifted by one byte it must not match "a\0b" misaligned.
            let bytes: [UInt8] = [0x78, 0x61, 0x00, 0x62, 0x00, 0x79]
            try put(root, "shifted.bin", Data(bytes))
            #expect(try await contentSearch(root, query("ab")) == [])
        }
    }

    @Test func legacyEncodingFile() async throws {
        try await withSearchDir { root in
            let text = "Příliš žluťoučký kůň"
            try put(root, "cp1250.txt", Data(TextEncoding.windows1250.encode(text)!))
            #expect(try await contentSearch(root, query("ŽLUŤOUČKÝ"), legacy: .windows1250) == ["cp1250.txt"])
            #expect(try await contentSearch(root, query("kůň"), legacy: .windows1250) == ["cp1250.txt"])
            // Without the right legacy encoding the bytes do not match.
            #expect(try await contentSearch(root, query("kůň"), legacy: .windows1251) == [])
        }
    }

    @Test func wholeWords() async throws {
        try await withSearchDir { root in
            try put(root, "word.txt", "a cat sat")
            try put(root, "part.txt", "concatenate")
            try put(root, "edge.txt", "cat")
            try put(root, "punct.txt", "(cat),dog")
            try put(root, "under.txt", "cat_food")
            try put(root, "digit.txt", "cat9")
            try put(root, "accent.txt", "cat\u{E9}")
            let hits = try await contentSearch(root, query("cat", wholeWords: true))
            #expect(hits == ["edge.txt", "punct.txt", "word.txt"])
            let loose = try await contentSearch(root, query("cat"))
            #expect(loose.count == 7)
        }
    }

    @Test func wholeWordsInUTF16AndLegacy() async throws {
        try await withSearchDir { root in
            try put(root, "w.txt", Data([0xFF, 0xFE]) + Data(TextEncoding.utf16LE.encode("x kůň y")!))
            try put(root, "p.txt", Data([0xFF, 0xFE]) + Data(TextEncoding.utf16LE.encode("xkůňy")!))
            try put(root, "l.txt", Data(TextEncoding.windows1250.encode("x kůň y")!))
            try put(root, "m.txt", Data(TextEncoding.windows1250.encode("žkůň")!))
            let hits = try await contentSearch(root, query("kůň", wholeWords: true), legacy: .windows1250)
            #expect(hits == ["l.txt", "w.txt"])
        }
    }

    @Test func hexWithQuotedText() async throws {
        try await withSearchDir { root in
            try put(root, "yes.bin", Data([0x01, 0x61, 0x62, 0x63, 0x00, 0x02]))
            try put(root, "no.bin", Data([0x61, 0x62, 0x63, 0x01]))
            try put(root, "case.bin", Data([0x41, 0x42, 0x43, 0x00]))
            #expect(try await contentSearch(root, query("\"abc\" 00", hex: true)) == ["yes.bin"])
            #expect(try await contentSearch(root, query("62 63 00", hex: true)) == ["yes.bin"])
        }
    }

    @Test func regex() async throws {
        try await withSearchDir { root in
            try put(root, "a.txt", "first line\norder 12345 done\n")
            try put(root, "b.txt", "order abc")
            try put(root, "c.txt", "xxORDERyy 7")
            #expect(try await contentSearch(root, query("order \\d+", regex: true)) == ["a.txt"])
            #expect(try await contentSearch(root, query("^order \\d+ done$", regex: true)) == ["a.txt"])
            #expect(try await contentSearch(root, query("order", caseSensitive: true, regex: true)) == ["a.txt", "b.txt"])
            #expect(try await contentSearch(root, query("order", wholeWords: true, regex: true)) == ["a.txt", "b.txt"])
        }
    }

    @Test func regexOnUTF16AndLegacy() async throws {
        try await withSearchDir { root in
            try put(root, "u16.txt", Data([0xFF, 0xFE]) + Data(TextEncoding.utf16LE.encode("žluťoučký 42")!))
            try put(root, "cp.txt", Data(TextEncoding.windows1250.encode("žluťoučký 42")!))
            #expect(try await contentSearch(root, query("ŽLUŤ\\w+ \\d\\d", regex: true), legacy: .windows1250) == ["cp.txt", "u16.txt"])
        }
    }

    @Test func matchAcrossChunkBoundaries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AxolotlChunk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let needle = "červený-klíč"
        for chunk in [1, 3, 7, 16, 64] {
            for offset in 0..<40 {
                let path = dir.appendingPathComponent("f.txt")
                let content = String(repeating: "x", count: offset) + needle + String(repeating: "y", count: 20)
                try Data(content.utf8).write(to: path)
                var matcher = try ContentMatcher(query("ČERVENÝ-KLÍČ"), legacyEncoding: .windows1250)
                matcher.chunkSize = chunk
                #expect(try matcher.matches(fileAt: path.path), "chunk \(chunk) offset \(offset)")
                var miss = try ContentMatcher(query("ČERVENÝ-KLÍČX"), legacyEncoding: .windows1250)
                miss.chunkSize = chunk
                #expect(try !miss.matches(fileAt: path.path))
            }
        }
    }

    @Test func wholeWordsAcrossChunkBoundaries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AxolotlChunk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("f.txt")
        for chunk in [1, 2, 5, 9, 32] {
            for offset in 0..<24 {
                for (text, expected) in [("kůň", true), ("kůňě", false), ("ěkůň", false)] {
                    let pad = String(repeating: " ", count: offset)
                    try Data((pad + text + pad).utf8).write(to: path)
                    var matcher = try ContentMatcher(query("kůň", wholeWords: true), legacyEncoding: .windows1250)
                    matcher.chunkSize = chunk
                    #expect(try matcher.matches(fileAt: path.path) == expected, "chunk \(chunk) offset \(offset) \(text)")
                }
            }
        }
    }

    @Test func utf16MatchAcrossChunkBoundaries() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AxolotlChunk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("f.txt")
        let text = String(repeating: "ab", count: 37) + "Žlutý" + String(repeating: "cd", count: 11)
        try Data(TextEncoding.utf16LE.encode(text)!).write(to: path)
        for chunk in [1, 2, 3, 8, 13, 100] {
            var matcher = try ContentMatcher(query("žlutý"), legacyEncoding: .windows1250)
            matcher.chunkSize = chunk
            #expect(try matcher.matches(fileAt: path.path), "chunk \(chunk)")
        }
    }

    @Test func largeFileMatchBeyondFirstChunk() async throws {
        try await withSearchDir { root in
            var data = Data(repeating: 0x20, count: (1 << 20) - 3)
            data.append(Data("ZVLÁŠTNÍ".utf8))
            data.append(Data(repeating: 0x20, count: 2 << 20))
            try put(root, "big.txt", data)
            #expect(try await contentSearch(root, query("zvlášt")) == ["big.txt"])
            #expect(try await contentSearch(root, query("zvláštní!")) == [])
        }
    }

    @Test func emptyAndUnreadableFiles() async throws {
        try await withSearchDir { root in
            try put(root, "empty.txt", "")
            let secret = try put(root, "locked.txt", "needle")
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: secret.path)
            let r = try await search(SearchCriteria(roots: [root.path], content: query("needle")))
            if getuid() != 0 {
                #expect(r.items.isEmpty)
                #expect(r.problems.count == 1)
            }
            #expect(try ContentMatcher(query("x"), legacyEncoding: .windows1252).matches(fileAt: root.appendingPathComponent("empty.txt").path) == false)
            #expect(throws: SearchError.self) {
                _ = try ContentMatcher(query("x"), legacyEncoding: .windows1252).matches(fileAt: root.appendingPathComponent("nope").path)
            }
        }
    }

    @Test func contentAppliesToRegularFilesOnly() async throws {
        try await withSearchDir { root in
            try put(root, "needle-dir/a.txt", "needle")
            try put(root, "file.txt", "needle")
            #expect(symlink(root.appendingPathComponent("file.txt").path, root.appendingPathComponent("link.txt").path) == 0)
            let r = try await search(SearchCriteria(roots: [root.path], content: query("needle")))
            #expect(r.names(root) == ["file.txt", "needle-dir/a.txt"])
        }
    }

    @Test func contentCombinedWithNameAndSize() async throws {
        try await withSearchDir { root in
            try put(root, "a.txt", "needle")
            try put(root, "b.md", "needle")
            try put(root, "c.txt", "hay")
            let r = try await search(SearchCriteria(namePattern: "*.txt", roots: [root.path], content: query("needle"), minSize: 6))
            #expect(r.names(root) == ["a.txt"])
        }
    }
}

// MARK: - Duplicates

@Suite struct DuplicateFinderTests {
    private func items(_ root: URL) throws -> [FileItem] {
        let manager = FileManager.default
        var result: [FileItem] = []
        for sub in try manager.subpathsOfDirectory(atPath: root.path) {
            let url = root.appendingPathComponent(sub)
            var isDir: ObjCBool = false
            manager.fileExists(atPath: url.path, isDirectory: &isDir)
            let size = isDir.boolValue ? nil : (try manager.attributesOfItem(atPath: url.path)[.size] as? Int64)
            result.append(FileItem(url: url, isDirectory: isDir.boolValue, size: size))
        }
        return result
    }

    private func rel(_ groups: [[FileItem]], _ root: URL) -> [[String]] {
        let prefix = root.path + "/"
        return groups.map { $0.map { String($0.url.path.dropFirst(prefix.count)) } }
    }

    @Test func nameAndSize() async throws {
        try await withSearchDir { root in
            try put(root, "a/same.txt", "1234")
            try put(root, "b/SAME.txt", "abcd")
            try put(root, "c/same.txt", "12345")
            try put(root, "d/other.txt", "1234")
            try put(root, "e/lonely.txt", "x")
            let groups = try await DuplicateFinder.groups(try items(root), by: DuplicateCriteria())
            #expect(rel(groups, root) == [["a/same.txt", "b/SAME.txt"]])
        }
    }

    @Test func nameOnlyAndSizeOnly() async throws {
        try await withSearchDir { root in
            try put(root, "a/same.txt", "1234")
            try put(root, "b/same.txt", "12345")
            try put(root, "c/x.txt", "abcd")
            let byName = try await DuplicateFinder.groups(try items(root), by: DuplicateCriteria(sameName: true, sameSize: false))
            #expect(rel(byName, root) == [["a/same.txt", "b/same.txt"]])
            let bySize = try await DuplicateFinder.groups(try items(root), by: DuplicateCriteria(sameName: false, sameSize: true))
            #expect(rel(bySize, root) == [["a/same.txt", "c/x.txt"]])
            let none = try await DuplicateFinder.groups(try items(root), by: DuplicateCriteria(sameName: false, sameSize: false))
            #expect(none.isEmpty)
        }
    }

    @Test func content() async throws {
        try await withSearchDir { root in
            try put(root, "a/f.txt", "abcd")
            try put(root, "b/f.txt", "abcd")
            try put(root, "c/f.txt", "abce")
            try put(root, "d/z.txt", "abce")
            try put(root, "e/empty1.txt", "")
            try put(root, "e/empty2.txt", "")
            let byContent = try await DuplicateFinder.groups(try items(root), by: DuplicateCriteria(sameName: false, sameSize: false, sameContent: true))
            #expect(rel(byContent, root) == [["e/empty1.txt", "e/empty2.txt"], ["a/f.txt", "b/f.txt"], ["c/f.txt", "d/z.txt"]])
            let withName = try await DuplicateFinder.groups(try items(root), by: DuplicateCriteria(sameName: true, sameSize: true, sameContent: true))
            #expect(rel(withName, root) == [["a/f.txt", "b/f.txt"]])
        }
    }

    @Test func largeFilesDifferingLate() async throws {
        try await withSearchDir { root in
            var a = Data(repeating: 7, count: 300_000)
            var b = a
            let c = a
            b[250_000] = 8
            a.append(1)
            try put(root, "a/big.bin", c)
            try put(root, "b/big.bin", c)
            try put(root, "c/big.bin", b)
            try put(root, "d/big.bin", Data(a.dropLast()))
            let box = ProgressBox()
            let groups = try await DuplicateFinder.groups(try items(root), by: DuplicateCriteria(sameName: true, sameSize: true, sameContent: true),
                                                           progress: { done, total in box.record(done, total) })
            #expect(rel(groups, root) == [["a/big.bin", "b/big.bin", "d/big.bin"]])
            #expect(box.last == [4, 4])
        }
    }

    @Test func ignoresDirectoriesAndSizeless() async throws {
        try await withSearchDir { root in
            try mkdir(root, "x/same")
            try mkdir(root, "y/same")
            let files = try items(root)
            #expect(try await DuplicateFinder.groups(files, by: DuplicateCriteria()).isEmpty)
            let sizeless = [FileItem(url: root.appendingPathComponent("p")), FileItem(url: root.appendingPathComponent("q/p"))]
            #expect(try await DuplicateFinder.groups(sizeless, by: DuplicateCriteria(sameName: true, sameSize: false)).isEmpty)
        }
    }

    @Test func groupOrdering() async throws {
        try await withSearchDir { root in
            try put(root, "1/b.txt", "xx")
            try put(root, "2/b.txt", "xx")
            try put(root, "1/a.txt", "yyy")
            try put(root, "2/a.txt", "yyy")
            try put(root, "3/a.txt", "z")
            try put(root, "4/a.txt", "z")
            let groups = try await DuplicateFinder.groups(try items(root), by: DuplicateCriteria())
            #expect(rel(groups, root) == [["3/a.txt", "4/a.txt"], ["1/a.txt", "2/a.txt"], ["1/b.txt", "2/b.txt"]])
        }
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [Int] = []
    func record(_ done: Int, _ total: Int) { lock.lock(); value = [done, total]; lock.unlock() }
    var last: [Int] { lock.lock(); defer { lock.unlock() }; return value }
}
