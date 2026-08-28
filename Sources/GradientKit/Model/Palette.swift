//
//  Palette.swift
//  GradientKit
//
//  Six colour roles that every motif recipe is written against, so one
//  composition can be re-dressed in any palette. Curated palettes are
//  lifted from the reference wallpapers; generated ones are built in
//  OKLCH so lightness and chroma are perceptually honest.
//

import Foundation

public struct Palette: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Mood: String, Codable, Sendable, CaseIterable { case dark, light }

    public var name: String
    /// The dominant ground.
    public var base: RGBA
    /// A second ground hue the background drifts towards.
    public var baseAlt: RGBA
    /// The saturated seam / rim colour — the one people remember.
    public var accent: RGBA
    /// A second hue for two-tone rims and secondary blobs.
    public var secondary: RGBA
    /// The brightest colour: a tinted near-white for rims and orbs.
    public var highlight: RGBA
    /// The darkest: a tinted near-black for discs and horizons.
    public var deep: RGBA
    public var mood: Mood

    public var id: String { name }

    public init(name: String, base: RGBA, baseAlt: RGBA, accent: RGBA, secondary: RGBA,
                highlight: RGBA, deep: RGBA, mood: Mood) {
        self.name = name; self.base = base; self.baseAlt = baseAlt; self.accent = accent
        self.secondary = secondary; self.highlight = highlight; self.deep = deep; self.mood = mood
    }

    /// All six roles, in a stable order.
    public var colors: [RGBA] { [base, baseAlt, accent, secondary, highlight, deep] }

    // MARK: Curated

    private static func hex(_ s: String) -> RGBA { RGBA(hex: s)! }

    public static let iris = Palette(
        name: "Iris", base: hex("#E9C6F5"), baseAlt: hex("#F2A6DE"), accent: hex("#FF4553"),
        secondary: hex("#86B6FF"), highlight: hex("#3DE8F2"), deep: hex("#0A090D"), mood: .light)

    public static let eclipse = Palette(
        name: "Eclipse", base: hex("#061421"), baseAlt: hex("#0B2C4C"), accent: hex("#23D5FF"),
        secondary: hex("#1E7CC4"), highlight: hex("#CFF7FF"), deep: hex("#010204"), mood: .dark)

    public static let lunar = Palette(
        name: "Lunar", base: hex("#4D5CE0"), baseAlt: hex("#1D2250"), accent: hex("#A9B2FF"),
        secondary: hex("#7C86F0"), highlight: hex("#F8F6FF"), deep: hex("#14173A"), mood: .dark)

    public static let ember = Palette(
        name: "Ember", base: hex("#0B0A0A"), baseAlt: hex("#1B1212"), accent: hex("#FF3B2E"),
        secondary: hex("#FF8A5C"), highlight: hex("#C7D0D2"), deep: hex("#000000"), mood: .dark)

    public static let lagoon = Palette(
        name: "Lagoon", base: hex("#16E1E6"), baseAlt: hex("#0B2434"), accent: hex("#F1935C"),
        secondary: hex("#F6C79E"), highlight: hex("#BDF5F2"), deep: hex("#071A26"), mood: .dark)

    public static let mint = Palette(
        name: "Mint", base: hex("#0C3A45"), baseAlt: hex("#0A2A38"), accent: hex("#7CE05A"),
        secondary: hex("#37B57C"), highlight: hex("#EEFBF1"), deep: hex("#061E26"), mood: .dark)

    public static let cherryCream = Palette(
        name: "Cherry Cream", base: hex("#F4ECD9"), baseAlt: hex("#FFD9C9"), accent: hex("#FF2A4B"),
        secondary: hex("#FF7AA0"), highlight: hex("#FFF7EA"), deep: hex("#3A1A86"), mood: .light)

    public static let reef = Palette(
        name: "Reef", base: hex("#123F45"), baseAlt: hex("#0E2E37"), accent: hex("#F0894A"),
        secondary: hex("#F5C89B"), highlight: hex("#FFE8CB"), deep: hex("#08232A"), mood: .dark)

    public static let solar = Palette(
        name: "Solar", base: hex("#060606"), baseAlt: hex("#101425"), accent: hex("#F5C14E"),
        secondary: hex("#1F3FE6"), highlight: hex("#FFF2BA"), deep: hex("#000000"), mood: .dark)

    public static let orchid = Palette(
        name: "Orchid", base: hex("#2A0F3D"), baseAlt: hex("#160822"), accent: hex("#FF6FD8"),
        secondary: hex("#8A5CFF"), highlight: hex("#FFE6FA"), deep: hex("#0E0416"), mood: .dark)

    public static let seaGlass = Palette(
        name: "Sea Glass", base: hex("#DDF3EE"), baseAlt: hex("#BFE9F6"), accent: hex("#FF8C42"),
        secondary: hex("#2BB3C0"), highlight: hex("#FFFFFF"), deep: hex("#0E2A33"), mood: .light)

    public static let peach = Palette(
        name: "Peach", base: hex("#FFE3D3"), baseAlt: hex("#FFC9B6"), accent: hex("#FF5A3C"),
        secondary: hex("#8E5BFF"), highlight: hex("#FFF8F2"), deep: hex("#2B1030"), mood: .light)

    public static let curated: [Palette] = [
        .iris, .eclipse, .lunar, .ember, .lagoon, .mint, .cherryCream, .reef, .solar, .orchid, .seaGlass, .peach,
    ]

    public static func named(_ name: String) -> Palette? {
        curated.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: Generated

    /// Build a palette in OKLCH from a seed. Hue relationships are chosen
    /// from a small set of harmonies (split-complement, analogous-with-a-
    /// clash, triad) that all read well at wallpaper scale.
    public static func generate(mood: Mood, using rng: inout SeededRandom) -> Palette {
        let h0 = rng.double(in: 0...360)
        let harmony = rng.int(in: 0...2)
        let hAccent: Double
        let hSecondary: Double
        switch harmony {
        case 0:   // split-complement
            hAccent = h0 + 180 + rng.double(in: -30...30)
            hSecondary = h0 + 180 - (hAccent - h0 - 180)
        case 1:   // analogous ground, one clashing accent
            hAccent = h0 + rng.sign() * rng.double(in: 100...150)
            hSecondary = h0 + rng.sign() * rng.double(in: 25...45)
        default:  // triad
            hAccent = h0 + 120
            hSecondary = h0 + 240
        }
        func jitter(_ h: Double) -> Double { h + rng.jitter(6) }

        switch mood {
        case .dark:
            let baseC = rng.double(in: 0.02...0.07)
            return Palette(
                name: "Generated",
                base: RGBA(l: rng.double(in: 0.12...0.22), c: baseC, h: jitter(h0)),
                baseAlt: RGBA(l: rng.double(in: 0.18...0.32), c: baseC * 1.8, h: jitter(h0 + 15)),
                accent: RGBA(l: rng.double(in: 0.68...0.8), c: rng.double(in: 0.16...0.24), h: jitter(hAccent)),
                secondary: RGBA(l: rng.double(in: 0.5...0.66), c: rng.double(in: 0.14...0.22), h: jitter(hSecondary)),
                highlight: RGBA(l: rng.double(in: 0.9...0.97), c: rng.double(in: 0.04...0.1), h: jitter(hAccent)),
                deep: RGBA(l: rng.double(in: 0.04...0.09), c: 0.02, h: jitter(h0)),
                mood: .dark)
        case .light:
            return Palette(
                name: "Generated",
                base: RGBA(l: rng.double(in: 0.86...0.93), c: rng.double(in: 0.04...0.09), h: jitter(h0)),
                baseAlt: RGBA(l: rng.double(in: 0.78...0.88), c: rng.double(in: 0.08...0.14), h: jitter(h0 + 25)),
                accent: RGBA(l: rng.double(in: 0.58...0.7), c: rng.double(in: 0.2...0.27), h: jitter(hAccent)),
                secondary: RGBA(l: rng.double(in: 0.7...0.8), c: rng.double(in: 0.12...0.18), h: jitter(hSecondary)),
                highlight: RGBA(l: rng.double(in: 0.94...0.98), c: 0.03, h: jitter(h0)),
                deep: RGBA(l: rng.double(in: 0.08...0.16), c: rng.double(in: 0.03...0.08), h: jitter(hAccent + 180)),
                mood: .light)
        }
    }

    public static func generate(mood: Mood, seed: UInt64) -> Palette {
        var rng = SeededRandom(seed: seed)
        return generate(mood: mood, using: &rng)
    }
}
