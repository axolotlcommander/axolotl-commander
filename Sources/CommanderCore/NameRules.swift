// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// How file names compare on one volume. Canonical keys are for comparison
/// only and are never written to disk.
public struct NameRules: Sendable, Hashable {
    public let caseSensitive: Bool

    public init(caseSensitive: Bool) {
        self.caseSensitive = caseSensitive
    }

    /// APFS and HFS+ default: case-insensitive, case-preserving.
    public static let apfsDefault = NameRules(caseSensitive: false)

    public static func forVolume(containing url: URL) -> NameRules {
        let probe = url.nearestExistingAncestor
        let values = try? probe.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return NameRules(caseSensitive: values?.volumeSupportsCaseSensitiveNames ?? false)
    }

    /// Canonical form: NFC, plus case folding on case-insensitive volumes.
    public func key(_ name: String) -> String {
        if caseSensitive { return name.precomposedStringWithCanonicalMapping }
        return name.folding(options: .caseInsensitive, locale: nil).precomposedStringWithCanonicalMapping
    }

    public func same(_ a: String, _ b: String) -> Bool {
        key(a) == key(b)
    }

    /// Finder-like natural order: case-insensitive, numbers compared by value
    /// ("file2" < "file10"), with a deterministic tie-break.
    public func order(_ a: String, _ b: String) -> ComparisonResult {
        let na = a.precomposedStringWithCanonicalMapping
        let nb = b.precomposedStringWithCanonicalMapping
        let primary = na.compare(nb, options: [.caseInsensitive, .numeric], range: nil, locale: nil)
        if primary != .orderedSame { return primary }
        let tie = Self.scalarCompare(na, nb)
        if tie != .orderedSame { return tie }
        return Self.scalarCompare(a, b)
    }

    private static func scalarCompare(_ a: String, _ b: String) -> ComparisonResult {
        var ia = a.unicodeScalars.makeIterator()
        var ib = b.unicodeScalars.makeIterator()
        while true {
            switch (ia.next(), ib.next()) {
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedAscending
            case (_, nil): return .orderedDescending
            case let (x?, y?):
                if x.value != y.value { return x.value < y.value ? .orderedAscending : .orderedDescending }
            }
        }
    }
}
