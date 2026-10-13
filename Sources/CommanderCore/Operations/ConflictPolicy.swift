// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// One per copy/move operation, in front of the replace question.
public struct ConflictPolicy: Sendable {
    public enum Mode: Equatable, Sendable { case ask, overwriteAllOlder, renameAllAutomatically }
    public enum Choice: Equatable, Sendable {
        case overwrite, overwriteAll, skip, skipAll, cancel
        case overwriteAllOlder, rename(String), renameAutomatically, renameAllAutomatically
    }
    public enum Decision: Equatable, Sendable { case answer(ConflictResolution), ask }

    /// An automatic name handed to the backend that may turn out to be taken as well.
    private struct Pending: Sendable {
        var source: URL
        var candidate: String
        var attempt: Int
        var original: String
    }

    public private(set) var mode: Mode = .ask
    private var pending: Pending?

    public init() {}

    /// Called for every conflict before the question is shown.
    public mutating func decide(_ conflict: Conflict) -> Decision {
        if let p = pending {
            pending = nil
            if p.source == conflict.source.url, p.candidate == conflict.destination.name {
                return .answer(rename(conflict, original: p.original, attempt: p.attempt + 1))
            }
        }
        switch mode {
        case .ask:
            return .ask
        case .overwriteAllOlder:
            return .answer(olderResolution(conflict))
        case .renameAllAutomatically:
            guard conflict.canRename else { return .ask }
            return .answer(rename(conflict, original: conflict.destination.name, attempt: 2))
        }
    }

    /// The user's choice in the question for this conflict.
    public mutating func choose(_ choice: Choice, for conflict: Conflict) -> ConflictResolution {
        pending = nil
        switch choice {
        case .overwrite: return .overwrite
        case .overwriteAll: return .overwriteAll
        case .skip: return .skip
        case .skipAll: return .skipAll
        case .cancel: return .cancel
        case .rename(let name): return .rename(name)
        case .renameAutomatically:
            return rename(conflict, original: conflict.destination.name, attempt: 2)
        case .renameAllAutomatically:
            mode = .renameAllAutomatically
            return rename(conflict, original: conflict.destination.name, attempt: 2)
        case .overwriteAllOlder:
            mode = .overwriteAllOlder
            return olderResolution(conflict)
        }
    }

    private func olderResolution(_ conflict: Conflict) -> ConflictResolution {
        let s = conflict.source, d = conflict.destination
        if !s.isDirectory, !d.isDirectory, let a = s.modificationDate, let b = d.modificationDate, a > b {
            return .overwrite
        }
        return .skip
    }

    private mutating func rename(_ conflict: Conflict, original: String, attempt: Int) -> ConflictResolution {
        let candidate = AutoName.name(for: original, isDirectory: conflict.source.isDirectory, attempt: attempt)
        pending = Pending(source: conflict.source.url, candidate: candidate, attempt: attempt, original: original)
        return .rename(candidate)
    }
}
