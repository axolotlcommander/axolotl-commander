public import Foundation

/// A favorite directory with a display name.
public struct HotPath: Codable, Hashable, Sendable {
    public var name: String
    public var path: String

    /// A nil or empty `name` becomes the last path component ("/" for the root).
    public init(name: String? = nil, path: String) {
        self.path = path
        if let name, !name.isEmpty { self.name = name } else { self.name = PathText.lastComponent(path) }
    }
}

/// Favorite paths: 30 slots, the first 10 reachable by ⌃1…⌃9, ⌃0 (go) and ⌃⇧1…⌃⇧0 (store here).
public struct HotPaths: Codable, Hashable, Sendable {
    public static let capacity = 30
    public static let shortcutSlots = 10

    /// Always exactly `capacity` elements.
    public private(set) var slots: [HotPath?]

    /// Pads with nil or truncates to `capacity`.
    public init(slots: [HotPath?] = []) {
        self.slots = Self.fitted(slots)
    }

    /// Arrays of any length are padded or truncated.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(slots: try c.decodeIfPresent([HotPath?].self, forKey: .slots) ?? [])
    }

    private static func fitted(_ slots: [HotPath?]) -> [HotPath?] {
        var result = Array(slots.prefix(capacity))
        result.append(contentsOf: [HotPath?](repeating: nil, count: capacity - result.count))
        return result
    }

    /// nil for out-of-range slots.
    public subscript(slot: Int) -> HotPath? {
        slots.indices.contains(slot) ? slots[slot] : nil
    }

    /// Out-of-range slots are ignored.
    public mutating func set(_ slot: Int, _ hotPath: HotPath?) {
        guard slots.indices.contains(slot) else { return }
        slots[slot] = hotPath
    }

    /// Stores into the first free slot from `shortcutSlots` up (10…29), then 0…9; returns the slot,
    /// or nil when full. A path already stored (ignoring a trailing "/") is not added again; its slot is returned.
    @discardableResult
    public mutating func add(_ hotPath: HotPath) -> Int? {
        let key = PathText.trimmingTrailingSlashes(hotPath.path)
        if let existing = slots.firstIndex(where: { $0.map { PathText.trimmingTrailingSlashes($0.path) == key } ?? false }) {
            return existing
        }
        let order = Array(Self.shortcutSlots..<Self.capacity) + Array(0..<Self.shortcutSlots)
        guard let slot = order.first(where: { slots[$0] == nil }) else { return nil }
        slots[slot] = hotPath
        return slot
    }

    /// Swaps the contents of two slots.
    public mutating func move(from: Int, to: Int) {
        guard slots.indices.contains(from), slots.indices.contains(to) else { return }
        slots.swapAt(from, to)
    }

    /// Occupied slots only, ascending.
    public var defined: [(slot: Int, hotPath: HotPath)] {
        slots.enumerated().compactMap { i, h in h.map { (slot: i, hotPath: $0) } }
    }

    /// Key digit to slot: 1→0, 2→1 … 9→8, 0→9; anything else nil.
    public static func slot(forDigit digit: Int) -> Int? {
        switch digit {
        case 1...9: digit - 1
        case 0: 9
        default: nil
        }
    }

    /// Slot to the digit shown for its shortcut (0…9 → 1…9, 0); nil for slots without one.
    public static func digit(forSlot slot: Int) -> Int? {
        switch slot {
        case 0...8: slot + 1
        case 9: 0
        default: nil
        }
    }
}
