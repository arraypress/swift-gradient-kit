//
//  WallpaperView.swift
//  GradientKitUI
//
//  A SwiftUI view that renders a `Wallpaper` at its own pixel size. Renders
//  happen off the main thread on a shared renderer; rapid edits are
//  coalesced (the latest scene wins) and the previous frame stays on screen
//  until the new one lands, so slider drags never flash.
//

import SwiftUI
import GradientKit

public struct WallpaperView: View {
    public var wallpaper: Wallpaper
    /// Cap on the longer rendered edge, in pixels. Keeps interactive edits
    /// cheap on 5K displays; pass `nil` for full-resolution previews.
    public var maxPixels: Int?

    @State private var image: CGImage?
    @State private var renderedSize: CGSize = .zero
    @Environment(\.displayScale) private var displayScale

    public init(_ wallpaper: Wallpaper, maxPixels: Int? = 2048) {
        self.wallpaper = wallpaper
        self.maxPixels = maxPixels
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Color.clear
                }
            }
            .task(id: RenderKey(wallpaper: wallpaper, size: geo.size, scale: displayScale, cap: maxPixels)) {
                await render(size: geo.size)
            }
        }
    }

    private func render(size: CGSize) async {
        guard size.width >= 1, size.height >= 1 else { return }
        var w = Int(size.width * displayScale), h = Int(size.height * displayScale)
        if let cap = maxPixels, max(w, h) > cap {
            let k = Double(cap) / Double(max(w, h))
            w = max(1, Int(Double(w) * k)); h = max(1, Int(Double(h) * k))
        }
        let scene = wallpaper
        let result = await SharedRenderer.render(scene, width: w, height: h)
        if !Task.isCancelled, let result {
            image = result
            renderedSize = CGSize(width: w, height: h)
        }
    }

    private struct RenderKey: Equatable {
        var wallpaper: Wallpaper
        var size: CGSize
        var scale: CGFloat
        var cap: Int?
    }
}

/// One renderer per process, serialised so a burst of edits never queues
/// more than one render behind the one in flight.
public actor SharedRenderer {
    public static let shared = SharedRenderer()

    private var renderer: WallpaperRenderer?
    private var failed = false

    private func make() -> WallpaperRenderer? {
        if let renderer { return renderer }
        if failed { return nil }
        do {
            let r = try WallpaperRenderer()
            renderer = r
            return r
        } catch {
            failed = true
            return nil
        }
    }

    public func render(_ wallpaper: Wallpaper, width: Int, height: Int,
                       options: WallpaperRenderer.Options = .init()) -> CGImage? {
        guard let r = make() else { return nil }
        return try? r.render(wallpaper, width: width, height: height, options: options)
    }

    public static func render(_ wallpaper: Wallpaper, width: Int, height: Int,
                              options: WallpaperRenderer.Options = .init()) async -> CGImage? {
        await shared.render(wallpaper, width: width, height: height, options: options)
    }
}
