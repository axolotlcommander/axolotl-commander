// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// Which side of a conflict is newer / larger, for the marks in the replace question.
public struct ConflictMarks: Equatable, Sendable {
    public enum Side: Equatable, Sendable { case existing, new }

    /// The side with the later modification date; nil when equal or either is unknown.
    public let newer: Side?
    /// The side with the bigger size; nil when equal, unknown, or either side is a directory.
    public let larger: Side?

    public init(_ conflict: Conflict) {
        let new = conflict.source, old = conflict.destination
        if let a = new.modificationDate, let b = old.modificationDate, a != b {
            newer = a > b ? .new : .existing
        } else {
            newer = nil
        }
        if !new.isDirectory, !old.isDirectory, let a = new.size, let b = old.size, a != b {
            larger = a > b ? .new : .existing
        } else {
            larger = nil
        }
    }
}
