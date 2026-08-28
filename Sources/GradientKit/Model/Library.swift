//
//  Library.swift
//  GradientKit
//
//  User-extensible palettes and gradients: built-in defaults plus a folder
//  of JSON files that can be edited by hand, dropped in from elsewhere and
//  reloaded at any time. Headless — the app layers file pickers on top.
//

import Foundation

/// A named, reusable ramp — the colour side of a background or a layer,
/// independent of shape. `positions` are 0...1 for backgrounds; layers map
/// them into their signed-distance domain with `Layer.apply(_:)`.
public struct GradientPreset: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var stops: [RampStop]
    /// Hard bands instead of a blend (colour ladders, retro stripes).
    public var stepped: Bool
    /// Suggested direction for a background, degrees.
    public var angle: Double

    public var id: String { name }

    public init(name: String, stops: [RampStop], stepped: Bool = false, angle: Double = 90) {
        self.name = name; self.stops = stops; self.stepped = stepped; self.angle = angle
    }

    /// Evenly spaced colours.
    public init(name: String, colors: [RGBA], stepped: Bool = false, angle: Double = 90) {
        self.init(name: name, stops: RampStop.spread(colors, from: 0, to: 1), stepped: stepped, angle: angle)
    }

    /// A flat band per colour (retro stripes): the first and last colours
    /// extend to the edges; the ones between are `bandWidth` wide.
    public init(name: String, bands: [RGBA], bandWidth: Double, angle: Double = -30) {
        var stops: [RampStop] = []
        let inner = max(bands.count - 1, 1)
        let start = 0.5 - bandWidth * Double(inner) / 2
        for (i, c) in bands.enumerated() {
            stops.append(RampStop(i == 0 ? 0 : start + bandWidth * Double(i - 1), c))
        }
        self.init(name: name, stops: stops, stepped: true, angle: angle)
    }

    public var colors: [RGBA] { stops.map(\.color) }

    public func background(kind: Background.Kind = .linear) -> Background {
        Background(kind: kind, stops: stops, angle: angle, stepped: stepped)
    }

    // MARK: Defaults

    private static func hex(_ s: String) -> RGBA { RGBA(hex: s)! }

    public static let defaults: [GradientPreset] = [
        GradientPreset(name: "Rose Ladder", colors: [hex("#F98BAF"), hex("#B5407C"), hex("#4A1A45")]),
        GradientPreset(name: "Lagoon Ladder", colors: [hex("#B2D3C0"), hex("#1B9DA6"), hex("#173A5F")]),
        GradientPreset(name: "Graphite Ladder", colors: [hex("#E6E6E6"), hex("#7A7A7A"), hex("#1A1A1A")]),
        GradientPreset(name: "Amber Ladder", colors: [hex("#FFF3C4"), hex("#F09A1A"), hex("#5F2E06")]),
        GradientPreset(name: "Ultraviolet Ladder", colors: [hex("#D9C7FF"), hex("#6B1BEE"), hex("#150A3A")]),
        GradientPreset(name: "Sky Ladder", colors: [hex("#E3F4FF"), hex("#1F7DE8"), hex("#031A46")]),
        GradientPreset(name: "Sunset Ladder", colors: [hex("#F5B41B"), hex("#E85A1F"), hex("#C51621")]),
        GradientPreset(name: "Ember Ladder", colors: [hex("#F3A64B"), hex("#B54A19"), hex("#1E1206")]),
        GradientPreset(name: "Retro Teal Sunset", bands: [hex("#0B3A44"), hex("#0E6E6A"), hex("#F1E3A8"), hex("#F5A15B"), hex("#EE7B3A"), hex("#C43C3C")], bandWidth: 0.05),
        GradientPreset(name: "Retro Prism", bands: [hex("#7BA03A"), hex("#3A7D4E"), hex("#3B8BD0"), hex("#3F5B9B"), hex("#C4548C"), hex("#E9683B"), hex("#F7A83C")], bandWidth: 0.045),
        GradientPreset(name: "Retro Spectrum", bands: [hex("#050505"), hex("#1C6BE0"), hex("#2FA84A"), hex("#F5C11C"), hex("#F26A1B"), hex("#050505")], bandWidth: 0.04),
        GradientPreset(name: "Retro Ice", bands: [hex("#0A1F5C"), hex("#1B71C9"), hex("#22A6D8"), hex("#8EDCEF"), hex("#CFF3FB")], bandWidth: 0.05),
        GradientPreset(name: "Retro Cream", bands: [hex("#8B4513"), hex("#1C3A3D"), hex("#4E6B5D"), hex("#A8B49A"), hex("#ECE9D3")], bandWidth: 0.05),
        GradientPreset(name: "Retro Orchid", bands: [hex("#1B1857"), hex("#6E2BB5"), hex("#C25FD8"), hex("#F49BE9"), hex("#FBE7FB")], bandWidth: 0.045),
        GradientPreset(name: "Prism Sweep", colors: [hex("#FF9A1F"), hex("#FF3E6C"), hex("#B03BEE"), hex("#2D8BFF"), hex("#14C7B5"), hex("#0E5F3A")], angle: 20),
        GradientPreset(name: "Dusk Sweep", colors: [hex("#FF7A18"), hex("#C63A5B"), hex("#3B1C5C"), hex("#0B0A1A")], angle: 120),
        GradientPreset(name: "Slate Sweep", colors: [hex("#9CA3AF"), hex("#4B5563"), hex("#111827")], angle: 135),
    ]
}

