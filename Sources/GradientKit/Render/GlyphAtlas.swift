//
//  GlyphAtlas.swift
//  GradientKit
//
//  Emoji and text as shapes. A glyph is rasterised with CoreText (Apple
//  Color Emoji included), its coverage turned into an exact signed
//  distance field, and both the colour bitmap and the field are uploaded
//  as slices of two texture arrays. The kernel then treats a glyph like
//  any other shape: rims, glows, relief, tiling with per-cell jitter.
//

import Foundation
import CoreGraphics
import CoreText
import Metal
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct GlyphBitmap: Sendable {
    let size: Int
    /// Premultiplied RGBA, row-major, top row first.
    let rgba: [UInt8]
    /// Signed distance in units of the bitmap side (negative inside).
    let sdf: [Float]
}

public enum GlyphRasterizer {
    /// Folders searched for `file:` shapes given by bare name (the app's
    /// Shapes library, for instance). Absolute paths bypass the search.
    nonisolated(unsafe) public static var shapeSearchPaths: [URL] = []

    /// A glyph token: `sf:heart.fill` is an SF Symbol, `file:stars.svg` an
    /// image (SVG, PDF, PNG…) resolved against `shapeSearchPaths`, anything
    /// else is drawn as text (an emoji, a letter, a word).
    public enum Source: Equatable, Sendable {
        case text(String)
        case symbol(String)
        case file(String)

        public init(_ token: String) {
            if token.hasPrefix("sf:") { self = .symbol(String(token.dropFirst(3))) }
            else if token.hasPrefix("file:") { self = .file(String(token.dropFirst(5))) }
            else { self = .text(token) }
        }

        public var token: String {
            switch self {
            case let .text(t): t
            case let .symbol(n): "sf:" + n
            case let .file(f): "file:" + f
            }
        }
    }

    /// Render a glyph token centred in a `size`×`size` bitmap, scaled so its
    /// ink fits `fill` of the box, and compute its signed distance field.
    static func render(_ token: String, size: Int = 512, fill: Double = 0.82) -> GlyphBitmap {
        switch Source(token) {
        case let .text(t): return renderText(t, size: size, fill: fill)
        case let .symbol(name): return renderImage(symbolImage(named: name), size: size, fill: fill)
        case let .file(path): return renderImage(fileImage(path), size: size, fill: fill)
        }
    }

    // MARK: Symbols & files

    static func resolve(_ path: String) -> URL? {
        if path.hasPrefix("/") || path.hasPrefix("~") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        for dir in shapeSearchPaths {
            let url = dir.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func symbolImage(named name: String) -> CGImage? {
        #if canImport(AppKit)
        let config = NSImage.SymbolConfiguration(pointSize: 600, weight: .regular)
            .applying(NSImage.SymbolConfiguration.preferringMulticolor())
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #elseif canImport(UIKit)
        let config = UIImage.SymbolConfiguration(pointSize: 600, weight: .regular).applying(UIImage.SymbolConfiguration.preferringMulticolor())
        return UIImage(systemName: name, withConfiguration: config)?.cgImage
        #else
        return nil
        #endif
    }

    static func fileImage(_ path: String) -> CGImage? {
        guard let url = resolve(path) else { return nil }
        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else { return nil }
        // Ask for a large representation so vector files (SVG, PDF) rasterise crisply.
        var rect = CGRect(origin: .zero, size: CGSize(width: 1200, height: 1200))
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #elseif canImport(UIKit)
        return UIImage(contentsOfFile: url.path)?.cgImage
        #else
        return nil
        #endif
    }

    /// Draw any image as a glyph: its alpha is the ink (opaque images use
    /// darkness instead), its colours are kept for `glyphColor`.
    static func renderImage(_ image: CGImage?, size: Int, fill: Double) -> GlyphBitmap {
        let n = size
        var rgba = [UInt8](repeating: 0, count: n * n * 4)
        guard let image else { return GlyphBitmap(size: n, rgba: rgba, sdf: [Float](repeating: 1, count: n * n)) }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        rgba.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .high
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let scale = CGFloat(fill) * CGFloat(n) / max(w, h)
            let dw = w * scale, dh = h * scale
            ctx.draw(image, in: CGRect(x: (CGFloat(n) - dw) / 2, y: (CGFloat(n) - dh) / 2, width: dw, height: dh))
        }
        let opaque = image.alphaInfo == .none || image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst
        var flipped = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            let src = (n - 1 - y) * n * 4, dst = y * n * 4
            flipped.replaceSubrange(dst..<(dst + n * 4), with: rgba[src..<(src + n * 4)])
        }
        if opaque {
            // No alpha channel: dark pixels are ink, white is background.
            for i in 0..<(n * n) {
                let lum = (Int(flipped[i * 4]) * 299 + Int(flipped[i * 4 + 1]) * 587 + Int(flipped[i * 4 + 2]) * 114) / 1000
                let a = UInt8(255 - lum)
                flipped[i * 4 + 3] = a
                // Premultiply so the ink is the original colour scaled by coverage.
                flipped[i * 4] = UInt8(Int(flipped[i * 4]) * Int(a) / 255)
                flipped[i * 4 + 1] = UInt8(Int(flipped[i * 4 + 1]) * Int(a) / 255)
                flipped[i * 4 + 2] = UInt8(Int(flipped[i * 4 + 2]) * Int(a) / 255)
            }
        }
        let sdf = signedDistance(alpha: flipped, size: n)
        return GlyphBitmap(size: n, rgba: flipped, sdf: sdf)
    }

