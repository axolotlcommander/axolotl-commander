import CommanderCore
import Foundation

extension CommandSpec {
    /// Command title in the app language. `CommandRegistry` (CommanderCore) keeps English
    /// titles as keys; the translations live in `Resources/Localizable.xcstrings`.
    var localizedTitle: String {
        Bundle.main.localizedString(forKey: title, value: title, table: nil)
    }
}

extension ServerEncoding {
    /// `title` (English, from CommanderCore) in the app language.
    var localizedTitle: String {
        Bundle.main.localizedString(forKey: title, value: title, table: nil)
    }
}
