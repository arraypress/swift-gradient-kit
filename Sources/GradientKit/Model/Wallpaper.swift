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
    /// Where a generated scene came from, so an editor can re-roll or
    /// recolour it. Nil for hand-built scenes.
    public var origin: Origin?

    public init(background: Background,
                layers: [Layer] = [],
                effects: Effects = Effects(),
                seed: UInt32 = 1,
                title: String = "",
                palette: Palette? = nil,
                origin: Origin? = nil) {
        self.background = background
        self.layers = layers
        self.effects = effects
        self.seed = seed
        self.title = title
        self.palette = palette
        self.origin = origin
    }

    public struct Origin: Codable, Sendable, Equatable {
        public var motif: String
        public var seed: UInt64
        /// The palette the user chose explicitly; nil when the seed chose.
        public var paletteName: String?

        public init(motif: String, seed: UInt64, paletteName: String? = nil) {
            self.motif = motif; self.seed = seed; self.paletteName = paletteName
        }
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
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case solid, linear, radial, mesh
        /// Free-floating colour points blended by inverse distance — the
        /// "mesh gradient" everyone actually means. See `points`.
        case points
        /// Stops swept around `center`, starting at `angle`.
        case conic

        public var displayName: String {
            switch self {
            case .solid: "Solid"
            case .linear: "Linear"
            case .radial: "Radial"
            case .mesh: "Grid"
            case .points: "Points"
            case .conic: "Conic"
            }
        }
    }

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
    /// `.points`: the colour points. Each is blended into every pixel with a
    /// weight of `weight / distance^(2·mixing)`, so the field is smooth
    /// everywhere and exactly the point's colour at the point — colour
    /// metaballs. This is what a soft "mesh gradient" is made of; the grid
    /// in `.mesh` cannot produce it.
    public var points: [MeshPoint]
    /// `.points`: blend exponent. 0.5 = broad, mushy washes; 1 = the default
    /// balance; 2 = tight pools of colour with sharp valleys between them.
    public var mixing: Double
    /// `.points`: rotates the sampled position by `swirl` radians per unit of
    /// distance from the centre, so the field winds around itself.
    public var swirl: Double

    public init(kind: Kind, stops: [RampStop], angle: Double = 90,
                center: Vec2 = [0.5, 0.5], radius: Double = 0.8, smoothing: Double = 0.5,
                meshColumns: Int = 2, meshRows: Int = 2, stepped: Bool = false,
                points: [MeshPoint] = [], mixing: Double = 1, swirl: Double = 0) {
        self.kind = kind; self.stops = stops; self.angle = angle
        self.center = center; self.radius = radius; self.smoothing = smoothing
        self.meshColumns = meshColumns; self.meshRows = meshRows; self.stepped = stepped
        self.points = points; self.mixing = mixing; self.swirl = swirl
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
        points = try c.decodeIfPresent([MeshPoint].self, forKey: .points) ?? []
        mixing = try c.decodeIfPresent(Double.self, forKey: .mixing) ?? 1
        swirl = try c.decodeIfPresent(Double.self, forKey: .swirl) ?? 0
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

    /// Stops swept around a centre. `angle` is where position 0 sits.
    public static func conic(_ colors: [RGBA], center: Vec2 = [0.5, 0.5], angle: Double = -90,
                             smoothing: Double = 0.5) -> Background {
        Background(kind: .conic, stops: RampStop.spread(colors, from: 0, to: 1),
                   angle: angle, center: center, smoothing: smoothing)
    }

    /// The same background as another kind, carrying the colours across.
    ///
    /// `.points` keeps its colours in `points` and everything else keeps
    /// them in `stops`, so a bare `kind = .points` leaves the new field
    /// empty and the picture loses every colour it had. Changing kind
    /// should never do that, so go through here.
    public func converted(to kind: Kind) -> Background {
        guard kind != self.kind else { return self }
        var out = self
        out.kind = kind

        // Whatever this background's colours are, in order.
        let colours: [RGBA] = self.kind == .points
            ? points.map(\.color)
            : stops.sorted { $0.position < $1.position }.map(\.color)
        guard !colours.isEmpty else { return out }

        // The rule throughout: never DESTROY colour information a kind
        // happens not to read. `.solid` renders only the first stop and
        // `.mesh` reads the stops in array order ignoring their positions —
        // so both can leave `stops` exactly as they found it, and switching
        // away and back returns the gradient you had.
        switch kind {
        case .points:
            if out.points.isEmpty {
                out.points = Background.points(colours).points
            }
        case .solid:
            // Keep every stop; the renderer takes the first one.
            if out.stops.isEmpty { out.stops = [RampStop(0, colours[0])] }
        case .mesh:
            if out.stops.isEmpty { out.stops = colours.map { RampStop(0, $0) } }
            let n = colours.count
            out.meshColumns = max(1, Int(Double(n).squareRoot().rounded()))
            out.meshRows = max(1, (n + out.meshColumns - 1) / out.meshColumns)
        case .linear, .radial, .conic:
            // Coming BACK from a point field, the ramp this background had
            // is still sitting in `stops` untouched — restore it rather
            // than evenly respacing, so linear → points → linear returns
            // you to where you started instead of quietly flattening the
            // stop positions you had set.
            let kept = stops.sorted { $0.position < $1.position }
            // Coming back from a kind that did not use positions, the ramp
            // is still sitting in `stops` untouched — restore it rather than
            // evenly respacing, so a round trip returns you to where you
            // started instead of quietly flattening the stops you set.
            out.stops = kept.count == colours.count
                ? kept
                : RampStop.spread(colours, from: 0, to: 1)
        }
        return out
    }

    /// Colour points blended by inverse distance.
    public static func points(_ points: [MeshPoint], mixing: Double = 1, swirl: Double = 0) -> Background {
        Background(kind: .points, stops: [], points: points, mixing: mixing, swirl: swirl)
    }

    /// `colors` scattered on a golden-angle spiral inside the canvas — an
    /// even, unrepetitive arrangement that needs no hand placement.
    public static func points(_ colors: [RGBA], mixing: Double = 1, swirl: Double = 0,
                              spread: Double = 0.34) -> Background {
        let golden = 2.39996322972865332
        let pts = colors.enumerated().map { i, c -> MeshPoint in
            let t = colors.count > 1 ? Double(i) / Double(colors.count - 1) : 0
            let r = spread * (0.35 + 0.65 * t.squareRoot())
            let a = Double(i) * golden
            return MeshPoint(position: [0.5 + r * Foundation.cos(a), 0.5 + r * Foundation.sin(a)], color: c)
        }
        return .points(pts, mixing: mixing, swirl: swirl)
    }
}

