// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

// Every file here is generated: in memory, or in a TestSandbox directory for the mapped-file check.

private func dialect(_ separator: CSVSeparator? = .semicolon, _ encoding: TextEncoding = .utf8,
                     start: Int = 0) -> CSVDialect {
    CSVDialect(separator: separator, encoding: encoding, contentStart: start)
}

private func index(_ data: Data, _ d: CSVDialect) -> CSVIndex {
    CSVIndexer.build(data, dialect: d)!
}

private func table(_ text: String, _ separator: CSVSeparator? = .semicolon) -> [[String]] {
    table(Data(text.utf8), dialect(separator))
}

private func table(_ data: Data, _ d: CSVDialect) -> [[String]] {
    let idx = index(data, d)
    return (0..<idx.rowCount).map { CSVRow.fields(in: data, index: idx, row: $0, dialect: d) }
}

@Suite struct CSVReadingTests {
    @Test func plainRows() {
        #expect(table("a;b;c\r\n1;2;3\r\n") == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test func quotedFields() {
        #expect(table("\"Praha; centrum\";x\n\"he said \"\"hi\"\"\";y\n")
            == [["Praha; centrum", "x"], ["he said \"hi\"", "y"]])
    }

    @Test func lineBreakInsideQuotes() {
        let rows = table("\"a\r\nb\";c\nd;e")
        #expect(rows == [["a\r\nb", "c"], ["d", "e"]])
    }

    @Test func lineEnds() {
        #expect(table("a\rb\nc\r\nd") == [["a"], ["b"], ["c"], ["d"]])
    }

    @Test func finalBreakAndEmptyLine() {
        #expect(table("a;b\n\nc;d\n") == [["a", "b"], [""], ["c", "d"]])
        #expect(table("a;b") == [["a", "b"]])
        #expect(table("").isEmpty)
        #expect(table("\n") == [[""]])
    }

    @Test func quoteInsideAndAfterField() {
        #expect(table("ab\"c;d\n") == [["ab\"c", "d"]])
        #expect(table("\"ab\"c;d\n") == [["abc", "d"]])
        #expect(table(" a ; b \n") == [[" a ", " b "]])
    }

    @Test func unclosedQuoteIsText() {
        let data = Data("a;b\nc;\"d\ne;f\ng;h\n".utf8)
        let idx = index(data, dialect())
        #expect(idx.rowCount == 4)
        #expect(idx.unclosedQuotes == [CSVUnclosedQuote(row: 1, offset: 6)])
        #expect(table(data, dialect()) == [["a", "b"], ["c", "\"d"], ["e", "f"], ["g", "h"]])
        #expect(idx.malformedRows(excludingFirst: false) == [1])
    }

    @Test func byteOrderMark() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("x;y\n".utf8)
        #expect(table(data, dialect(start: 3)) == [["x", "y"]])
    }

    @Test func utf16() {
        let text = "á;b\n\"c;d\";e\n"
        for (encoding, system) in [(TextEncoding.utf16LE, String.Encoding.utf16LittleEndian),
                                   (.utf16BE, .utf16BigEndian)] {
            let data = text.data(using: system)!
            #expect(table(data, dialect(.semicolon, encoding)) == [["á", "b"], ["c;d", "e"]])
        }
    }

    @Test func windows1250() {
        let bytes = TextEncoding.windows1250.encode("Žluťoučký;kůň\n")!
        #expect(table(Data(bytes), dialect(.semicolon, .windows1250)) == [["Žluťoučký", "kůň"]])
    }

    @Test func singleColumnAndLimit() {
        #expect(table("a;b\n", nil) == [["a;b"]])
        let data = Data("a;b;c\n".utf8)
        let idx = index(data, dialect())
        #expect(CSVRow.fields(in: data, index: idx, row: 0, dialect: dialect(), limit: 2) == ["a", "b"])
    }

    @Test func rowLookup() {
        let idx = index(Data("aa\nbb\ncc\n".utf8), dialect())
        #expect(idx.rowStarts == [0, 3, 6, 9])
        #expect(idx.row(containing: 0) == 0)
        #expect(idx.row(containing: 4) == 1)
        #expect(idx.row(containing: 100) == 2)
    }

    @Test func streamEndsComplete() async {
        let text = String(repeating: "a;b;c\n", count: 20_000)
        var last: CSVIndex?
        for await snapshot in CSVIndexer.stream(Data(text.utf8), dialect: dialect()) { last = snapshot }
        #expect(last?.isComplete == true)
        #expect(last?.rowCount == 20_000)
    }

    @Test func buildStopsWhenAsked() {
        let text = String(repeating: "a;b\n", count: 20_000)
        #expect(CSVIndexer.build(Data(text.utf8), dialect: dialect()) { _ in false } == nil)
    }

    @Test func largeMappedFile() throws {
        try TestSandbox.with("axo-csv", sync: { root in
            let url = root.appendingPathComponent("big.csv")
            var text = ""
            text.reserveCapacity(25_000_000)
            for i in 0..<200_000 {
                text += "Firma \(i % 5000) s.r.o.;;;\(230_000_000 + i);234;Ulice \(i % 900);\(i % 3000);;Praha;Praha 4;14000;;;;;\(26_000_000 + i);;\"x;y\";\r\n"
            }
            try Data(text.utf8).write(to: url)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let clock = ContinuousClock()
            var idx: CSVIndex?
            let elapsed = clock.measure { idx = CSVIndexer.build(data, dialect: dialect()) }
            #expect(idx?.rowCount == 200_000)
            #expect(idx?.maxFields == 19)
            #expect(idx?.malformedRows(excludingFirst: false).isEmpty == true)
            // Generous for debug builds; a release build indexes this in a few tens of milliseconds.
            #expect(elapsed < .seconds(10))
        })
    }
}

