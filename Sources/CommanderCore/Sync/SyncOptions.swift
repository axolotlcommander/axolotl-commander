// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Which way Synchronize Folders copies.
public enum SyncDirection: String, Codable, Sendable, CaseIterable {
    case bothWays, leftToRight, rightToLeft
}

/// The options of Synchronize Folders (remembered as `syncOptions`).
public struct SyncOptions: Codable, Hashable, Sendable {
    public var includeSubfolders = true
    public var compareDate = true
    /// Dates exactly one hour apart (± the tolerance) count as equal (daylight saving on FAT).
    public var ignoreHourDifference = true
    public var compareSize = true
    /// Reads pairs of files that are equal by the other criteria and have the same size.
    public var compareContent = false
    /// Masks in the Compare Panels syntax; blank means none.
    public var ignoreFiles: String? = nil
    public var ignoreFolders: String? = nil
    public var direction: SyncDirection = .bothWays
    /// Items missing on the source side are deleted on the target side (one way only).
    public var deleteMissing = false

    /// Dates this close count as equal (FAT stores 2-second steps).
    public static let dateTolerance: TimeInterval = 2

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case includeSubfolders, compareDate, ignoreHourDifference, compareSize, compareContent
        case ignoreFiles, ignoreFolders, direction, deleteMissing
    }

    /// Missing or unreadable fields keep their defaults, so older and newer files both load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        includeSubfolders = value(.includeSubfolders, true)
        compareDate = value(.compareDate, true)
        ignoreHourDifference = value(.ignoreHourDifference, true)
        compareSize = value(.compareSize, true)
        compareContent = value(.compareContent, false)
        ignoreFiles = (try? c.decodeIfPresent(String.self, forKey: .ignoreFiles)) ?? nil
        ignoreFolders = (try? c.decodeIfPresent(String.self, forKey: .ignoreFolders)) ?? nil
        direction = value(.direction, SyncDirection.bothWays)
        deleteMissing = value(.deleteMissing, false)
    }

    /// The side whose extra items may be deleted, or nil (both ways, or deleting off).
    public var deletionSide: Side? {
        guard deleteMissing else { return nil }
        switch direction {
        case .bothWays: return nil
        case .leftToRight: return .right
        case .rightToLeft: return .left
        }
    }
}
