// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// How the letters of one part of a name are rewritten.
public enum CaseStyle: String, CaseIterable, Codable, Sendable {
    case keep
    case lower
    case upper
    /// First letter and every letter after a non-letter-non-digit character upper, all other letters lower
    /// ("my FILE-name_x" becomes "My File-Name_X").
    case mixed

    func apply(to text: String) -> String {
        switch self {
        case .keep: return text
        case .lower: return text.map { String($0).lowercased() }.joined()
        case .upper: return text.map { String($0).uppercased() }.joined()
        case .mixed:
            var out = ""
            var first = true
            var afterBoundary = false
            for c in text {
                if c.isLetter {
                    out += (first || afterBoundary) ? String(c).uppercased() : String(c).lowercased()
                    first = false
                    afterBoundary = false
                } else {
                    out.append(c)
                    afterBoundary = !c.isNumber
                }
            }
            return out
        }
    }
}

/// Change of case of a file name: separate styles for the name part and the extension.
public struct CaseChange: Codable, Sendable, Hashable {
    /// Part before the last dot (the whole name for folders and names without an extension).
    public var name: CaseStyle
    /// Part after the last dot (a leading dot does not start an extension).
    public var ext: CaseStyle

    public init(name: CaseStyle, ext: CaseStyle) {
        self.name = name
        self.ext = ext
    }

    public static let lower = CaseChange(name: .lower, ext: .lower)
    public static let upper = CaseChange(name: .upper, ext: .upper)
    /// Name mixed, extension lower.
    public static let partiallyMixed = CaseChange(name: .mixed, ext: .lower)
    public static let mixed = CaseChange(name: .mixed, ext: .mixed)

    public func apply(to fileName: String, isDirectory: Bool) -> String {
        if isDirectory { return name.apply(to: fileName) }
        let (base, extPart, hasDot) = NameParts.split(fileName)
        let newBase = name.apply(to: base)
        return hasDot ? newBase + "." + ext.apply(to: extPart) : newBase
    }
}

enum NameParts {
    /// Splits at the last dot; a leading dot does not start an extension. A trailing dot gives an empty extension.
    static func split(_ name: String) -> (base: String, ext: String, hasDot: Bool) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "", false) }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]), true)
    }
}
