// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

// Every document here is generated in memory.

private func doc(_ text: String, lines: Bool = false) throws -> JSONDocument {
    try JSONDocument.parse(Data(text.utf8), lines: lines)
}

private func parseError(_ text: String) -> JSONParseError? {
    do {
        _ = try doc(text)
        return nil
    } catch let error as JSONParseError {
        return error
    } catch {
        return nil
    }
}

/// The node reached by following keys (objects) or indices (arrays) from the root.
private func node(_ d: JSONDocument, _ steps: Any...) -> Int {
    var current = 0
    for step in steps {
        let kids = d.children(of: current)
        if let key = step as? String {
            current = kids.first { d.keyText($0) == key }!
        } else {
            current = kids[step as! Int]
        }
    }
    return current
}

@Suite struct JSONDocumentParseTests {
    @Test func everyValueKind() throws {
        let d = try doc(#"{"o": {}, "a": [], "s": "x", "n": -1.5e3, "t": true, "f": false, "z": null}"#)
        #expect(d.nodes.map(\.kind) == [.object, .object, .array, .string, .number, .bool, .bool, .null])
        #expect(d.valueText(node(d, "n")) == "-1.5e3")
        #expect(d.valueText(node(d, "s")) == "x")
        #expect(d.valueText(node(d, "t")) == "true")
        #expect(d.valueText(node(d, "z")) == "null")
        #expect(d.valueText(0) == "")
        #expect(!d.isLines)
        for top in [#""text""#, "42", "true", "null", "[]"] {
            #expect(try doc(top).nodes.count == 1)
        }
    }

    @Test func preOrderLayout() throws {
        let d = try doc(#"{"a": [1, {"b": 2}], "c": 3}"#)
        // 0 root, 1 a, 2 1, 3 {b}, 4 b, 5 c
        #expect(d.nodes.map(\.kind) == [.object, .array, .number, .object, .number, .number])
        #expect(d.nodes.map(\.parent) == [-1, 0, 1, 1, 3, 0])
        #expect(d.nodes.map(\.firstChild) == [1, 2, -1, 4, -1, -1])
        #expect(d.nodes.map(\.childCount) == [2, 2, 0, 1, 0, 0])
        #expect(d.nodes.map(\.nextSibling) == [-1, 5, 3, -1, -1, -1])
        #expect(d.nodes.map(\.index) == [0, 0, 0, 1, 0, 1])
        #expect(d.children(of: 0) == [1, 5])
        #expect(d.ancestors(of: 4) == [3, 1, 0])
        #expect(d.ancestors(of: 0) == [])
        #expect(d.nodes[1].key.map { Array(d.bytes[$0]) } == Array(#""a""#.utf8))
        #expect(d.nodes[2].key == nil)
        #expect(String(decoding: d.bytes[d.nodes[3].value], as: UTF8.self) == #"{"b": 2}"#)
        #expect(String(decoding: d.bytes[d.nodes[0].value], as: UTF8.self) == #"{"a": [1, {"b": 2}], "c": 3}"#)
    }

    @Test func positionsOfValues() throws {
        let d = try doc("{\n  \"é\": [true,\n    null]\n}")
        #expect(d.nodes.map(\.line) == [1, 2, 2, 3])
        #expect(d.nodes.map(\.column) == [1, 8, 9, 5])
    }

    @Test func keyOrderAndDuplicates() throws {
        let d = try doc(#"{"z": 1, "a": 2, "m": 3, "a": 4, "\u0061": 5}"#)
        #expect(d.children(of: 0).map { d.keyText($0)! } == ["z", "a", "m", "a", "a"])
        #expect(d.nodes.map(\.isDuplicate) == [false, false, false, false, true, true])
        #expect(d.children(of: 0).map { d.valueText($0) } == ["1", "2", "3", "4", "5"])
        // Large objects use a set; duplicates in different objects do not count.
        let members = (0..<20).map { "\"k\($0 % 10)\": \($0)" }.joined(separator: ",")
        let big = try doc("[{\(members)}, {\"k0\": 1}]")
        let flags = big.children(of: node(big, 0)).map { big.nodes[$0].isDuplicate }
        #expect(flags == Array(repeating: false, count: 10) + Array(repeating: true, count: 10))
        #expect(!big.nodes[node(big, 1, 0)].isDuplicate)
    }

    @Test func bigNumberKeptExactly() throws {
        let d = try doc(#"[12345678901234567890.5, -0, 0.0e-0, 1E+400]"#)
        #expect(d.children(of: 0).map { d.valueText($0) } == ["12345678901234567890.5", "-0", "0.0e-0", "1E+400"])
        #expect(d.copyValue(of: 1) == "12345678901234567890.5")
    }

    @Test func escapesInKeysAndValues() throws {
        let d = try doc(#"{"caf\u00e9 \ud83d\ude00": "\"q\" \\ \/ \b\f\n\r\t \u00e9\ud83d\ude00", "raw é😀": "é😀"}"#)
        let first = node(d, 0)
        #expect(d.keyText(first) == "café 😀")
        #expect(d.valueText(first) == "\"q\" \\ / \u{8}\u{C}\n\r\t é😀")
        #expect(d.copyValue(of: first) == "\"q\" \\ / \u{8}\u{C}\n\r\t é😀")
        #expect(d.keyText(node(d, 1)) == "raw é😀")
        #expect(d.valueText(node(d, 1)) == "é😀")
        // A lone surrogate decodes to U+FFFD.
        #expect(try doc(#"["\ud83d x"]"#).valueText(1) == "\u{FFFD} x")
    }

    @Test func valueTextIsCut() throws {
        let long = String(repeating: "abc", count: 100)
        let d = try doc("[\"\(long)\", \"\(String(repeating: "é", count: 10))\", \"a\\nb\(long)\"]")
        #expect(d.valueText(1, limit: 5) == "abcab…")
        #expect(d.valueText(1).count == 201)
        #expect(d.valueText(2, limit: 10) == String(repeating: "é", count: 10))
        #expect(d.valueText(2, limit: 3) == "ééé…")
        #expect(d.valueText(3, limit: 4) == "a\nba…")
    }

    @Test func commentsAndTrailingCommas() throws {
        let text = """
            // leading
            { /* a */ "a": [1, 2, /* x */ ], // end
              "b" /* before colon */ : {"c": 3,}, }
            /* trailing */
            """
        let d = try doc(text)
        #expect(d.children(of: 0).count == 2)
        #expect(d.children(of: node(d, "a")).count == 2)
        #expect(d.nodes[node(d, "b", "c")].line == 3)
    }

    @Test func byteOrderMarkIsSkipped() throws {
        let d = try JSONDocument.parse(Data([0xEF, 0xBB, 0xBF] + Array(#"{"a":1}"#.utf8)), lines: false)
        #expect(d.bytes.first == 0x7B)
        #expect(d.nodes[0].column == 1)
        #expect(d.keyText(1) == "a")
    }

    @Test func json5IsRejected() {
        let cases: [(String, Int, Int)] = [
            ("{a: 1}", 1, 2),
            ("{\n  \"x\": 1,\n  $b: 2}", 3, 3),
            ("['x']", 1, 2),
            ("{'x': 1}", 1, 2),
            ("[0x1F]", 1, 2),
            ("[-0X1F]", 1, 2),
            ("[+1]", 1, 2),
            ("[Infinity]", 1, 2),
            ("[-Infinity]", 1, 2),
            ("NaN", 1, 1),
            ("[.5]", 1, 2),
            ("[-.5]", 1, 3),
            ("[5.]", 1, 3),
            ("[\"é\", 5.e3]", 1, 8),
        ]
        for (text, line, column) in cases {
            #expect(parseError(text) == JSONParseError(line: line, column: column, reason: .unsupportedJSON5),
                    "\(text)")
        }
    }

    @Test func errorPositions() {
        let cases: [(String, JSONParseError)] = [
            ("{\n  \"a\": 1\n  \"b\": 2\n}", .init(line: 3, column: 3, reason: .unexpectedCharacter)),
            ("[1,\n 2,\n", .init(line: 3, column: 1, reason: .unexpectedEnd)),
            ("{\"a\": \"é\\x\"}", .init(line: 1, column: 9, reason: .invalidEscape)),
            ("[\"\\u12G4\"]", .init(line: 1, column: 3, reason: .invalidEscape)),
            ("[\n  \"abc\n]", .init(line: 2, column: 3, reason: .unterminatedString)),
            ("\"abc", .init(line: 1, column: 1, reason: .unterminatedString)),
            ("[\"a\tb\"]", .init(line: 1, column: 4, reason: .controlCharacter)),
            ("[01]", .init(line: 1, column: 3, reason: .invalidNumber)),
            ("[1e]", .init(line: 1, column: 4, reason: .invalidNumber)),
            ("[-]", .init(line: 1, column: 3, reason: .invalidNumber)),
            ("[tru]", .init(line: 1, column: 2, reason: .unexpectedCharacter)),
            ("{\"a\" 1}", .init(line: 1, column: 6, reason: .unexpectedCharacter)),
            ("{\"a\": }", .init(line: 1, column: 7, reason: .unexpectedCharacter)),
            ("[1,,2]", .init(line: 1, column: 4, reason: .unexpectedCharacter)),
            ("[1 /* open", .init(line: 1, column: 11, reason: .unexpectedEnd)),
            ("{\"a\": 1} x", .init(line: 1, column: 10, reason: .trailingData)),
            ("1\n// c\n2", .init(line: 3, column: 1, reason: .trailingData)),
            ("", .init(line: 1, column: 1, reason: .emptyDocument)),
            (" \n /* only */ \n", .init(line: 1, column: 1, reason: .emptyDocument)),
        ]
        for (text, expected) in cases {
            #expect(parseError(text) == expected, "\(text)")
        }
    }

    @Test func deepNestingDoesNotRecurse() throws {
        let depth = 100_000
        let d = try doc(String(repeating: "[", count: depth) + String(repeating: "]", count: depth))
        #expect(d.nodes.count == depth)
        #expect(d.nodes[depth - 1].parent == depth - 2)
        #expect(d.path(of: 2) == "[0][0]")
    }

    @Test func cancellation() {
        #expect(throws: CancellationError.self) {
            try JSONDocument.parse(Data("[1, 2]".utf8), lines: false, isCancelled: { true })
        }
        #expect(throws: CancellationError.self) {
            try JSONDocument.parse(Data("1\n2".utf8), lines: true, isCancelled: { true })
        }
    }

    @Test func largeGeneratedDocument() throws {
        // About 5 MB minified: 50 000 objects of 5 members each.
        var text = "["
        for i in 0..<50_000 {
            if i > 0 { text += "," }
            text += #"{"id":\#(i),"name":"item \#(i) with some padding text","tags":["a","b","c"],"#
            text += #""ok":true,"score":\#(i).25,"note":"lorem ipsum dolor sit amet consectetur"}"#
        }
        text += "]"
        #expect(text.utf8.count > 5_000_000)
        let d = try doc(text)
        #expect(d.nodes.count == 1 + 50_000 * 10)
        #expect(d.path(of: d.nodes.count - 1) == "[49999].note")
    }
}

@Suite struct JSONLinesTests {
    @Test func linesWithABadLine() throws {
        let text = "{\"a\": 1}\r\n\n   \n[1, 2]\n{\"b\": tru}\n\"s\"\n// only a comment\n42"
        let d = try doc(text, lines: true)
        #expect(d.isLines)
        let root = d.nodes[0]
        #expect(root.kind == .array && root.value == 0..<d.bytes.count && root.line == 1 && root.column == 1)
        let lines = d.children(of: 0)
        #expect(lines.map { d.nodes[$0].kind } == [.object, .array, .error, .string, .number])
        #expect(lines.map { d.nodes[$0].index } == [0, 1, 2, 3, 4])
        #expect(lines.map { d.nodes[$0].line } == [1, 4, 5, 6, 8])
        let bad = d.nodes[lines[2]]
        #expect(bad.error == JSONParseError(line: 5, column: 7, reason: .unexpectedCharacter))
        #expect(d.valueText(lines[2]) == "{\"b\": tru}")
        #expect(d.copyValue(of: lines[2]) == "{\"b\": tru}")
        #expect(String(decoding: d.bytes[d.nodes[lines[0]].value], as: UTF8.self) == "{\"a\": 1}")
        #expect(d.nodes[node(d, 1, 1)].line == 4 && d.nodes[node(d, 1, 1)].column == 5)
        #expect(root.childCount == 5)
    }

    @Test func emptyAndTrailingData() throws {
        #expect(try doc("", lines: true).nodes.count == 1)
        let d = try doc("1 2\n{\"x\":", lines: true)
        let errors = d.children(of: 0).map { d.nodes[$0].error }
        #expect(errors == [JSONParseError(line: 1, column: 3, reason: .trailingData),
                           JSONParseError(line: 2, column: 6, reason: .unexpectedEnd)])
    }
}

@Suite struct JSONPathAndCopyTests {
    @Test func paths() throws {
        let d = try doc(#"{"items": [{"name": 1}, [[0, {"x": 2}]]], "two words": {"q\"t": 3, "_ok$1": 4, "1a": 5}}"#)
        #expect(d.path(of: 0) == "$")
        #expect(d.path(of: node(d, "items")) == "items")
        #expect(d.path(of: node(d, "items", 0, "name")) == "items[0].name")
        #expect(d.path(of: node(d, "items", 1, 0, 1, "x")) == "items[1][0][1].x")
        #expect(d.path(of: node(d, "two words")) == #"["two words"]"#)
        #expect(d.path(of: node(d, "two words", "q\"t")) == #"["two words"]["q\"t"]"#)
        #expect(d.path(of: node(d, "two words", "_ok$1")) == #"["two words"]._ok$1"#)
        #expect(d.path(of: node(d, "two words", "1a")) == #"["two words"]["1a"]"#)
        let array = try doc(#"[0, 1, {"a": true}]"#)
        #expect(array.path(of: node(array, 2, "a")) == "[2].a")
        let lines = try doc("1\n2\n3\n\n4\n{\"name\": 5}", lines: true)
        #expect(lines.path(of: node(lines, 4, "name")) == "[4].name")
        #expect(lines.path(of: 0) == "$")
    }

    @Test func copyScalars() throws {
        let d = try doc(#"["a\"b\u00e9", 1.50, true, null]"#)
        #expect(d.children(of: 0).map { d.copyValue(of: $0) } == ["a\"bé", "1.50", "true", "null"])
    }

    @Test func copyContainerPrettyPrints() throws {
        let text = """
            {"b": [1, "x\\u0041\\"", {}, [], {"n": null}], // note
             /* c */ "a": {"z": 2.0e1, "t": "tab\\tq"}, "e": [ ],
             "dup": 1, "dup": 2}
            """
        let d = try doc(text)
        let expected = """
            {
              "b": [
                1,
                "xA\\"",
                {},
                [],
                {
                  "n": null
                }
              ],
              "a": {
                "z": 2.0e1,
                "t": "tab\\tq"
              },
              "e": [],
              "dup": 1,
              "dup": 2
            }
            """
        #expect(d.copyValue(of: 0) == expected)
        #expect(d.copyValue(of: node(d, "e")) == "[]")
        #expect(d.copyValue(of: node(d, "a")) == "{\n  \"z\": 2.0e1,\n  \"t\": \"tab\\tq\"\n}")
        #expect(try doc(#"{"k\u0001": "\/"}"#).copyValue(of: 0) == "{\n  \"k\\u0001\": \"/\"\n}")
    }
}

@Suite struct JSONSearchTests {
    // 0 root, 1 alpha, 2 beta, 3 "Gamma", 4 {delta}, 5 delta "alphabet", 6 n 42
    private let text = #"{"alpha": 1, "beta": ["Gamma", {"delta": "alphabet"}], "n": 42}"#

    @Test func forwardBackwardAndWrap() throws {
        let d = try doc(text)
        #expect(d.search("alpha", from: 0, backward: false, ignoreCase: false) == 1)
        #expect(d.search("alpha", from: 1, backward: false, ignoreCase: false) == 5)
        #expect(d.search("alpha", from: 5, backward: false, ignoreCase: false) == 1)
        #expect(d.search("alpha", from: 1, backward: true, ignoreCase: false) == 5)
        #expect(d.search("alpha", from: 5, backward: true, ignoreCase: false) == 1)
        #expect(d.search("42", from: 0, backward: true, ignoreCase: false) == 6)
        // The starting node is checked last.
        #expect(d.search("beta", from: 2, backward: false, ignoreCase: false) == 2)
    }

    @Test func caseAndMisses() throws {
        let d = try doc(text)
        #expect(d.search("gamma", from: 0, backward: false, ignoreCase: false) == nil)
        #expect(d.search("gamma", from: 0, backward: false, ignoreCase: true) == 3)
        #expect(d.search("ALPHABET", from: 0, backward: false, ignoreCase: true) == 5)
        #expect(d.search("missing", from: 0, backward: false, ignoreCase: true) == nil)
        #expect(d.search("", from: 0, backward: false, ignoreCase: true) == nil)
        let escaped = try doc(#"["caf\u00e9", "CAFÉ"]"#)
        #expect(escaped.search("café", from: 0, backward: false, ignoreCase: false) == 1)
        #expect(escaped.search("café", from: 1, backward: false, ignoreCase: true) == 2)
        #expect(escaped.search("\n", from: 0, backward: false, ignoreCase: false) == nil)
    }

    @Test func virtualRootNeverMatches() throws {
        let d = try doc("\"x\"\n\"y\"", lines: true)
        #expect(d.search("x", from: 1, backward: false, ignoreCase: false) == 1)
        #expect(d.search("y", from: 0, backward: false, ignoreCase: false) == 2)
    }
}
