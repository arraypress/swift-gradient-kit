//
//  Wallpaper.swift
//  GradientKit
//
//  The scene. A wallpaper is a background plus a stack of shape layers,
//  each a signed-distance field with a colour ramp mapped over distance
//  (negative = inside, positive = outside). That one idea — "colour as a
//  function of distance to an edge" — is what produces the sphere with a
//  bright rim, the eclipse, the dark horizon with a glowing seam: the
//  things a stack of blurred ellipses can't do.
//
//  Coordinates: positions are normalised to the canvas (0,0 top-left,
//  1,1 bottom-right, so a scene re-composes itself for any aspect ratio);
//  lengths (radius, spread, thickness, warp) are in units of the shorter
//  side of the canvas. Angles are degrees, 0° pointing right, 90° down.
//

import Foundation

/// A normalised canvas position or a 2-vector of lengths.
public typealias Vec2 = SIMD2<Double>

public struct Wallpaper: Codable, Sendable, Equatable {
    public var background: Background
    public var layers: [Layer]
    public var effects: Effects
    /// Drives every noise field (warp, distortion, grain). Same scene, same
    /// seed, same pixels.
    public var seed: UInt32
    /// Free-form label — the generator writes the motif and palette here.
    public var title: String
    /// The palette the scene was composed in, so editors can offer matching
    /// colours for new layers. Optional: hand-built scenes may not have one.
    public var palette: Palette?

    public init(background: Background,
                layers: [Layer] = [],
                effects: Effects = Effects(),
                seed: UInt32 = 1,
                title: String = "",
                palette: Palette? = nil) {
        self.background = background
        self.layers = layers
        self.effects = effects
        self.seed = seed
        self.title = title
        self.palette = palette
    }

    /// The renderer's hard ceiling on layers in one scene.
    public static let maxLayers = 12
    /// Per ramp.
    public static let maxStops = 12

    // MARK: JSON

    public func jsonData(pretty: Bool = true) throws -> Data {
        let enc = JSONEncoder()
        if pretty { enc.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try enc.encode(self)
    }

    public init(jsonData: Data) throws {
        self = try JSONDecoder().decode(Wallpaper.self, from: jsonData)
    }
}

// MARK: - Background

public struct Background: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case solid, linear, radial, mesh }

    public var kind: Kind
    /// Positions 0...1 along the gradient (ignored for `.solid`, which uses
    /// the first stop).
    public var stops: [RampStop]
    /// `.linear`: direction the stops run in. 0° = left→right, 90° = top→bottom.
    public var angle: Double
    /// `.radial`: centre (normalised) and radius (min-side units) at which
    /// position 1 is reached.
    public var center: Vec2
    public var radius: Double
    /// 0 = straight linear interpolation between stops, 1 = smoothstep.
    public var smoothing: Double
    /// `.mesh`: the stops are a `meshColumns × meshRows` grid of colours in
    /// row-major order (top-left first), blended across the canvas. Warp the
    /// scene to get the organic "mesh gradient" look.
    public var meshColumns: Int
    public var meshRows: Int
    /// Piecewise-constant: each stop's colour holds until the next stop —
    /// hard bands instead of a blend. Colour ladders, retro stripes.
    public var stepped: Bool

    public init(kind: Kind, stops: [RampStop], angle: Double = 90,
                center: Vec2 = [0.5, 0.5], radius: Double = 0.8, smoothing: Double = 0.5,
                meshColumns: Int = 2, meshRows: Int = 2, stepped: Bool = false) {
        self.kind = kind; self.stops = stops; self.angle = angle
        self.center = center; self.radius = radius; self.smoothing = smoothing
        self.meshColumns = meshColumns; self.meshRows = meshRows; self.stepped = stepped
    }

    /// `count` flat bands running along `angle`, colours blended in OKLab
    /// through `colors` — the classic colour ladder.
    public static func ladder(_ colors: [RGBA], count: Int, angle: Double = 90) -> Background {
        let n = max(2, count)
        var bands: [RampStop] = []
        for i in 0..<n {
            let u = Double(i) / Double(n - 1)
            bands.append(RampStop(Double(i) / Double(n), RGBA.sample(colors, at: u)))
        }
        return Background(kind: .linear, stops: bands, angle: angle, stepped: true)
    }

    // Older scenes have no mesh fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        stops = try c.decode([RampStop].self, forKey: .stops)
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 90
        center = try c.decodeIfPresent(Vec2.self, forKey: .center) ?? [0.5, 0.5]
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0.8
        smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0.5
        meshColumns = try c.decodeIfPresent(Int.self, forKey: .meshColumns) ?? 2
        meshRows = try c.decodeIfPresent(Int.self, forKey: .meshRows) ?? 2
        stepped = try c.decodeIfPresent(Bool.self, forKey: .stepped) ?? false
    }

    /// A grid of colours, row-major, `columns` wide.
    public static func mesh(_ colors: [RGBA], columns: Int, smoothing: Double = 1) -> Background {
        let rows = max(1, (colors.count + columns - 1) / columns)
        return Background(kind: .mesh, stops: colors.map { RampStop(0, $0) }, smoothing: smoothing,
                          meshColumns: max(1, columns), meshRows: rows)
    }

    public static func solid(_ color: RGBA) -> Background {
        Background(kind: .solid, stops: [RampStop(0, color)])
    }

    /// Evenly spaced stops along `angle`.
    public static func linear(_ colors: [RGBA], angle: Double = 90, smoothing: Double = 0.5) -> Background {
        Background(kind: .linear, stops: RampStop.spread(colors, from: 0, to: 1), angle: angle, smoothing: smoothing)
    }

    public static func linear(stops: [RampStop], angle: Double = 90, smoothing: Double = 0.5) -> Background {
        Background(kind: .linear, stops: stops, angle: angle, smoothing: smoothing)
    }

    public static func radial(_ colors: [RGBA], center: Vec2 = [0.5, 0.5], radius: Double = 0.8,
                              smoothing: Double = 0.5) -> Background {
        Background(kind: .radial, stops: RampStop.spread(colors, from: 0, to: 1),
                   center: center, radius: radius, smoothing: smoothing)
    }
}

