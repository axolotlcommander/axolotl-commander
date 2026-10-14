// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// The tab list rules of spec 028 (no files are touched).
@Suite struct TabLockTests {
    static func state(_ path: String, cursor: String? = nil) -> PanelState {
        PanelState(location: URL(filePath: path), cursorName: cursor)
    }

    /// Tabs at /a, /b, /c, … with the first active.
    static func list(_ paths: [String]) -> TabList {
        var list = TabList(state(paths[0]))
        for path in paths.dropFirst() { list.open(state(path), activate: true) }
        list.select(0)
        return list
    }

    let paths = ["/a", "/b", "/c", "/d"]

    func locations(_ list: TabList) -> [String] { list.tabs.map(\.location.path) }

    @Test func updateCurrentKeepsTheLock() {
        var list = Self.list(["/a", "/b"])
        list.setLock(.locked, at: 0)
        list.updateCurrent(Self.state("/a", cursor: "x"))      // a snapshot has no lock
        #expect(list.current.lock?.mode == .locked)
        #expect(list.current.cursorName == "x")
        list.setLock(nil, at: 0)
        #expect(list.current.lock == nil)
    }

    @Test func lockRemembersFolderAndCursor() {
        var list = TabList(Self.state("/work", cursor: "notes.txt"))
        list.setLock(.allowsChanges, at: 0)
        #expect(list.current.lock == TabLock(mode: .allowsChanges, folder: URL(filePath: "/work"), cursorName: "notes.txt"))
    }

    @Test func splitOpensTheNewFolderAtTheEnd() {
        var list = Self.list(["/a", "/b"])
        list.setLock(.locked, at: 0)
        list.split(keeping: Self.state("/a", cursor: "sub"), opened: Self.state("/a/sub"))
        #expect(locations(list) == ["/a", "/b", "/a/sub"])
        #expect(list.active == 2)
        #expect(list.tabs[0].lock?.mode == .locked)
        #expect(list.tabs[0].cursorName == "sub")
        #expect(list.tabs[1].lock == nil)
    }

    @Test func returnOnActivation() {
        var list = Self.list(["/a", "/b"])
        list.updateCurrent(PanelState(location: URL(filePath: "/a"), cursorName: "one",
                                      back: [.init(url: URL(filePath: "/"))]))
        list.setLock(.allowsChanges, at: 0)
        var moved = list.current
        moved.location = URL(filePath: "/a/deep")
        moved.cursorName = "other"
        moved.selectedNames = ["other"]
        list.updateCurrent(moved)
        list.returnCurrentToLock()
        #expect(list.current.location.path == "/a")
        #expect(list.current.cursorName == "one")
        #expect(list.current.selectedNames.isEmpty)
        #expect(list.current.back.count == 1)                   // history stays
        // A strictly locked tab is never moved by the return.
        list.setLock(.locked, at: 1)
        list.select(1)
        list.returnCurrentToLock()
        #expect(list.current.location.path == "/b")
    }

    @Test func returnAllAtStart() {
        var list = Self.list(["/a", "/b"])
        list.setLock(.allowsChanges, at: 1)
        list.select(1)
        list.updateCurrent(Self.state("/b/elsewhere"))
        list.returnAllToLocks()
        #expect(locations(list) == ["/a", "/b"])
    }

    @Test func closingSeveralKeepsLockedTabs() {
        var list = Self.list(paths)
        list.setLock(.locked, at: 1)
        list.setLock(.allowsChanges, at: 3)
        list.select(2)
        let closed = list.closeOthers(keeping: 0)
        #expect(locations(list) == ["/a", "/b", "/d"])
        #expect(closed.map(\.location.path) == ["/c"])
        #expect(list.current.location.path == "/a")             // the active tab was closed: the kept one

        list = Self.list(paths)
        list.setLock(.locked, at: 2)
        list.select(1)
        #expect(list.closeToTheRight(of: 0).map(\.location.path) == ["/b", "/d"])
        #expect(locations(list) == ["/a", "/c"])
        #expect(list.current.location.path == "/a")

        list = Self.list(paths)
        list.select(1)
        list.closeToTheRight(of: 2)
        #expect(locations(list) == ["/a", "/b", "/c"])
        #expect(list.current.location.path == "/b")             // the active tab stays active
        #expect(list.closeToTheRight(of: 2).isEmpty)            // nothing to the right
    }

    @Test func duplicateIsUnlocked() {
        var list = Self.list(["/a", "/b"])
        list.setLock(.locked, at: 0)
        list.duplicate(at: 0)
        #expect(locations(list) == ["/a", "/b", "/a"])
        #expect(list.active == 2)
        #expect(list.tabs[0].lock != nil && list.tabs[2].lock == nil)
    }

