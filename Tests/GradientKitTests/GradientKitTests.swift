//
//  GradientKitTests.swift
//  GradientKitTests
//

import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import GradientKit

@Suite("Colour")
struct ColorTests {
    @Test("Hex round-trips")
    func hex() {
        let c = RGBA(hex: "#FF4553")!
        #expect(abs(c.r - 1) < 1e-9 && abs(c.g - 0x45 / 255.0) < 1e-9 && abs(c.b - 0x53 / 255.0) < 1e-9)
        #expect(c.hexString == "#FF4553")
        #expect(RGBA(hex: "abc")!.hexString == "#AABBCC")
        #expect(RGBA(hex: "#12345680")!.a == 0x80 / 255.0)
        #expect(RGBA(hex: "nope") == nil)
    }

    @Test("OKLab matches Ottosson's reference values")
    func oklab() {
        let white = RGBA.white.oklab
        #expect(abs(white.l - 1) < 1e-3 && abs(white.a) < 1e-3 && abs(white.b) < 1e-3)
        let red = RGBA(r: 1, g: 0, b: 0).oklab
        #expect(abs(red.l - 0.628) < 2e-3 && abs(red.a - 0.2249) < 2e-3 && abs(red.b - 0.1258) < 2e-3)
        // Round trip through OKLab and back.
        let c = RGBA(hex: "#3DE8F2")!
        let back = RGBA(lab: c.oklab)
        #expect(abs(back.r - c.r) < 2e-3 && abs(back.g - c.g) < 2e-3 && abs(back.b - c.b) < 2e-3)
    }

    @Test("OKLCH out-of-gamut requests are mapped back by chroma only")
    func gamut() {
        let c = RGBA(l: 0.7, c: 0.5, h: 30)   // far outside sRGB
        #expect((0...1).contains(c.r) && (0...1).contains(c.g) && (0...1).contains(c.b))
        let (l, _, h) = c.oklch
        #expect(abs(l - 0.7) < 0.02)
        #expect(abs(h - 30) < 3)
    }
}

@Suite("Model")
struct ModelTests {
    @Test("Wallpaper JSON round-trips")
    func json() throws {
        let w = Wallpaper.generate(.eclipse, seed: 7)
        let data = try w.jsonData()
        let back = try Wallpaper(jsonData: data)
        #expect(back == w)
        #expect(back.layers.count == w.layers.count)
    }

    @Test("Shape anchor / size accessors move the whole shape")
    func shapeAccessors() {
        var s = Shape.crescent(center: [0.5, 0.5], radius: 0.3, cutCenter: [0.5, 0.7], cutRadius: 0.3)
        s.anchor = [0.6, 0.5]
        if case let .crescent(c, _, cc, _) = s {
            #expect(c == [0.6, 0.5] && cc == [0.6, 0.7])
        } else { Issue.record("shape changed kind") }
        s.size = 0.4
        #expect(s.size == 0.4)
        var e = Shape.ellipse(center: [0, 0], radii: [0.4, 0.2], rotation: 10)
        e.size = 0.8
        if case let .ellipse(_, r, _) = e { #expect(r == [0.8, 0.4]) } else { Issue.record("shape changed kind") }
    }

    @Test("GPU layouts match the shader's expectations")
    func layouts() {
        #expect(MemoryLayout<GPUStop>.stride == 32)
        #expect(MemoryLayout<GPULayer>.stride == 176)
        #expect(MemoryLayout<GPUGlobals>.stride == 192)
    }
}

@Suite("Generator")
struct GeneratorTests {
    @Test("Same seed, same wallpaper; different seed, different wallpaper")
    func determinism() {
        for motif in Motif.allCases {
            let a = Wallpaper.generate(motif, seed: 42)
            let b = Wallpaper.generate(motif, seed: 42)
            let c = Wallpaper.generate(motif, seed: 43)
            #expect(a == b)
            #expect(a != c)
        }
    }

