//
//  Smear+Random.swift
//  GradientKit
//
//  Liquify strokes generated rather than painted.
//
//  The trick is that a stroke is not a scatter of pokes: each one is a
//  PATH, sampled densely enough that consecutive smears overlap, with the
//  push vector following the path's tangent. That is what the brush does
//  when a hand drags it, and it is what makes the result read as one
//  continuous swish instead of a row of dents.
//

import Foundation

public extension Smear {
    /// A handful of smooth strokes across the canvas.
    ///
    /// - Parameters:
    ///   - count: how many separate strokes.
    ///   - seed: same seed, same strokes.
    ///   - strength: 0…1.5, scales how hard each stroke pushes.
    ///   - scale: 0…1, how large the brush is relative to the picture.
    static func randomStrokes(count: Int = 3,
                              seed: UInt64,
                              strength: Double = 0.9,
                              scale: Double = 1) -> [Smear] {
        var rng = SeededRandom(seed: seed)
        var out: [Smear] = []

        for _ in 0..<max(1, count) {
            let radius = rng.double(in: 0.10...0.26) * max(0.2, scale)
            // Start off the edge as often as not, so a stroke can sweep in
            // from outside rather than always beginning mid-picture.
            var p: Vec2 = rng.bool(0.45)
                ? [rng.bool() ? rng.double(in: -0.15...0.05) : rng.double(in: 0.95...1.15),
                   rng.double(in: 0...1)]
                : [rng.double(in: 0.15...0.85), rng.double(in: 0.15...0.85)]

            var heading = rng.double(in: 0...(2 * .pi))
            // How sharply the path bends per step. Small, or it stops
            // reading as a single gesture and becomes a scribble.
            let curl = rng.double(in: -0.22...0.22)
            let wobble = rng.double(in: 0...0.06)
            let steps = rng.int(in: 10...22)
            // Overlap is what makes it smooth: a quarter of the brush per
            // step is what the painted version uses.
            let step = radius * 0.25
            let kind: Smear.Kind = rng.bool(0.8) ? .push : .swirl
            let softness = rng.double(in: 0.25...0.6)
            let push = rng.double(in: 0.5...1.0) * strength

            for s in 0..<steps {
                let t = Double(s) / Double(steps - 1)
                // Taper both ends so a stroke fades in and out rather than
                // starting and stopping with a hard dent.
                let taper = sin(t * .pi)
                heading += curl * (1.0 / Double(steps)) * 6 + rng.jitter(wobble)
                let dir: Vec2 = [cos(heading), sin(heading)]
                out.append(Smear(kind: kind,
                                 position: p,
                                 vector: [dir.x * step * push * taper * 3,
                                          dir.y * step * push * taper * 3],
                                 radius: radius,
                                 strength: max(0.05, push * taper),
                                 softness: softness))
                p = [p.x + dir.x * step, p.y + dir.y * step]
                // Once a path has wandered well outside, the rest of the
                // stroke would do nothing visible.
                if p.x < -0.4 || p.x > 1.4 || p.y < -0.4 || p.y > 1.4 { break }
            }
        }
        return Array(out.prefix(Effects.maxSmears))
    }
}
