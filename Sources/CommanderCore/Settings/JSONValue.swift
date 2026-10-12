// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Any JSON value. The settings file embeds stored settings as plain JSON, so it stays readable
/// and editable; integral numbers are written without a fraction.
public indirect enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Parses JSON text (any top-level value).
    public init(data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Pretty-printed JSON with sorted keys: equal values always give equal bytes.
    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// A property list value as stored in UserDefaults (booleans, numbers, strings, arrays and
    /// dictionaries of those); nil for anything else (data, dates).
    public init?(propertyList value: Any) {
        switch value {
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            var items: [JSONValue] = []
            for element in array {
                guard let item = JSONValue(propertyList: element) else { return nil }
                items.append(item)
            }
            self = .array(items)
        case let dictionary as [String: Any]:
            var members: [String: JSONValue] = [:]
            for (key, element) in dictionary {
                guard let member = JSONValue(propertyList: element) else { return nil }
                members[key] = member
            }
            self = .object(members)
        default:
            return nil
        }
    }

    /// The value as a property list for UserDefaults; nil when it holds a JSON null.
    public var propertyList: Any? {
        switch self {
        case .null: nil
        case .bool(let value): value
        case .number(let value): Self.integral(value).map { $0 as Any } ?? value
        case .string(let value): value
        case .array(let items):
            items.reduce(into: [Any]?([])) { result, item in
                guard let value = item.propertyList else { result = nil; return }
                result?.append(value)
            }
        case .object(let members):
            members.reduce(into: [String: Any]?([:])) { result, member in
                guard let value = member.value.propertyList else { result = nil; return }
                result?[member.key] = value
            }
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let members) = self { return members }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Integral values that fit an Int exactly are written without a fraction.
    fileprivate static func integral(_ value: Double) -> Int? {
        guard value.rounded() == value, abs(value) < 9_007_199_254_740_992 else { return nil }
        return Int(value)
    }
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            if let integral = Self.integral(value) { try container.encode(integral) } else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let items): try container.encode(items)
        case .object(let members): try container.encode(members)
        }
    }
}
