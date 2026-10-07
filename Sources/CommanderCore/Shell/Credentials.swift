import Foundation

/// Keeps passwords out of stored command history.
public enum Credentials {
    // scheme://user:password@host → scheme://user@host (password may contain '@', not '/')
    private static let urlForm = try! NSRegularExpression(
        pattern: #"([A-Za-z][A-Za-z0-9+.\-]*://[^\s/:@]+):[^\s/]*@"#)
    // whitespace-delimited word user:password@host
    private static let wordForm = try! NSRegularExpression(
        pattern: #"(?<!\S)([^\s/:@]+):[^\s/@]+@"#)

    /// Removes the password from `scheme://user:password@host…` and from a whitespace-delimited
    /// word `user:password@host…`. `git@github.com:a/b`, `user@host:path` and plain text stay unchanged.
    public static func scrub(_ text: String) -> String {
        var result = text
        for regex in [urlForm, wordForm] {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1@")
        }
        return result
    }
}
