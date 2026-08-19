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
    float4 startColor;
    float4 endColor;
    float2 scale;
    float2 feather;
    float radius;
    float noiseAmount;
    float noiseScale;
    float smoothness;
    float speed;
    float intensity;
    float exponent;
    float startAngle;
    float endAngle;
    float profileMode;
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
    if (u.profileMode > 0.5) {
        float2 ray = float2(
            (uv.x - 0.5) / max(u.scale.x, 0.1),
            (1.0 - uv.y) / max(u.scale.y, 0.1)
        );
        float distanceFromOrigin = length(ray);
        float angle = atan2(ray.x, max(ray.y, 0.0001));
        float fanStart = mix(-0.62, 0.62, saturate(u.startAngle));
        float fanEnd = mix(-0.62, 0.62, saturate(u.endAngle));
        float angularWidth = 0.012 + saturate(u.radius) * 0.07
            + saturate(u.smoothness) * 0.008;
        float phase = u.time * u.speed;
        float profile = 0.0;
        for (uint index = 0; index < 7; ++index) {
            float beam = float(index);
            float2 seedCoord = fract(float2(
                0.19 + beam * 0.157 * max(u.noiseScale, 0.01),
                0.31 + beam * 0.271 + u.noiseScale * 0.083
            ));
            float3 seed = noiseTexture.sample(repeatSampler, seedCoord).rgb;
            float center = mix(fanStart, fanEnd, (beam + 0.5) / 7.0);
            center += sin(
                phase * (0.72 + beam * 0.05) + beam * 1.71 + seed.b * 6.2831853
            ) * mix(0.025, 0.075, saturate(u.noiseAmount));
            float width = angularWidth * mix(0.76, 1.24, seed.g);
            float delta = (angle - center) / max(width, 0.001);
            float band = exp(-0.5 * delta * delta);
            float strength = 0.72 + 0.18 * sin(phase * 0.41 + beam * 2.11);
            profile += band * strength * mix(0.82, 1.12, seed.r);
        }
        float shafts = pow(
            saturate(profile * 0.82),
            mix(1.45, 0.82, saturate(u.smoothness))
        );
        if (u.exponent > 0.001) {
            shafts = pow(max(shafts, 0.0), u.exponent);
        }
        float originFade = smoothstep(
            0.01,
            0.055 + saturate(u.feather.y) * 0.3,
            distanceFromOrigin
        );
        float reach = 1.0 - smoothstep(0.62, 1.38, distanceFromOrigin);
        float edgeWidth = max(u.feather.x, 0.02);
        float horizontal = smoothstep(0.0, edgeWidth, uv.x)
            * smoothstep(0.0, edgeWidth, 1.0 - uv.x);
        float opacity = min(
            shafts * originFade * reach * horizontal
                * min(max(u.intensity, 0.0), 1.4) * 0.32,
            0.48
        ) * u.alpha;
        float colorMix = saturate(distanceFromOrigin * 0.85);
        float3 color = mix(u.startColor.rgb, u.endColor.rgb, colorMix);
        return float4(saturate(color * max(u.intensity, 1.0)) * opacity, opacity);
    }

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
        var startColor: SIMD4<Float>
        var endColor: SIMD4<Float>
        var scale: SIMD2<Float>
        var feather: SIMD2<Float>
        var radius: Float
        var noiseAmount: Float
        var noiseScale: Float
        var smoothness: Float
        var speed: Float
        var intensity: Float
        var exponent: Float
        var startAngle: Float
        var endAngle: Float
        var profileMode: Float
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
              valid(texture: noise),
              valid(plan: plan, time: time, alpha: alpha),
              noise.device.registryID == deviceRegistryID,
              validGradient(resources.gradient, for: plan) else {
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
            startColor: SIMD4(plan.startColor, 1),
            endColor: SIMD4(plan.endColor, 1),
            scale: plan.scale,
            feather: plan.feather,
            radius: plan.radius,
            noiseAmount: plan.noiseAmount,
            noiseScale: plan.noiseScale,
            smoothness: plan.smoothness,
            speed: plan.speed,
            intensity: plan.intensity,
            exponent: plan.exponent,
            startAngle: plan.startAngle,
            endAngle: plan.endAngle,
            profileMode: plan.profile.rawValue,
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
        encoder.setFragmentTexture(resources.gradient, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        return true
    }

    func renderOffscreen(
        plan: SceneLightShaftsExecutionPlan,
        resources: SceneLightShaftsEffectTextures,
        target: MTLTexture,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard target.pixelFormat == .bgra8Unorm,
              target.textureType == .type2D,
              target.usage.contains(.renderTarget),
              target.width > 0,
              target.height > 0,
              target.device.registryID == deviceRegistryID,
              commandBuffer.status == .notEnqueued,
              commandBuffer.commandQueue.device.registryID == deviceRegistryID else {
            return nil
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = .init(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else { return nil }
        encoder.label = "Scene Light Shafts unified pair leaf"
        let encoded = draw(
            plan: plan,
            resources: resources,
            mvp: simd_float4x4(columns: (
                SIMD4<Float>(2, 0, 0, 0),
                SIMD4<Float>(0, 2, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(0, 0, 0, 1)
            )),
            time: time,
            alpha: 1,
            encoder: encoder
        )
        encoder.endEncoding()
        return encoded ? target : nil
    }

    private func valid(
        plan: SceneLightShaftsExecutionPlan,
        time: Float,
        alpha: Float
    ) -> Bool {
        let points = [plan.points.0, plan.points.1, plan.points.2, plan.points.3]
        return points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
            && plan.effectUVTransform.isFinite
            && plan.startColor.x.isFinite
            && plan.startColor.y.isFinite
            && plan.startColor.z.isFinite
            && plan.endColor.x.isFinite
            && plan.endColor.y.isFinite
            && plan.endColor.z.isFinite
            && plan.feather.x.isFinite && plan.feather.y.isFinite
            && plan.scale.x.isFinite && plan.scale.y.isFinite
            && plan.radius.isFinite
            && plan.noiseAmount.isFinite
            && plan.noiseScale.isFinite
            && plan.smoothness.isFinite
            && plan.speed.isFinite
            && plan.intensity.isFinite
            && plan.exponent.isFinite
            && plan.startAngle.isFinite
            && plan.endAngle.isFinite
            && time.isFinite
            && alpha.isFinite
            && (0...1).contains(alpha)
    }

    private func validGradient(
        _ gradient: MTLTexture?,
        for plan: SceneLightShaftsExecutionPlan
    ) -> Bool {
        guard plan.profile.requiresGradientTexture else { return true }
        guard let gradient else { return false }
        return valid(texture: gradient)
            && gradient.device.registryID == deviceRegistryID
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
