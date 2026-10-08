// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// The notice that function keys need `fn` on this Mac. It is shown at most twice in total and
/// never again after "Don't Show Again"; with standard function keys it is never shown.
public struct FunctionKeyNotice: Codable, Equatable, Sendable {
    public static let maxShowings = 2

    public var timesShown: Int
    public var suppressed: Bool

    public init(timesShown: Int = 0, suppressed: Bool = false) {
        self.timesShown = timesShown
        self.suppressed = suppressed
    }

    public func shouldShow(standardFunctionKeys: Bool) -> Bool {
        !standardFunctionKeys && !suppressed && timesShown < Self.maxShowings
    }

    public mutating func recordShown() { timesShown += 1 }

    public mutating func suppress() { suppressed = true }

    // Missing fields (older or hand-edited values) fall back to the defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timesShown = try container.decodeIfPresent(Int.self, forKey: .timesShown) ?? 0
        suppressed = try container.decodeIfPresent(Bool.self, forKey: .suppressed) ?? false
    }
}