    @Test func ejectedVolumesDropLocks() {
        var list = Self.list(["/Volumes/X/a", "/Volumes/X/b", "/c"])
        list.setLock(.locked, at: 0)
        list.setLock(.locked, at: 1)
        list.setLock(.locked, at: 2)
        let onX = { (url: URL) in url.path.hasPrefix("/Volumes/X") }
        list.unlock(where: onX)
        #expect(list.tabs.map { $0.lock == nil } == [true, true, false])
        // A tab that browsed away from a locked folder on the volume is unlocked too.
        var away = Self.list(["/Volumes/X/a", "/c"])
        away.setLock(.allowsChanges, at: 0)
        away.updateCurrent(Self.state("/elsewhere"))
        away.unlock(where: onX)
        #expect(away.tabs[0].lock == nil)
        list.setLock(.locked, at: 1)
        list.redirect(where: onX, to: URL(filePath: "/Users/u"))
        #expect(list.tabs[1].lock == nil && list.tabs[1].location.path == "/Users/u")
    }

    @Test func relockMovesTheFolder() {
        var list = TabList(Self.state("/gone/deep", cursor: "x"))
        list.setLock(.allowsChanges, at: 0)
        list.relock(at: 0, to: URL(filePath: "/gone"))
        #expect(list.current.lock?.folder.path == "/gone" && list.current.lock?.cursorName == nil)
    }

    @Test func splitNextToCurrentOpensRightAfterTheLockedTab() {
        var list = Self.list(["/a", "/b"])
        list.select(0)
        list.setLock(.locked, at: 0)
        list.split(keeping: Self.state("/a", cursor: "sub"), opened: Self.state("/a/sub"), nextToCurrent: true)
        #expect(locations(list) == ["/a", "/a/sub", "/b"])
        #expect(list.active == 1)
    }

    @Test func newTabsNextToCurrentSetting() {
        #expect(PanelBehavior().newTabsNextToCurrent == false)
        let suite = "TabLockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PanelBehavior.tabsNextToCurrentKey)
        #expect(PanelBehavior(defaults: defaults).newTabsNextToCurrent)
        #expect(PanelBehavior.tabsNextToCurrentKey == "panel.newTabsNextToCurrent")
    }

    @Test func alwaysShowTabsSetting() {
        #expect(PanelBehavior().alwaysShowTabs == false)
        let suite = "TabLockTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PanelBehavior.alwaysShowTabsKey)
        #expect(PanelBehavior(defaults: defaults).alwaysShowTabs)
        #expect(PanelBehavior.alwaysShowTabsKey == "panel.alwaysShowTabs")
    }

    /// Which tabs the strip shows when only `capacity` fit (spec 028, "»").
    @Test func visibleTabsKeepTheActiveOne() {
        #expect(TabStripLayout.visible(count: 3, active: 2, capacity: 5) == [0, 1, 2])
        #expect(TabStripLayout.visible(count: 6, active: 1, capacity: 3) == [0, 1, 2])
        #expect(TabStripLayout.visible(count: 6, active: 4, capacity: 3) == [0, 1, 4])
        #expect(TabStripLayout.visible(count: 6, active: 5, capacity: 1) == [5])
        #expect(TabStripLayout.capacity(width: 400, count: 3, tabWidth: 90, spacing: 1, button: 22) == 3)
        // 4 tabs need 363 + "+"; they do not fit in 300, so "»" takes room as well.
        #expect(TabStripLayout.capacity(width: 300, count: 4, tabWidth: 90, spacing: 1, button: 22) == 2)
        #expect(TabStripLayout.capacity(width: 0, count: 4, tabWidth: 90, spacing: 1, button: 22) == 1)
    }

    @Test func locksAreSavedAndOldLayoutsLoadUnlocked() throws {
        var list = Self.list(["/a", "/b"])
        list.setLock(.locked, at: 0)
        list.setLock(.allowsChanges, at: 1)
        let decoded = try JSONDecoder().decode(TabList.self, from: JSONEncoder().encode(list))
        #expect(decoded.tabs.map(\.lock) == list.tabs.map(\.lock))
        let old = Data(#"{"tabs": [{"location": "file:///a"}, {"location": "file:///b"}], "active": 1}"#.utf8)
        let loaded = try JSONDecoder().decode(TabList.self, from: old)
        #expect(loaded.tabs.allSatisfy { $0.lock == nil })
    }
}
