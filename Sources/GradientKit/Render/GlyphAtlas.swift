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

struct GlyphBitmap: Sendable {
    let size: Int
    /// Premultiplied RGBA, row-major, top row first.
    let rgba: [UInt8]
    /// Signed distance in units of the bitmap side (negative inside).
    let sdf: [Float]
}

enum GlyphRasterizer {
    /// Render `text` centred in a `size`×`size` bitmap, scaled so its ink
    /// fits `fill` of the box, and compute its signed distance field.
    static func render(_ text: String, size: Int = 512, fill: Double = 0.82) -> GlyphBitmap {
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
    /// The user-perceived characters (grapheme clusters) — each emoji,
    /// including multi-scalar ones, is one glyph.
    var glyphs: [String] { map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}
