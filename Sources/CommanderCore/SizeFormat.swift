// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// What the Size column of the panels shows.
public enum SizeDisplay: String, Sendable, CaseIterable {
    /// The rounded size as Finder writes it ("4,1 MB").
    case finder
    /// Exact bytes with grouping ("4 100 000").
    case bytes
}

/// The base of rounded sizes.
public enum SizeUnits: String, Sendable, CaseIterable {
    /// 1 kB = 1000 bytes, as Finder counts.
    case decimal
    /// 1 kB = 1024 bytes, with the labels the system writes for it (no "KiB").
    case binary
}

/// How the app writes byte counts: the system's file-size text, as in Finder, or exact bytes.
public struct SizeFormat: Sendable, Equatable {
    public var display: SizeDisplay
    public var units: SizeUnits

    public init(display: SizeDisplay = .finder, units: SizeUnits = .decimal) {
        self.display = display
        self.units = units
    }

    /// The system's rounded text ("4,3 MB", "402 bajtů") in the given base.
    public static func rounded(_ bytes: Int64, units: SizeUnits, locale: Locale = .current) -> String {
        bytes.formatted(ByteCountFormatStyle(style: units == .binary ? .binary : .file, locale: locale))
    }

    /// Every byte, with grouping ("4 300 000").
    public static func exact(_ bytes: Int64, locale: Locale = .current) -> String {
        bytes.formatted(IntegerFormatStyle<Int64>(locale: locale).grouping(.automatic))
    }

    /// The Size column's texts from the longest to the shortest: a narrow column shows the first
    /// that fits, never a cut number.
    public func columnVariants(_ bytes: Int64, locale: Locale = .current) -> [String] {
        let rounded = Self.rounded(bytes, units: units, locale: locale)
        switch display {
        case .finder: return [rounded]
        case .bytes:
            let exact = Self.exact(bytes, locale: locale)
            return exact == rounded ? [exact] : [exact, rounded]
        }
    }

    /// Whether the rounded text already shows every byte ("402 bajtů"), so the exact count need not
    /// be repeated next to it.
    public func roundedIsExact(_ bytes: Int64, locale: Locale = .current) -> Bool {
        let digits = Self.rounded(bytes, units: units, locale: locale).filter(\.isNumber)
        return !digits.isEmpty && digits == String(bytes)
    }
}
