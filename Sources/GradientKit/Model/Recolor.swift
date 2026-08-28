//
//  Recolor.swift
//  GradientKit
//
//  Re-dress a scene in another palette without regenerating it, so edits,
//  added layers and liquify strokes survive. Every colour is mapped from
//  the nearest role of the scene's palette to the same role of the target,
//  keeping its OKLab offset from that role — a drifted accent stays a
//  drifted accent, a shadow stays a shadow.
//

import Foundation

public extension Wallpaper {
    /// The scene in `target`'s colours. `source` defaults to the scene's
    /// own palette; without either, the scene is returned unchanged.
    func recolored(to target: Palette, from source: Palette? = nil) -> Wallpaper {
        guard let source = source ?? palette else { return self }
        let src = source.colors.map(\.oklab)
        let dst = target.colors.map(\.oklab)

        func map(_ c: RGBA) -> RGBA {
            let lab = c.oklab
            var best = 0
            var bestDistance = Double.infinity
            for (i, s) in src.enumerated() {
                let d = (lab.l - s.l) * (lab.l - s.l) + (lab.a - s.a) * (lab.a - s.a) + (lab.b - s.b) * (lab.b - s.b)
                if d < bestDistance { bestDistance = d; best = i }
            }
            let out = OKLab(l: min(max(dst[best].l + (lab.l - src[best].l), 0), 1),
                            a: dst[best].a + (lab.a - src[best].a),
                            b: dst[best].b + (lab.b - src[best].b))
            return RGBA(lab: out, alpha: c.a)
        }

        var w = self
        w.background.stops = background.stops.map { RampStop($0.position, map($0.color)) }
        w.layers = layers.map { layer in
            var l = layer
            l.ramp = layer.ramp.map { RampStop($0.position, map($0.color)) }
            return l
        }
        w.palette = target
        if var o = w.origin { o.paletteName = target.name; w.origin = o }
        if let motif = w.origin.flatMap({ Motif(rawValue: $0.motif) }), let seed = w.origin?.seed {
            w.title = "\(motif.displayName) · \(target.name) · \(seed)"
        }
        return w
    }
}
