// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct MediaDetailsTests {
    @Test func durations() {
        #expect(MediaDetails.duration(7) == "0:07")
        #expect(MediaDetails.duration(222) == "3:42")
        #expect(MediaDetails.duration(3723) == "1:02:03")
        #expect(MediaDetails.duration(59.9) == "0:59")
        #expect(MediaDetails(duration: .nan).summaryParts.isEmpty)
        #expect(MediaDetails(duration: -1).summaryParts.isEmpty)
    }

    @Test func channels() {
        func parts(_ n: Int) -> [String] { MediaDetails(audio: [.init(channels: n)]).summaryParts }
        #expect(parts(1) == [String(localized: "Mono")])
        #expect(parts(2) == [String(localized: "Stereo")])
        #expect(parts(6) == ["5.1"])
        #expect(parts(8) == ["7.1"])
        #expect(parts(3) == [String(localized: "\(3) channels")])
    }

    @Test func frameSizeAndRates() {
        let d = MediaDetails(video: [.init(width: 1920, height: 1080)])
        #expect(d.summaryParts == ["1920 × 1080"])
        let a = MediaDetails(audio: [.init(sampleRate: 48000)])
        #expect(a.summaryParts == ["48 kHz"])
        let c = MediaDetails(audio: [.init(sampleRate: 44100)]).summaryParts[0]
        #expect(c.contains("44") && c.contains("1 kHz"))
    }

    @Test func fullOrder() {
        let d = MediaDetails(duration: 222, container: "MPEG-4",
                             audio: [.init(codec: "AAC", sampleRate: 48000, channels: 2)],
                             video: [.init(codec: "H.264", width: 1920, height: 1080, frameRate: 25)])
        #expect(d.summaryParts == ["3:42", "MPEG-4", "H.264", "1920 × 1080", "25 fps",
                                   "AAC", "48 kHz", String(localized: "Stereo")])
    }

    @Test func audioOnlyAndEmpty() {
        let d = MediaDetails(duration: 7, container: "MP3",
                             audio: [.init(codec: "MP3", sampleRate: 48000, channels: 1)])
        #expect(d.summaryParts == ["0:07", "MP3", "MP3", "48 kHz", String(localized: "Mono")])
        #expect(MediaDetails().summaryParts == [])
    }
}
