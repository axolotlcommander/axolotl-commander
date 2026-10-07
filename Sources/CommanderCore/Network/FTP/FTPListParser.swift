public import Foundation

/// Parses FTP directory listings: MLSD facts (RFC 3659), Unix `ls -l` and DOS/IIS LIST output.
/// "." and ".." are dropped.
///
/// Names arrive as raw bytes and each line is decoded with the connection's `ServerEncoding`.
/// `.auto` reads a line as UTF-8, or as ISO Latin-1 when it is not valid UTF-8 (legacy servers
/// send their local 8-bit code page; Latin-1 never fails, so such names stay visible and
/// `ServerNameCodec` sends them back as the same bytes).
public enum FTPListParser {
    // MARK: Lines

    /// Splits a listing into decoded lines (LF or CRLF), skipping empty ones.
    public static func lines(_ data: Data, encoding: ServerEncoding = .auto) -> [String] {
        decodedLines(data, encoding).map(\.text)
    }

    /// Lines with whether `.auto` read them as Latin-1.
    static func decodedLines(_ data: Data, _ encoding: ServerEncoding) -> [(text: String, latin1: Bool)] {
        data.split(separator: 0x0A, omittingEmptySubsequences: true).compactMap { raw in
            var line = raw
            if line.last == 0x0D { line = line.dropLast() }
            if line.isEmpty { return nil }
            let r = encoding.decodeReportingFallback(line)
            return (r.text, r.fallback)
        }
    }

    /// UTF-8, or ISO Latin-1 when the bytes are not valid UTF-8.
    public static func decode(_ bytes: some Collection<UInt8>) -> String {
        ServerEncoding.auto.decode(bytes)
    }

    // MARK: MLSD

    public static func parseMLSD(_ data: Data, encoding: ServerEncoding = .auto) -> [RemoteEntry] {
        parseMLSDReportingLatin1(data, encoding).map(\.entry)
    }

    /// Entries with whether `.auto` read their line as Latin-1.
    static func parseMLSDReportingLatin1(_ data: Data, _ encoding: ServerEncoding) -> [(entry: RemoteEntry, latin1: Bool)] {
        decodedLines(data, encoding).compactMap { line in parseMLSDLine(line.text).map { ($0, line.latin1) } }
    }

    /// One `fact=value;fact=value; name` line; nil for "cdir"/"pdir", "." and "..", or garbage.
    public static func parseMLSDLine(_ line: String) -> RemoteEntry? {
        guard let space = line.firstIndex(of: " ") else { return nil }
        let name = String(line[line.index(after: space)...])
        guard !name.isEmpty, name != ".", name != ".." else { return nil }

        var kind = RemoteEntry.Kind.file
        var size: Int64?
        var date: Date?
        var mode: UInt32?
        var target: String?
        for fact in line[..<space].split(separator: ";") {
            guard let eq = fact.firstIndex(of: "=") else { continue }
            let key = fact[..<eq].lowercased()
            let value = fact[fact.index(after: eq)...]
            switch key {
            case "type":
                let type = value.lowercased()
                switch type {
                case "file": kind = .file
                case "dir": kind = .directory
                case "cdir", "pdir": return nil
                default:
                    if type.hasPrefix("os.unix=symlink") || type.hasPrefix("os.unix=slink") {
                        kind = .symlink
                        if let colon = value.firstIndex(of: ":") {
                            let t = value[value.index(after: colon)...]
                            if !t.isEmpty { target = String(t) }
                        }
                    } else {
                        kind = .other
                    }
                }
            case "size", "sizd":
                size = Int64(value)
            case "modify":
                date = mlsdTime(value)
            case "unix.mode":
                mode = UInt32(value, radix: 8).map { $0 & 0o7777 }
            default:
                break
            }
        }
        return RemoteEntry(name: name, kind: kind, size: size, modificationDate: date,
                           permissions: mode, linkTarget: target)
    }

    /// `YYYYMMDDHHMMSS[.sss]` in UTC.
    static func mlsdTime(_ text: Substring) -> Date? {
        let parts = text.split(separator: ".", maxSplits: 1)
        let digits = Array(parts.first ?? "")
        guard digits.count == 14, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        func num(_ from: Int, _ len: Int) -> Int { Int(String(digits[from..<from + len])) ?? 0 }
        var c = DateComponents()
        c.year = num(0, 4); c.month = num(4, 2); c.day = num(6, 2)
        c.hour = num(8, 2); c.minute = num(10, 2); c.second = num(12, 2)
        guard let base = calendar(TimeZone(identifier: "UTC")!).date(from: c) else { return nil }
        if parts.count == 2, let frac = Double("0." + parts[1]) { return base.addingTimeInterval(frac) }
        return base
    }

