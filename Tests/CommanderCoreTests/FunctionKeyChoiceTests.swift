// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
@testable import CommanderCore

/// Which function key buttons are shown and where they stand (spec 017, SC-001, SC-002).
@Suite struct FunctionKeyChoiceTests {
    @Test func missingOrEmptyValueShowsAllTwelve() {
        #expect(FunctionKeyChoice(storage: nil).visible == Array(1...12))
        #expect(FunctionKeyChoice(storage: "").visible == Array(1...12))
        #expect(SettingsCatalog.app.preferences.first { $0.key == FunctionKeyChoice.key }?.defaultValue == .string(""))
    }

    @Test func storedTextRoundTrips() {
        let choice = FunctionKeyChoice(storage: "8, 5,6")
        #expect(choice.visible == [1, 2, 3, 4, 7, 9, 10, 11, 12])
        #expect(choice.storage == "5,6,8")
        #expect(FunctionKeyChoice(storage: choice.storage) == choice)
    }

    @Test func garbageAndOutOfRangeAreIgnored() {
        #expect(FunctionKeyChoice(storage: "x,0,13,-1,3").hidden == [3])
    }

    @Test func hidingEverythingShowsEverything() {
        let all = (1...12).map(String.init).joined(separator: ",")
        #expect(FunctionKeyChoice(storage: all).visible == Array(1...12))
    }

    @Test func theLastShownKeyCannotBeHidden() {
        var choice = FunctionKeyChoice(hidden: Set(1...12).subtracting([3]))
        #expect(choice.visible == [3])
        #expect(!choice.canHide(3))
        #expect(choice.canHide(4))
        choice.set(3, visible: false)
        #expect(choice.visible == [3])
        choice.set(4, visible: true)
        #expect(choice.visible == [3, 4])
        choice.set(3, visible: false)
        #expect(choice.visible == [4])
    }

    @Test func oneButtonStaysAtTheMaximumOnTheLeft() {
        let frames = FunctionKeyBarLayout.frames(count: 1, width: 2000, edge: 1, gap: 1)
        #expect(frames.count == 1)
        #expect(frames[0].x == 1)
        #expect(frames[0].width == FunctionKeyBarLayout.maxButtonWidth)
    }

    @Test func fewButtonsStandSideBySideFromTheLeft() {
        let frames = FunctionKeyBarLayout.frames(count: 3, width: 1200, edge: 1, gap: 1)
        #expect(frames.map(\.x) == [1, 142, 283])
        #expect(frames.allSatisfy { $0.width == 140 })
    }

    @Test func narrowBarIsSharedEvenlyToTheEdge() {
        let frames = FunctionKeyBarLayout.frames(count: 12, width: 1000, edge: 1, gap: 1)
        #expect(frames.dropLast().allSatisfy { $0.width == 82 })
        let last = frames[frames.count - 1]
        #expect(last.x + last.width == 999)
        #expect(frames.allSatisfy { $0.width <= FunctionKeyBarLayout.maxButtonWidth })
    }

    @Test func edgesStayFreeAtBothEnds() {
        let few = FunctionKeyBarLayout.frames(count: 2, width: 1000, edge: 5, gap: 1)
        #expect(few.map(\.x) == [5, 146])
        let all = FunctionKeyBarLayout.frames(count: 12, width: 1000, edge: 5, gap: 1)
        #expect(all[0].x == 5)
        #expect(all[11].x + all[11].width == 995)
    }

    @Test func shrinkingBelowTheMaximumSharesEvenly() {
        let wide = FunctionKeyBarLayout.frames(count: 3, width: 600, edge: 1, gap: 1)
        #expect(wide.allSatisfy { $0.width == 140 })
        let narrow = FunctionKeyBarLayout.frames(count: 3, width: 401, edge: 1, gap: 1)
        #expect(narrow.map(\.width) == [132, 132, 133])
        #expect(narrow[2].x + narrow[2].width == 400)
    }
}