    @Test("Every motif stays within the renderer's limits")
    func limits() {
        for motif in Motif.allCases {
            for seed in 1...25 {
                let w = Wallpaper.generate(motif, seed: UInt64(seed))
                #expect(w.layers.count <= Wallpaper.maxLayers)
                #expect(w.layers.allSatisfy { $0.ramp.count <= Wallpaper.maxStops && $0.spread > 0 })
                #expect(w.background.stops.count <= Wallpaper.maxStops)
                #expect(w.title.hasPrefix(motif.displayName))
            }
        }
    }

    @Test("Generated palettes are in gamut and honour the mood")
    func palettes() {
        for seed in 1...50 {
            let dark = Palette.generate(mood: .dark, seed: UInt64(seed))
            let light = Palette.generate(mood: .light, seed: UInt64(seed))
            #expect(dark.base.luminance < 0.1)
            #expect(light.base.luminance > 0.5)
            #expect(dark.highlight.luminance > dark.accent.luminance)
            for c in dark.colors + light.colors {
                #expect((0...1).contains(c.r) && (0...1).contains(c.g) && (0...1).contains(c.b))
            }
        }
    }
}

@Suite("Renderer")
struct RendererTests {
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let data = image.dataProvider!.data! as Data
        let bpr = image.bytesPerRow
        let i = y * bpr + x * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    @Test("Solid background renders the requested colour")
    func solid() throws {
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .solid(RGBA(hex: "#4080C0")!))
        w.effects.grain = .none
        let img = try r.render(w, width: 64, height: 32)
        #expect(img.width == 64 && img.height == 32)
        let p = pixel(img, 10, 10)
        #expect(abs(p.r - 0x40) <= 1 && abs(p.g - 0x80) <= 1 && abs(p.b - 0xC0) <= 1)
    }

    @Test("A circle layer paints its inside colour and leaves the outside alone")
    func circle() throws {
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .solid(.black))
        w.effects.grain = .none
        w.layers = [Layer(shape: .circle(center: [0.5, 0.5], radius: 0.2), spread: 0.01,
                          ramp: [RampStop(-1, .white), RampStop(0, .white), RampStop(1, RGBA.white.with(alpha: 0))])]
        let img = try r.render(w, width: 200, height: 100)
        let inside = pixel(img, 100, 50)
        let outside = pixel(img, 5, 5)
        #expect(inside.r >= 254 && inside.g >= 254 && inside.b >= 254)
        #expect(outside.r <= 1 && outside.g <= 1 && outside.b <= 1)
    }

    @Test("Same seed gives identical bytes; a new seed changes the grain")
    func grainDeterminism() throws {
        let r = try WallpaperRenderer()
        let w = Wallpaper.generate(.orb, seed: 5)
        let a = try r.render(w, width: 160, height: 90)
        let b = try r.render(w, width: 160, height: 90)
        var w2 = w; w2.seed &+= 1
        let c = try r.render(w2, width: 160, height: 90)
        let da = a.dataProvider!.data! as Data, db = b.dataProvider!.data! as Data, dc = c.dataProvider!.data! as Data
        #expect(da == db)
        #expect(da != dc)
    }

    @Test("Sixteen-bit render and PNG export")
    func sixteenBit() throws {
        let r = try WallpaperRenderer()
        let w = Wallpaper.generate(.halo, seed: 9)
        let img = try r.render(w, width: 120, height: 80, options: .init(bitDepth: .sixteen))
        #expect(img.bitsPerComponent == 16)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gradientkit-\(UUID().uuidString).png")
        try ImageExport.write(img, to: url, format: .png)
        defer { try? FileManager.default.removeItem(at: url) }
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let back = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        #expect(back.width == 120 && back.height == 80 && back.bitsPerComponent == 16)
    }

    @Test("Every motif renders without error at a portrait and a landscape size")
    func allMotifs() throws {
        let r = try WallpaperRenderer()
        for motif in Motif.allCases {
            let w = Wallpaper.generate(motif, seed: 3)
            _ = try r.render(w, width: 96, height: 54)
            _ = try r.render(w, width: 54, height: 96)
        }
    }
}