    // MARK: LIST

    /// Unix or DOS LIST output. Times without a zone are interpreted in `timeZone`; a Unix
    /// "Mon dd hh:mm" date (no year) falls in the year of `referenceDate`, or the previous one
    /// when that would put it more than a day after `referenceDate`.
    public static func parseLIST(
        _ data: Data, encoding: ServerEncoding = .auto, referenceDate: Date = Date(), timeZone: TimeZone = .current
    ) -> [RemoteEntry] {
        parseLISTReportingLatin1(data, encoding, referenceDate: referenceDate, timeZone: timeZone).map(\.entry)
    }

    /// Entries with whether `.auto` read their line as Latin-1.
    static func parseLISTReportingLatin1(
        _ data: Data, _ encoding: ServerEncoding, referenceDate: Date = Date(), timeZone: TimeZone = .current
    ) -> [(entry: RemoteEntry, latin1: Bool)] {
        decodedLines(data, encoding).compactMap { line in
            parseLISTLine(line.text, referenceDate: referenceDate, timeZone: timeZone).map { ($0, line.latin1) }
        }
    }

    public static func parseLISTLine(
        _ line: String, referenceDate: Date = Date(), timeZone: TimeZone = .current
    ) -> RemoteEntry? {
        let entry: RemoteEntry?
        if let first = line.first, first.isASCII, first.isNumber {
            entry = parseDOS(line, timeZone: timeZone)
        } else {
            entry = parseUnix(line, referenceDate: referenceDate, timeZone: timeZone)
        }
        guard let entry, entry.name != ".", entry.name != ".." else { return nil }
        return entry
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun",
                                 "jul", "aug", "sep", "oct", "nov", "dec"]

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    /// Whitespace-separated tokens as slices of `line` (so the tail can be cut out verbatim).
    private static func tokens(_ line: String) -> [Substring] {
        var result: [Substring] = []
        var i = line.startIndex
        while i < line.endIndex {
            while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
            guard i < line.endIndex else { break }
            let start = i
            while i < line.endIndex, line[i] != " ", line[i] != "\t" { i = line.index(after: i) }
            result.append(line[start..<i])
        }
        return result
    }

    private static func isDigits(_ s: Substring) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// "rwxr-x--x" (9 chars, s/S/t/T included) → mode bits.
    private static func modeBits(_ perms: [Character]) -> UInt32? {
        guard perms.count >= 9 else { return nil }
        var mode: UInt32 = 0
        let special: [UInt32] = [0o4000, 0o2000, 0o1000]
        for group in 0..<3 {
            let shift = UInt32(6 - group * 3)
            let r = perms[group * 3], w = perms[group * 3 + 1], x = perms[group * 3 + 2]
            guard "r-".contains(r), "w-".contains(w), "xsStTl-".contains(x) else { return nil }
            if r == "r" { mode |= 0o4 << shift }
            if w == "w" { mode |= 0o2 << shift }
            switch x {
            case "x": mode |= 0o1 << shift
            case "s", "t": mode |= (0o1 << shift) | special[group]
            case "S", "T", "l": mode |= special[group]
            default: break
            }
        }
        return mode
    }