// MARK: - Ramp

/// A colour at a position along a ramp. For backgrounds the position is
/// 0...1; for layers it is signed distance divided by the layer's `spread`
/// (so −1 is one spread inside the edge, 0 is the edge, 1 is one spread
/// outside). Beyond the first/last stop the ramp holds that stop's colour.
public struct RampStop: Codable, Sendable, Equatable {
    public var position: Double
    public var color: RGBA

    public init(_ position: Double, _ color: RGBA) {
        self.position = position; self.color = color
    }

    public init(position: Double, color: RGBA) {
        self.position = position; self.color = color
    }

    /// Evenly distribute colours between two positions.
    public static func spread(_ colors: [RGBA], from: Double, to: Double) -> [RampStop] {
        guard colors.count > 1 else { return colors.map { RampStop(from, $0) } }
        return colors.enumerated().map { i, c in
            RampStop(from + (to - from) * Double(i) / Double(colors.count - 1), c)
        }
    }
}

// MARK: - Layer

public struct Layer: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var shape: Shape
    /// Distance scale for the ramp, min-side units. Small = crisp edge,
    /// large = the whole layer is one soft wash.
    public var spread: Double
    /// Signed-distance colour ramp. Positions in units of `spread`.
    public var ramp: [RampStop]
    public var blend: BlendMode
    public var opacity: Double
    /// 0 = linear between stops, 1 = smoothstep (softer, blur-like).
    public var smoothing: Double
    /// Bends the edge with fractal noise: `amount` in min-side units,
    /// `scale` in cycles per min-side.
    public var distortion: Distortion
    /// One-sided glow: the ramp's alpha is scaled by how much the edge
    /// faces `angle`. `amount` 0 = uniform, 1 = fully dark on the far side.
    public var lighting: Lighting
    /// Ramp repetition period in units of `spread` (0 = off). The ramp is
    /// evaluated on distance folded into ±period/2, so a bright stop at 0
    /// becomes contour lines around any shape — concentric rings from a
    /// circle, a topographic map from a noise field.
    public var repeatPeriod: Double
    /// Degrees of OKLab hue rotation per unit of ramp position. Turns any
    /// ramp iridescent; 360 over a wide spread reads as holographic foil.
    public var hueSweep: Double
    /// Piecewise-constant ramp: hard bands between stops.
    public var stepped: Bool
    /// Treat the distance field as a height field and light it — bevelled
    /// tiles, extruded ridges, glossy blobs.
    public var relief: Relief
    /// Glyph shapes only: 1 = the emoji's own colours, 0 = a silhouette in
    /// the ramp's colours (for shadows, glows, monochrome patterns).
    public var glyphColor: Double
    public var isEnabled: Bool

    public init(id: UUID = UUID(),
                name: String = "",
                shape: Shape,
                spread: Double = 0.3,
                ramp: [RampStop],
                blend: BlendMode = .normal,
                opacity: Double = 1,
                smoothing: Double = 1,
                distortion: Distortion = Distortion(),
                lighting: Lighting = Lighting(),
                repeatPeriod: Double = 0,
                hueSweep: Double = 0,
                stepped: Bool = false,
                relief: Relief = Relief(),
                glyphColor: Double = 1,
                isEnabled: Bool = true) {
        self.id = id; self.name = name; self.shape = shape; self.spread = spread
        self.ramp = ramp; self.blend = blend; self.opacity = opacity
        self.smoothing = smoothing; self.distortion = distortion
        self.lighting = lighting; self.repeatPeriod = repeatPeriod; self.hueSweep = hueSweep
        self.stepped = stepped; self.relief = relief; self.glyphColor = glyphColor
        self.isEnabled = isEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        shape = try c.decode(Shape.self, forKey: .shape)
        spread = try c.decodeIfPresent(Double.self, forKey: .spread) ?? 0.3
        ramp = try c.decode([RampStop].self, forKey: .ramp)
        blend = try c.decodeIfPresent(BlendMode.self, forKey: .blend) ?? .normal
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? 1
        distortion = try c.decodeIfPresent(Distortion.self, forKey: .distortion) ?? Distortion()
        lighting = try c.decodeIfPresent(Lighting.self, forKey: .lighting) ?? Lighting()
        repeatPeriod = try c.decodeIfPresent(Double.self, forKey: .repeatPeriod) ?? 0
        hueSweep = try c.decodeIfPresent(Double.self, forKey: .hueSweep) ?? 0
        stepped = try c.decodeIfPresent(Bool.self, forKey: .stepped) ?? false
        relief = try c.decodeIfPresent(Relief.self, forKey: .relief) ?? Relief()
        glyphColor = try c.decodeIfPresent(Double.self, forKey: .glyphColor) ?? 1
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    // Identity is the id; two layers with equal content but different ids
    // are still equal for scene comparison purposes.
    public static func == (lhs: Layer, rhs: Layer) -> Bool {
        lhs.name == rhs.name && lhs.shape == rhs.shape && lhs.spread == rhs.spread
            && lhs.ramp == rhs.ramp && lhs.blend == rhs.blend && lhs.opacity == rhs.opacity
            && lhs.smoothing == rhs.smoothing && lhs.distortion == rhs.distortion
            && lhs.lighting == rhs.lighting && lhs.repeatPeriod == rhs.repeatPeriod
            && lhs.hueSweep == rhs.hueSweep && lhs.stepped == rhs.stepped
            && lhs.relief == rhs.relief && lhs.glyphColor == rhs.glyphColor && lhs.isEnabled == rhs.isEnabled
    }
}

