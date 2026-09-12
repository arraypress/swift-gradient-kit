//
//  Palette+Spectra.swift
//  GradientKit
//
//  Five-colour ramps that run pale → warm → saturated → deep, as palettes.
//
//  These arrived as gradient presets — a separate concept from a palette,
//  which turned out to be one concept too many: with no layer stack there
//  is nothing a bare ramp can dress that a palette cannot. The colours were
//  worth keeping, so they moved here and the concept went.
//
//  PROVENANCE: colour relationships taken by eye from the reference ramps
//  on feralui.dev. Values are data; the names here are ours.
//

import Foundation

public extension Palette {
    /// Build a palette from a run of five colours.
    ///
    /// Roles are assigned from the COLOURS, not from their position in the
    /// run. Most of these ramps do go pale → deep, but not all — `Layered`
    /// ends on a bright mint, so taking "last = darkest" gave it a highlight
    /// darker than its accent. Sorting by luminance and picking the accent
    /// by chroma holds for every set without special cases.
    static func spectrum(_ name: String, _ hexes: String...) -> Palette {
        let colors = hexes.compactMap { RGBA(hex: $0) }
        precondition(colors.count >= 4, "\(name) needs at least four colours")
        let byLight = colors.sorted { $0.luminance > $1.luminance }
        let highlight = byLight.first!
        let deep = byLight.last!
        // The middle of the run, most chromatic first: the accent is the one
        // the eye goes to, which is a question of saturation, not lightness.
        let middle = byLight.dropFirst().dropLast().sorted { $0.oklch.c > $1.oklch.c }
        let accent = middle.first ?? highlight
        let secondary = middle.count > 1 ? middle[1] : accent
        let base = middle.count > 2 ? middle[2] : secondary
        return Palette(
            name: name,
            base: base,
            baseAlt: base.mixed(with: highlight, 0.45),
            accent: accent,
            secondary: secondary,
            highlight: highlight,
            deep: deep,
            // Light when there is a genuine near-white to build on.
            mood: highlight.luminance > 0.6 ? .light : .dark)
    }

    /// Pale-to-deep five-colour sets.
    static let spectra: [Palette] = [
        .spectrum("Citrus Rise", "#FFFDF7", "#FFE27A", "#FF9A4A", "#FF4F63", "#8C3DEB"),
        .spectrum("Meadow Signal", "#FFFEFB", "#E9FF95", "#59E39C", "#1EC9D8", "#2874F0"),
        .spectrum("Apricot Violet", "#FFF9F4", "#FFD99A", "#FF8E62", "#F44D8A", "#7C45D9"),
        .spectrum("Lotus", "#FCFFF6", "#DDF174", "#64D890", "#2FBAC7", "#245A9D"),
        .spectrum("Daylight Blue", "#FAFBFF", "#BDE6FF", "#5AB8F4", "#6269E8", "#CE72D8"),
        .spectrum("Sequence", "#FFF8EE", "#FFE08A", "#FF9F55", "#ED5D73", "#6D315F"),
        .spectrum("Wisteria", "#FCF9FF", "#E9C7FF", "#B875E8", "#665ED2", "#263A82"),
        .spectrum("Layered", "#FFFDF7", "#FFD466", "#FF647D", "#9A6BFF", "#46E1C3"),
        .spectrum("Layered Dark", "#15131B", "#FFD466", "#FF647D", "#9A6BFF", "#46E1C3"),
        .spectrum("Field Green", "#F3FBF2", "#9EE89A", "#3FBF63", "#007A33", "#044D22"),
        .spectrum("Warm Clay", "#FBF0DC", "#FFEBB0", "#FFC855", "#F28A30", "#D9503B"),
        .spectrum("Rosewater", "#FBEEF1", "#FFD6C2", "#F79C97", "#E1679A", "#7E3D9A"),
        .spectrum("Coral Plum", "#FFF6F1", "#FFDBC0", "#FF9E7E", "#EE5A82", "#873DBC"),
        .spectrum("Acid Spring", "#F8FFE8", "#E8FF45", "#67F08D", "#14C7B8", "#1945B8"),
        .spectrum("Marmalade", "#FFF7ED", "#FFC061", "#FF714B", "#C62E65", "#4B225E"),
        .spectrum("Glacier", "#F7FCFF", "#D8F5FF", "#7DD7F4", "#6394E8", "#8B62D6"),
        .spectrum("Newsprint", "#F7F5F0", "#D9D6CF", "#A8A49D", "#625F5B", "#211F1D"),
    ]
}
