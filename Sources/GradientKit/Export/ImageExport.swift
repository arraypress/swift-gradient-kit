//
//  ImageExport.swift
//  GradientKit
//
//  Write a rendered CGImage to disk via ImageIO. PNG keeps 16-bit renders
//  at 16 bits; JPEG and HEIC are 8-bit lossy.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case png, jpeg, heic

    public var id: String { rawValue }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }

    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
}

public enum ExportError: Error, LocalizedError, Sendable {
    case destinationFailed(URL)
    case encodeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case let .destinationFailed(url): "Could not create an image destination at \(url.path)."
        case let .encodeFailed(url): "Encoding the image to \(url.path) failed."
        }
    }
}

public enum ImageExport {
    /// `quality` applies to lossy formats (0...1).
    public static func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Double = 0.95) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw ExportError.destinationFailed(url)
        }
        var props: [CFString: Any] = [:]
        if format != .png { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.encodeFailed(url) }
    }

    public static func data(_ image: CGImage, format: ImageFormat, quality: Double = 0.95) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, format.utType.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if format != .png { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
