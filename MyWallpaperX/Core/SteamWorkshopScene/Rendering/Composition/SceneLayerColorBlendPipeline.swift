import Foundation
import Metal
import simd

private let sceneLayerColorBlendShaderSource = SceneBlendModeShaderSource.blendFunctions + """

struct SceneLayerBlendVertex {
    float2 position;
    float2 texcoord;
    float vertexCoverage;
};

struct SceneLayerBlendVaryings {
    float4 position [[position]];
    float2 texcoord;
    float vertexCoverage;
    float2 modelPosition;
};

vertex SceneLayerBlendVaryings sceneLayerColorBlendVert(
    uint vertexID [[vertex_id]],
    constant SceneLayerBlendVertex *vertices [[buffer(0)]],
    constant float4x4 &mvp [[buffer(1)]]
) {
    SceneLayerBlendVaryings out;
    out.position = mvp * float4(vertices[vertexID].position, 0.0, 1.0);
    out.texcoord = vertices[vertexID].texcoord;
    out.vertexCoverage = vertices[vertexID].vertexCoverage;
    out.modelPosition = vertices[vertexID].position;
    return out;
}

inline float4 sceneLayerColorBlend(
    SceneLayerBlendVaryings input,
    texture2d<float> layerTexture,
    float4 background,
    texture2d<float> clipMask,
    constant uint2 &blend,
    constant float4 &clipTransform,
    constant SceneImageDistanceFogUniforms &distanceFog
) {
    constexpr sampler sampler2d(filter::linear, address::clamp_to_edge);
    constexpr sampler linearClipSampler(filter::linear, address::clamp_to_zero);
    const float clipCoverage = clipTransform.z == 0.0 ? 1.0
        : clipMask.sample(linearClipSampler,
            input.modelPosition * clipTransform.zw + clipTransform.xy).r;
    float4 layer = layerTexture.sample(sampler2d, input.texcoord);
    const float shapeCoverage = input.vertexCoverage * clipCoverage;
    const bool usesFog = distanceFog.color.w > 0.5;
    // Authored opacity participates in color blending before Fog. Geometry
    // coverage instead bounds the entire visible result, including its Fog;
    // a clipped mesh part must not darken the background around its shape.
    const float opacity = layer.a * (usesFog ? 1.0 : shapeCoverage);
    float3 blended = background.rgb;
    if (opacity != 0.0 || (blend.y & 2u) == 0u) {
        const float3 straightLayer = (blend.y & 1u) != 0u ? layer.rgb
            : layer.a > 0.0 ? layer.rgb / layer.a : float3(0.0);
        blended = sceneApplyBlending(int(blend.x), background.rgb, straightLayer, opacity);
    }
    if (usesFog) {
        blended = mix(background.rgb,
            sceneImageDistanceFog(blended, input.modelPosition, distanceFog), shapeCoverage);
    }
    return float4(blended, background.a);
}

fragment float4 sceneLayerColorBlendFrag(
    SceneLayerBlendVaryings input [[stage_in]],
    texture2d<float> layerTexture [[texture(0)]],
    texture2d<float> background [[texture(1)]],
    texture2d<float> clipMask [[texture(2)]],
    constant uint2 &blend [[buffer(0)]],
    constant float4 &clipTransform [[buffer(1)]],
    constant SceneImageDistanceFogUniforms &distanceFog [[buffer(2)]]
) {
    return sceneLayerColorBlend(input, layerTexture, background.read(uint2(input.position.xy)),
        clipMask, blend, clipTransform, distanceFog);
}
"""

private let sceneLayerColorBlendAttachmentSource = """

fragment float4 sceneLayerColorBlendAttachmentFrag(
    SceneLayerBlendVaryings input [[stage_in]],
    texture2d<float> layerTexture [[texture(0)]],
    float4 background [[color(0)]],
    texture2d<float> clipMask [[texture(2)]],
    constant uint2 &blend [[buffer(0)]],
    constant float4 &clipTransform [[buffer(1)]],
    constant SceneImageDistanceFogUniforms &distanceFog [[buffer(2)]]
) {
    return sceneLayerColorBlend(input, layerTexture, background, clipMask, blend, clipTransform, distanceFog);
}
"""

final class SceneLayerColorBlendPipelineState {
    let renderPipeline: MTLRenderPipelineState
    let attachmentPipeline: MTLRenderPipelineState?
    let pixelFormat: MTLPixelFormat

