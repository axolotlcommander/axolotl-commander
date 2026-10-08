// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation
internal import ImageIO
public import UniformTypeIdentifiers

/// Formats the image viewer can save to.
public enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg, heic, tiff, gif, bmp

    public var type: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        }
    }

    public var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .gif: "GIF"
        case .bmp: "BMP"
        }
    }

    public var fileExtension: String { type.preferredFilenameExtension ?? rawValue }
    /// Lossy formats take a quality between 0 and 1.
    public var hasQuality: Bool { self == .jpeg || self == .heic }
    /// Formats that keep every frame (animation, pages); the others keep the first one.
    var keepsFrames: Bool { self == .gif || self == .tiff }

    /// The format a file name asks for, e.g. "photo.JPG" → .jpeg.
    public static func forFile(named name: String) -> ImageFormat? {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return nil }
        return allCases.first { type.conforms(to: $0.type) }
    }
}

public enum ImageExportError: Error, Equatable {
    /// The source is not an image ImageIO can read.
    case unreadable
    /// ImageIO could not write the format (for example HEIC without an encoder).
    case cannotEncode(ImageFormat)
}

public enum ImageExport {
    /// File types ImageIO can open.
    public static func canRead(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { return false }
        let readable = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        return readable.contains(type.identifier)
    }

    /// Saves `source` as `format` at `target`. An existing target is replaced only by a complete
    /// new file (see `SafeFileWriter`); the source may be the target itself. Metadata such as
    /// EXIF and orientation is carried over.
    public static func export(_ source: URL, to target: URL, format: ImageFormat, quality: Double? = nil) throws {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(image) > 0,
              CGImageSourceGetStatus(image) == .statusComplete else { throw ImageExportError.unreadable }
        // Decode before writing, so a source that is also the target is read completely first.
        let frames = format.keepsFrames ? CGImageSourceGetCount(image) : 1
        guard (0..<frames).allSatisfy({ CGImageSourceCreateImageAtIndex(image, $0, nil) != nil }) else {
            throw ImageExportError.unreadable
        }
        // Encoded in memory first, so a failing write reports the file system's error, not the encoder's.
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded as CFMutableData, format.type.identifier as CFString,
                                                                 frames, nil) else {
            throw ImageExportError.cannotEncode(format)
        }
        var options: [CFString: Any] = [:]
        if format.hasQuality, let quality { options[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1) }
        if let properties = CGImageSourceCopyProperties(image, nil) as? [CFString: Any] {
            // Container properties such as the GIF loop count.
            CGImageDestinationSetProperties(destination, properties as CFDictionary)
        }
        for index in 0..<frames {
            try Task.checkCancellation()
            CGImageDestinationAddImageFromSource(destination, image, index, options as CFDictionary)
        }
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else { throw ImageExportError.cannotEncode(format) }
        try SafeFileWriter.write(to: target) { temp in try (encoded as Data).write(to: temp) }
    }
}

/// What the image viewer's status line says about a picture.
public struct ImageInfo: Sendable, Equatable {
    /// Pixel size as displayed, i.e. after the EXIF orientation is applied.
    public var width: Int
    public var height: Int
    public var frames: Int
    /// Uniform type identifier of the file's format.
    public var type: String?
    public var depth: Int?
    public var colorModel: String?
    public var hasAlpha: Bool
    /// EXIF orientation 1…8; 5…8 swap width and height.
    public var orientation: Int

    public static func read(_ url: URL) -> ImageInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let swapped = (5...8).contains(orientation)
        return ImageInfo(width: swapped ? height : width, height: swapped ? width : height,
                         frames: CGImageSourceGetCount(source),
                         type: CGImageSourceGetType(source) as String?,
                         depth: properties[kCGImagePropertyDepth] as? Int,
                         colorModel: properties[kCGImagePropertyColorModel] as? String,
                         hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
                         orientation: orientation)
    }
}