@Suite("Renderer edge cases")
struct RendererEdgeTests {
    @Test("Extreme effect values never fail a render")
    func extremes() throws {
        let r = try WallpaperRenderer()
        for motif in Motif.allCases {
            var w = Wallpaper.generate(motif, seed: 11)
            w.effects.warp = Warp(amount: 0.2, scale: 4, octaves: 6)
            w.effects.aberration = 6
            w.effects.grain = Grain(intensity: 0.25, size: 4, chroma: 1, shadowBias: -1)
            w.effects.vignette = Vignette(intensity: 1, radius: 0, softness: 0.05)
            w.effects.tone = Tone(exposure: 2, contrast: 1.6, saturation: 2, hueShift: 180)
            for i in w.layers.indices {
                w.layers[i].distortion = Distortion(amount: 0.3, scale: 4, octaves: 6)
                w.layers[i].spread = 0.01
                w.layers[i].lighting = Lighting(angle: 0, amount: 1)
            }
            _ = try r.render(w, width: 320, height: 180)
            w.effects.warp.octaves = 0          // clamped to 1 on the way to the GPU
            w.layers = []
            _ = try r.render(w, width: 7, height: 3)
        }
    }

    @Test("Sizes beyond the GPU limit are refused, not attempted")
    func tooLarge() throws {
        let r = try WallpaperRenderer()
        #expect(throws: RenderError.self) {
            _ = try r.render(Wallpaper(background: .solid(.black)), width: r.maxSide + 1, height: 10)
        }
    }
}

@Suite("New shapes & features")
struct ShapeFeatureTests {
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let data = image.dataProvider!.data! as Data
        let i = y * image.bytesPerRow + x * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    @Test("Every shape kind renders and converts to every other kind")
    func kinds() throws {
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .solid(.black))
        w.effects.grain = .none
        for kind in Shape.Kind.allCases {
            let shape = Shape.circle(center: [0.5, 0.5], radius: 0.25).converted(to: kind)
            #expect(shape.kind == kind)
            w.layers = [Layer(shape: shape, spread: 0.05, ramp: [RampStop(-1, .white), RampStop(0, .white), RampStop(1, RGBA.white.with(alpha: 0))])]
            _ = try r.render(w, width: 64, height: 36)
            for other in Shape.Kind.allCases { #expect(shape.converted(to: other).kind == other) }
        }
    }

