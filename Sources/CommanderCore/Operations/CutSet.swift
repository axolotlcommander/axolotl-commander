// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Items put on the clipboard by Cut Files (spec 033). The cut lasts while the pasteboard still holds what
/// Cut wrote, i.e. while its change count is the one recorded after writing.
public struct CutSet: Equatable, Sendable {
    /// The cut items by their standardized path.
    public let paths: Set<String>
    public let changeCount: Int

    public init(urls: [URL], changeCount: Int) {
        paths = Set(urls.map(Self.key))
        self.changeCount = changeCount
    }

    /// What Paste Files does with the pasteboard's file list.
    public enum PasteAction: Equatable, Sendable {
        case copy
        case move
        /// Every cut item already sits in the destination folder: nothing to do (beep).
        case sameFolder
    }

    public func isActive(changeCount current: Int) -> Bool {
        current == changeCount && !paths.isEmpty
    }

    public func contains(_ url: URL, changeCount current: Int) -> Bool {
        isActive(changeCount: current) && paths.contains(Self.key(url))
    }

    /// Move only what this cut put on the pasteboard and only while it is still there; anything else is
    /// pasted as copied files, so a paste never moves files the user did not cut in this app.
    public func pasteAction(for pasted: [URL], destination: URL, changeCount current: Int) -> PasteAction {
        guard isActive(changeCount: current), !pasted.isEmpty,
              pasted.allSatisfy({ paths.contains(Self.key($0)) }) else { return .copy }
        let folder = Self.key(destination)
        if pasted.allSatisfy({ (Self.key($0) as NSString).deletingLastPathComponent == folder }) { return .sameFolder }
        return .move
    }

    /// After a move: the items still at their place stay cut (a failed or cancelled part of the move).
    public func remaining(exists: (URL) -> Bool) -> [URL] {
        paths.sorted().map { URL(filePath: $0) }.filter(exists)
    }

    /// File URLs compare by their standardized path, with or without a trailing slash.
    static func key(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
