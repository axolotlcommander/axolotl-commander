import Foundation
import Testing
@testable import CommanderCore

@Suite struct UserMenuTests {
    private static func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    private func context(cursor: String? = "/work/a/notes.final.txt", selected: [String] = [],
                         env: [String: String] = [:]) -> UserMenuContext {
        UserMenuContext(
            activeDirectory: Self.url("/work/a/"), inactiveDirectory: Self.url("/work/b"),
            leftDirectory: Self.url("/work/left"), rightDirectory: Self.url("/work/right"),
            cursor: cursor.map(Self.url), selected: selected.map(Self.url),
            leftCursor: Self.url("/work/left/l.txt"), rightCursor: Self.url("/work/right/r.txt"),
            environment: env, home: Self.url("/Users/test"))
    }

    private func item(_ program: String = "/bin/echo", arguments: String = "",
                      directory: String = "$(FullPath)") -> UserMenuItem {
        UserMenuItem(title: "t", program: program, arguments: arguments, directory: directory)
    }

    private func args(_ arguments: String, _ ctx: UserMenuContext? = nil) throws -> [String] {
        let invocations = try UserMenuExpander.invocations(for: item(arguments: arguments), in: ctx ?? context())
        #expect(invocations.count == 1)
        return invocations.first?.arguments ?? []
    }

