import Testing
import Foundation
@testable import CommanderCore

@Suite struct NameRulesTests {
    @Test func normalizationInsensitive() {
        let r = NameRules.apfsDefault
        #expect(r.same("\u{E9}", "e\u{301}"))
        #expect(NameRules(caseSensitive: true).same("\u{E9}", "e\u{301}"))
        #expect(r.key("e\u{301}") == "\u{E9}")
    }

    @Test func caseHandling() {
        #expect(NameRules.apfsDefault.same("Readme.TXT", "readme.txt"))
        #expect(!NameRules(caseSensitive: true).same("Readme", "readme"))
    }

    @Test func naturalOrder() {
        let r = NameRules.apfsDefault
        #expect(r.order("file2", "file10") == .orderedAscending)
        #expect(r.order("File2", "file10") == .orderedAscending)
        #expect(r.order("b", "A") == .orderedDescending)
        #expect(r.order("a", "a") == .orderedSame)
        // Deterministic tie-break between names equal under folding.
        #expect(r.order("a", "A") != .orderedSame)
        #expect(r.order("a", "A") == (r.order("A", "a") == .orderedAscending ? .orderedDescending : .orderedAscending))
    }

    @Test func volumeRulesDefaultForMissingPath() {
        _ = NameRules.forVolume(containing: URL(fileURLWithPath: "/definitely/not/here"))
        #expect(!NameRules.forVolume(containing: URL(fileURLWithPath: "/")).caseSensitive)
    }
}
