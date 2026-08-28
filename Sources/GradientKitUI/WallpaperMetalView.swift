//
//  WallpaperMetalView.swift
//  GradientKitUI
//
//  A zero-copy live preview: the compute kernel writes straight into the
//  MTKView's drawable. No readback, no CGImage, no CPU resampling — the
//  scene is rendered at exactly the view's pixel size and presented. Edits
//  cost one dispatch; even a 5K-backed view stays interactive.
//

import SwiftUI
import MetalKit
import GradientKit

#if canImport(AppKit)
import AppKit
public typealias PlatformViewRepresentable = NSViewRepresentable
#else
import UIKit
public typealias PlatformViewRepresentable = UIViewRepresentable
#endif

public struct WallpaperMetalView: PlatformViewRepresentable {
    public var wallpaper: Wallpaper

    public init(_ wallpaper: Wallpaper) {
        self.wallpaper = wallpaper
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    private func configure(_ view: MTKView, context: Context) {
        view.device = context.coordinator.renderer?.device
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false          // the kernel writes the drawable directly
        view.isPaused = true                  // draw only when the scene changes
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        #if canImport(AppKit)
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        #endif
        context.coordinator.wallpaper = wallpaper
    }

    #if canImport(AppKit)
    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        configure(view, context: context)
        return view
    }

    public func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.wallpaper = wallpaper
        view.needsDisplay = true
    }
    #else
    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        configure(view, context: context)
        return view
    }

    public func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.wallpaper = wallpaper
        view.setNeedsDisplay()
    }
    #endif

    @MainActor
    public final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: WallpaperRenderer? = try? WallpaperRenderer()
        var wallpaper: Wallpaper?

        public nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        public nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated {
                guard let renderer, let wallpaper,
                      let drawable = view.currentDrawable,
                      drawable.texture.width > 0, drawable.texture.height > 0,
                      let cmd = renderer.commandQueue.makeCommandBuffer()
                else { return }
                do {
                    try renderer.encode(wallpaper, into: drawable.texture, commandBuffer: cmd)
                    cmd.present(drawable)
                    cmd.commit()
                } catch {
                    // A failed encode leaves the previous frame on screen.
                }
            }
        }
    }
}