    @Test func perFileVariables() throws {
        #expect(try args("$(FullName) $(Name) $(NamePart) $(ExtPart)")
            == ["/work/a/notes.final.txt", "notes.final.txt", "notes.final", "txt"])
    }

    @Test func directoryVariables() throws {
        #expect(try args("$(FullPath) $(FullPathInactive) $(FullPathLeft) $(FullPathRight)")
            == ["/work/a", "/work/b", "/work/left", "/work/right"])
        #expect(try args("$(FileToCompareLeft) $(FileToCompareRight)") == ["/work/left/l.txt", "/work/right/r.txt"])
    }

    @Test func variableNamesAreCaseInsensitive() throws {
        #expect(try args("$(fullname) $(NAMEPART)") == ["/work/a/notes.final.txt", "notes.final"])
    }

    @Test func extensionEdgeCases() throws {
        let hidden = context(cursor: "/work/a/.bashrc")
        #expect(try args("$(NamePart) $(ExtPart)", hidden) == [".bashrc", ""])
        let plain = context(cursor: "/work/a/Makefile")
        #expect(try args("$(NamePart) $(ExtPart)", plain) == ["Makefile", ""])
    }

    @Test func nastyNamesAreNeverResplit() throws {
        let nasty = "/work/a/it's a \"$HOME\" `x`; *.txt"
        let ctx = context(cursor: nasty)
        let result = try args("--file $(FullName) -n=$(Name) '$(Name)' \"$(Name)\"", ctx)
        #expect(result == ["--file", nasty, "-n=it's a \"$HOME\" `x`; *.txt",
                           "it's a \"$HOME\" `x`; *.txt", "it's a \"$HOME\" `x`; *.txt"])
    }

    @Test func spacesInDirectoryAndPrivateUseNames() throws {
        let ctx = context(cursor: "/work/a/\u{E000}x \u{E001}")
        #expect(try args("$(Name) \u{E000}", ctx) == ["\u{E000}x \u{E001}", "\u{E000}"])
    }

    @Test func listVariableAsWholeWordExpandsToManyArguments() throws {
        let ctx = context(selected: ["/work/a/one two", "/work/a/three"])
        #expect(try args("-a TextEdit $(ListOfSelectedFullNames)", ctx) == ["-a", "TextEdit", "/work/a/one two", "/work/a/three"])
        #expect(try args("$(ListOfSelectedNames)", ctx) == ["one two", "three"])
    }

    @Test func listVariableInsideWordJoinsWithSpaces() throws {
        let ctx = context(selected: ["/work/a/one two", "/work/a/three"])
        #expect(try args("--files=$(ListOfSelectedNames)", ctx) == ["--files=one two three"])
        #expect(try args("\"x $(ListOfSelectedNames)\"", ctx) == ["x one two three"])
    }

    @Test func listVariableFallsBackToCursor() throws {
        #expect(try args("$(ListOfSelectedFullNames)") == ["/work/a/notes.final.txt"])
        #expect(throws: UserMenuError.noFile) { try args("$(ListOfSelectedNames)", context(cursor: nil)) }
    }

    @Test func perFileVariableMultipliesInvocations() throws {
        let ctx = context(selected: ["/work/a/x.txt", "/work/a/y y.md"])
        let result = try UserMenuExpander.invocations(for: item("/usr/bin/tool", arguments: "-i $(FullName) -o $(NamePart).out"), in: ctx)
        #expect(result.map(\.arguments) == [["-i", "/work/a/x.txt", "-o", "x.out"],
                                            ["-i", "/work/a/y y.md", "-o", "y y.out"]])
        #expect(result.allSatisfy { $0.program == "/usr/bin/tool" && $0.directory.path == "/work/a" })
    }

    @Test func perFileInProgramMultiplies() throws {
        let ctx = context(selected: ["/work/a/one", "/work/a/two"])
        let result = try UserMenuExpander.invocations(for: item("$(FullName)", arguments: "go"), in: ctx)
        #expect(result.map(\.program) == ["/work/a/one", "/work/a/two"])
    }

    @Test func itemsWithoutPerFileVariablesRunOnce() throws {
        let ctx = context(selected: ["/work/a/x", "/work/a/y"])
        let result = try UserMenuExpander.invocations(for: item(arguments: "$(FullPath) $(ListOfSelectedNames)"), in: ctx)
        #expect(result.count == 1)
        // No file needed at all.
        let none = try UserMenuExpander.invocations(for: item(arguments: "$(FullPath)"), in: context(cursor: nil))
        #expect(none.map(\.arguments) == [["/work/a"]])
    }

    @Test func cursorIsUsedWhenNothingSelected() throws {
        let result = try UserMenuExpander.invocations(for: item(arguments: "$(Name)"), in: context())
        #expect(result.map(\.arguments) == [["notes.final.txt"]])
    }

    @Test func noFileWhenNeitherCursorNorSelection() {
        #expect(throws: UserMenuError.noFile) {
            try UserMenuExpander.invocations(for: item(arguments: "$(FullName)"), in: context(cursor: nil))
        }
        #expect(throws: UserMenuError.noFile) {
            try UserMenuExpander.invocations(for: item(arguments: "$(FileToCompareLeft)"),
                                             in: { var c = context(); c.leftCursor = nil; return c }())
        }
    }

    @Test func environmentVariables() throws {
        let ctx = context(env: ["EDITOR": "vim -u NONE", "EMPTY": ""])
        #expect(try args("$[EDITOR] x$[EMPTY]y $[NOPE] pre-$[EDITOR]", ctx) == ["vim -u NONE", "xy", "", "pre-vim -u NONE"])
        let result = try UserMenuExpander.invocations(for: item("$[TOOLS]/run"), in: context(env: ["TOOLS": "/opt/tools"]))
        #expect(result.first?.program == "/opt/tools/run")
    }

    @Test func dollarEscapes() throws {
        #expect(try args("$$HOME a$$b '$$(Name)' cost$") == ["$HOME", "a$b", "$(Name)", "cost$"])
        #expect(try args("\"$$\" '$$'") == ["$", "$"])
    }

    @Test func unknownVariable() {
        #expect(throws: UserMenuError.unknownVariable("$(Bogus)")) { try args("$(Bogus)") }
        #expect(throws: UserMenuError.unknownVariable("$(Nope)")) {
            try UserMenuExpander.invocations(for: item("$(Nope)"), in: context())
        }
        #expect(throws: UserMenuError.unknownVariable("$(open")) { try args("$(open") }
    }

    @Test func badQuoting() {
        #expect(throws: UserMenuError.badQuoting) { try args("'unterminated") }
        #expect(throws: UserMenuError.badQuoting) { try args("a | b") }
    }

    @Test func quotingAndTildeInArguments() throws {
        #expect(try args("'a b' \"c d\" e\\ f ~/x ~") == ["a b", "c d", "e f", "/Users/test/x", "/Users/test"])
        // A value starting with ~ is not tilde-expanded.
        #expect(try args("$[T]", context(env: ["T": "~/x"])) == ["~/x"])
    }

    @Test func programExpansion() throws {
        let tilde = try UserMenuExpander.invocations(for: item("~/bin/tool"), in: context())
        #expect(tilde.first?.program == "/Users/test/bin/tool")
        #expect(throws: UserMenuError.emptyProgram) { try UserMenuExpander.invocations(for: item(""), in: context()) }
        #expect(throws: UserMenuError.emptyProgram) { try UserMenuExpander.invocations(for: item("  "), in: context()) }
        #expect(throws: UserMenuError.emptyProgram) { try UserMenuExpander.invocations(for: item("$[NOPE]"), in: context()) }
        var separator = item("x")
        separator.kind = .separator
        #expect(throws: UserMenuError.emptyProgram) { try UserMenuExpander.invocations(for: separator, in: context()) }
    }

    @Test func directoryExpansion() throws {
        func dir(_ d: String, _ ctx: UserMenuContext? = nil) throws -> String {
            try UserMenuExpander.invocations(for: item(directory: d), in: ctx ?? context()).first?.directory.path ?? ""
        }
        #expect(try dir("$(FullPath)") == "/work/a")
        #expect(try dir("") == "/work/a")
        #expect(try dir("$(FullPathInactive)") == "/work/b")
        #expect(try dir("~/Projects") == "/Users/test/Projects")
        #expect(try dir("sub/dir") == "/work/a/sub/dir")
        #expect(try dir("../b/./c") == "/work/b/c")
        #expect(try dir("/tmp/x y") == "/tmp/x y")
        #expect(throws: UserMenuError.notADirectory("$(ListOfSelectedNames)")) { try dir("$(ListOfSelectedNames)") }
    }

    @Test func variableListCoversEverything() {
        let names = UserMenuExpander.variables.map(\.name)
        for expected in ["$(FullName)", "$(Name)", "$(NamePart)", "$(ExtPart)", "$(FullPath)", "$(FullPathLeft)",
                         "$(FullPathRight)", "$(FullPathInactive)", "$(FileToCompareLeft)", "$(FileToCompareRight)",
                         "$(ListOfSelectedNames)", "$(ListOfSelectedFullNames)", "$[NAME]", "$$"] {
            #expect(names.contains(expected))
        }
        #expect(UserMenuExpander.variables.allSatisfy { !$0.description.isEmpty })
    }

    @Test func codableRoundTripWithSubmenu() throws {
        let tree = [
            UserMenuItem(title: "One", program: "~/bin/x", arguments: "-a $(Name) 'q q'", directory: "~", runInTerminal: true),
            UserMenuItem(kind: .separator),
            UserMenuItem(kind: .submenu, title: "Group", children: [
                UserMenuItem(title: "Inner", program: "/usr/bin/open", arguments: "$(ListOfSelectedFullNames)"),
                UserMenuItem(kind: .submenu, title: "Deeper", children: [UserMenuItem(title: "Leaf", program: "ls")]),
            ]),
        ]
        let data = try UserMenuStore.encode(tree)
        #expect(try UserMenuStore.decode(data) == tree)
        #expect(try UserMenuStore.decode(UserMenuStore.encode(UserMenuStore.examples)) == UserMenuStore.examples)
    }

    @Test func decodeFillsMissingKeys() throws {
        let json = #"[{"title": "Hand edited", "program": "ls"}]"#
        let items = try UserMenuStore.decode(Data(json.utf8))
        #expect(items.count == 1)
        #expect(items[0].kind == .command && items[0].directory == "$(FullPath)" && !items[0].runInTerminal)
        #expect(items[0].children.isEmpty)
    }

    @Test func examplesAreExpandable() throws {
        #expect(UserMenuStore.examples.count >= 2)
        let ctx = context(selected: ["/work/a/x.txt"])
        for example in UserMenuStore.examples where example.kind == .command {
            #expect(try !UserMenuExpander.invocations(for: example, in: ctx).isEmpty)
        }
        let textEdit = try UserMenuExpander.invocations(for: UserMenuStore.examples[0], in: ctx)
        #expect(textEdit.first?.program == "/usr/bin/open")
        #expect(textEdit.first?.arguments == ["-a", "TextEdit", "/work/a/x.txt"])
    }

    @Test func shellCommandQuotesNastyNames() {
        let invocation = UserMenuInvocation(
            program: "/usr/bin/tool", arguments: ["plain", "a b'c\"$d", ""],
            directory: Self.url("/work/it's here"))
        #expect(UserMenuExpander.shellCommand(invocation)
            == "cd '/work/it'\\''s here' && /usr/bin/tool plain 'a b'\\''c\"$d' ''")
    }

    @Test func shellCommandOpensAppBundles() {
        let invocation = UserMenuInvocation(program: "/Applications/Some App.app", arguments: ["x y"],
                                            directory: Self.url("/work"))
        #expect(UserMenuExpander.shellCommand(invocation) == "cd /work && open '/Applications/Some App.app' --args 'x y'")
        let bare = UserMenuInvocation(program: "/Applications/Some App.app", arguments: [], directory: Self.url("/work"))
        #expect(UserMenuExpander.shellCommand(bare) == "cd /work && open '/Applications/Some App.app'")
    }

    // MARK: Shortcuts

    @Test func shortcutRoundTrip() throws {
        let items = [
            UserMenuItem(title: "a", program: "/bin/a", shortcut: KeyChord(.character("e"), [.control, .option])),
            UserMenuItem(title: "b", program: "/bin/b", shortcut: KeyChord(.function(7), .shift)),
            UserMenuItem(title: "c", program: "/bin/c"),
        ]
        let data = try UserMenuStore.encode(items)
        #expect(String(decoding: data, as: UTF8.self).contains("ctrl+opt+char:e"))
        #expect(try UserMenuStore.decode(data) == items)
    }

    @Test func oldJSONWithoutShortcutDecodes() throws {
        let json = #"[{"kind":"command","title":"x","program":"/bin/x","arguments":"","directory":"$(FullPath)","runInTerminal":false,"children":[]}]"#
        let items = try UserMenuStore.decode(Data(json.utf8))
        #expect(items.count == 1)
        #expect(items[0].shortcut == nil)
        #expect(items[0].program == "/bin/x")
    }

    @Test func malformedShortcutKeepsItem() throws {
        let json = #"[{"title":"x","program":"/bin/x","shortcut":"cmd+bogus"}]"#
        let items = try UserMenuStore.decode(Data(json.utf8))
        #expect(items.count == 1)
        #expect(items[0].shortcut == nil)
    }

    @Test func commandForChordSearchesSubmenusFirstMatchWins() {
        let chord = KeyChord(.character("g"), [.control, .option])
        let other = KeyChord(.function(4), .control)
        let nested = UserMenuItem(title: "nested", program: "/bin/n", shortcut: chord)
        let later = UserMenuItem(title: "later", program: "/bin/l", shortcut: chord)
        let items = [
            UserMenuItem(title: "plain", program: "/bin/p"),
            UserMenuItem(kind: .separator),
            UserMenuItem(kind: .submenu, title: "Sub", children: [
                UserMenuItem(title: "deep", program: "/bin/d", shortcut: other),
                nested,
            ]),
            later,
        ]
        #expect(UserMenuStore.commands(in: items).map(\.title) == ["plain", "deep", "nested", "later"])
        #expect(UserMenuStore.command(for: chord, in: items)?.id == nested.id)
        #expect(UserMenuStore.command(for: other, in: items)?.title == "deep")
        #expect(UserMenuStore.command(for: KeyChord(.function(9)), in: items) == nil)
    }

    @Test func plainCharactersAreNotAssignable() {
        #expect(!UserMenuStore.isAssignable(KeyChord(.character("a"))))
        #expect(!UserMenuStore.isAssignable(KeyChord(.character("5"), .shift)))
        #expect(UserMenuStore.isAssignable(KeyChord(.character("a"), .command)))
        #expect(UserMenuStore.isAssignable(KeyChord(.character("1"), .control)))
        #expect(UserMenuStore.isAssignable(KeyChord(.character("x"), [.option, .shift])))
        #expect(UserMenuStore.isAssignable(KeyChord(.function(3))))
        #expect(UserMenuStore.isAssignable(KeyChord(.enter, .shift)))
    }
}
