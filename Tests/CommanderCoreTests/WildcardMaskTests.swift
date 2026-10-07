import Testing
@testable import CommanderCore

@Suite struct WildcardMaskTests {
    private func m(_ p: String, _ n: String) -> Bool { WildcardMask(p).matches(n) }

    @Test func helpPageExamples() {
        #expect(m("*.doc", "letter.doc"))
        #expect(m("*.doc", "a.b.doc"))
        #expect(!m("*.doc", "letter.docx"))
        #expect(m("readme.*", "readme.txt"))
        #expect(m("readme.*", "README.md"))
        #expect(m("readme.???", "readme.htm"))
        #expect(!m("readme.???", "readme.html"))
        #expect(m("*.a?", ".a1"))
        #expect(m("*.a?", "anything.ai"))
        #expect(!m("*.a?", "x.abc"))
    }

    @Test func multipleMasks() {
        #expect(m("*.txt;*.doc", "a.txt"))
        #expect(m("*.txt;*.doc", "b.doc"))
        #expect(!m("*.txt;*.doc", "c.pdf"))
        #expect(m("one;;mask", "one;mask"))
        #expect(!m("one;;mask", "one"))
    }

    @Test func exclusion() {
        #expect(!m("|*.txt;*.doc", "a.txt"))
        #expect(!m("|*.txt;*.doc", "a.doc"))
        #expect(m("|*.txt;*.doc", "a.pdf"))
        #expect(m("*.swift|*Tests*", "Panel.swift"))
        #expect(!m("*.swift|*Tests*", "PanelTests.swift"))
    }

    @Test func starDotStarMatchesNamesWithoutExtension() {
        #expect(m("*.*", "Makefile"))
        #expect(m("*.*", "a.txt"))
        #expect(m("*.*", ".hidden"))
        #expect(m("readme.*", "readme"))
        #expect(!m("readme.???", "readme"))
    }

    @Test func plainPatternMatchesWholeName() {
        #expect(m("txt", "txt"))
        #expect(!m("txt", "a.txt"))
        #expect(!m("txt?", "txt"))
        #expect(m("txt?", "txt1"))
    }

    @Test func caseAndNormalization() {
        #expect(m("*.TXT", "a.txt"))
        #expect(!WildcardMask("*.TXT").matches("a.txt", rules: NameRules(caseSensitive: true)))
        #expect(m("\u{E9}*", "e\u{301}clair"))  // NFC pattern vs NFD name
        #expect(m("e\u{301}*", "\u{E9}clair"))
    }
}
