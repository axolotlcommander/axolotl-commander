// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

@Suite struct SplitTextTests {
    @Test func shortLinesStayAsTheyAre() {
        for text in ["", "a", "one\ntwo\r\nthree\rfour", String(repeating: "x", count: 10)] {
            let split = SplitText(text, maxLine: 10)
            #expect(!split.isSplit)
            #expect(split.display == text)
            #expect(split.displayOffset(ofSource: 3) == 3)
        }
    }

    @Test func longLineIsCutAtTheLimit() {
        let split = SplitText(String(repeating: "x", count: 25) + "\n" + String(repeating: "y", count: 12), maxLine: 10)
        #expect(split.breaks == [10, 20, 36])
        #expect(split.display == "xxxxxxxxxx\nxxxxxxxxxx\nxxxxx\nyyyyyyyyyy\nyy")
        #expect(split.display.components(separatedBy: "\n").allSatisfy { $0.count <= 10 })
    }

    @Test func cutPrefersCommaSemicolonOrSpace() {
        let split = SplitText("aaaa,bbbbbbbbbbbb", maxLine: 8)
        #expect(split.display.hasPrefix("aaaa,\n"))
        let spaced = SplitText("one two three four", maxLine: 10)
        #expect(spaced.display == "one two \nthree four")
        let semicolon = SplitText("a;bcdefghijk", maxLine: 5)
        #expect(semicolon.display.hasPrefix("a;\n"))
    }

    @Test func farSeparatorIsNotUsed() {
        // The comma is further back than the look-back window.
        let text = "," + String(repeating: "x", count: SplitText.lookBack + 20)
        let split = SplitText(text, maxLine: SplitText.lookBack + 10)
        #expect(split.breaks == [SplitText.lookBack + 10])
    }

    @Test func surrogatePairsAreNotCut() {
        let text = String(repeating: "a", count: 9) + "😀" + "bbbb"
        let split = SplitText(text, maxLine: 10)
        #expect(split.breaks == [9])
        #expect(split.display == String(repeating: "a", count: 9) + "\n😀bbbb")
    }

    @Test func offsetsMapBothWays() {
        let split = SplitText(String(repeating: "x", count: 25), maxLine: 10)
        // Display: 10 x, \n at 10, 10 x, \n at 21, 5 x.
        #expect(split.displayOffset(ofSource: 0) == 0)
        #expect(split.displayOffset(ofSource: 9) == 9)
        #expect(split.displayOffset(ofSource: 10) == 11)
        #expect(split.displayOffset(ofSource: 25) == 27)
        #expect(split.sourceOffset(ofDisplay: 10) == 10)
        #expect(split.sourceOffset(ofDisplay: 11) == 10)
        #expect(split.sourceOffset(ofDisplay: 22) == 20)
        #expect(split.sourceOffset(ofDisplay: 27) == 25)
        #expect(split.displayRange(ofSource: NSRange(location: 8, length: 4)) == NSRange(location: 8, length: 5))
    }

    @Test func copiedTextLeavesTheBreaksOut() {
        let text = "0123456789abcdefghij0123"
        let split = SplitText(text, maxLine: 10)
        #expect(split.sourceText(ofDisplay: NSRange(location: 0, length: (split.display as NSString).length)) == text)
        #expect(split.sourceText(ofDisplay: NSRange(location: 8, length: 5)) == "89ab")
        #expect(split.sourceText(ofDisplay: NSRange(location: 10, length: 1)) == "")
    }

    @Test func largeMinifiedLineIsFast() {
        let text = String(repeating: #"{"id":1,"name":"x"},"#, count: 500_000)
        let start = Date()
        let split = SplitText(text)
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(split.display.components(separatedBy: "\n").allSatisfy { $0.utf16.count <= SplitText.maxLineLength })
        #expect(split.display.replacingOccurrences(of: "\n", with: "") == text)
    }
}
