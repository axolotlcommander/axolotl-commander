// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin

/// Whether items can go to the Trash, and the plan of a delete that honors it.
public enum TrashSupport {
    /// True when the volume holding `url` has a Trash for this user. Asks the system for the
    /// Trash folder without creating one: disk images, Time Machine and similar volumes have
    /// none. A volume whose Trash was never created may also answer false — the safe side,
    /// because the user is then asked before anything is deleted permanently.
    public static func isAvailable(_ url: URL) -> Bool {
        (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)) != nil
    }

    /// Moves one item to the Trash; returns where it went.
    public static func moveToTrash(_ url: URL) throws -> URL {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return (trashed as URL?) ?? url
    }
}

/// F8 split before anything changes: what can go to the Trash and what could only be
/// deleted permanently (its volume has no Trash).
public struct DeletePlan: Sendable, Equatable {
    public var toTrash: [URL]
    /// On a volume without a Trash; deleted only after the user explicitly agrees.
    public var permanent: [URL]
    /// On a volume without a Trash and in a folder this user can't change: deleting would
    /// fail anyway, so the user is not asked about them, only told.
    public var unremovable: [URL]

    public init(toTrash: [URL], permanent: [URL], unremovable: [URL] = []) {
        self.toTrash = toTrash
        self.permanent = permanent
        self.unremovable = unremovable
    }
}

/// What a move to the Trash did. It stops at the first failure.
public struct TrashReport: Sendable {
    public var trashed: [(original: URL, inTrash: URL)]
    public var failed: (url: URL, error: any Error)?
    /// After the failure (or a cancellation): left where they were.
    public var notAttempted: [URL]

    public init(trashed: [(original: URL, inTrash: URL)] = [], failed: (url: URL, error: any Error)? = nil, notAttempted: [URL] = []) {
        self.trashed = trashed
        self.failed = failed
        self.notAttempted = notAttempted
    }

    /// Everything went to the Trash.
    public var isComplete: Bool { failed == nil && notAttempted.isEmpty }
}