    @Test("A polygon and a rect paint their centres, stripes alternate, repeat folds")
    func geometry() throws {
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .solid(.black))
        w.effects.grain = .none
        let solid = [RampStop(-1, RGBA.white), RampStop(0, .white), RampStop(0.001, RGBA.white.with(alpha: 0))]
        w.layers = [Layer(shape: .polygon(center: [0.5, 0.5], radius: 0.3, sides: 6, rotation: 0, rounding: 0.02), spread: 0.01, ramp: solid)]
        var img = try r.render(w, width: 200, height: 100)
        #expect(pixel(img, 100, 50).r > 250)
        #expect(pixel(img, 2, 2).r < 3)
        w.layers = [Layer(shape: .rect(center: [0.5, 0.5], size: [0.4, 0.2], rotation: 0, cornerRadius: 0.05), spread: 0.01, ramp: solid)]
        img = try r.render(w, width: 200, height: 100)
        #expect(pixel(img, 100, 50).r > 250 && pixel(img, 100, 5).r < 3)
        // Stripes every 0.2 (min-side units = 20 px), 10 px wide, along y.
        w.layers = [Layer(shape: .stripes(through: [0.5, 0.5], angle: 90, period: 0.2, width: 0.1, bend: 0), spread: 0.005, ramp: solid)]
        img = try r.render(w, width: 100, height: 100)
        #expect(pixel(img, 50, 50).r > 250)   // on a stripe centre
        #expect(pixel(img, 50, 60).r < 3)     // between stripes
        // Concentric rings via repeat: a circle of radius 0.2 with period 0.1 spread.
        w.layers = [Layer(shape: .circle(center: [0.5, 0.5], radius: 0.2), spread: 0.1,
                          ramp: [RampStop(-0.5, RGBA.white.with(alpha: 0)), RampStop(-0.2, RGBA.white.with(alpha: 0)), RampStop(-0.05, .white),
                                 RampStop(0.05, .white), RampStop(0.2, RGBA.white.with(alpha: 0)), RampStop(0.5, RGBA.white.with(alpha: 0))],
                          repeatPeriod: 1)]
        img = try r.render(w, width: 100, height: 100)
        #expect(pixel(img, 70, 50).r > 250)   // d = 0 (radius 0.2 → 20 px from centre)
        #expect(pixel(img, 80, 50).r > 250)   // d = 0.1 → folded to 0 again
        #expect(pixel(img, 75, 50).r < 3)     // half-way between rings
    }

    @Test("Mesh background blends its corner colours")
    func mesh() throws {
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .mesh([RGBA(r: 1, g: 0, b: 0), RGBA(r: 0, g: 0, b: 1),
                                             RGBA(r: 0, g: 1, b: 0), RGBA(r: 1, g: 1, b: 1)], columns: 2, smoothing: 0))
        w.effects.grain = .none
        let img = try r.render(w, width: 100, height: 100)
        // A 1% OKLab mix towards a neighbour lifts a zero channel to ~30/255 after sRGB encoding.
        #expect(pixel(img, 1, 1).r > 240 && pixel(img, 1, 1).b < 60)      // top-left red
        #expect(pixel(img, 98, 1).b > 240 && pixel(img, 98, 1).r < 60)    // top-right blue
        #expect(pixel(img, 1, 98).g > 240 && pixel(img, 1, 98).r < 60)    // bottom-left green
        let mid = pixel(img, 50, 50)
        #expect(mid.r > 60 && mid.g > 60 && mid.b > 60)                   // a blend, not any corner
        let back = try Wallpaper(jsonData: try w.jsonData())
        #expect(back.background.meshColumns == 2 && back.background.meshRows == 2)
    }

    @Test("Older scene JSON without the new fields still decodes")
    func legacyJSON() throws {
        let json = """
        {"background":{"kind":"solid","stops":[{"position":0,"color":{"r":0,"g":0,"b":0,"a":1}}],"angle":90,"center":[0.5,0.5],"radius":0.8,"smoothing":0.5},
         "layers":[{"id":"3B1F1C1E-0000-4000-8000-000000000001","name":"x","shape":{"circle":{"center":[0.5,0.5],"radius":0.2}},"spread":0.3,
                    "ramp":[{"position":0,"color":{"r":1,"g":1,"b":1,"a":1}}],"blend":"normal","opacity":1,"smoothing":1,
                    "distortion":{"amount":0,"scale":2,"octaves":3},"lighting":{"angle":-90,"amount":0},"isEnabled":true}],
         "effects":{"grain":{"intensity":0.06,"size":1.5,"chroma":0.25,"shadowBias":0.3},"vignette":{"intensity":0,"radius":0.6,"softness":0.6},
                    "warp":{"amount":0,"scale":1.2,"octaves":2},"aberration":0,"tone":{"exposure":0,"contrast":1,"saturation":1,"hueShift":0}},
         "seed":1,"title":"legacy"}
        """
        let w = try Wallpaper(jsonData: Data(json.utf8))
        #expect(w.layers.count == 1 && w.layers[0].repeatPeriod == 0 && w.palette == nil && w.background.meshColumns == 2)
    }
}

@Suite("Library stores")
struct StoreTests {
    @Test("Palette store: defaults, save, override, reload, delete, import")
    func paletteStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var store = PaletteStore.standard(directory: dir)
        #expect(store.all.count == Palette.curated.count && store.custom.isEmpty)

