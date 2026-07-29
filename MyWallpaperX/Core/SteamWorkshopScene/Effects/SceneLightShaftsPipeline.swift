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
    float3 effectCoord;
};

struct LightShaftsPerspectiveUniforms {
    float4 effectUVRow0;
    float4 effectUVRow1;
    float4 effectUVRow2;
};

struct LightShaftsUniforms {
    float2 scale;
    float2 feather;
    float radius;
    float noiseAmount;
    float noiseScale;
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
    constant float4x4 &mvp [[buffer(1)]],
    constant LightShaftsPerspectiveUniforms &u [[buffer(2)]]
) {
    LightShaftsVaryings out;
    out.position = mvp * float4(vertices[vertexID].position, 0.0, 1.0);
    float3 base = float3(vertices[vertexID].texcoord, 1.0);
    out.effectCoord = float3(
        dot(u.effectUVRow0.xyz, base),
        dot(u.effectUVRow1.xyz, base),
        dot(u.effectUVRow2.xyz, base)
    );
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
    float2 uv = input.effectCoord.xy / input.effectCoord.z;
    float profile = 0.0;
    float baseWidth = (
        0.015 + saturate(u.radius) * 0.09 + saturate(u.smoothness) * 0.006
    ) / sqrt(max(u.scale.x, 0.1));
    float phase = u.time * u.speed * (0.65 + max(u.scale.y, 0.0) * 0.35);
    for (uint index = 0; index < 6; ++index) {
        float ray = float(index);
        float2 seedCoord = fract(float2(
            0.13 + ray * 0.173 * max(u.noiseScale, 0.01),
            0.27 + ray * 0.319 + u.noiseScale * 0.071
        ));
        float3 seed = noiseTexture.sample(repeatSampler, seedCoord).rgb;
        float rayPhase = phase + ray * 2.3999632
            + (seed.b - 0.5) * u.noiseAmount * 0.8;
        float pulse = smoothstep(0.22, 0.78, 0.5 + 0.5 * sin(rayPhase));
        pulse = mix(0.18, 1.0, pulse);
        float center = (ray + 0.5) / 6.0
            + (seed.r - 0.5) * u.noiseAmount * 0.12
            + sin(rayPhase * 0.47) * u.noiseAmount * 0.012;
        float width = baseWidth * mix(0.78, 1.22, seed.g);
        float distance = (uv.x - center) / max(width, 0.001);
        float band = exp(-0.5 * distance * distance);
        profile += band * pulse * mix(0.78, 1.18, seed.r);
    }
    float structure = saturate(profile * 0.8);
    float contrast = mix(1.7, 0.8, saturate(u.smoothness));
    float shafts = pow(structure, contrast);
    shafts = pow(max(shafts, 0.0), max(u.exponent, 0.01));

    float2 edgeWidth = max(u.feather, float2(0.0001));
    float horizontal = smoothstep(0.0, edgeWidth.x, uv.x)
        * smoothstep(0.0, edgeWidth.x, 1.0 - uv.x);
    float topFade = smoothstep(0.0, max(edgeWidth.y * 0.35, 0.0001), uv.y);
    float reachExponent = mix(0.35, 1.1, saturate(edgeWidth.y * 2.0));
    float longitudinal = topFade * pow(saturate(1.0 - uv.y), reachExponent);
    float opacity = saturate(
        shafts * horizontal * longitudinal * min(max(u.intensity, 0.0), 1.0) * 0.58
    ) * u.alpha;
    float3 gradient = gradientTexture.sample(
        clampSampler,
        float2(saturate(uv.y), 0.5)
    ).rgb;
    float luminance = dot(gradient, float3(0.2126, 0.7152, 0.0722));
    float3 softenedGradient = mix(float3(luminance), gradient, 0.55);
    float3 litColor = saturate(softenedGradient * max(u.intensity, 1.0));
    return float4(litColor * opacity, opacity);
}
"""

final class SceneLightShaftsPipeline {
    private struct PerspectiveUniforms {
        var effectUVRow0: SIMD4<Float>
        var effectUVRow1: SIMD4<Float>
        var effectUVRow2: SIMD4<Float>
    }

    private struct Uniforms {
        var scale: SIMD2<Float>
        var feather: SIMD2<Float>
        var radius: Float
        var noiseAmount: Float
        var noiseScale: Float
        var smoothness: Float
        var speed: Float
        var intensity: Float
        var exponent: Float
        var time: Float
        var alpha: Float
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64
    static let unitQuadVertices: [SceneQuadVertex] = [
        .init(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        .init(position: SIMD2(0.5, -0.5), texcoord: SIMD2(1, 1)),
        .init(position: SIMD2(-0.5, 0.5), texcoord: SIMD2(0, 0)),
        .init(position: SIMD2(0.5, 0.5), texcoord: SIMD2(1, 0)),
    ]

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
        var vertices = Self.unitQuadVertices
        var mvpCopy = mvp
        var perspective = PerspectiveUniforms(
            effectUVRow0: SIMD4(plan.effectUVTransform.row0, 0),
            effectUVRow1: SIMD4(plan.effectUVTransform.row1, 0),
            effectUVRow2: SIMD4(plan.effectUVTransform.row2, 0)
        )
        var uniforms = Uniforms(
            scale: plan.scale,
            feather: plan.feather,
            radius: plan.radius,
            noiseAmount: plan.noiseAmount,
            noiseScale: plan.noiseScale,
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
        encoder.setVertexBytes(
            &perspective,
            length: MemoryLayout<PerspectiveUniforms>.stride,
            index: 2
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

    private func valid(
        plan: SceneLightShaftsExecutionPlan,
        time: Float,
        alpha: Float
    ) -> Bool {
        let points = [plan.points.0, plan.points.1, plan.points.2, plan.points.3]
        return points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            && plan.effectUVTransform.isFinite
            && plan.feather.x.isFinite && plan.feather.y.isFinite
            && plan.scale.x.isFinite && plan.scale.y.isFinite
            && plan.radius.isFinite
            && plan.noiseAmount.isFinite
            && plan.noiseScale.isFinite
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
