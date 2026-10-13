// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import CoreGraphics
import Foundation
import Testing
@testable import CommanderCore

/// Arrow keys between dialog buttons.
@Suite struct DialogButtonsTests {
    /// The replace question: five buttons in a column, the first at the top.
    private let column = (0..<5).map { CGRect(x: 16, y: 152 - 34 * $0, width: 228, height: 28) }
    /// A classic alert row: the first button is on the right.
    private let row = [CGRect(x: 300, y: 16, width: 80, height: 28), CGRect(x: 210, y: 16, width: 80, height: 28),
                       CGRect(x: 120, y: 16, width: 80, height: 28)]

    @Test func columnGoesTopToBottom() {
        #expect(DialogButtons.order(column) == [0, 1, 2, 3, 4])
        #expect(DialogButtons.next(frames: column, current: 0, step: 1) == 1)
        #expect(DialogButtons.next(frames: column, current: 3, step: -1) == 2)
    }

    @Test func rowGoesLeftToRight() {
        #expect(DialogButtons.order(row) == [2, 1, 0])
        // ← from the default (rightmost) button moves to the one on its left.
        #expect(DialogButtons.next(frames: row, current: 0, step: -1) == 1)
        #expect(DialogButtons.next(frames: row, current: 2, step: 1) == 1)
    }

    @Test func endsDoNotWrap() {
        #expect(DialogButtons.next(frames: column, current: 0, step: -1) == 0)
        #expect(DialogButtons.next(frames: column, current: 4, step: 1) == 4)
    }

    @Test func withoutDefaultTheFirstStepPicksAnEnd() {
        #expect(DialogButtons.next(frames: column, current: nil, step: 1) == 0)
        #expect(DialogButtons.next(frames: column, current: nil, step: -1) == 4)
        #expect(DialogButtons.next(frames: [], current: nil, step: 1) == nil)
    }
}
