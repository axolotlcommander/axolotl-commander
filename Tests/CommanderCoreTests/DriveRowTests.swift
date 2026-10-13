// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

@Test func driveRowSettingsDefaultsAndStorage() {
    #expect(DriveRowSettings() == DriveRowSettings(showRow: true, showVolumeBar: true, freeSpaceElsewhere: true))
    #expect(DriveRowSettings { _ in nil } == DriveRowSettings())
    let stored: [String: Any] = ["driveRow.show": false, "volumeBar.show": false, "driveRow.freeSpaceElsewhere": false]
    #expect(DriveRowSettings { stored[$0] } == DriveRowSettings(showRow: false, showVolumeBar: false, freeSpaceElsewhere: false))
    // A value of the wrong type keeps the default.
    #expect(DriveRowSettings { $0 == "driveRow.show" ? "no" : nil }.showRow)
}

/// The free space shows in one place only: the row, else the volume bar, else the status line.
@Test(arguments: [
    (true, true, true, FreeSpacePlace.driveRow),
    (true, false, false, .driveRow),
    (true, true, false, .driveRow),
    (false, true, true, .volumeBar),
    (false, false, true, .statusLine),
    (false, true, false, .hidden),
    (false, false, false, .hidden),
])
func freeSpacePlace(row: Bool, volumeBar: Bool, elsewhere: Bool, place: FreeSpacePlace) {
    #expect(DriveRowSettings(showRow: row, showVolumeBar: volumeBar, freeSpaceElsewhere: elsewhere).freeSpacePlace == place)
}

@Test func diskSpaceUsedPercent() {
    #expect(DiskSpace(total: 1000, available: 250).usedPercent == 75)
    #expect(DiskSpace(total: 0, available: 0).usedPercent == 0)
    #expect(DiskSpace(total: 3, available: 2).usedPercent == 33)
    // Purgeable space can make "available" exceed what is not used; never below 0 %.
    #expect(DiskSpace(total: 100, available: 120).usedPercent == 0)
}

@Test func freeSpaceTextShortensToFit() {
    let space = DiskSpace(total: 994_660_000_000, available: 59_070_000_000, isReadOnly: true)
    let bytes: (Int64) -> String = { "\($0 / 1_000_000_000) GB" }
    let variants = FreeSpaceText.variants(space, bytes: bytes)
    #expect(variants == ["59 GB free of 994 GB", "59 GB free"])
    let width: (String) -> Double = { Double($0.count) }
    #expect(FreeSpaceText.fitting(variants, available: 100, width: width) == "59 GB free of 994 GB")
    #expect(FreeSpaceText.fitting(variants, available: 12, width: width) == "59 GB free")
    #expect(FreeSpaceText.fitting(variants, available: 5, width: width) == nil)
    #expect(FreeSpaceText.toolTip(space, bytes: bytes, locale: Locale(identifier: "en_US"))
            == "59 GB free of 994 GB — 94% used — read-only")
}

@Test func driveRowCommandsAndPreferences() {
    #expect(CommandRegistry.all.contains { $0.command == .toggleDriveRow && $0.menu == .view })
    #expect(CommandRegistry.all.contains { $0.command == .toggleVolumeBar && $0.menu == .view })
    let keys = Set(SettingsCatalog.app.preferences.map(\.key))
    #expect(keys.isSuperset(of: ["driveRow.show", "volumeBar.show", "driveRow.freeSpaceElsewhere"]))
}
