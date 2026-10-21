// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Reordering tabs and the tab look of spec 036 (no files are touched).
@Suite struct TabReorderTests {
    /// Tabs at /a, /b, /c, /d with `active` active.
    func list(active: Int) -> TabList {
        var list = TabLockTests.list(["/a", "/b", "/c", "/d"])
        list.select(active)
        return list
    }

    func locations(_ list: TabList) -> [String] { list.tabs.map(\.location.path) }

    @Test func movingTheActiveTabKeepsItActive() {
        var tabs = list(active: 0)
        tabs.move(from: 0, to: 2)
        #expect(locations(tabs) == ["/b", "/c", "/a", "/d"])
        #expect(tabs.current.location.path == "/a")
    }

    @Test func movingAnotherTabAcrossTheActiveOneKeepsTheActiveTab() {
        var tabs = list(active: 1)
        tabs.move(from: 3, to: 0)
        #expect(locations(tabs) == ["/d", "/a", "/b", "/c"])
        #expect(tabs.current.location.path == "/b")
        tabs.move(from: 0, to: 3)
        #expect(locations(tabs) == ["/a", "/b", "/c", "/d"])
        #expect(tabs.current.location.path == "/b")
    }

    @Test func targetsOutsideTheListClamp() {
        var tabs = list(active: 2)
        tabs.move(from: 0, to: 9)
        #expect(locations(tabs) == ["/b", "/c", "/d", "/a"])
        #expect(tabs.current.location.path == "/c")
        tabs.move(from: 9, to: 0)
        #expect(locations(tabs) == ["/b", "/c", "/d", "/a"])
    }

    @Test func canMoveOnlyInsideTheList() {
        let tabs = list(active: 0)
        #expect(!tabs.canMove(0, by: -1))
        #expect(tabs.canMove(0, by: 1))
        #expect(tabs.canMove(3, by: -1))
        #expect(!tabs.canMove(3, by: 1))
        #expect(!tabs.canMove(1, by: 0))
        #expect(!TabLockTests.list(["/a"]).canMove(0, by: 1))
    }

    @Test func moveCommandsHaveNoKeysAndLiveInTheGoMenu() {
        for command in [Command.moveTabLeft, .moveTabRight] {
            #expect(CommandRegistry.spec(command).menu == .go)
            for scheme in [KeyScheme.axolotl, .classicCommander] {
                #expect(scheme.chords(for: command).isEmpty)
            }
        }
    }

    @Test func tabLookDefaultsToStandard() {
        #expect(PanelBehavior().tabLook == .standard)
        let suite = "TabReorderTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PanelBehavior(defaults: defaults).tabLook == .standard)
        defaults.set("prominent", forKey: PanelBehavior.tabLookKey)
        #expect(PanelBehavior(defaults: defaults).tabLook == .prominent)
        defaults.set("rainbow", forKey: PanelBehavior.tabLookKey)
        #expect(PanelBehavior(defaults: defaults).tabLook == .standard)
    }
}
