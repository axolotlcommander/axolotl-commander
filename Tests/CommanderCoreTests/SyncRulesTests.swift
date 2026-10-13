// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

private let t0 = Date(timeIntervalSince1970: 1_500_000_000)

private func file(_ size: Int64 = 10, files: Int = 1) -> SyncSide {
    SyncSide(kind: .file, size: size, fileCount: files, modified: t0)
}

private func folder(_ size: Int64 = 0, files: Int = 0) -> SyncSide {
    SyncSide(kind: .folder, size: size, fileCount: files, modified: t0)
}

private func options(_ direction: SyncDirection = .bothWays, delete: Bool = false) -> SyncOptions {
    var o = SyncOptions()
    o.direction = direction
    o.deleteMissing = delete
    return o
}

private func item(_ path: String, _ state: SyncState, left: SyncSide?, right: SyncSide?,
                  options o: SyncOptions = options()) -> SyncItem {
    SyncItem(path: path, left: left, right: right, state: state,
             defaultAction: SyncRules.defaultAction(state: state, left: left, right: right, options: o))
}

private func has(_ item: SyncItem, _ effect: SyncEffect, _ target: Side?) -> Bool {
    let result = SyncRules.effect(of: item)
    return result.effect == effect && result.target == target
}

@Suite struct SyncOptionsTests {
    @Test func defaults() {
        let o = SyncOptions()
        #expect(o.includeSubfolders && o.compareDate && o.ignoreHourDifference && o.compareSize)
        #expect(!o.compareContent && !o.deleteMissing)
        #expect(o.ignoreFiles == nil && o.ignoreFolders == nil)
        #expect(o.direction == .bothWays)
        #expect(SyncOptions.dateTolerance == 2)
    }

    @Test func missingAndUnknownFieldsKeepDefaults() throws {
        let json = #"{"compareContent": true, "direction": "sideways", "ignoreFiles": "*.o"}"#
        let o = try JSONDecoder().decode(SyncOptions.self, from: Data(json.utf8))
        #expect(o.compareContent)
        #expect(o.direction == .bothWays)
        #expect(o.ignoreFiles == "*.o")
        #expect(o.includeSubfolders && o.compareDate && o.compareSize && !o.deleteMissing)
        let empty = try JSONDecoder().decode(SyncOptions.self, from: Data("{}".utf8))
        #expect(empty == SyncOptions())
    }

    @Test func roundTrip() throws {
        var o = options(.rightToLeft, delete: true)
        o.ignoreFolders = "build;.git"
        o.includeSubfolders = false
        let back = try JSONDecoder().decode(SyncOptions.self, from: JSONEncoder().encode(o))
        #expect(back == o)
    }

    @Test func deletionSide() {
        #expect(options(.bothWays, delete: true).deletionSide == nil)
        #expect(options(.leftToRight, delete: false).deletionSide == nil)
        #expect(options(.leftToRight, delete: true).deletionSide == .right)
        #expect(options(.rightToLeft, delete: true).deletionSide == .left)
    }
}

@Suite struct SyncGuardTests {
    @Test func sameAndNested() throws {
        try TestSandbox.with(sync: { root in
            let a = root.appending(path: "a"), b = a.appending(path: "b"), ab = root.appending(path: "ab")
            try TestSandbox.mkdirs(b)
            try TestSandbox.mkdirs(ab)
            #expect(SyncGuard.check(left: a, right: a) == .same)
            #expect(SyncGuard.check(left: a, right: URL(fileURLWithPath: a.path + "/")) == .same)
            #expect(SyncGuard.check(left: a, right: b) == .nested)
            #expect(SyncGuard.check(left: b, right: a) == .nested)
            #expect(SyncGuard.check(left: a, right: ab) == nil)
            #expect(SyncGuard.check(left: ab, right: a) == nil)
        })
    }

