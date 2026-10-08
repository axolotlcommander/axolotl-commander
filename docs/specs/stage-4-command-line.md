# Stage 4 — command line and properties (core specification)

Everything in `Sources/CommanderCore/Shell/`, Swift Testing tests in `Tests/CommanderCoreTests/ShellTests.swift`.
No AppKit. The package has the upcoming features `ExistentialAny`, `InternalImportsByDefault`,
`MemberImportVisibility` → public API needs `public import Foundation`.
Password rule: `../tandemcommander/docs/macos-port/05-pravidla.md` (the address is stored in history without the password).

## API

```swift
public enum ShellQuote {
    /// POSIX sh quoting. Unchanged when non-empty and only [A-Za-z0-9_./+:@%,=-] (and non-ASCII letters
    /// are NOT safe → quote). Otherwise single quotes, ' → '\''. Empty → ''.
    public static func quote(_ s: String) -> String
}

public enum ShellWords {
    /// Word splitting like sh: whitespace separates, '…' literal, "…" with \" \\ \$ \` escapes,
    /// backslash escapes outside quotes. nil when a quote is unbalanced or an unquoted shell
    /// metacharacter occurs: ; & | < > ( ) $ ` * ? [ (globs/vars → let the shell handle it).
    /// Tilde: a word starting with unquoted "~" or "~/" gets `home` substituted.
    public static func split(_ line: String, home: URL) -> [String]?
}

public enum Credentials {
    /// Removes the password from `scheme://user:password@host…` → `scheme://user@host…`
    /// and from a whitespace-delimited word `user:password@host…` (user without / : @).
    /// `git@github.com:a/b`, `user@host:path`, plain text stay unchanged.
    public static func scrub(_ text: String) -> String
}

public struct CommandHistory: Codable, Equatable, Sendable {
    public static let limit = 30
    public private(set) var entries: [String]          // newest first
    public init(entries: [String] = [])
    /// Trims whitespace; ignores empty; stores Credentials.scrub(command); an equal older entry
    /// moves to the front (no duplicates); keeps at most `limit`.
    public mutating func add(_ command: String)
}

/// Shell-like ↑/↓ browsing over a history snapshot.
public struct HistoryBrowser: Sendable {
    public init(_ history: CommandHistory)
    /// First call saves `current` as draft and returns the newest entry; then older ones; nil at the end.
    public mutating func older(current: String) -> String?
    /// Goes back towards newest; past the newest returns the saved draft; nil when not browsing.
    public mutating func newer() -> String?
}

public enum CommandLineAction: Equatable, Sendable {
    case none                      // empty / whitespace only
    case changeDirectory(URL)      // cd, cd ~, cd ~/x, cd .., cd /abs, cd "a b", cd a\ b (one word)
    case back                      // cd -
    case open(URL)                 // the line is exactly one word naming an existing item (relative or absolute)
    case run(String)               // anything else, trimmed, passed to the shell unchanged
    case invalid(PathError)        // cd target rejected by PathRules (too long…)
}

public enum CommandInput {
    /// `cd` without argument → home. `cd` with more than one word or with metacharacters → .run.
    /// Relative paths resolve against `directory` (use PathRules.resolve / validate; never truncate).
    /// `exists` is injectable for tests; default checks the file system (no writes).
    public static func parse(_ line: String, in directory: URL, home: URL,
                             exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> CommandLineAction
}

public enum TerminalScript {
    /// Contents of a self-deleting `.command` file Terminal runs:
    ///   #!/bin/sh
    ///   rm -f -- "$0"
    ///   cd -- <quoted dir> || exit 1
    ///   "${SHELL:-/bin/zsh}" -l -c <quoted command>
    ///   exec "${SHELL:-/bin/zsh}" -l
    /// (user's own shell runs the command — it may be fish/zsh; the window stays open with a prompt).
    public static func contents(command: String, directory: URL) -> String
}

public struct FileProperties: Sendable, Equatable {
    public var url: URL
    public var name: String
    public var kind: String?              // UTType(…).localizedDescription (import UniformTypeIdentifiers)
    public var isDirectory: Bool          // of the link itself when it is a symlink (lstat)
    public var isPackage: Bool
    public var isSymlink: Bool
    public var linkDestination: String?   // raw destinationOfSymbolicLink
    public var size: Int64?               // regular file logical size; nil for directories
    public var allocatedSize: Int64?
    public var created: Date?
    public var modified: Date?
    public var accessed: Date?
    public var mode: Int                  // st_mode & 0o7777
    public var owner: String?
    public var group: String?
    public var isHidden: Bool
    public var isLocked: Bool             // uchg flag
    /// Reads with lstat semantics (does not follow the item itself if it is a link). Read-only.
    public static func load(_ url: URL) throws -> FileProperties
    /// "drwxr-xr-x", "-rw-r--r--", "lrwxr-xr-x"; setuid/setgid s/S, sticky t/T.
    public static func permissionsString(mode: Int, isDirectory: Bool, isSymlink: Bool) -> String
    /// "0755", "4755".
    public static func octal(_ mode: Int) -> String
}
```

## Tests

- ShellQuote: `abc` unchanged, `a b` → `'a b'`, `it's` → `'it'\''s'`, `""` → `''`, `čaj` → `'čaj'`.
- ShellWords: `cd "a b"` → [cd, a b]; `a\ b`; `'x"y'`; `~/x` → home/x; `"~/x"` without expansion;
  `a; b`, `a | b`, `$HOME`, `*.txt`, `"unclosed` → nil.
- Credentials: `ftp://joe:secret@host/x` → `ftp://joe@host/x`; `sftp joe:pw@host` → `sftp joe@host`;
  `git clone git@github.com:a/b` unchanged; `scp f user@host:/p` unchanged; `https://host/a:b@c`? unchanged.
- CommandHistory: limit 30, a duplicate moves to the front, empty ignored, password not stored, Codable round trip.
- HistoryBrowser: older → newest…oldest → nil; newer → back → draft.
- CommandInput (exists injected, or a read-only temp directory): `""` → none; `cd` → home; `cd ..`;
  `cd ~/x`; `cd /usr/bin`; `cd "a b"` relative; `cd -` → back; `cd a b` → run; `cd x && make` → run;
  existing `readme.txt` → open; `ls -la` → run; `cd` + too long a path → invalid.
- TerminalScript: contains `cd -- '/tmp/a b'` and `-c 'echo '\''hi'\'''` (correct quoting).
- FileProperties (in a temp directory that the test creates and deletes): file 0644 → `-rw-r--r--`, size;
  symlink → isSymlink, linkDestination; folder → isDirectory, size nil; permissionsString for 04755,
  01777 (`drwxrwxrwt`), 02644 without x (`-rw-r-Sr--`); octal.