/// Surface lighting derived from the distance field. The field becomes a
/// height map (`profile` over one `spread` inside the edge), normals come
/// from its slope, and the layer's colour is shaded with a directional
/// light plus a specular highlight.
public struct Relief: Codable, Sendable, Equatable {
    public enum Profile: String, Codable, Sendable, CaseIterable {
        /// Quarter-circle rise: rounded, glossy — blobs, ridges.
        case dome
        /// Smooth ramp then flat top — bevelled tiles, keycaps.
        case bevel
        /// Straight slope — chiselled facets.
        case slope
    }

    /// Apparent height in min-side units; 0 = off.
    public var height: Double
    public var profile: Profile
    /// Where the light sits, degrees in the plane (0 right, 90 down).
    public var lightAngle: Double
    /// Light elevation, degrees above the surface (90 = straight on).
    public var lightElevation: Double
    /// Specular strength 0...1.
    public var gloss: Double
    /// Specular tightness; 8 = broad plastic, 96 = tight chrome.
    public var shininess: Double
    /// Fill light so the unlit side is not black.
    public var ambient: Double

    public init(height: Double = 0, profile: Profile = .dome, lightAngle: Double = -120, lightElevation: Double = 45,
                gloss: Double = 0.5, shininess: Double = 24, ambient: Double = 0.35) {
        self.height = height; self.profile = profile; self.lightAngle = lightAngle
        self.lightElevation = lightElevation; self.gloss = gloss; self.shininess = shininess; self.ambient = ambient
    }

    public var isActive: Bool { height > 0 }
}

public struct Distortion: Codable, Sendable, Equatable {
    public var amount: Double
    public var scale: Double
    public var octaves: Int

