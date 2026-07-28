import Metal
import simd

private let sceneLightShaftsShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct LightShaftsVertex {
    float2 position;
    float2 texcoord;
};

struct LightShaftsVaryings {
    float4 position [[position]];
    float2 uv;
};

struct LightShaftsUniforms {
    float2 scale;
    float2 feather;
    float smoothness;
    float speed;
    float intensity;
    float exponent;
    float time;
    float alpha;
};

vertex LightShaftsVaryings sceneLightShaftsVert(
    uint vertexID [[vertex_id]],
    constant LightShaftsVertex *vertices [[buffer(0)]],
    constant float4x4 &mvp [[buffer(1)]]
) {
    LightShaftsVaryings out;
    out.position = mvp * float4(vertices[vertexID].position, 0.0, 1.0);
    out.uv = vertices[vertexID].texcoord;
    return out;
}

fragment float4 sceneLightShaftsFrag(
    LightShaftsVaryings input [[stage_in]],
    texture2d<float> noiseTexture [[texture(0)]],
    texture2d<float> gradientTexture [[texture(1)]],
    constant LightShaftsUniforms &u [[buffer(0)]]
) {
    constexpr sampler repeatSampler(filter::linear, address::repeat);
    constexpr sampler clampSampler(filter::linear, address::clamp_to_edge);
    float2 frequency = max(u.scale, float2(0.001)) * float2(4.0, 7.0);
    float travel = u.time * u.speed;
    float first = noiseTexture.sample(
        repeatSampler,
        input.uv * frequency + float2(travel * 0.11, travel * 0.29)
    ).r;
    float second = noiseTexture.sample(
        repeatSampler,
        float2(1.0 - input.uv.x, input.uv.y) * frequency * 0.57
            + float2(-travel * 0.19, travel * 0.41)
    ).g;
    float structure = saturate(first * 0.62 + second * 0.38);
    float threshold = mix(0.72, 0.18, u.smoothness);
    float shafts = smoothstep(threshold, 1.0, structure);
    shafts = pow(max(shafts, 0.0001), max(u.exponent, 0.01));

    float2 edgeWidth = max(u.feather, float2(0.0001));
    float horizontal = smoothstep(0.0, edgeWidth.x, input.uv.x)
        * smoothstep(0.0, edgeWidth.x, 1.0 - input.uv.x);
    float longitudinal = smoothstep(0.0, edgeWidth.y, input.uv.y)
        * smoothstep(0.0, edgeWidth.y, 1.0 - input.uv.y);
    float opacity = saturate(shafts * horizontal * longitudinal * u.intensity) * u.alpha;
    float3 gradient = gradientTexture.sample(
        clampSampler,
        float2(saturate(input.uv.y), 0.5)
    ).rgb;
    return float4(gradient * opacity, opacity);
}
"""

final class SceneLightShaftsPipeline {
    private struct Uniforms {
        var scale: SIMD2<Float>
        var feather: SIMD2<Float>
        var smoothness: Float
        var speed: Float
        var intensity: Float
        var exponent: Float
        var time: Float
        var alpha: Float
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneLightShaftsShaderSource,
                  options: MTLCompileOptions()
              ),
              let vertex = library.makeFunction(name: "sceneLightShaftsVert"),
              let fragment = library.makeFunction(name: "sceneLightShaftsFrag") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.state = state
        deviceRegistryID = device.registryID
    }

    func draw(
        plan: SceneLightShaftsExecutionPlan,
        resources: SceneLightShaftsEffectTextures,
        mvp: simd_float4x4,
        time: Float,
        alpha: Float,
        encoder: MTLRenderCommandEncoder
    ) -> Bool {
        guard resources.matches(plan),
              let noise = resources.noise,
              let gradient = resources.gradient,
              valid(texture: noise),
              valid(texture: gradient),
              valid(plan: plan, time: time, alpha: alpha),
              noise.device.registryID == deviceRegistryID,
              gradient.device.registryID == deviceRegistryID else {
            return false
        }
        var vertices = vertices(for: plan.points)
        var mvpCopy = mvp
        var uniforms = Uniforms(
            scale: plan.scale,
            feather: plan.feather,
            smoothness: plan.smoothness,
            speed: plan.speed,
            intensity: plan.intensity,
            exponent: plan.exponent,
            time: time,
            alpha: alpha
        )
        encoder.setRenderPipelineState(state)
        encoder.setVertexBytes(
            &vertices,
            length: MemoryLayout<SceneQuadVertex>.stride * vertices.count,
            index: 0
        )
        encoder.setVertexBytes(
            &mvpCopy,
            length: MemoryLayout<simd_float4x4>.size,
            index: 1
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 0
        )
        encoder.setFragmentTexture(noise, index: 0)
        encoder.setFragmentTexture(gradient, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    private func vertices(
        for points: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    ) -> [SceneQuadVertex] {
        let ordered = [points.3, points.2, points.0, points.1]
        let texcoords = [
            SIMD2<Float>(0, 1), SIMD2<Float>(1, 1),
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
        ]
        return zip(ordered, texcoords).map { point, texcoord in
            SceneQuadVertex(
                position: SIMD2((point.x - 0.5) * 1_000, (0.5 - point.y) * 1_000),
                texcoord: texcoord
            )
        }
    }

    private func valid(
        plan: SceneLightShaftsExecutionPlan,
        time: Float,
        alpha: Float
    ) -> Bool {
        let points = [plan.points.0, plan.points.1, plan.points.2, plan.points.3]
        return points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            && plan.feather.x.isFinite && plan.feather.y.isFinite
            && plan.scale.x.isFinite && plan.scale.y.isFinite
            && plan.smoothness.isFinite
            && plan.speed.isFinite
            && plan.intensity.isFinite
            && plan.exponent.isFinite
            && time.isFinite
            && alpha.isFinite
            && (0...1).contains(alpha)
    }

    private func valid(texture: MTLTexture) -> Bool {
        texture.textureType == .type2D
            && texture.width > 0
            && texture.height > 0
            && texture.sampleCount == 1
            && texture.usage.contains(.shaderRead)
            && [.r8Unorm, .rgba8Unorm, .bgra8Unorm].contains(texture.pixelFormat)
    }
}
