// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation

public enum PanelViewMode: String, Codable, Sendable, CaseIterable { case detailed, brief }

public enum Side: String, Codable, Sendable { case left, right }

/// Saved arrangement of the window (the UI stores it as JSON in UserDefaults).
public struct WindowLayout: Codable, Hashable, Sendable {
    public var left: TabList
    public var right: TabList
    public var leftMode: PanelViewMode
    public var rightMode: PanelViewMode
    public var activeSide: Side
    /// nil shows both panels.
    public var maximized: Side?
    /// Share of the width given to the left panel, within 0.1...0.9.
    public var splitFraction: Double {
        didSet { splitFraction = Self.clamp(splitFraction) }
    }

    public init(
        left: TabList,
        right: TabList,
        leftMode: PanelViewMode = .detailed,
        rightMode: PanelViewMode = .detailed,
        activeSide: Side = .left,
        maximized: Side? = nil,
        splitFraction: Double = 0.5
    ) {
        self.left = left
        self.right = right
        self.leftMode = leftMode
        self.rightMode = rightMode
        self.activeSide = activeSide
        self.maximized = maximized
        self.splitFraction = Self.clamp(splitFraction)
    }

    /// Missing keys fall back to defaults (panels start in the home directory); `splitFraction` is clamped.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let home = TabList(PanelState(location: FileManager.default.homeDirectoryForCurrentUser))
        self.init(
            left: try c.decodeIfPresent(TabList.self, forKey: .left) ?? home,
            right: try c.decodeIfPresent(TabList.self, forKey: .right) ?? home,
            leftMode: try c.decodeIfPresent(PanelViewMode.self, forKey: .leftMode) ?? .detailed,
            rightMode: try c.decodeIfPresent(PanelViewMode.self, forKey: .rightMode) ?? .detailed,
            activeSide: try c.decodeIfPresent(Side.self, forKey: .activeSide) ?? .left,
            maximized: try c.decodeIfPresent(Side.self, forKey: .maximized),
            splitFraction: try c.decodeIfPresent(Double.self, forKey: .splitFraction) ?? 0.5
        )
    }

    private static func clamp(_ value: Double) -> Double {
        value.isNaN ? 0.5 : min(0.9, max(0.1, value))
    }

    /// nil when `data` is not a valid layout.
    public static func decode(_ data: Data) -> WindowLayout? {
        try? JSONDecoder().decode(WindowLayout.self, from: data)
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