    init?(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        fogShaderSource: String? = nil
    ) {
        // Fixed shaders include this same header at build time. Dynamic blend
        // preparation reads its bundled copy once through the existing slot.
        let fogSource = fogShaderSource ?? Bundle.main.url(
            forResource: "SceneDistanceFog", withExtension: "metalh"
        ).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        guard let fogSource else { return nil }
        let options = MTLCompileOptions()
        let source = fogSource + "\n" + sceneLayerColorBlendShaderSource
        let supportsAttachment = device.supportsFamily(.apple2)
            && (pixelFormat == .bgra8Unorm || pixelFormat == .rgba16Float)
        let withAttachment = supportsAttachment ? try? device.makeLibrary(
            source: source + "\n" + sceneLayerColorBlendAttachmentSource, options: options
        ) : nil
        guard let library = withAttachment ?? (try? device.makeLibrary(source: source, options: options)),
           let vertex = library.makeFunction(name: "sceneLayerColorBlendVert"),
           let fragment = library.makeFunction(name: "sceneLayerColorBlendFrag") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let state = try? device.makeRenderPipelineState(
            descriptor: descriptor
        ) else {
            return nil
        }
        renderPipeline = state
        if let attachment = withAttachment?.makeFunction(name: "sceneLayerColorBlendAttachmentFrag") {
            descriptor.fragmentFunction = attachment
            attachmentPipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        } else {
            attachmentPipeline = nil
        }
        self.pixelFormat = pixelFormat
    }
}

final class SceneLayerColorBlendPipeline {
    enum Background {
        case snapshot(MTLTexture)
        case attachment(MTLRenderPipelineState)
    }

    private let state: SceneLayerColorBlendPipelineState
    let framebufferSnapshot: SceneFramebufferSnapshot

    var renderTargetResidentByteCost: Int {
        framebufferSnapshot.residentByteCost
    }

    convenience init?(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) {
        guard let state = SceneLayerColorBlendPipelineState(
            device: device,
            pixelFormat: pixelFormat
        ) else {
            return nil
        }
        self.init(device: device, state: state)
    }

    init(device: MTLDevice, state: SceneLayerColorBlendPipelineState) {
        self.state = state
        self.framebufferSnapshot = SceneFramebufferSnapshot(
            device: device,
            label: "Scene layer color blend background"
        )
    }

    func snapshot(
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        region: MTLRegion? = nil
    ) -> MTLTexture? {
        framebufferSnapshot.capture(target: target, commandBuffer: commandBuffer, region: region)
    }

    func attachmentPipeline(for target: MTLTexture, sampling source: MTLTexture) -> MTLRenderPipelineState? {
        guard let pipeline = state.attachmentPipeline, target.pixelFormat == state.pixelFormat,
              target.sampleCount == 1, (source.parent ?? source) !== (target.parent ?? target)
        else { return nil }
        return pipeline
    }

    func draw(
        layerTexture: MTLTexture,
        background: Background,
        blendMode: Int,
        mvp: simd_float4x4,
        sourceIsStraightAlpha: Bool = false,
        distanceFog: SceneImageDistanceFogUniforms = .init(),
        encoder: MTLRenderCommandEncoder
    ) {
        var vertices = Self.unitQuadVertices
        encoder.setVertexBytes(
            &vertices,
            length: vertices.count * MemoryLayout<SceneQuadVertex>.stride,
            index: 0
        )
        bind(
            layerTexture: layerTexture,
            background: background,
            blendMode: blendMode,
            mvp: mvp,
            sourceIsStraightAlpha: sourceIsStraightAlpha,
            distanceFog: distanceFog,
            encoder: encoder
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        #if DEBUG
        SceneGPUStageTimestampHook.drew(encoder)
                ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: false)
#endif
    }

    /// Binds the same blend fragment contract for caller-owned geometry. The
    /// caller keeps vertex/index ownership and issues the indexed mesh draw.
    func bindGeometry(
        layerTexture: MTLTexture,
        backgroundTexture: MTLTexture,
        blendMode: Int,
        mvp: simd_float4x4,
        sourceIsStraightAlpha: Bool = false,
        distanceFog: SceneImageDistanceFogUniforms = .init(),
        encoder: MTLRenderCommandEncoder
    ) {
        bind(layerTexture: layerTexture, background: .snapshot(backgroundTexture), blendMode: blendMode,
             mvp: mvp, sourceIsStraightAlpha: sourceIsStraightAlpha, distanceFog: distanceFog, encoder: encoder)
    }