        var mine = Palette.generate(mood: .light, seed: 3)
        mine.name = "Mine"
        try store.save(mine)
        #expect(store.item(named: "mine") == mine)
        #expect(store.isCustom(mine) && store.all.count == Palette.curated.count + 1)

        // Same name as a default → overrides it, count unchanged.
        var override = Palette.iris; override.accent = .black
        try store.save(override)
        #expect(store.all.count == Palette.curated.count + 1)
        #expect(store.item(named: "Iris")?.accent == .black)

        // A fresh store sees the files; a broken file is reported, not fatal.
        try Data("not json".utf8).write(to: dir.appendingPathComponent("broken.json"))
        let again = PaletteStore.standard(directory: dir)
        #expect(again.custom.count == 2 && again.problems.count == 1)

        try store.delete(mine)
        #expect(store.item(named: "Mine") == nil)
        #expect(store.item(named: "Iris")?.accent == .black)

        // Import an array file.
        let arrayURL = FileManager.default.temporaryDirectory.appendingPathComponent("gk-import-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: arrayURL) }
        try JSONEncoder().encode([Palette.solar, Palette.reef].map { var p = $0; p.name += " 2"; return p }).write(to: arrayURL)
        try store.importFile(at: arrayURL)
        #expect(store.item(named: "Solar 2") != nil && store.item(named: "Reef 2") != nil)
    }

    @Test("Gradient presets: bands, ladders, applying to layers")
    func gradientPresets() {
        let retro = GradientPreset(name: "r", bands: [.black, .white, .black], bandWidth: 0.1)
        #expect(retro.stepped && retro.stops.count == 3 && retro.stops[0].position == 0)
        #expect(abs(retro.stops[1].position - 0.4) < 1e-9 && abs(retro.stops[2].position - 0.5) < 1e-9)
        let ladder = Background.ladder([.black, .white], count: 8)
        #expect(ladder.stepped && ladder.stops.count == 8 && ladder.stops.last!.color.r > 0.99)
        var layer = Layer(shape: .circle(center: [0.5, 0.5], radius: 0.2), ramp: [])
        layer.apply(GradientPreset(name: "g", colors: [.black, .white]), from: -1, to: 1)
        #expect(layer.ramp.count == 2 && layer.ramp[0].position == -1 && layer.ramp[1].position == 1)
        #expect(GradientPreset.defaults.count > 10 && Set(GradientPreset.defaults.map(\.name)).count == GradientPreset.defaults.count)
        #expect(Set(Palette.curated.map(\.name)).count == Palette.curated.count)
    }
}

@Suite("Glyphs")
struct GlyphTests {
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let data = image.dataProvider!.data! as Data
        let i = y * image.bytesPerRow + x * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    @Test("Rasterised glyph has ink, a signed field, and the field is zero at the outline")
    func rasterise() {
        let bmp = GlyphRasterizer.render("●", size: 128)
        let n = bmp.size
        let centre = bmp.sdf[(n / 2) * n + n / 2]
        let corner = bmp.sdf[0]
        #expect(centre < -0.2 && corner > 0.2)
        #expect(bmp.rgba[((n / 2) * n + n / 2) * 4 + 3] > 200)
        // Somewhere on the middle row the field crosses zero.
        let row = (0..<n).map { bmp.sdf[(n / 2) * n + $0] }
        #expect(row.min()! < 0 && row.max()! > 0)
        #expect("🍒🍋🫧".glyphs.count == 3 && "a b".glyphs == ["a", "b"])
    }

