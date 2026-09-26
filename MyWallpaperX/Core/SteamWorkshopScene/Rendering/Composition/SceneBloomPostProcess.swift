import Metal

/// Scene-level bloom post-process configuration parsed from authored
/// `general` bloom keys (user-directed 2026-09-26; reference: the
/// MirageWallpaper `__bloom` LDR post-process chain).
nonisolated struct SceneBloomConfiguration: Codable, Equatable, Sendable {
    let enabled: Bool
    let strength: Float
    let threshold: Float
    let tint: SIMD3<Float>

    nonisolated static let disabled = SceneBloomConfiguration(
        enabled: false, strength: 1, threshold: 0.65, tint: SIMD3(1, 1, 1)
    )
}

/// Encodes the bloom chain over a completed scene composite: bright-pass
/// downsample to quarter resolution, separable 13-tap gaussian blur (8-texel
/// spread, reference weights), then an additive full-resolution combine
/// blitted back into the source. All shaders are fixed product code in
/// `SceneBloomPostProcess.metal`; authored constants ride per-pass buffers.
/// Any pipeline or texture failure skips the chain silently — bloom is an
/// enhancement layer, never a frame-fatal effect.
final class SceneBloomPostProcess {
    private var device: MTLDevice?
    private var brightPipeline: MTLRenderPipelineState?
    private var blurPipeline: MTLRenderPipelineState?
    private var combinePipeline: MTLRenderPipelineState?
    private var pipelineFailureLogged = false
    private var cachedTexturesBySize: [SIMD2<Int>: (mip1: MTLTexture, mip2: MTLTexture)] = [:]

    init() {}

    /// Raster pixel format of every intermediate target; the chain assumes
    /// the drawable is 8-bit UNorm like the rest of the compositor.
    private static let pixelFormat = MTLPixelFormat.bgra8Unorm

    private func makePipelines(on device: MTLDevice) -> Bool {
        guard brightPipeline == nil else { return true }
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "sceneBloomVertex"),
              let bright = library.makeFunction(name: "sceneBloomBrightFragment"),
              let blur = library.makeFunction(name: "sceneBloomBlurFragment"),
              let combine = library.makeFunction(name: "sceneBloomCombineFragment") else {
            if !pipelineFailureLogged {
                pipelineFailureLogged = true
                NSLog("MWX Scene bloom: default library functions unavailable")
            }
            return false
        }
        func descriptor(
            _ fragment: MTLFunction, additive: Bool = false
        ) -> MTLRenderPipelineDescriptor {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = additive
            if additive {
                descriptor.colorAttachments[0].rgbBlendOperation = .add
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
                descriptor.colorAttachments[0].alphaBlendOperation = .add
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
            }
            return descriptor
        }
        do {
            brightPipeline = try device.makeRenderPipelineState(
                descriptor: descriptor(bright)
            )
            blurPipeline = try device.makeRenderPipelineState(
                descriptor: descriptor(blur)
            )
            combinePipeline = try device.makeRenderPipelineState(
                descriptor: descriptor(combine, additive: true)
            )
        } catch {
            if !pipelineFailureLogged {
                pipelineFailureLogged = true
                NSLog(
                    "MWX Scene bloom: pipeline state rejected: %@",
                    String(describing: error)
                )
            }
            return false
        }
        return true
    }

    private func intermediateTargets(
        on device: MTLDevice,
        matching source: MTLTexture
    ) -> (mip1: MTLTexture, mip2: MTLTexture)? {
        let key = SIMD2(Int(source.width), Int(source.height))
        if let cached = cachedTexturesBySize[key] {
            return cached
        }
        func makeTexture(width: Int, height: Int) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: Self.pixelFormat,
                width: max(1, width),
                height: max(1, height),
                mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            return device.makeTexture(descriptor: descriptor)
        }
        let quarter = SIMD2(
            max(1, source.width / 4), max(1, source.height / 4)
        )
        let sixteenth = SIMD2(
            max(1, quarter.x / 4), max(1, quarter.y / 4)
        )
        guard let mip1 = makeTexture(width: quarter.x, height: quarter.y),
              let mip2 = makeTexture(width: sixteenth.x, height: sixteenth.y)
        else {
            if !pipelineFailureLogged {
                pipelineFailureLogged = true
                NSLog("MWX Scene bloom: intermediate texture allocation failed")
            }
            return nil
        }
        let entry = (mip1: mip1, mip2: mip2)
        cachedTexturesBySize = [key: entry]
        return entry
    }

    private struct BrightUniforms {
        var strength: Float
        var threshold: Float
        var tint: SIMD3<Float>
    }

    private struct BlurUniforms {
        var direction: SIMD2<Float>
        var stepUV: SIMD2<Float>
    }

    /// Fixed reference tap step (g_TexelSize 1080p compile-time constant ×8).
    private static let blurStep = SIMD2<Float>(Float(8.0 / 1920.0), Float(8.0 / 1080.0))

    private func encodeQuad(
        _ pipeline: MTLRenderPipelineState,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        bind: (MTLRenderCommandEncoder) -> Void
    ) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setTriangleFillMode(.fill)
        bind(encoder)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    /// Runs the chain over `source` (the completed scene composite) and blits
    /// the combined result back into it. Returns false when the chain was
    /// skipped (never frame-fatal).
    @discardableResult
    func encode(
        configuration: SceneBloomConfiguration,
        source: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard configuration.enabled,
              source.pixelFormat == Self.pixelFormat,
              self.device == nil || self.device === source.device else {
            return false
        }
        self.device = source.device
        guard makePipelines(on: source.device),
              let pipelines = (
                bright: brightPipeline,
                blur: blurPipeline,
                combine: combinePipeline
            ) as (bright: MTLRenderPipelineState?, blur: MTLRenderPipelineState?, combine: MTLRenderPipelineState?)?,
              let bright = pipelines.bright,
              let blur = pipelines.blur,
              let combine = pipelines.combine,
              let targets = intermediateTargets(on: source.device, matching: source)
        else { return false }

        var brightUniforms = BrightUniforms(
            strength: configuration.strength,
            threshold: configuration.threshold,
            tint: configuration.tint
        )
        encodeQuad(bright, target: targets.mip1, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(
                &brightUniforms, length: MemoryLayout<BrightUniforms>.stride, index: 0
            )
        }

        var blurVertical = BlurUniforms(
            direction: SIMD2(0, 1),
            stepUV: Self.blurStep
        )
        encodeQuad(blur, target: targets.mip2, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(targets.mip1, index: 0)
            encoder.setFragmentBytes(
                &blurVertical, length: MemoryLayout<BlurUniforms>.stride, index: 0
            )
        }

        var blurHorizontal = BlurUniforms(
            direction: SIMD2(1, 0),
            stepUV: Self.blurStep
        )
        encodeQuad(blur, target: targets.mip1, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(targets.mip2, index: 0)
            encoder.setFragmentBytes(
                &blurHorizontal, length: MemoryLayout<BlurUniforms>.stride, index: 0
            )
        }

        // Additive pass straight onto the completed composite (load + RGB
        // add): no full-res combine texture, no blit — half the bandwidth of
        // the combine-and-copy shape.
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = source
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.setRenderPipelineState(combine)
        encoder.setFragmentTexture(targets.mip1, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }
}
