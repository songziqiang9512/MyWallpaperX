import Metal
import simd

// Quad vertex laid out to match the MSL struct QuadVertex below.
// Position is in model space (unit quad centered at origin); the model
// matrix scales it to the layer's size and places it in world space.
struct SceneQuadVertex {
    var position: SIMD2<Float>
    var texcoord: SIMD2<Float>
    var vertexCoverage: Float = 1
}

enum SceneLayerBlendMode {
    case sourceOver
    case alphaWeightedAdditive
}

// Only visible world-space composition receives Fog; raw/source captures
// retain this disabled value. Layout matches SceneDistanceFog.metalh.
struct SceneImageDistanceFogUniforms {
    var color: SIMD4<Float> = .zero
    var range: SIMD4<Float> = .zero
    var cameraRelativeOrigin: SIMD4<Float> = .zero
    var modelX: SIMD4<Float> = .zero
    var modelY: SIMD4<Float> = .zero
}

// Per-layer uniform packed for setFragmentBytes. Layout matches MSL struct
// LayerFragmentUniforms below; all vector fields stay 16-byte aligned.
struct SceneLayerFragmentUniforms {
    var time: Float
    var alpha: Float
    var dependencyBlendMode: UInt32
    var usesDependencyBlend: UInt32
    var cursorUV: SIMD2<Float>   // cursor in layer-local UV space ([0..1])
    /// x: 0 linear-clamp, 1 linear-repeat, 2 nearest-clamp, 3 nearest-repeat.
    /// y bit 0: straight input; bit 1: preserve straight RGB in graph source capture.
    var sourceSampling: SIMD2<UInt32>
    var tint: SIMD4<Float>
    var textureFrame0: SIMD4<Float>
    var textureFrame1: SIMD4<Float>
    var distanceFog: SceneImageDistanceFogUniforms = .init()
}

struct SceneImageLayerPipeline {
    let pixelFormat: MTLPixelFormat
    let state: MTLRenderPipelineState
    private enum DepthMode: Hashable {
        case readOnly, readWrite, writeOnly
    }
    private let depthState: MTLRenderPipelineState?
    private let depthStencilStates: [DepthMode: MTLDepthStencilState]
    private let supportsTranslucentMaterialState: Bool
    var supportsReadOnlyDepth: Bool {
        supportsTranslucentMaterialState && depthState != nil
            && depthStencilStates[.readOnly] != nil
    }

    // Unit quad centered at origin, +Y up. The vertex MVP scales/translates it
    // into world space. UV convention: top-left (0,0) -> matches the flip done
    // by SceneTextureLoader.
    //
    // triangleStrip order: BL → BR → TL → TR.
    private static let unitQuadVertices: [SceneQuadVertex] = [
        SceneQuadVertex(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        SceneQuadVertex(position: SIMD2( 0.5, -0.5), texcoord: SIMD2(1, 1)),
        SceneQuadVertex(position: SIMD2(-0.5,  0.5), texcoord: SIMD2(0, 0)),
        SceneQuadVertex(position: SIMD2( 0.5,  0.5), texcoord: SIMD2(1, 0))
    ]

    init?(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        blendMode: SceneLayerBlendMode = .sourceOver,
        library injectedLibrary: MTLLibrary? = nil,
        preparesDepth: Bool = false
    ) {
        guard let library = injectedLibrary ?? device.makeDefaultLibrary(),
              let vertFn = library.makeFunction(name: "sceneImageLayerVert") else { return nil }
        let constants = MTLFunctionConstantValues()
        var weightsSourceAlpha = blendMode == .alphaWeightedAdditive
        constants.setConstantValue(&weightsSourceAlpha, type: .bool, index: 0)
        guard let fragFn = try? library.makeFunction(
            name: "sceneImageLayerFrag", constantValues: constants
        ) else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertFn
        descriptor.fragmentFunction = fragFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        // The image fragment associates straight input exactly once. Additive
        // drawing independently weights source RGB by authored coverage before
        // layer opacity; both use ONE for source RGB here.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = blendMode == .alphaWeightedAdditive ? .one : .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.state = state
        self.pixelFormat = pixelFormat
        supportsTranslucentMaterialState = blendMode == .sourceOver
        if preparesDepth {
            descriptor.depthAttachmentPixelFormat = .depth32Float
            depthState = try? device.makeRenderPipelineState(descriptor: descriptor)
            var states: [DepthMode: MTLDepthStencilState] = [:]
            for mode in [DepthMode.readOnly, .readWrite, .writeOnly] {
                let depthDescriptor = MTLDepthStencilDescriptor()
                depthDescriptor.depthCompareFunction = mode == .writeOnly ? .always : .greaterEqual
                depthDescriptor.isDepthWriteEnabled = mode != .readOnly
                states[mode] = device.makeDepthStencilState(descriptor: depthDescriptor)
            }
            depthStencilStates = states
        } else {
            depthState = nil
            depthStencilStates = [:]
        }
    }

    func supports(_ renderState: SceneMaterialRenderState) -> Bool {
        guard supportsTranslucentMaterialState, renderState.blending == .translucent,
              renderState.alphaWriting == .unspecified else { return false }
        guard let mode = Self.depthMode(for: renderState) else { return true }
        return depthState != nil && depthStencilStates[mode] != nil
    }

    private static func depthMode(for state: SceneMaterialRenderState) -> DepthMode? {
        if state.depthTest == .enabled {
            return state.depthWrite == .enabled ? .readWrite : .readOnly
        }
        return state.depthWrite == .enabled ? .writeOnly : nil
    }

    // Sets pipeline state + vertex quad buffer once per encoder. Call drawLayer
    // per layer after binding.
    func bind(encoder: MTLRenderCommandEncoder) {
#if DEBUG
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
#endif
        encoder.setRenderPipelineState(state)
        encoder.setDepthStencilState(nil)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.none)
        Self.bindQuad(encoder: encoder)
    }

