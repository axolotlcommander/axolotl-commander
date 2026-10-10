// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Texts of the Size and Date columns from the longest to the shortest, so a narrow column shows a
/// shorter form of the value instead of cutting a number in the middle.
public enum CellText {
    /// Bytes with grouping ("1 234 567"), then a rounded size ("1,2 MB").
    public static func size(_ bytes: Int64, locale: Locale = .current) -> [String] {
        let grouped = bytes.formatted(IntegerFormatStyle<Int64>(locale: locale).grouping(.automatic))
        let rounded = bytes.formatted(ByteCountFormatStyle(style: .file, locale: locale))
        return distinct([grouped, rounded])
    }

    /// Date and time, then the date alone, then the date with a two-digit year.
    public static func date(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> [String] {
        var calendar = Calendar.current
        calendar.locale = locale
        calendar.timeZone = timeZone
        let full = Date.FormatStyle(date: .numeric, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
        let day = Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)
        let short = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .day(.defaultDigits).month(.defaultDigits).year(.twoDigits)
        return distinct([date.formatted(full), date.formatted(day), date.formatted(short)])
    }

    /// The first variant that fits; the last one when none does (it is then truncated).
    public static func fitting(_ variants: [String], fits: (String) -> Bool) -> String {
        variants.first(where: fits) ?? variants.last ?? ""
    }

    private static func distinct(_ variants: [String]) -> [String] {
        variants.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
