// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import AppKit
import CommanderCore
import Observation

extension Notification.Name {
    /// Panel colors or highlighting changed; panels redraw.
    static let appearanceChanged = Notification.Name("cz.acidek.icommander.appearanceChanged")
}

/// App-wide settings shared by both panels and the Settings window. Each value is stored in
/// UserDefaults as JSON and saved when it changes.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var appearance: PanelAppearance {
        didSet {
            save(appearance, "appearance")
            NotificationCenter.default.post(name: .appearanceChanged, object: nil)
        }
    }
    var hotPaths: HotPaths { didSet { save(hotPaths, "hotPaths") } }
    var comparison: ComparisonOptions { didSet { save(comparison, "comparison") } }
    var recentPaths: RecentPaths { didSet { save(recentPaths, "recentPaths") } }
    /// Saved server connections (without passwords; those are in the keychain).
    var connections: [ConnectionProfile] { didSet { save(connections, "connections") } }

    private init() {
        appearance = Self.load("appearance") ?? PanelAppearance()
        hotPaths = Self.load("hotPaths") ?? HotPaths()
        comparison = Self.load("comparison") ?? ComparisonOptions()
        recentPaths = Self.load("recentPaths") ?? RecentPaths()
        connections = Self.load("connections") ?? []
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save(_ value: some Encodable, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension SystemColor {
    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .cyan: .systemCyan
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .brown: .systemBrown
        case .gray: .systemGray
        }
    }

    var title: String {
        switch self {
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .mint: String(localized: "Mint")
        case .teal: String(localized: "Teal")
        case .cyan: String(localized: "Cyan")
        case .blue: String(localized: "Blue")
        case .indigo: String(localized: "Indigo")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .brown: String(localized: "Brown")
        case .gray: String(localized: "Gray")
        }
    }
}
