// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

@Suite struct ShellQuoteTests {
    @Test func quoting() {
        #expect(ShellQuote.quote("abc") == "abc")
        #expect(ShellQuote.quote("/a/b-c_d.e+f:g@h%i,j=k") == "/a/b-c_d.e+f:g@h%i,j=k")
        #expect(ShellQuote.quote("a b") == "'a b'")
        #expect(ShellQuote.quote("it's") == "'it'\\''s'")
        #expect(ShellQuote.quote("") == "''")
        #expect(ShellQuote.quote("čaj") == "'čaj'")
        #expect(ShellQuote.quote("$x;y") == "'$x;y'")
    }

    @Test func leadingExpansionCharacters() {
        // zsh turns a leading `=ls` into `/bin/ls`; `~` expands to a home folder.
        #expect(ShellQuote.quote("=ls") == "'=ls'")
        #expect(ShellQuote.quote("=") == "'='")
        #expect(ShellQuote.quote("a=b") == "a=b")
        #expect(ShellQuote.quote("~") == "'~'")
        #expect(ShellQuote.quote("~root") == "'~root'")
    }
}

@Suite struct ShellWordsTests {
    let home = URL(fileURLWithPath: "/Users/test")

    @Test func plainAndQuoted() {
        #expect(ShellWords.split("cd \"a b\"", home: home) == ["cd", "a b"])
        #expect(ShellWords.split("a\\ b c", home: home) == ["a b", "c"])
        #expect(ShellWords.split("'x\"y'", home: home) == ["x\"y"])
        #expect(ShellWords.split("\"a\\\"b\\\\c\\$d\"", home: home) == ["a\"b\\c$d"])
        #expect(ShellWords.split("  ", home: home) == [])
        #expect(ShellWords.split("\"\" x", home: home) == ["", "x"])
        #expect(ShellWords.split("a'b'\"c\"", home: home) == ["abc"])
    }

    @Test func tilde() {
        #expect(ShellWords.split("~/x", home: home) == ["/Users/test/x"])
        #expect(ShellWords.split("cd ~", home: home) == ["cd", "/Users/test"])
        #expect(ShellWords.split("\"~/x\"", home: home) == ["~/x"])
        #expect(ShellWords.split("a~b ~user", home: home) == ["a~b", "~user"])
    }

    @Test func rejected() {
        for line in ["a; b", "a | b", "a && b", "$HOME", "*.txt", "a?", "f[1]", "a > b", "\"unclosed",
                     "'unclosed", "trailing\\", "\"$HOME\"", "(x)"] {
            #expect(ShellWords.split(line, home: home) == nil, "\(line)")
        }
    }
}

@Suite struct CredentialsTests {
    @Test func scrubbing() {
        #expect(Credentials.scrub("ftp://joe:secret@host/x") == "ftp://joe@host/x")
        #expect(Credentials.scrub("sftp joe:pw@host") == "sftp joe@host")
        #expect(Credentials.scrub("cd ftp://joe:p@ss@host/x") == "cd ftp://joe@host/x")
    }

    @Test func unchanged() {
        for s in ["git clone git@github.com:a/b", "scp f user@host:/p", "https://host/a:b@c",
                  "plain text", "ftp://joe@host/x", "ls -la"] {
            #expect(Credentials.scrub(s) == s, "\(s)")
        }
    }
}

@Suite struct CommandHistoryTests {
    @Test func limitAndDuplicates() {
        var h = CommandHistory()
        for i in 0..<40 { h.add("cmd \(i)") }
        #expect(h.entries.count == CommandHistory.limit)
        #expect(h.entries.first == "cmd 39")
        #expect(h.entries.last == "cmd 10")
        h.add("cmd 20")
        #expect(h.entries.first == "cmd 20")
        #expect(h.entries.filter { $0 == "cmd 20" }.count == 1)
        #expect(h.entries.count == CommandHistory.limit)
    }

    @Test func emptyIgnoredAndTrimmed() {
        var h = CommandHistory()
        h.add("")
        h.add("  \n ")
        h.add("  ls  ")
        #expect(h.entries == ["ls"])
    }

