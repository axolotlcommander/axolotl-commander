// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// The app was called iCommander (bundle id `cz.acidek.icommander`) before 2026-10. On the first
/// launch under the new id its settings are copied over once; the old domain stays untouched.
enum LegacySettings {
    private static let legacyDomain = "cz.acidek.icommander"
    private static let currentDomain = "cz.acidek.axolotlcommander"
    private static let doneKey = "migratedFromICommander"

    static func migrateIfNeeded() {
        // Only the real app: a test copy with its own bundle id must not pick up the user's settings.
        guard Bundle.main.bundleIdentifier == currentDomain else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard let legacy = defaults.persistentDomain(forName: legacyDomain) else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
