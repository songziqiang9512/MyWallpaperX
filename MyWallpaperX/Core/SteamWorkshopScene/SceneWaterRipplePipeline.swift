import Metal
import simd

private struct SceneWaterRippleUniforms {
    let time: Float
    let sourceAspect: Float
    let animationSpeed: Float
    let scale: Float
    let scrollSpeed: Float
    let direction: Float
    let ratio: Float
    let strength: Float
}

private let sceneWaterRippleShader = """
#include <metal_stdlib>
using namespace metal;

struct QuadVertex {
    float2 position;
    float2 texcoord;
};

struct WaterRippleUniforms {
    float time;
    float sourceAspect;
    float animationSpeed;
    float scale;
    float scrollSpeed;
    float direction;
    float ratio;
    float strength;
};

struct WaterRippleVaryings {
    float4 position [[position]];
    float2 uv;
};

vertex WaterRippleVaryings sceneWaterRippleVert(
    uint vid [[vertex_id]],
    constant QuadVertex *verts [[buffer(0)]]
) {
    WaterRippleVaryings out;
    out.position = float4(verts[vid].position * 2.0, 0.0, 1.0);
    out.uv = verts[vid].texcoord;
    return out;
}

fragment float4 sceneWaterRippleFrag(
    WaterRippleVaryings in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> normalMap [[texture(1)]],
    constant WaterRippleUniforms &u [[buffer(0)]]
) {
    constexpr sampler sourceSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler normalSampler(filter::linear, address::repeat);
    float animation = u.time * u.animationSpeed * u.animationSpeed;
    float2 scrollDirection = float2(-sin(u.direction), cos(u.direction));
    float2 scroll = scrollDirection * u.scrollSpeed * u.scrollSpeed * u.time;
    float2 rippleUV1 = (in.uv + animation + scroll) * u.scale;
    float2 rippleUV2 = (in.uv * 1.333 - animation + scroll) * u.scale;
    rippleUV1 *= float2(u.sourceAspect, u.ratio);
    rippleUV2 *= float2(u.sourceAspect, u.ratio);
    float3 n1 = normalMap.sample(normalSampler, rippleUV1).xyz * 2.0 - 1.0;
    float3 n2 = normalMap.sample(normalSampler, rippleUV2).xyz * 2.0 - 1.0;
    float3 normal = normalize(float3(n1.xy + n2.xy, n1.z));
    float2 sourceUV = in.uv + normal.xy * u.strength * u.strength;
    return source.sample(sourceSampler, sourceUV);
}
"""

struct SceneWaterRipplePipeline {
    private let state: MTLRenderPipelineState
    private let vertices: [SceneQuadVertex] = [
        .init(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        .init(position: SIMD2(0.5, -0.5), texcoord: SIMD2(1, 1)),
        .init(position: SIMD2(-0.5, 0.5), texcoord: SIMD2(0, 0)),
        .init(position: SIMD2(0.5, 0.5), texcoord: SIMD2(1, 0))
    ]

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let library = try? device.makeLibrary(source: sceneWaterRippleShader, options: nil),
              let vertex = library.makeFunction(name: "sceneWaterRippleVert"),
              let fragment = library.makeFunction(name: "sceneWaterRippleFrag") else {
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
        normalMap: MTLTexture,
        target: MTLTexture,
        plan: SceneWaterRippleNormalPlan,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        var vertexCopy = vertices
        var uniforms = SceneWaterRippleUniforms(
            time: time,
            sourceAspect: Float(source.width) / Float(max(source.height, 1)),
            animationSpeed: plan.animationSpeed,
            scale: plan.scale,
            scrollSpeed: plan.scrollSpeed,
            direction: plan.direction,
            ratio: plan.ratio,
            strength: plan.strength
        )
        encoder.setRenderPipelineState(state)
        encoder.setVertexBytes(&vertexCopy, length: MemoryLayout<SceneQuadVertex>.stride * vertexCopy.count, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneWaterRippleUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(normalMap, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCopy.count)
        encoder.endEncoding()
        return true
    }
}
