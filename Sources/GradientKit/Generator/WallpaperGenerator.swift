//
//  WallpaperGenerator.swift
//  GradientKit
//
//  Seeded compositions. Each motif is a recipe written against the six
//  palette roles, with every position, radius, spread and ramp jittered
//  from the seed — so one motif gives a family of wallpapers, and a seed
//  is a permanent address for one of them.
//

import Foundation

public enum Motif: String, Codable, Sendable, CaseIterable, Identifiable {
    /// A black disc off the top edge with a bright rim decaying into a dark ground.
    case eclipse
    /// A luminous sphere, soft-edged, sitting in a coloured glow.
    case orb
    /// A pastel sky cut by a dark diagonal with a glowing seam.
    case horizon
    /// A curved hill with a warm rim rising through a two-tone ground.
    case hill
    /// A light ground with saturated blobs and a dark crescent.
    case crescent
    /// A dim moon and a one-sided glowing ring on black.
    case halo
    /// Warped, overlapping colour fields — the loosest of the set.
    case aurora

    public var id: String { rawValue }

    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The palette mood the recipe was designed around.
    public var preferredMood: Palette.Mood {
        switch self {
        case .eclipse, .hill, .halo, .aurora: .dark
        case .orb: .dark
        case .horizon, .crescent: .light
        }
    }
}

public struct WallpaperGenerator: Sendable {
    public var seed: UInt64

    public init(seed: UInt64) { self.seed = seed }

    /// A motif (random if nil) in a palette (curated-or-generated if nil).
    /// `aspect` (width ÷ height) lets recipes that anchor to an edge keep
    /// their composition in portrait; it does not change the scene for any
    /// landscape aspect.
    public func make(_ motif: Motif? = nil, palette: Palette? = nil, aspect: Double = 16.0 / 9.0) -> Wallpaper {
        var rng = SeededRandom(seed: seed)
        let motif = motif ?? rng.pick(Motif.allCases)
        let palette = palette ?? WallpaperGenerator.choosePalette(for: motif, using: &rng)
        var recipe = Recipe(rng: rng.fork(), palette: palette, aspect: aspect)
        var wallpaper: Wallpaper
        switch motif {
        case .eclipse: wallpaper = recipe.eclipse()
        case .orb: wallpaper = recipe.orb()
        case .horizon: wallpaper = recipe.horizon()
        case .hill: wallpaper = recipe.hill()
        case .crescent: wallpaper = recipe.crescent()
        case .halo: wallpaper = recipe.halo()
        case .aurora: wallpaper = recipe.aurora()
        }
        wallpaper.seed = UInt32(truncatingIfNeeded: seed)
        wallpaper.title = "\(motif.displayName) · \(palette.name) · \(seed)"
        return wallpaper
    }

    static func choosePalette(for motif: Motif, using rng: inout SeededRandom) -> Palette {
        let mood = motif.preferredMood
        if rng.bool(0.6) {
            let candidates = Palette.curated.filter { $0.mood == mood }
            return rng.pick(candidates.isEmpty ? Palette.curated : candidates)
        }
        return Palette.generate(mood: mood, using: &rng)
    }
}

public extension Wallpaper {
    static func generate(_ motif: Motif? = nil, palette: Palette? = nil, seed: UInt64,
                         aspect: Double = 16.0 / 9.0) -> Wallpaper {
        WallpaperGenerator(seed: seed).make(motif, palette: palette, aspect: aspect)
    }
}

// MARK: - Recipes

struct Recipe {
    var rng: SeededRandom
    let p: Palette
    /// Height of the canvas in min-side units' inverse: multiply a min-side
    /// length by this to get the same length as a fraction of the height.
    let minSideOverHeight: Double

    init(rng: SeededRandom, palette: Palette, aspect: Double) {
        self.rng = rng
        self.p = palette
        self.minSideOverHeight = min(1, max(aspect, 0.1))
    }

    // Shorthands
    private mutating func d(_ r: ClosedRange<Double>) -> Double { rng.double(in: r) }
    private mutating func jit(_ s: Double) -> Double { rng.jitter(s) }
    private mutating func chance(_ p: Double) -> Bool { rng.bool(p) }

