import Metal
import simd

struct SceneParticleDrawBatch {
    let layerID: Int
    let particlePath: String
    let texture: MTLTexture
    let colorUVScale: SIMD2<Float>
    let colorSampling: SceneParticleTextureSampling
    let refraction: SceneParticleRefractionBinding?
    let renderState: SceneParticlePipelineRenderState
    let childTemplateIndex: Int?
    let instances: [SceneParticleGPUInstance]
    let orientation: SceneParticleOrientation
    let orientationAxis: SIMD3<Float>?
    let usesPerspective: Bool
    /// Existing root RopeTrail admission, independent of Sprite material state.
    var inheritsNativeSceneCamera: Bool = false
    var referenceWorldFrame: simd_float4x4? = nil
    var sizeIsWorldSpace: Bool = false
#if DEBUG
    var debugRendererComponentIndex: Int? = nil
    var debugRendererKind: String? = nil
#endif
}

private struct SceneParticleQuadVertex {
    var position: SIMD2<Float>
    var texcoord: SIMD2<Float>
}

final class SceneParticleMetalPipeline {
    struct PreparedBatch {
        let draw: SceneParticleDrawBatch
        let instanceBuffer: SceneParticleMetalInstanceBuffer
    }

    private struct InstanceBufferKey: Hashable {
        let layerID: Int
        let childTemplateIndex: Int?
    }

    struct BlendConfiguration {
        let sourceRGB: MTLBlendFactor
        let destinationRGB: MTLBlendFactor
        let sourceAlpha: MTLBlendFactor
        let destinationAlpha: MTLBlendFactor
    }

    private let device: MTLDevice
    let pipelineStates: [SceneParticlePipelineVariant: MTLRenderPipelineState]
    private let depthStates: [Int: MTLDepthStencilState]
    private let samplerStates: SceneParticleSamplerStateSet
    let framebufferSnapshot: SceneFramebufferSnapshot
    private let depthTargetPool = SceneParticleDepthTargetPool()
    private var instanceBuffers: [InstanceBufferKey: SceneParticleMetalInstanceBuffer] = [:]

    var renderTargetResidentByteCost: Int {
        framebufferSnapshot.residentByteCost + depthTargetPool.residentByteCost
    }