@Suite struct CSVDetectionTests {
    private func detect(_ text: String, preferTab: Bool = false) -> CSVSample {
        CSVSample.detect(Data(text.utf8), encoding: .utf8, contentStart: 0, preferTab: preferTab)
    }

    @Test func exportWithoutHeader() {
        let sample = detect("CEVA Logistics;;;239018339;234;Hybesova\nMowi ASA;;;234286900;234;Za Avií\nMowi ASA;;;234286901;234;Za Avií\n")
        #expect(sample.separator == .semicolon)
        #expect(!sample.hasHeader)
        #expect(sample.numericColumns.contains(3))
    }

    @Test func reportWithHeader() {
        let sample = detect("SYS_KOD;soubor;KB\nacn;a.csv;19.5\nx;b.csv;0.2\n")
        #expect(sample.separator == .semicolon)
        #expect(sample.hasHeader)
        #expect(sample.numericColumns == [2])
    }

    @Test func separators() {
        #expect(detect("a,b,c\n1,2,3\n").separator == .comma)
        #expect(detect("a|b\nc|d\n").separator == .bar)
        #expect(detect("a\tb\nc\td\n").separator == .tab)
        #expect(detect("abc\ndef\n").separator == nil)
        // A tie goes to the semicolon, or to tab for .tsv/.tab files.
        #expect(detect("a;b,c\n").separator == .semicolon)
        #expect(detect("a\tb;c\n", preferTab: true).separator == .tab)
        // The most consistent field count wins over more separators.
        #expect(detect("a;b,c,d,e\nf;g\nh;i,j\n").separator == .semicolon)
    }

    @Test func headerRule() {
        #expect(detect("name;city\nJan;Brno\n").hasHeader)
        #expect(!detect("name;city\nname;Brno\n").hasHeader)
        #expect(!detect("name;;city\nJan;x;Brno\n").hasHeader)
        #expect(!detect("name;city\n").hasHeader)
    }

    @Test func cutRowIsLeftOut() {
        let line = String(repeating: "x", count: 100) + ";1\n"
        let text = String(repeating: line, count: 1_000) + "tail;without;end"
        let sample = detect(text)
        #expect(sample.rows.allSatisfy { $0.count == 2 })
        #expect(sample.rows.count == CSVSample.byteLimit / line.utf8.count)
    }