    @Test func nestedThroughALink() throws {
        try TestSandbox.with(sync: { root in
            let a = root.appending(path: "a"), inner = a.appending(path: "inner")
            try TestSandbox.mkdirs(inner)
            let link = root.appending(path: "link")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: inner.path)
            #expect(SyncGuard.check(left: a, right: link) == .nested)
            let same = root.appending(path: "same")
            try FileManager.default.createSymbolicLink(atPath: same.path, withDestinationPath: a.path)
            #expect(SyncGuard.check(left: same, right: a) == .same)
        })
    }

    @Test func caseOnlyDifferenceIsTheSameFolderOnACaseInsensitiveVolume() throws {
        try TestSandbox.with(sync: { root in
            let a = root.appending(path: "Folder")
            try TestSandbox.mkdirs(a)
            guard !NameRules.forVolume(containing: root).caseSensitive else { return }
            #expect(SyncGuard.check(left: a, right: root.appending(path: "folder")) == .same)
        })
    }
}

@Suite struct SyncRulesTests {
    @Test func defaultActionsBothWays() {
        let o = options(.bothWays, delete: true)
        func a(_ s: SyncState) -> SyncAction { SyncRules.defaultAction(state: s, left: file(), right: file(), options: o) }
        #expect(a(.onlyLeft) == .toRight)
        #expect(a(.onlyRight) == .toLeft)
        #expect(a(.leftNewer) == .toRight)
        #expect(a(.rightNewer) == .toLeft)
        #expect(a(.different) == .none)
        #expect(a(.equal) == .none)
        #expect(a(.error("x")) == .none)
    }

    @Test func defaultActionsLeftToRight() {
        for delete in [false, true] {
            let o = options(.leftToRight, delete: delete)
            func a(_ s: SyncState) -> SyncAction { SyncRules.defaultAction(state: s, left: file(), right: file(), options: o) }
            #expect(a(.onlyLeft) == .toRight)
            #expect(a(.leftNewer) == .toRight)
            #expect(a(.onlyRight) == (delete ? .toRight : .none))
            #expect(a(.rightNewer) == .none)
            #expect(a(.different) == .none)
            #expect(a(.equal) == .none)
            #expect(a(.error("x")) == .none)
        }
    }

    @Test func defaultActionsRightToLeft() {
        for delete in [false, true] {
            let o = options(.rightToLeft, delete: delete)
            func a(_ s: SyncState) -> SyncAction { SyncRules.defaultAction(state: s, left: file(), right: file(), options: o) }
            #expect(a(.onlyRight) == .toLeft)
            #expect(a(.rightNewer) == .toLeft)
            #expect(a(.onlyLeft) == (delete ? .toLeft : .none))
            #expect(a(.leftNewer) == .none)
            #expect(a(.different) == .none)
            #expect(a(.equal) == .none)
        }
    }

    @Test func possibleActions() {
        let both = item("a", .different, left: file(), right: file())
        #expect(SyncRules.possible(both, options: options()) == [.none, .toRight, .toLeft])
        let onlyLeft = item("a", .onlyLeft, left: file(), right: nil)
        #expect(SyncRules.possible(onlyLeft, options: options()) == [.none, .toRight])
        // Copies stay possible against the direction; deleting only on its target side.
        #expect(SyncRules.possible(onlyLeft, options: options(.rightToLeft, delete: false)) == [.none, .toRight])
        #expect(SyncRules.possible(onlyLeft, options: options(.rightToLeft, delete: true)) == [.none, .toRight, .toLeft])
        #expect(SyncRules.possible(onlyLeft, options: options(.leftToRight, delete: true)) == [.none, .toRight])
        let onlyRight = item("a", .onlyRight, left: nil, right: file())
        #expect(SyncRules.possible(onlyRight, options: options(.leftToRight, delete: true)) == [.none, .toRight, .toLeft])
        #expect(SyncRules.possible(onlyRight, options: options(.bothWays, delete: true)) == [.none, .toLeft])
        let error = item("a", .error("x"), left: file(), right: file())
        #expect(SyncRules.possible(error, options: options()) == [.none])
    }

    @Test func setChangesOnlyWherePossible() {
        var items = [
            item("a", .onlyLeft, left: file(), right: nil),
            item("b", .onlyRight, left: nil, right: file()),
            item("c", .error("x"), left: file(), right: file()),
            item("d", .different, left: file(), right: file()),
        ]
        let refused = SyncRules.set(.toRight, at: [0, 1, 2, 3], in: &items, options: options())
        #expect(refused == [1, 2])
        #expect(items.map(\.action) == [.toRight, .toLeft, .none, .toRight])
        #expect(SyncRules.set(.none, at: 0..<4, in: &items, options: options()).isEmpty)
        #expect(items.allSatisfy { $0.action == .none })
        #expect(items[0].defaultAction == .toRight)
    }

