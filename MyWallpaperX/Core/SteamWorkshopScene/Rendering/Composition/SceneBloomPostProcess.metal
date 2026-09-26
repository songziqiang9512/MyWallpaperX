#include <metal_stdlib>
using namespace metal;

// Fixed product shaders for the scene-level bloom post process. Ported from
// the MirageWallpaper reference LDR bloom chain (downsample_quarter_bloom /
// downsample_eighth_blur_v / blur_h_bloom / combine), user-directed 2026-09-26.

struct SceneBloomVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct SceneBloomBrightUniforms {
    float2 texelSize;
    float strength;
    float threshold;
    float3 tint;
};

struct SceneBloomBlurUniforms {
    float2 texelSize;
    float2 direction;
};

constant static float sceneBloomBlurWeights[13] = {
    0.006299, 0.017298, 0.039533, 0.075189, 0.119007, 0.156756, 0.171834,
    0.156756, 0.119007, 0.075189, 0.039533, 0.017298, 0.006299,
};

vertex SceneBloomVaryings sceneBloomVertex(uint vertexID [[vertex_id]]) {
    // Fullscreen quad as a 4-vertex triangle strip (NDC, identity transform,
    // matching the reference post-process "effect" camera).
    float x = (vertexID == 1 || vertexID == 3) ? 1.0 : -1.0;
    float y = (vertexID >= 2) ? 1.0 : -1.0;
    float2 p = float2(x, y);
    SceneBloomVaryings result;
    result.position = float4(p, 0.0, 1.0);
    // Metal texture coordinates are Y-up while the quad's Y grows upward in
    // NDC; v maps directly.
    result.texcoord = (p + 1.0) * 0.5;
    return result;
}

fragment float4 sceneBloomBrightFragment(
    SceneBloomVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant SceneBloomBrightUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler bilinearSampler(
        mag_filter::linear, min_filter::linear,
        address::clamp_to_edge, coord::normalized
    );
    float2 texel = uniforms.texelSize;
    float3 albedo =
        source.sample(bilinearSampler, input.texcoord + float2(-texel.x, -texel.y)).rgb
        + source.sample(bilinearSampler, input.texcoord + float2(texel.x, texel.y)).rgb
        + source.sample(bilinearSampler, input.texcoord + float2(-texel.x, texel.y)).rgb
        + source.sample(bilinearSampler, input.texcoord + float2(texel.x, -texel.y)).rgb;
    albedo *= 0.25;

    float scale = max(albedo.x, max(albedo.y, albedo.z));
    albedo *= saturate(scale - uniforms.threshold);

    // Saturation boost (reference: stackoverflow.com/a/34183839, sat = 1).
    float grayscale = dot(float3(0.2989, 0.5870, 0.1140), albedo);
    albedo = albedo * 2.0 - grayscale;

    return float4(max(float3(0.0), albedo * uniforms.strength * uniforms.tint), 1.0);
}

fragment float4 sceneBloomBlurFragment(
    SceneBloomVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant SceneBloomBlurUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler bilinearSampler(
        mag_filter::linear, min_filter::linear,
        address::clamp_to_edge, coord::normalized
    );
    // The reference spreads taps 8 texels apart at the working resolution.
    float2 step = uniforms.direction * uniforms.texelSize * 8.0;
    float3 albedo = 0.0;
    for (int index = 0; index < 13; index++) {
        float2 offset = step * float(index - 6);
        albedo += source.sample(bilinearSampler, input.texcoord + offset).rgb
            * sceneBloomBlurWeights[index];
    }
    return float4(albedo, 1.0);
}

fragment float4 sceneBloomCombineFragment(
    SceneBloomVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> bloom [[texture(1)]]
) {
    constexpr sampler bilinearSampler(
        mag_filter::linear, min_filter::linear,
        address::clamp_to_edge, coord::normalized
    );
    float3 albedo = source.sample(bilinearSampler, input.texcoord).rgb;
    albedo += bloom.sample(bilinearSampler, input.texcoord).rgb;
    return float4(albedo, 1.0);
}
