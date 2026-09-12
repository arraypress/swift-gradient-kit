//
//  SVGExport.swift
//  GradientKit
//
//  The scene as vector art: real <linearGradient>/<radialGradient> defs and
//  one named <g> per layer, so pasting into Figma gives editable layers
//  rather than a flat picture.
//
//  This is a TRANSLATION, not the renderer. The engine draws colour as a
//  function of signed distance, evaluated per pixel; SVG has gradients along
//  a line and gradients from a point, and nothing else. Shapes whose field
//  is one of those two translate exactly (a circle's ramp IS a radial
//  gradient). Shapes whose field is procedural — the noise and cloth
//  fields — have no vector form at all, and coordinate effects (warp,
//  liquify) move pixels the geometry cannot follow.
//
//  So every export returns `notes`: the list of things that were
//  approximated or dropped. Show them. Silently handing someone a file that
//  does not match their screen is the one outcome worth engineering against.
//

import Foundation

public enum SVGExport {
    public struct Result: Sendable {
        public var svg: String
        /// Everything that is not a faithful translation, in scene order.
        /// Empty means the SVG matches the render.
        public var notes: [String]
        public var isExact: Bool { notes.isEmpty }
    }

    /// `grain` emits the film grain as an feTurbulence filter — vector and
    /// tiny, correct in browsers, but dropped by Figma's SVG import.
    public static func export(_ w: Wallpaper, width: Int, height: Int, grain: Bool = true) -> Result {
        var ctx = Context(width: Double(width), height: Double(height))
        var body = ""

        body += background(w.background, &ctx)
        for layer in w.layers where layer.isEnabled && layer.opacity > 0 {
            body += group(layer, &ctx)
        }
        body += overlays(w.effects, grain: grain, &ctx)
        ctx.noteEffects(w.effects)

        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" \
        viewBox="0 0 \(width) \(height)">
        <defs>\(ctx.defs)</defs>
        \(body)
        </svg>
        """
        return Result(svg: svg, notes: ctx.notes)
    }

    // MARK: - Context

    private struct Context {
        let width: Double
        let height: Double
        var defs = ""
        var notes: [String] = []
        private var nextID = 0

        var minSide: Double { min(width, height) }

        mutating func id(_ prefix: String) -> String {
            nextID += 1
            return "\(prefix)\(nextID)"
        }

        mutating func note(_ s: String) { if !notes.contains(s) { notes.append(s) } }

        /// Canvas-normalised position → pixels.
        func point(_ p: Vec2) -> (x: Double, y: Double) { (p.x * width, p.y * height) }
        /// Min-side units → pixels.
        func len(_ v: Double) -> Double { v * minSide }

        mutating func noteEffects(_ e: Effects) {
            let r = e.resolved
            if r.warp.amount != 0, r.isActive(.warp) {
                note("Domain warp is not vector: the SVG is the unwarped scene.")
            }
            if !r.smears.isEmpty, r.isActive(.liquify) {
                note("Liquify strokes are not vector: the SVG is the unsmeared scene.")
            }
            if r.aberration > 0, r.isActive(.aberration) {
                note("Chromatic aberration is dropped.")
            }
            if r.isActive(.tone), r.tone != Tone() {
                note("Tone (exposure/contrast/saturation/hue) is dropped — bake it into the colours if you need it.")
            }
        }
    }

    // MARK: - Ramp → gradient stops

    /// A ramp's stops as SVG `<stop>` elements. `offset(_:)` maps a ramp
    /// position to a 0…1 offset along the gradient.
    private static func stops(_ ramp: [RampStop], stepped: Bool,
                              offset: (Double) -> Double) -> String {
        let sorted = ramp.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return "" }
        var out = ""
        for (i, s) in sorted.enumerated() {
            let o = min(max(offset(s.position), 0), 1)
            // A stepped ramp holds each colour until the next stop, which in
            // SVG means doubling the stop at the boundary.
            if stepped, i > 0 {
                let prev = sorted[i - 1]
                out += stop(o, prev.color)
            }
            out += stop(o, s.color)
        }
        return out
    }

    private static func stop(_ offset: Double, _ c: RGBA) -> String {
        let op = c.a < 1 ? " stop-opacity=\"\(f(c.a, 3))\"" : ""
        // `stop-color` must be the OPAQUE colour: RGBA.hexString appends the
        // alpha byte when a < 1, and an 8-digit hex here would both
        // double-apply the alpha and be ignored by Figma's importer.
        return "<stop offset=\"\(f(offset * 100, 2))%\" stop-color=\"\(rgbHex(c))\"\(op)/>"
    }

    /// Six-digit hex, always — no alpha byte.
    private static func rgbHex(_ c: RGBA) -> String {
        let v = { (x: Double) -> String in String(format: "%02X", Int((min(max(x, 0), 1) * 255).rounded())) }
        return "#\(v(c.r))\(v(c.g))\(v(c.b))"
    }

    private static func f(_ v: Double, _ places: Int = 2) -> String {
        String(format: "%.\(places)f", v)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Background

    private static func background(_ bg: Background, _ ctx: inout Context) -> String {
        let W = ctx.width, H = ctx.height
        let rect = { (fill: String) in "<rect id=\"Background\" width=\"\(f(W))\" height=\"\(f(H))\" fill=\"\(fill)\"/>" }

        switch bg.kind {
        case .solid:
            return rect(bg.stops.first.map { rgbHex($0.color) } ?? "#000000")

        case .linear:
            let gid = ctx.id("bg")
            let a = bg.angle * .pi / 180
            // The gradient line through the centre, long enough to cover the
            // box along its own direction.
            let hx = abs(cos(a)) * W / 2, hy = abs(sin(a)) * H / 2
            let ext = hx + hy
            let cx = W / 2, cy = H / 2
            let x1 = cx - cos(a) * ext, y1 = cy - sin(a) * ext
            let x2 = cx + cos(a) * ext, y2 = cy + sin(a) * ext
            ctx.defs += "<linearGradient id=\"\(gid)\" gradientUnits=\"userSpaceOnUse\" "
                + "x1=\"\(f(x1))\" y1=\"\(f(y1))\" x2=\"\(f(x2))\" y2=\"\(f(y2))\">"
                + stops(bg.stops, stepped: bg.stepped) { $0 } + "</linearGradient>"
            return rect("url(#\(gid))")

        case .radial:
            let gid = ctx.id("bg")
            let c = ctx.point(bg.center)
            let r = ctx.len(bg.radius)
            ctx.defs += "<radialGradient id=\"\(gid)\" gradientUnits=\"userSpaceOnUse\" "
                + "cx=\"\(f(c.x))\" cy=\"\(f(c.y))\" r=\"\(f(max(r, 1)))\">"
                + stops(bg.stops, stepped: bg.stepped) { $0 } + "</radialGradient>"
            return rect("url(#\(gid))")

        case .conic:
            // SVG has no conic gradient in any shipping version, so the sweep
            // becomes wedges. 1° steps are smooth at wallpaper sizes.
            ctx.note("Conic background approximated as 360 wedge paths — SVG has no conic gradient.")
            let c = ctx.point(bg.center)
            let radius = (W + H)   // well past every corner
            var out = rect(bg.stops.first.map { rgbHex($0.color) } ?? "#000000")
            out += "<g id=\"Conic\">"
            let steps = 360
            for i in 0..<steps {
                let t0 = Double(i) / Double(steps)
                let a0 = bg.angle * .pi / 180 + t0 * 2 * .pi
                let a1 = bg.angle * .pi / 180 + (Double(i + 1) / Double(steps)) * 2 * .pi
                let col = rampColor(bg.stops, at: t0, stepped: bg.stepped, smoothing: bg.smoothing)
                let p0 = (c.x + cos(a0) * radius, c.y + sin(a0) * radius)
                let p1 = (c.x + cos(a1) * radius, c.y + sin(a1) * radius)
                out += "<path d=\"M\(f(c.x)),\(f(c.y)) L\(f(p0.0)),\(f(p0.1)) L\(f(p1.0)),\(f(p1.1)) Z\" "
                    + "fill=\"\(rgbHex(col))\"/>"
            }
            return out + "</g>"

        case .mesh, .points:
            // Both become soft radial blobs over a ground — the same trick
            // the web editors use. A grid reads well; an inverse-distance
            // field is close but not identical, because IDW has no falloff
            // radius and every point reaches the whole canvas.
            let isPoints = bg.kind == .points
            ctx.note(isPoints
                ? "Points background approximated as overlapping radial blobs — inverse-distance blending has no vector form. Colours and placement are right; the falloff is close, not exact."
                : "Grid background approximated as overlapping radial blobs.")
            var placed: [(Vec2, RGBA)] = []
            if isPoints {
                placed = bg.points.map { ($0.position, $0.color) }
            } else {
                let cols = max(1, bg.meshColumns), rows = max(1, bg.meshRows)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let i = row * cols + col
                        guard i < bg.stops.count else { continue }
                        let x = cols > 1 ? Double(col) / Double(cols - 1) : 0.5
                        let y = rows > 1 ? Double(row) / Double(rows - 1) : 0.5
                        placed.append(([x, y], bg.stops[i].color))
                    }
                }
            }
            guard !placed.isEmpty else { return rect("#000000") }
            let ground = averageColor(placed.map(\.1))
            var out = rect(rgbHex(ground))
            out += "<g id=\"Field\">"
            // Match the falloff to the real one. IDW weight goes as
            // 1/d^(2·mixing), so the normalised alpha of one point against a
            // neighbour at the reach distance is about 1/(1+(d/k)^(2·mixing)).
            // A 3-stop fade (the obvious choice) is far too soft and the
            // export reads washed out next to the render; sampling that
            // curve at six stops tracks it closely.
            let exponent = isPoints ? 2 * max(0.4, bg.mixing) : 2.0
            let reach = ctx.len(isPoints ? 0.72 : 0.8)
            for (i, item) in placed.enumerated() {
                let gid = ctx.id("blob")
                let c = ctx.point(item.0)
                var fade = ""
                for step in 0...6 {
                    let u = Double(step) / 6
                    let alpha = u <= 0 ? 1 : 1 / (1 + pow(u / 0.42, exponent))
                    fade += stop(u, item.1.with(alpha: alpha * item.1.a))
                }
                ctx.defs += "<radialGradient id=\"\(gid)\">" + fade + "</radialGradient>"
                out += "<ellipse id=\"Blob \(i + 1)\" cx=\"\(f(c.x))\" cy=\"\(f(c.y))\" "
                    + "rx=\"\(f(reach))\" ry=\"\(f(reach))\" fill=\"url(#\(gid))\"/>"
            }
            return out + "</g>"
        }
    }

    private static func averageColor(_ cs: [RGBA]) -> RGBA {
        guard !cs.isEmpty else { return .black }
        // Average in OKLab so the ground is not the muddy sRGB midpoint.
        var l = 0.0, a = 0.0, b = 0.0
        for c in cs { let o = c.oklab; l += o.l; a += o.a; b += o.b }
        let n = Double(cs.count)
        return RGBA(lab: OKLab(l: l / n, a: a / n, b: b / n))
    }

    /// Sample a ramp the way the shader does, for the places SVG needs a
    /// flat colour (conic wedges).
    private static func rampColor(_ ramp: [RampStop], at t: Double, stepped: Bool, smoothing: Double) -> RGBA {
        let s = ramp.sorted { $0.position < $1.position }
        guard let first = s.first, let last = s.last else { return .black }
        if t <= first.position { return first.color }
        if t >= last.position { return last.color }
        for i in 0..<(s.count - 1) where t >= s[i].position && t <= s[i + 1].position {
            if stepped { return s[i].color }
            let span = s[i + 1].position - s[i].position
            var u = span > 0 ? (t - s[i].position) / span : 0
            u = u + (u * u * (3 - 2 * u) - u) * smoothing
            return s[i].color.mixed(with: s[i + 1].color, u)
        }
        return last.color
    }

    // MARK: - Layers

    private static func group(_ layer: Layer, _ ctx: inout Context) -> String {
        let name = layer.name.isEmpty ? layer.shape.kind.displayName : layer.name
        guard let content = shape(layer, &ctx) else { return "" }

        if layer.distortion.isActive {
            ctx.note("\(name): edge distortion is not vector — the SVG edge is undistorted.")
        }
        if layer.lighting.isActive {
            ctx.note("\(name): one-sided light is dropped.")
        }
        if layer.repeatPeriod > 0 {
            ctx.note("\(name): the repeating ramp is drawn once, not folded.")
        }
        if layer.hueSweep != 0 {
            ctx.note("\(name): hue sweep is dropped.")
        }
        if layer.blend != .normal {
            ctx.note("\(name): blend mode \(layer.blend.rawValue) — SVG uses mix-blend-mode, which Figma ignores on import.")
        }

        var attrs = " id=\"\(esc(name))\""
        if layer.opacity < 1 { attrs += " opacity=\"\(f(layer.opacity, 3))\"" }
        if layer.blend != .normal { attrs += " style=\"mix-blend-mode:\(cssBlend(layer.blend))\"" }
        return "<g\(attrs)>\(content)</g>"
    }

    private static func cssBlend(_ b: BlendMode) -> String {
        switch b {
        case .normal: "normal"
        case .add: "plus-lighter"
        case .screen: "screen"
        case .multiply: "multiply"
        case .softLight: "soft-light"
        case .overlay: "overlay"
        }
    }

    /// A radial gradient whose stops sit at (inner + t·spread) / outer.
    private static func radialFill(_ layer: Layer, centre: (x: Double, y: Double),
                                   inner: Double, _ ctx: inout Context) -> (fill: String, radius: Double) {
        let spread = ctx.len(max(layer.spread, 1e-4))
        let maxT = layer.ramp.map(\.position).max() ?? 1
        let outer = max(inner + maxT * spread, 1)
        let gid = ctx.id("g")
        ctx.defs += "<radialGradient id=\"\(gid)\" gradientUnits=\"userSpaceOnUse\" "
            + "cx=\"\(f(centre.x))\" cy=\"\(f(centre.y))\" r=\"\(f(outer))\">"
            + stops(layer.ramp, stepped: layer.stepped) { (inner + $0 * spread) / outer }
            + "</radialGradient>"
        return ("url(#\(gid))", outer)
    }

    private static func name(_ layer: Layer) -> String {
        layer.name.isEmpty ? layer.shape.kind.displayName : layer.name
    }

    private static func shape(_ layer: Layer, _ ctx: inout Context) -> String? {
        switch layer.shape {
        case let .circle(centre, radius):
            let c = ctx.point(centre)
            let (fill, r) = radialFill(layer, centre: c, inner: ctx.len(radius), &ctx)
            return "<circle cx=\"\(f(c.x))\" cy=\"\(f(c.y))\" r=\"\(f(r))\" fill=\"\(fill)\"/>"

        case let .ellipse(centre, radii, rotation):
            let c = ctx.point(centre)
            let rx = ctx.len(radii.x), ry = ctx.len(radii.y)
            let (fill, r) = radialFill(layer, centre: c, inner: max(rx, ry), &ctx)
            let k = max(rx, ry) > 0 ? min(rx, ry) / max(rx, ry) : 1
            let t = rx >= ry
                ? "rotate(\(f(rotation)) \(f(c.x)) \(f(c.y))) translate(0 \(f(c.y))) scale(1 \(f(k, 4))) translate(0 \(f(-c.y)))"
                : "rotate(\(f(rotation)) \(f(c.x)) \(f(c.y))) translate(\(f(c.x)) 0) scale(\(f(k, 4)) 1) translate(\(f(-c.x)) 0)"
            return "<g transform=\"\(t)\"><circle cx=\"\(f(c.x))\" cy=\"\(f(c.y))\" r=\"\(f(r))\" fill=\"\(fill)\"/></g>"

        case let .polygon(centre, radius, sides, rotation, _):
            let c = ctx.point(centre)
            let (fill, _) = radialFill(layer, centre: c, inner: ctx.len(radius), &ctx)
            let n = max(3, min(sides, 24))
            let rr = ctx.len(radius)
            let pts = (0..<n).map { i -> String in
                let a = rotation * .pi / 180 + Double(i) * 2 * .pi / Double(n)
                return "\(f(c.x + cos(a) * rr)),\(f(c.y + sin(a) * rr))"
            }.joined(separator: " ")
            ctx.note("\(layer.name.isEmpty ? "Polygon" : layer.name): the glow outside the polygon is approximated by a radial fill.")
            return "<polygon points=\"\(pts)\" fill=\"\(fill)\"/>"

        case let .line(through, angle, _):
            // A half-plane's ramp runs along the normal — exactly a linear gradient.
            let p = ctx.point(through)
            let spread = ctx.len(max(layer.spread, 1e-4))
            let a = angle * .pi / 180
            let minT = layer.ramp.map(\.position).min() ?? -1
            let maxT = layer.ramp.map(\.position).max() ?? 1
            let x1 = p.x + cos(a) * minT * spread, y1 = p.y + sin(a) * minT * spread
            let x2 = p.x + cos(a) * maxT * spread, y2 = p.y + sin(a) * maxT * spread
            let gid = ctx.id("g")
            let span = maxT - minT
            ctx.defs += "<linearGradient id=\"\(gid)\" gradientUnits=\"userSpaceOnUse\" "
                + "x1=\"\(f(x1))\" y1=\"\(f(y1))\" x2=\"\(f(x2))\" y2=\"\(f(y2))\">"
                + stops(layer.ramp, stepped: layer.stepped) { span > 0 ? ($0 - minT) / span : 0 }
                + "</linearGradient>"
            return "<rect width=\"\(f(ctx.width))\" height=\"\(f(ctx.height))\" fill=\"url(#\(gid))\"/>"

        case let .discs(centre, cell, radius, rotation, stagger, jitter, scaleJitter):
            if jitter > 0 || scaleJitter > 0 {
                ctx.note("\(layer.name.isEmpty ? "Discs" : layer.name): per-cell jitter is hash-based on the GPU; the SVG lays the discs out evenly.")
            }
            let gid = ctx.id("g")
            let spread = ctx.len(max(layer.spread, 1e-4))
            let rr = ctx.len(radius)
            let maxT = layer.ramp.map(\.position).max() ?? 1
            let outer = max(rr + maxT * spread, 1)
            ctx.defs += "<radialGradient id=\"\(gid)\">"
                + stops(layer.ramp, stepped: layer.stepped) { (rr + $0 * spread) / outer }
                + "</radialGradient>"
            let cw = ctx.len(cell.x), ch = ctx.len(cell.y)
            guard cw > 1, ch > 1 else { return nil }
            let c = ctx.point(centre)
            var out = "<g transform=\"rotate(\(f(rotation)) \(f(c.x)) \(f(c.y)))\">"
            let cols = Int((ctx.width * 1.6) / cw) + 2, rows = Int((ctx.height * 1.6) / ch) + 2
            for row in -rows / 2...rows / 2 {
                for col in -cols / 2...cols / 2 {
                    let x = c.x + Double(col) * cw - stagger * cw * Double(row)
                    let y = c.y + Double(row) * ch
                    guard x > -outer, x < ctx.width + outer, y > -outer, y < ctx.height + outer else { continue }
                    out += "<circle cx=\"\(f(x))\" cy=\"\(f(y))\" r=\"\(f(outer))\" fill=\"url(#\(gid))\"/>"
                }
            }
            return out + "</g>"

        case let .hexagons(centre, cell, inset, rotation):
            let gid = ctx.id("g")
            let colour = rampColor(layer.ramp, at: -0.5, stepped: layer.stepped, smoothing: layer.smoothing)
            let edge = rampColor(layer.ramp, at: 0.2, stepped: layer.stepped, smoothing: layer.smoothing)
            ctx.defs += "<radialGradient id=\"\(gid)\">" + stop(0, colour) + stop(1, edge) + "</radialGradient>"
            ctx.note("\(layer.name.isEmpty ? "Honeycomb" : layer.name): each cell gets a two-stop fill; the GPU ramps colour continuously across the cell edge.")
            let r = ctx.len(cell) - ctx.len(inset)
            let pitchX = ctx.len(cell) * 1.7320508, pitchY = ctx.len(cell) * 1.5
            guard pitchX > 1, pitchY > 1 else { return nil }
            let c = ctx.point(centre)
            var out = "<g transform=\"rotate(\(f(rotation)) \(f(c.x)) \(f(c.y)))\">"
            let cols = Int((ctx.width * 1.6) / pitchX) + 2, rows = Int((ctx.height * 1.6) / pitchY) + 2
            for row in -rows / 2...rows / 2 {
                for col in -cols / 2...cols / 2 {
                    let x = c.x + Double(col) * pitchX + (row % 2 == 0 ? 0 : pitchX / 2)
                    let y = c.y + Double(row) * pitchY
                    guard x > -pitchX, x < ctx.width + pitchX, y > -pitchY, y < ctx.height + pitchY else { continue }
                    let pts = (0..<6).map { i -> String in
                        let a = Double(i) * .pi / 3 + .pi / 6
                        return "\(f(x + cos(a) * r)),\(f(y + sin(a) * r))"
                    }.joined(separator: " ")
                    out += "<polygon points=\"\(pts)\" fill=\"url(#\(gid))\"/>"
                }
            }
            return out + "</g>"

        case let .rays(centre, count, rotation, width):
            let c = ctx.point(centre)
            let colour = rampColor(layer.ramp, at: -0.5, stepped: layer.stepped, smoothing: layer.smoothing)
            let len = (ctx.width + ctx.height)
            var out = ""
            let n = max(1, count)
            for i in 0..<n {
                let step = 2 * .pi / Double(n)
                let mid = rotation * .pi / 180 + Double(i) * step
                let half = step * max(0, min(width, 1)) / 2
                let p0 = (c.x + cos(mid - half) * len, c.y + sin(mid - half) * len)
                let p1 = (c.x + cos(mid + half) * len, c.y + sin(mid + half) * len)
                out += "<path d=\"M\(f(c.x)),\(f(c.y)) L\(f(p0.0)),\(f(p0.1)) L\(f(p1.0)),\(f(p1.1)) Z\" "
                    + "fill=\"\(rgbHex(colour))\"\(colour.a < 1 ? " fill-opacity=\"\(f(colour.a, 3))\"" : "")/>"
            }
            ctx.note("\(layer.name.isEmpty ? "Rays" : layer.name): wedges are flat-filled; the GPU softens their edges.")
            return out

        case .noise, .cloth:
            ctx.note("\(layer.name.isEmpty ? layer.shape.kind.displayName : layer.name): \(layer.shape.kind.displayName) is a procedural field with no vector form — this layer is MISSING from the SVG. Export PNG for it.")
            return nil

        case let .rect(centre, size, rotation, cornerRadius):
            // The ramp runs outwards from the rect's edge in every direction,
            // which is a rounded-rect offset field. A radial fill centred on
            // the box is the closest SVG gets; exact on the diagonals, a
            // little tight along the long sides.
            let c = ctx.point(centre)
            let w = ctx.len(size.x), h = ctx.len(size.y)
            let (fill, _) = radialFill(layer, centre: c, inner: max(w, h) / 2, &ctx)
            let cr = min(ctx.len(cornerRadius), min(w, h) / 2)
            if abs(size.x - size.y) > 1e-6 {
                ctx.note("\(name(layer)): the rectangle's glow is radial in SVG, so it is tighter along the long sides than the render.")
            }
            return "<rect x=\"\(f(c.x - w / 2))\" y=\"\(f(c.y - h / 2))\" width=\"\(f(w))\" height=\"\(f(h))\" "
                + "rx=\"\(f(cr))\" fill=\"\(fill)\" "
                + "transform=\"rotate(\(f(rotation)) \(f(c.x)) \(f(c.y)))\"/>"

        case let .capsule(from, to, radius):
            // A capsule's field is the distance to its AXIS, so the ramp runs
            // across the beam, not out from its midpoint. That makes it a
            // linear gradient along the normal, mirrored about the centre
            // line — faithful down the whole length. (A radial fill here
            // renders as a blob at the midpoint, which is simply wrong.)
            let a = ctx.point(from), b = ctx.point(to)
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 1e-6 else { return nil }
            let nx = -dy / length, ny = dx / length              // unit normal
            let mid = (x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let rr = ctx.len(radius)
            let spread = ctx.len(max(layer.spread, 1e-4))
            let maxT = layer.ramp.map(\.position).max() ?? 1
            let outer = max(rr + maxT * spread, 1)
            let gid = ctx.id("g")
            let sorted = layer.ramp.sorted { $0.position < $1.position }
            var mirrored = ""
            // Far side → axis → near side.
            for st in sorted.reversed() {
                mirrored += stop(0.5 - (rr + st.position * spread) / (2 * outer), st.color)
            }
            for st in sorted {
                mirrored += stop(0.5 + (rr + st.position * spread) / (2 * outer), st.color)
            }
            ctx.defs += "<linearGradient id=\"\(gid)\" gradientUnits=\"userSpaceOnUse\" "
                + "x1=\"\(f(mid.x - nx * outer))\" y1=\"\(f(mid.y - ny * outer))\" "
                + "x2=\"\(f(mid.x + nx * outer))\" y2=\"\(f(mid.y + ny * outer))\">"
                + mirrored + "</linearGradient>"
            ctx.note("\(name(layer)): the beam's rounded ends are square in SVG — the ramp is drawn across the beam, not around its caps.")
            return "<line x1=\"\(f(a.x))\" y1=\"\(f(a.y))\" x2=\"\(f(b.x))\" y2=\"\(f(b.y))\" "
                + "stroke=\"url(#\(gid))\" stroke-width=\"\(f(outer * 2))\" stroke-linecap=\"butt\"/>"

        case let .blob(centre, radius, lobes, wobble, rotation):
            // Exact geometry: sample the wobbling radius and close the path.
            let c = ctx.point(centre)
            let rr = ctx.len(radius)
            let (fill, outer) = radialFill(layer, centre: c, inner: rr, &ctx)
            let steps = 180
            var d = ""
            for i in 0...steps {
                let theta = Double(i) / Double(steps) * 2 * .pi
                // Matches the shader: r·(1 + wobble·sin(lobes·θ + rotation)).
                let scale = 1 + wobble * sin(Double(max(1, lobes)) * theta + rotation * .pi / 180)
                let rad = (outer / max(rr, 1e-4)) * rr * scale
                let x = c.x + cos(theta) * rad, y = c.y + sin(theta) * rad
                d += i == 0 ? "M\(f(x)),\(f(y))" : "L\(f(x)),\(f(y))"
            }
            return "<path d=\"\(d) Z\" fill=\"\(fill)\"/>"

        case let .ring(centre, radius, thickness):
            // |distance to the circle| − thickness: symmetric about the ring
            // line, so a stroked circle with the ramp mirrored around it.
            let c = ctx.point(centre)
            let spread = ctx.len(max(layer.spread, 1e-4))
            let th = ctx.len(thickness)
            let maxT = layer.ramp.map(\.position).max() ?? 1
            let outer = th + maxT * spread
            let gid = ctx.id("g")
            // A radial gradient centred on the ring: stops mirrored so the
            // band reads the same inside and out, which is what |d| means.
            let rOuter = ctx.len(radius) + outer
            var mirrored = ""
            for st in layer.ramp.sorted(by: { $0.position > $1.position }) {
                let r = ctx.len(radius) - (th + st.position * spread)
                mirrored += stop(max(0, r) / rOuter, st.color)
            }
            for st in layer.ramp.sorted(by: { $0.position < $1.position }) {
                let r = ctx.len(radius) + th + st.position * spread
                mirrored += stop(min(rOuter, r) / rOuter, st.color)
            }
            ctx.defs += "<radialGradient id=\"\(gid)\" gradientUnits=\"userSpaceOnUse\" "
                + "cx=\"\(f(c.x))\" cy=\"\(f(c.y))\" r=\"\(f(rOuter))\">" + mirrored + "</radialGradient>"
            return "<circle cx=\"\(f(c.x))\" cy=\"\(f(c.y))\" r=\"\(f(rOuter))\" fill=\"url(#\(gid))\"/>"

        case let .crescent(centre, radius, cutCentre, cutRadius):
            // A disc with a disc subtracted: exact as an even-odd path pair.
            let c = ctx.point(centre), cc = ctx.point(cutCentre)
            let (fill, outer) = radialFill(layer, centre: c, inner: ctx.len(radius), &ctx)
            let cutR = ctx.len(cutRadius)
            let cid = ctx.id("cut")
            ctx.defs += "<mask id=\"\(cid)\">"
                + "<rect width=\"\(f(ctx.width))\" height=\"\(f(ctx.height))\" fill=\"white\"/>"
                + "<circle cx=\"\(f(cc.x))\" cy=\"\(f(cc.y))\" r=\"\(f(cutR))\" fill=\"black\"/></mask>"
            ctx.note("\(name(layer)): the crescent's soft edge is radial from its own centre, so the cut side is harder than the render.")
            return "<circle cx=\"\(f(c.x))\" cy=\"\(f(c.y))\" r=\"\(f(outer))\" fill=\"\(fill)\" mask=\"url(#\(cid))\"/>"

        case let .tiles(centre, cell, inset, cornerRadius, rotation, stagger):
            // A rect lattice — the same construction as discs.
            let gid = ctx.id("g")
            let inside = rampColor(layer.ramp, at: -0.5, stepped: layer.stepped, smoothing: layer.smoothing)
            let edge = rampColor(layer.ramp, at: 0.2, stepped: layer.stepped, smoothing: layer.smoothing)
            ctx.defs += "<linearGradient id=\"\(gid)\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">"
                + stop(0, inside) + stop(1, edge) + "</linearGradient>"
            ctx.note("\(name(layer)): each tile gets a two-stop fill; the GPU ramps colour continuously across the tile edge.")
            let cw = ctx.len(cell.x), ch = ctx.len(cell.y)
            guard cw > 1, ch > 1 else { return nil }
            let tw = max(cw - 2 * ctx.len(inset), 1), th2 = max(ch - 2 * ctx.len(inset), 1)
            let cr = min(ctx.len(cornerRadius), min(tw, th2) / 2)
            let c = ctx.point(centre)
            var out = "<g transform=\"rotate(\(f(rotation)) \(f(c.x)) \(f(c.y)))\">"
            let cols = Int((ctx.width * 1.6) / cw) + 2, rows = Int((ctx.height * 1.6) / ch) + 2
            for row in -rows / 2...rows / 2 {
                for col in -cols / 2...cols / 2 {
                    let x = c.x + Double(col) * cw - stagger * cw * Double(row)
                    let y = c.y + Double(row) * ch
                    guard x > -cw, x < ctx.width + cw, y > -ch, y < ctx.height + ch else { continue }
                    out += "<rect x=\"\(f(x - tw / 2))\" y=\"\(f(y - th2 / 2))\" width=\"\(f(tw))\" height=\"\(f(th2))\" "
                        + "rx=\"\(f(cr))\" fill=\"url(#\(gid))\"/>"
                }
            }
            return out + "</g>"

        case .stripes, .chevrons, .wave:
            // Periodic half-plane fields. Expressible, but each needs its own
            // tiling construction and they are the least likely to be the
            // reason someone wants vector output. Say so rather than guess.
            ctx.note("\(name(layer)): \(layer.shape.kind.displayName) layers are not translated yet — this layer is MISSING from the SVG.")
            return nil
        }
    }

    // MARK: - Effects

    private static func overlays(_ effects: Effects, grain: Bool, _ ctx: inout Context) -> String {
        let e = effects.resolved
        var out = ""
        if e.vignette.intensity > 0, e.isActive(.vignette) {
            let gid = ctx.id("vig")
            let r = ctx.len(max(e.vignette.radius, 0.1)) * 1.4
            ctx.defs += "<radialGradient id=\"\(gid)\" gradientUnits=\"userSpaceOnUse\" "
                + "cx=\"\(f(ctx.width / 2))\" cy=\"\(f(ctx.height / 2))\" r=\"\(f(r))\">"
                + "<stop offset=\"\(f((1 - min(max(e.vignette.softness, 0), 1)) * 100))%\" stop-color=\"#000000\" stop-opacity=\"0\"/>"
                + "<stop offset=\"100%\" stop-color=\"#000000\" stop-opacity=\"\(f(min(e.vignette.intensity, 1), 3))\"/>"
                + "</radialGradient>"
            out += "<rect id=\"Vignette\" width=\"\(f(ctx.width))\" height=\"\(f(ctx.height))\" fill=\"url(#\(gid))\"/>"
        }
        if grain, e.grain.intensity > 0, e.isActive(.grain) {
            let fid = ctx.id("grain")
            // feTurbulence, not an embedded bitmap: a few hundred bytes
            // instead of a hundred kilobytes, and resolution-independent.
            ctx.defs += "<filter id=\"\(fid)\" x=\"0\" y=\"0\" width=\"100%\" height=\"100%\">"
                + "<feTurbulence type=\"fractalNoise\" baseFrequency=\"0.8\" numOctaves=\"3\" stitchTiles=\"stitch\"/>"
                + "<feColorMatrix type=\"saturate\" values=\"0\"/>"
                + "</filter>"
            out += "<rect id=\"Film grain\" width=\"\(f(ctx.width))\" height=\"\(f(ctx.height))\" "
                + "filter=\"url(#\(fid))\" opacity=\"\(f(min(e.grain.intensity, 1) * 0.5, 3))\" "
                + "style=\"mix-blend-mode:overlay\"/>"
            ctx.note("Film grain uses an feTurbulence filter: correct in a browser, dropped by Figma.")
        }
        return out
    }
}
