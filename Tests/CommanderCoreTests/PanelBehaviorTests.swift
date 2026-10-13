// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Panel behavior options (spec 011): settings, typing routing, ⌃← / ⌃→ plans and volume buttons.
@Suite struct PanelBehaviorTests {
    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "test.behavior.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    // MARK: Settings

    @Test func defaultsKeepTodaysBehavior() {
        withSuite { defaults in
            let behavior = PanelBehavior(defaults: defaults)
            #expect(behavior == PanelBehavior())
            #expect(behavior.spaceMovesDown)
            #expect(!behavior.typingToCommandLine)
            #expect(!behavior.arrowsTargetPointedPanel)
            #expect(!behavior.volumeButtonsFollow)
        }
    }

    @Test func readsStoredValues() {
        withSuite { defaults in
            defaults.set(false, forKey: PanelBehavior.spaceKey)
            defaults.set(true, forKey: PanelBehavior.typingKey)
            defaults.set(true, forKey: PanelBehavior.arrowsKey)
            defaults.set(true, forKey: PanelBehavior.volumesKey)
            let behavior = PanelBehavior(defaults: defaults)
            #expect(!behavior.spaceMovesDown)
            #expect(behavior.typingToCommandLine)
            #expect(behavior.arrowsTargetPointedPanel)
            #expect(behavior.volumeButtonsFollow)
        }
    }