    @Test func passwordNotStored() {
        var h = CommandHistory()
        h.add("cd ftp://joe:secret@host/x")
        #expect(h.entries == ["cd ftp://joe@host/x"])
    }

    @Test func codableRoundtrip() throws {
        var h = CommandHistory()
        h.add("a")
        h.add("b")
        let data = try JSONEncoder().encode(h)
        #expect(try JSONDecoder().decode(CommandHistory.self, from: data) == h)
    }
}

@Suite struct HistoryBrowserTests {
    @Test func browsing() {
        var h = CommandHistory()
        for c in ["one", "two", "three"] { h.add(c) }
        var b = HistoryBrowser(h)
        #expect(b.newer() == nil)
        #expect(b.older(current: "draft") == "three")
        #expect(b.older(current: "ignored") == "two")
        #expect(b.older(current: "") == "one")
        #expect(b.older(current: "") == nil)
        #expect(b.newer() == "two")
        #expect(b.newer() == "three")
        #expect(b.newer() == "draft")
        #expect(b.newer() == nil)
        #expect(b.older(current: "again") == "three")
    }

    @Test func emptyHistory() {
        var b = HistoryBrowser(CommandHistory())
        #expect(b.older(current: "x") == nil)
        #expect(b.newer() == nil)
    }
}

@Suite struct CommandInputTests {
    let dir = URL(fileURLWithPath: "/Users/test/work")
    let home = URL(fileURLWithPath: "/Users/test")

    func parse(_ line: String, existing: Set<String> = []) -> CommandLineAction {
        CommandInput.parse(line, in: dir, home: home, exists: { existing.contains($0.path) })
    }

    @Test func basics() {
        #expect(parse("") == .none)
        #expect(parse("   ") == .none)
        #expect(parse("cd") == .changeDirectory(home))
        #expect(parse("cd ..") == .changeDirectory(URL(fileURLWithPath: "/Users/test")))
        #expect(parse("cd ~/x") == .changeDirectory(URL(fileURLWithPath: "/Users/test/x")))
        #expect(parse("cd /usr/bin") == .changeDirectory(URL(fileURLWithPath: "/usr/bin")))
        #expect(parse("cd \"a b\"") == .changeDirectory(URL(fileURLWithPath: "/Users/test/work/a b")))
        #expect(parse("cd a\\ b") == .changeDirectory(URL(fileURLWithPath: "/Users/test/work/a b")))
        #expect(parse("cd -") == .back)
    }

    @Test func quotedTildeIsLiteral() {
        #expect(parse("cd \"~\"") == .changeDirectory(URL(fileURLWithPath: "/Users/test/work/~")))
    }

    @Test func runCases() {
        #expect(parse("cd a b") == .run("cd a b"))
        #expect(parse("cd x && make") == .run("cd x && make"))
        #expect(parse("ls -la") == .run("ls -la"))
        #expect(parse("  ls -la  ") == .run("ls -la"))
        #expect(parse("readme.txt") == .run("readme.txt"))
    }

    @Test func openExisting() {
        let existing: Set<String> = ["/Users/test/work/readme.txt", "/Users/test/work/a b.txt", "/etc/hosts"]
        #expect(parse("readme.txt", existing: existing) == .open(URL(fileURLWithPath: "/Users/test/work/readme.txt")))
        #expect(parse("a\\ b.txt", existing: existing) == .open(URL(fileURLWithPath: "/Users/test/work/a b.txt")))
        #expect(parse("/etc/hosts", existing: existing) == .open(URL(fileURLWithPath: "/etc/hosts")))
        #expect(parse("readme.txt x", existing: existing) == .run("readme.txt x"))
    }

    @Test func defaultExistsChecksFileSystem() {
        #expect(CommandInput.parse("/usr/bin", in: dir, home: home) == .open(URL(fileURLWithPath: "/usr/bin")))
        let missing = "/no/such/\(UUID().uuidString)"
        #expect(CommandInput.parse(missing, in: dir, home: home) == .run(missing))
    }

