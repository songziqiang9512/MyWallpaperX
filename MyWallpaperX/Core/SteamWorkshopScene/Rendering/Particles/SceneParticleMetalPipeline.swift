import Metal
import simd

private struct SceneParticleQuadVertex {
    var position: SIMD2<Float>
    var texcoord: SIMD2<Float>
}

struct SceneParticleMetalPipeline {
    struct BlendConfiguration {
        let sourceRGB: MTLBlendFactor
        let destinationRGB: MTLBlendFactor
        let sourceAlpha: MTLBlendFactor
        let destinationAlpha: MTLBlendFactor
    }

    private let device: MTLDevice
    private let translucentState: MTLRenderPipelineState
    private let additiveState: MTLRenderPipelineState
    private let depthTranslucentState: MTLRenderPipelineState
    private let depthAdditiveState: MTLRenderPipelineState
    private let refractTranslucentState: MTLRenderPipelineState
    private let refractAdditiveState: MTLRenderPipelineState
    private let coverageState: MTLRenderPipelineState?
    private let depthCoverageState: MTLRenderPipelineState?
    private let depthStates: [Int: MTLDepthStencilState]
    private let samplerStates: SceneParticleSamplerStateSet
    let framebufferSnapshot: SceneFramebufferSnapshot
    private let depthTargetPool = SceneParticleDepthTargetPool()

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
        requiresAlphaToCoverage: Bool = false
    ) {
        let library: MTLLibrary?
        let coverageLibrary: MTLLibrary?
        if requiresAlphaToCoverage {
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
              let vertex = library.makeFunction(name: "sceneParticleVert"),
              let fragment = library.makeFunction(name: "sceneParticleFrag"),
              let refractFragment = library.makeFunction(name: "sceneParticleRefractFrag"),
              let translucent = Self.makeState(
                  device: device,
                  vertex: vertex,
                  fragment: fragment,
                  pixelFormat: pixelFormat,
                  blendMode: .translucent
              ),
              let additive = Self.makeState(
                  device: device,
                  vertex: vertex,
                  fragment: fragment,
                  pixelFormat: pixelFormat,
                  blendMode: .additive
              ),
              let depthTranslucent = Self.makeState(
                  device: device,
                  vertex: vertex,
                  fragment: fragment,
                  pixelFormat: pixelFormat,
                  blendMode: .translucent,
                  depthPixelFormat: .depth32Float
              ),
              let depthAdditive = Self.makeState(
                  device: device,
                  vertex: vertex,
                  fragment: fragment,
                  pixelFormat: pixelFormat,
                  blendMode: .additive,
                  depthPixelFormat: .depth32Float
              ),
              let refractTranslucent = Self.makeState(
                  device: device,
                  vertex: vertex,
                  fragment: refractFragment,
                  pixelFormat: pixelFormat,
                  blendMode: .translucent
              ),
              let refractAdditive = Self.makeState(
                  device: device,
                  vertex: vertex,
                  fragment: refractFragment,
                  pixelFormat: pixelFormat,
                  blendMode: .additive
              ),
              let samplerStates = SceneParticleSamplerStateSet(device: device),
              let depthStates = Self.makeDepthStates(device: device) else {
            return nil
        }
        translucentState = translucent
        self.device = device
        additiveState = additive
        depthTranslucentState = depthTranslucent
        depthAdditiveState = depthAdditive
        refractTranslucentState = refractTranslucent
        refractAdditiveState = refractAdditive
        if let coverageVertex = coverageLibrary?.makeFunction(name: "sceneParticleCoverageVert"),
           let coverageFragment = coverageLibrary?.makeFunction(name: "sceneParticleCoverageFrag") {
            coverageState = Self.makeState(
                device: device, vertex: coverageVertex, fragment: coverageFragment,
                pixelFormat: pixelFormat, blendMode: .alphaToCoverage
            )
            // Another prepared batch may require a shared depth attachment
            // even though this coverage material itself does not test/write it.
            depthCoverageState = Self.makeState(
                device: device, vertex: coverageVertex, fragment: coverageFragment,
                pixelFormat: pixelFormat, blendMode: .alphaToCoverage,
                depthPixelFormat: .depth32Float
            )
        } else {
            coverageState = nil
            depthCoverageState = nil
        }
        self.depthStates = depthStates
        self.samplerStates = samplerStates
        framebufferSnapshot = SceneFramebufferSnapshot(
            device: device,
            label: "Scene particle refraction background"
        )
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
        encoder: MTLRenderCommandEncoder
    ) -> Bool {
        let state: MTLRenderPipelineState?
        switch renderState.blendMode {
        case .translucent:
            state = usesDepthAttachment ? depthTranslucentState : translucentState
        case .additive:
            state = usesDepthAttachment ? depthAdditiveState : additiveState
        case .alphaToCoverage:
            state = usesDepthAttachment ? depthCoverageState : coverageState
        }
        guard let state, let drawState = instances.currentDrawState() else { return false }
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
        encoder: MTLRenderCommandEncoder
    ) -> Bool {
        let state: MTLRenderPipelineState
        switch renderState.blendMode {
        case .translucent: state = refractTranslucentState
        case .additive: state = refractAdditiveState
        case .alphaToCoverage: return false
        }
        guard let drawState = instances.currentDrawState(),
              let normal = binding.resolvedNormalArguments() else { return false }
#if DEBUG
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
#endif
        encoder.setRenderPipelineState(state)
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
