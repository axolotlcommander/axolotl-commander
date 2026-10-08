// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

/// A span rendered as its text and kind, for readable expectations.
private struct Tok: Equatable, CustomStringConvertible {
    let text: String
    let kind: SyntaxTokenKind
    var description: String { "\(kind):\(text.debugDescription)" }
}

private func tok(_ text: String, _ kind: SyntaxTokenKind) -> Tok { Tok(text: text, kind: kind) }

private func language(_ id: String) -> SyntaxLanguage {
    SyntaxLanguage.all.first { $0.id == id }!
}

private func spans(_ text: String, _ id: String) -> [SyntaxSpan] {
    SyntaxHighlighter.spans(in: text, language: language(id))
}

private func tokens(_ text: String, _ id: String) -> [Tok] {
    let ns = text as NSString
    return spans(text, id).map { Tok(text: ns.substring(with: $0.range), kind: $0.kind) }
}

/// Spans are non-empty, inside the text, sorted and non-overlapping.
private func isWellFormed(_ spans: [SyntaxSpan], length: Int) -> Bool {
    var end = 0
    for s in spans {
        if s.range.length <= 0 || s.range.location < end || NSMaxRange(s.range) > length { return false }
        end = NSMaxRange(s.range)
    }
    return true
}

@Suite struct SyntaxHighlighterTests {
    // MARK: Language lookup

    @Test func lookupByExtension() {
        #expect(SyntaxLanguage.forFile(named: "main.swift")?.id == "swift")
        #expect(SyntaxLanguage.forFile(named: "a.h")?.id == "c")
        #expect(SyntaxLanguage.forFile(named: "a.hpp")?.id == "cpp")
        #expect(SyntaxLanguage.forFile(named: "page.xhtml")?.id == "html")
        #expect(SyntaxLanguage.forFile(named: "Info.plist")?.id == "xml")
        #expect(SyntaxLanguage.forFile(named: "Localizable.xcstrings")?.id == "json")
        #expect(SyntaxLanguage.forFile(named: "x.tar.sh")?.id == "shell")
        #expect(SyntaxLanguage.forFile(named: "/some/dir/readme.md")?.id == "markdown")
    }

    @Test func lookupIsCaseInsensitive() {
        #expect(SyntaxLanguage.forFile(named: "MAIN.CPP")?.id == "cpp")
        #expect(SyntaxLanguage.forFile(named: "Script.Ps1")?.id == "powershell")
        #expect(SyntaxLanguage.forFile(named: "MAKEFILE")?.id == "makefile")
    }

    @Test func lookupByFullName() {
        #expect(SyntaxLanguage.forFile(named: "Makefile")?.id == "makefile")
        #expect(SyntaxLanguage.forFile(named: "GNUmakefile")?.id == "makefile")
        #expect(SyntaxLanguage.forFile(named: "Dockerfile")?.id == "dockerfile")
        #expect(SyntaxLanguage.forFile(named: "Dockerfile.dev")?.id == "dockerfile")
        #expect(SyntaxLanguage.forFile(named: "CMakeLists.txt")?.id == "cmake")
        #expect(SyntaxLanguage.forFile(named: ".bashrc")?.id == "shell")
        #expect(SyntaxLanguage.forFile(named: ".zshrc")?.id == "shell")
        #expect(SyntaxLanguage.forFile(named: "Gemfile")?.id == "ruby")
        #expect(SyntaxLanguage.forFile(named: "Podfile")?.id == "ruby")
        #expect(SyntaxLanguage.forFile(named: "Package.swift")?.id == "swift")
        #expect(SyntaxLanguage.forFile(named: ".gitconfig")?.id == "ini")
    }

    @Test func unknownAndPlainTextAreNil() {
        for name in ["notes.txt", "app.log", "README", "archive.zip", "trailing.", "", ".gitignore"] {
            #expect(SyntaxLanguage.forFile(named: name) == nil, "\(name)")
        }
    }

