// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// The `fn` notice is shown at most twice, never after "Don't Show Again", never with standard
/// function keys (FR-024, SC-006).
@Suite struct FunctionKeyNoticeTests {
    @Test func neverWithStandardFunctionKeys() {
        #expect(!FunctionKeyNotice().shouldShow(standardFunctionKeys: true))
    }

    @Test func atMostTwice() {
        var notice = FunctionKeyNotice()
        var shown = 0
        for _ in 0..<5 where notice.shouldShow(standardFunctionKeys: false) {
            notice.recordShown()
            shown += 1
        }
        #expect(shown == FunctionKeyNotice.maxShowings)
        #expect(!notice.shouldShow(standardFunctionKeys: false))
    }

    @Test func neverAfterSuppress() {
        var notice = FunctionKeyNotice()
        notice.recordShown()
        notice.suppress()
        #expect(!notice.shouldShow(standardFunctionKeys: false))
    }

    @Test func roundTripAndDefaults() throws {
        var notice = FunctionKeyNotice()
        notice.recordShown()
        notice.suppress()
        let data = try JSONEncoder().encode(notice)
        #expect(try JSONDecoder().decode(FunctionKeyNotice.self, from: data) == notice)
        #expect(try JSONDecoder().decode(FunctionKeyNotice.self, from: Data("{}".utf8)) == FunctionKeyNotice())
    }
}
