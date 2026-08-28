//
//  main.swift
//  gradientkit-samples
//
//  Renders every motif at a range of seeds into a folder, plus a contact
//  sheet — the fastest way to eyeball a recipe change.
//
//    swift run gradientkit-samples [outDir] [--seeds N] [--width W] [--height H] [--motif name] [--palette name]
//    swift run gradientkit-samples outDir --picks eclipse:7919,orb:16838 --width 5120 --height 2880 [--16bit]
//

import Foundation
import CoreGraphics
import GradientKit

let args = CommandLine.arguments.dropFirst()
var outDir = URL(fileURLWithPath: "Examples/output")
var seeds = 4
var width = 960, height = 540
var motifFilter: Motif? = nil
var paletteFilter: Palette? = nil
var picks: [(Motif, UInt64)] = []
var sixteenBit = false
var it = args.makeIterator()
while let a = it.next() {
    switch a {
    case "--picks":
        picks = (it.next() ?? "").split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":")
            guard parts.count == 2, let m = Motif(rawValue: String(parts[0])), let seed = UInt64(parts[1]) else { return nil }
            return (m, seed)
        }
    case "--16bit": sixteenBit = true
    case "--seeds": seeds = Int(it.next() ?? "4") ?? 4
    case "--width": width = Int(it.next() ?? "960") ?? 960
    case "--height": height = Int(it.next() ?? "540") ?? 540
    case "--motif": motifFilter = Motif(rawValue: it.next() ?? "")
    case "--palette": paletteFilter = Palette.named(it.next() ?? "")
    default: outDir = URL(fileURLWithPath: a)
    }
}

let renderer = try WallpaperRenderer()

if args.contains("--bench") {
    // GPU + readback time per motif at a Retina preview size, after warm-up.
    let w = 2400, h = 1350
    print(String(format: "%-10@ %8@ %8@   layers  aberr  relief  smears", "motif", "gpu ms", "cg ms"))
    for motif in Motif.allCases {
        let scene = Wallpaper.generate(motif, seed: 5, aspect: Double(w) / Double(h))
        _ = try renderer.renderTexture(scene, width: w, height: h)
        var gpu = 0.0, cg = 0.0
        for _ in 0..<5 {
            let t0 = Date()
            let tex = try renderer.renderTexture(scene, width: w, height: h)
            let t1 = Date()
            _ = try WallpaperRenderer.image(from: tex, bitDepth: .eight)
            let t2 = Date()
            gpu += t1.timeIntervalSince(t0); cg += t2.timeIntervalSince(t1)
        }
        let relief = scene.layers.filter { $0.relief.isActive }.count
        print(String(format: "%-10@ %8.2f %8.2f   %2d      %4.1f   %d       %d", motif.rawValue, gpu / 5 * 1000, cg / 5 * 1000,
                     scene.layers.count, scene.effects.aberration, relief, scene.effects.smears.count))
    }
    // Smear scaling: 400 strokes on the liquid scene.
    var heavy = Wallpaper.generate(.liquid, seed: 5, aspect: Double(w) / Double(h))
    heavy.effects.smears = (0..<400).map { i in Smear(position: [Double(i % 20) / 20, Double(i / 20) / 20], vector: [0.05, 0.02], radius: 0.2) }
    _ = try renderer.renderTexture(heavy, width: w, height: h)      // builds the map
    let t0 = Date()
    for _ in 0..<5 { _ = try renderer.renderTexture(heavy, width: w, height: h) }
    print(String(format: "liquid + 400 smears (map cached): %.2f ms", Date().timeIntervalSince(t0) / 5 * 1000))
    heavy.effects.smears.append(Smear(position: [0.5, 0.5], vector: [0.05, 0.02], radius: 0.2))
    let t1 = Date()
    _ = try renderer.renderTexture(heavy, width: w, height: h)
    print(String(format: "…plus one appended stroke: %.2f ms", Date().timeIntervalSince(t1) * 1000))
    // CPU-side packing cost.
    let t2 = Date()
    for _ in 0..<100 { _ = GPUScene(heavy, width: w, height: h, ditherStep: 1 / 255) }
    print(String(format: "GPUScene packing: %.3f ms", Date().timeIntervalSince(t2) / 100 * 1000))
    exit(0)
}

if !picks.isEmpty {
    // Explicit seeds: one file each, numbered in the order given.
    let start = Date()
    for (i, (motif, seed)) in picks.enumerated() {
        let w = Wallpaper.generate(motif, palette: paletteFilter, seed: seed, aspect: Double(width) / Double(height))
        let image = try renderer.render(w, width: width, height: height,
                                        options: .init(bitDepth: sixteenBit ? .sixteen : .eight))
        let palette = w.title.split(separator: "·").dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "palette"
        let slug = palette.lowercased().replacingOccurrences(of: " ", with: "-")
        let name = String(format: "%02d-%@-%@-%llu.png", i + 1, motif.rawValue, slug, seed)
        try ImageExport.write(image, to: outDir.appendingPathComponent(name), format: .png)
        print("wrote \(name)  —  \(w.title)")
    }
    print(String(format: "rendered %d images at %dx%d in %.2fs", picks.count, width, height, Date().timeIntervalSince(start)))
    exit(0)
}

let motifs = motifFilter.map { [$0] } ?? Motif.allCases
var tiles: [(String, CGImage)] = []
let start = Date()
for motif in motifs {
    let motifIndex = Motif.allCases.firstIndex(of: motif) ?? 0
    for s in 1...seeds {
        let seed = UInt64(s) &* 7919 &+ UInt64(motifIndex * 1000)
        let w = Wallpaper.generate(motif, palette: paletteFilter, seed: seed, aspect: Double(width) / Double(height))
        let image = try renderer.render(w, width: width, height: height)
        let name = "\(motif.rawValue)-\(s).png"
        try ImageExport.write(image, to: outDir.appendingPathComponent(name), format: .png)
        tiles.append((w.title, image))
        print("wrote \(name)  —  \(w.title)")
    }
}
print(String(format: "rendered %d images in %.2fs", tiles.count, Date().timeIntervalSince(start)))

// Contact sheet
let cols = seeds
let rows = (tiles.count + cols - 1) / cols
let tw = 480, th = tw * height / width, gap = 12
let sheetW = cols * tw + (cols + 1) * gap, sheetH = rows * th + (rows + 1) * gap
if let ctx = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
    ctx.setFillColor(CGColor(gray: 0.96, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
    for (i, (_, img)) in tiles.enumerated() {
        let c = i % cols, r = i / cols
        let x = gap + c * (tw + gap)
        let y = sheetH - (gap + (r + 1) * th + r * gap)
        ctx.draw(img, in: CGRect(x: x, y: y, width: tw, height: th))
    }
    if let sheet = ctx.makeImage() {
        try ImageExport.write(sheet, to: outDir.appendingPathComponent("contact-sheet.png"), format: .png)
        print("wrote contact-sheet.png")
    }
}
