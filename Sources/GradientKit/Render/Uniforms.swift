//
//  Uniforms.swift
//  GradientKit
//
//  GPU-side layouts. These must match the structs in ShaderSource.swift
//  field for field: float4 members are 16-byte aligned on both sides,
//  SIMD2<Float> is 8-aligned, Int32/UInt32/Float are 4.
//

import Foundation
import simd

struct GPUStop {
    var lab: SIMD4<Float>      // L, a, b, alpha
    var position: Float
    var pad0: Float = 0
    var pad1: Float = 0
    var pad2: Float = 0
}

struct GPUSmear {
    var posVec: SIMD4<Float>     // px, py (scene units), vx, vy (scene units)
    var params: SIMD4<Float>     // radius, strength, kind, 0
}

struct GPULayer {
    var p0: SIMD4<Float> = .zero
    var p1: SIMD4<Float> = .zero
    var p2: SIMD4<Float> = .zero
    var p3: SIMD4<Float> = .zero
    var p4: SIMD4<Float> = .zero
    var p5: SIMD4<Float> = .zero
    var p6: SIMD4<Float> = .zero
    var p7: SIMD4<Float> = .zero
    var kind: Int32 = 0
    var blend: Int32 = 0
    var stopOffset: Int32 = 0
    var stopCount: Int32 = 0
}

struct GPUGlobals {
    var size: SIMD2<Float> = .zero
    var invSize: SIMD2<Float> = .zero
    var minSide: Float = 1
    var aspect: Float = 1
    var seed: UInt32 = 1
    var layerCount: Int32 = 0
    var bgKind: Int32 = 0
    var bgStopOffset: Int32 = 0
    var bgStopCount: Int32 = 0
    var bgAngle: Float = 0
    var bgCenterRadius: SIMD4<Float> = .zero
    var warp: SIMD4<Float> = .zero
    var grain: SIMD4<Float> = .zero
    var vignette: SIMD4<Float> = .zero
    var tone: SIMD4<Float> = .zero
    var misc: SIMD4<Float> = .zero
    var bgMesh: SIMD4<Float> = .zero
    /// Effect order as kind indices (liquify 0, warp 1, aberration 2, tone 3, vignette 4, grain 5), 6 used.
    var orderA: SIMD4<Float> = .zero
    var orderB: SIMD4<Float> = .zero
}

/// The scene flattened into the three buffers the kernel reads.
public struct GPUScene {
    var globals: GPUGlobals
    var layers: [GPULayer]
    var stops: [GPUStop]
    var smears: [GPUSmear]
    /// Distinct glyphs in slice order (empty when the scene uses none).
    var glyphs: [String]

    /// Every glyph the scene draws, in first-use order, capped to the atlas.
    static func glyphList(for w: Wallpaper) -> [String] {
        var seen: [String] = []
        for layer in w.layers where layer.isEnabled {
            guard let text = layer.shape.glyphText else { continue }
            for g in text.glyphs where !seen.contains(g) { seen.append(g) }
        }
        return Array(seen.prefix(GlyphAtlas.maxSlices))
    }

