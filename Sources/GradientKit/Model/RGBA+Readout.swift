//
//  RGBA+Readout.swift
//  GradientKit
//
//  The numbers a designer reads off a colour: other spaces to paste into
//  another tool, and the WCAG contrast a colour actually achieves. Nothing
//  here is used by the renderer — it is all for display and export.
//

import Foundation

public extension RGBA {
    // MARK: CMYK

    /// Naive CMYK, the same "device ink" conversion a browser's
    /// `device-cmyk()` does. Values are percentages, 0...100.
    ///
    /// This is NOT a colour-managed separation: there is no profile, no
    /// black generation policy and no ink limit, so a printer will not
    /// match it. It is for reading a rough ink mix off a swatch, not for
    /// sending to press.
    var cmyk: (c: Double, m: Double, y: Double, k: Double) {
        let k = 1 - max(r, max(g, b))
        guard k < 1 else { return (0, 0, 0, 100) }
        let d = 1 - k
        return (((1 - r - k) / d) * 100, ((1 - g - k) / d) * 100, ((1 - b - k) / d) * 100, k * 100)
    }

    var cmykString: String {
        let (c, m, y, k) = cmyk
        return String(format: "%.0f, %.0f, %.0f, %.0f", c, m, y, k)
    }

    // MARK: Display P3

    /// The same colour in Display P3, components 0...1. sRGB is a subset of
    /// P3, so every sRGB colour has an exact P3 form (the numbers are
    /// smaller because P3's primaries are further out).
    var displayP3: (r: Double, g: Double, b: Double) {
        let l = linear
        // sRGB linear → XYZ (D65)
        let x = 0.4123907993 * l.r + 0.3575843394 * l.g + 0.1804807884 * l.b
        let y = 0.2126390059 * l.r + 0.7151686788 * l.g + 0.0721923154 * l.b
        let z = 0.0193308187 * l.r + 0.1191947798 * l.g + 0.9505321522 * l.b
        // XYZ (D65) → Display P3 linear
        let pr = 2.4934969119 * x - 0.9313836179 * y - 0.4027107845 * z
        let pg = -0.8294889696 * x + 1.7626640603 * y + 0.0236246858 * z
        let pb = 0.0358458302 * x - 0.0761723893 * y + 0.9568845240 * z
        return (RGBA.encode(pr), RGBA.encode(pg), RGBA.encode(pb))
    }

    var displayP3String: String {
        let p = displayP3
        return String(format: "color(display-p3 %.4f %.4f %.4f)", p.r, p.g, p.b)
    }

    var oklchString: String {
        let (l, c, h) = oklch
        return String(format: "oklch(%.1f%% %.3f %.1f)", l * 100, c, h)
    }

    var rgbString: String {
        String(format: "rgb(%.0f, %.0f, %.0f)", r * 255, g * 255, b * 255)
    }

    // MARK: Contrast

    /// WCAG 2.1 contrast ratio, 1...21. Symmetric.
    func contrastRatio(with other: RGBA) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Black or white, whichever this colour carries more contrast against —
    /// the readable ink for a label sitting on it.
    var readableInk: RGBA {
        contrastRatio(with: .black) >= contrastRatio(with: .white) ? .black : .white
    }

    /// What a pairing passes at. Thresholds are WCAG 2.1: normal text needs
    /// 4.5 for AA and 7 for AAA; large text (18pt, or 14pt bold) needs 3
    /// and 4.5. `fail` means it does not reach AA even at large sizes.
    enum ContrastGrade: String, Sendable, CaseIterable {
        case aaa = "AAA", aa = "AA", aaLarge = "AA Large", fail = "Fail"

        public var passesBodyText: Bool { self == .aaa || self == .aa }
    }

    func contrastGrade(on background: RGBA) -> ContrastGrade {
        let ratio = contrastRatio(with: background)
        if ratio >= 7 { return .aaa }
        if ratio >= 4.5 { return .aa }
        if ratio >= 3 { return .aaLarge }
        return .fail
    }

    /// Every readout for one swatch, for a JSON payload or an inspector row.
    var readout: Readout {
        let (c, m, y, k) = cmyk
        let (ol, oc, oh) = oklch
        let p = displayP3
        return Readout(hex: hexString,
                       rgb: [r * 255, g * 255, b * 255].map { ($0).rounded() },
                       oklch: [ol * 100, oc, oh],
                       cmyk: [c, m, y, k].map { $0.rounded() },
                       displayP3: [p.r, p.g, p.b],
                       contrastOnWhite: contrastRatio(with: .white),
                       contrastOnBlack: contrastRatio(with: .black),
                       grade: contrastGrade(on: readableInk).rawValue)
    }

    struct Readout: Codable, Sendable, Equatable {
        public var hex: String
        public var rgb: [Double]
        public var oklch: [Double]
        public var cmyk: [Double]
        public var displayP3: [Double]
        public var contrastOnWhite: Double
        public var contrastOnBlack: Double
        /// The grade this colour reaches against whichever of black/white
        /// suits it better — i.e. the best a label on it can do.
        public var grade: String
    }
}
