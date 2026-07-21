import Metal
import simd

struct ScenePerspectiveOpacityPlan {
    let edges: SIMD4<Float>
    let weights: SIMD4<Float>
    let opacity: Float
}

private struct ScenePerspectiveOpacityUniforms {
    let edges: SIMD4<Float>
    let weights: SIMD4<Float>
    let opacity: Float
    let repeats: UInt32
    let padding: SIMD2<Float> = .zero
}

private let scenePerspectiveOpacityShader = """
#include <metal_stdlib>
using namespace metal;

struct QuadVertex {
    float2 position;
    float2 texcoord;
};

struct PerspectiveOpacityUniforms {
    float4 edges;
    float4 weights;
    float opacity;
    uint repeats;
    float2 padding;
};

struct PerspectiveVaryings {
    float4 position [[position]];
    float3 projectedUV;
    float2 opacityUV;
};

vertex PerspectiveVaryings scenePerspectiveOpacityVert(
    uint vid [[vertex_id]],
    constant QuadVertex *verts [[buffer(0)]],
    constant PerspectiveOpacityUniforms &u [[buffer(1)]]
) {
    float2 uv = verts[vid].texcoord;
    float top = u.edges.x;
    float bottom = u.edges.y;
    float left = u.edges.z;
    float right = u.edges.w;
    float xSide = step(0.5, uv.x);
    float ySide = step(0.5, uv.y);

    float2 warped = uv - 0.5;
    warped.x *= 0.5 / (0.5 - mix(top, bottom, ySide));
    warped.y *= 0.5 / (0.5 - mix(left, right, xSide));
    warped += 0.5;

    float qTop = mix(u.weights.w, u.weights.z, uv.x);
    float qBottom = mix(u.weights.x, u.weights.y, uv.x);
    float q = mix(qTop, qBottom, uv.y);

    PerspectiveVaryings out;
    out.position = float4(verts[vid].position * 2.0, 0.0, 1.0);
    out.projectedUV = float3(warped * q, q);
    out.opacityUV = uv;
    return out;
}

fragment float4 scenePerspectiveOpacityFrag(
    PerspectiveVaryings in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> opacityMask [[texture(1)]],
    constant PerspectiveOpacityUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float q = max(abs(in.projectedUV.z), 0.000001);
    float2 sourceUV = in.projectedUV.xy / q;
    if (u.repeats != 0u) {
        sourceUV = fract(sourceUV);
    }
    float4 color = source.sample(linearClamp, sourceUV);
    float opacity = opacityMask.sample(linearClamp, in.opacityUV).r * u.opacity;
    return color * opacity;
}
"""

struct ScenePerspectiveOpacityPipeline {
    private let state: MTLRenderPipelineState
    private let vertices: [SceneQuadVertex] = [
        .init(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        .init(position: SIMD2(0.5, -0.5), texcoord: SIMD2(1, 1)),
        .init(position: SIMD2(-0.5, 0.5), texcoord: SIMD2(0, 0)),
        .init(position: SIMD2(0.5, 0.5), texcoord: SIMD2(1, 0))
    ]

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let library = try? device.makeLibrary(source: scenePerspectiveOpacityShader, options: nil),
              let vertex = library.makeFunction(name: "scenePerspectiveOpacityVert"),
              let fragment = library.makeFunction(name: "scenePerspectiveOpacityFrag") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.state = state
    }

    func encode(
        source: MTLTexture,
        opacityMask: MTLTexture,
        target: MTLTexture,
        plan: ScenePerspectiveOpacityPlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        var vertexCopy = vertices
        var uniforms = ScenePerspectiveOpacityUniforms(
            edges: plan.edges,
            weights: plan.weights,
            opacity: plan.opacity,
            repeats: 1
        )
        encoder.setRenderPipelineState(state)
        encoder.setVertexBytes(&vertexCopy, length: MemoryLayout<SceneQuadVertex>.stride * vertexCopy.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ScenePerspectiveOpacityUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ScenePerspectiveOpacityUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(opacityMask, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCopy.count)
        encoder.endEncoding()
        return true
    }
}
