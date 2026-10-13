// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// Default actions, possible actions and what an action does.
public enum SyncRules {
    public static func defaultAction(state: SyncState, left: SyncSide?, right: SyncSide?,
                                     options: SyncOptions) -> SyncAction {
        switch options.direction {
        case .bothWays:
            switch state {
            case .onlyLeft, .leftNewer: return .toRight
            case .onlyRight, .rightNewer: return .toLeft
            case .equal, .different, .error: return .none
            }
        case .leftToRight:
            switch state {
            case .onlyLeft, .leftNewer: return .toRight
            case .onlyRight: return options.deletionSide == .right ? .toRight : .none
            case .rightNewer, .equal, .different, .error: return .none
            }
        case .rightToLeft:
            switch state {
            case .onlyRight, .rightNewer: return .toLeft
            case .onlyLeft: return options.deletionSide == .left ? .toLeft : .none
            case .leftNewer, .equal, .different, .error: return .none
            }
        }
    }

    /// The actions an item can take; always includes `.none`.
    public static func possible(_ item: SyncItem, options: SyncOptions) -> [SyncAction] {
        if item.isError { return [.none] }
        var result: [SyncAction] = [.none]
        if item.left != nil || options.deletionSide == .right { result.append(.toRight) }
        if item.right != nil || options.deletionSide == .left { result.append(.toLeft) }
        return result
    }

    /// Sets the action where possible; returns the indices it could not change.
    @discardableResult
    public static func set(_ action: SyncAction, at indices: some Sequence<Int>, in items: inout [SyncItem],
                           options: SyncOptions) -> [Int] {
        var refused: [Int] = []
        for i in indices where items.indices.contains(i) {
            if possible(items[i], options: options).contains(action) {
                items[i].action = action
            } else {
                refused.append(i)
            }
        }
        return refused
    }

    /// Excludes all the items when any of them is included, else includes them all; actions stay.
    public static func toggleExcluded(at indices: some Sequence<Int>, in items: inout [SyncItem]) {
        let chosen = indices.filter { items.indices.contains($0) }
        let exclude = chosen.contains { !items[$0].excluded }
        for i in chosen { items[i].excluded = exclude }
    }

    /// What the item's action does, and on which side.
    public static func effect(of item: SyncItem) -> (effect: SyncEffect, target: Side?) {
        guard !item.excluded, !item.isError else { return (.nothing, nil) }
        let source: Side
        switch item.action {
        case .none: return (.nothing, nil)
        case .toRight: source = .left
        case .toLeft: source = .right
        }
        let target = source.other
        switch (item.side(source), item.side(target)) {
        case (nil, nil): return (.nothing, nil)
        case (nil, .some): return (.delete, target)
        case (.some, nil): return (.copy, target)
        case let (s?, t?):
            if !s.sameKind(as: t) { return (.replace, target) }
            // Two folders have nothing to copy themselves; their contents are rows of their own.
            if s.isFolder { return (.nothing, nil) }
            return (.overwrite, target)
        }
    }
}
