// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Rename by clicking the name (`specs/035-click-rename`): a slow second click on the name of the cursor item
/// starts in-place renaming, as in Finder.
public enum ClickRename {
    /// What a left press in a panel's list saw.
    public struct Press: Equatable, Sendable {
        /// Settings → Panels → "Rename by clicking the name of the item under the cursor".
        public var enabled = true
        public var clickCount = 1
        /// ⇧, ⌘, ⌃ or ⌥ was held.
        public var hasModifiers = false
        /// The panel was the active panel before the press (the click that activates a panel only activates it).
        public var panelWasActive = true
        /// The pressed item was the cursor item before the press.
        public var wasCursor = true
        /// The press was on the name text (not the icon or the empty part of the row or cell).
        public var onText = true
        public var isParent = false
        /// The Rename command is available there.
        public var renameAvailable = true

        public init() {}
    }

    /// Whether the release of `press` (without a drag) starts the wait for in-place renaming.
    public static func arms(_ press: Press) -> Bool {
        press.enabled && press.clickCount == 1 && !press.hasModifiers && press.panelWasActive && press.wasCursor
            && press.onText && !press.isParent && press.renameAvailable
    }

    /// The wait after an arming click; any other click, key or scroll drops it before it ends.
    public struct Pending: Equatable, Sendable {
        public let index: Int
        public let item: URL
        public let scrollOrigin: CGPoint

        public init(index: Int, item: URL, scrollOrigin: CGPoint) {
            self.index = index
            self.item = item
            self.scrollOrigin = scrollOrigin
        }

        /// Whether editing starts when the wait ends: the cursor and the item are the same, the list did not
        /// scroll, the panel is still active and nothing is being edited.
        public func fires(cursor: Int, item: URL?, scrollOrigin: CGPoint, panelActive: Bool, editing: Bool) -> Bool {
            cursor == index && item == self.item && scrollOrigin == self.scrollOrigin && panelActive && !editing
        }
    }

    /// The part of `name` selected when editing starts: the base name, so typing keeps the extension (as
    /// Finder does); a folder's whole name. A leading dot does not start an extension.
    public static func selection(of name: String, isFolder: Bool) -> NSRange {
        let whole = (name as NSString).length
        guard !isFolder, let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return NSRange(location: 0, length: whole)
        }
        return NSRange(location: 0, length: (String(name[..<dot]) as NSString).length)
    }
}
