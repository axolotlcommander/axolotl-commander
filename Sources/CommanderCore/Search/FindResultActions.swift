// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// What the Find window does after Go to File and Results to Panel (spec 032). The key is part of the
/// settings file and is never renamed.
public enum FindWindowBehavior: String, CaseIterable, Sendable {
    /// The window steps aside and Find Files brings it back with its results, as the classic commander's
    /// dialog closes and shows its last search again.
    case hide
    /// The window stays open behind the main window; Find Files opens a new one.
    case keepOpen

    public static let key = "find.afterGoToFile"
    public static let `default` = FindWindowBehavior.hide

    public init(defaults: UserDefaults) {
        self = defaults.string(forKey: Self.key).flatMap(Self.init(rawValue:)) ?? .default
    }
}

/// Where Go to File takes the panel for a found item: its folder with the cursor on it (a folder result
/// too: its parent, cursor on the folder). Results can be stale, so the item and its folder are checked.
public enum FindGoToTarget: Equatable, Sendable {
    case focus(folder: URL, name: String)
    /// The item is gone, its folder is not: the folder is shown and the app beeps.
    case folderOnly(URL)
    /// The folder is gone too: a message, the panel does not change.
    case gone(URL)

    public static func resolve(_ url: URL, exists: (URL) -> Bool) -> FindGoToTarget {
        let item = url.standardizedFileURL
        let folder = item.deletingLastPathComponent()
        if exists(item) { return .focus(folder: folder, name: item.lastPathComponent) }
        return exists(folder) ? .folderOnly(folder) : .gone(folder)
    }
}
