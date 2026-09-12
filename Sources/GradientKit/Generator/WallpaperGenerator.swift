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
    /// A warped colour grid — the classic mesh gradient.
    case mesh
    /// Colour points blended by inverse distance, warped and swirled — the
    /// soft, painterly mesh gradient.
    case flow
    /// The same field pulled tight: distinct pools of colour with deep
    /// valleys between them.
    case smesh
    /// Long satin folds catching the light, hue turning along them.
    case silk
    /// Colour swept around a centre.
    case angular
    /// A lit honeycomb over a colour field.
    case beehive
    /// A grid of soft spheres.
    case orbs
    /// Out-of-focus discs of light.
    case bokeh
    /// Contour lines of a noise field over a dark ground — a topographic map.
    case topo
    /// Flowing stripes bent by noise, like ribbons of light.
    case ribbons
    /// A noise field mapped through the palette — clouds and nebulae.
    case nebula
    /// Hue that sweeps across a soft edge — holographic foil.
    case holo
    /// Flat colour bands stepping through a ramp — the colour ladder.
    case ladder
    /// Hard diagonal stripes between two flat fields — retro racing stripes.
    case retro
    /// Light leaks: soft beams across a dark ground.
    case beams
    /// A sunburst behind a soft glow.
    case rays
    /// Jagged ridges receding into haze.
    case mountains
    /// Smooth stacked dunes.
    case dunes
    /// A striped sun over a gradient sky.
    case sunset
    /// A plain two- or three-colour diagonal gradient with grain.
    case classic
    /// A planet's edge: a bright curved horizon over a dark sky.
    case glow

    public var id: String { rawValue }

    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    public enum Family: String, CaseIterable, Sendable, Identifiable {
        case soft, fields, surfaces, scenes, flat
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .soft: "Soft"
            case .fields: "Fields"
            case .surfaces: "Surfaces"
            case .scenes: "Scenes"
            case .flat: "Flat"
            }
        }
    }

    public var family: Family {
        switch self {
        case .eclipse, .orb, .horizon, .hill, .crescent, .halo, .glow, .classic, .beams, .rays, .bokeh: .soft
        case .aurora, .mesh, .nebula, .topo, .holo, .ribbons, .flow, .smesh, .silk, .angular: .fields
        case .beehive, .orbs: .surfaces
        case .mountains, .dunes, .sunset: .scenes
        case .ladder, .retro: .flat
        }
    }

    /// Motifs in gallery order, grouped by family.
    public static func grouped() -> [(Family, [Motif])] {
        Family.allCases.map { f in (f, allCases.filter { $0.family == f }) }
    }

    /// The palette mood the recipe was designed around.
    public var preferredMood: Palette.Mood {
        switch self {
        case .eclipse, .hill, .halo, .aurora, .topo, .nebula: .dark
        case .orb, .ribbons, .holo, .glow, .classic: .dark
        case .flow, .smesh, .silk, .angular: .light
        case .beehive, .orbs, .bokeh: .dark
        case .horizon, .crescent, .mesh, .ladder, .retro: .light
        case .beams, .rays, .mountains: .dark
        case .dunes, .sunset: .light
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
        let explicitPalette = palette
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
        case .mesh: wallpaper = recipe.mesh()
        case .flow: wallpaper = recipe.flow()
        case .smesh: wallpaper = recipe.smesh()
        case .silk: wallpaper = recipe.silk()
        case .angular: wallpaper = recipe.angular()
        case .beehive: wallpaper = recipe.beehive()
        case .orbs: wallpaper = recipe.orbs()
        case .bokeh: wallpaper = recipe.bokeh()
        case .topo: wallpaper = recipe.topo()
        case .ribbons: wallpaper = recipe.ribbons()
        case .nebula: wallpaper = recipe.nebula()
        case .holo: wallpaper = recipe.holo()
        case .ladder: wallpaper = recipe.ladder()
        case .retro: wallpaper = recipe.retro()
        case .beams: wallpaper = recipe.beams()
        case .rays: wallpaper = recipe.rays()
        case .mountains: wallpaper = recipe.mountains()
        case .dunes: wallpaper = recipe.dunes()
        case .sunset: wallpaper = recipe.sunset()
        case .classic: wallpaper = recipe.classic()
        case .glow: wallpaper = recipe.glow()
        }
        wallpaper.seed = UInt32(truncatingIfNeeded: seed)
        wallpaper.title = "\(motif.displayName) · \(palette.name) · \(seed)"
        wallpaper.palette = palette
        wallpaper.origin = Wallpaper.Origin(motif: motif.rawValue, seed: seed, paletteName: explicitPalette?.name)
        return wallpaper
    }

    /// The palette `make` would choose for this motif and seed when none is given.
    public static func autoPalette(for motif: Motif, seed: UInt64) -> Palette {
        var rng = SeededRandom(seed: seed)
        return choosePalette(for: motif, using: &rng)
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
    let aspect: Double

    init(rng: SeededRandom, palette: Palette, aspect: Double) {
        self.rng = rng
        self.p = palette
        self.aspect = max(aspect, 0.1)
        self.minSideOverHeight = min(1, max(aspect, 0.1))
    }

    /// A fraction of the canvas width / height expressed in min-side units.
    func widthUnits(_ fraction: Double) -> Double { fraction * aspect / minSideOverHeight }
    func heightUnits(_ fraction: Double) -> Double { fraction / minSideOverHeight }

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

    // MARK: Mesh

    mutating func mesh() -> Wallpaper {
        // A 3×3 (sometimes 4×3) grid of palette colours, warped hard.
        let cols = chance(0.4) ? 4 : 3, rows = 3
        // Saturated cells dominate; the ground colours only appear as accents.
        let vivid = [drift(p.accent), drift(p.accent, h: 30), drift(p.secondary), drift(p.secondary, h: -25),
                     drift(p.accent).adjusted(lightness: 0.12, chroma: 0.04), drift(p.secondary).adjusted(lightness: -0.12, chroma: 0.04)]
        let calm = [drift(p.base), drift(p.baseAlt), drift(p.highlight, l: -0.05)]
        var cells: [RGBA] = []
        for _ in 0..<(cols * rows) {
            let c = chance(0.7) ? rng.pick(vivid) : rng.pick(calm)
            cells.append(c.adjusted(lightness: jit(0.04), hue: jit(10)))
        }
        cells[rng.int(in: 0...(cells.count - 1))] = drift(p.deep)
        let background = Background.mesh(cells, columns: cols, smoothing: d(0.6...1))
        var w = Wallpaper(background: background, layers: [],
                          effects: effects(vignette: 0, warp: d(0.08...0.18), aberration: chance(0.3) ? d(0.5...1.5) : 0))
        w.effects.warp.scale = d(0.6...1.2)
        w.effects.warp.octaves = 3
        w.effects.grain.intensity = d(0.05...0.08)
        return w
    }

    // MARK: Flow / Smesh — inverse-distance colour points

    /// Shared body for the two point-field motifs.
    mutating func pointField(mixing: ClosedRange<Double>, swirl: ClosedRange<Double>,
                             warp: ClosedRange<Double>, count: ClosedRange<Int>) -> Wallpaper {
        let vivid = [drift(p.accent), drift(p.accent, h: 28), drift(p.secondary),
                     drift(p.secondary, h: -22), drift(p.highlight)]
        let n = rng.int(in: count)
        var pts: [MeshPoint] = []
        // Golden-angle placement, jittered: even coverage without a grid's
        // repetition and without two points landing on top of each other.
        let golden = 2.39996322972865332
        let reach = d(0.42...0.58)
        for i in 0..<n {
            let t = n > 1 ? Double(i) / Double(n - 1) : 0
            // Push points out towards the edges: clustered near the middle
            // they all average together and the field goes muddy.
            let r = reach * (0.45 + 0.55 * t.squareRoot())
            let a = Double(i) * golden + jit(0.35)
            let isDeep = i == n - 1 && chance(0.3)
            let c = isDeep ? drift(p.deep).mixed(with: drift(p.base), 0.3) : rng.pick(vivid)
            pts.append(MeshPoint(position: [0.5 + r * cos(a) + jit(0.04), 0.5 + r * sin(a) + jit(0.04)],
                                 color: c.adjusted(lightness: jit(0.05), hue: jit(8)),
                                 // A near-black point at full weight swallows
                                 // the frame; give it less pull than the rest.
                                 weight: isDeep ? d(0.35...0.6) : d(0.8...1.3)))
        }
        let background = Background.points(pts, mixing: d(mixing), swirl: d(swirl))
        var w = Wallpaper(background: background, layers: [],
                          effects: effects(vignette: chance(0.4) ? d(0.08...0.2) : 0,
                                           warp: d(warp),
                                           aberration: chance(0.3) ? d(0.5...1.6) : 0))
        w.effects.warp.scale = d(0.5...1.1)
        w.effects.warp.octaves = 3
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    mutating func flow() -> Wallpaper {
        pointField(mixing: 1.4...1.9, swirl: -1.6...1.6, warp: 0.04...0.13, count: 4...7)
    }

    mutating func smesh() -> Wallpaper {
        pointField(mixing: 2.0...2.8, swirl: -0.6...0.6, warp: 0.02...0.07, count: 5...8)
    }

    // MARK: Silk

    mutating func silk() -> Wallpaper {
        let deep = drift(p.deep), accent = drift(p.accent)
        let secondary = drift(p.secondary), highlight = drift(p.highlight)
        let angle = d(-150...(-30))
        let background = Background.linear([deep, drift(p.base)], angle: angle + 90, smoothing: 0.6)
        // Satin is ONE colour seen at different angles, so the ramp is a
        // lightness ladder through a single hue with only a few degrees of
        // turn. A wide hue sweep here reads as marble, not cloth.
        let cloth = chance(0.5) ? accent : secondary
        let sheen = Layer(name: "Satin",
                          shape: .cloth(offset: [0.5, 0.5], angle: angle, folds: d(2.5...4.5),
                                        drape: d(0.15...0.35), octaves: rng.int(in: 2...3)),
                          spread: d(1.9...2.8),
                          ramp: [
                              RampStop(-1, cloth.adjusted(lightness: -0.3, chroma: 0.02)),
                              RampStop(-0.12, cloth.adjusted(lightness: -0.05)),
                              RampStop(0.1, cloth.adjusted(lightness: 0.06)),
                              // A narrow sheen at the crest, not a whole band.
                              RampStop(0.26, highlight.mixed(with: cloth, 0.35).adjusted(lightness: 0.14)),
                              RampStop(0.45, cloth.adjusted(lightness: 0.02)),
                              RampStop(1, cloth.adjusted(lightness: -0.18)),
                          ],
                          opacity: 1,
                          smoothing: 1,
                          hueSweep: chance(0.5) ? d(6...16) : 0)
        var w = Wallpaper(background: background, layers: [sheen],
                          effects: effects(vignette: d(0.1...0.28), warp: d(0.0...0.04), aberration: 0))
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    // MARK: Angular

    mutating func angular() -> Wallpaper {
        // A conic sweep that returns to its first colour, so the seam closes.
        let ring = [drift(p.accent), drift(p.secondary), drift(p.highlight), drift(p.accent, h: 20)]
        var stops = ring.enumerated().map { i, c in
            RampStop(Double(i) / Double(ring.count), c)
        }
        stops.append(RampStop(1, stops[0].color))
        let centre: Vec2 = [0.5 + jit(0.22), 0.5 + jit(0.22)]
        let background = Background(kind: .conic, stops: stops, angle: d(-180...180),
                                    center: centre, smoothing: 1)
        // A soft wash over the middle hides the singularity at the centre.
        let bloom = Layer(name: "Centre bloom",
                          shape: .circle(center: centre, radius: d(0.12...0.3)),
                          spread: d(0.35...0.6),
                          ramp: [RampStop(-1, drift(p.base).with(alpha: d(0.7...0.95))),
                                 RampStop(0, drift(p.base).with(alpha: 0.45)),
                                 RampStop(1, drift(p.base).with(alpha: 0))],
                          smoothing: 1)
        var w = Wallpaper(background: background, layers: [bloom],
                          effects: effects(vignette: d(0.1...0.3), warp: d(0.02...0.09), aberration: chance(0.4) ? d(0.8...2) : 0))
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    // MARK: Beehive / Orbs — lattices

    mutating func beehive() -> Wallpaper {
        let cell = d(0.055...0.12)
        let background = Background.points([drift(p.deep), drift(p.accent), drift(p.secondary), drift(p.base)],
                                           mixing: d(0.8...1.2))
        let comb = Layer(name: "Honeycomb",
                         shape: .hexagons(center: [0.5, 0.5], cell: cell, inset: cell * d(0.04...0.1),
                                          rotation: chance(0.5) ? 0 : 30),
                         spread: cell * d(0.35...0.6),
                         ramp: [RampStop(-1, drift(p.highlight).with(alpha: d(0.16...0.34))),
                                RampStop(-0.2, drift(p.base).with(alpha: 0.06)),
                                RampStop(0, drift(p.deep).with(alpha: d(0.4...0.7))),
                                RampStop(0.8, drift(p.deep).with(alpha: 0))],
                         opacity: d(0.6...0.95),
                         smoothing: 1,
                         lighting: Lighting(angle: d(-160...(-20)), amount: d(0.3...0.6)))
        var w = Wallpaper(background: background, layers: [comb],
                          effects: effects(vignette: d(0.15...0.35), warp: 0, aberration: 0))
        w.effects.grain.intensity = d(0.04...0.08)
        return w
    }

    mutating func orbs() -> Wallpaper {
        let cell = d(0.1...0.2)
        let background = Background.linear([drift(p.deep), drift(p.base).mixed(with: drift(p.accent), 0.25)],
                                           angle: d(0...360), smoothing: 0.5)
        let grid = Layer(name: "Spheres",
                         shape: .discs(center: [0.5, 0.5], cell: [cell, cell * d(0.92...1.08)],
                                       radius: cell * d(0.3...0.42), rotation: chance(0.4) ? d(-20...20) : 0,
                                       stagger: chance(0.7) ? 0.5 : 0, jitter: 0, scaleJitter: chance(0.4) ? d(0.05...0.18) : 0),
                         spread: cell * d(0.3...0.55),
                         ramp: [RampStop(-1, drift(p.highlight)),
                                RampStop(-0.35, drift(p.accent)),
                                RampStop(0, drift(p.secondary).with(alpha: 0.85)),
                                RampStop(0.7, drift(p.accent).with(alpha: 0))],
                         blend: .screen, opacity: d(0.65...0.95), smoothing: 1,
                         lighting: Lighting(angle: d(-150...(-30)), amount: d(0.35...0.7)))
        var w = Wallpaper(background: background, layers: [grid],
                          effects: effects(vignette: d(0.15...0.4), warp: 0, aberration: chance(0.3) ? d(0.5...1.5) : 0))
        w.effects.grain.intensity = d(0.04...0.08)
        return w
    }

    mutating func bokeh() -> Wallpaper {
        let deep = drift(p.deep), base = drift(p.base)
        let accent = drift(p.accent), secondary = drift(p.secondary), highlight = drift(p.highlight)
        let background = Background.linear([deep, base.mixed(with: accent, 0.2)], angle: d(0...360), smoothing: 0.5)
        // Three passes at different sizes: the big ones sit behind, softest.
        func field(_ color: RGBA, cell: Double, radius: Double, opacity: Double, softness: Double) -> Layer {
            Layer(name: "Bokeh",
                  shape: .discs(center: [0.5 + jit(0.1), 0.5 + jit(0.1)],
                                cell: [cell, cell * d(0.85...1.15)], radius: radius,
                                rotation: d(0...360), stagger: 0.5,
                                jitter: d(0.35...0.55), scaleJitter: d(0.3...0.6)),
                  spread: radius * softness,
                  ramp: [RampStop(-1, color.with(alpha: 0.55)), RampStop(-0.25, color.with(alpha: 0.9)),
                         RampStop(0, color.with(alpha: 0.7)), RampStop(0.7, color.with(alpha: 0))],
                  blend: .screen, opacity: opacity, smoothing: 1)
        }
        let layers = [
            field(secondary.mixed(with: base, 0.3), cell: d(0.45...0.7), radius: d(0.09...0.15),
                  opacity: d(0.25...0.45), softness: d(1.2...2.0)),
            field(accent, cell: d(0.3...0.45), radius: d(0.04...0.08), opacity: d(0.4...0.7), softness: d(0.8...1.4)),
            field(highlight, cell: d(0.18...0.3), radius: d(0.015...0.035), opacity: d(0.5...0.9), softness: d(0.5...1.0)),
        ]
        var w = Wallpaper(background: background, layers: layers,
                          effects: effects(vignette: d(0.2...0.4), warp: 0, aberration: chance(0.7) ? d(1...3) : 0))
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    // MARK: Topo

    mutating func topo() -> Wallpaper {
        let deep = drift(p.deep)
        let base = drift(p.base)
        let accent = drift(p.accent)
        let highlight = drift(p.highlight)
        let secondary = drift(p.secondary)
        let background = Background.linear([deep, base], angle: d(0...360), smoothing: 0.5)

        // Contours: a noise field folded every `period`, with a thin bright line at 0.
        let lineWidth = d(0.03...0.07)
        let contours = Layer(name: "Contours",
                             shape: .noise(offset: [d(0...1), d(0...1)], scale: d(0.4...0.8), octaves: rng.int(in: 2...4)),
                             spread: d(0.14...0.24),
                             ramp: [
                                 RampStop(-0.5, accent.with(alpha: 0)),
                                 RampStop(-lineWidth * 3, accent.with(alpha: 0.25)),
                                 RampStop(-lineWidth, highlight.mixed(with: accent, 0.3)),
                                 RampStop(0, highlight),
                                 RampStop(lineWidth, highlight.mixed(with: accent, 0.3)),
                                 RampStop(lineWidth * 3, accent.with(alpha: 0.25)),
                                 RampStop(0.5, accent.with(alpha: 0)),
                             ],
                             blend: .screen,
                             opacity: d(0.6...0.95),
                             smoothing: 0.7,
                             repeatPeriod: 1)
        // A soft fill between lines so the map has terrain, not just lines.
        let terrain = Layer(name: "Terrain",
                            shape: contours.shape,
                            spread: 0.6,
                            ramp: [RampStop(-1, deep), RampStop(0, base.mixed(with: secondary, 0.3)), RampStop(1, secondary.mixed(with: base, 0.4))],
                            opacity: d(0.3...0.6),
                            smoothing: 0.5)
        let glow = Layer(name: "Glow",
                         shape: .circle(center: [d(0.2...0.8), d(0.2...0.8)], radius: d(0.2...0.4)),
                         spread: d(0.5...0.8),
                         ramp: [RampStop(-0.5, accent), RampStop(0.2, accent.mixed(with: base, 0.4)), RampStop(1.2, base.with(alpha: 0))],
                         blend: .screen, opacity: d(0.3...0.6))
        var w = Wallpaper(background: background, layers: [terrain, glow, contours],
                          effects: effects(vignette: d(0.15...0.35), warp: 0, aberration: chance(0.4) ? d(0.5...1.5) : 0))
        w.effects.grain.intensity = d(0.05...0.08)
        return w
    }

    // MARK: Ribbons

    mutating func ribbons() -> Wallpaper {
        let deep = drift(p.deep)
        let base = drift(p.base)
        let accent = drift(p.accent)
        let secondary = drift(p.secondary)
        let highlight = drift(p.highlight)
        let background = Background.linear([deep, base], angle: 90 + jit(30), smoothing: 0.5)
        let angle = 90 + jit(35)
        let period = d(0.16...0.3)
        let through: Vec2 = [0.5, 0.5]
        let ribbons = Layer(name: "Ribbons",
                            shape: .stripes(through: through, angle: angle, period: period, width: period * d(0.3...0.5), bend: d(-0.3...0.3)),
                            spread: period * d(0.15...0.3),
                            ramp: [
                                RampStop(-1.5, highlight.mixed(with: accent, 0.4)),
                                RampStop(-0.6, accent),
                                RampStop(0, accent.adjusted(lightness: -0.15)),
                                RampStop(0.6, secondary.with(alpha: 0.5)),
                                RampStop(1.8, base.with(alpha: 0)),
                            ],
                            opacity: d(0.75...1),
                            smoothing: 1,
                            distortion: Distortion(amount: d(0.08...0.2), scale: d(0.6...1.2), octaves: 3))
        let counter = Layer(name: "Counter ribbons",
                            shape: .stripes(through: [0.5, 0.5], angle: angle + jit(25), period: period * d(1.3...2), width: period * d(0.2...0.35), bend: d(-0.2...0.2)),
                            spread: period * d(0.2...0.4),
                            ramp: [RampStop(-1.2, secondary), RampStop(0, secondary.mixed(with: base, 0.3)), RampStop(1.5, base.with(alpha: 0))],
                            blend: .screen,
                            opacity: d(0.3...0.6),
                            smoothing: 1,
                            distortion: Distortion(amount: d(0.1...0.25), scale: d(0.5...1), octaves: 3))
        var w = Wallpaper(background: background, layers: [counter, ribbons],
                          effects: effects(vignette: d(0.1...0.3), warp: d(0.02...0.06), aberration: chance(0.4) ? d(0.5...1.5) : 0))
        w.effects.grain.intensity = d(0.05...0.08)
        return w
    }

    // MARK: Prism

    mutating func nebula() -> Wallpaper {
        let deep = drift(p.deep)
        let base = drift(p.base)
        let accent = drift(p.accent)
        let secondary = drift(p.secondary)
        let highlight = drift(p.highlight)
        let background = Background.radial([base, deep], center: [d(0.3...0.7), d(0.3...0.7)], radius: d(0.8...1.3), smoothing: 0.5)
        let clouds = Layer(name: "Clouds",
                           shape: .noise(offset: [d(0...1), d(0...1)], scale: d(0.5...1.0), octaves: rng.int(in: 3...4)),
                           spread: d(0.7...1.1),
                           ramp: [
                               RampStop(-1.0, deep.with(alpha: 0)),
                               RampStop(-0.2, secondary.with(alpha: 0.4)),
                               RampStop(0.35, accent.with(alpha: 0.85)),
                               RampStop(0.8, highlight.mixed(with: accent, 0.4)),
                           ],
                           blend: .screen,
                           opacity: d(0.6...0.9),
                           smoothing: 0.8,
                           hueSweep: chance(0.5) ? d(-40...40) : 0)
        let wisps = Layer(name: "Wisps",
                          shape: .noise(offset: [d(0...1), d(0...1)], scale: d(1.2...2.0), octaves: 4),
                          spread: d(0.5...0.8),
                          ramp: [RampStop(-0.6, secondary.with(alpha: 0)), RampStop(0.4, secondary.with(alpha: 0.35)), RampStop(1.0, highlight.with(alpha: 0.5))],
                          blend: .screen,
                          opacity: d(0.2...0.4),
                          smoothing: 0.8)
        let star = Layer(name: "Core",
                         shape: .circle(center: [d(0.25...0.75), d(0.25...0.75)], radius: d(0.02...0.06)),
                         spread: d(0.25...0.45),
                         ramp: [RampStop(-1, highlight), RampStop(0, highlight), RampStop(0.3, accent), RampStop(1.2, base.with(alpha: 0))],
                         blend: .screen,
                         opacity: d(0.5...0.9))
        var w = Wallpaper(background: background, layers: [clouds, wisps, star],
                          effects: effects(vignette: d(0.2...0.4), warp: d(0.02...0.06), aberration: chance(0.5) ? d(0.5...1.5) : 0))
        w.effects.grain.intensity = d(0.06...0.1)
        return w
    }

    // MARK: Holo

    mutating func holo() -> Wallpaper {
        let deep = drift(p.deep)
        let base = drift(p.base)
        let accent = drift(p.accent)
        let highlight = drift(p.highlight)
        let background = Background.linear([deep, base], angle: d(0...360), smoothing: 0.5)
        // A wide soft edge whose hue turns through the spectrum across the ramp.
        let angle = d(0...360)
        let foil = Layer(name: "Foil",
                         shape: .line(through: [0.5 + jit(0.2), 0.5 + jit(0.2)], angle: angle, bend: d(-0.4...0.4)),
                         spread: d(0.5...0.9),
                         ramp: [
                             RampStop(-1.6, accent.with(alpha: 0)),
                             RampStop(-0.9, accent.adjusted(chroma: 0.05)),
                             RampStop(0, accent.adjusted(lightness: 0.1, chroma: 0.05)),
                             RampStop(0.9, accent.adjusted(chroma: 0.05)),
                             RampStop(1.6, accent.with(alpha: 0)),
                         ],
                         blend: p.mood == .dark ? .screen : .normal,
                         opacity: d(0.75...1),
                         smoothing: 0.4,
                         distortion: Distortion(amount: d(0.05...0.15), scale: d(0.5...1.1), octaves: 3),
                         hueSweep: rng.sign() * d(160...300))
        let sheen = Layer(name: "Sheen",
                          shape: .stripes(through: [0.5, 0.5], angle: angle + 90 + jit(30), period: d(0.35...0.7), width: 0.05, bend: d(-0.3...0.3)),
                          spread: d(0.25...0.45),
                          ramp: [RampStop(-1.5, highlight.with(alpha: 0)), RampStop(0, highlight.with(alpha: d(0.3...0.6))), RampStop(1.5, highlight.with(alpha: 0))],
                          blend: .screen,
                          opacity: d(0.5...0.9),
                          smoothing: 1,
                          distortion: Distortion(amount: d(0.05...0.12), scale: 0.8, octaves: 2))
        var w = Wallpaper(background: background, layers: [foil, sheen],
                          effects: effects(vignette: d(0...0.2), warp: d(0.04...0.1), aberration: d(0.5...2)))
        w.effects.grain.intensity = d(0.06...0.09)
        return w
    }

    // MARK: Ladder

    mutating func ladder() -> Wallpaper {
        // Either a single-hue ladder from a gradient preset or a multi-hue retro ladder.
        let count = rng.int(in: 7...10)
        let angle = chance(0.85) ? 90.0 : (chance(0.5) ? 0 : 90 + jit(30))
        let background: Background
        if chance(0.55) {
            let ladders = GradientPreset.defaults.filter { $0.name.hasSuffix("Ladder") }
            var preset = rng.pick(ladders)
            preset.stops = preset.stops.map { RampStop($0.position, $0.color.adjusted(lightness: jit(0.03), hue: jit(8))) }
            background = .ladder(preset.colors, count: count, angle: angle)
        } else {
            // Palette walk: light → accent → dark, or the whole palette in sequence.
            let seq: [RGBA] = chance(0.5)
                ? [drift(p.highlight), drift(p.accent), drift(p.deep)]
                : [drift(p.base), drift(p.secondary), drift(p.highlight), drift(p.accent), drift(p.deep)]
            background = .ladder(seq, count: count, angle: angle)
        }
        var w = Wallpaper(background: background, effects: effects(vignette: 0, warp: 0, aberration: 0))
        w.effects.grain = Grain(intensity: d(0.0...0.03), size: 1, chroma: 0.1, shadowBias: 0)
        return w
    }

    // MARK: Retro

    mutating func retro() -> Wallpaper {
        let retros = GradientPreset.defaults.filter { $0.name.hasPrefix("Retro") }
        var bands: [RGBA]
        if chance(0.6) {
            bands = rng.pick(retros).colors.map { $0.adjusted(lightness: jit(0.02), hue: jit(5)) }
        } else {
            // From the palette: dark field, two mid tones, a cream, two warm tones, a saturated field.
            bands = [drift(p.deep), drift(p.base), drift(p.secondary), drift(p.highlight),
                     drift(p.accent, l: 0.12), drift(p.accent), drift(p.accent, l: -0.1)]
            if chance(0.5) { bands.reverse() }
        }
        let width = d(0.035...0.06)
        let angle = (chance(0.5) ? -30 : -150) + jit(12)
        let inner = bands.count - 1
        // First and last colours are the two big fields; the rest are stripes across the middle.
        let through: Vec2 = [0.5 + jit(0.08), 0.5 + jit(0.08)]
        var stops: [RampStop] = []
        let start = -width * Double(inner - 1) / 2
        for (i, c) in bands.enumerated() {
            stops.append(RampStop(i == 0 ? -10 : start + width * Double(i - 1), c))
        }
        let stripes = Layer(name: "Stripes",
                            shape: .line(through: through, angle: angle, bend: chance(0.3) ? d(-0.15...0.15) : 0),
                            spread: 1,
                            ramp: stops,
                            stepped: true)
        var w = Wallpaper(background: .solid(bands[0]), layers: [stripes],
                          effects: effects(vignette: 0, warp: 0, aberration: 0))
        w.effects.grain = Grain(intensity: d(0.0...0.025), size: 1, chroma: 0.1, shadowBias: 0)
        return w
    }

    // MARK: Chevron

    mutating func classic() -> Wallpaper {
        let dark = chance(0.7)
        let angle = (chance(0.5) ? -40 : 140) + jit(20)
        let stops: [RGBA] = dark
            ? (chance(0.5) ? [drift(p.accent), drift(p.secondary), drift(p.deep)] : [drift(p.accent), drift(p.deep)])
            : [drift(p.highlight), drift(p.secondary), drift(p.accent)]
        var w = Wallpaper(background: .linear(stops, angle: angle, smoothing: d(0.2...0.6)),
                          effects: effects(vignette: d(0...0.15), warp: 0, aberration: 0))
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    // MARK: Glow

    mutating func glow() -> Wallpaper {
        let deep = drift(p.deep, l: 0.005)
        let accent = drift(p.accent)
        let secondary = drift(p.secondary)
        let highlight = drift(p.highlight)
        let background = Background.linear([deep, deep.mixed(with: secondary, 0.25)], angle: 90, smoothing: 0.5)
        let radius = d(0.9...1.4)
        let top = d(0.35...0.55)
        let planet = Layer(name: "Horizon",
                           shape: .circle(center: [0.5 + jit(0.1), top + radius * minSideOverHeight], radius: radius),
                           spread: d(0.25...0.4),
                           ramp: [
                               RampStop(-2.0, deep.mixed(with: accent, 0.3)),
                               RampStop(-0.8, accent.adjusted(lightness: -0.15)),
                               RampStop(-0.15, accent),
                               RampStop(-0.02, highlight.mixed(with: accent, 0.3)),
                               RampStop(0.0, highlight),
                               RampStop(0.08, accent.with(alpha: 0.5)),
                               RampStop(0.5, secondary.with(alpha: 0)),
                           ],
                           smoothing: 1,
                           lighting: Lighting(angle: -90 + jit(20), amount: d(0.3...0.85)))
        var w = Wallpaper(background: background, layers: [planet],
                          effects: effects(vignette: d(0.1...0.3), warp: 0, aberration: chance(0.4) ? d(0.5...1.5) : 0))
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    mutating func beams() -> Wallpaper {
        let deep = drift(p.deep), base = drift(p.base), accent = drift(p.accent), secondary = drift(p.secondary), highlight = drift(p.highlight)
        let background = Background.linear([deep, base], angle: d(0...360), smoothing: 0.5)
        var layers: [Layer] = []
        let count = rng.int(in: 2...4)
        let angle = d(-60...(-20))
        for i in 0..<count {
            let c = [accent, secondary, highlight, accent.adjusted(hue: 30)][i % 4]
            let rad = (angle + jit(12)) * .pi / 180
            let mid: Vec2 = [d(0.1...0.9), d(0.1...0.9)]
            let len = d(0.8...1.6)
            layers.append(Layer(name: "Beam \(i + 1)",
                                shape: .capsule(from: [mid.x - cos(rad) * len, mid.y - sin(rad) * len], to: [mid.x + cos(rad) * len, mid.y + sin(rad) * len], radius: d(0.01...0.06)),
                                spread: d(0.15...0.4),
                                ramp: [RampStop(-1, c.with(alpha: 0.9)), RampStop(0, c.with(alpha: 0.6)), RampStop(1, c.with(alpha: 0))],
                                blend: .screen, opacity: d(0.4...0.8), smoothing: 1))
        }
        var w = Wallpaper(background: background, layers: layers,
                          effects: effects(vignette: d(0.15...0.35), warp: d(0.01...0.03), aberration: chance(0.6) ? d(0.8...2.5) : 0))
        w.effects.grain.intensity = d(0.06...0.1)
        return w
    }

    // MARK: Lava

    mutating func rays() -> Wallpaper {
        let deep = drift(p.deep), base = drift(p.base), accent = drift(p.accent), secondary = drift(p.secondary), highlight = drift(p.highlight)
        let center: Vec2 = [0.5 + jit(0.2), d(0.55...0.95)]
        let background = Background.radial([base.mixed(with: accent, 0.3), deep], center: center, radius: d(0.9...1.4), smoothing: 0.5)
        let burst = Layer(name: "Rays",
                          shape: .rays(center: center, count: rng.int(in: 10...28), rotation: d(0...360), width: d(0.35...0.6)),
                          spread: d(0.02...0.06),
                          ramp: [RampStop(-1, accent.with(alpha: d(0.25...0.5))), RampStop(0, accent.with(alpha: 0.2)), RampStop(1, accent.with(alpha: 0))],
                          blend: .screen, opacity: d(0.6...1), smoothing: 1)
        let fade = Layer(name: "Fade", shape: .circle(center: center, radius: 0.05), spread: d(0.6...1.0),
                         ramp: [RampStop(0, deep.with(alpha: 0)), RampStop(1.3, deep.with(alpha: 0.9))])
        let sun = Layer(name: "Sun", shape: .circle(center: center, radius: d(0.06...0.16)), spread: d(0.15...0.3),
                        ramp: [RampStop(-1, highlight), RampStop(0, highlight.mixed(with: accent, 0.4)), RampStop(0.5, secondary.with(alpha: 0.6)), RampStop(1.3, accent.with(alpha: 0))],
                        blend: .screen)
        var w = Wallpaper(background: background, layers: [burst, fade, sun],
                          effects: effects(vignette: d(0.1...0.3), warp: chance(0.4) ? d(0.005...0.02) : 0, aberration: chance(0.5) ? d(0.5...2) : 0))
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    // MARK: Mountains

    mutating func mountains() -> Wallpaper {
        let deep = drift(p.deep), base = drift(p.base), accent = drift(p.accent), secondary = drift(p.secondary), highlight = drift(p.highlight)
        // Sky: light near the horizon, dark above.
        let background = Background.linear([highlight.mixed(with: accent, 0.35), accent.mixed(with: base, 0.5), base, deep], angle: -90 + jit(10), smoothing: 0.4)
        var layers: [Layer] = []
        let ridges = rng.int(in: 4...6)
        for i in 0..<ridges {
            let t = Double(i) / Double(ridges - 1)          // 0 = far, 1 = near
            let y = d(0.38...0.5) + t * d(0.35...0.45)
            let colour = deep.mixed(with: base.mixed(with: accent, 0.4), (1 - t) * 0.85)   // far ridges lift into the haze
            layers.append(Layer(name: "Ridge \(i + 1)",
                                shape: .line(through: [0.5, y], angle: -90, bend: jit(0.15)),
                                spread: d(0.01...0.03),
                                ramp: [RampStop(-1, colour), RampStop(0, colour), RampStop(1, colour.with(alpha: 0))],
                                smoothing: 1,
                                distortion: Distortion(amount: d(0.06...0.14) * (0.5 + t * 0.7), scale: d(1.2...2.4), octaves: rng.int(in: 3...5))))
        }
        let sun = Layer(name: "Sun", shape: .circle(center: [d(0.25...0.75), d(0.25...0.42)], radius: d(0.04...0.1)), spread: d(0.2...0.4),
                        ramp: [RampStop(-1, highlight), RampStop(0, highlight.mixed(with: accent, 0.3)), RampStop(1.2, accent.with(alpha: 0))],
                        blend: .screen, opacity: d(0.5...0.9))
        var w = Wallpaper(background: background, layers: [sun] + layers,
                          effects: effects(vignette: d(0...0.2), warp: 0, aberration: 0))
        w.effects.grain.intensity = d(0.04...0.08)
        w.effects.grain.chroma = 0.1
        return w
    }

    // MARK: Dunes

    mutating func dunes() -> Wallpaper {
        let deep = drift(p.deep), base = drift(p.base), baseAlt = drift(p.baseAlt), accent = drift(p.accent), highlight = drift(p.highlight)
        let background = Background.linear([highlight, baseAlt], angle: 90, smoothing: 0.5)
        var layers: [Layer] = []
        let count = rng.int(in: 3...5)
        for i in 0..<count {
            let t = Double(i) / Double(max(count - 1, 1))
            let y = d(0.45...0.55) + t * d(0.3...0.4)
            let lit = accent.mixed(with: highlight, 0.35 * (1 - t))
            let shade = accent.mixed(with: deep, 0.25 + t * 0.35)
            layers.append(Layer(name: "Dune \(i + 1)",
                                shape: .wave(through: [0.5, y], angle: -90, amplitude: d(0.04...0.1), wavelength: d(0.8...1.8), phase: d(0...360)),
                                spread: d(0.12...0.25),
                                ramp: [RampStop(-1.5, shade), RampStop(-0.3, lit), RampStop(0, lit.adjusted(lightness: 0.05)), RampStop(0.02, lit.with(alpha: 0))],
                                smoothing: 0.8,
                                distortion: Distortion(amount: d(0.01...0.03), scale: d(1...2), octaves: 2)))
        }
        var w = Wallpaper(background: background, layers: layers, effects: effects(vignette: 0, warp: 0, aberration: 0))
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    // MARK: Sunset

    mutating func sunset() -> Wallpaper {
        let deep = drift(p.deep), base = drift(p.base), accent = drift(p.accent), secondary = drift(p.secondary), highlight = drift(p.highlight)
        let horizon = d(0.6...0.75)
        let background = Background.linear(stops: [RampStop(0, deep), RampStop(0.45, secondary.mixed(with: deep, 0.4)), RampStop(horizon, accent), RampStop(1, deep)],
                                           angle: 90, smoothing: 0.3)
        let sunR = d(0.2...0.32)
        let sunC: Vec2 = [0.5 + jit(0.1), horizon + jit(0.03)]
        let sun = Layer(name: "Sun", shape: .circle(center: sunC, radius: sunR), spread: d(0.01...0.03),
                        ramp: [RampStop(-1, highlight.mixed(with: accent, 0.3)), RampStop(0, accent.adjusted(lightness: 0.1)), RampStop(1, accent.with(alpha: 0))],
                        smoothing: 1)
        // Horizontal slats in the sky colour, clipped to the sun's lower half.
        let slats = Layer(name: "Slats",
                          shape: .stripes(through: [0.5, horizon + sunR * 0.1], angle: 90, period: d(0.04...0.07), width: d(0.012...0.03), bend: 0),
                          spread: 0.004,
                          ramp: [RampStop(-1, deep), RampStop(0, deep), RampStop(1, deep.with(alpha: 0))],
                          opacity: 1, smoothing: 1,
                          clip: .rect(center: [sunC.x, sunC.y + sunR * 0.6], size: [sunR * 2.4, sunR * 1.2], feather: sunR * 0.3))
        let ground = Layer(name: "Ground", shape: .line(through: [0.5, horizon + sunR * 0.75], angle: -90, bend: 0), spread: 0.01,
                           ramp: [RampStop(-1, deep), RampStop(0, deep), RampStop(1, deep.with(alpha: 0))])
        let glow = Layer(name: "Glow", shape: .circle(center: sunC, radius: sunR), spread: d(0.3...0.5),
                         ramp: [RampStop(0, accent.with(alpha: 0.5)), RampStop(1.2, accent.with(alpha: 0))], blend: .screen, opacity: 0.8)
        var w = Wallpaper(background: background, layers: [glow, sun, slats, ground],
                          effects: effects(vignette: d(0.1...0.3), warp: 0, aberration: chance(0.5) ? d(0.8...2) : 0))
        w.effects.grain.intensity = d(0.05...0.09)
        return w
    }

    // MARK: Saturn

}
