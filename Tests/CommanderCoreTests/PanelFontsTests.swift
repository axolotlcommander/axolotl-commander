// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct PanelFontsTests {
    @Test func choiceRoundTripsInAppearance() throws {
        let a = PanelAppearance(listFont: FontChoice(name: "Menlo-Bold", size: 15),
                                windowFont: FontChoice(name: "Avenir-Book", size: 14))
        let b = try JSONDecoder().decode(PanelAppearance.self, from: JSONEncoder().encode(a))
        #expect(b == a)
        #expect(b.font(.mainWindow)?.name == "Avenir-Book")
        #expect(b.listFont?.name == "Menlo-Bold")
    }

    @Test func oldSettingsDecodeWithDefaultFonts() throws {
        let json = #"{"markColor":"red","markBold":false}"#
        let a = try JSONDecoder().decode(PanelAppearance.self, from: Data(json.utf8))
        #expect(a.listFont == nil)
        #expect(a.windowFont == nil)
        #expect(a.markBold == false)
    }

    @Test func sizesAreClamped() {
        #expect(FontRole.fileList.clamped(4) == 8)
        #expect(FontRole.fileList.clamped(40) == 32)
        #expect(FontRole.mainWindow.clamped(25) == 20)
        #expect(FontRole.mainWindow.clamped(12) == 12)
        #expect(FontRole.fileList.normalized(FontChoice(name: "Menlo-Regular", size: 64))?.size == 32)
        #expect(FontRole.mainWindow.size(of: FontChoice(size: 2)) == 8)
        #expect(FontRole.mainWindow.clamped(21) == 20)
    }

    @Test func rolesAreSetSeparately() {
        var a = PanelAppearance()
        a.setFont(FontChoice(size: 16), for: .mainWindow)
        #expect(a.font(.mainWindow) == FontChoice(size: 16))
        #expect(a.font(.fileList) == nil)
    }

    @Test func defaultIsDetected() {
        #expect(FontRole.fileList.isDefault(nil))
        #expect(FontRole.fileList.isDefault(FontChoice(size: 13)))
        #expect(!FontRole.fileList.isDefault(FontChoice(size: 14)))
        #expect(!FontRole.fileList.isDefault(FontChoice(name: "Menlo-Regular", size: 13)))
        #expect(FontRole.mainWindow.isDefault(FontChoice(size: 11)))
        #expect(FontRole.mainWindow.normalized(FontChoice(size: 11)) == nil)
    }

    @Test func stepsKeepTheFaceAndStopAtTheLimits() {
        #expect(FontRole.fileList.bigger(nil) == FontChoice(size: 14))
        #expect(FontRole.fileList.smaller(nil) == FontChoice(size: 12))
        let menlo = FontChoice(name: "Menlo-Italic", size: 31.5)
        #expect(FontRole.fileList.bigger(menlo) == FontChoice(name: "Menlo-Italic", size: 32))
        #expect(FontRole.fileList.bigger(FontChoice(name: "Menlo-Italic", size: 32)) == nil)
        #expect(FontRole.fileList.smaller(FontChoice(size: 8)) == nil)
    }

    @Test func rowHeightNeverBelowToday() {
        // The default font: 16 pt line + 2 pt padding = today's 18 pt.
        #expect(FontRole.rowHeight(lineHeight: 16, padding: 2) == 18)
        #expect(FontRole.rowHeight(lineHeight: 10, padding: 2) == 18)
        #expect(FontRole.rowHeight(lineHeight: 37.2, padding: 2) == 40)
    }
}
