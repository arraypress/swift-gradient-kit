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

struct GPULayer {
    var p0: SIMD4<Float> = .zero
    var p1: SIMD4<Float> = .zero
    var p2: SIMD4<Float> = .zero
    var p3: SIMD4<Float> = .zero
    var p4: SIMD4<Float> = .zero
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
}

/// The scene flattened into the three buffers the kernel reads.
struct GPUScene {
    var globals: GPUGlobals
    var layers: [GPULayer]
    var stops: [GPUStop]

    init(_ w: Wallpaper, width: Int, height: Int, ditherStep: Float) {
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
        }
        (g.bgStopOffset, g.bgStopCount) = push(bg.kind == .solid ? Array(bg.stops.prefix(1)) : bg.stops)
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
            }
            L.p2.y = Float(layer.distortion.amount)
            L.p2.z = Float(layer.distortion.scale)
            L.p2.w = Float(max(1, min(layer.distortion.octaves, 6)))
            L.p3 = SIMD4<Float>(Float(layer.spread), Float(layer.opacity), rad(layer.lighting.angle), Float(layer.lighting.amount))
            // Per-layer noise offset derived from the layer's place in the stack + scene seed.
            let layerSeed = Float((Int(w.seed) &* 31 &+ layers.count &* 97) % 1000)
            L.p4 = SIMD4<Float>(Float(layer.smoothing), layerSeed, 0, 0)
            L.blend = Int32(BlendMode.allCases.firstIndex(of: layer.blend) ?? 0)
            (L.stopOffset, L.stopCount) = push(layer.ramp)
            layers.append(L)
        }
        g.layerCount = Int32(layers.count)

        // Effects
        let e = w.effects
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
        g.misc = SIMD4<Float>(aber, ditherStep, 0, 0)

        if stops.isEmpty {
            stops.append(GPUStop(lab: SIMD4<Float>(0, 0, 0, 1), position: 0))
        }
        if layers.isEmpty {
            layers.append(GPULayer())   // keep the buffer non-empty; layerCount is 0
        }

        self.globals = g
        self.layers = layers
        self.stops = stops
    }
}