    @Test("A glyph layer paints the emoji's own colour and a silhouette layer paints the ramp's")
    func render() throws {
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .solid(.black))
        w.effects.grain = .none
        // A red heart, own colours: centre pixel red-ish.
        w.layers = [Layer(shape: .glyph(text: "❤️", center: [0.5, 0.5], size: 0.6, rotation: 0), spread: 0.02,
                          ramp: [RampStop(-1, .white), RampStop(0, .white), RampStop(1, RGBA.white.with(alpha: 0))], glyphColor: 1)]
        var img = try r.render(w, width: 100, height: 100)
        let p = pixel(img, 50, 55)
        #expect(p.r > 150 && p.g < 120)
        #expect(pixel(img, 3, 3).r < 3)
        // Silhouette: same shape, ramp white, glyphColor 0 → white inside.
        w.layers[0].glyphColor = 0
        img = try r.render(w, width: 100, height: 100)
        let q = pixel(img, 50, 55)
        #expect(q.r > 240 && q.g > 240 && q.b > 240)
        // Pattern with several glyphs renders and reaches beyond one cell.
        w.layers = [Layer(shape: .glyphPattern(text: "●■▲", center: [0.5, 0.5], cell: [0.2, 0.2], size: 0.12, rotation: 15,
                                               stagger: 0.5, jitter: 0.1, rotationJitter: 20, scaleJitter: 0.1),
                          spread: 0.01, ramp: [RampStop(-1, .white), RampStop(0, .white), RampStop(1, RGBA.white.with(alpha: 0))], glyphColor: 0)]
        img = try r.render(w, width: 200, height: 120)
        let data = img.dataProvider!.data! as Data
        var lit = 0
        for i in stride(from: 0, to: data.count, by: 4) where data[i] > 200 { lit += 1 }
        #expect(lit > 200 && lit < 200 * 120 / 2)
        _ = try r.render(Wallpaper.generate(.emoji, seed: 4), width: 120, height: 200)
    }
}

@Suite("Symbols & shape files")
struct SymbolTests {
    @Test("Tokens split correctly and an SF Symbol rasterises with ink")
    func symbols() throws {
        #expect("sf:star.fill 🍒 file:x.svg ab".glyphs == ["sf:star.fill", "🍒", "file:x.svg", "a", "b"])
        #expect(GlyphRasterizer.Source("sf:heart.fill") == .symbol("heart.fill"))
        #expect(GlyphRasterizer.Source("file:a.png").token == "file:a.png")
        let bmp = GlyphRasterizer.render("sf:star.fill", size: 128)
        let n = bmp.size
        let inked = bmp.rgba.enumerated().filter { $0.offset % 4 == 3 && $0.element > 128 }.count
        #expect(inked > 500)
        #expect(bmp.sdf[(n / 2) * n + n / 2] < 0 && bmp.sdf[0] > 0)
        // Unknown symbol → empty glyph, never a crash.
        let none = GlyphRasterizer.render("sf:no.such.symbol.zzz", size: 32)
        #expect(none.sdf.allSatisfy { $0 > 0 })
    }

    @Test("A shape file is found through the search path and renders")
    func files() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-shapes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // A black disc on transparent, as PNG.
        let n = 64
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 8, y: 8, width: 48, height: 48))
        let url = dir.appendingPathComponent("disc.png")
        try ImageExport.write(ctx.makeImage()!, to: url, format: .png)
        GlyphRasterizer.shapeSearchPaths = [dir]
        defer { GlyphRasterizer.shapeSearchPaths = [] }
        let bmp = GlyphRasterizer.render("file:disc.png", size: 96)
        #expect(bmp.sdf[(96 / 2) * 96 + 96 / 2] < -0.2 && bmp.sdf[0] > 0.2)
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .solid(.black))
        w.effects.grain = .none
        w.layers = [Layer(shape: .glyphPattern(text: "file:disc.png sf:star.fill", center: [0.5, 0.5], cell: [0.3, 0.3], size: 0.2, rotation: 0,
                                               stagger: 0, jitter: 0, rotationJitter: 0, scaleJitter: 0),
                          spread: 0.01, ramp: [RampStop(-1, .white), RampStop(0, .white), RampStop(1, RGBA.white.with(alpha: 0))], glyphColor: 0)]
        _ = try r.render(w, width: 96, height: 64)
        _ = try r.render(Wallpaper.generate(.symbols, seed: 2), width: 96, height: 64)
    }
}

