// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import AppKit
import CommanderCore
import Observation
import SwiftUI

/// Records one key chord from the keyboard (Settings → Keyboard, Settings → User Menu): while
/// recording, the next key-down of the app is taken as the chord; Esc alone cancels.
@Observable
final class ChordRecorder {
    private(set) var isRecording = false
    @ObservationIgnored private var monitor: Any?

    /// Starts recording; `onChord` gets the recorded chord (recording has already stopped then).
    func start(onChord: @escaping (KeyChord) -> Void) {
        stop()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                stop()
                return nil
            }
            guard let chord = KeyChord(event: event) else { return event }
            stop()
            onChord(chord)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}

/// A shortcut shown as a capsule, optionally with a remove button.
struct ChordChip: View {
    let chord: KeyChord
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            Text(chord.description).monospaced()
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Remove this shortcut")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}
