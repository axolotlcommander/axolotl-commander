import Testing
import Foundation
@testable import CommanderCore

// MARK: - Case

@Suite struct NameCaseTests {
    @Test func czechDiacritics() {
        let name = "ŽLUŤOUČKÝ kůň.TXT"
        #expect(CaseChange.lower.apply(to: name, isDirectory: false) == "žluťoučký kůň.txt")
        #expect(CaseChange.upper.apply(to: name, isDirectory: false) == "ŽLUŤOUČKÝ KŮŇ.TXT")
        #expect(CaseChange.partiallyMixed.apply(to: name, isDirectory: false) == "Žluťoučký Kůň.txt")
        #expect(CaseChange.mixed.apply(to: name, isDirectory: false) == "Žluťoučký Kůň.Txt")
    }

    @Test func mixedWordBoundaries() {
        #expect(CaseStyle.mixed.apply(to: "my FILE-name_x") == "My File-Name_X")
        #expect(CaseStyle.mixed.apply(to: "a1b 2c") == "A1b 2c")
    }

    @Test func keepLeavesPartsAlone() {
        let change = CaseChange(name: .upper, ext: .keep)
        #expect(change.apply(to: "abc.TxT", isDirectory: false) == "ABC.TxT")
        #expect(CaseChange(name: .keep, ext: .upper).apply(to: "aBc.txt", isDirectory: false) == "aBc.TXT")
    }

    @Test func foldersHaveNoExtension() {
        let change = CaseChange(name: .upper, ext: .lower)
        #expect(change.apply(to: "v1.2 dir", isDirectory: true) == "V1.2 DIR")
        #expect(change.apply(to: "v1.2 dir", isDirectory: false) == "V1.2 dir")
    }

    @Test func leadingAndTrailingDots() {
        #expect(CaseChange.upper.apply(to: ".bashrc", isDirectory: false) == ".BASHRC")
        #expect(CaseChange(name: .upper, ext: .lower).apply(to: ".git.IGNORE", isDirectory: false) == ".GIT.ignore")
        #expect(CaseChange.upper.apply(to: "a.", isDirectory: false) == "A.")
        #expect(CaseChange.upper.apply(to: "noext", isDirectory: false) == "NOEXT")
        #expect(CaseChange.upper.apply(to: "a.tar.gz", isDirectory: false) == "A.TAR.GZ")
    }

    @Test func codable() throws {
        let data = try JSONEncoder().encode(CaseChange.partiallyMixed)
        #expect(try JSONDecoder().decode(CaseChange.self, from: data) == .partiallyMixed)
    }
}

// MARK: - Plan

@Suite struct RenamePlanTests {
    private let dir = URL(fileURLWithPath: "/virtual/dir", isDirectory: true)
    private let insensitive = NameRules(caseSensitive: false)
    private let sensitive = NameRules(caseSensitive: true)

    private func item(_ name: String, to new: String, in folder: URL? = nil, isDirectory: Bool = false) -> RenameItem {
        RenameItem(url: (folder ?? dir).appendingPathComponent(name), isDirectory: isDirectory, newName: new)
    }

    private func statuses(_ items: [RenameItem], rules: NameRules, listing: [String]) -> [RenameStatus] {
        RenamePlanner.plan(items, rules: { _ in rules }, listing: { _ in listing }).map(\.status)
    }

    @Test func unchangedWhenScalarIdentical() {
        #expect(statuses([item("a.txt", to: "a.txt")], rules: insensitive, listing: ["a.txt"]) == [.unchanged])
        // Same canonical form but different scalars is a real (respelling) rename.
        let nfd = "e\u{301}.txt"
        let nfc = "\u{e9}.txt"
        #expect(statuses([item(nfd, to: nfc)], rules: insensitive, listing: [nfd]) == [.rename])
    }

    @Test func respellingIsAllowed() {
        #expect(statuses([item("a.txt", to: "A.TXT")], rules: insensitive, listing: ["a.txt"]) == [.rename])
        #expect(statuses([item("a.txt", to: "A.TXT")], rules: sensitive, listing: ["a.txt"]) == [.rename])
    }

