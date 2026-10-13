// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

// Every document here is generated in memory.

private func format(_ text: String, lines: Bool = false) throws -> JSONFormatter.Output {
    try JSONFormatter.format(Data(text.utf8), lines: lines)
}

private func formatted(_ text: String) throws -> String { try format(text).text }

private func parseError(_ text: String) -> JSONParseError? {
    do {
        _ = try format(text)
        return nil
    } catch let error as JSONParseError {
        return error
    } catch {
        return nil
    }
}

@Suite struct JSONFormatterTests {
    @Test func scalarDocuments() throws {
        for text in [#""a\"b\u00e9""#, "1.50", "-0", "true", "false", "null", "{}", "[ ]"] {
            #expect(try formatted(" \(text) ") == (text == "[ ]" ? "[]" : text))
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
        let output = try format(text)
        #expect(output.text == expected)
        #expect(output.firstLineError == nil)
    }

    @Test func keyOrderAndDuplicatesAreKept() throws {
        #expect(try formatted(#"{"z":1,"a":2,"m":3,"a":4,"\u0061":5}"#)
                == "{\n  \"z\": 1,\n  \"a\": 2,\n  \"m\": 3,\n  \"a\": 4,\n  \"\\u0061\": 5\n}")
    }

    @Test func bigNumbersAreKeptExactly() throws {
        #expect(try formatted("[12345678901234567890.5, -0, 0.0e-0, 1E+400]")
                == "[\n  12345678901234567890.5,\n  -0,\n  0.0e-0,\n  1E+400\n]")
    }

    @Test func escapesAreKeptAsWritten() throws {
        let text = #"{"caf\u00e9 \ud83d\ude00": "\"q\" \\ \/ \b\f\n\r\t é😀", "raw é😀": "\ud83d x"}"#
        #expect(try formatted(text) == """
            {
              "caf\\u00e9 \\ud83d\\ude00": "\\"q\\" \\\\ \\/ \\b\\f\\n\\r\\t é😀",
              "raw é😀": "\\ud83d x"
            }
            """)
    }

    @Test func commentsAndTrailingCommasAreDropped() throws {
        let text = """
            // leading
            { /* a */ "a": [1, 2, /* x */ ], // end
              "b" /* before colon */ : {"c": 3,}, }
            /* trailing */
            """
        #expect(try formatted(text) == "{\n  \"a\": [\n    1,\n    2\n  ],\n  \"b\": {\n    \"c\": 3\n  }\n}")
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
            ("\u{FEFF}[x]", .init(line: 1, column: 2, reason: .unexpectedCharacter)),
            ("", .init(line: 1, column: 1, reason: .emptyDocument)),
            (" \n /* only */ \n", .init(line: 1, column: 1, reason: .emptyDocument)),
        ]
        for (text, expected) in cases {
            #expect(parseError(text) == expected, "\(text)")
        }
    }

    @Test func deepNestingIsCappedAndDoesNotRecurse() throws {
        let depth = 20_000
        let text = try formatted(String(repeating: "[", count: depth) + String(repeating: "]", count: depth))
        let rows = text.components(separatedBy: "\n")
        #expect(rows.count == depth * 2 - 1)
        #expect(rows.map { $0.prefix { $0 == " " }.count }.max() == JSONFormatter.maxIndentDepth * 2)
    }

    @Test func cancellation() {
        #expect(throws: CancellationError.self) {
            try JSONFormatter.format(Data("[1, 2]".utf8), lines: false, isCancelled: { true })
        }
        #expect(throws: CancellationError.self) {
            try JSONFormatter.format(Data("1\n2".utf8), lines: true, isCancelled: { true })
        }
    }

    @Test func largeGeneratedDocument() throws {
        // About 5 MB minified: 50 000 objects of 6 members each.
        var text = "["
        for i in 0..<50_000 {
            if i > 0 { text += "," }
            text += #"{"id":\#(i),"name":"item \#(i) with some padding text","tags":["a","b","c"],"#
            text += #""ok":true,"score":\#(i).25,"note":"lorem ipsum dolor sit amet consectetur"}"#
        }
        text += "]"
        #expect(text.utf8.count > 5_000_000)
        let result = try formatted(text)
        #expect(result.hasPrefix("[\n  {\n    \"id\": 0,\n    \"name\": \"item 0 with some padding text\","))
        #expect(result.hasSuffix("\"note\": \"lorem ipsum dolor sit amet consectetur\"\n  }\n]"))
        // Per object: braces 2, members 6, the tags array adds its closing bracket and 3 items.
        #expect(result.components(separatedBy: "\n").count == 2 + 50_000 * 12)
    }
}

@Suite struct JSONLinesFormatterTests {
    @Test func recordsOneAfterAnother() throws {
        let output = try format("{\"a\": [1]}\r\n\n   \n  42 \n{\"b\": tru}\n\"s\"\n// only a comment\n[]", lines: true)
        #expect(output.text == "{\n  \"a\": [\n    1\n  ]\n}\n42\n{\"b\": tru}\n\"s\"\n[]")
        #expect(output.firstLineError == JSONParseError(line: 5, column: 7, reason: .unexpectedCharacter))
    }

    @Test func badLinesKeepTheirText() throws {
        let output = try format("1 2\n{\"x\":\n/* open\n3", lines: true)
        #expect(output.text == "1 2\n{\"x\":\n/* open\n3")
        #expect(output.firstLineError == JSONParseError(line: 1, column: 3, reason: .trailingData))
    }

    @Test func emptyInput() throws {
        let output = try format("", lines: true)
        #expect(output.text == "")
        #expect(output.firstLineError == nil)
        #expect(try format("\n\n", lines: true).text == "")
    }
}
