// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The fonts of the file lists and the panel bars chosen in Settings → Appearance (spec 031), resolved
/// once per change. A font that is no longer installed falls back to the system font.
@MainActor
enum PanelFont {
    struct Faces: Equatable {
        let regular: NSFont
        let bold: NSFont
        let monospaced: NSFont
        let lineHeight: CGFloat
        /// Whether the choice is the system font (the bars then keep their usual weights).
        let isSystem: Bool
    }

    private static var cache: [FontRole: (choice: FontChoice?, set: Faces)] = [:]

    static func choice(_ role: FontRole) -> FontChoice? {
        let appearance = AppSettings.shared.appearance
        return role == .fileList ? appearance.listFont : appearance.barFont
    }

    static func faces(_ role: FontRole) -> Faces {
        let choice = choice(role)
        if let cached = cache[role], cached.choice == choice { return cached.set }
        let set = resolve(role, choice)
        cache[role] = (choice, set)
        return set
    }

    /// The font a choice names, nil when it is the system font or is not installed.
    static func installed(_ choice: FontChoice?, size: CGFloat) -> NSFont? {
        guard let name = choice?.name else { return nil }
        return NSFont(name: name, size: size)
    }

    private static func resolve(_ role: FontRole, _ choice: FontChoice?) -> Faces {
        let size = CGFloat(role.size(of: choice))
        let regular = installed(choice, size: size) ?? .systemFont(ofSize: size)
        let isSystem = installed(choice, size: size) == nil
        var bold = isSystem ? NSFont.boldSystemFont(ofSize: size)
            : NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask)
        // A font without a bold face: the regular one (the mark color still shows the mark).
        if !NSFontManager.shared.traits(of: bold).contains(.boldFontMask) { bold = regular }
        return Faces(regular: regular, bold: bold,
                   monospaced: .monospacedSystemFont(ofSize: size, weight: .regular),
                   lineHeight: lineHeight(of: regular), isSystem: isSystem)
    }

    static func lineHeight(of font: NSFont) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font)
    }

    // MARK: File list

    static var list: NSFont { faces(.fileList).regular }

    static func list(marked: Bool) -> NSFont {
        marked && AppSettings.shared.appearance.markBold ? faces(.fileList).bold : faces(.fileList).regular
    }

    /// The padding the default font has to today's 18 pt rows.
    private static let rowPadding: CGFloat =
        CGFloat(FontRole.minimumRowHeight) - lineHeight(of: .systemFont(ofSize: CGFloat(FontRole.fileList.defaultSize)))

    /// Row height of the detailed and brief lists: 18 pt with the default font, taller with a larger one.
    static var rowHeight: CGFloat {
        CGFloat(FontRole.rowHeight(lineHeight: Double(faces(.fileList).lineHeight), padding: Double(rowPadding)))
    }

    /// How much larger the file list font is than the default (for widths measured at the default size).
    static var listScale: CGFloat {
        max(1, list.pointSize / CGFloat(FontRole.fileList.defaultSize))
    }

    // MARK: Bars

    static var bar: NSFont { faces(.bars).regular }

    /// The bar font emphasized: the system font in the given weight, a chosen font in its bold face.
    static func bar(weight: NSFont.Weight) -> NSFont {
        let set = faces(.bars)
        guard weight != .regular else { return set.regular }
        return set.isSystem ? .systemFont(ofSize: set.regular.pointSize, weight: weight) : set.bold
    }

    static var barMonospaced: NSFont { faces(.bars).monospaced }

    /// How much taller a bar gets than with the default font (never lower than today).
    static var barGrowth: CGFloat {
        let base = lineHeight(of: .systemFont(ofSize: CGFloat(FontRole.bars.defaultSize)))
        return max(0, (faces(.bars).lineHeight - base).rounded(.up))
    }

    /// The bordered bar buttons' size for the bar font, so the text stays inside the bezel.
    static var barControlSize: NSControl.ControlSize {
        switch bar.pointSize {
        case ..<11.5: .small
        case ..<14: .regular
        default: .large
        }
    }

    // MARK: Settings

    /// "System font, 13 pt" or "Menlo Regular, 12 pt" for the Settings row.
    static func description(_ role: FontRole) -> String {
        let choice = choice(role)
        let size = role.size(of: choice)
        let sizeText = size == size.rounded() ? String(Int(size)) : String(format: "%.1f", size)
        let name = installed(choice, size: CGFloat(size))?.displayName ?? String(localized: "System font")
        return String(localized: "\(name), \(sizeText) pt")
    }
}