    @Test func existsOnVolume() {
        let listing = ["a.txt", "b.txt"]
        #expect(statuses([item("a.txt", to: "B.txt")], rules: insensitive, listing: listing)
            == [.skipped(.existsOnVolume("b.txt"))])
        #expect(statuses([item("a.txt", to: "B.txt")], rules: sensitive, listing: listing) == [.rename])
        #expect(statuses([item("a.txt", to: "b.txt")], rules: sensitive, listing: listing)
            == [.skipped(.existsOnVolume("b.txt"))])
    }

    @Test func duplicateInBatch() {
        let items = [item("a.txt", to: "x.txt"), item("b.txt", to: "X.txt")]
        #expect(statuses(items, rules: insensitive, listing: ["a.txt", "b.txt"])
            == [.skipped(.duplicateInBatch("x.txt")), .skipped(.duplicateInBatch("X.txt"))])
        #expect(statuses(items, rules: sensitive, listing: ["a.txt", "b.txt"]) == [.rename, .rename])
    }

    @Test func sameNameInDifferentFoldersIsFine() {
        let other = URL(fileURLWithPath: "/virtual/other", isDirectory: true)
        let items = [item("a.txt", to: "x.txt"), item("b.txt", to: "x.txt", in: other)]
        #expect(statuses(items, rules: insensitive, listing: []) == [.rename, .rename])
    }

    @Test func swapAndChainAreAllowed() {
        let swap = [item("a", to: "b"), item("b", to: "a")]
        #expect(statuses(swap, rules: insensitive, listing: ["a", "b"]) == [.rename, .rename])
        let chain = [item("a", to: "b"), item("b", to: "c")]
        #expect(statuses(chain, rules: insensitive, listing: ["a", "b"]) == [.rename, .rename])
    }

    @Test func chainEndingOnExistingFileIsBlockedThroughout() {
        let chain = [item("a", to: "b"), item("b", to: "c")]
        #expect(statuses(chain, rules: insensitive, listing: ["a", "b", "c"])
            == [.skipped(.existsOnVolume("b")), .skipped(.existsOnVolume("c"))])
    }

    @Test func renamingOntoAnUnchangedBatchItemIsBlocked() {
        let items = [item("a", to: "b"), item("b", to: "b")]
        #expect(statuses(items, rules: insensitive, listing: []) == [.skipped(.existsOnVolume("b")), .unchanged])
    }

    @Test func invalidNames() {
        let long = String(repeating: "x", count: 256)
        let ok = String(repeating: "x", count: 255)
        let items = ["", ".", "..", "a/b", "a\u{0}b", long, ok].map { item("a", to: $0) }
        #expect(statuses(items, rules: sensitive, listing: ["a"]) == [
            .skipped(.invalidName), .skipped(.invalidName), .skipped(.invalidName), .skipped(.invalidName),
            .skipped(.invalidName), .skipped(.invalidName), .rename,
        ])
        // 128 two-byte characters are 256 bytes.
        let wide = String(repeating: "é", count: 128)
        #expect(statuses([item("a", to: wide)], rules: sensitive, listing: ["a"]) == [.skipped(.invalidName)])
    }

    @Test func wildcardIntroduced() {
        let listing = ["ab.txt", "a?.txt", "a*.txt"]
        #expect(statuses([item("ab.txt", to: "a?.TXT")], rules: sensitive, listing: listing)
            == [.skipped(.wildcardIntroduced)])
        #expect(statuses([item("ab.txt", to: "a*")], rules: sensitive, listing: listing)
            == [.skipped(.wildcardIntroduced)])
        // A name that already has the character may keep it.
        #expect(statuses([item("a?.txt", to: "A?.txt")], rules: sensitive, listing: listing) == [.rename])
        #expect(statuses([item("a?.txt", to: "a*.txt")], rules: sensitive, listing: listing)
            == [.skipped(.wildcardIntroduced)])
    }
}

// MARK: - Execution (temp dir only)

@Suite struct RenameExecutionTests {
    private func makeDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("icmd-rn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, _ url: URL) throws {
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    private func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func names(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    private func entries(_ items: [RenameItem]) -> [RenamePlanEntry] {
        RenamePlanner.plan(items)
    }

    @Test func caseChangeOnRealVolume() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("abc.txt")
        try write("x", file)
        let plan = entries([RenameItem(url: file, isDirectory: false, newName: "ABC.TXT")])
        #expect(plan.map(\.status) == [.rename])
        let outcome = try await RenameExecutor.run(plan)
        #expect(outcome.failures.isEmpty)
        #expect(outcome.renamed.count == 1)
        #expect(names(dir) == ["ABC.TXT"])
        #expect(read(dir.appendingPathComponent("ABC.TXT")) == "x")
    }

    @Test func existingFileOnRealVolumeIsSkippedAndNeverOverwritten() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("A", dir.appendingPathComponent("a.txt"))
        try write("B", dir.appendingPathComponent("b.txt"))
        let plan = entries([RenameItem(url: dir.appendingPathComponent("a.txt"), isDirectory: false, newName: "B.txt")])
        let rules = NameRules.forVolume(containing: dir)
        if rules.caseSensitive {
            #expect(plan.map(\.status) == [.rename])
        } else {
            #expect(plan.map(\.status) == [.skipped(.existsOnVolume("b.txt"))])
        }
        let outcome = try await RenameExecutor.run(plan)
        #expect(read(dir.appendingPathComponent("b.txt")) == "B")
        _ = outcome
    }