    public init(amount: Double = 0, scale: Double = 2, octaves: Int = 3) {
        self.amount = amount; self.scale = scale; self.octaves = octaves
    }

    public var isActive: Bool { amount != 0 }
}

public struct Lighting: Codable, Sendable, Equatable {
    /// Direction the light comes from, degrees (0 right, 90 down).
    public var angle: Double
    public var amount: Double

    public init(angle: Double = -90, amount: Double = 0) {
        self.angle = angle; self.amount = amount
    }

    public var isActive: Bool { amount != 0 }
}

public enum BlendMode: String, Codable, Sendable, CaseIterable {
    case normal, add, screen, multiply, softLight, overlay
}

// MARK: - Shape

public enum Shape: Codable, Sendable, Equatable {
    /// A disc. Inside is negative distance.
    case circle(center: Vec2, radius: Double)
    /// Axis radii in min-side units, rotation in degrees.
    case ellipse(center: Vec2, radii: Vec2, rotation: Double)
    /// A half-plane. `angle` is the direction of the *outside* normal — the
    /// side the ramp fades out on. `bend` curves the edge (positive bows it
    /// towards the outside), in min-side units of offset per unit² along
    /// the edge.
    case line(through: Vec2, angle: Double, bend: Double)
    /// A half-plane whose edge undulates: `amplitude` (min-side units),
    /// `wavelength` (min-side units), `phase` (degrees).
    case wave(through: Vec2, angle: Double, amplitude: Double, wavelength: Double, phase: Double)
    /// An annulus: inside the band is negative.
    case ring(center: Vec2, radius: Double, thickness: Double)
    /// A disc with a second disc subtracted.
    case crescent(center: Vec2, radius: Double, cutCenter: Vec2, cutRadius: Double)
    /// A regular polygon with `sides` (3...12), circumradius `radius`,
    /// corners rounded by `rounding` (min-side units).
    case polygon(center: Vec2, radius: Double, sides: Int, rotation: Double, rounding: Double)
    /// A rectangle `size` (width, height) with rounded corners. A large
    /// `cornerRadius` on a square gives a squircle-ish tile.
    case rect(center: Vec2, size: Vec2, rotation: Double, cornerRadius: Double)
    /// A stadium: the segment `from`→`to` thickened by `radius`. A beam of
    /// light, a soft bar, a streak.
    case capsule(from: Vec2, to: Vec2, radius: Double)
    /// Parallel bands: stripe centre-lines every `period` along the normal
    /// of `angle`, each `width` wide (inside a stripe is negative), bent by
    /// `bend` like `line`. Add distortion for flowing ribbons.
    case stripes(through: Vec2, angle: Double, period: Double, width: Double, bend: Double)
    /// A disc whose radius wobbles around the circumference: `lobes` bumps,
    /// `wobble` as a fraction of the radius. An organic blob.
    case blob(center: Vec2, radius: Double, lobes: Int, wobble: Double, rotation: Double)
    /// Not an edge at all: the "distance" is a fractal-noise value in about
    /// −0.7…0.7 sampled at `scale` cycles per min-side. The ramp then maps
    /// noise to colour — clouds, nebulae; with `repeatPeriod`, contour maps.
    case noise(offset: Vec2, scale: Double, octaves: Int)
    /// Stripes whose centre-lines zigzag: a triangle wave of `amplitude`
    /// every `wavelength` along the stripe. With relief, extruded chevrons.
    case chevrons(through: Vec2, angle: Double, period: Double, width: Double, amplitude: Double, wavelength: Double)
    /// A grid of rounded tiles: `cell` is the grid pitch (w, h), `inset`
    /// the gap from cell edge to tile edge, rows shifted by `stagger`
    /// (fraction of a cell). With relief, keycaps.
    case tiles(center: Vec2, cell: Vec2, inset: Double, cornerRadius: Double, rotation: Double, stagger: Double)
    /// One emoji (or a short word) as a shape: `size` is its box in
    /// min-side units. The distance field comes from its rasterised
    /// outline, so it takes rims, glows and relief like anything else.
    case glyph(text: String, center: Vec2, size: Double, rotation: Double)
    /// A tiled field of glyphs. `text` may hold several emoji — each cell
    /// picks one by hash. `cell` is the pitch, `size` the glyph box,
    /// `stagger` shifts alternate rows, `jitter` scatters positions (fraction
    /// of a cell), `rotationJitter` (degrees) and `scaleJitter` (fraction)
    /// vary each glyph.
    case glyphPattern(text: String, center: Vec2, cell: Vec2, size: Double, rotation: Double,
                      stagger: Double, jitter: Double, rotationJitter: Double, scaleJitter: Double)

