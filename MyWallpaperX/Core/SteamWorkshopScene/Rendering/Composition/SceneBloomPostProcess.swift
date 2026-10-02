import Metal

/// Scene-level bloom post-process configuration parsed from authored
/// `general` bloom keys (user-directed 2026-09-26; reference: the
/// MirageWallpaper `__bloom` LDR post-process chain).
nonisolated struct SceneBloomConfiguration: Codable, Equatable, Sendable {
    let enabled: Bool
    let strength: Float
    let threshold: Float
    let tint: SIMD3<Float>

    /// Read the current frame through the existing typed property snapshot.
    /// Absent or non-representable values retain the authored configuration.
    nonisolated func resolving(_ snapshot: SceneDynamicSnapshot) -> Self {
        func scalar(_ field: SceneDynamicSceneField, fallback: Float) -> Float {
            guard case let .scalar(value)? = snapshot[.scene(field)]?.value,
                  Float(value).isFinite else { return fallback }
            return Float(value)
        }
        var resolvedEnabled = enabled
        if case let .bool(value)? = snapshot[.scene(.bloomEnabled)]?.value {
            resolvedEnabled = value
        }
        var resolvedTint = tint
        if case let .vector3(x, y, z)? = snapshot[.scene(.bloomTint)]?.value {
            let value = SIMD3<Float>(Float(x), Float(y), Float(z))
            if value.x.isFinite && value.y.isFinite && value.z.isFinite {
                resolvedTint = value
            }
        }
        return Self(
            enabled: resolvedEnabled,
            strength: scalar(.bloomStrength, fallback: strength),
            threshold: scalar(.bloomThreshold, fallback: threshold),
            tint: resolvedTint
        )
    }

    nonisolated static let disabled = SceneBloomConfiguration(
        enabled: false, strength: 1, threshold: 0.65, tint: SIMD3(1, 1, 1)
    )
}

/// Encodes the bloom chain over a completed scene composite: bright-pass
/// downsample to quarter resolution, separable 13-tap gaussian blur (8-texel
/// spread, reference weights), then an additive full-resolution combine
/// added directly to the source. All shaders are fixed product code in
/// `SceneBloomPostProcess.metal`; authored constants ride per-pass buffers.
/// Any pipeline or texture failure skips the chain silently — bloom is an
/// enhancement layer, never a frame-fatal effect.
final class SceneBloomPostProcess {
    private let device: MTLDevice
    private let brightPipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let combinePipeline: MTLRenderPipelineState
    private var textureFailureLogged = false
    private var cachedTexturesBySize: [SIMD2<Int>: (mip1: MTLTexture, mip2: MTLTexture)] = [:]

    private let pixelFormat: MTLPixelFormat

    /// Prepare the complete pipeline set once at renderer creation. A partial
    /// set is never published and cannot trigger compiler work during encode.
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        self.device = device
        self.pixelFormat = pixelFormat
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "sceneBloomVertex"),
              let bright = library.makeFunction(name: "sceneBloomBrightFragment"),
              let blur = library.makeFunction(name: "sceneBloomBlurFragment"),
              let combine = library.makeFunction(name: "sceneBloomCombineFragment") else {
            NSLog("MWX Scene bloom: default library functions unavailable")
            return nil
        }
        func descriptor(
            _ fragment: MTLFunction, additive: Bool = false
        ) -> MTLRenderPipelineDescriptor {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
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
            NSLog(
                "MWX Scene bloom: pipeline state rejected: %@",
                String(describing: error)
            )
            return nil
        }
    }

    /// Reserve the same physical intermediates used by terminal encode, before
    /// optional shadow consumes the shared GPU quota. No GPU commands are emitted.
    func prepareCapacity(configuration: SceneBloomConfiguration, source: MTLTexture) -> Bool {
        guard configuration.enabled, configuration.strength != 0 else { return true }
        guard source.pixelFormat == pixelFormat, source.device === device else { return false }
        return intermediateTargets(on: device, matching: source) != nil
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
                pixelFormat: pixelFormat,
                width: max(1, width),
                height: max(1, height),
                mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            return device.makeSceneTexture(descriptor: descriptor)
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
            if !textureFailureLogged {
                textureFailureLogged = true
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
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setTriangleFillMode(.fill)
        bind(encoder)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    /// Add bloom only after every intermediate pass has encoded. An encoder
    /// failure leaves the completed source unchanged; cached intermediates
    /// are overwritten on the next attempt before they can be consumed.
    @discardableResult
    func encode(
        configuration: SceneBloomConfiguration,
        source: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        // Zero strength contributes no RGB and combine preserves source alpha.
        // Skip before allocating intermediates; live nonzero values reuse this owner.
        guard configuration.enabled, configuration.strength != 0,
              source.pixelFormat == pixelFormat,
              source.device === device,
              let targets = intermediateTargets(on: device, matching: source)
        else { return false }

        var brightUniforms = BrightUniforms(
            strength: configuration.strength,
            threshold: configuration.threshold,
            tint: configuration.tint
        )
        guard encodeQuad(brightPipeline, target: targets.mip1, commandBuffer: commandBuffer, bind: { encoder in
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(
                &brightUniforms, length: MemoryLayout<BrightUniforms>.stride, index: 0
            )
        }) else { return false }

        var blurVertical = BlurUniforms(
            direction: SIMD2(0, 1),
            stepUV: Self.blurStep
        )
        guard encodeQuad(blurPipeline, target: targets.mip2, commandBuffer: commandBuffer, bind: { encoder in
            encoder.setFragmentTexture(targets.mip1, index: 0)
            encoder.setFragmentBytes(
                &blurVertical, length: MemoryLayout<BlurUniforms>.stride, index: 0
            )
        }) else { return false }

        var blurHorizontal = BlurUniforms(
            direction: SIMD2(1, 0),
            stepUV: Self.blurStep
        )
        guard encodeQuad(blurPipeline, target: targets.mip1, commandBuffer: commandBuffer, bind: { encoder in
            encoder.setFragmentTexture(targets.mip2, index: 0)
            encoder.setFragmentBytes(
                &blurHorizontal, length: MemoryLayout<BlurUniforms>.stride, index: 0
            )
        }) else { return false }

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
        encoder.setRenderPipelineState(combinePipeline)
        encoder.setFragmentTexture(targets.mip1, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }
}
