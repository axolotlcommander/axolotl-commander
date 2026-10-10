// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Texts of the Date column from the longest to the shortest, so a narrow column shows a
/// shorter form of the value instead of cutting a number in the middle. The Size column
/// gets its texts from `SizeFormat.columnVariants`.
public enum CellText {
    /// Date and time, then the date alone, with a two-digit year, and the day and month.
    public static func date(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> [String] {
        var calendar = Calendar.current
        calendar.locale = locale
        calendar.timeZone = timeZone
        let full = Date.FormatStyle(date: .numeric, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
        let day = Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)
        let short = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .day(.defaultDigits).month(.defaultDigits).year(.twoDigits)
        let dayMonth = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .day(.defaultDigits).month(.defaultDigits)
        return distinct([date.formatted(full), date.formatted(day), date.formatted(short), date.formatted(dayMonth)])
    }

    /// Shown when no variant fits: a cut number would mislead.
    public static let none = "…"

    /// The first variant that fits, or `none`.
    public static func fitting(_ variants: [String], fits: (String) -> Bool) -> String {
        variants.first(where: fits) ?? (variants.isEmpty ? "" : none)
    }

    private static func distinct(_ variants: [String]) -> [String] {
        variants.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