    public var kind: Kind {
        switch self {
        case .circle: .circle
        case .ellipse: .ellipse
        case .line: .line
        case .wave: .wave
        case .ring: .ring
        case .crescent: .crescent
        case .polygon: .polygon
        case .rect: .rect
        case .capsule: .capsule
        case .stripes: .stripes
        case .blob: .blob
        case .noise: .noise
        case .chevrons: .chevrons
        case .tiles: .tiles
        case .glyph: .glyph
        case .glyphPattern: .glyphPattern
        }
    }

    /// The emoji/text a glyph shape draws, if any.
    public var glyphText: String? {
        switch self {
        case let .glyph(t, _, _, _), let .glyphPattern(t, _, _, _, _, _, _, _, _): t
        default: nil
        }
    }

    public var kindName: String { kind.rawValue }

    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case circle, ellipse, line, wave, ring, crescent, polygon, rect, capsule, stripes, blob, noise, chevrons, tiles, glyph, glyphPattern
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .rect: "Rectangle"
            case .glyph: "Emoji"
            case .glyphPattern: "Emoji pattern"
            default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
            }
        }
    }

    /// The anchor position (normalised). Moving it moves the whole shape.
    public var anchor: Vec2 {
        get {
            switch self {
            case let .circle(c, _), let .ellipse(c, _, _), let .ring(c, _, _), let .crescent(c, _, _, _),
                 let .polygon(c, _, _, _, _), let .rect(c, _, _, _), let .blob(c, _, _, _, _): c
            case let .line(p, _, _), let .wave(p, _, _, _, _), let .stripes(p, _, _, _, _), let .chevrons(p, _, _, _, _, _): p
            case let .capsule(a, _, _): a
            case let .noise(o, _, _): o
            case let .tiles(c, _, _, _, _, _), let .glyph(_, c, _, _), let .glyphPattern(_, c, _, _, _, _, _, _, _): c
            }
        }
        set {
            switch self {
            case let .circle(_, r): self = .circle(center: newValue, radius: r)
            case let .ellipse(_, r, rot): self = .ellipse(center: newValue, radii: r, rotation: rot)
            case let .ring(_, r, t): self = .ring(center: newValue, radius: r, thickness: t)
            case let .crescent(c, r, cc, cr):
                self = .crescent(center: newValue, radius: r, cutCenter: cc + (newValue - c), cutRadius: cr)
            case let .line(_, a, b): self = .line(through: newValue, angle: a, bend: b)
            case let .wave(_, a, amp, wl, ph): self = .wave(through: newValue, angle: a, amplitude: amp, wavelength: wl, phase: ph)
            case let .polygon(_, r, n, rot, rd): self = .polygon(center: newValue, radius: r, sides: n, rotation: rot, rounding: rd)
            case let .rect(_, sz, rot, cr): self = .rect(center: newValue, size: sz, rotation: rot, cornerRadius: cr)
            case let .capsule(a, b, r): self = .capsule(from: newValue, to: b + (newValue - a), radius: r)
            case let .stripes(_, a, p, w, b): self = .stripes(through: newValue, angle: a, period: p, width: w, bend: b)
            case let .blob(_, r, l, w, rot): self = .blob(center: newValue, radius: r, lobes: l, wobble: w, rotation: rot)
            case let .noise(_, sc, oct): self = .noise(offset: newValue, scale: sc, octaves: oct)
            case let .chevrons(_, a, p, w, amp, wl): self = .chevrons(through: newValue, angle: a, period: p, width: w, amplitude: amp, wavelength: wl)
            case let .tiles(_, cell, inset, cr, rot, st): self = .tiles(center: newValue, cell: cell, inset: inset, cornerRadius: cr, rotation: rot, stagger: st)
            case let .glyph(t, _, sz, rot): self = .glyph(text: t, center: newValue, size: sz, rotation: rot)
            case let .glyphPattern(t, _, cell, sz, rot, st, j, rj, sj):
                self = .glyphPattern(text: t, center: newValue, cell: cell, size: sz, rotation: rot, stagger: st, jitter: j, rotationJitter: rj, scaleJitter: sj)
            }
        }
    }

    /// The main size parameter, where the shape has one.
    public var size: Double? {
        get {
            switch self {
            case let .circle(_, r), let .ring(_, r, _), let .crescent(_, r, _, _), let .polygon(_, r, _, _, _),
                 let .blob(_, r, _, _, _), let .capsule(_, _, r): r
            case let .ellipse(_, r, _): max(r.x, r.y)
            case let .rect(_, sz, _, _): max(sz.x, sz.y)
            case let .stripes(_, _, p, _, _), let .chevrons(_, _, p, _, _, _): p
            case let .tiles(_, cell, _, _, _, _): max(cell.x, cell.y)
            case let .glyph(_, _, sz, _), let .glyphPattern(_, _, _, sz, _, _, _, _, _): sz
            case .line, .wave, .noise: nil
            }
        }
        set {
            guard let v = newValue else { return }
            switch self {
            case let .circle(c, _): self = .circle(center: c, radius: v)
            case let .ring(c, _, t): self = .ring(center: c, radius: v, thickness: t)
            case let .crescent(c, _, cc, cr): self = .crescent(center: c, radius: v, cutCenter: cc, cutRadius: cr)
            case let .polygon(c, _, n, rot, rd): self = .polygon(center: c, radius: v, sides: n, rotation: rot, rounding: rd)
            case let .blob(c, _, l, w, rot): self = .blob(center: c, radius: v, lobes: l, wobble: w, rotation: rot)
            case let .capsule(a, b, _): self = .capsule(from: a, to: b, radius: v)
            case let .ellipse(c, r, rot):
                let m = max(r.x, r.y)
                self = .ellipse(center: c, radii: r * (m > 0 ? v / m : 1), rotation: rot)
            case let .rect(c, sz, rot, cr):
                let m = max(sz.x, sz.y)
                self = .rect(center: c, size: sz * (m > 0 ? v / m : 1), rotation: rot, cornerRadius: cr)
            case let .stripes(p, a, _, w, b): self = .stripes(through: p, angle: a, period: v, width: w, bend: b)
            case let .chevrons(p, a, per, w, amp, wl):
                let k = per > 0 ? v / per : 1
                self = .chevrons(through: p, angle: a, period: v, width: w * k, amplitude: amp, wavelength: wl)
            case let .tiles(c, cell, inset, cr, rot, st):
                let m = max(cell.x, cell.y)
                let k = m > 0 ? v / m : 1
                self = .tiles(center: c, cell: cell * k, inset: inset * k, cornerRadius: cr * k, rotation: rot, stagger: st)
            case let .glyph(t, c, _, rot): self = .glyph(text: t, center: c, size: v, rotation: rot)
            case let .glyphPattern(t, c, cell, sz, rot, st, j, rj, sj):
                let k = sz > 0 ? v / sz : 1
                self = .glyphPattern(text: t, center: c, cell: cell * k, size: v, rotation: rot, stagger: st, jitter: j, rotationJitter: rj, scaleJitter: sj)
            case .line, .wave, .noise: break
            }
        }
    }

    /// The orientation parameter, where the shape has one (degrees).
    public var angle: Double? {
        get {
            switch self {
            case let .ellipse(_, _, rot), let .polygon(_, _, _, rot, _), let .rect(_, _, rot, _), let .blob(_, _, _, _, rot): rot
            case let .line(_, a, _), let .wave(_, a, _, _, _), let .stripes(_, a, _, _, _), let .chevrons(_, a, _, _, _, _): a
            case let .tiles(_, _, _, _, rot, _), let .glyph(_, _, _, rot), let .glyphPattern(_, _, _, _, rot, _, _, _, _): rot
            case let .capsule(a, b, _): atan2(b.y - a.y, b.x - a.x) * 180 / .pi
            default: nil
            }
        }
        set {
            guard let v = newValue else { return }
            switch self {
            case let .ellipse(c, r, _): self = .ellipse(center: c, radii: r, rotation: v)
            case let .polygon(c, r, n, _, rd): self = .polygon(center: c, radius: r, sides: n, rotation: v, rounding: rd)
            case let .rect(c, sz, _, cr): self = .rect(center: c, size: sz, rotation: v, cornerRadius: cr)
            case let .blob(c, r, l, w, _): self = .blob(center: c, radius: r, lobes: l, wobble: w, rotation: v)
            case let .line(p, _, b): self = .line(through: p, angle: v, bend: b)
            case let .wave(p, _, amp, wl, ph): self = .wave(through: p, angle: v, amplitude: amp, wavelength: wl, phase: ph)
            case let .stripes(p, _, per, w, b): self = .stripes(through: p, angle: v, period: per, width: w, bend: b)
            case let .chevrons(p, _, per, w, amp, wl): self = .chevrons(through: p, angle: v, period: per, width: w, amplitude: amp, wavelength: wl)
            case let .tiles(c, cell, inset, cr, _, st): self = .tiles(center: c, cell: cell, inset: inset, cornerRadius: cr, rotation: v, stagger: st)
            case let .glyph(t, c, sz, _): self = .glyph(text: t, center: c, size: sz, rotation: v)
            case let .glyphPattern(t, c, cell, sz, _, st, j, rj, sj):
                self = .glyphPattern(text: t, center: c, cell: cell, size: sz, rotation: v, stagger: st, jitter: j, rotationJitter: rj, scaleJitter: sj)
            case let .capsule(a, b, r):
                let len = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
                let rad = v * .pi / 180
                self = .capsule(from: a, to: [a.x + cos(rad) * len, a.y + sin(rad) * len], radius: r)
            default: break
            }
        }
    }

    /// The same shape re-expressed as another kind, keeping anchor, size and
    /// angle where they translate. Editors use this for "convert to…".
    public func converted(to kind: Kind) -> Shape {
        let c = anchor
        let r = size ?? 0.3
        let a = angle ?? -90
        switch kind {
        case .circle: return .circle(center: c, radius: r)
        case .ellipse: return .ellipse(center: c, radii: [r, r * 0.65], rotation: angle ?? 0)
        case .line: return .line(through: c, angle: a, bend: 0)
        case .wave: return .wave(through: c, angle: a, amplitude: 0.08, wavelength: 1.5, phase: 0)
        case .ring: return .ring(center: c, radius: r, thickness: 0.04)
        case .crescent: return .crescent(center: c, radius: r, cutCenter: [c.x, c.y + r * 0.4], cutRadius: r * 1.05)
        case .polygon: return .polygon(center: c, radius: r, sides: 6, rotation: angle ?? 0, rounding: 0.02)
        case .rect: return .rect(center: c, size: [r * 1.6, r], rotation: angle ?? 0, cornerRadius: r * 0.2)
        case .capsule:
            let rad = a * .pi / 180
            return .capsule(from: c, to: [c.x + cos(rad) * r * 2, c.y + sin(rad) * r * 2], radius: r * 0.25)
        case .stripes: return .stripes(through: c, angle: a, period: max(r, 0.05), width: max(r, 0.05) * 0.4, bend: 0)
        case .blob: return .blob(center: c, radius: r, lobes: 5, wobble: 0.15, rotation: angle ?? 0)
        case .noise: return .noise(offset: c, scale: 1.5, octaves: 4)
        case .chevrons:
            let p = max(r * 0.6, 0.05)
            return .chevrons(through: c, angle: a, period: p, width: p, amplitude: p * 0.35, wavelength: p * 3)
        case .tiles:
            let cell = max(r * 0.35, 0.03)
            return .tiles(center: c, cell: [cell, cell], inset: cell * 0.08, cornerRadius: cell * 0.18, rotation: angle ?? 0, stagger: 0.5)
        case .glyph:
            return .glyph(text: glyphText ?? "✨", center: c, size: r * 1.6, rotation: angle ?? 0)
        case .glyphPattern:
            let sz = max(min(r * 0.5, 0.3), 0.04)
            return .glyphPattern(text: glyphText ?? "✨", center: c, cell: [sz * 1.7, sz * 1.7], size: sz, rotation: angle ?? -20,
                                 stagger: 0.5, jitter: 0.15, rotationJitter: 20, scaleJitter: 0.15)
        }
    }
}

