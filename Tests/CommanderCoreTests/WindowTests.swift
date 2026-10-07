import Testing
import Foundation
@testable import CommanderCore

// MARK: Helpers

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("iCommanderWindowTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func state(_ path: String) -> PanelState { PanelState(location: URL(fileURLWithPath: path)) }

private func tabs(_ names: String..., active: Int = 0) -> TabList {
    var list = TabList(state("/" + names[0]))
    for n in names.dropFirst() { list.open(state("/" + n)) }
    list.select(active)
    return list
}

private func titles(_ list: TabList) -> [String] { list.tabs.map(\.title) }

private func file(_ name: String, size: Int64? = 10, date: TimeInterval? = 1000, hidden: Bool = false,
                  symlink: Bool = false, package: Bool = false) -> FileItem {
    FileItem(url: URL(fileURLWithPath: "/x/\(name)"), isDirectory: package, isSymlink: symlink, isPackage: package,
             isHidden: hidden, size: size, modificationDate: date.map { Date(timeIntervalSince1970: $0) })
}

private func dir(_ name: String) -> FileItem {
    FileItem(url: URL(fileURLWithPath: "/x/\(name)", isDirectory: true), isDirectory: true)
}

// MARK: PanelState

@Suite struct PanelStateTests {
    @Test func titles() {
        #expect(state("/").title == "/")
        #expect(state("/Users/x/").title == "x")
        #expect(state("/Users/x").title == "x")
    }

    @Test func codableRoundTrip() throws {
        let s = PanelState(
            location: URL(fileURLWithPath: "/Users/x"), cursorName: "a.txt",
            sort: SortSpec(field: .size, ascending: false), showHidden: true, filterPattern: "*.txt",
            back: [.init(url: URL(fileURLWithPath: "/tmp"), cursorName: "q")],
            forward: [.init(url: URL(fileURLWithPath: "/var"))])
        let back = try JSONDecoder().decode(PanelState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func decodeMissingKeysUsesDefaults() throws {
        let s = try JSONDecoder().decode(PanelState.self, from: Data(#"{"location":"file:///tmp/"}"#.utf8))
        #expect(s == PanelState(location: URL(string: "file:///tmp/")!))
    }

    @Test func nearestExisting() {
        let existing: Set<String> = ["/", "/Users", "/Users/x"]
        let exists: (URL) -> Bool = { existing.contains($0.path) }
        #expect(PanelState.nearestExisting(URL(fileURLWithPath: "/Users/x"), exists: exists).path == "/Users/x")
        #expect(PanelState.nearestExisting(URL(fileURLWithPath: "/Users/x/gone/deeper"), exists: exists).path == "/Users/x")
        #expect(PanelState.nearestExisting(URL(fileURLWithPath: "/nope/a"), exists: exists).path == "/")
        #expect(PanelState.nearestExisting(URL(fileURLWithPath: "/nope/a"), exists: { _ in false }).path == "/")
    }
}

// MARK: PanelModel snapshot / restore

@MainActor
@Suite struct PanelModelStateTests {
    /// Temp tree: dirs a, b, c; files f1.txt, g.md; hidden `.h`.
    final class Fixture {
        let root: URL
        init() throws {
            root = try tempDir()
            for d in ["a", "b", "c"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
            }
            for f in ["f1.txt", "g.md", ".h"] { try Data(count: 1).write(to: root.appendingPathComponent(f)) }
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    @Test func snapshotRestoreRoundTrip() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        try await m.go(to: f.root.appendingPathComponent("a"))
        try await m.goParent()                         // back at root, cursor on "a"
        try await m.go(to: f.root.appendingPathComponent("b"))
        let snap = m.snapshot()
        #expect(snap.location == f.root.appendingPathComponent("b"))
        #expect(snap.cursorName == nil)                // cursor on ".."
        #expect(snap.back.count == 3)

        try await m.go(to: f.root.appendingPathComponent("c"))
        try await m.restore(snap)
        #expect(m.location == snap.location)
        #expect(m.canGoBack)
        #expect(!m.canGoForward)
        #expect(m.snapshot().back == snap.back)

        // restoring does not lengthen the history, and Back lands where it should
        try await m.goBack()
        #expect(m.location == f.root)
    }

    @Test func restoreFocusesCursorName() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        var s = PanelState(location: f.root, cursorName: "g.md")
        s.forward = [.init(url: f.root.appendingPathComponent("a"))]
        try await m.restore(s)
        #expect(m.cursorItem?.name == "g.md")
        #expect(m.canGoForward)
        #expect(m.snapshot().cursorName == "g.md")
    }

    @Test func restoreAppliesSortHiddenFilter() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.selectAll()
        let s = PanelState(location: f.root, sort: SortSpec(field: .name, ascending: false),
                           showHidden: true, filterPattern: "*.txt")
        try await m.restore(s)
        #expect(m.sort == s.sort)
        #expect(m.showHidden)
        #expect(m.filter?.pattern == "*.txt")
        #expect(m.selection.isEmpty)
        // directories (descending), hidden file shown but filtered out by *.txt, only f1.txt remains
        #expect(m.items.map(\.name) == ["..", "c", "b", "a", "f1.txt"])
        try await Task.sleep(for: .milliseconds(100))   // no stray refresh may disturb the result
        #expect(m.items.map(\.name) == ["..", "c", "b", "a", "f1.txt"])
        let snap = m.snapshot()
        #expect(snap.sort == s.sort && snap.showHidden && snap.filterPattern == "*.txt")
    }

    @Test func restoreClearsFilterWhenNil() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        m.filter = WildcardMask("*.txt")
        try await m.restore(PanelState(location: f.root))
        #expect(m.filter == nil)
        #expect(m.items.map(\.name) == ["..", "a", "b", "c", "f1.txt", "g.md"])
    }

    @Test func restoreToMissingDirectoryThrowsAndKeepsState() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        try await m.go(to: f.root.appendingPathComponent("a"))
        m.sort = SortSpec(field: .date, ascending: false)
        let before = m.snapshot()
        let bad = PanelState(location: f.root.appendingPathComponent("missing"), sort: .default, showHidden: true,
                             filterPattern: "*.x")
        await #expect(throws: (any Error).self) { try await m.restore(bad) }
        #expect(m.snapshot() == before)
        #expect(m.location == f.root.appendingPathComponent("a"))
    }

    @Test func setSelectionByNames() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.toggleSelection(at: 1)
        m.setSelection(names: ["F1.TXT", "g.md", "nope", ".."])
        #expect(m.selectedItems.map(\.name) == ["f1.txt", "g.md"])
        m.setSelection(names: [String]())
        #expect(m.selection.isEmpty)
    }
}

// MARK: TabList

@Suite struct TabListTests {
    @Test func openInsertsAfterActive() {
        var t = tabs("a", "b", "c", active: 0)       // opened in order, then select(0)
        #expect(titles(t) == ["a", "b", "c"])
        t.open(state("/n"))
        #expect(titles(t) == ["a", "n", "b", "c"])
        #expect(t.active == 1)
        #expect(t.current.title == "n")
    }

    @Test func closeLastIsRefused() {
        var t = TabList(state("/a"))
        let r1 = t.closeCurrent()
        #expect(!r1)
        let r2 = t.close(at: 0)
        #expect(!r2)
        #expect(t.tabs.count == 1)
    }

    @Test func closeMiddlePicksRight() {
        var t = tabs("a", "b", "c", active: 1)
        let r3 = t.closeCurrent()
        #expect(r3)
        #expect(titles(t) == ["a", "c"])
        #expect(t.current.title == "c")
    }

    @Test func closeRightmostPicksLeft() {
        var t = tabs("a", "b", "c", active: 2)
        let r4 = t.closeCurrent()
        #expect(r4)
        #expect(t.current.title == "b")
    }

    @Test func closeOtherTabKeepsActive() {
        var t = tabs("a", "b", "c", active: 2)
        let r5 = t.close(at: 0)
        #expect(r5)
        #expect(t.current.title == "c")
        let r6 = t.close(at: 9)
        #expect(!r6)
    }

    @Test func nextPreviousCycle() {
        var t = tabs("a", "b", "c", active: 2)
        t.next()
        #expect(t.active == 0)
        t.previous()
        #expect(t.active == 2)
    }

    @Test func selectIgnoresOutOfRange() {
        var t = tabs("a", "b", active: 1)
        t.select(5); t.select(-1)
        #expect(t.active == 1)
    }

    @Test func updateCurrent() {
        var t = tabs("a", "b", active: 1)
        var s = t.current
        s.cursorName = "z"
        t.updateCurrent(s)
        #expect(t.tabs[1].cursorName == "z")
        #expect(t.tabs[0].cursorName == nil)
    }

    @Test func moveKeepsActiveTab() {
        var t = tabs("a", "b", "c", "d", active: 0)
        t.move(from: 0, to: 2)                         // b c a d
        #expect(titles(t) == ["b", "c", "a", "d"])
        #expect(t.current.title == "a")
        t.select(3)                                    // d
        t.move(from: 0, to: 3)                         // c a d b
        #expect(titles(t) == ["c", "a", "d", "b"])
        #expect(t.current.title == "d")
        t.move(from: 3, to: 0)                         // b c a d
        #expect(t.current.title == "d")
        #expect(titles(t) == ["b", "c", "a", "d"])
    }

    @Test func codableRoundTripAndRepair() throws {
        let t = tabs("a", "b", active: 1)
        let back = try JSONDecoder().decode(TabList.self, from: JSONEncoder().encode(t))
        #expect(back == t)

        var json = String(decoding: try JSONEncoder().encode(t), as: UTF8.self)
        json = json.replacingOccurrences(of: #""active":1"#, with: #""active":7"#)
        let repaired = try JSONDecoder().decode(TabList.self, from: Data(json.utf8))
        #expect(repaired.active == 1)

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TabList.self, from: Data(#"{"tabs":[],"active":0}"#.utf8))
        }
    }
}

// MARK: RecentPaths

@Suite struct RecentPathsTests {
    @Test func newestFirstAndDedupe() {
        var r = RecentPaths()
        r.add("/a"); r.add("/b/"); r.add("/a/")
        #expect(r.paths == ["/a/", "/b/"])
        r.add("/b")
        #expect(r.paths == ["/b", "/a/"])
    }

    @Test func rootStaysRoot() {
        var r = RecentPaths()
        r.add("/"); r.add("/x"); r.add("/")
        #expect(r.paths == ["/", "/x"])
    }

    @Test func ignoresBlankAndTrims() {
        var r = RecentPaths()
        r.add("   "); r.add("")
        #expect(r.paths.isEmpty)
        r.add("  /a  ")
        #expect(r.paths == ["/a"])
    }

    @Test func limit() {
        var r = RecentPaths()
        for i in 0..<30 { r.add("/p\(i)") }
        #expect(r.paths.count == RecentPaths.limit)
        #expect(r.paths.first == "/p29")
        #expect(RecentPaths(paths: (0..<40).map { "/\($0)" }).paths.count == RecentPaths.limit)
    }

    @Test func scrubsPasswords() {
        var r = RecentPaths()
        r.add("smb://user:secret@host/share")
        #expect(r.paths == ["smb://user@host/share"])
        #expect(!r.paths[0].contains("secret"))
    }

    @Test func codable() throws {
        var r = RecentPaths()
        r.add("/a"); r.add("/b")
        #expect(try JSONDecoder().decode(RecentPaths.self, from: JSONEncoder().encode(r)) == r)
    }
}

// MARK: HotPaths

@Suite struct HotPathsTests {
    @Test func digitMapping() {
        #expect(HotPaths.slot(forDigit: 1) == 0)
        #expect(HotPaths.slot(forDigit: 9) == 8)
        #expect(HotPaths.slot(forDigit: 0) == 9)
        #expect(HotPaths.slot(forDigit: 10) == nil)
        #expect(HotPaths.slot(forDigit: -1) == nil)
        #expect(HotPaths.digit(forSlot: 0) == 1)
        #expect(HotPaths.digit(forSlot: 8) == 9)
        #expect(HotPaths.digit(forSlot: 9) == 0)
        #expect(HotPaths.digit(forSlot: 10) == nil)
    }

    @Test func nameFromPath() {
        #expect(HotPath(path: "/Users/x/Documents").name == "Documents")
        #expect(HotPath(path: "/Users/x/Documents/").name == "Documents")
        #expect(HotPath(path: "/").name == "/")
        #expect(HotPath(name: "", path: "/tmp").name == "tmp")
        #expect(HotPath(name: "Mine", path: "/tmp").name == "Mine")
    }

    @Test func addFillsTenPlusThenZeroToNine() {
        var h = HotPaths()
        let r7 = h.add(HotPath(path: "/p0"))
        #expect(r7 == 10)
        let r8 = h.add(HotPath(path: "/p1"))
        #expect(r8 == 11)
        for i in 2..<20 {
            let slot = h.add(HotPath(path: "/p\(i)"))
            #expect(slot == 10 + i)
        }
        let r9 = h.add(HotPath(path: "/p20"))
        #expect(r9 == 0)
        for i in 21..<30 {
            let slot = h.add(HotPath(path: "/p\(i)"))
            #expect(slot == i - 20)
        }
        let r10 = h.add(HotPath(path: "/overflow"))
        #expect(r10 == nil)
        #expect(h.defined.count == 30)
        #expect(h.defined.map(\.slot) == Array(0..<30))
    }

    @Test func addDuplicateReturnsExistingSlot() {
        var h = HotPaths()
        h.add(HotPath(path: "/a"))
        let r11 = h.add(HotPath(path: "/a/"))
        #expect(r11 == 10)
        #expect(h.defined.count == 1)
    }

    @Test func setSubscriptMove() {
        var h = HotPaths()
        h.set(2, HotPath(path: "/a"))
        h.set(99, HotPath(path: "/ignored"))
        #expect(h[2]?.path == "/a")
        #expect(h[99] == nil)
        h.move(from: 2, to: 12)
        #expect(h[2] == nil && h[12]?.path == "/a")
        h.move(from: 0, to: 99)
        #expect(h.defined.count == 1)
        h.set(12, nil)
        #expect(h.defined.isEmpty)
    }

    @Test func decodingFitsLength() throws {
        let short = HotPaths(slots: [HotPath(path: "/a"), nil, HotPath(path: "/c")])
        #expect(short.slots.count == 30)
        let json = #"{"slots":[{"name":"a","path":"/a"},null,{"name":"c","path":"/c"}]}"#
        let decoded = try JSONDecoder().decode(HotPaths.self, from: Data(json.utf8))
        #expect(decoded.slots.count == HotPaths.capacity)
        #expect(decoded[0]?.path == "/a" && decoded[1] == nil && decoded[2]?.path == "/c")
        let long = HotPaths(slots: [HotPath?](repeating: HotPath(path: "/x"), count: 50))
        #expect(long.slots.count == 30)
        #expect(try JSONDecoder().decode(HotPaths.self, from: Data("{}".utf8)).slots.count == 30)
    }

    @Test func codableRoundTrip() throws {
        var h = HotPaths()
        h.add(HotPath(path: "/a"))
        #expect(try JSONDecoder().decode(HotPaths.self, from: JSONEncoder().encode(h)) == h)
    }
}

// MARK: PanelComparison

@Suite struct PanelComparisonTests {
    let rules = NameRules(caseSensitive: false)

    func compare(_ l: [FileItem], _ r: [FileItem], _ o: ComparisonOptions = .init()) -> PanelComparisonResult {
        PanelComparison.compare(left: l, right: r, options: o, rules: rules)
    }

    @Test func identicalDirectories() {
        let items = [dir("d"), file("a"), file("b")]
        let r = compare(items, items)
        #expect(r.isIdentical)
    }

    @Test func fileOnlyOnLeft() {
        let r = compare([file("a"), file("b")], [file("b")])
        #expect(r.left == ["a"] && r.right.isEmpty)
    }

    @Test func newerOnRight() {
        let r = compare([file("a", date: 1000)], [file("a", date: 2000)])
        #expect(r.left.isEmpty && r.right == ["a"])
    }

    @Test func toleranceHidesSmallDifference() {
        #expect(compare([file("a", date: 1000)], [file("a", date: 1001)]).isIdentical)
        #expect(compare([file("a", date: 1000)], [file("a", date: 1002)]).isIdentical)
        #expect(!compare([file("a", date: 1000)], [file("a", date: 1003)]).isIdentical)
    }

    @Test func largerLeftNewerRightSelectsBoth() {
        let r = compare([file("a", size: 99, date: 1000)], [file("a", size: 5, date: 2000)])
        #expect(r.left == ["a"] && r.right == ["a"])
    }

    @Test func criteriaCanBeDisabled() {
        var o = ComparisonOptions()
        o.compareDate = false
        let r = compare([file("a", size: 99, date: 1000)], [file("a", size: 5, date: 2000)], o)
        #expect(r.left == ["a"] && r.right.isEmpty)
        o.compareSize = false
        #expect(compare([file("a", size: 99, date: 1000)], [file("a", size: 5, date: 2000)], o).isIdentical)
    }

    @Test func missingDateIsNotCompared() {
        #expect(compare([file("a", date: nil)], [file("a", date: 5000)]).isIdentical)
    }

    @Test func caseInsensitivePairing() {
        #expect(compare([file("README.md")], [file("readme.md")]).isIdentical)
        let sensitive = PanelComparison.compare(left: [file("README.md")], right: [file("readme.md")],
                                                rules: NameRules(caseSensitive: true))
        #expect(sensitive.left == ["README.md"] && sensitive.right == ["readme.md"])
    }

    @Test func ignoreMasks() {
        var o = ComparisonOptions()
        o.ignoreFiles = "*.tmp;.DS_Store"
        o.ignoreDirectories = "build"
        let r = compare([file("a.tmp"), file(".DS_Store"), dir("build"), file("keep")],
                        [dir("build"), file("x.TMP")], o)
        #expect(r.left == ["keep"] && r.right.isEmpty)
        // a directory named like a file mask is not ignored
        o.ignoreFiles = "build"; o.ignoreDirectories = nil
        #expect(compare([dir("build")], [], o).left == ["build"])
        // a blank pattern ignores nothing
        o.ignoreFiles = "  "
        #expect(compare([file("a")], [], o).left == ["a"])
    }

    @Test func packageCountsAsFile() {
        var o = ComparisonOptions()
        o.ignoreFiles = "*.app"
        #expect(compare([file("X.app", package: true)], [], o).isIdentical)
        #expect(compare([file("X.app", package: true)], []).left == ["X.app"])
        o.selectDirectoriesOnlyInOnePanel = false
        o.ignoreFiles = nil
        #expect(compare([file("X.app", package: true)], [], o).left == ["X.app"])
    }

    @Test func directoryOnlyOnOneSide() {
        var o = ComparisonOptions()
        #expect(compare([], [dir("d")], o).right == ["d"])
        o.selectDirectoriesOnlyInOnePanel = false
        #expect(compare([], [dir("d")], o).isIdentical)
        #expect(compare([dir("d")], [], o).isIdentical)
    }

    @Test func fileVersusDirectorySelectsBoth() {
        let r = compare([file("x")], [dir("x")])
        #expect(r.left == ["x"] && r.right == ["x"])
        var o = ComparisonOptions()
        o.selectDirectoriesOnlyInOnePanel = false
        #expect(compare([file("x")], [dir("x")], o).right == ["x"])
    }

    @Test func parentRowIgnoredAndOrderPreserved() {
        let parent = FileItem.parent(of: URL(fileURLWithPath: "/x/y"))
        let r = compare([parent, file("c"), file("a"), file("b")], [parent])
        #expect(r.left == ["c", "a", "b"])
    }
}

// MARK: Highlighting

@Suite struct HighlightingTests {
    let rules = NameRules(caseSensitive: false)

    @Test func tristate() {
        #expect(Tristate.any.accepts(true) && Tristate.any.accepts(false))
        #expect(Tristate.yes.accepts(true) && !Tristate.yes.accepts(false))
        #expect(!Tristate.no.accepts(true) && Tristate.no.accepts(false))
    }

    @Test func firstRuleWins() {
        let a = PanelAppearance(highlights: [
            HighlightRule(masks: "*.txt", color: .blue),
            HighlightRule(masks: "*", color: .orange),
        ])
        #expect(a.color(for: file("a.txt"), rules: rules) == .blue)
        #expect(a.color(for: file("a.md"), rules: rules) == .orange)
    }

    @Test func attributeConditions() {
        let hiddenFiles = HighlightRule(masks: "", hidden: .yes, color: .gray)
        #expect(hiddenFiles.matches(file(".x", hidden: true), rules: rules))
        #expect(!hiddenFiles.matches(file("x"), rules: rules))
        let dirs = HighlightRule(masks: "", directory: .yes, color: .blue)
        #expect(dirs.matches(dir("d"), rules: rules))
        #expect(!dirs.matches(file("X.app", package: true), rules: rules))
        let links = HighlightRule(masks: "*", symlink: .yes, color: .cyan)
        #expect(links.matches(file("l", symlink: true), rules: rules))
        #expect(!links.matches(file("l"), rules: rules))
    }

    @Test func parentRowNeverMatches() {
        let all = HighlightRule(masks: "", color: .red)
        #expect(!all.matches(.parent(of: URL(fileURLWithPath: "/x/y")), rules: rules))
        #expect(PanelAppearance(highlights: [all]).color(for: .parent(of: URL(fileURLWithPath: "/x/y")), rules: rules) == nil)
    }

    @Test func defaultsColorArchivesAndScripts() {
        let a = PanelAppearance()
        #expect(a.markColor == .red)
        #expect(a.color(for: file("Backup.ZIP"), rules: rules) == .purple)
        #expect(a.color(for: file("run.sh"), rules: rules) == .green)
        #expect(a.color(for: file("notes.txt"), rules: rules) == nil)
        #expect(a.color(for: dir("stuff.zip"), rules: rules) == nil)
        #expect(PanelAppearance.defaultHighlights.map(\.id) == PanelAppearance.defaultHighlights.map(\.id))
    }

    @Test func disabledRuleIsSkipped() {
        let a = PanelAppearance(highlights: [
            HighlightRule(masks: "*.txt", color: .blue, isEnabled: false),
            HighlightRule(masks: "*.txt", color: .pink),
        ])
        #expect(a.color(for: file("a.txt"), rules: rules) == .pink)
    }

    @Test func decodeWithoutKeys() throws {
        let a = try JSONDecoder().decode(PanelAppearance.self, from: Data("{}".utf8))
        #expect(a == PanelAppearance())
        let b = try JSONDecoder().decode(PanelAppearance.self, from: Data(#"{"markColor":"teal"}"#.utf8))
        #expect(b.markColor == .teal && b.highlights == PanelAppearance.defaultHighlights)
        let r = try JSONDecoder().decode(HighlightRule.self, from: Data(#"{"masks":"*.c","color":"mint"}"#.utf8))
        #expect(r.masks == "*.c" && r.color == .mint && r.isEnabled && r.directory == .any)
    }

    @Test func codableRoundTrip() throws {
        let a = PanelAppearance(markColor: .indigo, highlights: [
            HighlightRule(masks: "*.a", directory: .no, hidden: .yes, symlink: .no, color: .brown, isEnabled: false)])
        #expect(try JSONDecoder().decode(PanelAppearance.self, from: JSONEncoder().encode(a)) == a)
    }
}

// MARK: WindowLayout

@Suite struct WindowLayoutTests {
    @Test func roundTrip() {
        var l = WindowLayout(left: tabs("a", "b", active: 1), right: tabs("c"), leftMode: .brief,
                             rightMode: .detailed, activeSide: .right, maximized: .left, splitFraction: 0.3)
        l.right.updateCurrent(PanelState(location: URL(fileURLWithPath: "/c"), cursorName: "f",
                                         sort: SortSpec(field: .date, ascending: false)))
        let back = WindowLayout.decode(l.encoded())
        #expect(back == l)
    }

    @Test func missingKeysUseDefaults() throws {
        let one = String(decoding: try JSONEncoder().encode(tabs("a")), as: UTF8.self)
        let l = try #require(WindowLayout.decode(Data(#"{"left":\#(one)}"#.utf8)))
        #expect(l.left.current.title == "a")
        #expect(l.leftMode == .detailed && l.rightMode == .detailed)
        #expect(l.activeSide == .left && l.maximized == nil && l.splitFraction == 0.5)
        #expect(l.right.tabs.count == 1)
        #expect(WindowLayout.decode(Data("{}".utf8)) != nil)
        #expect(WindowLayout.decode(Data("garbage".utf8)) == nil)
    }

    @Test func splitFractionClamped() throws {
        let one = String(decoding: try JSONEncoder().encode(tabs("a")), as: UTF8.self)
        let hi = try #require(WindowLayout.decode(Data(#"{"left":\#(one),"right":\#(one),"splitFraction":2.0}"#.utf8)))
        #expect(hi.splitFraction == 0.9)
        let lo = try #require(WindowLayout.decode(Data(#"{"splitFraction":-1}"#.utf8)))
        #expect(lo.splitFraction == 0.1)
        var l = WindowLayout(left: tabs("a"), right: tabs("b"), splitFraction: 5)
        #expect(l.splitFraction == 0.9)
        l.splitFraction = 0
        #expect(l.splitFraction == 0.1)
    }
}