    public init(_ w: Wallpaper, width: Int, height: Int, ditherStep: Float) {
        let glyphs = GPUScene.glyphList(for: w)
        func slices(for text: String) -> (Int32, Int32) {
            let mine = text.glyphs.compactMap { g in glyphs.firstIndex(of: g) }
            guard let first = mine.first else { return (0, 1) }
            // Slices for one text are contiguous only if it was seen first; use its run from `first`.
            var count = 1
            while count < mine.count, mine[count] == first + count { count += 1 }
            return (Int32(first), Int32(count))
        }
        let size = SIMD2<Float>(Float(width), Float(height))
        let minSide = Float(min(width, height))
        var g = GPUGlobals()
        g.size = size
        g.invSize = 1 / size
        g.minSide = minSide
        g.aspect = size.x / size.y
        g.seed = w.seed

        // Normalised (0...1) canvas position → scene units (min-side, centred).
        func scene(_ p: Vec2) -> SIMD2<Float> {
            SIMD2<Float>((Float(p.x) - 0.5) * size.x / minSide, (Float(p.y) - 0.5) * size.y / minSide)
        }
        func rad(_ deg: Double) -> Float { Float(deg * .pi / 180) }

        var stops: [GPUStop] = []
        func push(_ ramp: [RampStop]) -> (Int32, Int32) {
            let offset = stops.count
            let sorted = ramp.sorted { $0.position < $1.position }.prefix(Wallpaper.maxStops)
            for s in sorted {
                let lab = s.color.oklab
                stops.append(GPUStop(lab: SIMD4<Float>(Float(lab.l), Float(lab.a), Float(lab.b), Float(s.color.a)),
                                     position: Float(s.position)))
            }
            return (Int32(offset), Int32(sorted.count))
        }

        // Background
        let bg = w.background
        switch bg.kind {
        case .solid: g.bgKind = 0
        case .linear: g.bgKind = 1
        case .radial: g.bgKind = 2
        case .mesh: g.bgKind = 3
        }
        if bg.kind == .mesh {
            // Mesh colours keep their row-major order (push() sorts by position).
            let cols = max(1, bg.meshColumns), rows = max(1, bg.meshRows)
            let cells = Array(bg.stops.prefix(cols * rows))
            g.bgStopOffset = Int32(stops.count)
            for s in cells {
                let lab = s.color.oklab
                stops.append(GPUStop(lab: SIMD4<Float>(Float(lab.l), Float(lab.a), Float(lab.b), Float(s.color.a)), position: 0))
            }
            g.bgStopCount = Int32(cells.count)
            g.bgMesh = SIMD4<Float>(Float(cols), Float(rows), 0, 0)
        } else {
            (g.bgStopOffset, g.bgStopCount) = push(bg.kind == .solid ? Array(bg.stops.prefix(1)) : bg.stops)
            g.bgMesh = SIMD4<Float>(0, 0, bg.stepped ? 1 : 0, 1.5 / minSide)
        }
        g.bgAngle = rad(bg.angle)
        let bc = scene(bg.center)
        g.bgCenterRadius = SIMD4<Float>(bc.x, bc.y, Float(bg.radius), Float(bg.smoothing))

        // Layers
        var layers: [GPULayer] = []
        for layer in w.layers.prefix(Wallpaper.maxLayers) where layer.isEnabled && layer.opacity > 0 {
            var L = GPULayer()
            switch layer.shape {
            case let .circle(center, radius):
                L.kind = 0
                let c = scene(center)
                L.p0 = SIMD4<Float>(c.x, c.y, Float(radius), Float(radius))
            case let .ellipse(center, radii, rotation):
                L.kind = 1
                let c = scene(center)
                L.p0 = SIMD4<Float>(c.x, c.y, Float(radii.x), Float(radii.y))
                L.p1 = SIMD4<Float>(rad(rotation), 0, 0, 0)
            case let .line(through, angle, bend):
                L.kind = 2
                let c = scene(through)
                L.p0 = SIMD4<Float>(c.x, c.y, 0, 0)
                L.p1 = SIMD4<Float>(rad(angle), Float(bend), 0, 0)
            case let .ring(center, radius, thickness):
                L.kind = 3
                let c = scene(center)
                L.p0 = SIMD4<Float>(c.x, c.y, Float(radius), Float(thickness))
            case let .crescent(center, radius, cutCenter, cutRadius):
                L.kind = 4
                let c = scene(center), cc = scene(cutCenter)
                L.p0 = SIMD4<Float>(c.x, c.y, Float(radius), Float(cutRadius))
                L.p1 = SIMD4<Float>(cc.x, cc.y, 0, 0)
            case let .wave(through, angle, amplitude, wavelength, phase):
                L.kind = 5
                let c = scene(through)
                L.p0 = SIMD4<Float>(c.x, c.y, 0, 0)
                L.p1 = SIMD4<Float>(rad(angle), 0, Float(amplitude), Float(wavelength))
                L.p2.x = rad(phase)
            case let .polygon(center, radius, sides, rotation, rounding):
                L.kind = 6
                let c = scene(center)
                L.p0 = SIMD4<Float>(c.x, c.y, Float(radius), Float(rounding))
                L.p1 = SIMD4<Float>(rad(rotation), Float(max(3, min(sides, 24))), 0, 0)
            case let .rect(center, size, rotation, cornerRadius):
                L.kind = 7
                let c = scene(center)
                L.p0 = SIMD4<Float>(c.x, c.y, Float(size.x), Float(size.y))
                L.p1 = SIMD4<Float>(rad(rotation), Float(cornerRadius), 0, 0)
            case let .capsule(from, to, radius):
                L.kind = 8
                let a = scene(from), b = scene(to)
                L.p0 = SIMD4<Float>(a.x, a.y, b.x, b.y)
                L.p1 = SIMD4<Float>(Float(radius), 0, 0, 0)
            case let .stripes(through, angle, period, width, bend):
                L.kind = 9
                let c = scene(through)
                L.p0 = SIMD4<Float>(c.x, c.y, 0, 0)
                L.p1 = SIMD4<Float>(rad(angle), Float(bend), Float(period), Float(width))
            case let .blob(center, radius, lobes, wobble, rotation):
                L.kind = 10
                let c = scene(center)
                L.p0 = SIMD4<Float>(c.x, c.y, Float(radius), Float(wobble))
                L.p1 = SIMD4<Float>(rad(rotation), Float(max(1, lobes)), 0, 0)
            case let .noise(offset, scale, octaves):
                L.kind = 11
                let c = scene(offset)
                L.p0 = SIMD4<Float>(c.x, c.y, 0, 0)
                L.p1 = SIMD4<Float>(Float(scale), Float(max(1, min(octaves, 8))), 0, 0)
            case let .chevrons(through, angle, period, width, amplitude, wavelength):
                L.kind = 12
                let c = scene(through)
                L.p0 = SIMD4<Float>(c.x, c.y, 0, 0)
                L.p1 = SIMD4<Float>(rad(angle), 0, Float(period), Float(width))
                L.p5 = SIMD4<Float>(Float(amplitude), Float(wavelength), 0, 0)
            case let .tiles(center, cell, inset, cornerRadius, rotation, stagger):
                L.kind = 13
                let c = scene(center)
                L.p0 = SIMD4<Float>(c.x, c.y, Float(cell.x), Float(cell.y))
                L.p1 = SIMD4<Float>(rad(rotation), 0, 0, 0)
                L.p5 = SIMD4<Float>(Float(inset), Float(cornerRadius), Float(stagger), 0)
            case let .glyph(text, center, size, rotation):
                L.kind = 14
                let c = scene(center)
                let (offset, count) = slices(for: text)
                L.p0 = SIMD4<Float>(c.x, c.y, 0, 0)
                L.p1 = SIMD4<Float>(rad(rotation), Float(size), 0, 0)
                L.p5 = SIMD4<Float>(0, 0, Float(offset), Float(count))
            case let .glyphPattern(text, center, cell, size, rotation, stagger, jitter, rotationJitter, scaleJitter):
                L.kind = 15
                let c = scene(center)
                let (offset, count) = slices(for: text)
                L.p0 = SIMD4<Float>(c.x, c.y, Float(cell.x), Float(cell.y))
                L.p1 = SIMD4<Float>(rad(rotation), Float(size), Float(stagger), Float(jitter))
                L.p5 = SIMD4<Float>(rad(rotationJitter), Float(scaleJitter), Float(offset), Float(count))
            }
            L.p2.x = layer.shape.glyphText == nil ? L.p2.x : Float(max(0, min(layer.glyphColor, 1)))
            let r = layer.relief
            let profile: Float = r.profile == .dome ? 0 : (r.profile == .bevel ? 1 : 2)
            L.p6 = SIMD4<Float>(Float(max(0, r.height)), profile, rad(r.lightAngle), rad(max(1, min(r.lightElevation, 89))))
            L.p7 = SIMD4<Float>(Float(r.gloss), Float(r.shininess), Float(r.ambient), layer.stepped ? 1 : 0)
            L.p2.y = Float(layer.distortion.amount)
            L.p2.z = Float(layer.distortion.scale)
            L.p2.w = Float(max(1, min(layer.distortion.octaves, 6)))
            L.p3 = SIMD4<Float>(Float(layer.spread), Float(layer.opacity), rad(layer.lighting.angle), Float(layer.lighting.amount))
            // Per-layer noise offset derived from the layer's place in the stack + scene seed.
            let layerSeed = Float((Int(w.seed) &* 31 &+ layers.count &* 97) % 1000)
            L.p4 = SIMD4<Float>(Float(layer.smoothing), layerSeed, Float(max(0, layer.repeatPeriod)), rad(layer.hueSweep))
            L.blend = Int32(BlendMode.allCases.firstIndex(of: layer.blend) ?? 0)
            (L.stopOffset, L.stopCount) = push(layer.ramp)
            layers.append(L)
        }
        g.layerCount = Int32(layers.count)

        // Effects (bypassed ones neutralised)
        let e = w.effects.resolved
        g.warp = SIMD4<Float>(Float(e.warp.amount), Float(e.warp.scale), Float(max(1, min(e.warp.octaves, 6))), 0)
        // Grain size is specified at a 1440-high reference so the texture
        // looks the same in a preview and a 5K export.
        let grainPx = max(1, Float(e.grain.size) * Float(height) / 1440)
        g.grain = SIMD4<Float>(Float(e.grain.intensity), grainPx, Float(e.grain.chroma), Float(e.grain.shadowBias))
        g.vignette = SIMD4<Float>(Float(e.vignette.intensity), Float(e.vignette.radius), Float(e.vignette.softness), 0)
        g.tone = SIMD4<Float>(Float(e.tone.exposure), Float(e.tone.contrast), Float(e.tone.saturation), rad(e.tone.hueShift))
        // Aberration is specified in pixels at the corner; scale with resolution
        // relative to a 1080-high reference so previews match exports.
        let aber = Float(e.aberration) * (Float(height) / 1080)

        // Smears: stored oldest-first; the kernel walks them newest-first so
        // each stroke deforms everything painted before it.
        var smears: [GPUSmear] = []
        for sm in e.smears.suffix(Effects.maxSmears).reversed() where sm.radius > 0 && sm.strength != 0 {
            let p = scene(sm.position)
            let kind: Float
            switch sm.kind {
            case .push: kind = 0
            case .swirl: kind = 1
            case .pinch: kind = 2
            case .bloat: kind = 3
            }
            smears.append(GPUSmear(posVec: SIMD4<Float>(p.x, p.y, Float(sm.vector.x), Float(sm.vector.y)),
                                   params: SIMD4<Float>(Float(sm.radius), Float(sm.strength), kind, Float(1 + 3 * max(0, min(sm.softness, 1))))))
        }
        g.misc = SIMD4<Float>(aber, ditherStep, Float(smears.count), 0)
        if smears.isEmpty { smears.append(GPUSmear(posVec: .zero, params: .zero)) }
        let order = Effects.normalized(e.order).map { kind -> Float in
            switch kind {
            case .liquify: 0
            case .warp: 1
            case .aberration: 2
            case .tone: 3
            case .vignette: 4
            case .grain: 5
            }
        }
        g.orderA = SIMD4<Float>(order[0], order[1], order[2], order[3])
        g.orderB = SIMD4<Float>(order[4], order[5], 0, 0)

        if stops.isEmpty {
            stops.append(GPUStop(lab: SIMD4<Float>(0, 0, 0, 1), position: 0))
        }
        if layers.isEmpty {
            layers.append(GPULayer())   // keep the buffer non-empty; layerCount is 0
        }

        self.globals = g
        self.layers = layers
        self.stops = stops
        self.smears = smears
        self.glyphs = glyphs
    }
}
