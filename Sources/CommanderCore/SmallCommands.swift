// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// The name Copy As offers: "‹base› copy.‹ext›" for a file, "‹name› copy" for a folder, so
/// Return makes a copy at once (as Finder's Duplicate names it). `suffix` is the localized "copy".
public enum CopyAsName {
    public static func suggestion(for name: String, isFolder: Bool, suffix: String = "copy") -> String {
        guard !isFolder else { return "\(name) \(suffix)" }
        let (base, ext) = NameMask.split(name)
        return ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
    }
}

/// The name New Folder in Other Panel offers: a folder's own name, a file's name without its
/// extension.
public enum NewFolderName {
    public static func suggestion(for name: String, isFolder: Bool) -> String {
        isFolder ? name : NameMask.split(name).base
    }
}
