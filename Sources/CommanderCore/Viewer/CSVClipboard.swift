// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

public enum CSVClipboard {
    /// Rows as tab-separated text, one line per row. A field with a tab, quote or line break is
    /// quoted, with its quotes doubled.
    public static func tsv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { field in
                guard field.contains(where: { $0 == "\t" || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
                else { return field }
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }.joined(separator: "\t")
        }.joined(separator: "\n")
    }
}
