// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// sh-like word splitting for the command line.
public enum ShellWords {
    private static let metacharacters: Set<Character> = [";", "&", "|", "<", ">", "(", ")", "$", "`", "*", "?", "["]

    /// Whitespace separates words, `'…'` is literal, `"…"` honours `\"` `\\` `\$` `` \` `` escapes,
    /// backslash escapes the next character outside quotes. Returns nil for an unbalanced quote or
    /// an unquoted shell metacharacter (`; & | < > ( ) $ ` * ? [`) so the shell can handle the line.
    /// Unescaped `$` / `` ` `` inside double quotes also yield nil (expansion). A word starting with
    /// an unquoted `~` or `~/` gets `home` substituted.
    public static func split(_ line: String, home: URL) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var tildeAtStart = false
        var chars = Array(line)[...]

        func finish() {
            guard inWord else { return }
            if tildeAtStart { current = home.path + current.dropFirst() }
            words.append(current)
            current = ""
            inWord = false
            tildeAtStart = false
        }

        while let c = chars.popFirst() {
            switch c {
            case _ where c.isWhitespace:
                finish()
            case "'":
                inWord = true
                var closed = false
                while let d = chars.popFirst() {
                    if d == "'" { closed = true; break }
                    current.append(d)
                }
                if !closed { return nil }
            case "\"":
                inWord = true
                var closed = false
                while let d = chars.popFirst() {
                    if d == "\"" { closed = true; break }
                    if d == "$" || d == "`" { return nil }
                    if d == "\\", let e = chars.first, e == "\"" || e == "\\" || e == "$" || e == "`" {
                        current.append(e)
                        chars.removeFirst()
                    } else {
                        current.append(d)
                    }
                }
                if !closed { return nil }
            case "\\":
                guard let e = chars.popFirst() else { return nil }
                inWord = true
                current.append(e)
            case _ where metacharacters.contains(c):
                return nil
            default:
                if !inWord, c == "~", chars.first == nil || chars.first == "/" || chars.first!.isWhitespace {
                    tildeAtStart = true
                }
                inWord = true
                current.append(c)
            }
        }
        finish()
        return words
    }
}
