// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// What the top of a panel shows (spec 020): the volume bar, the drive row (a drive combo with the
/// free space of the panel's disk), and whether the free space moves elsewhere without the row.
public struct DriveRowSettings: Equatable, Sendable {
    public static let showRowKey = "driveRow.show"
    public static let showVolumeBarKey = "volumeBar.show"
    public static let freeSpaceElsewhereKey = "driveRow.freeSpaceElsewhere"

    public var showRow = true
    public var showVolumeBar = true
    public var freeSpaceElsewhere = true

    public init(showRow: Bool = true, showVolumeBar: Bool = true, freeSpaceElsewhere: Bool = true) {
        self.showRow = showRow
        self.showVolumeBar = showVolumeBar
        self.freeSpaceElsewhere = freeSpaceElsewhere
    }

    /// Reads the saved choices; `value` is a defaults lookup by key (a missing key keeps the default).
    public init(value: (String) -> Any?) {
        self.init()
        showRow = value(Self.showRowKey) as? Bool ?? showRow
        showVolumeBar = value(Self.showVolumeBarKey) as? Bool ?? showVolumeBar
        freeSpaceElsewhere = value(Self.freeSpaceElsewhereKey) as? Bool ?? freeSpaceElsewhere
    }

    /// Where the free space is shown; never in two places.
    public var freeSpacePlace: FreeSpacePlace {
        if showRow { return .driveRow }
        guard freeSpaceElsewhere else { return .hidden }
        return showVolumeBar ? .volumeBar : .statusLine
    }
}

public enum FreeSpacePlace: Equatable, Sendable {
    /// Next to the drive combo.
    case driveRow
    /// At the right end of the volume bar.
    case volumeBar
    /// At the right end of the panel's status line.
    case statusLine
    case hidden
}

/// Capacity of the disk holding a panel's location.
public struct DiskSpace: Equatable, Sendable {
    public var total: Int64
    public var available: Int64
    public var isReadOnly: Bool

    public init(total: Int64, available: Int64, isReadOnly: Bool = false) {
        self.total = total
        self.available = available
        self.isReadOnly = isReadOnly
    }

    /// Used share in whole percent (0…100).
    public var usedPercent: Int {
        guard total > 0 else { return 0 }
        let used = Double(max(0, min(total, total - available))) / Double(total)
        return Int((used * 100).rounded())
    }
}

/// The free space as text: the longest variant that fits wins.
public enum FreeSpaceText {
    /// "59.07 GB free of 994.66 GB", then "59.07 GB free"; `bytes` writes a size in the chosen units.
    public static func variants(_ space: DiskSpace, bytes: (Int64) -> String) -> [String] {
        let free = bytes(space.available)
        return [String(localized: "\(free) free of \(bytes(space.total))"), String(localized: "\(free) free")]
    }

    public static func toolTip(_ space: DiskSpace, bytes: (Int64) -> String, locale: Locale = .current) -> String {
        let used = (Double(space.usedPercent) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
        var text = String(localized: "\(bytes(space.available)) free of \(bytes(space.total)) — \(used) used")
        if space.isReadOnly { text += " — " + String(localized: "read-only") }
        return text
    }

    /// The first of `variants` whose `width` fits into `available`; nil when none fits.
    public static func fitting(_ variants: [String], available: Double, width: (String) -> Double) -> String? {
        variants.first { width($0) <= available }
    }
}