    @Test func swapOnDisk() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        try write("A", a)
        try write("B", b)
        let plan = entries([
            RenameItem(url: a, isDirectory: false, newName: "b.txt"),
            RenameItem(url: b, isDirectory: false, newName: "a.txt"),
        ])
        #expect(plan.map(\.status) == [.rename, .rename])
        let outcome = try await RenameExecutor.run(plan)
        #expect(outcome.failures.isEmpty)
        #expect(outcome.renamed.count == 2)
        #expect(names(dir) == ["a.txt", "b.txt"])
        #expect(read(a) == "B")
        #expect(read(b) == "A")
    }

    @Test func chainOnDisk() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a")
        let b = dir.appendingPathComponent("b")
        try write("A", a)
        try write("B", b)
        // Listed in the "wrong" order on purpose.
        let plan = entries([
            RenameItem(url: a, isDirectory: false, newName: "b"),
            RenameItem(url: b, isDirectory: false, newName: "c"),
        ])
        #expect(plan.map(\.status) == [.rename, .rename])
        let outcome = try await RenameExecutor.run(plan)
        #expect(outcome.failures.isEmpty)
        #expect(names(dir) == ["b", "c"])
        #expect(read(dir.appendingPathComponent("b")) == "A")
        #expect(read(dir.appendingPathComponent("c")) == "B")
    }

    @Test func expandRecursiveAndChildrenRenamedBeforeParent() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("folder", isDirectory: true)
        let inner = sub.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try write("1", sub.appendingPathComponent("one.txt"))
        try write("2", inner.appendingPathComponent("two.txt"))
        // A symlink to a folder must not be descended into.
        let outside = dir.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try write("3", outside.appendingPathComponent("three.txt"))
        try FileManager.default.createSymbolicLink(at: sub.appendingPathComponent("link"), withDestinationURL: outside)

        let flat = RenameExecutor.expand([sub], recursive: false)
        #expect(flat.count == 1)
        let expanded = RenameExecutor.expand([sub], recursive: true)
        #expect(expanded.map(\.url.lastPathComponent) == ["folder", "inner", "two.txt", "link", "one.txt"])
        #expect(expanded.map(\.isDirectory) == [true, true, false, false, false])

        let change = CaseChange.upper
        let items = expanded.map {
            RenameItem(url: $0.url, isDirectory: $0.isDirectory,
                       newName: change.apply(to: $0.url.lastPathComponent, isDirectory: $0.isDirectory))
        }
        let outcome = try await RenameExecutor.run(entries(items))
        #expect(outcome.failures.isEmpty)
        #expect(outcome.renamed.count == 5)
        #expect(outcome.renamed.last?.from == sub)
        #expect(outcome.renamed.first?.from.lastPathComponent == "two.txt")
        #expect(names(dir) == ["FOLDER", "outside"])
        let top = dir.appendingPathComponent("FOLDER")
        #expect(names(top) == ["INNER", "LINK", "ONE.TXT"])
        #expect(names(top.appendingPathComponent("INNER")) == ["TWO.TXT"])
        #expect(names(outside) == ["three.txt"])
    }

    @Test func targetCreatedAfterPlanningIsAFailureAndNothingIsLost() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a")
        try write("A", a)
        let plan = entries([RenameItem(url: a, isDirectory: false, newName: "b")])
        #expect(plan.map(\.status) == [.rename])
        try write("B", dir.appendingPathComponent("b"))
        let outcome = try await RenameExecutor.run(plan)
        #expect(outcome.renamed.isEmpty)
        #expect(outcome.failures.map(\.url) == [a])
        #expect(read(a) == "A")
        #expect(read(dir.appendingPathComponent("b")) == "B")
    }

    @Test func failedFinalRenameRestoresTemporaryNames() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a")
        let b = dir.appendingPathComponent("b")
        try write("A", a)
        try write("B", b)
        // b -> c is processed first and fails because c appears after planning; a -> b then fails too.
        let plan = entries([
            RenameItem(url: b, isDirectory: false, newName: "c"),
            RenameItem(url: a, isDirectory: false, newName: "b"),
        ])
        #expect(plan.map(\.status) == [.rename, .rename])
        try write("C", dir.appendingPathComponent("c"))
        let outcome = try await RenameExecutor.run(plan)
        #expect(outcome.renamed.isEmpty)
        #expect(Set(outcome.failures.map(\.url)) == [a, b])
        #expect(names(dir) == ["a", "b", "c"])
        #expect(read(a) == "A")
        #expect(read(b) == "B")
        #expect(read(dir.appendingPathComponent("c")) == "C")
    }

    @Test func cancellationLeavesEverythingUntouched() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a")
        let b = dir.appendingPathComponent("b")
        try write("A", a)
        try write("B", b)
        let plan = entries([
            RenameItem(url: a, isDirectory: false, newName: "b"),
            RenameItem(url: b, isDirectory: false, newName: "a"),
        ])
        let task = Task { () -> RenameOutcome in
            while !Task.isCancelled { await Task.yield() }
            return try await RenameExecutor.run(plan)
        }
        task.cancel()
        let outcome = try await task.value
        #expect(outcome.cancelled)
        #expect(outcome.renamed.isEmpty)
        #expect(names(dir) == ["a", "b"])
        #expect(read(a) == "A")
    }

    @Test func progressIsReported() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a")
        try write("A", a)
        let plan = entries([RenameItem(url: a, isDirectory: false, newName: "z")])
        let log = ProgressLog()
        _ = try await RenameExecutor.run(plan) { done, total in log.add(done, total) }
        #expect(log.values == [[1, 1]])
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[Int]] = []
    var values: [[Int]] { lock.withLock { storage } }
    func add(_ done: Int, _ total: Int) { lock.withLock { storage.append([done, total]) } }
}