    @Test func toggleExcludedKeepsTheAction() {
        var items = [item("a", .onlyLeft, left: file(), right: nil), item("b", .leftNewer, left: file(), right: file())]
        items[1].excluded = true
        SyncRules.toggleExcluded(at: [0, 1], in: &items)
        #expect(items.allSatisfy { $0.excluded })
        SyncRules.toggleExcluded(at: [0, 1], in: &items)
        #expect(items.allSatisfy { !$0.excluded })
        #expect(items.map(\.action) == [.toRight, .toRight])
    }

    @Test func effects() {
        var a = item("a", .onlyLeft, left: file(), right: nil)
        #expect(has(a, .copy, .right))
        a.action = .toLeft
        #expect(has(a, .delete, .left))
        a.excluded = true
        #expect(has(a, .nothing, nil))
        var b = item("b", .rightNewer, left: file(), right: file())
        #expect(has(b, .overwrite, .left))
        b.action = .none
        #expect(has(b, .nothing, nil))
        var c = item("c", .different, left: file(), right: folder(5, files: 2))
        c.action = .toRight
        #expect(has(c, .replace, .right))
        c.action = .toLeft
        #expect(has(c, .replace, .left))
        var d = item("d", .equal, left: folder(), right: folder())
        d.action = .toRight
        #expect(has(d, .nothing, nil))
        var e = item("e", .different, left: SyncSide(kind: .link(target: "x"), size: 1, fileCount: 1, modified: t0),
                     right: SyncSide(kind: .link(target: "y"), size: 1, fileCount: 1, modified: t0))
        e.action = .toRight
        #expect(has(e, .overwrite, .right))
        var f = item("f", .different, left: SyncSide(kind: .link(target: "x"), size: 1, fileCount: 1, modified: t0),
                     right: file())
        f.action = .toLeft
        #expect(has(f, .replace, .left))
    }

    @Test func itemNameAndDepth() {
        let i = SyncItem(path: "a/b/c.txt", left: file(), right: nil, state: .onlyLeft)
        #expect(i.name == "c.txt" && i.depth == 2 && i.id == "a/b/c.txt")
        #expect(SyncItem(path: "top", left: file(), right: nil, state: .onlyLeft).depth == 0)
    }

    @Test func urlUsesEachSideSpelling() {
        let i = SyncItem(path: "Docs/a.txt", left: nil, right: file(), state: .onlyRight,
                         leftPath: "Docs/a.txt", rightPath: "docs/a.txt")
        let c = SyncComparison(left: URL(fileURLWithPath: "/L"), right: URL(fileURLWithPath: "/R"),
                               options: options(), rules: .apfsDefault, items: [i])
        #expect(c.url(of: i, on: .left).path == "/L/Docs/a.txt")
        #expect(c.url(of: i, on: .right).path == "/R/docs/a.txt")
    }
}

@Suite struct SyncPlanTests {
    private func comparison(_ items: [SyncItem], _ o: SyncOptions = options()) -> SyncComparison {
        SyncComparison(left: URL(fileURLWithPath: "/L"), right: URL(fileURLWithPath: "/R"), options: o,
                       rules: .apfsDefault, items: items)
    }

    @Test func countsAndBytes() {
        var excluded = item("x", .onlyLeft, left: file(1000), right: nil)
        excluded.excluded = true
        let items = [
            item("a", .onlyLeft, left: file(100), right: nil),
            item("dir", .onlyLeft, left: folder(5000, files: 3), right: nil),
            item("b", .rightNewer, left: file(7), right: file(30)),
            item("same", .equal, left: file(10), right: file(10)),
            item("diff", .different, left: file(10), right: file(11)),
            excluded,
        ]
        let plan = SyncPlan(comparison(items))
        #expect(plan.steps.map(\.item.path) == ["a", "dir", "b"])
        #expect(plan.files(to: .right) == 4)
        #expect(plan.bytes(to: .right) == 5100)
        #expect(plan.files(to: .left) == 1)
        #expect(plan.bytes(to: .left) == 30)
        #expect(plan.deletionCount == 0)
        #expect(!plan.isEmpty)
        #expect(plan.trashLine == nil)
        #expect(plan.copyLine != nil)
    }