    @Test func allLanguagesSortedWithUniqueIDs() {
        let all = SyntaxLanguage.all
        let names = all.map { $0.name.lowercased() }
        #expect(names == names.sorted())
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(all.count >= 37)
    }

    // MARK: C-like basics

    @Test func swiftKeywordsVsIdentifiers() {
        #expect(tokens("let classy = class_x", "swift") == [tok("let", .keyword)])
        #expect(tokens("if x { return }", "swift") == [tok("if", .keyword), tok("return", .keyword)])
        #expect(tokens("let n: Int = 1", "swift") == [tok("let", .keyword), tok("Int", .type), tok("1", .number)])
        #expect(tokens("obj.default.class", "swift").isEmpty)
    }

    @Test func stringsWithEscapedQuotes() {
        #expect(tokens(#"let s = "a \"b\" c" + x"#, "swift") == [tok("let", .keyword), tok(#""a \"b\" c""#, .string)])
        #expect(tokens(#"char c = '\'';"#, "c") == [tok("char", .type), tok(#"'\''"#, .string)])
    }

    @Test func commentMarkerInsideStringIsNotComment() {
        #expect(tokens(#"s = "http://x.y" // real"#, "javascript") == [tok(#""http://x.y""#, .string), tok("// real", .comment)])
    }

    @Test func blockCommentAcrossLines() {
        let t = tokens("a /* one\ntwo */ b // tail\nc", "c")
        #expect(t == [tok("/* one\ntwo */", .comment), tok("// tail", .comment)])
        #expect(tokens("x /* never closed\nmore", "c") == [tok("/* never closed\nmore", .comment)])
    }

    @Test func nestedBlockCommentsOnlyInSwiftAndRust() {
        #expect(tokens("/* a /* b */ c */ d", "swift") == [tok("/* a /* b */ c */", .comment)])
        #expect(tokens("/* a /* b */ c */ d", "rust") == [tok("/* a /* b */ c */", .comment)])
        #expect(tokens("/* a /* b */ c */", "c") == [tok("/* a /* b */", .comment)])
    }