// MARK: - Batch rename

@Suite struct BatchRenameTests {
    private func source(_ path: String, dir: Bool = false, modified: Date? = nil) -> RenameSource {
        RenameSource(url: URL(fileURLWithPath: path, isDirectory: dir), isDirectory: dir, modified: modified, size: nil)
    }

    private func name(_ path: String, mask: String, index: Int = 0, dir: Bool = false,
                      configure: (inout BatchRenameOptions) -> Void = { _ in }) throws -> String {
        var options = BatchRenameOptions()
        options.mask = mask
        configure(&options)
        return try BatchRename.newName(for: source(path, dir: dir), index: index, options: options)
    }

    @Test func masksFollowNameMask() throws {
        #expect(try name("/x/report.txt", mask: "*.*") == "report.txt")
        #expect(try name("/x/report.txt", mask: "") == "report.txt")
        #expect(try name("/x/report.txt", mask: "*.bak") == "report.bak")
        #expect(try name("/x/report.txt", mask: "new_*.*") == "new_report.txt")
        #expect(try name("/x/report.txt", mask: "??_*.*") == "re_port.txt")
        #expect(try name("/x/report.txt", mask: "*") == "report.txt")
        #expect(try name("/x/report.txt", mask: "x.") == "x")
        for mask in ["*.bak", "new_*.*", "??_*.*", "a*.?", "*_x"] {
            for file in ["report.txt", "a.tar.gz", ".hidden", "noext"] {
                #expect(try name("/x/\(file)", mask: mask) == NameMask.apply(mask, to: file))
            }
        }
    }

    @Test func foldersHaveNoExtension() throws {
        #expect(try name("/x/v1.2", mask: "*_x", dir: true) == "v1.2_x")
        #expect(try name("/x/v1.2", mask: "*.bak", dir: true) == "v1.2.bak")
        #expect(try name("/x/v1.2", mask: "[N]|[E]", dir: true) == "v1.2|")
    }

    @Test func variables() throws {
        #expect(try name("/x/report.txt", mask: "[N]_[C:1:1:3].[E]", index: 4) == "report_005.txt")
        #expect(try name("/x/report.txt", mask: "[F]-[P]") == "report.txt-x")
        #expect(try name("/x/report.txt", mask: "[[N]") == "[N]")
        #expect(try name("/x/report.txt", mask: "[N] ([E])") == "report (txt)")
        #expect(try name("/x/report.txt", mask: "a]b.[E]") == "a]b.txt")
    }

    @Test func counterOptions() throws {
        #expect(try name("/x/a.txt", mask: "[C].[E]", index: 2) == "3.txt")
        #expect(try name("/x/a.txt", mask: "[C]", index: 2) { $0.counterStart = 10; $0.counterStep = 5; $0.counterWidth = 4 } == "0020")
        #expect(try name("/x/a.txt", mask: "[C:100]", index: 1) == "101")
        #expect(try name("/x/a.txt", mask: "[C:100:-10]", index: 2) == "80")
        #expect(try name("/x/a.txt", mask: "[C:-2:1:3]", index: 0) == "-002")
        #expect(try name("/x/a.txt", mask: "[C::2:2]", index: 3) == "07")
    }