    @Test func replacementCountsAsACopyAndADeletion() {
        var c = item("c", .different, left: folder(400, files: 2), right: file(9))
        c.action = .toRight
        let o = options(.leftToRight, delete: true)
        let gone = item("gone", .onlyRight, left: nil, right: file(50), options: o)
        let plan = SyncPlan(comparison([c, gone], o))
        #expect(plan.steps.map(\.effect) == [.replace, .delete])
        #expect(plan.files(to: .right) == 2)
        #expect(plan.bytes(to: .right) == 400)
        #expect(plan.deletions(on: .right) == 2)
        #expect(plan.deletions(on: .left) == 0)
        #expect(plan.deletionCount == 2)
        #expect(plan.trashLine != nil)
    }

    @Test func emptyPlan() {
        let plan = SyncPlan(comparison([item("same", .equal, left: file(), right: file())]))
        #expect(plan.isEmpty)
        #expect(plan.copyLine == nil && plan.trashLine == nil)
        #expect(plan.summary == "Nothing to do")
    }

    @Test func summaryTexts() {
        let o = options(.leftToRight, delete: true)
        let plan = SyncPlan(comparison([
            item("a", .onlyLeft, left: file(1500), right: nil, options: o),
            item("b", .onlyRight, left: nil, right: file(5), options: o),
        ], o))
        #expect(plan.summary.hasPrefix("Copy 1 file"))
        #expect(plan.summary.contains("to the right"))
        #expect(plan.summary.contains("to the Trash"))
        #expect(!plan.summary.contains("to the left"))
        #expect(plan.trashLine?.hasPrefix("Move 1 item") == true)
    }
}

@Suite struct SyncCheckTests {
    private func setDate(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test func detectsChanges() throws {
        try TestSandbox.with(sync: { root in
            let l = root.appending(path: "L"), r = root.appending(path: "R")
            try TestSandbox.mkdirs(l)
            try TestSandbox.mkdirs(r)
            try TestSandbox.write(l.appending(path: "a"), "hello")
            try setDate(l.appending(path: "a"), t0)
            try FileManager.default.createSymbolicLink(atPath: r.appending(path: "link").path, withDestinationPath: "target")
            let linkDate = try #require(try? r.appending(path: "link").resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate)
            let a = SyncItem(path: "a", left: SyncSide(kind: .file, size: 5, fileCount: 1, modified: t0), right: nil,
                             state: .onlyLeft, defaultAction: .toRight)
            let link = SyncItem(path: "link", left: nil,
                                right: SyncSide(kind: .link(target: "target"), size: 6, fileCount: 1, modified: linkDate),
                                state: .onlyRight)
            let c = SyncComparison(left: l, right: r, options: options(), rules: .apfsDefault, items: [a, link])
            #expect(SyncCheck.unchanged(a, in: c))
            #expect(SyncCheck.unchanged(link, in: c))

            // Date
            try setDate(l.appending(path: "a"), t0.addingTimeInterval(1))
            #expect(!SyncCheck.unchanged(a, in: c))
            try setDate(l.appending(path: "a"), t0)
            #expect(SyncCheck.unchanged(a, in: c))
            // Size
            try TestSandbox.write(l.appending(path: "a"), "hello!")
            try setDate(l.appending(path: "a"), t0)
            #expect(!SyncCheck.unchanged(a, in: c))
            try TestSandbox.write(l.appending(path: "a"), "hello")
            try setDate(l.appending(path: "a"), t0)
            // A target appeared
            try TestSandbox.write(r.appending(path: "a"), "x")
            #expect(!SyncCheck.unchanged(a, in: c))
            try FileManager.default.removeItem(at: r.appending(path: "a"))
            #expect(SyncCheck.unchanged(a, in: c))
            // The source vanished
            try FileManager.default.removeItem(at: l.appending(path: "a"))
            #expect(!SyncCheck.unchanged(a, in: c))
            // Another link target
            try FileManager.default.removeItem(at: r.appending(path: "link"))
            try FileManager.default.createSymbolicLink(atPath: r.appending(path: "link").path, withDestinationPath: "other")
            #expect(!SyncCheck.unchanged(link, in: c))
            // A folder where a file was
            try TestSandbox.mkdirs(l.appending(path: "a"))
            #expect(!SyncCheck.unchanged(a, in: c))
        })
    }
}
