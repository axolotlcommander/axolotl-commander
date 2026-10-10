// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import CommanderCore
import Foundation
import Testing

@Suite struct CellTextTests {
    private let cs = Locale(identifier: "cs_CZ")
    private let utc = TimeZone(identifier: "UTC")!

    @Test func dateDropsTheTimeThenShortensTheYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = calendar.date(from: DateComponents(year: 2026, month: 12, day: 23, hour: 7, minute: 46))!
        let variants = CellText.date(date, locale: cs, timeZone: utc)
        #expect(variants.count == 4)
        #expect(variants[0].contains("7:46") && variants[0].contains("2026"))
        #expect(!variants[1].contains(":") && variants[1].contains("2026"))
        #expect(!variants[2].contains("2026") && variants[2].contains("26"))
        #expect(!variants[3].contains("26") && variants[3].contains("23") && variants[3].contains("12"))
    }

    @Test func fittingPicksTheLongestThatFits() {
        let variants = ["1 234 567", "1,2 MB"]
        #expect(CellText.fitting(variants) { $0.count <= 20 } == "1 234 567")
        #expect(CellText.fitting(variants) { $0.count <= 6 } == "1,2 MB")
        // Nothing fits: an ellipsis rather than a cut number.
        #expect(CellText.fitting(variants) { _ in false } == "…")
        #expect(CellText.fitting([]) { _ in true } == "")
    }
}
