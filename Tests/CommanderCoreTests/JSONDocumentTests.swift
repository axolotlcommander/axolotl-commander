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

private extension JSONDocument {
    func kids(_ node: Int) -> [Int] {
        var result: [Int] = []
        var child = nodes[node].firstChild
        while child >= 0 {
            result.append(child)
            child = nodes[child].nextSibling
        }
        return result
    }

    /// The key token without its quotes, as written.
    func key(_ node: Int) -> String? {
        nodes[node].key.map { String(decoding: bytes[($0.lowerBound + 1)..<($0.upperBound - 1)], as: UTF8.self) }
    }

    /// The value text as written.
    func raw(_ node: Int) -> String { String(decoding: bytes[nodes[node].value], as: UTF8.self) }
}

/// The node reached by following keys (objects) or indices (arrays) from the root.
private func node(_ d: JSONDocument, _ steps: Any...) -> Int {
    var current = 0
    for step in steps {
        let kids = d.kids(current)
        if let key = step as? String {
            current = kids.first { d.key($0) == key }!
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
        #expect(d.raw(node(d, "n")) == "-1.5e3")
        #expect(d.raw(node(d, "s")) == #""x""#)
        #expect(d.raw(node(d, "t")) == "true")
        #expect(d.raw(node(d, "z")) == "null")
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
        #expect(d.kids(0) == [1, 5])
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

    @Test func keyOrderKeepsDuplicates() throws {
        let d = try doc(#"{"z": 1, "a": 2, "m": 3, "a": 4, "\u0061": 5}"#)
        #expect(d.kids(0).map { d.key($0)! } == ["z", "a", "m", "a", "\\u0061"])
        #expect(d.kids(0).map { d.raw($0) } == ["1", "2", "3", "4", "5"])
    }

    @Test func bigNumberKeptExactly() throws {
        let d = try doc(#"[12345678901234567890.5, -0, 0.0e-0, 1E+400]"#)
        #expect(d.kids(0).map { d.raw($0) } == ["12345678901234567890.5", "-0", "0.0e-0", "1E+400"])
        #expect(d.formatted() == "[\n  12345678901234567890.5,\n  -0,\n  0.0e-0,\n  1E+400\n]")
    }

    @Test func escapesAreKeptAsWritten() throws {
        let text = #"{"caf\u00e9 \ud83d\ude00": "\"q\" \\ \/ \b\f\n\r\t é😀", "raw é😀": "\ud83d x"}"#
        let d = try doc(text)
        #expect(d.key(node(d, 0)) == #"caf\u00e9 \ud83d\ude00"#)
        #expect(d.formatted() == """
            {
              "caf\\u00e9 \\ud83d\\ude00": "\\"q\\" \\\\ \\/ \\b\\f\\n\\r\\t é😀",
              "raw é😀": "\\ud83d x"
            }
            """)
    }

    @Test func commentsAndTrailingCommas() throws {
        let text = """
            // leading
            { /* a */ "a": [1, 2, /* x */ ], // end
              "b" /* before colon */ : {"c": 3,}, }
            /* trailing */
            """
        let d = try doc(text)
        #expect(d.kids(0).count == 2)
        #expect(d.kids(node(d, "a")).count == 2)
        #expect(d.nodes[node(d, "b", "c")].line == 3)
    }

    @Test func byteOrderMarkIsSkipped() throws {
        let d = try JSONDocument.parse(Data([0xEF, 0xBB, 0xBF] + Array(#"{"a":1}"#.utf8)), lines: false)
        #expect(d.bytes.first == 0x7B)
        #expect(d.nodes[0].column == 1)
        #expect(d.key(1) == "a")
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
        #expect(d.formatted().hasPrefix("[\n  {\n    \"id\": 0,\n    \"name\": \"item 0 with some padding text\","))
    }
}

@Suite struct JSONLinesTests {
    @Test func linesWithABadLine() throws {
        let text = "{\"a\": 1}\r\n\n   \n[1, 2]\n{\"b\": tru}\n\"s\"\n// only a comment\n42"
        let d = try doc(text, lines: true)
        #expect(d.isLines)
        let root = d.nodes[0]
        #expect(root.kind == .array && root.value == 0..<d.bytes.count && root.line == 1 && root.column == 1)
        let lines = d.kids(0)
        #expect(lines.map { d.nodes[$0].kind } == [.object, .array, .error, .string, .number])
        #expect(lines.map { d.nodes[$0].index } == [0, 1, 2, 3, 4])
        #expect(lines.map { d.nodes[$0].line } == [1, 4, 5, 6, 8])
        let bad = d.nodes[lines[2]]
        #expect(bad.error == JSONParseError(line: 5, column: 7, reason: .unexpectedCharacter))
        #expect(d.raw(lines[2]) == "{\"b\": tru}")
        #expect(d.firstLineError == JSONParseError(line: 5, column: 7, reason: .unexpectedCharacter))
        #expect(String(decoding: d.bytes[d.nodes[lines[0]].value], as: UTF8.self) == "{\"a\": 1}")
        #expect(d.nodes[node(d, 1, 1)].line == 4 && d.nodes[node(d, 1, 1)].column == 5)
        #expect(root.childCount == 5)
    }

    @Test func emptyAndTrailingData() throws {
        #expect(try doc("", lines: true).nodes.count == 1)
        let d = try doc("1 2\n{\"x\":", lines: true)
        let errors = d.kids(0).map { d.nodes[$0].error }
        #expect(errors == [JSONParseError(line: 1, column: 3, reason: .trailingData),
                           JSONParseError(line: 2, column: 6, reason: .unexpectedEnd)])
    }
}

@Suite struct JSONFormattingTests {
    @Test func scalarDocuments() throws {
        for text in [#""a\"b\u00e9""#, "1.50", "true", "null", "{}", "[ ]"] {
            #expect(try doc(" \(text) ").formatted() == (text == "[ ]" ? "[]" : text))
        }
    }

    @Test func containersAreIndented() throws {
        let text = """
            \u{FEFF}{"b": [1, "x\\u0041\\"", {}, [], {"n": null}], // note
             /* c */ "a": {"z": 2.0e1, "t": "tab\\tq",}, "e": [ ],
             "dup": 1, "dup": 2}
            """
        let expected = """
            {
              "b": [
                1,
                "x\\u0041\\"",
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
        #expect(try doc(text).formatted() == expected)
        #expect(try doc(text).firstLineError == nil)
    }

    @Test func linesAreFormattedOneAfterAnother() throws {
        let d = try doc("{\"a\": [1]}\n\n  42 \n{\"b\": tru}\n[]", lines: true)
        #expect(d.formatted() == "{\n  \"a\": [\n    1\n  ]\n}\n42\n{\"b\": tru}\n[]")
        #expect(d.firstLineError == JSONParseError(line: 4, column: 7, reason: .unexpectedCharacter))
        #expect(try doc("", lines: true).formatted() == "")
    }

    @Test func deepIndentationIsCapped() throws {
        let depth = JSONDocument.maxIndentDepth + 10
        let text = try doc(String(repeating: "[", count: depth) + String(repeating: "]", count: depth)).formatted()
        let rows = text.components(separatedBy: "\n")
        #expect(rows.map { $0.prefix { $0 == " " }.count }.max() == JSONDocument.maxIndentDepth * 2)
        #expect(rows.count == depth * 2 - 1)
    }
}
