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

    public init(background: Background,
                layers: [Layer] = [],
                effects: Effects = Effects(),
                seed: UInt32 = 1,
                title: String = "") {
        self.background = background
        self.layers = layers
        self.effects = effects
        self.seed = seed
        self.title = title
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
    public enum Kind: String, Codable, Sendable { case solid, linear, radial }

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

    public init(kind: Kind, stops: [RampStop], angle: Double = 90,
                center: Vec2 = [0.5, 0.5], radius: Double = 0.8, smoothing: Double = 0.5) {
        self.kind = kind; self.stops = stops; self.angle = angle
        self.center = center; self.radius = radius; self.smoothing = smoothing
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
                isEnabled: Bool = true) {
        self.id = id; self.name = name; self.shape = shape; self.spread = spread
        self.ramp = ramp; self.blend = blend; self.opacity = opacity
        self.smoothing = smoothing; self.distortion = distortion
        self.lighting = lighting; self.isEnabled = isEnabled
    }

    // Identity is the id; two layers with equal content but different ids
    // are still equal for scene comparison purposes.
    public static func == (lhs: Layer, rhs: Layer) -> Bool {
        lhs.name == rhs.name && lhs.shape == rhs.shape && lhs.spread == rhs.spread
            && lhs.ramp == rhs.ramp && lhs.blend == rhs.blend && lhs.opacity == rhs.opacity
            && lhs.smoothing == rhs.smoothing && lhs.distortion == rhs.distortion
            && lhs.lighting == rhs.lighting && lhs.isEnabled == rhs.isEnabled
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

    public var kindName: String {
        switch self {
        case .circle: "circle"
        case .ellipse: "ellipse"
        case .line: "line"
        case .wave: "wave"
        case .ring: "ring"
        case .crescent: "crescent"
        }
    }

    /// The anchor position (normalised). Moving it moves the whole shape.
    public var anchor: Vec2 {
        get {
            switch self {
            case let .circle(c, _), let .ellipse(c, _, _), let .ring(c, _, _), let .crescent(c, _, _, _): c
            case let .line(p, _, _), let .wave(p, _, _, _, _): p
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
            }
        }
    }

    /// The main size parameter, where the shape has one.
    public var size: Double? {
        get {
            switch self {
            case let .circle(_, r), let .ring(_, r, _), let .crescent(_, r, _, _): r
            case let .ellipse(_, r, _): max(r.x, r.y)
            case .line, .wave: nil
            }
        }
        set {
            guard let v = newValue else { return }
            switch self {
            case let .circle(c, _): self = .circle(center: c, radius: v)
            case let .ring(c, _, t): self = .ring(center: c, radius: v, thickness: t)
            case let .crescent(c, _, cc, cr): self = .crescent(center: c, radius: v, cutCenter: cc, cutRadius: cr)
            case let .ellipse(c, r, rot):
                let m = max(r.x, r.y)
                let k = m > 0 ? v / m : 1
                self = .ellipse(center: c, radii: r * k, rotation: rot)
            case .line, .wave: break
            }
        }
    }

    /// The orientation parameter, where the shape has one (degrees).
    public var angle: Double? {
        get {
            switch self {
            case let .ellipse(_, _, rot): rot
            case let .line(_, a, _), let .wave(_, a, _, _, _): a
            default: nil
            }
        }
        set {
            guard let v = newValue else { return }
            switch self {
            case let .ellipse(c, r, _): self = .ellipse(center: c, radii: r, rotation: v)
            case let .line(p, _, b): self = .line(through: p, angle: v, bend: b)
            case let .wave(p, _, amp, wl, ph): self = .wave(through: p, angle: v, amplitude: amp, wavelength: wl, phase: ph)
            default: break
            }
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

    public init(grain: Grain = Grain(), vignette: Vignette = Vignette(), warp: Warp = Warp(),
                aberration: Double = 0, tone: Tone = Tone()) {
        self.grain = grain; self.vignette = vignette; self.warp = warp
        self.aberration = aberration; self.tone = tone
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
