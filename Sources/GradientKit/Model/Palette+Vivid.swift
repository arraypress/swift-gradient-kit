//
//  Palette+Vivid.swift
//  GradientKit
//
//  The high-chroma end of the collection: a near-black ground with two
//  bright hues over it. Where the curated sets are photographic and the
//  Japanese sets are muted, these are the ones that glow — neon on dark,
//  the register a lot of modern gradient wallpaper lives in.
//
//  PROVENANCE. The colour relationships were taken by eye from the
//  reference gradients on feralui.dev, which is where this family of looks
//  was worked out. Hex values are data and these combinations are a common
//  idiom (dark base, two saturated hues a long way apart in hue), but the
//  NAMES are ours — theirs are their own work and not reused.
//
//  Each set arrives as three colours: the ground, and two hues. The other
//  three roles are derived in OKLab rather than written down, so they stay
//  in gamut and keep a consistent relationship to the source three.
//

import Foundation

public extension Palette {
    /// Build a palette from a ground and two hues, deriving the rest.
    ///
    /// `accent` is the hue that should carry a rim or a seam — the one the
    /// eye goes to; `secondary` is the support. `highlight` is pulled from
    /// whichever of the two is lighter so it never fights the accent.
    static func vivid(_ name: String, ground: String, accent: String, secondary: String) -> Palette {
        let deep = RGBA(hex: ground)!
        let a = RGBA(hex: accent)!
        let b = RGBA(hex: secondary)!
        let lighter = a.oklch.l >= b.oklch.l ? a : b
        return Palette(
            name: name,
            // The ground, lifted just off black and tinted by the support
            // hue, so the dark areas are never a flat neutral.
            base: deep.mixed(with: b, 0.10).adjusted(lightness: 0.03),
            baseAlt: deep.mixed(with: a, 0.14).adjusted(lightness: 0.06),
            accent: a,
            secondary: b,
            // A tinted near-white, not white: a pure white highlight on a
            // saturated ground reads as a blown-out hole.
            highlight: lighter.adjusted(lightness: 0.30, chroma: -0.06),
            deep: deep,
            mood: .dark)
    }

    /// Neon-on-dark sets. All `.dark`.
    static let vivid: [Palette] = [
        .vivid("Reactor",     ground: "#072B35", accent: "#DEFF58", secondary: "#31E7BC"),
        .vivid("Flamingo",    ground: "#420B32", accent: "#FF3B64", secondary: "#FF9362"),
        .vivid("Deep Signal", ground: "#101647", accent: "#388BFF", secondary: "#72F5DE"),
        .vivid("Nightbloom",  ground: "#270A57", accent: "#F171FF", secondary: "#8785FF"),
        .vivid("Sunfall",     ground: "#201542", accent: "#FF783E", secondary: "#C3A5FF"),
        .vivid("Poolight",    ground: "#073A3C", accent: "#46F2C3", secondary: "#DBF879"),
        .vivid("Sugar Ice",   ground: "#350D29", accent: "#FF5486", secondary: "#9DA9FF"),
        .vivid("Cold Brass",  ground: "#111F38", accent: "#83BEF9", secondary: "#F3DBB0"),
        .vivid("Rave",        ground: "#210655", accent: "#FF46D3", secondary: "#C6FF32"),
        .vivid("Voltage",     ground: "#090E42", accent: "#71FF36", secondary: "#FF39B0"),
        .vivid("Blaze",       ground: "#390718", accent: "#FF4A08", secondary: "#FFDF16"),
        .vivid("Cryo",        ground: "#090D56", accent: "#1AFFCE", secondary: "#4B8CFF"),
        .vivid("Neon Dusk",   ground: "#260D59", accent: "#FF7323", secondary: "#FF33B8"),
    ]
}
