//
//  WallpaperRenderer.swift
//  GradientKit
//
//  Metal compute renderer. One instance owns a device, a queue and the
//  compiled pipeline; `render` is safe to call from any thread (command
//  queues are thread-safe and every call gets its own buffers).
//

import Foundation
import CoreGraphics
import Metal

public enum RenderError: Error, LocalizedError, Sendable {
    case noMetalDevice
    case shaderCompilation(String)
    case kernelMissing
    case invalidSize
    case tooLarge(maxSide: Int)
    case gpuFailure(String)
    case imageCreation

    public var errorDescription: String? {
        switch self {
        case .noMetalDevice: "No Metal device is available."
        case let .shaderCompilation(msg): "Shader compilation failed: \(msg)"
        case .kernelMissing: "The wallpaper kernel was not found in the compiled library."
        case .invalidSize: "Width and height must be at least 1 pixel."
        case let .tooLarge(maxSide): "Each side must be at most \(maxSide) pixels on this GPU."
        case let .gpuFailure(msg): "GPU execution failed: \(msg)"
        case .imageCreation: "Could not wrap the rendered pixels in a CGImage."
        }
    }
}

public enum BitDepth: Int, Codable, Sendable, CaseIterable {
    case eight = 8
    case sixteen = 16
}

public final class WallpaperRenderer: @unchecked Sendable {
    public struct Options: Sendable, Equatable {
        public var bitDepth: BitDepth
        public init(bitDepth: BitDepth = .eight) { self.bitDepth = bitDepth }
    }

    public let device: MTLDevice
    /// Shared with views that present drawables, so a preview can encode the
    /// wallpaper and present in one command buffer.
    public let commandQueue: MTLCommandQueue
    private var queue: MTLCommandQueue { commandQueue }
    private let pipeline: MTLComputePipelineState
    private let rebuildPipeline: MTLComputePipelineState
    private let appendPipeline: MTLComputePipelineState
    private let atlas: GlyphAtlas
    private let smearField = SmearField()