    @Test func dateVariables() throws {
        var parts = DateComponents()
        parts.year = 2024; parts.month = 3; parts.day = 7; parts.hour = 13; parts.minute = 45; parts.second = 2
        let date = try #require(Calendar(identifier: .gregorian).date(from: parts))
        var options = BatchRenameOptions()
        options.mask = "[D]_[T]_[Y]-[M]-[d]"
        let s = source("/x/a.txt", modified: date)
        #expect(try BatchRename.newName(for: s, index: 0, options: options) == "2024-03-07_134502_2024-03-07")
        #expect(try BatchRename.newName(for: source("/x/a.txt"), index: 0, options: options) == "__--")
    }

    @Test func variableValuesAreInsertedLiterally() throws {
        // Parent folder "a.b*": its dot must not move the name/extension split and `*` stays a literal character.
        #expect(try name("/x/a.b*/file.txt", mask: "[P]-*.*") == "a.b*-file.txt")
        #expect(try name("/x/a.b*/file.txt", mask: "[P].[E]") == "a.b*.txt")
        #expect(try name("/x/q?/f.txt", mask: "[P]*") == "q?f.txt")
        // ... and the planner refuses such names, so no wildcard can reach the file system.
        var options = BatchRenameOptions()
        options.mask = "[P]-*.*"
        let plan = try BatchRename.preview(
            [source("/x/a.b*/file.txt")], options: options, rules: { _ in NameRules(caseSensitive: false) }, listing: { _ in ["file.txt"] })
        #expect(plan.map(\.status) == [.skipped(.wildcardIntroduced)])
        #expect(plan.first?.item.newName == "a.b*-file.txt")
    }

    @Test func searchReplacePlain() throws {
        #expect(try name("/x/aaa.aaa", mask: "*.*") { $0.search = "a"; $0.replace = "b" } == "bbb.aaa")
        #expect(try name("/x/aaa.aaa", mask: "*.*") { $0.search = "a"; $0.replace = "b"; $0.excludeExtension = false } == "bbb.bbb")
        #expect(try name("/x/aaa.aaa", mask: "*.*") { $0.search = "a"; $0.replace = "b"; $0.excludeExtension = false; $0.onlyFirst = true } == "baa.aaa")
        #expect(try name("/x/AAA.txt", mask: "*.*") { $0.search = "a"; $0.replace = "b" } == "bbb.txt")
        #expect(try name("/x/AAA.txt", mask: "*.*") { $0.search = "a"; $0.replace = "b"; $0.caseSensitive = true } == "AAA.txt")
        // Plain mode: no regex and no template interpretation.
        #expect(try name("/x/axb.txt", mask: "*.*") { $0.search = "a.b"; $0.replace = "-" } == "axb.txt")
        #expect(try name("/x/a.b.txt", mask: "*.*") { $0.search = "a.b"; $0.replace = "$1" } == "$1.txt")
    }