// MARK: - Effects

public struct Effects: Codable, Sendable, Equatable {
    public var grain: Grain
    public var vignette: Vignette
    public var warp: Warp
    /// Chromatic aberration, in pixels at the frame corner (0 = off). Costs
    /// three scene evaluations per pixel.
    public var aberration: Double
    public var tone: Tone
    /// Liquify strokes, oldest first. Each one pushes the picture along its
    /// vector inside its radius; later strokes smear earlier ones, like
    /// dragging a finger through wet paint.
    public var smears: [Smear]

    public init(grain: Grain = Grain(), vignette: Vignette = Vignette(), warp: Warp = Warp(),
                aberration: Double = 0, tone: Tone = Tone(), smears: [Smear] = []) {
        self.grain = grain; self.vignette = vignette; self.warp = warp
        self.aberration = aberration; self.tone = tone; self.smears = smears
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grain = try c.decodeIfPresent(Grain.self, forKey: .grain) ?? Grain()
        vignette = try c.decodeIfPresent(Vignette.self, forKey: .vignette) ?? Vignette()
        warp = try c.decodeIfPresent(Warp.self, forKey: .warp) ?? Warp()
        aberration = try c.decodeIfPresent(Double.self, forKey: .aberration) ?? 0
        tone = try c.decodeIfPresent(Tone.self, forKey: .tone) ?? Tone()
        smears = try c.decodeIfPresent([Smear].self, forKey: .smears) ?? []
    }

