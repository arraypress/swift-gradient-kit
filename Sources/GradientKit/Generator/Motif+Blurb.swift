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
    /// soft, and anything with relief, tiling or glyphs reads as a demo of
    /// the engine. What a client should offer first; the rest are one step
    /// away.
    static let featured: [Motif] = [.holo, .mesh, .aurora, .nebula, .classic]

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
        case .topo: "Contour lines of a noise field"
        case .ribbons: "Flowing stripes bent by noise"
        case .prism: "A lit polygon rim on dark"
        case .nebula: "Clouds of colour on dark"
        case .holo: "Hue sweeping across a soft edge"
        case .ladder: "Flat bands stepping through a ramp"
        case .retro: "Hard diagonal stripes, two fields"
        case .chevron: "Lit zigzag ridges over colour"
        case .keycaps: "Bevelled tiles under a light sweep"
        case .liquid: "A glossy 3-D blob with folds"
        case .classic: "Plain diagonal gradient with grain"
        case .glow: "A planet's edge over a dark sky"
        case .emoji: "Emoji scattered over a gradient"
        case .symbols: "SF Symbols as a texture"
        case .ripples: "Concentric rings, hue turning outward"
        case .beams: "Light leaks across a dark ground"
        case .bokeh: "Out-of-focus discs of light"
        case .lava: "Glossy blobs on dark"
        case .rays: "A sunburst behind a glow"
        case .mountains: "Ridges receding into haze"
        case .dunes: "Smooth stacked dunes"
        case .sunset: "A striped sun over a gradient sky"
        case .saturn: "A ringed planet"
        case .sea: "Rolling swells with lit crests"
        case .blinds: "Lit slats"
        case .marble: "Veined stone"
        case .terrazzo: "Scattered chips on a light ground"
        case .grid: "A fine grid over a gradient"
        }
    }
}