/// One colour point of a `.points` background. Position is canvas-normalised.
public struct MeshPoint: Codable, Sendable, Equatable {
    public var position: Vec2
    public var color: RGBA
    /// Relative pull. 1 is neutral; a heavier point spreads further.
    public var weight: Double

    public init(position: Vec2, color: RGBA, weight: Double = 1) {
        self.position = position; self.color = color; self.weight = weight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decode(Vec2.self, forKey: .position)
        color = try c.decode(RGBA.self, forKey: .color)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1
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
    /// Confine the layer to a simple region — stripes inside a sun, a
    /// texture inside a tile, a ring only where it passes in front.
    public var clip: Clip?
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
                clip: Clip? = nil,
                isEnabled: Bool = true) {
        self.id = id; self.name = name; self.shape = shape; self.spread = spread
        self.ramp = ramp; self.blend = blend; self.opacity = opacity
        self.smoothing = smoothing; self.distortion = distortion
        self.lighting = lighting; self.repeatPeriod = repeatPeriod; self.hueSweep = hueSweep
        self.stepped = stepped; self.clip = clip
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
        clip = try c.decodeIfPresent(Clip.self, forKey: .clip)
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
            && lhs.clip == rhs.clip && lhs.isEnabled == rhs.isEnabled
    }
}

