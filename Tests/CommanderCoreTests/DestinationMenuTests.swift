// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// The destination menu of the copy/move dialog and the recent destinations (spec 021).
@Suite struct DestinationMenuTests {
    private func build(other: String? = "/other", otherTabs: [String] = [], ownTabs: [String] = [],
                       source: String = "/src", hot: [HotPath] = [], recent: [String] = [],
                       excluded: Set<String> = []) -> [DestinationMenu.Entry] {
        DestinationMenu.build(otherPanel: other, otherTabs: otherTabs, ownTabs: ownTabs, source: source,
                              hotPaths: hot, recent: recent, isExcluded: { excluded.contains($0) })
    }

    @Test func sectionOrder() {
        let entries = build(otherTabs: ["/ot"], ownTabs: ["/own"], hot: [HotPath(name: "Docs", path: "/docs")],
                            recent: ["/r"])
        #expect(entries.map(\.path) == ["/other", "/ot", "/own", "/docs", "/r"])
        #expect(entries.map(\.section) == [.otherPanel, .tabs, .tabs, .hotPaths, .recent])
    }

    @Test func dedupeIgnoresTrailingSlashAndFirstWins() {
        let entries = build(otherTabs: ["/other/", "/t"], ownTabs: ["/t/"], hot: [HotPath(name: "T", path: "/t")],
                            recent: ["/other"])
        #expect(entries.map(\.path) == ["/other", "/t"])
        #expect(entries[1].section == .tabs)
    }

    @Test func sourceAndExcludedLeftOut() {
        let entries = build(otherTabs: ["/src/", "/net", "/ok"], excluded: ["/net"])
        #expect(entries.map(\.path) == ["/other", "/ok"])
        #expect(build(other: nil, source: "/src").isEmpty)
    }

    @Test func titles() {
        let entries = build(hot: [HotPath(name: "Docs", path: "/docs"), HotPath(path: "/plain")], recent: ["/r"])
        #expect(entries.map(\.title) == ["/other", "Docs", "plain", "/r"])
        var unnamed = HotPath(path: "/z")
        unnamed.name = ""
        #expect(build(hot: [unnamed]).last?.title == "/z")
    }

    @Test func recentCapacityIsTen() {
        var recent = RecentPaths(capacity: DestinationMenu.recentCapacity)
        for i in 0..<15 { recent.add("/p\(i)") }
        #expect(recent.paths.count == 10)
        #expect(recent.paths.first == "/p14")
        #expect(recent.capacity == 10)
        #expect(RecentPaths(paths: (0..<30).map { "/\($0)" }).paths.count == RecentPaths.limit)
    }

    @Test func recentDecodesOldDataAndEncodesPathsOnly() throws {
        let old = Data(#"{"paths":["/a","/b"]}"#.utf8)
        let decoded = try JSONDecoder().decode(RecentPaths.self, from: old)
        #expect(decoded.paths == ["/a", "/b"])
        #expect(decoded.capacity == RecentPaths.limit)
        let encoded = try JSONEncoder().encode(RecentPaths(paths: ["/a"], capacity: 10))
        #expect(String(decoding: encoded, as: UTF8.self) == #"{"paths":["\/a"]}"#)
    }
}