    @Test func numbers() {
        #expect(tokens("0xFF 1_000 1.5e-3 0b101 0o17 42u 3.14f", "swift")
            == ["0xFF", "1_000", "1.5e-3", "0b101", "0o17", "42u", "3.14f"].map { tok($0, .number) })
        #expect(tokens("x = 1..5", "swift") == [tok("1", .number), tok("5", .number)])
    }

    @Test func numbersInsideIdentifiersAreNotNumbers() {
        #expect(tokens("abc123 + _9 + x1y2", "c").isEmpty)
        #expect(tokens("v2 = 7", "python") == [tok("7", .number)])
    }

    @Test func cPreprocessorLine() {
        let t = tokens("  #include <stdio.h>\nint x; // c\n#define M(a) \\\n  a+1\nreturn;", "c")
        #expect(t == [
            tok("#include <stdio.h>", .preprocessor), tok("int", .type), tok("// c", .comment),
            tok("#define M(a) \\\n  a+1", .preprocessor), tok("return", .keyword),
        ])
    }

    @Test func swiftHashDirectivesAndAttributes() {
        let t = tokens("#if DEBUG\n@MainActor func f() {}\n#endif", "swift")
        #expect(t == [tok("#if", .preprocessor), tok("@MainActor", .preprocessor), tok("func", .keyword), tok("#endif", .preprocessor)])
        #expect(tokens(##"let r = #"a "quoted" \n"#"##, "swift") == [tok("let", .keyword), tok(##"#"a "quoted" \n"#"##, .string)])
    }

    @Test func rustLifetimesAreNotStrings() {
        let t = tokens("fn f<'a>(x: &'a str) -> char { 'x' }", "rust")
        #expect(t == [
            tok("fn", .keyword), tok("'a", .type), tok("'a", .type), tok("str", .type),
            tok("char", .type), tok("'x'", .string),
        ])
        #expect(tokens(##"let s = r#"raw "q" text"#;"##, "rust") == [tok("let", .keyword), tok(##"r#"raw "q" text"#"##, .string)])
    }

    @Test func csharpVerbatimString() {
        #expect(tokens("var p = @\"C:\\dir\\\"\"x\";", "csharp") == [tok("var", .keyword), tok("@\"C:\\dir\\\"\"x\"", .string)])
    }

    // MARK: Scripting languages

    @Test func pythonTripleQuotedStringAndDecorator() {
        let t = tokens("@app.route\ndef f():\n    \"\"\"doc\n    more\"\"\"\n    return rb'x'  # c", "python")
        #expect(t == [
            tok("@app.route", .preprocessor), tok("def", .keyword), tok("\"\"\"doc\n    more\"\"\"", .string),
            tok("return", .keyword), tok("rb'x'", .string), tok("# c", .comment),
        ])
        #expect(tokens("a @ b", "python").isEmpty)
    }

    @Test func shellVariablesAndComments() {
        let t = tokens("echo $HOME ${PATH} a#b # real\nx='$no' y=\"q\\\"r\"", "shell")
        #expect(t == [
            tok("echo", .keyword), tok("$HOME", .variable), tok("${PATH}", .variable), tok("# real", .comment),
            tok("'$no'", .string), tok("\"q\\\"r\"", .string),
        ])
        #expect(tokens("n=$# m=$(date)", "shell") == [tok("$#", .variable)])
    }

    @Test func luaBlockComments() {
        let t = tokens("--[[ multi\nline ]] x = 1 -- tail\n--[==[ a ]] b ]==] y", "lua")
        #expect(t == [tok("--[[ multi\nline ]]", .comment), tok("1", .number), tok("-- tail", .comment), tok("--[==[ a ]] b ]==]", .comment)])
    }

    @Test func sqlCaseInsensitiveAndDoubledQuote() {
        let t = tokens("SeLeCt 'it''s' FROM t -- c\n/* b */", "sql")
        #expect(t == [tok("SeLeCt", .keyword), tok("'it''s'", .string), tok("FROM", .keyword), tok("-- c", .comment), tok("/* b */", .comment)])
    }

    @Test func pascalBracesAndDirectives() {
        let t = tokens("{ c } (* d *) // e\nBEGIN {$IFDEF X} s := 'a''b'; End.", "pascal")
        #expect(t == [
            tok("{ c }", .comment), tok("(* d *)", .comment), tok("// e", .comment), tok("BEGIN", .keyword),
            tok("{$IFDEF X}", .preprocessor), tok("'a''b'", .string), tok("End", .keyword),
        ])
    }

    @Test func batchCommentsAndVariables() {
        let t = tokens("@REM hello\n:: other\nset X=%PATH% %~dp0 %%i\nrem x", "batch")
        #expect(t == [
            tok("REM hello", .comment), tok(":: other", .comment), tok("set", .keyword), tok("%PATH%", .variable),
            tok("%~dp0", .variable), tok("%%i", .variable), tok("rem x", .comment),
        ])
    }

    @Test func makefileTargetsAndVariables() {
        let t = tokens("CC := gcc\nall: $(OBJ) # c\n\t$(CC) -o $@ $<\n.PHONY: all", "makefile")
        #expect(t == [
            tok("all", .attribute), tok("$(OBJ)", .variable), tok("# c", .comment),
            tok("$(CC)", .variable), tok("$@", .variable), tok("$<", .variable), tok(".PHONY", .attribute),
        ])
    }

    @Test func dockerfileInstructionsAreCaseInsensitive() {
        let t = tokens("FROM x AS b\nrun echo $V # not a comment\n# real", "dockerfile")
        #expect(t == [tok("FROM", .keyword), tok("AS", .keyword), tok("run", .keyword), tok("$V", .variable), tok("# real", .comment)])
    }

    // MARK: Data and markup formats

    @Test func jsonKeysAndValues() {
        let t = tokens("{\"k\" : \"v\", \"n\": -1.5e3, \"b\": [true, null]}", "json")
        #expect(t == [
            tok("\"k\"", .attribute), tok("\"v\"", .string), tok("\"n\"", .attribute), tok("-1.5e3", .number),
            tok("\"b\"", .attribute), tok("true", .keyword), tok("null", .keyword),
        ])
    }

    @Test func htmlTagsAttributesCommentsAndDoctype() {
        let t = tokens("<!DOCTYPE html><a href=\"x\" id=y>t &amp; <!-- c --></a><br/>", "html")
        #expect(t == [
            tok("<!DOCTYPE html>", .preprocessor), tok("<a", .tag), tok("href", .attribute), tok("\"x\"", .string),
            tok("id", .attribute), tok("y", .string), tok(">", .tag), tok("&amp;", .keyword), tok("<!-- c -->", .comment),
            tok("</a", .tag), tok(">", .tag), tok("<br", .tag), tok("/>", .tag),
        ])
    }

    @Test func htmlEmbedsScriptAndStyle() {
        let t = tokens("<script>var x = 1; // c\n</script><style>a { color: red }</style>", "html")
        #expect(t.contains(tok("var", .keyword)))
        #expect(t.contains(tok("// c", .comment)))
        #expect(t.contains(tok("color", .attribute)))
        #expect(t.contains(tok("</script", .tag)))
    }

    @Test func xmlProcessingInstructionAndCData() {
        let t = tokens("<?xml version=\"1.0\"?>\n<a:b k='v'><![CDATA[x < y]]></a:b>", "xml")
        #expect(t == [
            tok("<?xml version=\"1.0\"?>", .preprocessor), tok("<a:b", .tag), tok("k", .attribute), tok("'v'", .string),
            tok(">", .tag), tok("<![CDATA[x < y]]>", .string), tok("</a:b", .tag), tok(">", .tag),
        ])
    }

    @Test func cssPropertiesNumbersAndAtRules() {
        let t = tokens("@media (min-width: 600px) {\n a:hover { color: #fff; margin: -1.5em 50% }\n /* c */ }", "css")
        #expect(t == [
            tok("@media", .preprocessor), tok("600px", .number), tok("color", .attribute), tok("#fff", .number),
            tok("margin", .attribute), tok("-1.5em", .number), tok("50%", .number), tok("/* c */", .comment),
        ])
    }

    @Test func yamlKeysCommentsAndLiterals() {
        let t = tokens("---\nname: \"x\" # c\nlist:\n  - true\n  - 12\n  - key: no\ntext: |\n  # not comment\nend: ~", "yaml")
        #expect(t == [
            tok("---", .preprocessor), tok("name", .attribute), tok("\"x\"", .string), tok("# c", .comment),
            tok("list", .attribute), tok("true", .keyword), tok("12", .number), tok("key", .attribute), tok("no", .keyword),
            tok("text", .attribute), tok("end", .attribute), tok("~", .keyword),
        ])
    }

    @Test func iniSectionsKeysAndComments() {
        let t = tokens("; c\n[core]\nname = \"x\" # tail\nport=8080\nflag = true", "ini")
        #expect(t == [
            tok("; c", .comment), tok("[core]", .tag), tok("name", .attribute), tok("\"x\"", .string), tok("# tail", .comment),
            tok("port", .attribute), tok("8080", .number), tok("flag", .attribute), tok("true", .keyword),
        ])
    }

    @Test func markdownHeadingsCodeAndLinks() {
        let t = tokens("# Title\nsome `code` and [t](http://u)\n```swift\nlet x # y\n```\nafter", "markdown")
        #expect(t == [
            tok("# Title", .keyword), tok("`code`", .string), tok("http://u", .attribute),
            tok("```swift", .string), tok("let x # y", .string), tok("```", .string),
        ])
    }

    @Test func diffLines() {
        let text = "diff --git a/f b/f\nindex 1..2 100644\n--- a/f\n+++ b/f\n@@ -1,2 +1,2 @@\n ctx\n-old\n+new\n--- not header\n"
        let t = tokens(text, "diff")
        #expect(t == [
            tok("diff --git a/f b/f", .comment), tok("index 1..2 100644", .comment), tok("--- a/f", .comment),
            tok("+++ b/f", .comment), tok("@@ -1,2 +1,2 @@", .preprocessor), tok("-old", .keyword),
            tok("+new", .type), tok("--- not header", .keyword),
        ])
    }

    // MARK: Offsets, robustness

    @Test func utf16OffsetsAfterDiacriticsAndEmoji() {
        let text = "let s = \"žluťoučký 😀\" // ok"
        let ns = text as NSString
        let result = spans(text, "swift")
        #expect(result.count == 3)
        let comment = result.last!
        #expect(comment.kind == .comment)
        #expect(comment.range == ns.range(of: "// ok"))
        #expect(ns.substring(with: result[1].range) == "\"žluťoučký 😀\"")
        #expect(isWellFormed(result, length: ns.length))
    }

    @Test func emojiInIdentifiersAndMarkupKeepOffsets() {
        let text = "😀<b a=\"é😀\">&amp;"
        let ns = text as NSString
        let result = spans(text, "html")
        #expect(isWellFormed(result, length: ns.length))
        #expect(result.last.map { ns.substring(with: $0.range) } == "&amp;")
    }

    @Test func unterminatedStringEndsAtLineEnd() {
        #expect(tokens("x = \"abc\ny = 1", "swift") == [tok("\"abc", .string), tok("1", .number)])
        #expect(tokens("x = 'abc\r\ny = 1", "python") == [tok("'abc", .string), tok("1", .number)])
        // Multi-line delimiters run to the end of the text.
        #expect(tokens("`abc\ndef", "javascript") == [tok("`abc\ndef", .string)])
        #expect(tokens("\"\"\"abc\ndef", "python") == [tok("\"\"\"abc\ndef", .string)])
    }

    @Test func crlfLineEndings() {
        #expect(tokens("// a\r\nint x;\r\n// b\r\n", "c") == [tok("// a", .comment), tok("int", .type), tok("// b", .comment)])
        #expect(tokens("a: 1\r\n# c\r\nb: yes\r\n", "yaml")
            == [tok("a", .attribute), tok("1", .number), tok("# c", .comment), tok("b", .attribute), tok("yes", .keyword)])
    }

    @Test func largeSourceTokenizesWithValidSpans() {
        let line = "#include <x.h>\nstatic int f(int a) { return a * 0x10 + 3; } // \"c\" ž😀\nconst char *s = \"str\\\"ing\"; /* b */\n"
        let text = String(repeating: line, count: 1_000_000 / line.utf16.count + 1)
        let ns = text as NSString
        let result = spans(text, "c")
        #expect(result.count > 100_000)
        #expect(isWellFormed(result, length: ns.length))
    }

    @Test func everyLanguageProducesValidSpansOnMixedInput() {
        let sample = """
        #!/bin/sh
        <a href="x"> /* c */ // d -- e
        "str \\" 'q' `b` @attr $var ${v} %v% {-n-} (* p *) [[ l ]] --[[ m ]]
        key: value = 1.5e3 0xFF 😀 ž
        ```
        +x -y @@ :: rem
        """
        let length = (sample as NSString).length
        for lang in SyntaxLanguage.all {
            let r = SyntaxHighlighter.spans(in: sample, language: lang)
            #expect(isWellFormed(r, length: length), "\(lang.id)")
            #expect(SyntaxHighlighter.spans(in: "", language: lang).isEmpty)
            for cut in stride(from: 1, to: length, by: 7) {
                let part = (sample as NSString).substring(to: cut)
                #expect(isWellFormed(SyntaxHighlighter.spans(in: part, language: lang), length: (part as NSString).length), "\(lang.id) \(cut)")
            }
        }
    }
}