    @Test func searchReplaceRegex() throws {
        #expect(try name("/x/2024-report.txt", mask: "*.*") {
            $0.useRegex = true; $0.search = "(\\d+)-(\\w+)"; $0.replace = "$2_$1"
        } == "report_2024.txt")
        #expect(try name("/x/a1b22.txt", mask: "*.*") {
            $0.useRegex = true; $0.search = "\\d+"; $0.replace = "#"; $0.onlyFirst = true
        } == "a#b22.txt")
        #expect(try name("/x/a1b22.txt", mask: "*.*") {
            $0.useRegex = true; $0.search = "\\d+"; $0.replace = "#"
        } == "a#b#.txt")
        #expect(try name("/x/photo.JPG", mask: "*.*") {
            $0.useRegex = true; $0.search = "^photo"; $0.replace = "img"; $0.excludeExtension = true
        } == "img.JPG")
    }

    @Test func searchAppliesAfterMaskAndCaseAfterSearch() throws {
        #expect(try name("/x/report.txt", mask: "new_*.*") {
            $0.search = "new"; $0.replace = "old"; $0.caseChange = .upper
        } == "OLD_REPORT.TXT")
        #expect(try name("/x/my file.txt", mask: "[N].[E]") { $0.caseChange = .partiallyMixed } == "My File.txt")
    }

    @Test func errors() {
        #expect(throws: BatchRenameError.unknownVariable("Z")) { try name("/x/a.txt", mask: "[Z]") }
        #expect(throws: BatchRenameError.unknownVariable("N:1")) { try name("/x/a.txt", mask: "[N:1]") }
        #expect(throws: BatchRenameError.unknownVariable("C:x")) { try name("/x/a.txt", mask: "[C:x]") }
        #expect(throws: BatchRenameError.unterminatedVariable) { try name("/x/a.txt", mask: "[N") }
        #expect(throws: BatchRenameError.self) {
            try name("/x/a.txt", mask: "*.*") { $0.useRegex = true; $0.search = "(" }
        }
        // Mask errors surface even when there is nothing to rename.
        var options = BatchRenameOptions()
        options.mask = "[Q]"
        #expect(throws: BatchRenameError.unknownVariable("Q")) { try BatchRename.preview([], options: options) }
    }

    @Test func previewWithCounterAndPlanning() throws {
        var options = BatchRenameOptions()
        options.mask = "f[C:1:1:2].*"
        let sources = ["a.txt", "b.txt", "c.txt"].map { source("/x/\($0)") }
        let plan = try BatchRename.preview(
            sources, options: options, rules: { _ in NameRules(caseSensitive: false) }, listing: { _ in ["a.txt", "b.txt", "c.txt"] })
        #expect(plan.map(\.item.newName) == ["f01.txt", "f02.txt", "f03.txt"])
        #expect(plan.map(\.status) == [.rename, .rename, .rename])
    }

    @Test func previewDetectsCollisionsAndWildcards() throws {
        var options = BatchRenameOptions()
        options.mask = "same.*"
        let sources = ["a.txt", "b.txt"].map { source("/x/\($0)") }
        let plan = try BatchRename.preview(
            sources, options: options, rules: { _ in NameRules(caseSensitive: false) }, listing: { _ in ["a.txt", "b.txt"] })
        #expect(plan.map(\.status) == [.skipped(.duplicateInBatch("same.txt")), .skipped(.duplicateInBatch("same.txt"))])

        var replace = BatchRenameOptions()
        replace.search = "x"
        replace.replace = "?"
        let wild = try BatchRename.preview(
            [source("/x/axb.txt"), source("/x/q?x.txt")], options: replace,
            rules: { _ in NameRules(caseSensitive: true) }, listing: { _ in [] })
        // "axb" becomes "a?b" (skipped); "q?x" already had a "?" so it may keep it ("q??").
        #expect(wild.map(\.status) == [.skipped(.wildcardIntroduced), .rename])
        #expect(wild.map(\.item.newName) == ["a?b.txt", "q??.txt"])
    }

    @Test func optionsAreCodable() throws {
        var options = BatchRenameOptions()
        options.mask = "[N]_[C]"
        options.useRegex = true
        options.caseChange = .mixed
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(BatchRenameOptions.self, from: data) == options)
    }

    @Test func endToEndOnDisk() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("icmd-rn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for n in ["b.txt", "a.txt"] { try "x".write(to: dir.appendingPathComponent(n), atomically: false, encoding: .utf8) }
        var options = BatchRenameOptions()
        options.mask = "[N]_[C:1:1:2].[E]"
        let sources = ["a.txt", "b.txt"].map { RenameSource(url: dir.appendingPathComponent($0), isDirectory: false) }
        let plan = try BatchRename.preview(sources, options: options)
        let outcome = try await RenameExecutor.run(plan)
        #expect(outcome.failures.isEmpty)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        #expect(names == ["a_01.txt", "b_02.txt"])
    }
}

// MARK: - Batch rename in subfolders (temp dir only)

