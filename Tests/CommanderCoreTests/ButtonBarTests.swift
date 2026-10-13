// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// The button bar's model, defaults and layout (spec 018, SC-002).
@Suite struct ButtonBarTests {
    @Test func placementDefaultsToOffAndShowsAtTheTop() {
        #expect(ButtonBarPlacement(storage: nil) == .off)
        #expect(ButtonBarPlacement(storage: "nonsense") == .off)
        #expect(ButtonBarPlacement(storage: "bottom") == .bottom)
        #expect(ButtonBarPlacement.shown(last: nil) == .top)
        #expect(ButtonBarPlacement.shown(last: "off") == .top)
        #expect(ButtonBarPlacement.shown(last: "bottom") == .bottom)
    }

    @Test func missingDataGivesTheSamples() {
        #expect(ButtonBarStore.decode(nil) == ButtonBarStore.samples)
        #expect(ButtonBarStore.decode(Data("not json".utf8)) == ButtonBarStore.samples)
        #expect(ButtonBarStore.decode(Data("[]".utf8)).isEmpty)
        #expect(ButtonBarStore.samples.compactMap(\.resolvedCommand).count == 6)
    }

    @Test func buttonsRoundTrip() throws {
        let program = UserMenuItem(title: "Edit", program: "/Applications/TextEdit.app", arguments: "$(FullName)")
        let items: [ButtonBarItem] = [.command(.find, icon: "star"), .separator, .program(program, icon: ButtonBarIcon.appIcon)]
        #expect(ButtonBarStore.decode(try ButtonBarStore.encode(items)) == items)
    }

    @Test func brokenEntriesAreDroppedAndUnknownCommandsKept() {
        let json = """
        [{"kind": "command", "command": "find"}, {"kind": "rocket"}, {"kind": "command", "command": "teleport"},
         {"kind": "program", "program": {"title": "Git", "program": "git"}}]
        """
        let items = ButtonBarStore.decode(Data(json.utf8))
        #expect(items.map(\.kind) == [.command, .command, .program])
        #expect(items[0].resolvedCommand == .find)
        #expect(items[1].resolvedCommand == nil)
        #expect(items[1].command == "teleport")
        #expect(items[2].program.program == "git")
    }

    @Test func defaultIcons() {
        #expect(ButtonBarIcon.resolve(.command(.find)) == .symbol("magnifyingglass"))
        #expect(ButtonBarIcon.resolve(.command(.find, icon: "star")) == .symbol("star"))
        #expect(ButtonBarIcon.resolve(.command(.sortBySize)) == .symbol("arrow.up.arrow.down"))
        #expect(ButtonBarIcon.resolve(ButtonBarItem(kind: .command, command: "teleport")) == .symbol(ButtonBarIcon.genericCommand))
        let app = UserMenuItem(program: "~/Applications/Tool.app")
        #expect(ButtonBarIcon.resolve(.program(app)) == .appIcon(path: NSString(string: "~/Applications/Tool.app").expandingTildeInPath))
        #expect(ButtonBarIcon.resolve(.program(UserMenuItem(program: "git"))) == .symbol(ButtonBarIcon.genericProgram))
        #expect(ButtonBarIcon.resolve(.program(UserMenuItem(program: "git"), icon: ButtonBarIcon.appIcon)) == .symbol(ButtonBarIcon.genericProgram))
        #expect(ButtonBarIcon.resolve(.program(app, icon: "hammer")) == .symbol("hammer"))
    }

    @Test func everythingFits() {
        let items: [ButtonBarItem] = [.command(.find), .separator, .command(.copy)]
        #expect(ButtonBarLayout.naturalWidth(items) == 28 + 9 + 28 + 4)
        #expect(ButtonBarLayout.visibleCount(items, in: 69) == 3)
    }

    @Test func whatDoesNotFitGoesIntoTheOverflowMenu() {
        let items: [ButtonBarItem] = Array(repeating: .command(.find), count: 10)
        // 100 points: » takes 22 + 2, leaving 76 = two buttons (28 + 2 + 28 = 58), not three (88).
        #expect(ButtonBarLayout.visibleCount(items, in: 100) == 2)
        #expect(ButtonBarLayout.visibleCount(items, in: 10) == 0)
    }

    @Test func aSeparatorAtTheCutIsNotShown() {
        let items: [ButtonBarItem] = [.command(.find), .command(.copy), .separator, .command(.move), .command(.delete)]
        // Room for 28 + 2 + 28 + 2 + 9 = 69 before »: the separator would end the row.
        #expect(ButtonBarLayout.visibleCount(items, in: 69 + 24 + 10) == 2)
    }

    @Test func bottomRowKeepsNaturalKeysWhenEverythingFits() {
        let row = ButtonBarLayout.bottomRow(width: 2000, keyCount: 12, buttons: 200, edge: 5, keyGap: 1, divider: 9, minKeyWidth: 36)
        #expect(row.keys == 10 + 12 * 140 + 11)
        #expect(row.buttons == 2000 - row.keys - 9 - 5)
    }

    @Test func bottomRowShrinksKeysBeforeButtons() {
        let row = ButtonBarLayout.bottomRow(width: 1000, keyCount: 12, buttons: 200, edge: 5, keyGap: 1, divider: 9, minKeyWidth: 36)
        #expect(row.keys == 1000 - 9 - 200 - 5)
        #expect(row.buttons == 200)
        let narrow = ButtonBarLayout.bottomRow(width: 500, keyCount: 12, buttons: 200, edge: 5, keyGap: 1, divider: 9, minKeyWidth: 36)
        #expect(narrow.keys == 10 + 12 * 36 + 11)
        #expect(narrow.buttons == 500 - narrow.keys - 9 - 5)
    }

    @Test func bottomRowWithoutKeysOrButtons() {
        #expect(ButtonBarLayout.bottomRow(width: 800, keyCount: 0, buttons: 100, edge: 5, keyGap: 1, divider: 9, minKeyWidth: 36) == (0, 790))
        #expect(ButtonBarLayout.bottomRow(width: 800, keyCount: 12, buttons: 0, edge: 5, keyGap: 1, divider: 9, minKeyWidth: 36) == (800, 0))
    }

    @Test func symbolSearch() {
        #expect(ButtonBarSymbols.search("").count == ButtonBarSymbols.all.count)
        let stars = ButtonBarSymbols.search("star")
        #expect(stars.contains("star") && stars.contains("star.fill"))
        #expect(ButtonBarSymbols.search("folder plus") == ["folder.badge.plus", "plus.rectangle.on.folder"])
        #expect(Set(ButtonBarSymbols.all).count == ButtonBarSymbols.all.count)
    }

    @Test func settingsExportIncludesTheBar() {
        #expect(SettingsCatalog.app.preferences.contains { $0.key == ButtonBarPlacement.key })
        #expect(SettingsCatalog.app.blobs[.buttonBar]?.defaultsKey == ButtonBarStore.key)
    }
}
