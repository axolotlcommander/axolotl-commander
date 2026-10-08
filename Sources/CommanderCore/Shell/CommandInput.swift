// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// What the command line should do with the entered text.
public enum CommandLineAction: Equatable, Sendable {
    case none
    case changeDirectory(URL)
    case back
    case open(URL)
    case run(String)
    case invalid(PathError)
}

public enum CommandInput {
    /// `cd` without argument → home. `cd` with more than one word or with metacharacters → `.run`.
    /// Relative paths resolve against `directory` via `PathRules`; over-long paths are `.invalid`.
    /// A single word naming an existing item → `.open`. `exists` is injectable for tests.
    public static func parse(_ line: String, in directory: URL, home: URL,
                             exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        -> CommandLineAction
    {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .none }
        guard let words = ShellWords.split(trimmed, home: home), let first = words.first else {
            return .run(trimmed)
        }

        if first == "cd" {
            switch words.count {
            case 1:
                return changeDirectory(home.path, in: directory)
            case 2 where words[1] == "-":
                return .back
            case 2:
                return changeDirectory(words[1], in: directory)
            default:
                return .run(trimmed)
            }
        }

        if words.count == 1, let url = try? PathRules.resolve(literal(first), relativeTo: directory),
           exists(url) {
            return .open(url)
        }
        return .run(trimmed)
    }

    private static func changeDirectory(_ word: String, in directory: URL) -> CommandLineAction {
        do throws(PathError) {
            return .changeDirectory(try PathRules.resolve(literal(word), relativeTo: directory))
        } catch {
            return .invalid(error)
        }
    }

    /// A word that still starts with `~` was quoted/escaped (a literal name); keep PathRules from expanding it.
    private static func literal(_ word: String) -> String {
        word.hasPrefix("~") ? "./" + word : word
    }
}