@Suite struct BatchRenameSubfolderTests {
    private func makeDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("icmd-rn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func names(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    @Test func oldSavedOptionsStillDecode() throws {
        // Saved before the subfolder options existed.
        let old = #"{"mask":"[N]_[C]","counterStart":5,"counterStep":1,"counterWidth":2,"search":"a","replace":"b","#
            + #""useRegex":true,"caseSensitive":false,"onlyFirst":false,"excludeExtension":true,"#
            + #""caseChange":{"name":"keep","ext":"keep"}}"#
        let options = try JSONDecoder().decode(BatchRenameOptions.self, from: Data(old.utf8))
        #expect(options.mask == "[N]_[C]")
        #expect(options.counterStart == 5)
        #expect(options.counterWidth == 2)
        #expect(options.useRegex)
        #expect(!options.includeSubfolders)
        #expect(options.subfolderItems == .filesAndFolders)
        // Missing or unknown values fall back to the defaults.
        let partial = try JSONDecoder().decode(BatchRenameOptions.self,
                                               from: Data(#"{"mask":"x","subfolderItems":"bogus"}"#.utf8))
        #expect(partial.mask == "x")
        #expect(partial.counterStep == 1)
        #expect(partial.subfolderItems == .filesAndFolders)

        var current = BatchRenameOptions()
        current.includeSubfolders = true
        current.subfolderItems = .folders
        let data = try JSONEncoder().encode(current)
        #expect(try JSONDecoder().decode(BatchRenameOptions.self, from: data) == current)
    }

    @Test func expandFiltersKindsAndKeepsParentsFirst() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let top = dir.appendingPathComponent("top", isDirectory: true)
        let sub = top.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for url in [top.appendingPathComponent("f10.txt"), top.appendingPathComponent("f2.txt"),
                    top.appendingPathComponent(".hidden"), sub.appendingPathComponent("inner.txt")] {
            try "x".write(to: url, atomically: false, encoding: .utf8)
        }
        let outside = dir.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "y".write(to: outside.appendingPathComponent("o.txt"), atomically: false, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: top.appendingPathComponent("link"), withDestinationURL: outside)
        let loose = dir.appendingPathComponent("loose.txt")
        try "z".write(to: loose, atomically: false, encoding: .utf8)
        let selected = [RenameSource(url: top, isDirectory: true), RenameSource(url: loose, isDirectory: false)]

        func expanded(_ kinds: SubfolderItems, hidden: Bool = false) -> [String] {
            BatchRename.expand(selected, kinds: kinds, includeHidden: hidden).sources.map(\.url.lastPathComponent)
        }
        // Finder order (f2 before f10), parents before children, symlinks not followed.
        #expect(expanded(.filesAndFolders) == ["top", "f2.txt", "f10.txt", "link", "sub", "inner.txt", "loose.txt"])
        #expect(expanded(.files) == ["top", "f2.txt", "f10.txt", "link", "inner.txt", "loose.txt"])
        #expect(expanded(.folders) == ["top", "sub", "loose.txt"])
        #expect(expanded(.files, hidden: true).contains(".hidden"))

        let result = BatchRename.expand(selected, kinds: .filesAndFolders, includeHidden: false)
        let f2 = try #require(result.sources.first { $0.url.lastPathComponent == "f2.txt" })
        #expect(f2.size == 1)
        #expect(f2.modified != nil)
        #expect(result.sources.first { $0.url.lastPathComponent == "sub" }?.isDirectory == true)
        #expect(result.sources.first { $0.url.lastPathComponent == "link" }?.isDirectory == false)
        #expect(result.listings[top.path]?.sorted() == [".hidden", "f10.txt", "f2.txt", "link", "sub"])
        #expect(result.listings[sub.path] == ["inner.txt"])
        #expect(result.listings[outside.path] == nil)
    }

    @Test func folderAndItsChildrenRenamedTogether() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let photos = dir.appendingPathComponent("photos", isDirectory: true)
        let trip = photos.appendingPathComponent("trip", isDirectory: true)
        try FileManager.default.createDirectory(at: trip, withIntermediateDirectories: true)
        try "a".write(to: photos.appendingPathComponent("a.jpg"), atomically: false, encoding: .utf8)
        try "b".write(to: trip.appendingPathComponent("b.jpg"), atomically: false, encoding: .utf8)

        let expansion = BatchRename.expand([RenameSource(url: photos, isDirectory: true)],
                                           kinds: .filesAndFolders, includeHidden: false)
        var options = BatchRenameOptions()
        options.mask = "[N]_[C].*"
        let plan = try BatchRename.preview(expansion.sources, options: options, listing: {
            try expansion.listings[$0.path] ?? RenamePlanner.defaultListing($0)
        })
        // The counter follows the expanded order.
        #expect(plan.map(\.item.newName) == ["photos_1", "a_2.jpg", "trip_3", "b_4.jpg"])
        #expect(plan.allSatisfy { $0.status == .rename })
        let outcome = try await RenameExecutor.run(plan)
        #expect(outcome.failures.isEmpty)
        #expect(outcome.renamed.count == 4)
        #expect(names(dir) == ["photos_1"])
        let top = dir.appendingPathComponent("photos_1")
        #expect(names(top) == ["a_2.jpg", "trip_3"])
        #expect(names(top.appendingPathComponent("trip_3")) == ["b_4.jpg"])
    }
}

// MARK: - Undo (temp dir only)