    private func bind(
        layerTexture: MTLTexture,
        background: Background,
        blendMode: Int,
        mvp: simd_float4x4,
        sourceIsStraightAlpha: Bool,
        distanceFog: SceneImageDistanceFogUniforms,
        encoder: MTLRenderCommandEncoder
    ) {
        var mvpCopy = mvp
        let flags: UInt32 = (sourceIsStraightAlpha ? 1 : 0)
            | (SceneBlendModeShaderSource.keepsBackdropAtZeroOpacity(blendMode) ? 2 : 0)
        var mode = SIMD2(UInt32(blendMode), flags)
        var fog = distanceFog
#if DEBUG
        ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
#endif
        switch background {
        case let .snapshot(texture):
            encoder.setRenderPipelineState(state.renderPipeline)
            encoder.setFragmentTexture(texture, index: 1)
        case let .attachment(pipeline):
            encoder.setRenderPipelineState(pipeline)
        }
        encoder.setVertexBytes(
            &mvpCopy,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        encoder.setFragmentBytes(&mode, length: MemoryLayout<SIMD2<UInt32>>.size, index: 0)
        encoder.setFragmentBytes(&fog, length: MemoryLayout<SceneImageDistanceFogUniforms>.stride, index: 2)
        encoder.setFragmentTexture(layerTexture, index: 0)
        SceneImageLayerPipeline.bindClipMask(encoder: encoder, texture: layerTexture)
    }

    private static let unitQuadVertices: [SceneQuadVertex] = [
        SceneQuadVertex(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        SceneQuadVertex(position: SIMD2( 0.5, -0.5), texcoord: SIMD2(1, 1)),
        SceneQuadVertex(position: SIMD2(-0.5,  0.5), texcoord: SIMD2(0, 0)),
        SceneQuadVertex(position: SIMD2( 0.5,  0.5), texcoord: SIMD2(1, 0)),
    ]
}

enum SceneLayerColorBlendRenderer {
    static func supports(_ blendMode: Int) -> Bool {
        (0 ... SceneBlendModeShaderSource.maximumMode).contains(blendMode)
    }

    static func draw(
        texture: MTLTexture,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        dependencyTexture: MTLTexture?,
        layer: SceneRenderDescriptor.Layer,
        pipeline: SceneImageLayerPipeline,
        colorBlendPipeline: SceneLayerColorBlendPipeline?,
        geometryProduct: SceneGeometryProduct? = nil,
        terminalDepth: SceneImageLayerTerminalDepthBinding? = nil,
        terminalMaterialState: SceneMaterialRenderState? = nil,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        let blendMode = layer.colorBlendMode ?? 0
        guard supports(blendMode) else { return false }
        if layer.utilityLayer?.framebufferSource != nil {
            guard terminalMaterialState == nil, terminalDepth != nil, pipeline.supportsReadOnlyDepth,
                  blendMode == 0, geometryProduct == nil else { return false }
        } else if let terminalMaterialState {
            let needsDepth = terminalMaterialState.requiresDepthAttachment
            guard layer.utilityLayer == nil,
                  let prepared = layer.imageMaterialRenderState,
                  terminalMaterialState == prepared,
                  pipeline.supports(terminalMaterialState),
                  needsDepth == (terminalDepth != nil),
                  blendMode == 0, geometryProduct == nil else { return false }
        } else if terminalDepth != nil {
            return false
        }
        if let prepare = geometryProduct?.prepare {
            let extent = mainPass.targetExtent
            mainPass.encodeOffscreen {
                prepare($0, SIMD2(extent.width, extent.height), mvp,
                        mainPass.retainAuxiliaryRelease)
            }
        }
        if blendMode == 0 {
            let encoder: MTLRenderCommandEncoder?
            if let terminalDepth { encoder = terminalDepth.encoder(mainPass) }
            else { encoder = mainPass.encoder() }
            guard let encoder else { return false }
            if let geometryProduct {
                return geometryProduct.encode(
                    encoder,
                    texture,
                    dependencyTexture,
                    mvp,
                    uniforms,
                    nil
                )
            }
            if let terminalMaterialState {
                guard pipeline.bind(encoder: encoder, renderState: terminalMaterialState) else { return false }
            } else if terminalDepth != nil {
                guard pipeline.bindReadOnlyDepth(encoder: encoder) else { return false }
            } else {
                guard pipeline.bind(encoder: encoder, rasterSampleCount: mainPass.rasterSampleCount) else {
                    return false
                }
            }
            pipeline.drawLayer(
                texture: texture,
                dependencyTexture: dependencyTexture,
                mvp: mvp,
                uniforms: uniforms,
                encoder: encoder
            )
            return true
        }

        guard let colorBlendPipeline else { return false }
        let sourceIsStraightAlpha = uniforms.sourceSampling.y == 1
        if geometryProduct == nil, mainPass.isSceneRoot,
           layer.utilityLayer == nil || layer.childLayerIDs.isEmpty,
           mvp.columns.0.w == 0, mvp.columns.1.w == 0,
           mvp.columns.3.w.isFinite, mvp.columns.3.w > 0,
           mainPass.encodePreparedDraw({ target, _ in
               guard let attachment = colorBlendPipeline.attachmentPipeline(for: target, sampling: texture)
               else { return nil }
               mainPass.closeForOffscreen()
               return { encoder in
                   colorBlendPipeline.draw(layerTexture: texture, background: .attachment(attachment),
                       blendMode: blendMode, mvp: mvp, sourceIsStraightAlpha: sourceIsStraightAlpha,
                       distanceFog: uniforms.distanceFog, encoder: encoder)
               }
           }) {
#if DEBUG
            if let trace = mainPass.compositionTrace, trace.isCompositionSelected {
                let target = mainPass.compositionTarget
                trace.recordComposition(.init(kind: "color-blend-background", layerID: layer.id, slot: 1,
                    source: target, target: target, access: "color-attachment-read", outcome: "draw-encoded"))
            }
#endif
            return true
        }
        let captured = mainPass.withReadableTarget { target, commandBuffer in
            // The fragment reads the frozen background at its current pixel.
            let region: MTLRegion?
            if let geometryProduct {
                if mainPass.isSceneRoot, let backgroundBounds = geometryProduct.backgroundBounds,
                   geometryProduct.isPreparedForPublication(commandBuffer), let bounds = backgroundBounds() {
                    region = SceneLayerSourcePassthroughPlan.projectedRegion(bounds: bounds, mvp: mvp,
                        width: target.width, height: target.height)
                } else {
                    region = nil
                }
            } else {
                region = SceneLayerSourcePassthroughPlan.projectedGeometry(for: mvp)?
                    .pixelRegion(width: target.width, height: target.height)
            }
            let snapshot = colorBlendPipeline.snapshot(
                target: target, commandBuffer: commandBuffer, region: region)
#if DEBUG
            if let snapshot, let trace = mainPass.compositionTrace, trace.isCompositionSelected {
                trace.recordComposition(.init(kind: "background-copy", layerID: layer.id,
                    source: .init(target, role: "main-color"), target: .init(snapshot, role: "background-snapshot"),
                    access: "copy-source", outcome: "encoded", details: [
                        "x": String(region?.origin.x ?? 0), "y": String(region?.origin.y ?? 0),
                        "width": String(region?.size.width ?? target.width),
                        "height": String(region?.size.height ?? target.height)
                    ]))
            }
#endif
            return snapshot
        }
        guard let background = captured ?? nil,
              let encoder = mainPass.encoder() else {
            return false
        }
#if DEBUG
        var didEncodeBlend = false
        defer {
            if let trace = mainPass.compositionTrace, trace.isCompositionSelected {
                trace.recordComposition(.init(kind: "color-blend-background", layerID: layer.id, slot: 1,
                    source: .init(background, role: "background-snapshot"), target: mainPass.compositionTarget,
                    outcome: didEncodeBlend ? "draw-encoded" : "failed"))
            }
        }
#endif
        if let geometryProduct {
            let bindColorBlend: SceneGeometryProduct.ColorBlendBinder = {
                encoder, layerTexture, geometryMVP in
                colorBlendPipeline.bindGeometry(
                    layerTexture: layerTexture,
                    backgroundTexture: background,
                    blendMode: blendMode,
                    mvp: geometryMVP,
                    sourceIsStraightAlpha: sourceIsStraightAlpha,
                    distanceFog: uniforms.distanceFog,
                    encoder: encoder
                )
            }
            let encoded = geometryProduct.encode(
                encoder,
                texture,
                dependencyTexture,
                mvp,
                uniforms,
                bindColorBlend
            )
#if DEBUG
            didEncodeBlend = encoded
#endif
            return encoded
        }
        colorBlendPipeline.draw(
            layerTexture: texture,
            background: .snapshot(background),
            blendMode: blendMode,
            mvp: mvp,
            sourceIsStraightAlpha: sourceIsStraightAlpha,
            distanceFog: uniforms.distanceFog,
            encoder: encoder
        )
#if DEBUG
        didEncodeBlend = true
#endif
        return true
    }
}