    /// Slight per-seed drift of a palette colour so the same palette never
    /// renders twice identically.
    private mutating func drift(_ c: RGBA, l: Double = 0.03, h: Double = 6) -> RGBA {
        c.adjusted(lightness: jit(l), hue: jit(h))
    }

    private mutating func grain(_ base: Double = 0.065) -> Grain {
        Grain(intensity: base + jit(0.02), size: d(1.0...1.6), chroma: d(0.15...0.35), shadowBias: d(0.2...0.5))
    }

    private mutating func effects(vignette: Double = 0, warp: Double = 0, aberration: Double = 0) -> Effects {
        Effects(grain: grain(),
                vignette: Vignette(intensity: vignette, radius: d(0.45...0.7), softness: d(0.5...0.8)),
                warp: Warp(amount: warp, scale: d(0.8...1.6), octaves: 2),
                aberration: aberration)
    }

    // MARK: Eclipse

    mutating func eclipse() -> Wallpaper {
        let deep = drift(p.deep, l: 0.01)
        let base = drift(p.base)
        let accent = drift(p.accent)
        let secondary = drift(p.secondary)
        let highlight = drift(p.highlight, l: 0.02, h: 3)

        // Disc hangs off the top edge (or a top corner).
        let fromCorner = chance(0.35)
        let cx = fromCorner ? (chance(0.5) ? d(0.05...0.25) : d(0.75...0.95)) : 0.5 + jit(0.12)
        let cy = fromCorner ? d(0.0...0.25) : d(-0.3...(-0.02))
        let radius = fromCorner ? d(0.5...0.75) : d(0.55...0.85)
        let spread = d(0.32...0.5)

        var background = Background.radial([drift(p.baseAlt), base, deep],
                                           center: [cx, cy + radius * 0.6],
                                           radius: radius + d(0.9...1.4), smoothing: 0.5)
        if chance(0.3) {
            background = .linear([drift(p.baseAlt), base, deep], angle: 90 + jit(25), smoothing: 0.4)
        }

        let rimWidth = d(0.03...0.08)
        var layers: [Layer] = [
            Layer(name: "Eclipse",
                  shape: .circle(center: [cx, cy], radius: radius),
                  spread: spread,
                  ramp: [
                      RampStop(-1.0, deep),
                      RampStop(-0.02, deep),
                      RampStop(rimWidth, highlight),
                      RampStop(rimWidth + d(0.1...0.2), accent),
                      RampStop(d(0.45...0.65), secondary),
                      RampStop(d(1.1...1.5), base.with(alpha: 0)),
                  ],
                  smoothing: 1,
                  lighting: Lighting(angle: 90 + jit(40), amount: d(0.0...0.35))),
        ]

        // Two-tone rim: a second colour lit from the other side.
        if chance(0.45) {
            let side = d(0...360)
            layers[0].lighting = Lighting(angle: side, amount: d(0.5...0.8))
            layers.append(Layer(name: "Second rim",
                                shape: .circle(center: [cx + jit(0.01), cy + jit(0.01)], radius: radius),
                                spread: spread * d(0.7...1.0),
                                ramp: [
                                    RampStop(-0.02, deep.with(alpha: 0)),
                                    RampStop(rimWidth * 0.8, highlight.mixed(with: secondary, 0.35)),
                                    RampStop(rimWidth + 0.15, secondary),
                                    RampStop(0.5, secondary.adjusted(lightness: -0.2)),
                                    RampStop(1.2, base.with(alpha: 0)),
                                ],
                                blend: .screen,
                                opacity: d(0.7...1),
                                lighting: Lighting(angle: side + 180 + jit(30), amount: d(0.7...0.9))))
        }

        var w = Wallpaper(background: background, layers: layers,
                          effects: effects(vignette: d(0...0.25), warp: chance(0.3) ? d(0.005...0.02) : 0,
                                           aberration: chance(0.4) ? d(0.5...2) : 0))
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    // MARK: Orb

    mutating func orb() -> Wallpaper {
        let base = drift(p.base)
        let baseAlt = drift(p.baseAlt)
        let accent = drift(p.accent)
        let secondary = drift(p.secondary)
        let highlight = drift(p.highlight, l: 0.01, h: 3)

        let cx = chance(0.5) ? d(0.6...0.85) : d(0.15...0.4)
        let cy = d(0.35...0.75)
        let radius = d(0.3...0.5)
        let angle = 20 + jit(40) + (cx < 0.5 ? 180 : 0)
        let background = Background.linear([baseAlt, base, drift(secondary, l: 0.02)],
                                           angle: angle, smoothing: 0.4)

        // The rim is brightest on the side facing away from the frame centre.
        let litFrom = atan2(cy - 0.5, cx - 0.5) * 180 / .pi + jit(35)
        let rim = chance(0.5)
        var ramp: [RampStop]
        if rim {
            // Mint-style: pale core, a thin white rim, saturated glow outside.
            ramp = [
                RampStop(-1.2, highlight.mixed(with: accent, 0.25)),
                RampStop(-0.35, highlight.mixed(with: base, 0.1)),
                RampStop(-0.04, highlight),
                RampStop(0.03, highlight),
                RampStop(0.14, accent),
                RampStop(0.55, accent.mixed(with: base, 0.55)),
                RampStop(1.4, base.with(alpha: 0)),
            ]
        } else {
            // Lunar-style: a soft white sphere sinking into its own glow.
            ramp = [
                RampStop(-1.4, highlight.mixed(with: secondary, 0.2)),
                RampStop(-0.3, highlight),
                RampStop(0.06, highlight.mixed(with: accent, 0.35)),
                RampStop(0.45, accent),
                RampStop(1.3, base.with(alpha: 0)),
            ]
        }
        // A broad underglow so the sphere sits in light rather than on a flat ground.
        let glow = Layer(name: "Glow",
                         shape: .circle(center: [cx + jit(0.05), cy + jit(0.05)], radius: radius * d(0.8...1.0)),
                         spread: d(0.4...0.6),
                         ramp: [RampStop(-0.3, secondary), RampStop(0.2, secondary.mixed(with: base, 0.3)), RampStop(1.2, base.with(alpha: 0))],
                         opacity: d(0.4...0.8),
                         smoothing: 1)
        let orb = Layer(name: "Orb",
                        shape: .circle(center: [cx, cy], radius: radius),
                        spread: rim ? d(0.16...0.26) : d(0.24...0.38),
                        ramp: ramp,
                        smoothing: 1,
                        lighting: Lighting(angle: litFrom, amount: rim ? d(0.5...0.75) : d(0.15...0.35)))
        var w = Wallpaper(background: background, layers: [glow, orb],
                          effects: effects(vignette: d(0...0.2), warp: chance(0.25) ? d(0.005...0.015) : 0,
                                           aberration: chance(0.3) ? d(0.5...1.5) : 0))
        w.effects.grain.intensity = d(0.05...0.085)
        return w
    }

    // MARK: Horizon

    mutating func horizon() -> Wallpaper {
        let base = drift(p.base)
        let baseAlt = drift(p.baseAlt)
        let accent = drift(p.accent)
        let secondary = drift(p.secondary)
        let highlight = drift(p.highlight, l: 0.02, h: 3)
        let deep = drift(p.deep, l: 0.01)

        // Sky: three or four hues sweeping from the near corner to the far one.
        let flip = chance(0.5)   // dark side on the right (false) or the left (true)
        let skyAngle = (flip ? -150 : -30) + jit(15)
        let background = Background.linear(
            stops: [RampStop(0, baseAlt), RampStop(0.45, base), RampStop(0.8, secondary), RampStop(1, highlight)],
            angle: skyAngle, smoothing: 0.3)

        // The seam: a half-plane, dark inside, a wide warm glow on the light side.
        let through: Vec2 = [flip ? d(0.3...0.45) : d(0.55...0.7), d(0.6...0.8)]
        let normal = (flip ? -45 : -135) + jit(12)
        let seam = Layer(name: "Horizon",
                         shape: .line(through: through, angle: normal, bend: d(0.04...0.15)),
                         spread: d(0.42...0.58),
                         ramp: [
                             RampStop(-1.0, deep),
                             RampStop(-0.5, deep),
                             RampStop(-0.12, deep.mixed(with: accent, 0.35)),
                             RampStop(0.0, accent.adjusted(lightness: -0.12)),
                             RampStop(0.16, accent),
                             RampStop(0.4, accent.mixed(with: baseAlt, 0.45)),
                             RampStop(d(0.75...1.0), baseAlt.with(alpha: 0)),
                         ],
                         smoothing: 1)

        // A warm pool where the seam meets the near corner.
        let pool = Layer(name: "Pool",
                         shape: .ellipse(center: [flip ? d(0.8...0.95) : d(0.05...0.2), d(0.95...1.1)],
                                         radii: [d(0.35...0.5), d(0.2...0.3)], rotation: jit(20)),
                         spread: d(0.3...0.45),
                         ramp: [
                             RampStop(-0.5, accent.mixed(with: baseAlt, 0.35)),
                             RampStop(0.0, accent.mixed(with: baseAlt, 0.5)),
                             RampStop(1.0, baseAlt.with(alpha: 0)),
                         ],
                         opacity: d(0.6...0.95))

        var w = Wallpaper(background: background, layers: [pool, seam],
                          effects: effects(vignette: 0, warp: chance(0.4) ? d(0.005...0.02) : 0,
                                           aberration: chance(0.5) ? d(0.8...2.5) : 0))
        w.effects.grain.intensity = d(0.05...0.08)
        return w
    }

    // MARK: Hill

    mutating func hill() -> Wallpaper {
        let base = drift(p.base)
        let baseAlt = drift(p.baseAlt)
        let accent = drift(p.accent)
        let secondary = drift(p.secondary)
        let highlight = drift(p.highlight)
        let deep = drift(p.deep)

        // Ground: the base hue on the near side, deep on the far side.
        let flip = chance(0.5)
        let background = Background.linear(
            stops: [RampStop(0, base), RampStop(d(0.4...0.55), baseAlt), RampStop(1, deep)],
            angle: (flip ? 160 : 20) + jit(15), smoothing: 0.4)

        // A big disc sitting below the frame; only its crown shows.
        let cx = flip ? d(0.2...0.4) : d(0.6...0.8)
        let radius = d(0.85...1.25)
        // Place the crown at a fixed fraction of the height whatever the aspect.
        let crown = d(0.4...0.6)
        let cy = crown + radius * minSideOverHeight
        let hill = Layer(name: "Hill",
                         shape: .circle(center: [cx, cy], radius: radius),
                         spread: d(0.28...0.4),
                         ramp: [
                             RampStop(-2.2, highlight),
                             RampStop(-1.0, highlight.mixed(with: secondary, 0.45)),
                             RampStop(-0.45, secondary),
                             RampStop(-0.15, accent),
                             RampStop(0.12, accent.adjusted(lightness: -0.18)),
                             RampStop(0.45, accent.adjusted(lightness: -0.38, chroma: -0.06)),
                             RampStop(d(0.9...1.3), deep.with(alpha: 0)),
                         ],
                         smoothing: 1,
                         lighting: Lighting(angle: (flip ? -30 : -150) + jit(20), amount: d(0.35...0.6)))

        // A cool haze across the far side so the hill emerges from something.
        let haze = Layer(name: "Haze",
                         shape: .ellipse(center: [flip ? d(0.75...0.95) : d(0.05...0.25), d(0.1...0.4)],
                                         radii: [d(0.4...0.6), d(0.25...0.4)], rotation: jit(30)),
                         spread: d(0.4...0.6),
                         ramp: [RampStop(-0.4, base), RampStop(0.2, base.mixed(with: baseAlt, 0.4)), RampStop(1.2, deep.with(alpha: 0))],
                         opacity: d(0.4...0.8),
                         smoothing: 1)

        var w = Wallpaper(background: background, layers: [haze, hill],
                          effects: effects(vignette: d(0...0.2), warp: chance(0.5) ? d(0.008...0.025) : 0,
                                           aberration: chance(0.3) ? d(0.5...1.5) : 0))
        w.effects.grain.intensity = d(0.05...0.085)
        return w
    }

    // MARK: Crescent

    mutating func crescent() -> Wallpaper {
        let base = drift(p.base)
        let baseAlt = drift(p.baseAlt)
        let accent = drift(p.accent)
        let secondary = drift(p.secondary)
        let deep = drift(p.deep)

        let background = Background.linear([base, baseAlt], angle: d(0...360), smoothing: 0.5)

        let flip = chance(0.5)
        let blobA = Layer(name: "Blob A",
                          shape: .ellipse(center: [flip ? d(0.0...0.25) : d(0.75...1.0), d(0.2...0.5)],
                                          radii: [d(0.5...0.7), d(0.4...0.6)], rotation: jit(30)),
                          spread: d(0.45...0.65),
                          ramp: [RampStop(-0.8, accent), RampStop(-0.1, accent), RampStop(1.1, base.with(alpha: 0))],
                          smoothing: 1,
                          distortion: Distortion(amount: d(0.05...0.14), scale: d(0.8...1.6), octaves: 3))
        let blobB = Layer(name: "Blob B",
                          shape: .ellipse(center: [flip ? d(0.65...0.9) : d(0.1...0.35), d(0.75...1.05)],
                                          radii: [d(0.35...0.55), d(0.3...0.45)], rotation: jit(40)),
                          spread: d(0.45...0.7),
                          ramp: [RampStop(-0.6, secondary), RampStop(0.0, secondary), RampStop(1.2, base.with(alpha: 0))],
                          opacity: d(0.7...1),
                          smoothing: 1,
                          distortion: Distortion(amount: d(0.04...0.12), scale: d(0.8...1.6), octaves: 3))

        // A thick, soft arch: a disc with a slightly larger disc cut from below it.
        let cx = 0.5 + jit(0.12), cy = d(0.62...0.82)
        let radius = d(0.5...0.7)
        let cutOffset = radius * d(0.3...0.45)
        let moon = Layer(name: "Crescent",
                         shape: .crescent(center: [cx, cy], radius: radius,
                                          cutCenter: [cx + jit(0.08), cy + cutOffset], cutRadius: radius * d(1.0...1.12)),
                         spread: d(0.26...0.4),
                         ramp: [
                             RampStop(-1.0, deep),
                             RampStop(-0.45, deep),
                             RampStop(0.0, deep.mixed(with: accent, 0.5)),
                             RampStop(d(0.45...0.7), accent.with(alpha: 0)),
                         ],
                         smoothing: 1)

        var w = Wallpaper(background: background, layers: [blobA, blobB, moon],
                          effects: effects(vignette: 0, warp: d(0.01...0.03), aberration: chance(0.4) ? d(0.5...2) : 0))
        w.effects.grain.intensity = d(0.05...0.08)
        return w
    }

    // MARK: Halo

    mutating func halo() -> Wallpaper {
        let deep = drift(p.deep, l: 0.005)
        let base = drift(p.base)
        let accent = drift(p.accent)
        let secondary = drift(p.secondary)
        let highlight = drift(p.highlight)

        let background = Background.radial([base, deep], center: [0.5 + jit(0.2), 0.5 + jit(0.2)],
                                           radius: d(0.9...1.4), smoothing: 0.5)

        let cx = chance(0.5) ? d(0.6...0.8) : d(0.2...0.4)
        let cy = d(0.25...0.5)
        let moonRadius = d(0.24...0.36)
        let ringSide = 135 + jit(50) + (cx < 0.5 ? -90 : 0)   // the glowing arc faces the frame's centre
        let moon = Layer(name: "Moon",
                         shape: .circle(center: [cx, cy], radius: moonRadius),
                         spread: d(0.2...0.32),
                         ramp: [
                             RampStop(-1.2, highlight),
                             RampStop(-0.3, highlight.mixed(with: secondary, 0.3)),
                             RampStop(0.0, highlight.mixed(with: secondary, 0.55)),
                             RampStop(0.8, base.with(alpha: 0)),
                         ],
                         smoothing: 1,
                         lighting: Lighting(angle: ringSide + 180, amount: d(0.55...0.8)))

        let ringRadius = moonRadius * d(1.2...1.5)
        let ringCenter: Vec2 = [cx + jit(0.08), cy + d(0.06...0.2)]
        let ring = Layer(name: "Halo",
                         shape: .ring(center: ringCenter, radius: ringRadius, thickness: d(0.02...0.06)),
                         spread: d(0.1...0.2),
                         ramp: [
                             RampStop(-1.0, highlight.mixed(with: accent, 0.4)),
                             RampStop(0.0, accent),
                             RampStop(0.4, accent.mixed(with: secondary, 0.5).adjusted(lightness: -0.15)),
                             RampStop(1.2, deep.with(alpha: 0)),
                         ],
                         blend: .screen,
                         smoothing: 1,
                         lighting: Lighting(angle: ringSide, amount: d(0.85...0.97)))

        var w = Wallpaper(background: background, layers: [moon, ring],
                          effects: effects(vignette: d(0.1...0.35), warp: chance(0.3) ? d(0.005...0.015) : 0,
                                           aberration: chance(0.5) ? d(0.8...2.5) : 0))
        w.effects.grain.intensity = d(0.06...0.1)
        return w
    }

    // MARK: Aurora

    mutating func aurora() -> Wallpaper {
        let base = drift(p.base)
        let baseAlt = drift(p.baseAlt)
        let deep = drift(p.deep)
        let colors = [drift(p.accent), drift(p.secondary), drift(p.highlight, l: -0.2).mixed(with: p.accent, 0.3), drift(p.baseAlt, l: 0.2, h: 20)]
        let dark = p.mood == .dark
        let background = Background.linear([deep, base, baseAlt], angle: 90 + jit(40), smoothing: 0.5)

        // Curtains: undulating bands (a wave edge faded on both sides), each
        // bent further by its own noise, drifting across a domain-warped ground.
        var layers: [Layer] = []
        let count = 2 + (chance(0.35) ? 1 : 0)
        let tilt = d(-35...35)
        for i in 0..<count {
            let c = colors[i % colors.count]
            let y = d(0.15...0.85)
            let width = d(0.25...0.5)
            layers.append(Layer(name: "Curtain \(i + 1)",
                                shape: .wave(through: [0.5, y], angle: 90 + tilt + jit(15),
                                             amplitude: d(0.08...0.2), wavelength: d(1.8...3.5), phase: d(0...360)),
                                spread: width,
                                ramp: [
                                    RampStop(-1.3, c.with(alpha: 0)),
                                    RampStop(-0.5, c.mixed(with: base, 0.2)),
                                    RampStop(0.0, c),
                                    RampStop(0.35, c.mixed(with: base, 0.4)),
                                    RampStop(1.0, c.with(alpha: 0)),
                                ],
                                blend: dark ? .screen : .normal,
                                opacity: d(0.6...0.95),
                                smoothing: 1,
                                distortion: Distortion(amount: d(0.03...0.1), scale: d(0.7...1.4), octaves: 3)))
        }
        // One pool of light behind them.
        layers.insert(Layer(name: "Pool",
                            shape: .ellipse(center: [d(0.2...0.8), d(0.3...0.9)], radii: [d(0.4...0.7), d(0.25...0.45)], rotation: d(-40...40)),
                            spread: d(0.5...0.8),
                            ramp: [RampStop(-0.5, colors[3]), RampStop(0.2, colors[3].mixed(with: base, 0.4)), RampStop(1.2, base.with(alpha: 0))],
                            blend: dark ? .screen : .normal,
                            opacity: d(0.4...0.7),
                            smoothing: 1), at: 0)

        var w = Wallpaper(background: background, layers: layers,
                          effects: effects(vignette: dark ? d(0.1...0.3) : 0, warp: d(0.03...0.07),
                                           aberration: chance(0.4) ? d(0.5...2) : 0))
        w.effects.grain.intensity = d(0.06...0.1)
        return w
    }
}
