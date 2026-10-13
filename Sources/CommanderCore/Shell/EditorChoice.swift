// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// Which app F4 opens a file with, from the editor chosen in Settings.
public enum EditorChoice: Equatable, Sendable {
    /// The app the system opens this file type with.
    case systemDefault
    /// An installed app.
    case app(bundleID: String)
    /// The chosen app is not installed; F4 says so instead of opening another app.
    case missing(bundleID: String)

    public static let defaultBundleID = "com.apple.TextEdit"
    public static let systemDefaultTag = "system"

    public static func resolve(chosen: String?, isInstalled: (String) -> Bool) -> EditorChoice {
        let bundleID = chosen.flatMap { $0.isEmpty ? nil : $0 } ?? defaultBundleID
        if bundleID == systemDefaultTag { return .systemDefault }
        return isInstalled(bundleID) ? .app(bundleID: bundleID) : .missing(bundleID: bundleID)
    }
}
