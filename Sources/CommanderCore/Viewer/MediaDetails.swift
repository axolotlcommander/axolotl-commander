// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// Technical facts about an audio or video file, shown in the viewer status line.
public struct MediaDetails: Sendable, Equatable {
    public struct Audio: Sendable, Equatable {
        public var codec: String?
        public var sampleRate: Double?
        public var channels: Int?

        public init(codec: String? = nil, sampleRate: Double? = nil, channels: Int? = nil) {
            self.codec = codec
            self.sampleRate = sampleRate
            self.channels = channels
        }
    }

    public struct Video: Sendable, Equatable {
        public var codec: String?
        public var width: Int
        public var height: Int
        public var frameRate: Double?

        public init(codec: String? = nil, width: Int, height: Int, frameRate: Double? = nil) {
            self.codec = codec
            self.width = width
            self.height = height
            self.frameRate = frameRate
        }
    }

    /// Length in seconds.
    public var duration: Double?
    /// Container name, e.g. "MPEG-4".
    public var container: String?
    public var audio: [Audio]
    public var video: [Video]

    public init(duration: Double? = nil, container: String? = nil,
                audio: [Audio] = [], video: [Video] = []) {
        self.duration = duration
        self.container = container
        self.audio = audio
        self.video = video
    }

    /// Status line items: duration, container, first video track (codec, size, frame rate),
    /// first audio track (codec, sample rate, channels). Missing values are skipped.
    public var summaryParts: [String] {
        var parts: [String] = []
        if let duration, duration.isFinite, duration >= 0 { parts.append(Self.duration(duration)) }
        if let container, !container.isEmpty { parts.append(container) }
        if let v = video.first {
            if let codec = v.codec, !codec.isEmpty { parts.append(codec) }
            if v.width > 0, v.height > 0 { parts.append("\(v.width) × \(v.height)") }
            if let fps = v.frameRate, fps.isFinite, fps > 0 { parts.append("\(Self.decimal(fps)) fps") }
        }
        if let a = audio.first {
            if let codec = a.codec, !codec.isEmpty { parts.append(codec) }
            if let rate = a.sampleRate, rate.isFinite, rate > 0 {
                parts.append("\(Self.decimal(rate / 1000)) kHz")
            }
            if let ch = a.channels, ch > 0 { parts.append(Self.channelName(ch)) }
        }
        return parts
    }

    /// `m:ss` under one hour, `h:mm:ss` from one hour; rounded down to whole seconds.
    public static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let ss = s < 10 ? "0\(s)" : "\(s)"
        if h > 0 { return "\(h):\(m < 10 ? "0\(m)" : "\(m)"):\(ss)" }
        return "\(m):\(ss)"
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func channelName(_ n: Int) -> String {
        switch n {
        case 1: String(localized: "Mono")
        case 2: String(localized: "Stereo")
        case 6: "5.1"
        case 8: "7.1"
        default: String(localized: "\(n) channels")
        }
    }
}
