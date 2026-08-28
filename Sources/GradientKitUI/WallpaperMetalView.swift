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
    /// Drawable pixels per point relative to the display's own scale:
    /// 1 = native, 0.5 = quarter the pixels — pass 0.5 while the user is
    /// dragging and 1 when idle for a smooth-then-sharp preview.
    public var quality: Double

    public init(_ wallpaper: Wallpaper, quality: Double = 1) {
        self.wallpaper = wallpaper
        self.quality = quality
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    private func configure(_ view: ScaledMTKView, context: Context) {
        view.device = context.coordinator.renderer?.device
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false          // the kernel writes the drawable directly
        view.isPaused = true                  // draw only when the scene changes
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = false       // ScaledMTKView sizes the drawable itself
        #if canImport(AppKit)
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        #endif
        view.quality = CGFloat(quality)
        context.coordinator.wallpaper = wallpaper
    }

    #if canImport(AppKit)
    public func makeNSView(context: Context) -> ScaledMTKView {
        let view = ScaledMTKView()
        configure(view, context: context)
        return view
    }

    public func updateNSView(_ view: ScaledMTKView, context: Context) {
        context.coordinator.wallpaper = wallpaper
        view.quality = CGFloat(quality)
        view.needsDisplay = true
    }
    #else
    public func makeUIView(context: Context) -> ScaledMTKView {
        let view = ScaledMTKView()
        configure(view, context: context)
        return view
    }

    public func updateUIView(_ view: ScaledMTKView, context: Context) {
        context.coordinator.wallpaper = wallpaper
        view.quality = CGFloat(quality)
        view.setNeedsDisplay()
    }
    #endif

    /// An MTKView whose drawable is `quality` × the native pixel size.
    public final class ScaledMTKView: MTKView {
        public var quality: CGFloat = 1 {
            didSet { if quality != oldValue { updateDrawableSize() } }
        }

        private func updateDrawableSize() {
            #if canImport(AppKit)
            let scale = window?.backingScaleFactor ?? 2
            #else
            let scale = window?.screen.scale ?? traitCollection.displayScale
            #endif
            let q = max(0.2, min(quality, 1))
            let size = CGSize(width: max(1, (bounds.width * scale * q).rounded()), height: max(1, (bounds.height * scale * q).rounded()))
            if size != drawableSize { drawableSize = size }
        }

        #if canImport(AppKit)
        public override func layout() {
            super.layout()
            updateDrawableSize()
        }
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateDrawableSize()
        }
        #else
        public override func layoutSubviews() {
            super.layoutSubviews()
            updateDrawableSize()
        }
        #endif
    }

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