    private static let unitQuad: [SceneParticleQuadVertex] = [
        .init(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        .init(position: SIMD2( 0.5, -0.5), texcoord: SIMD2(1, 1)),
        .init(position: SIMD2(-0.5,  0.5), texcoord: SIMD2(0, 0)),
        .init(position: SIMD2( 0.5,  0.5), texcoord: SIMD2(1, 0))
    ]

    init?(
        device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm,
        requiredVariants: Set<SceneParticlePipelineVariant> = SceneParticlePipelineVariant.standaloneDefaults
    ) {
        let library: MTLLibrary?
        let coverageLibrary: MTLLibrary?
        if requiredVariants.contains(where: { $0.blendMode == .alphaToCoverage }) {
            let candidate = try? device.makeLibrary(
                source: sceneParticleShaderSource + sceneParticleCoverageShaderSource,
                options: nil
            )
            coverageLibrary = candidate
            // An optional coverage function failure must not retire healthy
            // ordinary particles. All compilation stays in launch preparation.
            library = candidate ?? (try? device.makeLibrary(source: sceneParticleShaderSource, options: nil))
        } else {
            coverageLibrary = nil
            library = try? device.makeLibrary(source: sceneParticleShaderSource, options: nil)
        }
        guard let library,
              let samplerStates = SceneParticleSamplerStateSet(device: device),
              let depthStates = Self.makeDepthStates(device: device) else {
            return nil
        }
        let vertex = library.makeFunction(name: "sceneParticleVert")
        let fragment = library.makeFunction(name: "sceneParticleFrag")
        let refractFragment = library.makeFunction(name: "sceneParticleRefractFrag")
        let coverageVertex = coverageLibrary?.makeFunction(name: "sceneParticleCoverageVert")
        let coverageFragment = coverageLibrary?.makeFunction(name: "sceneParticleCoverageFrag")
        var states: [SceneParticlePipelineVariant: MTLRenderPipelineState] = [:]
        for variant in requiredVariants {
            let usesCoverage = variant.blendMode == .alphaToCoverage
            if usesCoverage && variant.isRefraction { continue }
            let variantVertex = usesCoverage ? coverageVertex : vertex
            let variantFragment = usesCoverage ? coverageFragment
                : (variant.isRefraction ? refractFragment : fragment)
            if let variantVertex, let variantFragment,
               let state = Self.makeState(
                   device: device, vertex: variantVertex, fragment: variantFragment,
                   pixelFormat: pixelFormat, blendMode: variant.blendMode,
                   depthPixelFormat: variant.usesDepthAttachment ? .depth32Float : .invalid
               ) {
                states[variant] = state
            } else if !usesCoverage {
                return nil
            }
        }
        self.device = device
        pipelineStates = states
        self.depthStates = depthStates
        self.samplerStates = samplerStates
        framebufferSnapshot = SceneFramebufferSnapshot(
            device: device,
            label: "Scene particle refraction background"
        )
    }

    func retire(layerIDs: Set<Int>) {
        for key in instanceBuffers.keys.filter({ layerIDs.contains($0.layerID) }) {
            instanceBuffers.removeValue(forKey: key)
        }
    }

    func prepare(_ batches: [SceneParticleDrawBatch]) -> [PreparedBatch] {
        batches.compactMap { batch in
            let key = InstanceBufferKey(layerID: batch.layerID, childTemplateIndex: batch.childTemplateIndex)
            let buffer: SceneParticleMetalInstanceBuffer
            if let existing = instanceBuffers[key] {
                buffer = existing
            } else {
                buffer = SceneParticleMetalInstanceBuffer()
                instanceBuffers[key] = buffer
            }
            guard buffer.update(device: device, instances: batch.instances),
                  buffer.currentDrawState() != nil else { return nil }
            return PreparedBatch(draw: batch, instanceBuffer: buffer)
        }
    }

    func cancel(_ batches: [PreparedBatch], on commandBuffer: MTLCommandBuffer) {
        guard commandBuffer.status == .notEnqueued else { return }
        for batch in batches {
            batch.instanceBuffer.cancelUncommittedSubmission(on: commandBuffer)
            batch.instanceBuffer.cancelPending()
        }
    }

    static func blendConfiguration(
        for mode: SceneParticlePipelineBlendMode
    ) -> BlendConfiguration {
        switch mode {
        case .translucent:
            BlendConfiguration(sourceRGB: .one, destinationRGB: .oneMinusSourceAlpha,
                sourceAlpha: .one, destinationAlpha: .oneMinusSourceAlpha)
        case .additive:
            BlendConfiguration(sourceRGB: .one, destinationRGB: .one,
                sourceAlpha: .one, destinationAlpha: .oneMinusSourceAlpha)
        case .alphaToCoverage:
            BlendConfiguration(sourceRGB: .one, destinationRGB: .zero,
                sourceAlpha: .one, destinationAlpha: .zero)
        }
    }

    @discardableResult
    func draw(
        texture: MTLTexture,
        instances: SceneParticleMetalInstanceBuffer,
        uniforms: SceneParticleLayerUniforms,
        renderState: SceneParticlePipelineRenderState,
        colorUVScale: SIMD2<Float> = SIMD2(repeating: 1),
        colorSampling: SceneParticleTextureSampling,
        usesDepthAttachment: Bool = false,
        encoder: MTLRenderCommandEncoder,
        observeBindings: ((MTLTexture, SceneParticleRefractionBinding.NormalArguments?, MTLTexture?, Int) -> Void)? = nil
    ) -> Bool {
        let variant = SceneParticlePipelineVariant(
            blendMode: renderState.blendMode, usesDepthAttachment: usesDepthAttachment
        )
        guard let state = pipelineStates[variant],
              let drawState = instances.currentDrawState() else { return false }
#if DEBUG
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
#endif
        encoder.setRenderPipelineState(state)
        if usesDepthAttachment {
            encoder.setDepthStencilState(depthState(for: renderState))
        }
        configureCull(renderState.cullMode, encoder: encoder)
        defer { encoder.setCullMode(.none) }
        var quad = Self.unitQuad
        encoder.setVertexBytes(
            &quad,
            length: quad.count * MemoryLayout<SceneParticleQuadVertex>.stride,
            index: 0
        )
        encoder.setVertexBuffer(drawState.buffer, offset: 0, index: 1)
        var uniformCopy = uniforms
        encoder.setVertexBytes(
            &uniformCopy,
            length: MemoryLayout<SceneParticleLayerUniforms>.stride,
            index: 2
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(
            samplerStates.state(for: colorSampling),
            index: 0
        )
        var parameters = SIMD4<Float>(
            colorUVScale.x,
            colorUVScale.y,
            renderState.overbright,
            0
        )
        encoder.setFragmentBytes(
            &parameters,
            length: MemoryLayout<SIMD4<Float>>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: Self.unitQuad.count,
            instanceCount: drawState.count
        )
        #if DEBUG
        observeBindings?(texture, nil, nil, drawState.count)
        SceneGPUStageTimestampHook.drew(encoder)
                ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: true)
#endif
        return true
    }

    func acquireDepthTarget(width: Int, height: Int,
                            on commandBuffer: MTLCommandBuffer) -> SceneParticleDepthTargetPool.Acquisition {
        depthTargetPool.acquire(device: device, width: width, height: height, on: commandBuffer)
    }

    func snapshot(
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        framebufferSnapshot.capture(target: target, commandBuffer: commandBuffer)
    }

    @discardableResult
    func drawRefraction(
        texture: MTLTexture,
        binding: SceneParticleRefractionBinding,
        background: MTLTexture,
        instances: SceneParticleMetalInstanceBuffer,
        uniforms: SceneParticleLayerUniforms,
        renderState: SceneParticlePipelineRenderState,
        colorUVScale: SIMD2<Float>,
        colorSampling: SceneParticleTextureSampling,
        usesDepthAttachment: Bool = false,
        encoder: MTLRenderCommandEncoder,
        observeBindings: ((MTLTexture, SceneParticleRefractionBinding.NormalArguments?, MTLTexture?, Int) -> Void)? = nil
    ) -> Bool {
        let variant = SceneParticlePipelineVariant(
            isRefraction: true, blendMode: renderState.blendMode,
            usesDepthAttachment: usesDepthAttachment
        )
        guard let state = pipelineStates[variant],
              let drawState = instances.currentDrawState(),
              let normal = binding.resolvedNormalArguments() else { return false }
#if DEBUG
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
#endif
        encoder.setRenderPipelineState(state)
        if usesDepthAttachment {
            encoder.setDepthStencilState(depthState(for: renderState))
        }
        configureCull(renderState.cullMode, encoder: encoder)
        defer { encoder.setCullMode(.none) }
        bindGeometry(
            drawState: drawState,
            uniforms: uniforms,
            encoder: encoder
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(normal.texture, index: 1)
        encoder.setFragmentTexture(background, index: 2)
        encoder.setFragmentSamplerState(
            samplerStates.state(for: colorSampling),
            index: 0
        )
        encoder.setFragmentSamplerState(
            samplerStates.state(for: normal.sampling),
            index: 1
        )
        var parameters = SIMD4<Float>(
            binding.amount,
            binding.overbright,
            Float(binding.colorEncoding.rawValue),
            (normal.usesParticleFrames ? 1 : 0)
                + (normal.authoredFormat == .dxt5 ? 2 : 0)
                + (normal.authoredFormat == nil ? 4 : 0)
        )
        var scales = SIMD4<Float>(
            colorUVScale.x,
            colorUVScale.y,
            normal.uvScale.x,
            normal.uvScale.y
        )
        encoder.setFragmentBytes(
            &parameters,
            length: MemoryLayout<SIMD4<Float>>.stride,
            index: 0
        )
        encoder.setFragmentBytes(
            &scales,
            length: MemoryLayout<SIMD4<Float>>.stride,
            index: 1
        )
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: Self.unitQuad.count,
            instanceCount: drawState.count
        )
        #if DEBUG
        observeBindings?(texture, normal, background, drawState.count)
        SceneGPUStageTimestampHook.drew(encoder)
                ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: true)
#endif
        return true
    }

