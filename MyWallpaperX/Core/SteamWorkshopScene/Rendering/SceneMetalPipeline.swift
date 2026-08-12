import Metal
import simd

// Quad vertex laid out to match the MSL struct QuadVertex below.
// Position is in model space (unit quad centered at origin); the model
// matrix scales it to the layer's size and places it in world space.
struct SceneQuadVertex {
    var position: SIMD2<Float>
    var texcoord: SIMD2<Float>
}

enum SceneLayerBlendMode {
    case sourceOver
    case additive
}

// Per-layer uniform packed for setFragmentBytes. Layout matches MSL struct
// LayerFragmentUniforms below; all vector fields stay 16-byte aligned.
struct SceneLayerFragmentUniforms {
    var time: Float
    var alpha: Float
    var dependencyBlendMode: UInt32
    var usesDependencyBlend: UInt32
    var cursorUV: SIMD2<Float>   // cursor in layer-local UV space ([0..1])
    var _pad1: SIMD2<Float>      // pad to 32 bytes
    var tint: SIMD4<Float>
    var textureFrame0: SIMD4<Float>
    var textureFrame1: SIMD4<Float>
}

// Embedded MSL. Vertex shader transforms a unit quad by an MVP supplied in
// buffer(1). Fragment shader only samples the base layer and performs the
// structural dependency blend used by the graph compositor. Effects execute
// exclusively through SceneResolvedMaterialGraphExecutor.
private let imageLayerShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct QuadVertex {
    float2 position;
    float2 texcoord;
};

struct QuadVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct LayerFragmentUniforms {
    float time;
    float alpha;
    uint  dependencyBlendMode;
    uint  usesDependencyBlend;
    float2 cursorUV;
    float2 _pad1;
    float4 tint;
    float4 textureFrame0;
    float4 textureFrame1;
};

float2 textureFrameUV(float2 uv, constant LayerFragmentUniforms &u) {
    return u.textureFrame0.xy
        + uv.x * u.textureFrame0.zw
        + uv.y * u.textureFrame1.xy;
}

vertex QuadVaryings sceneImageLayerVert(
    uint vid [[vertex_id]],
    constant QuadVertex *verts [[buffer(0)]],
    constant float4x4 &mvp [[buffer(1)]]
) {
    QuadVaryings out;
    out.position = mvp * float4(verts[vid].position, 0.0, 1.0);
    out.texcoord = verts[vid].texcoord;
    return out;
}

fragment float4 sceneImageLayerFrag(
    QuadVaryings in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    texture2d<float> dependencyTex [[texture(1)]],
    constant LayerFragmentUniforms &u [[buffer(0)]]
) {
    constexpr sampler s(
        min_filter::linear,
        mag_filter::linear,
        mip_filter::linear,
        address::clamp_to_edge
    );
    float4 color = tex.sample(s, textureFrameUV(clamp(in.texcoord, 0.0, 1.0), u));
    if (u.usesDependencyBlend != 0u) {
        float3 target = dependencyTex.sample(s, clamp(in.texcoord, 0.0, 1.0)).rgb;
        if (u.dependencyBlendMode == 0u) {
            color.rgb = mix(color.rgb, target, color.a);
        } else if (u.dependencyBlendMode == 5u) {
            color.rgb = min(color.rgb, target);
        }
    }

    return color * u.tint * u.alpha;
}
"""

struct SceneImageLayerPipeline {
    let state: MTLRenderPipelineState

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
        blendMode: SceneLayerBlendMode = .sourceOver
    ) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(source: imageLayerShaderSource, options: options),
              let vertFn = library.makeFunction(name: "sceneImageLayerVert"),
              let fragFn = library.makeFunction(name: "sceneImageLayerFrag") else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertFn
        descriptor.fragmentFunction = fragFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        // Premultiplied source-over: data was uploaded via CGContext with
        // premultipliedLast, so rgb is already alpha-scaled.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = blendMode == .additive ? .one : .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.state = state
    }

    // Sets pipeline state + vertex quad buffer once per encoder. Call drawLayer
    // per layer after binding.
    func bind(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(state)
        var vertices = Self.unitQuadVertices
        encoder.setVertexBytes(
            &vertices,
            length: vertices.count * MemoryLayout<SceneQuadVertex>.stride,
            index: 0
        )
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
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