    @Test func numbers() {
        #expect(CSVNumber.parse("-12,5") == -12.5)
        #expect(CSVNumber.parse("+3") == 3)
        #expect(CSVNumber.parse("007") == 7)
        #expect(CSVNumber.parse("1,5", allowComma: false) == nil)
        for text in ["1.", ".5", "1 000", "1.2.3", "", "-", "1e3", "12a"] {
            #expect(CSVNumber.parse(text) == nil, "\(text)")
        }
    }
}

@Suite struct CSVMalformedTests {
    private func rows(_ counts: [Int]) -> String {
        counts.map { Array(repeating: "x", count: $0).joined(separator: ";") + "\n" }.joined()
    }

    @Test func expectedAndMalformed() {
        var counts = Array(repeating: 19, count: 10)
        counts[3] = 18
        counts[8] = 20
        let idx = index(Data(rows(counts).utf8), dialect())
        #expect(idx.expectedFields(excludingFirst: false) == 19)
        #expect(idx.malformedRows(excludingFirst: false) == [3, 8])
        #expect(idx.maxFields == 20)
    }

    @Test func headerIsLeftOut() {
        let idx = index(Data(rows([3, 2, 2, 2]).utf8), dialect())
        #expect(idx.malformedRows(excludingFirst: false) == [0])
        #expect(idx.malformedRows(excludingFirst: true).isEmpty)
    }

    @Test func tieGoesToMoreFields() {
        let idx = index(Data(rows([2, 3, 2, 3]).utf8), dialect())
        #expect(idx.expectedFields(excludingFirst: false) == 3)
    }

    @Test func emptyFile() {
        let idx = index(Data(), dialect())
        #expect(idx.rowCount == 0)
        #expect(idx.isComplete)
        #expect(idx.malformedRows(excludingFirst: true).isEmpty)
        #expect(idx.expectedFields(excludingFirst: false) == 0)
    }
}

@Suite struct CSVSearchAndCopyTests {
    private let data = Data("Čáslav;x\nPraha;y\nbrno;z\n".utf8)

    private func find(_ query: String, from: Int, backward: Bool = false, ignoreCase: Bool = true) throws -> CSVSearch.Match? {
        let idx = index(data, dialect())
        return try CSVSearch.find(query, ignoreCase: ignoreCase, locale: Locale(identifier: "cs_CZ"), in: data,
                                  index: idx, dialect: dialect(), rows: .range(0..<idx.rowCount),
                                  from: from, backward: backward)
    }

    @Test func diacriticsCaseAndWrap() throws {
        #expect(try find("caslav", from: -1) == .init(position: 0, column: 0))
        #expect(try find("BRNO", from: 0) == .init(position: 2, column: 0))
        #expect(try find("caslav", from: 2) == .init(position: 0, column: 0))
        #expect(try find("y", from: 0, backward: true) == .init(position: 1, column: 1))
        #expect(try find("BRNO", from: -1, ignoreCase: false) == nil)
        // A match across the separator is not a cell match.
        #expect(try find("slav;x", from: -1) == nil)
    }

    @Test func cellByCell() throws {
        let data = Data("a;Praha;b;Praha\nPraha;c\nd;e\n".utf8)
        let idx = index(data, dialect())
        func next(_ position: Int, _ column: Int?, backward: Bool = false) throws -> CSVSearch.Match? {
            try CSVSearch.find("praha", ignoreCase: true, in: data, index: idx, dialect: dialect(),
                               rows: .range(0..<3), from: position, column: column, backward: backward)
        }
        #expect(try next(-1, nil) == .init(position: 0, column: 1))
        #expect(try next(0, 1) == .init(position: 0, column: 3))
        #expect(try next(0, 3) == .init(position: 1, column: 0))
        #expect(try next(1, 0) == .init(position: 0, column: 1))
        #expect(try next(0, 3, backward: true) == .init(position: 0, column: 1))
        #expect(try next(0, 1, backward: true) == .init(position: 1, column: 0))
        #expect(try next(1, 0, backward: true) == .init(position: 0, column: 3))
        // A row without a found cell is passed as a whole.
        #expect(try next(0, nil) == .init(position: 1, column: 0))
        // The only match is in the starting row, before the cell: found after wrapping around.
        let single = Data("x;Brno;y\n".utf8)
        let one = index(single, dialect())
        #expect(try CSVSearch.find("brno", ignoreCase: true, in: single, index: one, dialect: dialect(),
                                   rows: .range(0..<1), from: 0, column: 1, backward: false) == .init(position: 0, column: 1))
    }

    @Test func listOrder() throws {
        let idx = index(data, dialect())
        let match = try CSVSearch.find("praha", ignoreCase: true, in: data, index: idx, dialect: dialect(),
                                       rows: .list([2, 1, 0]), from: -1, backward: false)
        #expect(match == .init(position: 1, column: 0))
    }

    @Test func rowList() {
        let range = CSVRowList.range(1..<5)
        #expect(range.count == 4)
        #expect(range[0] == 1)
        #expect(range.position(of: 4) == 3)
        #expect(range.position(of: 0) == nil)
        #expect(CSVRowList.list([5, 2]).position(of: 2) == 1)
    }

    @Test func tsv() {
        #expect(CSVClipboard.tsv([["a", "b"], ["c\td", "say \"hi\""], ["x\ny", ""]])
            == "a\tb\n\"c\td\"\t\"say \"\"hi\"\"\"\n\"x\ny\"\t")
    }
}

