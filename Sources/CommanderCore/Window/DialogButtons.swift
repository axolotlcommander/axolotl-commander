// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import CoreGraphics

/// Arrow keys in a dialog move the default button (the one Return presses) to the next button on
/// screen. Buttons are ordered as they are read: rows top to bottom, each row left to right, so it
/// works for a vertical stack and a row of buttons alike.
public enum DialogButtons {
    /// The order to step through; `frames` are in window coordinates (y grows upwards).
    public static func order(_ frames: [CGRect]) -> [Int] {
        frames.indices.sorted { a, b in
            let (fa, fb) = (frames[a], frames[b])
            if abs(fa.midY - fb.midY) > 4 { return fa.midY > fb.midY }
            return fa.minX < fb.minX
        }
    }

    /// The button to make the default after an arrow: `step` is -1 for ↑ / ← and +1 for ↓ / →.
    /// Without a default the first step picks the first (or last) button; the ends do not wrap.
    public static func next(frames: [CGRect], current: Int?, step: Int) -> Int? {
        let order = order(frames)
        guard !order.isEmpty else { return nil }
        guard let current, let position = order.firstIndex(of: current) else {
            return step < 0 ? order.last : order.first
        }
        return order[min(max(position + step, 0), order.count - 1)]
    }
}
