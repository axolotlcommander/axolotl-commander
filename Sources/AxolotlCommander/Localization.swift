// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import CommanderCore
import Foundation

extension CommandSpec {
    /// Command title in the app language. `CommandRegistry` (CommanderCore) keeps English
    /// titles as keys; the translations live in `Resources/Localizable.xcstrings`.
    var localizedTitle: String {
        Bundle.main.localizedString(forKey: title, value: title, table: nil)
    }

    /// The name on a function key button: its own bar title, or the title without a trailing "…".
    var barTitle: String {
        if let own = CommandRegistry.barTitle(command) {
            return Bundle.main.localizedString(forKey: own, value: own, table: nil)
        }
        let title = localizedTitle
        return title.hasSuffix("…") ? String(title.dropLast()) : title
    }

    /// The short name for a narrow function key button, or `barTitle` when there is none.
    var localizedShortTitle: String {
        guard let short = CommandRegistry.shortTitle(command) else { return barTitle }
        return Bundle.main.localizedString(forKey: short, value: short, table: nil)
    }
}

extension ServerEncoding {
    /// `title` (English, from CommanderCore) in the app language.
    var localizedTitle: String {
        Bundle.main.localizedString(forKey: title, value: title, table: nil)
    }
}