/// A soft mask the layer is multiplied by. Positions normalised, sizes in
/// min-side units (`size` is the full width/height of the region).
public struct Clip: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case circle, rect }

    public var kind: Kind
    public var center: Vec2
    public var size: Vec2
    public var rotation: Double
    /// Edge softness in min-side units.
    public var feather: Double
    /// Keep the outside instead of the inside.
    public var inverted: Bool

    public init(kind: Kind = .circle, center: Vec2 = [0.5, 0.5], size: Vec2 = [0.5, 0.5], rotation: Double = 0,
                feather: Double = 0.005, inverted: Bool = false) {
        self.kind = kind; self.center = center; self.size = size; self.rotation = rotation
        self.feather = feather; self.inverted = inverted
    }

    public static func circle(center: Vec2, radius: Double, feather: Double = 0.005, inverted: Bool = false) -> Clip {
        Clip(kind: .circle, center: center, size: [radius * 2, radius * 2], feather: feather, inverted: inverted)
    }

    public static func rect(center: Vec2, size: Vec2, rotation: Double = 0, feather: Double = 0.005, inverted: Bool = false) -> Clip {
        Clip(kind: .rect, center: center, size: size, rotation: rotation, feather: feather, inverted: inverted)
    }
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
    /// every `wavelength` along the stripe.
    case chevrons(through: Vec2, angle: Double, period: Double, width: Double, amplitude: Double, wavelength: Double)
    /// A grid of rounded tiles: `cell` is the grid pitch (w, h), `inset`
    /// the gap from cell edge to tile edge, rows shifted by `stagger`
    /// (fraction of a cell).
    case tiles(center: Vec2, cell: Vec2, inset: Double, cornerRadius: Double, rotation: Double, stagger: Double)
    /// `count` wedges radiating from `center`, each covering `width` (0…1) of
    /// its slice; inside a wedge is negative. A sunburst.
    case rays(center: Vec2, count: Int, rotation: Double, width: Double)
    /// A honeycomb: flat-topped hexagons on a lattice of pitch `cell`
    /// (min-side units, centre to centre), each shrunk by `inset`. Inside a
    /// cell is negative, so a ramp over distance gives the bevelled edge.
    case hexagons(center: Vec2, cell: Double, inset: Double, rotation: Double)
    /// A lattice of discs — the sphere grid, the pixel-orb field, and
    /// out-of-focus bokeh, depending on `radius` against `cell` and how soft
    /// the ramp is. `stagger` shifts alternate rows (0.5 = brick), `jitter`
    /// scatters each disc within its cell and `scaleJitter` varies its size.
    case discs(center: Vec2, cell: Vec2, radius: Double, rotation: Double,
               stagger: Double, jitter: Double, scaleJitter: Double)
    /// Not an edge: a directional FOLD field in about −0.7…0.7, like
    /// `.noise` but combed along `angle` so the contours run as parallel
    /// creases rather than blobs. `folds` is creases per min-side, `drape`
    /// how far fractal noise bends them off-straight. Mapped through a ramp
    /// it reads as satin or silk; add `hueSweep` for shot silk.
    case cloth(offset: Vec2, angle: Double, folds: Double, drape: Double, octaves: Int)

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
        case .rays: .rays
        case .hexagons: .hexagons
        case .discs: .discs
        case .cloth: .cloth
        }
    }

    public var kindName: String { kind.rawValue }

    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case circle, ellipse, line, wave, ring, crescent, polygon, rect, capsule, stripes, blob, noise, chevrons, tiles, rays, hexagons, discs, cloth
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .rect: "Rectangle"
            case .hexagons: "Honeycomb"
            case .discs: "Disc grid"
            case .cloth: "Fold field"
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
            case let .tiles(c, _, _, _, _, _), let .rays(c, _, _, _): c
            case let .hexagons(c, _, _, _), let .discs(c, _, _, _, _, _, _): c
            case let .cloth(o, _, _, _, _): o
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
            case let .rays(_, n, rot, w): self = .rays(center: newValue, count: n, rotation: rot, width: w)
            case let .hexagons(_, cell, inset, rot): self = .hexagons(center: newValue, cell: cell, inset: inset, rotation: rot)
            case let .discs(_, cell, r, rot, st, j, sj): self = .discs(center: newValue, cell: cell, radius: r, rotation: rot, stagger: st, jitter: j, scaleJitter: sj)
            case let .cloth(_, a, f, dr, oct): self = .cloth(offset: newValue, angle: a, folds: f, drape: dr, octaves: oct)
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
            case let .hexagons(_, cell, _, _): cell
            case let .discs(_, cell, _, _, _, _, _): max(cell.x, cell.y)
            case .line, .wave, .noise, .rays, .cloth: nil
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
            case let .hexagons(c, cell, inset, rot):
                let k = cell > 0 ? v / cell : 1
                self = .hexagons(center: c, cell: v, inset: inset * k, rotation: rot)
            case let .discs(c, cell, r, rot, st, j, sj):
                let m = max(cell.x, cell.y)
                let k = m > 0 ? v / m : 1
                self = .discs(center: c, cell: cell * k, radius: r * k, rotation: rot, stagger: st, jitter: j, scaleJitter: sj)
            case .line, .wave, .noise, .rays, .cloth: break
            }
        }
    }

    /// The orientation parameter, where the shape has one (degrees).
    public var angle: Double? {
        get {
            switch self {
            case let .ellipse(_, _, rot), let .polygon(_, _, _, rot, _), let .rect(_, _, rot, _), let .blob(_, _, _, _, rot): rot
            case let .line(_, a, _), let .wave(_, a, _, _, _), let .stripes(_, a, _, _, _), let .chevrons(_, a, _, _, _, _): a
            case let .tiles(_, _, _, _, rot, _), let .rays(_, _, rot, _): rot
            case let .hexagons(_, _, _, rot), let .discs(_, _, _, rot, _, _, _): rot
            case let .cloth(_, a, _, _, _): a
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
            case let .rays(c, n, _, w): self = .rays(center: c, count: n, rotation: v, width: w)
            case let .hexagons(c, cell, inset, _): self = .hexagons(center: c, cell: cell, inset: inset, rotation: v)
            case let .discs(c, cell, r, _, st, j, sj): self = .discs(center: c, cell: cell, radius: r, rotation: v, stagger: st, jitter: j, scaleJitter: sj)
            case let .cloth(o, _, f, dr, oct): self = .cloth(offset: o, angle: v, folds: f, drape: dr, octaves: oct)
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
        case .rays:
            return .rays(center: c, count: 16, rotation: angle ?? 0, width: 0.5)
        case .hexagons:
            let cell = max(r * 0.4, 0.04)
            return .hexagons(center: c, cell: cell, inset: cell * 0.06, rotation: angle ?? 0)
        case .discs:
            let cell = max(r * 0.45, 0.05)
            return .discs(center: c, cell: [cell, cell], radius: cell * 0.38, rotation: angle ?? 0,
                          stagger: 0.5, jitter: 0, scaleJitter: 0)
        case .cloth:
            return .cloth(offset: c, angle: a, folds: 6, drape: 0.35, octaves: 3)
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
    /// Effects switched off without losing their settings — an editor's
    /// "adjustment layer" toggles.
    public var bypassed: Set<Kind>
    /// The order effects apply in, first to last. Coordinate effects
    /// (liquify, warp) compose in this order before the scene is sampled;
    /// colour effects (aberration, tone, vignette, grain) run in this order
    /// afterwards. Missing kinds are appended in the default order.
    public var order: [Kind]

    public static let defaultOrder: [Kind] = [.liquify, .warp, .aberration, .tone, .vignette, .grain]

    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case grain, vignette, warp, aberration, tone, liquify
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .grain: "Grain"
            case .vignette: "Vignette"
            case .warp: "Warp"
            case .aberration: "Aberration"
            case .tone: "Tone"
            case .liquify: "Liquify"
            }
        }
    }

    public init(grain: Grain = Grain(), vignette: Vignette = Vignette(), warp: Warp = Warp(),
                aberration: Double = 0, tone: Tone = Tone(), smears: [Smear] = [], bypassed: Set<Kind> = [],
                order: [Kind] = Effects.defaultOrder) {
        self.grain = grain; self.vignette = vignette; self.warp = warp
        self.aberration = aberration; self.tone = tone; self.smears = smears; self.bypassed = bypassed
        self.order = Effects.normalized(order)
    }

    /// Every kind exactly once: the given ones first, then the defaults.
    public static func normalized(_ order: [Kind]) -> [Kind] {
        var seen: [Kind] = []
        for k in order + defaultOrder where !seen.contains(k) { seen.append(k) }
        return seen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grain = try c.decodeIfPresent(Grain.self, forKey: .grain) ?? Grain()
        vignette = try c.decodeIfPresent(Vignette.self, forKey: .vignette) ?? Vignette()
        warp = try c.decodeIfPresent(Warp.self, forKey: .warp) ?? Warp()
        aberration = try c.decodeIfPresent(Double.self, forKey: .aberration) ?? 0
        tone = try c.decodeIfPresent(Tone.self, forKey: .tone) ?? Tone()
        smears = try c.decodeIfPresent([Smear].self, forKey: .smears) ?? []
        bypassed = try c.decodeIfPresent(Set<Kind>.self, forKey: .bypassed) ?? []
        order = Effects.normalized(try c.decodeIfPresent([Kind].self, forKey: .order) ?? Effects.defaultOrder)
    }

    /// Move one effect in the stack.
    public mutating func move(_ kind: Kind, to index: Int) {
        var o = Effects.normalized(order)
        guard let i = o.firstIndex(of: kind) else { return }
        o.remove(at: i)
        o.insert(kind, at: max(0, min(index, o.count)))
        order = o
    }

    public func isActive(_ kind: Kind) -> Bool { !bypassed.contains(kind) }

    /// Whether the effect does anything at its current settings.
    public func hasEffect(_ kind: Kind) -> Bool {
        switch kind {
        case .grain: grain.intensity > 0
        case .vignette: vignette.intensity > 0
        case .warp: warp.amount > 0
        case .aberration: aberration > 0
        case .tone: tone != Tone()
        case .liquify: !smears.isEmpty
        }
    }

    /// The effects with bypassed ones neutralised — what the renderer sees.
    public var resolved: Effects {
        var e = self
        if bypassed.contains(.grain) { e.grain.intensity = 0 }
        if bypassed.contains(.vignette) { e.vignette.intensity = 0 }
        if bypassed.contains(.warp) { e.warp.amount = 0 }
        if bypassed.contains(.aberration) { e.aberration = 0 }
        if bypassed.contains(.tone) { e.tone = Tone() }
        if bypassed.contains(.liquify) { e.smears = [] }
        e.bypassed = []
        return e
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
