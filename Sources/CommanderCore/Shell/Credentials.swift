// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// Keeps passwords out of stored command history.
public enum Credentials {
    // scheme://user:password@host → scheme://user@host (password may contain '@', not '/')
    private static let urlForm = try! NSRegularExpression(
        pattern: #"([A-Za-z][A-Za-z0-9+.\-]*://[^\s/:@]+):[^\s/]*@"#)
    // whitespace-delimited word user:password@host
    private static let wordForm = try! NSRegularExpression(
        pattern: #"(?<!\S)([^\s/:@]+):[^\s/@]+@"#)
    // curl -u/--user (and -U/--proxy-user) user:password → user, only in the same command as a
    // word `curl` (so `docker run -u 1000:1000` stays). The value may be quoted, without spaces.
    private static let curlUserForm = try! NSRegularExpression(
        pattern: #"(?<!\S)((?:\S*/)?curl\s(?:[^|;&]*?\s)?(?:-[uU]\s*|--(?:proxy-)?user\s+)(['"]?)[^\s:'"]+):[^\s'"]*\2(?!\S)"#)

    /// Removes the password from `scheme://user:password@host…`, from a whitespace-delimited
    /// word `user:password@host…` and from curl's `-u user:password`. `git@github.com:a/b`,
    /// `user@host:path` and plain text stay unchanged.
    public static func scrub(_ text: String) -> String {
        var result = text
        for regex in [urlForm, wordForm] {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1@")
        }
        // One match consumes the command up to its option; repeat for further options.
        while true {
            let range = NSRange(result.startIndex..., in: result)
            let next = curlUserForm.stringByReplacingMatches(in: result, range: range, withTemplate: "$1$2")
            if next == result { return result }
            result = next
        }
    }
}
