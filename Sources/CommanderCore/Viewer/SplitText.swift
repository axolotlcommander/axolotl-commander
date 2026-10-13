// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Text for the viewer's text view with very long lines cut into display lines. TextKit lays out a
/// whole paragraph at once, so one line of tens of megabytes (a minified file) would take minutes and
/// gigabytes. The cuts are line breaks that exist only on screen: offsets map back to the source, and
/// copied text leaves them out. All offsets are UTF-16, as in `NSString`.
public struct SplitText: Sendable {
    public static let maxLineLength = 10_000
    /// How far back from the limit a cut looks for a comma, semicolon or space to cut after.
    static let lookBack = 200

    public let source: String
    public let display: String
    /// Source offsets with an inserted line break before them, ascending.
    public let breaks: [Int]

    public var isSplit: Bool { !breaks.isEmpty }

    public init(_ source: String, maxLine: Int = SplitText.maxLineLength) {
        self.source = source
        // A line never has more UTF-16 units than UTF-8 bytes, so text without a line that long in
        // UTF-8 needs no cut, and no copy of its units.
        guard Self.hasLine(longerThan: maxLine, in: source) else {
            breaks = []
            display = source
            return
        }
        let units = Array(source.utf16)
        var breaks: [Int] = []
        var lineStart = 0
        var i = 0
        while i < units.count {
            let u = units[i]
            if u == 0x0A || u == 0x0D {
                lineStart = i + 1
            } else if i - lineStart >= maxLine {
                let cut = Self.cut(in: units, at: i, lineStart: lineStart)
                breaks.append(cut)
                lineStart = cut
                i = cut
                continue
            }
            i += 1
        }
        self.breaks = breaks
        guard !breaks.isEmpty else {
            display = source
            return
        }
        var out: [UInt16] = []
        out.reserveCapacity(units.count + breaks.count)
        var from = 0
        for cut in breaks {
            out += units[from..<cut]
            out.append(0x0A)
            from = cut
        }
        out += units[from...]
        display = String(decoding: out, as: UTF16.self)
    }

    private static func hasLine(longerThan maxLine: Int, in text: String) -> Bool {
        var text = text
        return text.withUTF8 { bytes in
            var lineStart = 0
            for (i, byte) in bytes.enumerated() {
                if byte == 0x0A || byte == 0x0D {
                    lineStart = i + 1
                } else if i - lineStart >= maxLine {
                    return true
                }
            }
            return false
        }
    }

    /// Where to cut a line that reached the limit at `limit`: after the last comma, semicolon or space
    /// close before it, otherwise at the limit, never inside a surrogate pair.
    private static func cut(in units: [UInt16], at limit: Int, lineStart: Int) -> Int {
        var p = limit
        let floor = max(lineStart + 1, limit - lookBack)
        while p > floor {
            let previous = units[p - 1]
            if previous == 0x2C || previous == 0x3B || previous == 0x20 { return p }
            p -= 1
        }
        return UTF16.isTrailSurrogate(units[limit]) ? limit - 1 : limit
    }

    /// Inserted breaks at or before the source offset.
    private func breaksUpTo(_ offset: Int) -> Int {
        var low = 0, high = breaks.count
        while low < high {
            let mid = (low + high) / 2
            if breaks[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return low
    }

    public func displayOffset(ofSource offset: Int) -> Int { offset + breaksUpTo(offset) }

    public func displayRange(ofSource range: NSRange) -> NSRange {
        let start = displayOffset(ofSource: range.location)
        return NSRange(location: start, length: displayOffset(ofSource: NSMaxRange(range)) - start)
    }

    /// The source offset of a display offset; an inserted break maps to the character after it.
    public func sourceOffset(ofDisplay offset: Int) -> Int {
        var low = 0, high = breaks.count
        while low < high {
            let mid = (low + high) / 2
            if breaks[mid] + mid < offset { low = mid + 1 } else { high = mid }
        }
        return offset - low
    }

    /// The source text under a display range, without the inserted breaks.
    public func sourceText(ofDisplay range: NSRange) -> String {
        let start = sourceOffset(ofDisplay: range.location)
        let end = sourceOffset(ofDisplay: NSMaxRange(range))
        return (source as NSString).substring(with: NSRange(location: start, length: max(0, end - start)))
    }
}