@Suite struct CSVSortTests {
    private let czech = Locale(identifier: "cs_CZ")

    private func sorted(_ cells: [String], numeric: Bool, ascending: Bool = true) async throws -> [String] {
        let text = cells.map { $0 + "\n" }.joined()
        let data = Data(text.utf8)
        let idx = index(data, dialect())
        let order = try await CSVSort.order(data, index: idx, dialect: dialect(), rows: 0..<idx.rowCount,
                                            column: 0, numeric: numeric, ascending: ascending, locale: czech)
        return order.map { cells[Int($0)] }
    }

    @Test func numbers() async throws {
        let cells = ["2", "10", "", "x", "1,5", "a"]
        #expect(try await sorted(cells, numeric: true) == ["1,5", "2", "10", "x", "a", ""])
        #expect(try await sorted(cells, numeric: true, ascending: false) == ["10", "2", "1,5", "x", "a", ""])
    }

    @Test func czechText() async throws {
        let cells = ["Čáslav", "cheb", "", "Brno", "Hradec", "Cvikov"]
        #expect(try await sorted(cells, numeric: false) == ["Brno", "Cvikov", "Čáslav", "Hradec", "cheb", ""])
        #expect(try await sorted(cells, numeric: false, ascending: false)
            == ["cheb", "Hradec", "Čáslav", "Cvikov", "Brno", ""])
    }

    @Test func stableForEqualTexts() async throws {
        let text = "Praha;1\nbrno;2\npraha;3\nPRAHA;4\n"
        let data = Data(text.utf8)
        let idx = index(data, dialect())
        let order = try await CSVSort.order(data, index: idx, dialect: dialect(), rows: 0..<4, column: 0,
                                            numeric: false, ascending: true, locale: czech)
        #expect(order == [1, 0, 2, 3])
    }

    @Test func headerAndShortRows() async throws {
        let data = Data("title;n\nb;2\nshort\na;1\n".utf8)
        let idx = index(data, dialect())
        let order = try await CSVSort.order(data, index: idx, dialect: dialect(), rows: 1..<4, column: 1,
                                            numeric: true, ascending: true, locale: czech)
        #expect(order == [3, 1, 2])
    }

    @Test func parallelTextSort() async throws {
        let count = CSVSort.parallelThreshold + 10_000
        let cells = (0..<count).map { "Položka \(($0 * 7_919) % count)" }
        let ranks = try await CSVSort.textRanks(cells, locale: czech)
        let order = cells.indices.sorted { ranks[$0] < ranks[$1] }
        for (a, b) in zip(order, order.dropFirst()) {
            #expect(cells[a].compare(cells[b], options: .caseInsensitive, range: nil, locale: czech) != .orderedDescending)
        }
    }

    @Test func cancelled() async {
        let cells = (0..<100_000).map { "x\($0)" }.joined(separator: "\n")
        let data = Data(cells.utf8)
        let idx = index(data, dialect())
        let task = Task {
            try await CSVSort.order(data, index: idx, dialect: dialect(), rows: 0..<idx.rowCount, column: 0,
                                    numeric: false, ascending: true)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
