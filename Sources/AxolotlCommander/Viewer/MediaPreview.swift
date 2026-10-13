// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import AVFoundation
import AVKit
import CommanderCore
import CoreMedia
import UniformTypeIdentifiers

/// The player keeps its controls but never the keyboard focus: the viewer's keys stay in charge.
final class FocuslessPlayerView: AVPlayerView {
    override var acceptsFirstResponder: Bool { false }
}

/// Focus holder of the media preview; keys go to the viewer first, then to the player.
final class MediaKeyView: NSView {
    var onKey: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

/// Audio and video in the viewer (spec 019): Return plays and pauses, ← → seek by 5 seconds,
/// ↑ ↓ change the volume; Space stays Next File. Playback never starts by itself.
final class MediaPreview: NSView {
    /// Types the system can play, from AVFoundation (identifiers of UTTypes).
    private static let playableTypes: [UTType] = AVURLAsset.audiovisualTypes().compactMap { UTType($0.rawValue) }

    /// A file AVFoundation can open.
    static func canPlay(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .audiovisualContent) else {
            return false
        }
        return playableTypes.contains { type.conforms(to: $0) }
    }

    static let seekStep: Double = 5

    private let keyHolder = MediaKeyView()
    private let playerView = FocuslessPlayerView()
    private let messageField = NSTextField(labelWithString: "")
    private var detailsTask: Task<Void, Never>?
    private(set) var details: MediaDetails?
    var keyView: NSView { keyHolder }
    var onKey: ((NSEvent) -> Bool)?
    var onDetails: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.videoGravity = .resizeAspect
        messageField.textColor = .secondaryLabelColor
        messageField.alignment = .center
        messageField.isHidden = true
        keyHolder.onKey = { [weak self] in self?.handleKey($0) ?? false }
        for view in [keyHolder, playerView, messageField] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            keyHolder.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyHolder.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyHolder.topAnchor.constraint(equalTo: topAnchor),
            keyHolder.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            messageField.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageField.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Content

    func show(_ url: URL) {
        clear()
        let asset = AVURLAsset(url: url)
        playerView.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        playerView.isHidden = false
        let container = UTType(filenameExtension: url.pathExtension)?.localizedDescription
        detailsTask = Task {
            let loaded = await Self.details(of: asset, container: container)
            guard !Task.isCancelled else { return }
            if let loaded {
                details = loaded
            } else {
                playerView.player = nil
                playerView.isHidden = true
                messageField.stringValue = String(localized: "This file cannot be played.")
                messageField.isHidden = false
            }
            onDetails?()
        }
    }

    /// Stops playback and releases the file.
    func clear() {
        detailsTask?.cancel()
        playerView.player?.pause()
        playerView.player = nil
        details = nil
        messageField.isHidden = true
    }

    func pause() { playerView.player?.pause() }

    private nonisolated static func details(of asset: AVURLAsset, container: String?) async -> MediaDetails? {
        guard let (playable, duration, tracks) = try? await asset.load(.isPlayable, .duration, .tracks), playable else {
            return nil
        }
        var result = MediaDetails(duration: duration.isNumeric ? duration.seconds : nil, container: container)
        for track in tracks {
            let type = track.mediaType
            guard let formats = try? await track.load(.formatDescriptions) else { continue }
            let codec = formats.first.map { codecName(CMFormatDescriptionGetMediaSubType($0)) }
            if type == .audio {
                let basic = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
                result.audio.append(.init(codec: codec, sampleRate: basic.map { $0.mSampleRate },
                                          channels: basic.map { Int($0.mChannelsPerFrame) }))
            } else if type == .video, let (size, rate) = try? await track.load(.naturalSize, .nominalFrameRate) {
                result.video.append(.init(codec: codec, width: Int(abs(size.width)), height: Int(abs(size.height)),
                                          frameRate: rate > 0 ? Double(rate) : nil))
            }
        }
        return result
    }

    /// Readable names of the common codecs; other ones as their four-character code.
    private nonisolated static func codecName(_ code: FourCharCode) -> String {
        let known: [FourCharCode: String] = [
            kAudioFormatMPEG4AAC: "AAC", kAudioFormatMPEGLayer3: "MP3", kAudioFormatLinearPCM: "PCM",
            kAudioFormatAppleLossless: "ALAC", kAudioFormatFLAC: "FLAC", kAudioFormatOpus: "Opus",
            kAudioFormatAC3: "AC-3", kAudioFormatEnhancedAC3: "E-AC-3",
            kCMVideoCodecType_H264: "H.264", kCMVideoCodecType_HEVC: "HEVC", kCMVideoCodecType_MPEG4Video: "MPEG-4",
            kCMVideoCodecType_AppleProRes422: "ProRes 422", kCMVideoCodecType_AppleProRes4444: "ProRes 4444",
            kCMVideoCodecType_JPEG: "Motion JPEG", kCMVideoCodecType_VP9: "VP9", kCMVideoCodecType_AV1: "AV1",
        ]
        if let name = known[code] { return name }
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Keys

    func handleKey(_ event: NSEvent) -> Bool {
        if onKey?(event) == true { return true }
        guard let player = playerView.player,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        switch event.specialKey {
        case .carriageReturn?, .enter?:
            if player.rate == 0 { player.play() } else { player.pause() }
        case .leftArrow?, .rightArrow?:
            let delta = event.specialKey == .leftArrow ? -Self.seekStep : Self.seekStep
            let target = max(0, player.currentTime().seconds + delta)
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        case .upArrow?, .downArrow?:
            let delta: Float = event.specialKey == .upArrow ? 0.1 : -0.1
            player.volume = min(max(player.volume + delta, 0), 1)
        default:
            return false
        }
        return true
    }
}
