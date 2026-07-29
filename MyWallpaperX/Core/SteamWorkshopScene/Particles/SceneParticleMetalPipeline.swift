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

    private let translucentState: MTLRenderPipelineState
    private let additiveState: MTLRenderPipelineState
    private let refractTranslucentState: MTLRenderPipelineState
    private let refractAdditiveState: MTLRenderPipelineState
    private let samplerStates: SceneParticleSamplerStateSet
    private let framebufferSnapshot: SceneFramebufferSnapshot

    private static let unitQuad: [SceneParticleQuadVertex] = [
        .init(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        .init(position: SIMD2( 0.5, -0.5), texcoord: SIMD2(1, 1)),
        .init(position: SIMD2(-0.5,  0.5), texcoord: SIMD2(0, 0)),
        .init(position: SIMD2( 0.5,  0.5), texcoord: SIMD2(1, 0))
    ]

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let library = try? device.makeLibrary(source: sceneParticleShaderSource, options: nil),
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
              let samplerStates = SceneParticleSamplerStateSet(device: device) else {
            return nil
        }
        translucentState = translucent
        additiveState = additive
        refractTranslucentState = refractTranslucent
        refractAdditiveState = refractAdditive
        self.samplerStates = samplerStates
        framebufferSnapshot = SceneFramebufferSnapshot(
            device: device,
            label: "Scene particle refraction background"
        )
    }

    static func blendConfiguration(
        for mode: SceneParticlePipelineBlendMode
    ) -> BlendConfiguration {
        BlendConfiguration(
            sourceRGB: mode == .additive ? .sourceAlpha : .one,
            destinationRGB: mode == .additive ? .one : .oneMinusSourceAlpha,
            sourceAlpha: .one,
            destinationAlpha: .oneMinusSourceAlpha
        )
    }

    func draw(
        texture: MTLTexture,
        instances: SceneParticleMetalInstanceBuffer,
        uniforms: SceneParticleLayerUniforms,
        blendMode: SceneParticlePipelineBlendMode,
        colorUVScale: SIMD2<Float> = SIMD2(repeating: 1),
        colorSampling: SceneParticleTextureSampling,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let drawState = instances.currentDrawState() else { return }
        encoder.setRenderPipelineState(
            blendMode == .additive ? additiveState : translucentState
        )
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
        var uvScale = colorUVScale
        encoder.setFragmentBytes(
            &uvScale,
            length: MemoryLayout<SIMD2<Float>>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: Self.unitQuad.count,
            instanceCount: drawState.count
        )
    }

    func snapshot(
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        framebufferSnapshot.capture(target: target, commandBuffer: commandBuffer)
    }

    func drawRefraction(
        texture: MTLTexture,
        binding: SceneParticleRefractionBinding,
        background: MTLTexture,
        instances: SceneParticleMetalInstanceBuffer,
        uniforms: SceneParticleLayerUniforms,
        blendMode: SceneParticlePipelineBlendMode,
        colorUVScale: SIMD2<Float>,
        colorSampling: SceneParticleTextureSampling,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let drawState = instances.currentDrawState() else { return }
        encoder.setRenderPipelineState(
            blendMode == .additive ? refractAdditiveState : refractTranslucentState
        )
        bindGeometry(
            drawState: drawState,
            uniforms: uniforms,
            encoder: encoder
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(binding.normalTexture, index: 1)
        encoder.setFragmentTexture(background, index: 2)
        encoder.setFragmentSamplerState(
            samplerStates.state(for: colorSampling),
            index: 0
        )
        encoder.setFragmentSamplerState(
            samplerStates.state(for: binding.normalSampling),
            index: 1
        )
        var parameters = SIMD4<Float>(
            binding.amount,
            binding.overbright,
            Float(binding.colorEncoding.rawValue),
            (binding.normalUsesParticleFrames ? 1 : 0)
                + (blendMode == .additive ? 2 : 0)
        )
        var scales = SIMD4<Float>(
            colorUVScale.x,
            colorUVScale.y,
            binding.normalUVScale.x,
            binding.normalUVScale.y
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

    private static func makeState(
        device: MTLDevice,
        vertex: MTLFunction,
        fragment: MTLFunction,
        pixelFormat: MTLPixelFormat,
        blendMode: SceneParticlePipelineBlendMode
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        let blend = blendConfiguration(for: blendMode)
        attachment.sourceRGBBlendFactor = blend.sourceRGB
        attachment.destinationRGBBlendFactor = blend.destinationRGB
        attachment.sourceAlphaBlendFactor = blend.sourceAlpha
        attachment.destinationAlphaBlendFactor = blend.destinationAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}