@Suite("Effect order")
struct EffectOrderTests {
    @Test("Order normalises, moves, round-trips, and changes the render")
    func order() throws {
        var e = Effects()
        #expect(e.order == Effects.defaultOrder)
        e.move(.grain, to: 0)
        #expect(e.order.first == .grain && e.order.count == 6 && Set(e.order).count == 6)
        e.order = [.tone, .tone, .liquify]
        #expect(Effects.normalized(e.order).count == 6)
        let back = try JSONDecoder().decode(Effects.self, from: JSONEncoder().encode(e))
        #expect(back.order == Effects.normalized(e.order))

        // Vignette then grain vs grain then vignette: the corner pixels differ.
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .solid(RGBA(r: 0.5, g: 0.5, b: 0.5)))
        w.effects = Effects(grain: Grain(intensity: 0.2, size: 1, chroma: 0), vignette: Vignette(intensity: 1, radius: 0.1, softness: 0.2))
        w.effects.order = Effects.normalized([.vignette, .grain])
        let a = try r.render(w, width: 64, height: 64)
        w.effects.order = Effects.normalized([.grain, .vignette])
        let b = try r.render(w, width: 64, height: 64)
        let da = a.dataProvider!.data! as Data, db = b.dataProvider!.data! as Data
        // Corner: grain-then-vignette is nearly black; vignette-then-grain keeps grain.
        // Sum the top row so a single unlucky (negative) grain sample can't hide the difference.
        var cornerA = 0, cornerB = 0
        for i in 0..<(64 * 4) { cornerA += Int(da[i]); cornerB += Int(db[i]) }
        #expect(cornerA > cornerB)
        // Bypassed effects keep their order entry.
        w.effects.bypassed = [.grain]
        #expect(w.effects.resolved.order.count == 6)
    }
}

@Suite("Recolour")
struct RecolorTests {
    @Test("Recolouring keeps layers, strokes and edits; moves colours to the new palette")
    func recolor() throws {
        var w = Wallpaper.generate(.eclipse, palette: .eclipse, seed: 7919)
        w.effects.smears = [Smear(position: [0.5, 0.5], vector: [0.1, 0], radius: 0.2)]
        w.layers.append(Layer.starter(.rect, palette: .eclipse))
        let r = w.recolored(to: .ember)
        #expect(r.layers.count == w.layers.count && r.effects.smears == w.effects.smears)
        #expect(r.palette == Palette.ember && r.origin?.paletteName == "Ember")
        // The stop that was closest to Eclipse's accent (cyan) should now sit near Ember's accent (red).
        func dist(_ a: RGBA, _ b: RGBA) -> Double {
            let x = a.oklab, y = b.oklab
            return (x.l - y.l) * (x.l - y.l) + (x.a - y.a) * (x.a - y.a) + (x.b - y.b) * (x.b - y.b)
        }
        let i = w.layers[0].ramp.indices.min { dist(w.layers[0].ramp[$0].color, Palette.eclipse.accent) < dist(w.layers[0].ramp[$1].color, Palette.eclipse.accent) }!
        let mappedHue = r.layers[0].ramp[i].color.oklch.h
        let targetHue = Palette.ember.accent.oklch.h
        let diff = abs(((mappedHue - targetHue) + 540).truncatingRemainder(dividingBy: 360) - 180)
        #expect(diff < 30)
        // Greys and alpha survive: a transparent stop stays transparent.
        #expect(r.layers[0].ramp.last!.color.a == 0)
        // No palette → unchanged.
        var bare = Wallpaper(background: .solid(.black)); bare.palette = nil
        #expect(bare.recolored(to: .ember) == bare)
        #expect(WallpaperGenerator.autoPalette(for: .eclipse, seed: 7919) == Wallpaper.generate(.eclipse, seed: 7919).palette)
    }
}

