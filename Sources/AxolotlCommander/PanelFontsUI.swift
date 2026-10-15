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

    private static var cache: [FontRole: (stored: FontChoice?, effective: FontChoice?, faces: Faces)] = [:]

    /// The choice in effect: the stored one, or nil (the default) when its font is not installed.
    static func choice(_ role: FontRole) -> FontChoice? {
        entry(role).effective
    }

    static func faces(_ role: FontRole) -> Faces {
        entry(role).faces
    }

    private static func entry(_ role: FontRole) -> (stored: FontChoice?, effective: FontChoice?, faces: Faces) {
        let appearance = AppSettings.shared.appearance
        let stored = role == .fileList ? appearance.listFont : appearance.barFont
        if let cached = cache[role], cached.stored == stored { return cached }
        let size = CGFloat(role.size(of: stored))
        let named = stored?.name.flatMap { NSFont(name: $0, size: size) }
        // A font removed after it was chosen: the row's default, without a message.
        let effective = stored?.name != nil && named == nil ? nil : stored
        let entry = (stored, effective, resolve(role, named, size: CGFloat(role.size(of: effective))))
        cache[role] = entry
        return entry
    }

    private static func resolve(_ role: FontRole, _ named: NSFont?, size: CGFloat) -> Faces {
        let regular = named ?? .systemFont(ofSize: size)
        var bold = named == nil ? NSFont.boldSystemFont(ofSize: size)
            : NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask)
        // A font without a bold face: the regular one (the mark color still shows the mark).
        if !NSFontManager.shared.traits(of: bold).contains(.boldFontMask) { bold = regular }
        return Faces(regular: regular, bold: bold,
                     monospaced: .monospacedSystemFont(ofSize: size, weight: .regular),
                     lineHeight: lineHeight(of: regular), isSystem: named == nil)
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
        let faces = faces(role)
        let size = Double(faces.regular.pointSize)
        let sizeText = size == size.rounded() ? String(Int(size)) : String(format: "%.1f", size)
        let name = faces.isSystem ? String(localized: "System font") : faces.regular.displayName ?? faces.regular.fontName
        return String(localized: "\(name), \(sizeText) pt")
    }
}

extension PanelFont {
    /// Stores a choice for a role (normalized: within the limits, the default stored as nil).
    static func store(_ choice: FontChoice?, for role: FontRole) {
        let choice = role.normalized(choice)
        let settings = AppSettings.shared
        switch role {
        case .fileList: if settings.appearance.listFont != choice { settings.appearance.listFont = choice }
        case .bars: if settings.appearance.barFont != choice { settings.appearance.barFont = choice }
        }
    }

    /// The choice that names `font`; the system font is stored without its private name.
    static func choice(for font: NSFont, role: FontRole) -> FontChoice? {
        let size = role.clamped(Double(font.pointSize))
        let isSystem = font.fontName.hasPrefix(".") || font.familyName == NSFont.systemFont(ofSize: 13).familyName
        return role.normalized(FontChoice(name: isSystem ? nil : font.fontName, size: size))
    }
}

/// Connects the standard Fonts panel to one font role in Settings: every change in the panel applies at once.
/// Closing Settings or restoring a default lets the Fonts panel go back to the text it normally changes.
@MainActor
final class FontChooser: NSObject, NSFontChanging {
    static let shared = FontChooser()
    private(set) var role: FontRole?

    func choose(_ role: FontRole) {
        self.role = role
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(PanelFont.faces(role).regular, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    func stop() {
        role = nil
        if NSFontManager.shared.target === self { NSFontManager.shared.target = nil }
    }

    func changeFont(_ sender: NSFontManager?) {
        guard let role else { return }
        let manager = sender ?? NSFontManager.shared
        let font = manager.convert(PanelFont.faces(role).regular)
        PanelFont.store(PanelFont.choice(for: font, role: role), for: role)
    }

    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }
}
