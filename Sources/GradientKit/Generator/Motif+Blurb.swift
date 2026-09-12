//
//  Motif+Blurb.swift
//  GradientKit
//
//  One line per motif, for anything that lists them — a gallery, a menu, a
//  command's help. Lifted here from the Halo studio so the kit's clients
//  share one description instead of each writing its own.
//

public extension Motif {
    /// The motifs that read as wallpapers: colour FIELDS with nothing drawn
    /// on them — warped gradients, hue sweeps, noise clouds, under grain.
    /// Judged by eye on rendered sheets: anything with a discrete shape in
    /// it (a rim, a disc, an arch, a dot) reads as an illustration, however
    /// soft. What a client should offer first; the rest are one step away.
    static let featured: [Motif] = [.flow, .smesh, .holo, .mesh, .aurora, .nebula, .silk, .classic]

    /// Whether this motif is in the featured set.
    var isFeatured: Bool { Motif.featured.contains(self) }

    /// What this motif looks like, in a sentence.
    var blurb: String {
        switch self {
        case .eclipse: "Black disc, bright rim, dark ground"
        case .orb: "A luminous sphere in its own glow"
        case .horizon: "Pastel sky cut by a glowing seam"
        case .hill: "A warm-rimmed hill through two tones"
        case .crescent: "Light blobs and a soft dark arch"
        case .halo: "A dim moon and a one-sided ring"
        case .aurora: "Warped curtains of colour"
        case .mesh: "A warped colour grid"
        case .flow: "Colour points blended into a soft field"
        case .smesh: "Tight pools of colour, deep valleys"
        case .silk: "Satin folds with the hue turning"
        case .angular: "Colour swept around a centre"
        case .beehive: "A lit honeycomb over a colour field"
        case .orbs: "A grid of soft spheres"
        case .bokeh: "Out-of-focus discs of light"
        case .topo: "Contour lines of a noise field"
        case .ribbons: "Flowing stripes bent by noise"
        case .nebula: "Clouds of colour on dark"
        case .holo: "Hue sweeping across a soft edge"
        case .ladder: "Flat bands stepping through a ramp"
        case .retro: "Hard diagonal stripes, two fields"
        case .classic: "Plain diagonal gradient with grain"
        case .glow: "A planet's edge over a dark sky"
        case .beams: "Light leaks across a dark ground"
        case .rays: "A sunburst behind a glow"
        case .mountains: "Ridges receding into haze"
        case .dunes: "Smooth stacked dunes"
        case .sunset: "A striped sun over a gradient sky"
        }
    }
}