    private static func parseUnix(_ line: String, referenceDate: Date, timeZone: TimeZone) -> RemoteEntry? {
        let toks = tokens(line)
        guard toks.count >= 5 else { return nil }
        let perm = Array(toks[0])
        guard perm.count >= 10, let mode = modeBits(Array(perm[1...9])) else { return nil }
        let kind: RemoteEntry.Kind
        switch perm[0] {
        case "-": kind = .file
        case "d": kind = .directory
        case "l": kind = .symlink
        case "c", "b", "p", "s", "D": kind = .other
        default: return nil
        }

        let cal = calendar(timeZone)
        // Find "<size> <Mon> <dd> <hh:mm|yyyy>" or "<size> <yyyy-mm-dd> <hh:mm>".
        var dateEnd: Int?
        var sizeIndex = 0
        var date: Date?
        for i in 2..<(toks.count - 1) where dateEnd == nil && isDigits(toks[i - 1]) {
            if i + 2 < toks.count, toks[i].count == 3,
               let month = months.firstIndex(of: toks[i].lowercased()),
               isDigits(toks[i + 1]), let day = Int(toks[i + 1]), (1...31).contains(day) {
                var c = DateComponents()
                c.month = month + 1
                c.day = day
                let third = toks[i + 2]
                if isDigits(third), third.count == 4 {
                    c.year = Int(third)
                } else if let (h, m) = clock(third) {
                    c.hour = h
                    c.minute = m
                    let year = cal.component(.year, from: referenceDate)
                    c.year = year
                    if let d = cal.date(from: c), d > referenceDate.addingTimeInterval(86_400) {
                        c.year = year - 1
                    }
                } else {
                    continue
                }
                date = cal.date(from: c)
                dateEnd = i + 2
                sizeIndex = i - 1
            } else if let ymd = isoDate(toks[i]), let (h, m) = clock(toks[i + 1]) {
                var c = DateComponents()
                (c.year, c.month, c.day) = ymd
                c.hour = h
                c.minute = m
                date = cal.date(from: c)
                dateEnd = i + 1
                sizeIndex = i - 1
            }
        }
        guard let dateEnd else { return nil }

        var rest = line[toks[dateEnd].endIndex...]
        if rest.first == " " || rest.first == "\t" { rest = rest.dropFirst() }
        guard !rest.isEmpty else { return nil }
        var name = String(rest)
        var target: String?
        if kind == .symlink, let arrow = rest.range(of: " -> ") {
            name = String(rest[..<arrow.lowerBound])
            target = String(rest[arrow.upperBound...])
        }
        let size = kind == .other ? nil : Int64(toks[sizeIndex])
        return RemoteEntry(name: name, kind: kind, size: size, modificationDate: date,
                           permissions: mode, linkTarget: target)
    }

    /// "hh:mm" → (h, m).
    private static func clock(_ s: Substring) -> (Int, Int)? {
        let p = s.split(separator: ":")
        guard p.count == 2, isDigits(p[0]), isDigits(p[1]), let h = Int(p[0]), let m = Int(p[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }

    /// "yyyy-mm-dd".
    private static func isoDate(_ s: Substring) -> (Int?, Int?, Int?)? {
        let p = s.split(separator: "-")
        guard p.count == 3, p[0].count == 4, p.allSatisfy(isDigits) else { return nil }
        return (Int(p[0]), Int(p[1]), Int(p[2]))
    }

    /// `01-02-24  10:15AM  <DIR>  name` or `01-02-2024 22:15 1234 name` (month first).
    private static func parseDOS(_ line: String, timeZone: TimeZone) -> RemoteEntry? {
        let toks = tokens(line)
        guard toks.count >= 4 else { return nil }
        let d = toks[0].split(separator: "-")
        guard d.count == 3, d.allSatisfy(isDigits), let month = Int(d[0]), let day = Int(d[1]),
              var year = Int(d[2]) else { return nil }
        if d[2].count <= 2 { year += year < 70 ? 2000 : 1900 }

        var timeText = toks[1].uppercased()
        var next = 2
        if toks[2].uppercased() == "AM" || toks[2].uppercased() == "PM" {
            timeText += toks[2].uppercased()
            next = 3
        }
        var pm: Bool?
        if timeText.hasSuffix("AM") || timeText.hasSuffix("PM") {
            pm = timeText.hasSuffix("PM")
            timeText.removeLast(2)
        }
        guard next + 1 < toks.count, let (h, minute) = clock(Substring(timeText)) else { return nil }
        var hour = h
        if let pm {
            guard (1...12).contains(hour) else { return nil }
            if hour == 12 { hour = 0 }
            if pm { hour += 12 }
        }
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        let date = calendar(timeZone).date(from: c)

        let sizeTok = toks[next]
        let kind: RemoteEntry.Kind
        var size: Int64?
        if sizeTok.uppercased() == "<DIR>" {
            kind = .directory
        } else {
            let digits = sizeTok.filter { $0 != "," && $0 != "." }
            guard isDigits(Substring(digits)) else { return nil }
            kind = .file
            size = Int64(digits)
        }
        let name = line[sizeTok.endIndex...].drop { $0 == " " || $0 == "\t" }
        guard !name.isEmpty else { return nil }
        return RemoteEntry(name: String(name), kind: kind, size: size, modificationDate: date)
    }
}
