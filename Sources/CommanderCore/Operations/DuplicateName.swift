// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Finder-style names for Duplicate (spec 033): "report copy.pdf", "report copy 2.pdf", …; the word is
/// the app's localized "copy".
public enum DuplicateName {
    /// The first free name for a copy of `original`. A folder, a name without an extension and a name
    /// starting with a dot get the word at the end. The result fits 255 bytes of UTF-8: the base is
    /// shortened, never the word, the number or the extension.
    public static func name(for original: String, isDirectory: Bool, word: String,
                            isTaken: (String) -> Bool) -> String {
        var base = original
        var ext = ""
        if !isDirectory, let dot = original.lastIndex(of: "."),
           dot != original.startIndex, original.index(after: dot) != original.endIndex {
            base = String(original[..<dot])
            ext = String(original[dot...])
        }
        var attempt = 1
        while true {
            let tail = " " + word + (attempt == 1 ? "" : " \(attempt)") + ext
            var head = base
            let room = PathRules.maxNameBytes - tail.utf8.count
            while head.utf8.count > room, !head.isEmpty { head.removeLast() }
            let candidate = head + tail
            if !isTaken(candidate) { return candidate }
            attempt += 1
        }
    }
}

/// The standard folders of the Go menu (spec 033).
public enum StandardFolder: CaseIterable, Sendable {
    case desktop, documents, downloads, applications

    /// The folder for the user whose home folder is `home`; Applications is the system folder.
    public func url(home: URL) -> URL {
        switch self {
        case .desktop: home.appending(path: "Desktop", directoryHint: .isDirectory)
        case .documents: home.appending(path: "Documents", directoryHint: .isDirectory)
        case .downloads: home.appending(path: "Downloads", directoryHint: .isDirectory)
        case .applications: URL(filePath: "/Applications", directoryHint: .isDirectory)
        }
    }
}
