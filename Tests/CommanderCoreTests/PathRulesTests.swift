import Testing
import Foundation
@testable import CommanderCore

@Suite struct PathRulesTests {
    let base = URL(fileURLWithPath: "/Users/test/work")

    @Test func emptyRejected() {
        #expect(throws: PathError.empty) { try PathRules.validate("") }
    }

    @Test func longPathRejectedNotTruncated() {
        let path = "/" + (0..<11).map { _ in String(repeating: "a", count: 99) }.joined(separator: "/")
        #expect(path.utf8.count > 1023)
        #expect(throws: PathError.tooLong) { try PathRules.validate(path) }
        #expect(throws: PathError.tooLong) { try PathRules.resolve(path, relativeTo: base) }
    }

    @Test func longNameRejected() {
        let name = String(repeating: "n", count: 256)
        #expect(throws: PathError.nameTooLong(name)) { try PathRules.validate("/tmp/" + name) }
        #expect(throws: Never.self) { try PathRules.validate("/tmp/" + String(repeating: "n", count: 255)) }
    }

    @Test func multiByteCountedInBytes() {
        let ok = String(repeating: "é", count: 127)   // 254 bytes
        let bad = String(repeating: "é", count: 128)  // 256 bytes, 128 characters
        #expect(throws: Never.self) { try PathRules.validate(ok) }
        #expect(throws: PathError.nameTooLong(bad)) { try PathRules.validate(bad) }
    }

    @Test func tildeExpansion() throws {
        #expect(try PathRules.resolve("~", relativeTo: base).path == URL(fileURLWithPath: NSHomeDirectory()).path)
        #expect(try PathRules.resolve("~/Documents", relativeTo: base).path == NSHomeDirectory() + "/Documents")
    }

    @Test func relativeAndDotDot() throws {
        #expect(try PathRules.resolve("sub/../other/./x", relativeTo: base).path == "/Users/test/work/other/x")
        #expect(try PathRules.resolve("../..", relativeTo: base).path == "/Users")
        #expect(try PathRules.resolve("/a//b/../c", relativeTo: base).path == "/a/c")
        #expect(try PathRules.resolve("../../../../..", relativeTo: base).path == "/")
    }
}