    /// The renderer's ceiling on smears per scene; extra ones are dropped.
    public static let maxSmears = 1024
}

/// One sample of a liquify stroke.
public struct Smear: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case push, swirl, pinch, bloat }

    public var kind: Kind
    /// Normalised canvas position of the brush.
    public var position: Vec2
    /// Displacement at the brush centre, min-side units (`.push`); for
    /// `.swirl` the magnitude is the rotation in turns × 0.1 (sign = direction).
    public var vector: Vec2
    /// Brush radius, min-side units.
    public var radius: Double
    /// 0...1 multiplier on the effect.
    public var strength: Double
    /// Brush feather 0...1: 0 pushes almost uniformly out to the rim, 1 is a
    /// soft bump that only really moves the centre.
    public var softness: Double

    public init(kind: Kind = .push, position: Vec2, vector: Vec2, radius: Double, strength: Double = 1, softness: Double = 0.35) {
        self.kind = kind; self.position = position; self.vector = vector
        self.radius = radius; self.strength = strength; self.softness = softness
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .push
        position = try c.decode(Vec2.self, forKey: .position)
        vector = try c.decode(Vec2.self, forKey: .vector)
        radius = try c.decode(Double.self, forKey: .radius)
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? 1
        softness = try c.decodeIfPresent(Double.self, forKey: .softness) ?? 0.35
    }
}