public extension Layer {
    /// Dress the layer in a gradient preset: colours are laid across the
    /// ramp from one spread inside the edge to one spread outside, keeping
    /// the last colour's alpha (so a preset ending in transparency still fades).
    mutating func apply(_ preset: GradientPreset, from inner: Double = -1, to outer: Double = 1) {
        ramp = preset.stops.map { RampStop(inner + (outer - inner) * $0.position, $0.color) }
        stepped = preset.stepped
    }
}

// MARK: - Stores

/// A file-backed collection: built-in defaults plus everything in a folder
/// of JSON files, reloadable. Items whose names collide override defaults.
public struct PresetStore<Item: Codable & Identifiable & Sendable>: Sendable where Item.ID == String {
    public let directory: URL?
    public let defaults: [Item]
    public private(set) var custom: [Item] = []
    /// Files that failed to decode on the last load, with their errors.
    public private(set) var problems: [(file: String, error: String)] = []

    public init(defaults: [Item], directory: URL?) {
        self.defaults = defaults
        self.directory = directory
        reload()
    }

    /// Defaults first (unless overridden by a custom item of the same name), then custom.
    public var all: [Item] {
        let customNames = Set(custom.map(\.id))
        return defaults.filter { !customNames.contains($0.id) } + custom
    }

    public func item(named name: String) -> Item? {
        all.first { $0.id.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func isCustom(_ item: Item) -> Bool { custom.contains { $0.id == item.id } }

    /// Re-read the folder. Safe to call any time; the defaults never change.
    public mutating func reload() {
        custom = []
        problems = []
        guard let directory else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        for file in files.filter({ $0.pathExtension.lowercased() == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let data = try Data(contentsOf: file)
                if let one = try? decoder.decode(Item.self, from: data) {
                    custom.append(one)
                } else {
                    custom.append(contentsOf: try decoder.decode([Item].self, from: data))
                }
            } catch {
                problems.append((file.lastPathComponent, error.localizedDescription))
            }
        }
    }

    /// Write one item as `<name>.json` in the folder (creating it) and reload.
    @discardableResult
    public mutating func save(_ item: Item) throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(PresetStore.fileName(for: item.id))
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(item).write(to: url)
        reload()
        return url
    }

    /// Delete the file that provides a custom item (defaults cannot be deleted).
    public mutating func delete(_ item: Item) throws {
        guard let directory, isCustom(item) else { return }
        let url = directory.appendingPathComponent(PresetStore.fileName(for: item.id))
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        } else {
            // Provided by a multi-item file: rewrite that file without it.
            for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension.lowercased() == "json" {
                if var items = try? JSONDecoder().decode([Item].self, from: Data(contentsOf: file)),
                   items.contains(where: { $0.id == item.id }) {
                    items.removeAll { $0.id == item.id }
                    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try enc.encode(items).write(to: file)
                }
            }
        }
        reload()
    }

    /// Copy an external JSON file (one item or an array) into the folder.
    public mutating func importFile(at url: URL) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let items: [Item]
        if let one = try? decoder.decode(Item.self, from: data) { items = [one] } else { items = try decoder.decode([Item].self, from: data) }
        for item in items { try save(item) }
    }

    static func fileName(for name: String) -> String {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return (slug.isEmpty ? "untitled" : slug) + ".json"
    }
}

public typealias PaletteStore = PresetStore<Palette>
public typealias GradientStore = PresetStore<GradientPreset>

public extension PaletteStore {
    /// Curated palettes plus `directory`.
    static func standard(directory: URL?) -> PaletteStore { PaletteStore(defaults: Palette.curated, directory: directory) }
}

public extension GradientStore {
    static func standard(directory: URL?) -> GradientStore { GradientStore(defaults: GradientPreset.defaults, directory: directory) }
}

public extension URL {
    /// `~/Library/Application Support/<app>/<folder>` — the conventional home
    /// for a store's folder.
    static func applicationSupport(app: String, folder: String) -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        return base.appendingPathComponent(app, isDirectory: true).appendingPathComponent(folder, isDirectory: true)
    }
}