@Suite("Clip & rays")
struct ClipTests {
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> Int {
        let data = image.dataProvider!.data! as Data
        return Int(data[y * image.bytesPerRow + x * 4])
    }

    @Test("A clipped layer paints only inside its region; inverted, only outside")
    func clip() throws {
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .solid(.black))
        w.effects.grain = .none
        var white = Layer(shape: .line(through: [0.5, 0.5], angle: 0, bend: 0), spread: 0.001,
                          ramp: [RampStop(-1, .white), RampStop(0, .white), RampStop(0.01, .white)])
        white.ramp = [RampStop(-100, .white), RampStop(100, .white)]   // paints everywhere
        white.clip = .circle(center: [0.5, 0.5], radius: 0.2, feather: 0.002)
        w.layers = [white]
        var img = try r.render(w, width: 100, height: 100)
        #expect(pixel(img, 50, 50) > 250 && pixel(img, 5, 5) < 3)
        w.layers[0].clip?.inverted = true
        img = try r.render(w, width: 100, height: 100)
        #expect(pixel(img, 50, 50) < 3 && pixel(img, 5, 5) > 250)
        w.layers[0].clip = .rect(center: [0.5, 0.5], size: [0.4, 0.2], rotation: 0, feather: 0.002)
        img = try r.render(w, width: 100, height: 100)
        #expect(pixel(img, 50, 50) > 250 && pixel(img, 50, 30) < 3 && pixel(img, 65, 50) > 250)
        let back = try Wallpaper(jsonData: try w.jsonData())
        #expect(back.layers[0].clip == w.layers[0].clip)
    }

    @Test("Rays alternate around the centre")
    func rays() throws {
        let r = try WallpaperRenderer()
        var w = Wallpaper(background: .solid(.black))
        w.effects.grain = .none
        w.layers = [Layer(shape: .rays(center: [0.5, 0.5], count: 4, rotation: 0, width: 0.5), spread: 0.002,
                          ramp: [RampStop(-1, .white), RampStop(0, .white), RampStop(1, RGBA.white.with(alpha: 0))])]
        let img = try r.render(w, width: 100, height: 100)
        // 4 rays of half width: centred on 0°, 90°, 180°, 270°; gaps at 45° etc.
        #expect(pixel(img, 90, 50) > 250)          // 0°
        #expect(pixel(img, 80, 20) < 3)            // ~ -56°: in a gap
        for motif in [Motif.sunset, .saturn, .rays] { _ = try r.render(Wallpaper.generate(motif, seed: 3), width: 96, height: 54) }
    }
}

@Suite("Curation")
struct CurationTests {
    @Test("Featured motifs are colour fields, judged by eye, and nothing else")
    func featured() {
        #expect(Motif.featured == [.holo, .mesh, .aurora, .nebula, .classic])
        let allFeatured = Motif.featured.allSatisfy(\.isFeatured)
        #expect(allFeatured)
        #expect(!Motif.eclipse.isFeatured)
    }

    @Test("Every motif has a blurb")
    func blurbs() {
        for motif in Motif.allCases { #expect(!motif.blurb.isEmpty, "\(motif)") }
    }

    @Test("Soft palettes: five distinct low-chroma sets, four light and Dusk the one dark")
    func soft() {
        #expect(Palette.soft.count == 5)
        let names = Set(Palette.soft.map(\.name))
        #expect(names.count == Palette.soft.count)
        let allSoft = Palette.soft.allSatisfy(\.isSoft)
        #expect(allSoft)
        for palette in Palette.soft {
            let lab = palette.base.oklab
            let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
            #expect(chroma < 0.1, "\(palette.name) base is not pastel")
            // Dusk is the deliberate dark one (L 0.38); the rest sit above 0.88.
            if palette.name == "Dusk" { #expect(lab.l < 0.5) } else { #expect(lab.l > 0.85, "\(palette.name) base is not light") }
        }
    }
}
