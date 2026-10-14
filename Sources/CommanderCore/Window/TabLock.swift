// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// A tab's lock (spec 028): a locked tab opens every other folder in a new tab; a tab locked with folder
/// changes allowed can be browsed and shows its folder again whenever it becomes active.
public struct TabLock: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable {
        case locked
        case allowsChanges
    }

    public var mode: Mode
    /// The folder the tab showed when it was locked.
    public var folder: URL
    /// The item under the cursor at that moment.
    public var cursorName: String?

    public init(mode: Mode, folder: URL, cursorName: String? = nil) {
        self.mode = mode
        self.folder = folder
        self.cursorName = cursorName
    }

    /// The lock of a tab in `state` as it is now.
    public init(mode: Mode, state: PanelState) {
        self.init(mode: mode, folder: state.location, cursorName: state.cursorName)
    }

    /// What the tab shows when it comes back to its folder: the folder and the remembered item, without
    /// search results, branch view or marks; history stays.
    public func returning(_ state: PanelState) -> PanelState {
        var state = state
        state.location = folder
        state.cursorName = cursorName
        state.results = nil
        state.branch = nil
        state.selectedNames = []
        return state
    }
}
