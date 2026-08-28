//
//  RGBA.swift
//  GradientKit
//
//  A colour in sRGB (0...1 per channel, straight alpha) with the OKLab /
//  OKLCH machinery the renderer and the palette generator lean on. Every
//  gradient in GradientKit is interpolated in OKLab, so this is the one
//  place the maths lives — the Metal shader carries the same constants.
//

import Foundation

public struct RGBA: Codable, Sendable, Equatable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `#RRGGBB`, `#RRGGBBAA`, `RRGGBB`, `#RGB`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        r = Double((v >> (16 + shift)) & 0xFF) / 255
        g = Double((v >> (8 + shift)) & 0xFF) / 255
        b = Double((v >> shift) & 0xFF) / 255
        a = hasAlpha ? Double(v & 0xFF) / 255 : 1
    }

    /// Build from OKLCH (perceptual lightness 0...1, chroma ~0...0.37, hue in
    /// degrees). Out-of-gamut requests are mapped back into sRGB by reducing
    /// chroma while keeping lightness and hue — the hue never shifts.
    public init(l: Double, c: Double, h: Double, alpha: Double = 1) {
        let rad = h * .pi / 180
        self.init(lab: OKLab(l: l, a: c * cos(rad), b: c * sin(rad)), alpha: alpha)
    }

    /// Build from OKLab, gamut-mapping by chroma reduction if needed.
    public init(lab: OKLab, alpha: Double = 1) {
        var lab = lab
        var rgb = lab.linearRGB
        if !rgb.isInGamut {
            // Achromatic anchor — always in gamut for L in 0...1.
            let anchor = OKLab(l: min(max(lab.l, 0), 1), a: 0, b: 0)
            var lo = 0.0, hi = 1.0
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                let candidate = OKLab(l: anchor.l,
                                      a: lab.a * mid,
                                      b: lab.b * mid)
                if candidate.linearRGB.isInGamut { lo = mid } else { hi = mid }
            }
            lab = OKLab(l: anchor.l, a: lab.a * lo, b: lab.b * lo)
            rgb = lab.linearRGB
        }
        self.init(r: RGBA.encode(rgb.r), g: RGBA.encode(rgb.g), b: RGBA.encode(rgb.b), a: alpha)
        clampInPlace()
    }

    // MARK: Conversions

    public var hexString: String {
        let f = { (v: Double) -> String in String(format: "%02X", Int((min(max(v, 0), 1) * 255).rounded())) }
        return a < 1 ? "#\(f(r))\(f(g))\(f(b))\(f(a))" : "#\(f(r))\(f(g))\(f(b))"
    }

    /// Linear-light sRGB.
    public var linear: LinearRGB {
        LinearRGB(r: RGBA.decode(r), g: RGBA.decode(g), b: RGBA.decode(b))
    }

    public var oklab: OKLab { linear.oklab }

    public var oklch: (l: Double, c: Double, h: Double) {
        let lab = oklab
        let c = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        var h = atan2(lab.b, lab.a) * 180 / .pi
        if h < 0 { h += 360 }
        return (lab.l, c, h)
    }

    /// Relative luminance (linear light), 0...1.
    public var luminance: Double {
        let l = linear
        return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
    }

    public func with(alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    /// Shift OKLCH lightness by `dl` (and optionally chroma / hue), keeping
    /// the result in gamut.
    public func adjusted(lightness dl: Double = 0, chroma dc: Double = 0, hue dh: Double = 0) -> RGBA {
        let (l, c, h) = oklch
        return RGBA(l: min(max(l + dl, 0), 1), c: max(c + dc, 0), h: h + dh, alpha: a)
    }

    /// OKLab blend towards another colour.
    public func mixed(with other: RGBA, _ t: Double) -> RGBA {
        let x = oklab, y = other.oklab
        return RGBA(lab: OKLab(l: x.l + (y.l - x.l) * t,
                               a: x.a + (y.a - x.a) * t,
                               b: x.b + (y.b - x.b) * t),
                    alpha: a + (other.a - a) * t)
    }

    /// OKLab-blend through an ordered list of colours at `t` in 0...1.
    public static func sample(_ colors: [RGBA], at t: Double) -> RGBA {
        guard let first = colors.first else { return .black }
        guard colors.count > 1 else { return first }
        let u = min(max(t, 0), 1) * Double(colors.count - 1)
        let i = min(Int(u), colors.count - 2)
        return colors[i].mixed(with: colors[i + 1], u - Double(i))
    }

    // MARK: Transfer functions

    static func decode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func encode(_ v: Double) -> Double {
        let v = min(max(v, 0), 1)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private mutating func clampInPlace() {
        r = min(max(r, 0), 1); g = min(max(g, 0), 1); b = min(max(b, 0), 1); a = min(max(a, 0), 1)
    }

    // MARK: Constants

    public static let black = RGBA(r: 0, g: 0, b: 0)
    public static let white = RGBA(r: 1, g: 1, b: 1)
    public static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)
}

/// Linear-light sRGB (no transfer curve), unbounded.
public struct LinearRGB: Sendable, Equatable {
    public var r: Double, g: Double, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    public var isInGamut: Bool {
        let eps = 1e-6
        return r >= -eps && r <= 1 + eps && g >= -eps && g <= 1 + eps && b >= -eps && b <= 1 + eps
    }

    public var oklab: OKLab {
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return OKLab(l: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                     a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                     b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    public var rgba: RGBA { RGBA(r: RGBA.encode(r), g: RGBA.encode(g), b: RGBA.encode(b)) }
}

/// Björn Ottosson's OKLab: perceptual lightness `l` 0...1, `a`/`b` opponent axes.
public struct OKLab: Sendable, Equatable {
    public var l: Double, a: Double, b: Double
    public init(l: Double, a: Double, b: Double) { self.l = l; self.a = a; self.b = b }

    public var linearRGB: LinearRGB {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        return LinearRGB(r: 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S,
                         g: -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S,
                         b: -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S)
    }
}