    // MARK: Text

    static func renderText(_ text: String, size: Int, fill: Double) -> GlyphBitmap {
        let n = size
        var rgba = [UInt8](repeating: 0, count: n * n * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        rgba.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.setAllowsFontSmoothing(true)
            ctx.setShouldSmoothFonts(false)
            ctx.setAllowsAntialiasing(true)
            // Measure at a reference size, then scale to fit.
            let probeSize: CGFloat = 200
            let probe = CTFontCreateWithName("AppleColorEmoji" as CFString, probeSize, nil)
            let system = CTFontCreateUIFontForLanguage(.system, probeSize, nil) ?? probe
            let attrs: [CFString: Any] = [kCTFontAttributeName: system]
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary))
            let bounds = CTLineGetImageBounds(line, ctx)
            guard bounds.width > 0, bounds.height > 0 else { return }
            let scale = CGFloat(fill) * CGFloat(n) / max(bounds.width, bounds.height)
            let fontSize = probeSize * scale
            let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("AppleColorEmoji" as CFString, fontSize, nil)
            let line2 = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, [kCTFontAttributeName: font] as CFDictionary))
            let b2 = CTLineGetImageBounds(line2, ctx)
            // Centre the ink box in the bitmap (CG origin is bottom-left).
            ctx.textPosition = CGPoint(x: (CGFloat(n) - b2.width) / 2 - b2.minX, y: (CGFloat(n) - b2.height) / 2 - b2.minY)
            CTLineDraw(line2, ctx)
        }
        // CGContext rows are bottom-up; flip to top-first so uv.y runs down like the canvas.
        var flipped = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            let src = (n - 1 - y) * n * 4, dst = y * n * 4
            flipped.replaceSubrange(dst..<(dst + n * 4), with: rgba[src..<(src + n * 4)])
        }
        let sdf = signedDistance(alpha: flipped, size: n)
        return GlyphBitmap(size: n, rgba: flipped, sdf: sdf)
    }

    // MARK: Distance transform (Felzenszwalb & Huttenlocher, exact Euclidean)

    static func signedDistance(alpha: [UInt8], size n: Int) -> [Float] {
        let inf = Float(n * n * 4)
        var inside = [Float](repeating: inf, count: n * n)
        var outside = [Float](repeating: inf, count: n * n)
        for i in 0..<(n * n) {
            let covered = alpha[i * 4 + 3] >= 128
            if covered { outside[i] = 0 } else { inside[i] = 0 }
        }
        edt2D(&inside, n)
        edt2D(&outside, n)
        var out = [Float](repeating: 0, count: n * n)
        let inv = 1 / Float(n)
        for i in 0..<(n * n) {
            // Coverage ≥ 0.5 marks the inside; sub-pixel edge refined by alpha.
            // `inside` holds distance to the nearest uncovered pixel, `outside` to the nearest covered one.
            let d = outside[i].squareRoot() - inside[i].squareRoot()
            let a = Float(alpha[i * 4 + 3]) / 255
            let refine = (0.5 - a)  // -0.5…0.5 px towards the true edge
            out[i] = (d + (abs(d) < 1.5 ? refine : 0)) * inv
        }
        return out
    }

    private static func edt2D(_ f: inout [Float], _ n: Int) {
        var scratch = [Float](repeating: 0, count: n)
        var d = [Float](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n + 1)
        // Columns
        for x in 0..<n {
            for y in 0..<n { scratch[y] = f[y * n + x] }
            edt1D(&scratch, &d, &v, &z, n)
            for y in 0..<n { f[y * n + x] = d[y] }
        }
        // Rows
        for y in 0..<n {
            for x in 0..<n { scratch[x] = f[y * n + x] }
            edt1D(&scratch, &d, &v, &z, n)
            for x in 0..<n { f[y * n + x] = d[x] }
        }
    }

    private static func edt1D(_ f: inout [Float], _ d: inout [Float], _ v: inout [Int], _ z: inout [Float], _ n: Int) {
        var k = 0
        v[0] = 0
        z[0] = -.infinity
        z[1] = .infinity
        for q in 1..<n {
            var s: Float
            while true {
                let p = v[k]
                s = ((f[q] + Float(q * q)) - (f[p] + Float(p * p))) / Float(2 * (q - p))
                if s <= z[k] && k > 0 { k -= 1 } else { break }
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = .infinity
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Float(q) { k += 1 }
            let p = v[k]
            d[q] = Float((q - p) * (q - p)) + f[p]
        }
    }
}