    func bindReadOnlyDepth(encoder: MTLRenderCommandEncoder) -> Bool {
        guard supportsReadOnlyDepth else { return false }
        return bindDepth(encoder: encoder, mode: .readOnly, cullMode: .none)
    }

    func bind(encoder: MTLRenderCommandEncoder, renderState: SceneMaterialRenderState) -> Bool {
        guard supports(renderState) else { return false }
        let cullMode: MTLCullMode = renderState.cullMode == .normal ? .back : .none
        guard let mode = Self.depthMode(for: renderState) else {
            bind(encoder: encoder)
            encoder.setCullMode(cullMode)
            return true
        }
        return bindDepth(encoder: encoder, mode: mode, cullMode: cullMode)
    }

    private func bindDepth(
        encoder: MTLRenderCommandEncoder, mode: DepthMode, cullMode: MTLCullMode
    ) -> Bool {
        guard let depthState, let depthStencilState = depthStencilStates[mode] else { return false }
#if DEBUG
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
#endif
        encoder.setRenderPipelineState(depthState)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(cullMode)
        Self.bindQuad(encoder: encoder)
        return true
    }

    static func bindQuad(encoder: MTLRenderCommandEncoder) {
        var vertices = Self.unitQuadVertices
        encoder.setVertexBytes(
            &vertices,
            length: vertices.count * MemoryLayout<SceneQuadVertex>.stride,
            index: 0
        )
    }

    /// Zero scale disables clipping. Ordinary draws bind a source placeholder
    /// so a previous mesh part cannot leave its mask state on this encoder.
    static func bindClipMask(
        encoder: MTLRenderCommandEncoder,
        texture: MTLTexture,
        transform: SIMD4<Float> = .zero
    ) {
        var transformCopy = transform
        encoder.setFragmentTexture(texture, index: 2)
        encoder.setFragmentBytes(&transformCopy, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
    }

    func drawLayer(
        texture: MTLTexture,
        dependencyTexture: MTLTexture? = nil,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        encoder: MTLRenderCommandEncoder
    ) {
        var mvpCopy = mvp
        encoder.setVertexBytes(&mvpCopy, length: MemoryLayout<simd_float4x4>.size, index: 1)
        var uniformsCopy = uniforms
        encoder.setFragmentBytes(&uniformsCopy, length: MemoryLayout<SceneLayerFragmentUniforms>.size, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(dependencyTexture ?? texture, index: 1)
        Self.bindClipMask(encoder: encoder, texture: texture)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        #if DEBUG
        SceneGPUStageTimestampHook.drew(encoder)
                ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: false)
#endif
    }
}
