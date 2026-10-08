// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation

/// Semantic colors; the UI maps them to `NSColor.systemX`, which adapts to light and dark mode.
public enum SystemColor: String, Codable, Sendable, CaseIterable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray
}

/// A yes/no/don't-care condition on a file attribute.
public enum Tristate: String, Codable, Sendable, CaseIterable {
    case any, yes, no

    public func accepts(_ value: Bool) -> Bool {
        switch self {
        case .any: true
        case .yes: value
        case .no: !value
        }
    }
}

/// Colors names by mask and attributes. All conditions must hold.
public struct HighlightRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// `WildcardMask` pattern; blank matches everything.
    public var masks: String
    /// Directory in the sense of `isDirectory && !isPackage`.
    public var directory: Tristate
    public var hidden: Tristate
    public var symlink: Tristate
    public var color: SystemColor
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        masks: String,
        directory: Tristate = .any,
        hidden: Tristate = .any,
        symlink: Tristate = .any,
        color: SystemColor,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.masks = masks
        self.directory = directory
        self.hidden = hidden
        self.symlink = symlink
        self.color = color
        self.isEnabled = isEnabled
    }

    /// Missing keys fall back to defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            masks: try c.decodeIfPresent(String.self, forKey: .masks) ?? "",
            directory: try c.decodeIfPresent(Tristate.self, forKey: .directory) ?? .any,
            hidden: try c.decodeIfPresent(Tristate.self, forKey: .hidden) ?? .any,
            symlink: try c.decodeIfPresent(Tristate.self, forKey: .symlink) ?? .any,
            color: try c.decodeIfPresent(SystemColor.self, forKey: .color) ?? .gray,
            isEnabled: try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        )
    }

    /// Ignores `isEnabled` (see `PanelAppearance.color(for:rules:)`); never matches "..".
    public func matches(_ item: FileItem, rules: NameRules) -> Bool {
        guard !item.isParent else { return false }
        guard directory.accepts(item.isDirectory && !item.isPackage),
              hidden.accepts(item.isHidden),
              symlink.accepts(item.isSymlink) else { return false }
        if masks.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return WildcardMask(masks).matches(item.name, rules: rules)
    }
}

/// How a panel colors its rows.
public struct PanelAppearance: Codable, Hashable, Sendable {
    /// Color of selected items.
    public var markColor: SystemColor
    /// The first enabled matching rule from the top wins.
    public var highlights: [HighlightRule]

    public init(markColor: SystemColor = .red, highlights: [HighlightRule] = PanelAppearance.defaultHighlights) {
        self.markColor = markColor
        self.highlights = highlights
    }

    /// Missing keys fall back to defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            markColor: try c.decodeIfPresent(SystemColor.self, forKey: .markColor) ?? .red,
            highlights: try c.decodeIfPresent([HighlightRule].self, forKey: .highlights) ?? Self.defaultHighlights
        )
    }

    /// Archives purple, scripts green (files only). Fixed ids keep the list stable across launches.
    public static let defaultHighlights: [HighlightRule] = [
        HighlightRule(
            id: UUID(uuidString: "5E1A0C10-0000-4000-8000-000000000001")!,
            masks: "*.zip;*.tar;*.gz;*.tgz;*.bz2;*.xz;*.7z;*.rar;*.dmg;*.pkg",
            directory: .no, color: .purple),
        HighlightRule(
            id: UUID(uuidString: "5E1A0C10-0000-4000-8000-000000000002")!,
            masks: "*.sh;*.command;*.py;*.rb;*.pl",
            directory: .no, color: .green),
    ]

    public func color(for item: FileItem, rules: NameRules) -> SystemColor? {
        highlights.first { $0.isEnabled && $0.matches(item, rules: rules) }?.color
    }
}