    /// Largest texture side this device will allocate. Any size up to this
    /// (per side) renders; there is no other limit on resolution.
    public var maxSide: Int { device.supportsFamily(.apple3) || device.supportsFamily(.mac2) ? 16384 : 8192 }

    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw RenderError.noMetalDevice }
        self.commandQueue = queue
        self.atlas = GlyphAtlas(device: device)
        let options = MTLCompileOptions()
        options.mathMode = .fast
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: ShaderSource.source, options: options)
        } catch {
            throw RenderError.shaderCompilation(String(describing: error))
        }
        guard let fn = library.makeFunction(name: ShaderSource.kernelName),
              let rebuildFn = library.makeFunction(name: "gradientkit_smear_rebuild"),
              let appendFn = library.makeFunction(name: "gradientkit_smear_append")
        else { throw RenderError.kernelMissing }
        pipeline = try device.makeComputePipelineState(function: fn)
        rebuildPipeline = try device.makeComputePipelineState(function: rebuildFn)
        appendPipeline = try device.makeComputePipelineState(function: appendFn)
    }

    // MARK: Render

    public func render(_ wallpaper: Wallpaper, resolution: Resolution, options: Options = Options()) throws -> CGImage {
        try render(wallpaper, width: resolution.width, height: resolution.height, options: options)
    }

    public func render(_ wallpaper: Wallpaper, width: Int, height: Int, options: Options = Options()) throws -> CGImage {
        let texture = try renderTexture(wallpaper, width: width, height: height, options: options)
        return try WallpaperRenderer.image(from: texture, bitDepth: options.bitDepth)
    }

    /// Render into a texture you own (for MTKView or further GPU work).
    /// The texture is `rgba8Unorm` or `rgba16Unorm`, shared storage.
    public func renderTexture(_ wallpaper: Wallpaper, width: Int, height: Int, options: Options = Options()) throws -> MTLTexture {
        guard width >= 1, height >= 1 else { throw RenderError.invalidSize }
        guard width <= maxSide, height <= maxSide else { throw RenderError.tooLarge(maxSide: maxSide) }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: options.bitDepth == .eight ? .rgba8Unorm : .rgba16Unorm,
            width: width, height: height, mipmapped: false)
        desc.usage = [.shaderWrite, .shaderRead]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { throw RenderError.gpuFailure("texture allocation") }
        try render(wallpaper, into: texture)
        return texture
    }

    /// Render into an existing writable texture and wait for the GPU.
    public func render(_ wallpaper: Wallpaper, into texture: MTLTexture) throws {
        guard let cmd = queue.makeCommandBuffer() else { throw RenderError.gpuFailure("command buffer") }
        try encode(wallpaper, into: texture, commandBuffer: cmd)
        cmd.commit()
        cmd.waitUntilCompleted()
        if let error = cmd.error { throw RenderError.gpuFailure(String(describing: error)) }
    }

    /// Encode the wallpaper into `texture` on a command buffer you own —
    /// present a drawable on the same buffer for a zero-copy live preview.
    /// Any writable 8- or 16-bit-per-channel format works (`bgra8Unorm`
    /// drawables included); dithering adapts to the format's bit depth.
    public func encode(_ wallpaper: Wallpaper, into texture: MTLTexture, commandBuffer cmd: MTLCommandBuffer) throws {
        let sixteen = texture.pixelFormat == .rgba16Unorm || texture.pixelFormat == .rgba16Float
        let ditherStep: Float = sixteen ? 1 / 65535 : 1 / 255
        let scene = GPUScene(wallpaper, width: texture.width, height: texture.height, ditherStep: ditherStep)

        guard let layerBuf = device.makeBuffer(bytes: scene.layers, length: MemoryLayout<GPULayer>.stride * scene.layers.count),
              let stopBuf = device.makeBuffer(bytes: scene.stops, length: MemoryLayout<GPUStop>.stride * scene.stops.count),
              let smearBuf = device.makeBuffer(bytes: scene.smears, length: MemoryLayout<GPUSmear>.stride * scene.smears.count)
        else { throw RenderError.gpuFailure("buffer allocation") }

        guard let textures = atlas.textures(for: scene.glyphs), let sampler = atlas.sampler else {
            throw RenderError.gpuFailure("glyph atlas")
        }
        var globals = scene.globals
        // Liquify: keep a displacement map up to date (rebuild or append), then
        // the main pass samples it once per pixel.
        let map = try smearField.prepare(wallpaper.effects.smears, globals: &globals, scene: scene, width: texture.width, height: texture.height,
                                         device: device, commandBuffer: cmd, rebuild: rebuildPipeline, append: appendPipeline,
                                         smearBuffer: smearBuf, sampler: sampler)
        guard let enc = cmd.makeComputeCommandEncoder() else {
            throw RenderError.gpuFailure("command encoder")
        }
        enc.setComputePipelineState(pipeline)
        enc.setTexture(texture, index: 0)
        enc.setBytes(&globals, length: MemoryLayout<GPUGlobals>.stride, index: 0)
        enc.setBuffer(layerBuf, offset: 0, index: 1)
        enc.setBuffer(stopBuf, offset: 0, index: 2)
        enc.setBuffer(smearBuf, offset: 0, index: 3)
        enc.setTexture(textures.color, index: 1)
        enc.setTexture(textures.sdf, index: 2)
        enc.setTexture(map, index: 3)
        enc.setSamplerState(sampler, index: 0)

        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        let tg = MTLSize(width: w, height: h, depth: 1)
        let groups = MTLSize(width: (texture.width + w - 1) / w, height: (texture.height + h - 1) / h, depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
        enc.endEncoding()
    }

    // MARK: Readback

    public static func image(from texture: MTLTexture, bitDepth: BitDepth) throws -> CGImage {
        let width = texture.width, height = texture.height
        let bytesPerComponent = bitDepth == .eight ? 1 : 2
        let bytesPerPixel = 4 * bytesPerComponent
        let bytesPerRow = width * bytesPerPixel
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { buf in
            texture.getBytes(buf.baseAddress!, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: data as CFData) else { throw RenderError.imageCreation }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info: CGBitmapInfo = bitDepth == .eight
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            : CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        guard let image = CGImage(width: width, height: height,
                                  bitsPerComponent: bytesPerComponent * 8,
                                  bitsPerPixel: bytesPerPixel * 8,
                                  bytesPerRow: bytesPerRow,
                                  space: space, bitmapInfo: info, provider: provider,
                                  decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw RenderError.imageCreation }
        return image
    }
}


// MARK: - Smear displacement map

/// Two ping-pong `rg32Float` textures holding the accumulated liquify
/// displacement for the current stroke list and aspect ratio. Appending a
/// stroke composes it in one pass; anything else rebuilds from the list.
final class SmearField: @unchecked Sendable {
    private let lock = NSLock()
    private var textures: [MTLTexture] = []
    private var current = 0
    private var bakedHashes: [Int] = []
    private var aspectKey: Int = -1
    private var placeholder: MTLTexture?

    static let resolution = 2048

    func prepare(_ smears: [Smear], globals: inout GPUGlobals, scene: GPUScene, width: Int, height: Int,
                 device: MTLDevice, commandBuffer cmd: MTLCommandBuffer,
                 rebuild: MTLComputePipelineState, append: MTLComputePipelineState,
                 smearBuffer: MTLBuffer, sampler: MTLSamplerState) throws -> MTLTexture {
        lock.lock(); defer { lock.unlock() }
        let list = Array(smears.suffix(Effects.maxSmears)).filter { $0.radius > 0 && $0.strength != 0 }
        if list.isEmpty {
            globals.misc.z = 0
            if placeholder == nil {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: 4, height: 4, mipmapped: false)
                d.usage = [.shaderRead]; d.storageMode = .shared
                placeholder = device.makeTexture(descriptor: d)
                var zeros = [Float](repeating: 0, count: 4 * 4 * 2)
                placeholder?.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: &zeros, bytesPerRow: 4 * 8)
            }
            guard let placeholder else { throw RenderError.gpuFailure("smear placeholder") }
            return placeholder
        }
        let aspect = Double(width) / Double(height)
        let key = Int((aspect * 1000).rounded())
        let hashes = list.map(\.hashValue)
        let mapW = aspect >= 1 ? SmearField.resolution : Int(Double(SmearField.resolution) * aspect)
        let mapH = aspect >= 1 ? Int(Double(SmearField.resolution) / aspect) : SmearField.resolution

        func makeMap() -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: max(mapW, 1), height: max(mapH, 1), mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .private
            return device.makeTexture(descriptor: d)
        }
        if textures.count != 2 || textures[0].width != mapW || textures[0].height != mapH {
            guard let a = makeMap(), let b = makeMap() else { throw RenderError.gpuFailure("smear map") }
            textures = [a, b]; bakedHashes = []; aspectKey = -1; current = 0
        }

        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(width: (mapW + 15) / 16, height: (mapH + 15) / 16, depth: 1)
        var g = globals

        let canAppend = key == aspectKey && bakedHashes.count <= hashes.count && Array(hashes.prefix(bakedHashes.count)) == bakedHashes
        if !canAppend {
            // Full rebuild: one pass over every stroke, newest first (scene.smears is already in that order).
            g.misc.z = Float(scene.smears.count)
            guard let enc = cmd.makeComputeCommandEncoder() else { throw RenderError.gpuFailure("smear encoder") }
            enc.setComputePipelineState(rebuild)
            enc.setTexture(textures[current], index: 0)
            enc.setBytes(&g, length: MemoryLayout<GPUGlobals>.stride, index: 0)
            enc.setBuffer(smearBuffer, offset: 0, index: 3)
            enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
            enc.endEncoding()
            bakedHashes = hashes
            aspectKey = key
        } else if bakedHashes.count < hashes.count {
            // Append each new stroke sample, oldest new one first.
            for smear in list[bakedHashes.count...] {
                let p = SIMD2<Float>((Float(smear.position.x) - 0.5) * Float(width) / Float(min(width, height)),
                                     (Float(smear.position.y) - 0.5) * Float(height) / Float(min(width, height)))
                let kind: Float = smear.kind == .push ? 0 : (smear.kind == .swirl ? 1 : (smear.kind == .pinch ? 2 : 3))
                var one = GPUSmear(posVec: SIMD4<Float>(p.x, p.y, Float(smear.vector.x), Float(smear.vector.y)),
                                   params: SIMD4<Float>(Float(smear.radius), Float(smear.strength), kind, Float(1 + 3 * max(0, min(smear.softness, 1)))))
                guard let enc = cmd.makeComputeCommandEncoder() else { throw RenderError.gpuFailure("smear encoder") }
                enc.setComputePipelineState(append)
                enc.setTexture(textures[current], index: 0)
                enc.setTexture(textures[1 - current], index: 1)
                enc.setBytes(&g, length: MemoryLayout<GPUGlobals>.stride, index: 0)
                enc.setBytes(&one, length: MemoryLayout<GPUSmear>.stride, index: 3)
                enc.setSamplerState(sampler, index: 0)
                enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
                enc.endEncoding()
                current = 1 - current
            }
            bakedHashes = hashes
        }
        globals.misc.z = 1   // "map in use"
        return textures[current]
    }
}