@Suite struct RenameUndoTests {
    private func makeDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("icmd-rn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, _ url: URL) throws {
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    private func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func names(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    private func rename(_ items: [RenameItem]) async throws -> RenameOutcome {
        let outcome = try await RenameExecutor.run(RenamePlanner.plan(items))
        #expect(outcome.failures.isEmpty)
        return outcome
    }

    @Test func simpleUndo() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt")
        try write("A", a)
        let done = try await rename([RenameItem(url: a, isDirectory: false, newName: "b.txt")])
        #expect(names(dir) == ["b.txt"])
        let undone = try await RenameExecutor.undo(done.renamed)
        #expect(undone.failures.isEmpty)
        #expect(undone.renamed.count == 1)
        #expect(names(dir) == ["a.txt"])
        #expect(read(a) == "A")
    }

    @Test func folderAndChildUndo() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("folder", isDirectory: true)
        let inner = folder.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try write("1", inner.appendingPathComponent("one.txt"))
        let items = RenameExecutor.expand([folder], recursive: true).map {
            RenameItem(url: $0.url, isDirectory: $0.isDirectory, newName: "x-" + $0.url.lastPathComponent)
        }
        let done = try await rename(items)
        #expect(done.renamed.count == 3)
        #expect(names(dir) == ["x-folder"])
        #expect(names(dir.appendingPathComponent("x-folder/x-inner")) == ["x-one.txt"])

        let plan = RenameExecutor.undoPlan(done.renamed)
        #expect(plan.allSatisfy { $0.status == .rename })
        let undone = try await RenameExecutor.undo(done.renamed)
        #expect(undone.failures.isEmpty)
        #expect(undone.renamed.count == 3)
        #expect(names(dir) == ["folder"])
        #expect(names(folder) == ["inner"])
        #expect(read(inner.appendingPathComponent("one.txt")) == "1")
    }

    @Test func swapAndChainUndo() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        let c = dir.appendingPathComponent("c.txt")
        try write("A", a)
        try write("B", b)
        try write("C", c)
        // A swap (a ↔ b) plus a chain (c → d → e: d.txt is taken by c's new name only).
        let done = try await rename([
            RenameItem(url: a, isDirectory: false, newName: "b.txt"),
            RenameItem(url: b, isDirectory: false, newName: "a.txt"),
            RenameItem(url: c, isDirectory: false, newName: "d.txt"),
        ])
        #expect(read(a) == "B")
        let undone = try await RenameExecutor.undo(done.renamed)
        #expect(undone.failures.isEmpty)
        #expect(names(dir) == ["a.txt", "b.txt", "c.txt"])
        #expect(read(a) == "A")
        #expect(read(b) == "B")
        #expect(read(c) == "C")
    }

    @Test func blockedUndoNeverOverwrites() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt")
        let x = dir.appendingPathComponent("x.txt")
        try write("A", a)
        try write("X", x)
        let done = try await rename([
            RenameItem(url: a, isDirectory: false, newName: "b.txt"),
            RenameItem(url: x, isDirectory: false, newName: "y.txt"),
        ])
        // Something new now holds the original name of a.txt.
        try write("NEW", a)
        let plan = RenameExecutor.undoPlan(done.renamed)
        let blocked = try #require(plan.first { $0.item.url.lastPathComponent == "b.txt" })
        #expect(blocked.status == .skipped(.existsOnVolume("a.txt")))
        let undone = try await RenameExecutor.undo(done.renamed)
        #expect(undone.renamed.map(\.to.lastPathComponent) == ["x.txt"])
        #expect(undone.failures.count == 1)
        #expect(undone.failures.first?.url.lastPathComponent == "b.txt")
        #expect(read(a) == "NEW")
        #expect(read(dir.appendingPathComponent("b.txt")) == "A")
        #expect(read(x) == "X")
    }

    @Test func undoOfUndoIsRedo() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write("1", folder.appendingPathComponent("one.txt"))
        try write("2", folder.appendingPathComponent("two.txt"))
        let items = RenameExecutor.expand([folder], recursive: true).map {
            RenameItem(url: $0.url, isDirectory: $0.isDirectory, newName: "new-" + $0.url.lastPathComponent)
        }
        let done = try await rename(items)
        let after = names(dir.appendingPathComponent("new-folder"))
        #expect(after == ["new-one.txt", "new-two.txt"])
        let undone = try await RenameExecutor.undo(done.renamed)
        #expect(undone.failures.isEmpty)
        #expect(names(dir) == ["folder"])
        let redone = try await RenameExecutor.undo(undone.renamed)
        #expect(redone.failures.isEmpty)
        #expect(redone.renamed.count == 3)
        #expect(names(dir) == ["new-folder"])
        #expect(names(dir.appendingPathComponent("new-folder")) == after)
        let again = try await RenameExecutor.undo(redone.renamed)
        #expect(again.failures.isEmpty)
        #expect(names(folder) == ["one.txt", "two.txt"])
    }
}