/// Film grain, applied in gamma space after compositing so it is visible in
/// the shadows too. Always paired with a 1-LSB triangular dither, so 8-bit
/// exports don't band even at `intensity` 0.
public struct Grain: Codable, Sendable, Equatable {
    /// Peak amplitude as a fraction of full scale. 0.04–0.10 reads as film.
    public var intensity: Double
    /// Grain cell size in pixels at a 1440-pixel-high reference (scaled with
    /// the output, floored at one pixel). 1 = fine; 2–3 = visible clumps.
    public var size: Double
    /// 0 = monochrome, 1 = fully independent per channel.
    public var chroma: Double
    /// >0 lifts grain in the shadows, <0 in the highlights. 0 = uniform.
    public var shadowBias: Double

    public init(intensity: Double = 0.06, size: Double = 1.5, chroma: Double = 0.25, shadowBias: Double = 0.3) {
        self.intensity = intensity; self.size = size; self.chroma = chroma; self.shadowBias = shadowBias
    }

    public static let none = Grain(intensity: 0)
}

public struct Vignette: Codable, Sendable, Equatable {
    public var intensity: Double
    /// Where the darkening starts, as a fraction of the half-diagonal.
    public var radius: Double
    public var softness: Double

    public init(intensity: Double = 0, radius: Double = 0.6, softness: Double = 0.6) {
        self.intensity = intensity; self.radius = radius; self.softness = softness
    }
}

/// Domain warp: bends the coordinate space every shape and the background
/// are evaluated in, so straight edges and circles go organic.
public struct Warp: Codable, Sendable, Equatable {
    /// Max displacement in min-side units.
    public var amount: Double
    /// Noise frequency in cycles per min-side.
    public var scale: Double
    public var octaves: Int

    public init(amount: Double = 0, scale: Double = 1.2, octaves: Int = 2) {
        self.amount = amount; self.scale = scale; self.octaves = octaves
    }
}

public struct Tone: Codable, Sendable, Equatable {
    /// Stops.
    public var exposure: Double
    /// 1 = neutral.
    public var contrast: Double
    /// 1 = neutral, 0 = greyscale.
    public var saturation: Double
    /// Degrees, rotated in OKLCH.
    public var hueShift: Double

    public init(exposure: Double = 0, contrast: Double = 1, saturation: Double = 1, hueShift: Double = 0) {
        self.exposure = exposure; self.contrast = contrast; self.saturation = saturation; self.hueShift = hueShift
    }
}
