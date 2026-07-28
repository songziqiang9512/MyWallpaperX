import Metal
import simd

private let sceneLayerColorBlendShaderSource = SceneBlendModeShaderSource.blendFunctions + """

struct SceneLayerBlendVertex {
    float2 position;
    float2 texcoord;
};

struct SceneLayerBlendVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex SceneLayerBlendVaryings sceneLayerColorBlendVert(
    uint vertexID [[vertex_id]],
    constant SceneLayerBlendVertex *vertices [[buffer(0)]],
    constant float4x4 &mvp [[buffer(1)]]
) {
    SceneLayerBlendVaryings out;
    out.position = mvp * float4(vertices[vertexID].position, 0.0, 1.0);
    out.texcoord = vertices[vertexID].texcoord;
    return out;
}

fragment float4 sceneLayerColorBlendFrag(
    SceneLayerBlendVaryings input [[stage_in]],
    texture2d<float> layerTexture [[texture(0)]],
    texture2d<float> backgroundTexture [[texture(1)]],
    constant int &blendMode [[buffer(0)]]
) {
    constexpr sampler sampler2d(filter::linear, address::clamp_to_edge);
    float4 layer = layerTexture.sample(sampler2d, input.texcoord);
    float4 background = backgroundTexture.read(uint2(input.position.xy));
    float3 straightLayer = layer.a > 0.0 ? layer.rgb / layer.a : float3(0.0);
    return float4(
        sceneApplyBlending(blendMode, background.rgb, straightLayer, layer.a),
        background.a
    );
}
"""

final class SceneLayerColorBlendPipeline {
    private let state: MTLRenderPipelineState
    private let framebufferSnapshot: SceneFramebufferSnapshot

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(
            source: sceneLayerColorBlendShaderSource,
            options: options
        ), let vertex = library.makeFunction(name: "sceneLayerColorBlendVert"),
           let fragment = library.makeFunction(name: "sceneLayerColorBlendFrag") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.state = state
        self.framebufferSnapshot = SceneFramebufferSnapshot(
            device: device,
            label: "Scene layer color blend background"
        )
    }

    func snapshot(
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        framebufferSnapshot.capture(target: target, commandBuffer: commandBuffer)
    }

    func draw(
        layerTexture: MTLTexture,
        backgroundTexture: MTLTexture,
        blendMode: Int,
        mvp: simd_float4x4,
        encoder: MTLRenderCommandEncoder
    ) {
        var vertices = Self.unitQuadVertices
        var mvpCopy = mvp
        var mode = Int32(blendMode)
        encoder.setRenderPipelineState(state)
        encoder.setVertexBytes(
            &vertices,
            length: vertices.count * MemoryLayout<SceneQuadVertex>.stride,
            index: 0
        )
        encoder.setVertexBytes(
            &mvpCopy,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        encoder.setFragmentBytes(&mode, length: MemoryLayout<Int32>.size, index: 0)
        encoder.setFragmentTexture(layerTexture, index: 0)
        encoder.setFragmentTexture(backgroundTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
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
        masks: SceneImageLayerMasks,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        dependencyTexture: MTLTexture?,
        layer: SceneRenderDescriptor.Layer,
        pipeline: SceneImageLayerPipeline,
        colorBlendPipeline: SceneLayerColorBlendPipeline?,
        mainPass: SceneMainPassEncoder
    ) -> Bool {
        let blendMode = layer.colorBlendMode ?? 0
        guard supports(blendMode) else { return false }
        if blendMode == 0 {
            guard let encoder = mainPass.encoder() else { return false }
            pipeline.bind(encoder: encoder)
            pipeline.drawLayer(
                texture: texture,
                shakeMaskTexture: nil,
                waterMaskTexture: masks.water,
                foliageMaskTexture: masks.foliage,
                auxMaskTexture: masks.iris ?? masks.opacity,
                dependencyTexture: dependencyTexture,
                mvp: mvp,
                uniforms: uniforms,
                encoder: encoder
            )
            return true
        }

        guard let colorBlendPipeline else { return false }
        let captured = mainPass.withReadableTarget { target, commandBuffer in
            colorBlendPipeline.snapshot(target: target, commandBuffer: commandBuffer)
        }
        guard let background = captured ?? nil,
              let encoder = mainPass.encoder() else {
            return false
        }
        colorBlendPipeline.draw(
            layerTexture: texture,
            backgroundTexture: background,
            blendMode: blendMode,
            mvp: mvp,
            encoder: encoder
        )
        return true
    }
}
