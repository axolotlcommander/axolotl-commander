// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// The "To:" text of the F5/F6 dialog for one item: folder plus name.
public enum TransferTarget {
    public enum Part: Equatable, Sendable { case name, `extension`, folder, all }

    /// Joins folder and name ("/" + "x" → "/x"; "/a/" + "x" → "/a/x"; "" + "x" → "x").
    public static func text(folder: String, name: String) -> String {
        if folder.isEmpty { return name }
        return folder.hasSuffix("/") ? folder + name : folder + "/" + name
    }

    /// Where the item goes. A trailing "/" or a text naming an existing folder → that folder
    /// (without the trailing slash, except "/") and `sourceName`. Otherwise the last component
    /// is the new name and the rest the folder ("" without "/"; "/" for "/x").
    public static func resolve(_ text: String, sourceName: String,
                               isFolder: (String) -> Bool) -> (folder: String, name: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return ("", sourceName) }
        if t.hasSuffix("/") { return (PathText.trimmingTrailingSlashes(t), sourceName) }
        if isFolder(t) { return (t, sourceName) }
        guard let slash = t.lastIndex(of: "/") else { return ("", t) }
        let name = String(t[t.index(after: slash)...])
        let folder = String(t[..<slash])
        return (folder.isEmpty ? "/" : folder, name)
    }

    /// UTF-16 range of a part; nil when the part is empty. With `isDirectory` the name has no extension.
    public static func range(of part: Part, in text: String, isDirectory: Bool) -> NSRange? {
        let u = Array(text.utf16)
        let slash = u.lastIndex(of: 0x2F)
        let start = slash.map { $0 + 1 } ?? 0
        let range: NSRange
        switch part {
        case .all:
            range = NSRange(location: 0, length: u.count)
        case .folder:
            guard let slash else { return nil }
            range = NSRange(location: 0, length: slash == 0 ? 1 : slash)
        case .name, .extension:
            var dot: Int?
            if !isDirectory, let d = u.lastIndex(of: 0x2E), d > start, d < u.count - 1 { dot = d }
            if part == .name {
                range = NSRange(location: start, length: (dot ?? u.count) - start)
            } else {
                guard let dot else { return nil }
                range = NSRange(location: dot + 1, length: u.count - dot - 1)
            }
        }
        return range.length > 0 ? range : nil
    }

    /// The cycle name → extension → folder → all → name, skipping parts without a range.
    public static func next(after part: Part, in text: String, isDirectory: Bool) -> Part {
        let cycle: [Part] = [.name, .extension, .folder, .all]
        let from = cycle.firstIndex(of: part) ?? 0
        for step in 1...cycle.count {
            let candidate = cycle[(from + step) % cycle.count]
            if range(of: candidate, in: text, isDirectory: isDirectory) != nil { return candidate }
        }
        return part
    }
}