    @Test func tooLongPathInvalid() {
        let long = "/" + (0..<11).map { _ in String(repeating: "a", count: 99) }.joined(separator: "/")
        #expect(parse("cd \(long)") == .invalid(.tooLong))
        let name = String(repeating: "n", count: 256)
        #expect(parse("cd \(name)") == .invalid(.nameTooLong(name)))
    }
}

@Suite struct TerminalScriptTests {
    @Test func quotedContents() {
        let s = TerminalScript.contents(command: "echo 'hi'", directory: URL(fileURLWithPath: "/tmp/a b"))
        #expect(s.hasPrefix("#!/bin/sh\nrm -f -- \"$0\"\n"))
        #expect(s.contains("cd -- '/tmp/a b' || exit 1\n"))
        #expect(s.contains("-c 'echo '\\''hi'\\'''\n"))
        #expect(s.contains("printf '\\033[H\\033[2J\\033[3J%s\\n' '› echo '\\''hi'\\'''\n"))
        #expect(s.hasSuffix("exec \"${SHELL:-/bin/zsh}\" -l\n"))
    }
}

@Suite struct FilePropertiesTests {
    func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axolotl-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @Test func fileSymlinkAndDirectory() throws {
        try withTempDir { dir in
            let fm = FileManager.default
            let file = dir.appendingPathComponent("a.txt")
            try Data("hello".utf8).write(to: file)
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            let link = dir.appendingPathComponent("link")
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "a.txt")
            let sub = dir.appendingPathComponent("sub")
            try fm.createDirectory(at: sub, withIntermediateDirectories: false)
            let hidden = dir.appendingPathComponent(".hid")
            try Data().write(to: hidden)

            let f = try FileProperties.load(file)
            #expect(f.name == "a.txt")
            #expect(f.mode == 0o644)
            #expect(FileProperties.permissionsString(mode: f.mode, isDirectory: f.isDirectory, isSymlink: f.isSymlink)
                == "-rw-r--r--")
            #expect(f.size == 5)
            #expect(f.allocatedSize != nil)
            #expect(!f.isDirectory && !f.isSymlink && !f.isPackage && !f.isHidden && !f.isLocked)
            #expect(f.kind != nil)
            #expect(f.modified != nil && f.created != nil && f.accessed != nil)
            #expect(f.owner == NSUserName())

            let l = try FileProperties.load(link)
            #expect(l.isSymlink)
            #expect(!l.isDirectory)
            #expect(l.linkDestination == "a.txt")

            let d = try FileProperties.load(sub)
            #expect(d.isDirectory && !d.isPackage)
            #expect(d.size == nil)

            #expect(try FileProperties.load(hidden).isHidden)
        }
    }

    @Test func symlinkToDirectoryIsNotFollowed() throws {
        try withTempDir { dir in
            let sub = dir.appendingPathComponent("sub")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
            let link = dir.appendingPathComponent("dlink")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "sub")
            let l = try FileProperties.load(link)
            #expect(l.isSymlink && !l.isDirectory)
        }
    }

    @Test func missingThrows() throws {
        try withTempDir { dir in
            #expect(throws: (any Error).self) { try FileProperties.load(dir.appendingPathComponent("nope")) }
        }
    }

    @Test func permissionsStrings() {
        func p(_ m: Int, dir: Bool = false, link: Bool = false) -> String {
            FileProperties.permissionsString(mode: m, isDirectory: dir, isSymlink: link)
        }
        #expect(p(0o755, dir: true) == "drwxr-xr-x")
        #expect(p(0o755, link: true) == "lrwxr-xr-x")
        #expect(p(0o4755) == "-rwsr-xr-x")
        #expect(p(0o4644) == "-rwSr--r--")
        #expect(p(0o1777, dir: true) == "drwxrwxrwt")
        #expect(p(0o1776, dir: true) == "drwxrwxrwT")
        #expect(p(0o2755) == "-rwxr-sr-x")
        #expect(p(0o2644) == "-rw-r-Sr--")
        #expect(p(0) == "----------")
    }

    @Test func octalStrings() {
        #expect(FileProperties.octal(0o755) == "0755")
        #expect(FileProperties.octal(0o4755) == "4755")
        #expect(FileProperties.octal(0) == "0000")
        #expect(FileProperties.octal(0o644) == "0644")
    }
}
