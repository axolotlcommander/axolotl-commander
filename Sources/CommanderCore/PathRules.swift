// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

public enum PathError: Error, Equatable {
    case empty, tooLong, nameTooLong(String), notFound, notADirectory
}

/// Path validation and resolution. Limits are UTF-8 byte counts of the
/// filesystem representation; over-long input is rejected, never truncated.
public enum PathRules {
    public static let maxPathBytes = 1023
    public static let maxNameBytes = 255

    public static func validate(_ path: String) throws(PathError) {
        if path.isEmpty { throw .empty }
        if path.utf8.count > maxPathBytes { throw .tooLong }
        for component in path.split(separator: "/") where component.utf8.count > maxNameBytes {
            throw .nameTooLong(String(component))
        }
    }

    /// Expands `~`, makes relative input absolute against `base`, resolves
    /// `.` and `..` lexically. Does not touch the filesystem.
    public static func resolve(_ input: String, relativeTo base: URL) throws(PathError) -> URL {
        try validate(input)
        var path = input
        if path.hasPrefix("~") { path = (path as NSString).expandingTildeInPath }
        if !path.hasPrefix("/") { path = base.path + "/" + path }

        var stack: [Substring] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".": continue
            case "..": if !stack.isEmpty { stack.removeLast() }
            default: stack.append(component)
            }
        }
        let normalized = "/" + stack.joined(separator: "/")
        try validate(normalized)
        return URL(fileURLWithPath: normalized)
    }
}