    private func bindGeometry(
        drawState: (buffer: MTLBuffer, count: Int),
        uniforms: SceneParticleLayerUniforms,
        encoder: MTLRenderCommandEncoder
    ) {
        var quad = Self.unitQuad
        encoder.setVertexBytes(
            &quad,
            length: quad.count * MemoryLayout<SceneParticleQuadVertex>.stride,
            index: 0
        )
        encoder.setVertexBuffer(drawState.buffer, offset: 0, index: 1)
        var uniformCopy = uniforms
        encoder.setVertexBytes(
            &uniformCopy,
            length: MemoryLayout<SceneParticleLayerUniforms>.stride,
            index: 2
        )
    }

    private func configureCull(
        _ mode: SceneParticlePipelineCullMode,
        encoder: MTLRenderCommandEncoder
    ) {
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(mode == .back ? .back : .none)
    }

    private func depthState(
        for state: SceneParticlePipelineRenderState
    ) -> MTLDepthStencilState? {
        depthStates[(state.depthTestEnabled ? 2 : 0) | (state.depthWriteEnabled ? 1 : 0)]
    }

    private static func makeState(
        device: MTLDevice,
        vertex: MTLFunction,
        fragment: MTLFunction,
        pixelFormat: MTLPixelFormat,
        blendMode: SceneParticlePipelineBlendMode,
        depthPixelFormat: MTLPixelFormat = .invalid
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.depthAttachmentPixelFormat = depthPixelFormat
        descriptor.rasterSampleCount = 1
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        switch blendMode {
        case .translucent, .additive:
            attachment.isBlendingEnabled = true
        case .alphaToCoverage:
            attachment.isBlendingEnabled = false
            descriptor.isAlphaToCoverageEnabled = true
            descriptor.isAlphaToOneEnabled = true
        }
        let blend = blendConfiguration(for: blendMode)
        attachment.sourceRGBBlendFactor = blend.sourceRGB
        attachment.destinationRGBBlendFactor = blend.destinationRGB
        attachment.sourceAlphaBlendFactor = blend.sourceAlpha
        attachment.destinationAlphaBlendFactor = blend.destinationAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeDepthStates(
        device: MTLDevice
    ) -> [Int: MTLDepthStencilState]? {
        var states: [Int: MTLDepthStencilState] = [:]
        for depthTest in [false, true] {
            for depthWrite in [false, true] {
                let descriptor = MTLDepthStencilDescriptor()
                descriptor.depthCompareFunction = depthTest ? .lessEqual : .always
                descriptor.isDepthWriteEnabled = depthWrite
                let key = (depthTest ? 2 : 0) | (depthWrite ? 1 : 0)
                guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
                    return nil
                }
                states[key] = state
            }
        }
        return states
    }
}
