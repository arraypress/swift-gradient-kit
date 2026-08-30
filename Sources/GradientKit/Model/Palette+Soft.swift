//
//  Palette+Soft.swift
//  GradientKit
//
//  The palettes that make a *field* read as a wallpaper rather than a
//  poster: several hues, all pastel, no accent shouting. Judged by eye on
//  rendered sheets — the neon curated set reads as illustration; these read
//  like a desktop.
//

public extension Palette {
    /// Pastel, multi-hue, low-contrast palettes for the field motifs.
    static let soft: [Palette] = [
        Palette(name: "Pastel", base: RGBA(hex: "#E6D6F5")!, baseAlt: RGBA(hex: "#CFE4F8")!, accent: RGBA(hex: "#F4B9C9")!,
                secondary: RGBA(hex: "#B9E4DA")!, highlight: RGBA(hex: "#FFF7EC")!, deep: RGBA(hex: "#8A93C4")!, mood: .light),
        Palette(name: "Dawn", base: RGBA(hex: "#F6DCD0")!, baseAlt: RGBA(hex: "#F0C9D6")!, accent: RGBA(hex: "#C9B6F0")!,
                secondary: RGBA(hex: "#FBE6C2")!, highlight: RGBA(hex: "#FFFBF5")!, deep: RGBA(hex: "#9C86B8")!, mood: .light),
        Palette(name: "Sea Mist", base: RGBA(hex: "#D3EAF2")!, baseAlt: RGBA(hex: "#DDEFE3")!, accent: RGBA(hex: "#B7CDF2")!,
                secondary: RGBA(hex: "#EBD9F0")!, highlight: RGBA(hex: "#FFFFFF")!, deep: RGBA(hex: "#7F97B3")!, mood: .light),
        Palette(name: "Lilac Hour", base: RGBA(hex: "#DED2F2")!, baseAlt: RGBA(hex: "#C8D6F5")!, accent: RGBA(hex: "#F1C4D8")!,
                secondary: RGBA(hex: "#D4E8F2")!, highlight: RGBA(hex: "#FBF6FF")!, deep: RGBA(hex: "#8E88B8")!, mood: .light),
        Palette(name: "Dusk", base: RGBA(hex: "#3B3F66")!, baseAlt: RGBA(hex: "#5A5487")!, accent: RGBA(hex: "#C89BB6")!,
                secondary: RGBA(hex: "#6E88A8")!, highlight: RGBA(hex: "#E9D8E6")!, deep: RGBA(hex: "#1E2038")!, mood: .dark),
    ]

    /// Whether this palette is one of the soft set.
    var isSoft: Bool { Palette.soft.contains { $0.name == name } }
}
