import Metal

/// Scene-level bloom post-process configuration parsed from authored
/// `general` bloom keys (user-directed 2026-09-26; reference: the
/// MirageWallpaper `__bloom` LDR post-process chain).
nonisolated struct SceneBloomConfiguration: Codable, Equatable, Sendable {
    /// Authored HDR Bloom parameters. Display EDR is a separate terminal policy.
    nonisolated struct HDR: Codable, Equatable, Sendable {
        let strength: Float
        let threshold: Float
        let scatter: Float
        let feather: Float
        let iterations: Float
    }
    let enabled: Bool
    let strength: Float
    let threshold: Float
    let tint: SIMD3<Float>
    var hdr: HDR? = nil

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
            tint: resolvedTint,
            hdr: hdr.map { configuration in
                HDR(
                    strength: scalar(.bloomHDRStrength, fallback: configuration.strength),
                    threshold: scalar(.bloomHDRThreshold, fallback: configuration.threshold),
                    scatter: scalar(.bloomHDRScatter, fallback: configuration.scatter),
                    feather: scalar(.bloomHDRFeather, fallback: configuration.feather),
                    iterations: scalar(.bloomHDRIterations, fallback: configuration.iterations)
                )
            }
        )
    }

    nonisolated static let disabled = SceneBloomConfiguration(
        enabled: false, strength: 1, threshold: 0.65, tint: SIMD3(1, 1, 1)
    )
}

/// Scene post processing in one owner. Standard Bloom retains its existing
/// quarter/sixteenth-resolution blur. Authored HDR selects a separate prepared
/// multiscale pipeline, preserving superwhite energy until terminal display.
/// Both routes add to the completed source only after all intermediates succeed.
/// Pipeline and resource failures skip this optional effect.
final class SceneBloomPostProcess {
    private let device: MTLDevice
    private let brightPipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let combinePipeline: MTLRenderPipelineState
    private let hdrUpsamplePipeline: MTLRenderPipelineState?
    private var hdrTargets: HDRTargets?
    private var textureFailureLogged = false
    private var cachedTexturesBySize: [SIMD2<Int>: (mip1: MTLTexture, mip2: MTLTexture)] = [:]

    private let pixelFormat: MTLPixelFormat