/// Builds and caches the two texture arrays (colour, distance) for the
/// distinct glyphs a scene uses. One per renderer.
final class GlyphAtlas: @unchecked Sendable {
    static let maxSlices = 32
    static let sliceSize = 1024

    private let device: MTLDevice
    private let lock = NSLock()
    private var bitmaps: [String: GlyphBitmap] = [:]
    private var builtKey: String = ""
    private var colorArray: MTLTexture?
    private var sdfArray: MTLTexture?
    let sampler: MTLSamplerState?

    init(device: MTLDevice) {
        self.device = device
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear; sd.mipFilter = .notMipmapped
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        sd.normalizedCoordinates = true
        sampler = device.makeSamplerState(descriptor: sd)
    }

    /// Texture arrays whose slice `i` holds `glyphs[i]`. Returns a 1-slice
    /// placeholder pair when the scene has no glyphs.
    func textures(for glyphs: [String]) -> (color: MTLTexture, sdf: MTLTexture)? {
        lock.lock(); defer { lock.unlock() }
        let list = Array(glyphs.prefix(GlyphAtlas.maxSlices))
        let key = list.joined(separator: "\u{1F}")
        if key == builtKey, let c = colorArray, let s = sdfArray { return (c, s) }
        let n = GlyphAtlas.sliceSize
        let count = max(list.count, 1)
        let cd = MTLTextureDescriptor()
        cd.textureType = .type2DArray; cd.pixelFormat = .rgba8Unorm; cd.width = n; cd.height = n; cd.arrayLength = count
        cd.usage = .shaderRead; cd.storageMode = .shared
        let sd = MTLTextureDescriptor()
        sd.textureType = .type2DArray; sd.pixelFormat = .r32Float; sd.width = n; sd.height = n; sd.arrayLength = count
        sd.usage = .shaderRead; sd.storageMode = .shared
        guard let color = device.makeTexture(descriptor: cd), let sdf = device.makeTexture(descriptor: sd) else { return nil }
        for (i, g) in list.enumerated() {
            let bmp: GlyphBitmap
            if let cached = bitmaps[g] { bmp = cached } else { bmp = GlyphRasterizer.render(g, size: n); bitmaps[g] = bmp }
            bmp.rgba.withUnsafeBytes { buf in
                color.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, slice: i, withBytes: buf.baseAddress!, bytesPerRow: n * 4, bytesPerImage: n * n * 4)
            }
            bmp.sdf.withUnsafeBytes { buf in
                sdf.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, slice: i, withBytes: buf.baseAddress!, bytesPerRow: n * 4, bytesPerImage: n * n * 4)
            }
        }
        if list.isEmpty {
            // Placeholder: fully "outside" everywhere.
            let far = [Float](repeating: 1, count: n * n)
            far.withUnsafeBytes { buf in
                sdf.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, slice: 0, withBytes: buf.baseAddress!, bytesPerRow: n * 4, bytesPerImage: n * n * 4)
            }
        }
        builtKey = key
        colorArray = color
        sdfArray = sdf
        return (color, sdf)
    }
}

public extension String {
    /// The glyph tokens in a shape's text: whitespace-separated words that
    /// carry a `sf:` or `file:` prefix are one glyph each; everything else
    /// splits into user-perceived characters, so each emoji is one glyph.
    var glyphs: [String] {
        var out: [String] = []
        for word in split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            let w = String(word)
            if w.hasPrefix("sf:") || w.hasPrefix("file:") { out.append(w) }
            else { out.append(contentsOf: w.map { String($0) }) }
        }
        return out
    }
}
