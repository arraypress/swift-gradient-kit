//
//  LayerPresets.swift
//  GradientKit
//
//  Starter layers for editors: one per shape kind, dressed in a palette so a
//  freshly added layer already belongs to the scene.
//

import Foundation

public extension Layer {
    /// A sensible, palette-matched starting layer of the given kind, placed
    /// at `position` (normalised canvas coordinates).
    static func starter(_ kind: Shape.Kind, palette: Palette?, at position: Vec2 = [0.5, 0.5]) -> Layer {
        let p = palette ?? .eclipse
        let accent = p.accent, highlight = p.highlight, secondary = p.secondary, deep = p.deep, base = p.base
        let fadeOut = accent.with(alpha: 0)
        switch kind {
        case .circle:
            return Layer(name: "Glow", shape: .circle(center: position, radius: 0.25), spread: 0.3,
                         ramp: [RampStop(-1, highlight), RampStop(-0.1, highlight), RampStop(0.2, accent), RampStop(1.2, fadeOut)],
                         lighting: Lighting(angle: -90, amount: 0.3))
        case .ellipse:
            return Layer(name: "Wash", shape: .ellipse(center: position, radii: [0.45, 0.25], rotation: -20), spread: 0.45,
                         ramp: [RampStop(-0.5, secondary), RampStop(0, secondary), RampStop(1, secondary.with(alpha: 0))],
                         opacity: 0.85, distortion: Distortion(amount: 0.06, scale: 1.4, octaves: 3))
        case .line:
            return Layer(name: "Seam", shape: .line(through: position, angle: -135, bend: 0.08), spread: 0.45,
                         ramp: [RampStop(-1, deep), RampStop(-0.4, deep), RampStop(0, accent.adjusted(lightness: -0.1)),
                                RampStop(0.18, accent), RampStop(0.9, fadeOut)])
        case .wave:
            return Layer(name: "Band", shape: .wave(through: position, angle: 90, amplitude: 0.1, wavelength: 1.6, phase: 0), spread: 0.3,
                         ramp: [RampStop(-1.2, fadeOut), RampStop(-0.4, accent), RampStop(0, accent), RampStop(0.4, secondary), RampStop(1, secondary.with(alpha: 0))],
                         blend: .screen, opacity: 0.85)
        case .ring:
            return Layer(name: "Halo", shape: .ring(center: position, radius: 0.28, thickness: 0.03), spread: 0.14,
                         ramp: [RampStop(-1, highlight.mixed(with: accent, 0.4)), RampStop(0, accent), RampStop(1, fadeOut)],
                         blend: .screen, lighting: Lighting(angle: 135, amount: 0.85))
        case .crescent:
            return Layer(name: "Arch", shape: .crescent(center: position, radius: 0.4, cutCenter: [position.x, position.y + 0.16], cutRadius: 0.42),
                         spread: 0.28,
                         ramp: [RampStop(-1, deep), RampStop(-0.45, deep), RampStop(0, deep.mixed(with: accent, 0.5)), RampStop(0.55, fadeOut)])
        case .polygon:
            return Layer(name: "Prism", shape: .polygon(center: position, radius: 0.3, sides: 6, rotation: 0, rounding: 0.03), spread: 0.25,
                         ramp: [RampStop(-1, deep), RampStop(-0.05, deep), RampStop(0.05, highlight), RampStop(0.25, accent), RampStop(1.2, fadeOut)],
                         lighting: Lighting(angle: -60, amount: 0.5))
        case .rect:
            return Layer(name: "Tile", shape: .rect(center: position, size: [0.5, 0.32], rotation: -12, cornerRadius: 0.08), spread: 0.2,
                         ramp: [RampStop(-1, secondary), RampStop(-0.1, secondary), RampStop(0.05, highlight), RampStop(0.8, fadeOut)],
                         opacity: 0.9)
        case .capsule:
            return Layer(name: "Beam", shape: .capsule(from: [position.x - 0.35, position.y + 0.2], to: [position.x + 0.35, position.y - 0.2], radius: 0.05),
                         spread: 0.3,
                         ramp: [RampStop(-1, highlight), RampStop(0, accent), RampStop(1, fadeOut)],
                         blend: .screen, opacity: 0.8)
        case .stripes:
            return Layer(name: "Ribbons", shape: .stripes(through: position, angle: 100, period: 0.22, width: 0.09, bend: 0.15), spread: 0.06,
                         ramp: [RampStop(-1, accent), RampStop(-0.3, accent), RampStop(0.3, secondary), RampStop(1.5, secondary.with(alpha: 0))],
                         opacity: 0.85, distortion: Distortion(amount: 0.08, scale: 1.2, octaves: 3))
        case .blob:
            return Layer(name: "Blob", shape: .blob(center: position, radius: 0.28, lobes: 5, wobble: 0.15, rotation: 0), spread: 0.35,
                         ramp: [RampStop(-0.8, accent), RampStop(0, accent), RampStop(1, fadeOut)],
                         blend: .screen, opacity: 0.9)
        case .noise:
            return Layer(name: "Nebula", shape: .noise(offset: position, scale: 1.4, octaves: 4), spread: 0.35,
                         ramp: [RampStop(-1, base.with(alpha: 0)), RampStop(-0.2, secondary.with(alpha: 0.6)), RampStop(0.3, accent), RampStop(0.9, highlight)],
                         blend: .screen, opacity: 0.8)
        case .chevrons:
            // Neutral grey with relief, overlay-blended: lit ridges that take the colour underneath.
            let grey = RGBA(r: 0.5, g: 0.5, b: 0.5)
            return Layer(name: "Chevrons", shape: .chevrons(through: position, angle: -35, period: 0.16, width: 0.16, amplitude: 0.05, wavelength: 0.5),
                         spread: 0.08, ramp: [RampStop(-1, grey), RampStop(0, grey)], blend: .overlay,
                         relief: Relief(height: 0.06, profile: .dome, lightAngle: -110, lightElevation: 40, gloss: 0.7, shininess: 32, ambient: 0.3))
        case .tiles:
            return Layer(name: "Keycaps", shape: .tiles(center: position, cell: [0.09, 0.09], inset: 0.006, cornerRadius: 0.016, rotation: -8, stagger: 0.5),
                         spread: 0.03, ramp: [RampStop(-1, base.adjusted(lightness: 0.08)), RampStop(0, base), RampStop(0.15, deep)],
                         relief: Relief(height: 0.02, profile: .bevel, lightAngle: -120, lightElevation: 50, gloss: 0.6, shininess: 40, ambient: 0.35))
        case .glyph:
            // One big emoji with a soft glow behind it.
            return Layer(name: "Emoji", shape: .glyph(text: "✨", center: position, size: 0.5, rotation: -8),
                         spread: 0.12, ramp: [RampStop(-1, highlight), RampStop(0, accent), RampStop(1.2, fadeOut)], glyphColor: 1)
        case .rays:
            return Layer(name: "Sunburst", shape: .rays(center: [position.x, position.y + 0.3], count: 18, rotation: 0, width: 0.5),
                         spread: 0.03, ramp: [RampStop(-1, accent.with(alpha: 0.35)), RampStop(0, accent.with(alpha: 0.25)), RampStop(1, accent.with(alpha: 0))],
                         blend: .screen, opacity: 0.9)
        case .glyphPattern:
            return Layer(name: "Emoji pattern",
                         shape: .glyphPattern(text: "🍒🍋🫧", center: position, cell: [0.22, 0.22], size: 0.12, rotation: -18,
                                              stagger: 0.5, jitter: 0.12, rotationJitter: 25, scaleJitter: 0.15),
                         spread: 0.01, ramp: [RampStop(-1, accent), RampStop(0, accent), RampStop(1, fadeOut)], glyphColor: 1)
        }
    }
}