    /// Prepare the complete pipeline set once at renderer creation. A partial
    /// set is never published and cannot trigger compiler work during encode.
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm, hdrEnabled: Bool = false) {
        self.device = device
        self.pixelFormat = pixelFormat
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "sceneBloomVertex"),
              let bright = library.makeFunction(name: hdrEnabled ? "sceneBloomHDRBrightFragment" : "sceneBloomBrightFragment"),
              let blur = library.makeFunction(name: hdrEnabled ? "sceneBloomHDRDownsampleFragment" : "sceneBloomBlurFragment"),
              let combine = library.makeFunction(name: hdrEnabled ? "sceneBloomHDRCombineFragment" : "sceneBloomCombineFragment") else {
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
            if hdrEnabled {
                guard pixelFormat == .rgba16Float,
                      let upsample = library.makeFunction(name: "sceneBloomHDRUpsampleFragment") else {
                    return nil
                }
                hdrUpsamplePipeline = try device.makeRenderPipelineState(descriptor: descriptor(upsample))
            } else {
                hdrUpsamplePipeline = nil
            }
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
        guard configuration.enabled else { return true }
        guard source.pixelFormat == pixelFormat, source.device === device else { return false }
        if hdrUpsamplePipeline != nil {
            guard let hdr = configuration.hdr, hdr.strength != 0 else { return true }
            guard let dimensions = hdrDimensions(hdr, source: source) else { return true }
            return prepareHDRTargets(dimensions) != nil
        }
        guard configuration.strength != 0 else { return true }
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
        if hdrUpsamplePipeline != nil {
            return encodeHDR(configuration: configuration, source: source, commandBuffer: commandBuffer)
        }
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

    private struct HDRTargets {
        let dimensions: [SIMD2<Int>]
        let down: [MTLTexture]
        let up: [MTLTexture]
    }

    /// Bound GPU work by the source's physical mip chain before converting the
    /// authored Float to Int. The same plan is used for capacity and encoding.
    /// Authored counts below two have a distinct, unresolved output transfer;
    /// skip this optional effect instead of guessing a whole-scene gamma change.
    private func hdrDimensions(_ hdr: SceneBloomConfiguration.HDR, source: MTLTexture) -> [SIMD2<Int>]? {
        guard [hdr.strength, hdr.threshold, hdr.scatter, hdr.feather, hdr.iterations].allSatisfy(\.isFinite),
              hdr.strength > 0, hdr.iterations >= 2 else { return nil }
        var available: [SIMD2<Int>] = []
        var size = SIMD2(source.width, source.height)
        repeat {
            size = SIMD2(max(1, size.x / 2), max(1, size.y / 2))
            available.append(size)
        } while size.x > 1 || size.y > 1
        let count = max(1, Int(min(Float(available.count), hdr.iterations)))
        return Array(available.prefix(count))
    }

    private func prepareHDRTargets(_ dimensions: [SIMD2<Int>]) -> HDRTargets? {
        if let hdrTargets, hdrTargets.dimensions == dimensions { return hdrTargets }
        // The old extent is no longer reusable. Command buffers retain their
        // actual textures and budget leases until completion; release this
        // cache reference so a completed old chain cannot block its replacement.
        hdrTargets = nil
        func texture(_ size: SIMD2<Int>) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat, width: size.x, height: size.y, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            return device.makeSceneTexture(descriptor: descriptor)
        }
        var down: [MTLTexture] = [], up: [MTLTexture] = []
        for (index, size) in dimensions.enumerated() {
            guard let target = texture(size) else { return nil }
            down.append(target)
            if index + 1 < dimensions.count {
                guard let target = texture(size) else { return nil }
                up.append(target)
            }
        }
        let result = HDRTargets(dimensions: dimensions, down: down, up: up)
        hdrTargets = result
        return result
    }

    private struct HDRUniforms {
        var threshold: Float
        var feather: Float
        var reconstructionScale: Float
        var strength: Float
        var tint: SIMD3<Float>
    }

    private struct HDRReconstructionUniforms {
        var fineWeight: Float
        var coarseWeight: Float
    }

    /// Independent normalized scale weights, tested against uniform-field
    /// observations. Log-space evaluation avoids computing an overflowing
    /// scatter power and dividing it back down after half storage.
    private func hdrScaleWeights(scatter: Float, count: Int) -> (weights: [Float], scale: Float) {
        guard count > 1 else { return ([1], 0.5) }
        let value = Double(max(0, scatter))
        if value == 0 {
            return ([1] + Array(repeating: 0, count: count - 1), count == 2 ? 0.5 : 1)
        }
        let logarithm = log(value)
        let exponent = Double(count - 2) * logarithm
        let denominatorLog = max(0, exponent) + log1p(exp(-abs(exponent)))
        // Each normalized weight is mathematically at most max(1, scatter).
        let upperBound = max(1, value)
        let raw = (0..<count).map {
            min(upperBound, exp(Double($0) * logarithm - denominatorLog))
        }
        // Keep the half-float pyramid a convex reconstruction. Recover the
        // common scale only with strength/tint at the final contribution, so
        // large scatter followed by small strength does not clip in storage.
        let total = raw.reduce(0, +)
        return (raw.map { Float($0 / total) }, Float(total))
    }

    private func encodeHDR(
        configuration: SceneBloomConfiguration, source: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard configuration.enabled, let hdr = configuration.hdr,
              source.pixelFormat == pixelFormat, source.device === device,
              let upsample = hdrUpsamplePipeline,
              let dimensions = hdrDimensions(hdr, source: source),
              let targets = prepareHDRTargets(dimensions) else { return false }
        var uniforms = HDRUniforms(threshold: hdr.threshold, feather: hdr.feather,
            reconstructionScale: 1, strength: hdr.strength, tint: configuration.tint)
        guard encodeQuad(brightPipeline, target: targets.down[0], commandBuffer: commandBuffer, bind: {
            $0.setFragmentTexture(source, index: 0)
            $0.setFragmentBytes(&uniforms, length: MemoryLayout<HDRUniforms>.stride, index: 0)
        }) else { return false }
        for index in 1..<targets.down.count {
            guard encodeQuad(blurPipeline, target: targets.down[index], commandBuffer: commandBuffer, bind: {
                $0.setFragmentTexture(targets.down[index - 1], index: 0)
            }) else { return false }
        }
        let reconstruction = hdrScaleWeights(scatter: hdr.scatter, count: targets.down.count)
        let weights = reconstruction.weights
        uniforms.reconstructionScale = reconstruction.scale
        var reconstructed = targets.down[targets.down.count - 1]
        for index in targets.up.indices.reversed() {
            var reconstruction = HDRReconstructionUniforms(fineWeight: weights[index],
                coarseWeight: index == targets.down.count - 2 ? weights[index + 1] : 1)
            guard encodeQuad(upsample, target: targets.up[index], commandBuffer: commandBuffer, bind: {
                $0.setFragmentTexture(reconstructed, index: 0)
                $0.setFragmentTexture(targets.down[index], index: 1)
                $0.setFragmentBytes(&reconstruction,
                    length: MemoryLayout<HDRReconstructionUniforms>.stride, index: 0)
            }) else { return false }
            reconstructed = targets.up[index]
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = source
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        encoder.setRenderPipelineState(combinePipeline)
        encoder.setFragmentTexture(reconstructed, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<HDRUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

}
