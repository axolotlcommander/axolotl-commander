// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// A chosen font: the PostScript name (family and face together) and the size in points.
/// `name == nil` means the system font.
public struct FontChoice: Codable, Hashable, Sendable {
    public var name: String?
    public var size: Double

    public init(name: String? = nil, size: Double) {
        self.name = name
        self.size = size
    }
}

/// Where a font is used, with its default size and limits.
public enum FontRole: Sendable, CaseIterable {
    /// The file lists of the panels with their column headers and status lines, and the folder menus.
    case fileList
    /// The rest of the main window: volume bar, drive row, path bar, tabs, command line, function keys.
    case mainWindow

    public var defaultSize: Double {
        switch self {
        case .fileList: 13
        case .mainWindow: 11
        }
    }

    public var limits: ClosedRange<Double> {
        switch self {
        case .fileList: 8...32
        case .mainWindow: 8...20
        }
    }

    /// Today's row height of the file list with the default font; rows never get lower.
    public static let minimumRowHeight: Double = 18

    public func clamped(_ size: Double) -> Double {
        min(max(size, limits.lowerBound), limits.upperBound)
    }

    /// The choice with its size kept within the limits; nil and the plain default stay nil.
    public func normalized(_ choice: FontChoice?) -> FontChoice? {
        guard var choice else { return nil }
        choice.size = clamped(choice.size)
        return isDefault(choice) ? nil : choice
    }

    /// The system font at the default size counts as the default.
    public func isDefault(_ choice: FontChoice?) -> Bool {
        guard let choice else { return true }
        return choice.name == nil && choice.size == defaultSize
    }

    public func size(of choice: FontChoice?) -> Double {
        clamped(choice?.size ?? defaultSize)
    }

    /// One point bigger, keeping the family and face; nil at the upper limit.
    public func bigger(_ choice: FontChoice?) -> FontChoice? {
        step(choice, by: 1)
    }

    /// One point smaller, keeping the family and face; nil at the lower limit.
    public func smaller(_ choice: FontChoice?) -> FontChoice? {
        step(choice, by: -1)
    }

    private func step(_ choice: FontChoice?, by delta: Double) -> FontChoice? {
        let current = size(of: choice)
        let next = clamped((current + delta).rounded())
        guard next != current else { return nil }
        return FontChoice(name: choice?.name, size: next)
    }

    /// The row height for a font's line height: the same padding as the default font has, never below
    /// `minimumRowHeight`.
    public static func rowHeight(lineHeight: Double, padding: Double) -> Double {
        max(minimumRowHeight, (lineHeight + padding).rounded(.up))
    }
}