    @Test func keysAreExportedAsBooleans() throws {
        let keys = [PanelBehavior.spaceKey, PanelBehavior.typingKey, PanelBehavior.arrowsKey, PanelBehavior.volumesKey]
        #expect(keys == ["panel.spaceMovesDown", "panel.typingToCommandLine",
                         "panel.arrowsTargetPointedPanel", "panel.volumeButtonsFollow"])
        try withSuite { source in
            source.set(false, forKey: PanelBehavior.spaceKey)
            source.set(true, forKey: PanelBehavior.typingKey)
            source.set(true, forKey: PanelBehavior.arrowsKey)
            source.set(true, forKey: PanelBehavior.volumesKey)
            let data = try SettingsArchive.export(from: source, catalog: .app, appVersion: "test")
            let contents = try SettingsArchive.read(data)
            withSuite { target in
                let report = SettingsArchive.apply(contents, sections: [.preferences], to: target, catalog: .app)
                #expect(report.skipped.isEmpty)
                #expect(PanelBehavior(defaults: target) == PanelBehavior(defaults: source))
            }
        }
    }

    // MARK: Typing

    private func route(_ key: KeyChord.Key, _ modifiers: KeyChord.Modifiers = [], text: String? = nil,
                       base: String? = nil, empty: Bool = true, searching: Bool = false,
                       bound: Bool = false) -> PanelTyping.Action {
        PanelTyping.route(key: key, modifiers: modifiers, text: text, baseText: base,
                          lineIsEmpty: empty, quickSearchActive: searching, isBound: bound)
    }

    @Test func charactersGoToTheLine() {
        #expect(route(.character("l"), text: "l") == .append("l"))
        #expect(route(.character("l"), .shift, text: "L") == .append("L"))
        #expect(route(.character("ě"), text: "ě", empty: false) == .append("ě"))
        #expect(route(.character("-"), text: "-") == .append("-"))
        // ⌘ and ⌃ characters are never typed.
        #expect(route(.character("c"), .control, text: "\u{3}") == .none)
        #expect(route(.character("c"), .command, text: "c") == .none)
    }

    @Test func optionCharacterStartsQuickSearch() {
        #expect(route(.character("r"), .option, text: "®", base: "r") == .startQuickSearch("r"))
        #expect(route(.character("2"), .option, text: "@", base: "ě") == .startQuickSearch("ě"))
        #expect(route(.character("r"), [.option, .shift], text: "‰", base: "R") == .startQuickSearch("R"))
        #expect(route(.character("r"), [.option, .control], text: "r", base: "r") == .none)
    }

    @Test func lineKeysActOnlyWithText() {
        #expect(route(.enter, empty: false) == .run)
        #expect(route(.numEnter, empty: false) == .run)
        #expect(route(.backspace, empty: false) == .deleteLast)
        #expect(route(.escape, empty: false) == .clear)
        #expect(route(.space, empty: false) == .append(" "))
        for key: KeyChord.Key in [.enter, .backspace, .escape, .space] {
            #expect(route(key, empty: true) == .none)
        }
        // ⇧Return works on the panel item; arrows and F-keys stay with the panel.
        #expect(route(.enter, .shift, empty: false) == .none)
        #expect(route(.down, empty: false) == .none)
        #expect(route(.function(5), empty: false) == .none)
        #expect(route(.insert, empty: false) == .none)
    }

    @Test func quickSearchAndBoundChordsWin() {
        #expect(route(.character("a"), text: "a", searching: true) == .none)
        #expect(route(.backspace, empty: false, searching: true) == .none)
        #expect(route(.character("r"), .option, text: "®", base: "r", bound: true) == .none)
        // Return, Backspace, Esc and Space have panel commands, yet act on a line with text.
        #expect(route(.enter, empty: false, bound: true) == .run)
        #expect(route(.space, empty: false, bound: true) == .append(" "))
        #expect(route(.space, empty: true, bound: true) == .none)
    }

    // MARK: Open in Left / Right Panel

    @Test func todaysPlanAlwaysSendsToTheOtherPanel() {
        // Left active: ⌃→ sends right and follows; ⌃← sends right and stays.
        #expect(OpenInPanel.plan(target: .right, active: .left, classic: false)
            == .init(source: .left, target: .right, focus: .right))
        #expect(OpenInPanel.plan(target: .left, active: .left, classic: false)
            == .init(source: .left, target: .right, focus: .left))
        #expect(OpenInPanel.plan(target: .left, active: .right, classic: false)
            == .init(source: .right, target: .left, focus: .left))
        #expect(OpenInPanel.plan(target: .right, active: .right, classic: false)
            == .init(source: .right, target: .left, focus: .right))
    }

    @Test func classicPlanChangesThePanelTheArrowPointsTo() {
        #expect(OpenInPanel.plan(target: .right, active: .left, classic: true)
            == .init(source: .left, target: .right, focus: .left))
        #expect(OpenInPanel.plan(target: .left, active: .left, classic: true)
            == .init(source: .right, target: .left, focus: .left))
        #expect(OpenInPanel.plan(target: .left, active: .right, classic: true)
            == .init(source: .right, target: .left, focus: .right))
        #expect(OpenInPanel.plan(target: .right, active: .right, classic: true)
            == .init(source: .left, target: .right, focus: .right))
    }

    // MARK: Volume buttons

    private let root = URL(fileURLWithPath: "/")
    private let disk = URL(fileURLWithPath: "/Volumes/Disk")

    private func choose(_ volume: URL, panel: URL?, other: URL? = nil, otherVolume: URL? = nil,
                        remembered: URL? = nil, existing: Set<String> = []) -> String {
        switch VolumeChoice.target(volume: volume, panelVolume: panel, otherFolder: other, otherVolume: otherVolume,
                                   remembered: remembered, exists: { existing.contains($0.path) }) {
        case .refresh: "refresh"
        case .open(let folder): folder.path
        }
    }

    @Test func bothPanelsOnTheVolumeMirrorTheOtherPanel() {
        let other = URL(fileURLWithPath: "/Volumes/Disk/Photos")
        #expect(choose(disk, panel: disk, other: other, otherVolume: disk) == "/Volumes/Disk/Photos")
    }

    @Test func onlyThisPanelOnTheVolumeRefreshesTheFolder() {
        let remembered = URL(fileURLWithPath: "/Volumes/Disk/Music")
        #expect(choose(disk, panel: disk, other: URL(fileURLWithPath: "/Users/someone"), otherVolume: root,
                       remembered: remembered, existing: [remembered.path]) == "refresh")
    }

    @Test func otherPanelsFolderOnTheVolumeWins() {
        let other = URL(fileURLWithPath: "/Volumes/Disk/Photos/2026")
        let remembered = URL(fileURLWithPath: "/Volumes/Disk/Music")
        #expect(choose(disk, panel: root, other: other, otherVolume: URL(fileURLWithPath: "/Volumes/Disk/"),
                       remembered: remembered, existing: [remembered.path]) == "/Volumes/Disk/Photos/2026")
    }

    @Test func rememberedFolderThenRoot() {
        let remembered = URL(fileURLWithPath: "/Volumes/Disk/Music")
        let other = URL(fileURLWithPath: "/Users/someone")
        #expect(choose(disk, panel: root, other: other, otherVolume: root,
                       remembered: remembered, existing: [remembered.path]) == "/Volumes/Disk/Music")
        // A deleted or ejected folder falls back to the root.
        #expect(choose(disk, panel: root, other: other, otherVolume: root, remembered: remembered) == "/Volumes/Disk")
        #expect(choose(disk, panel: root) == "/Volumes/Disk")
    }

    @Test func archivesServersAndNetworkDoNotCount() {
        // The UI passes nil volumes for them, so the rules fall through.
        let remembered = URL(fileURLWithPath: "/Volumes/Disk/Music")
        #expect(choose(disk, panel: nil, other: nil, otherVolume: nil,
                       remembered: remembered, existing: [remembered.path]) == "/Volumes/Disk/Music")
        #expect(choose(disk, panel: nil) == "/Volumes/Disk")
    }

    @Test func volumePlacesRememberThePerVolumeFolder() {
        var places = VolumePlaces()
        #expect(places.folder(on: disk) == nil)
        places.visit(URL(fileURLWithPath: "/Volumes/Disk/a"), volume: disk)
        places.visit(URL(fileURLWithPath: "/Users/someone"), volume: root)
        places.visit(URL(fileURLWithPath: "/Volumes/Disk/b"), volume: URL(fileURLWithPath: "/Volumes/Disk/"))
        #expect(places.folder(on: disk)?.path == "/Volumes/Disk/b")
        #expect(places.folder(on: root)?.path == "/Users/someone")
    }
}
