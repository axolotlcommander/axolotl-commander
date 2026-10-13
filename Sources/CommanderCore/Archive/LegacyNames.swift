// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// Member names that are not UTF-8. A zip without the UTF-8 flag made on Windows holds names
/// in the OEM code page of that system; other old archives use its ANSI code page. The page
/// is not stored, so it is guessed from the user's language.
enum LegacyNames {
    struct CodePages: Equatable {
        var oem: String.Encoding
        var ansi: String.Encoding
    }

    /// The code pages Windows uses for `language` (a BCP 47 tag such as "cs-CZ").
    static func codePages(language: String) -> CodePages {
        let parts = language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" })
        let code = parts.first.map(String.init) ?? "en"
        switch code {
        case "cs", "sk", "pl", "hu", "hr", "sl", "ro", "bs", "sq":
            return CodePages(oem: page(.dosLatin2), ansi: page(.windowsLatin2))
        case "ru", "uk", "be", "bg", "mk", "sr", "kk":
            return CodePages(oem: page(.dosRussian), ansi: page(.windowsCyrillic))
        case "el":
            return CodePages(oem: page(.dosGreek), ansi: page(.windowsGreek))
        case "tr", "az":
            return CodePages(oem: page(.dosTurkish), ansi: page(.windowsLatin5))
        case "lt", "lv", "et":
            return CodePages(oem: page(.dosBalticRim), ansi: page(.windowsBalticRim))
        case "he":
            return CodePages(oem: page(.dosHebrew), ansi: page(.windowsHebrew))
        case "ar", "fa":
            return CodePages(oem: page(.dosArabic), ansi: page(.windowsArabic))
        case "ja":
            return CodePages(oem: page(.dosJapanese), ansi: page(.dosJapanese))
        case "ko":
            return CodePages(oem: page(.dosKorean), ansi: page(.dosKorean))
        case "zh":
            let traditional = parts.contains { ["hant", "tw", "hk", "mo"].contains($0) }
            let cjk = page(traditional ? .dosChineseTrad : .dosChineseSimplif)
            return CodePages(oem: cjk, ansi: cjk)
        case "en":
            return CodePages(oem: page(.dosLatinUS), ansi: .windowsCP1252)
        default:
            return CodePages(oem: page(.dosLatin1), ansi: .windowsCP1252)
        }
    }

    /// The pages for the user's first preferred language.
    static let current = codePages(language: Locale.preferredLanguages.first ?? "en")

    /// `bytes` as UTF-8 when they are valid UTF-8, otherwise in `legacy`.
    static func decode(_ bytes: some Collection<UInt8>, legacy: String.Encoding) -> String {
        if let utf8 = String(validating: bytes, as: UTF8.self) { return utf8 }
        return String(bytes: bytes, encoding: legacy) ?? String(decoding: bytes, as: UTF8.self)
    }

    private static func page(_ encoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }
}
