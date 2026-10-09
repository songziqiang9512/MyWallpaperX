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
    float strength;
    float threshold;
    float3 tint;
};

struct SceneBloomBlurUniforms {
    float2 direction;
    float2 stepUV;
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
    // Metal texture V grows downward while NDC Y grows upward — flip V so
    // the top-left of the screen samples the top-left of the source.
    result.texcoord = float2((p.x + 1.0) * 0.5, (1.0 - p.y) * 0.5);
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
    // Keep the extraction footprint tied to the completed source resolution.
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
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
    // The caller expresses spacing in completed-source pixels for both axes,
    // independent of this pass's downsampled input texture dimensions.
    float2 step = uniforms.direction * uniforms.stepUV;
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
    texture2d<float> bloom [[texture(0)]]
) {
    constexpr sampler bilinearSampler(
        mag_filter::linear, min_filter::linear,
        address::clamp_to_edge, coord::normalized
    );
    // Additive contribution only: the pass renders onto the completed
    // composite with RGB blend += so the base never round-trips through an
    // extra full-resolution texture.
    return float4(bloom.sample(bilinearSampler, input.texcoord).rgb, 0.0);
}

// Independent HDR Bloom reconstruction. The author parameters select energy,
// a soft threshold and spatial scales; EDR display transfer belongs elsewhere.
struct SceneBloomHDRUniforms {
    float threshold;
    float feather;
    float reconstructionScale;
    float strength;
    float3 tint;
};

constant constexpr sampler sceneBloomHDRSampler(
    mag_filter::linear, min_filter::linear, address::clamp_to_edge, coord::normalized
);

static float3 sceneBloomHDRFinite(float3 value) {
    return clamp(select(float3(0.0), value, isfinite(value)), 0.0, 65504.0);
}

static float3 sceneBloomHDRTent(texture2d<float> source, float2 uv, float radius = 1.0) {
    float2 texel = radius / float2(source.get_width(), source.get_height());
    float3 sum = 0.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float weight = (x == 0 ? 2.0 : 1.0) * (y == 0 ? 2.0 : 1.0);
            sum += sceneBloomHDRFinite(source.sample(sceneBloomHDRSampler,
                uv + float2(x, y) * texel).rgb) * (weight / 16.0);
        }
    }
    return sum;
}

fragment float4 sceneBloomHDRBrightFragment(
    SceneBloomVaryings input [[stage_in]], texture2d<float> source [[texture(0)]],
    constant SceneBloomHDRUniforms &uniforms [[buffer(0)]]
) {
    // Cover the two-source-texel footprint before thresholding the half-size target.
    float3 color = sceneBloomHDRTent(source, input.texcoord, 2.0);
    float brightness = max(color.r, max(color.g, color.b));
    float threshold = max(0.0, uniforms.threshold);
    float knee = threshold * clamp(uniforms.feather, 0.0, 1.0);
    float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = knee > 0.0 ? soft * soft / (4.0 * knee) : 0.0;
    float contribution = max(brightness - threshold, soft);
    return float4(color * (max(0.0, contribution) / max(brightness, 0.00001)), 1.0);
}

fragment float4 sceneBloomHDRDownsampleFragment(
    SceneBloomVaryings input [[stage_in]], texture2d<float> source [[texture(0)]]
) {
    return float4(sceneBloomHDRTent(source, input.texcoord), 1.0);
}

struct SceneBloomHDRReconstructionUniforms {
    float fineWeight;
    float coarseWeight;
};

fragment float4 sceneBloomHDRUpsampleFragment(
    SceneBloomVaryings input [[stage_in]], texture2d<float> smaller [[texture(0)]],
    texture2d<float> current [[texture(1)]],
    constant SceneBloomHDRReconstructionUniforms &uniforms [[buffer(0)]]
) {
    float3 fine = current.sample(sceneBloomHDRSampler, input.texcoord).rgb;
    float3 coarse = sceneBloomHDRTent(smaller, input.texcoord);
    return float4(clamp(fine * uniforms.fineWeight + coarse * uniforms.coarseWeight, 0.0, 65504.0), 1.0);
}

fragment float4 sceneBloomHDRCombineFragment(
    SceneBloomVaryings input [[stage_in]], texture2d<float> bloom [[texture(0)]],
    constant SceneBloomHDRUniforms &uniforms [[buffer(0)]]
) {
    float3 color = bloom.sample(sceneBloomHDRSampler, input.texcoord).rgb;
    float intensity = uniforms.strength;
    float3 tint = select(float3(0.0), max(uniforms.tint, 0.0), isfinite(uniforms.tint));
    // Sort four positive factors and pair the smallest with the largest.
    // This preserves small-color/large-scale products until the final storage
    // saturation, without capping authored strength, scatter or tint.
    float3 a = min(color, intensity), b = max(color, intensity);
    float3 c = min(tint, uniforms.reconstructionScale), d = max(tint, uniforms.reconstructionScale);
    float3 low = min(a, c), high = max(b, d);
    float3 middleLow = min(max(a, c), min(b, d));
    float3 middleHigh = max(max(a, c), min(b, d));
    float3 contribution = (low * high) * (middleLow * middleHigh);
    contribution = select(contribution, float3(0.0), low == 0.0);
    return float4(clamp(contribution, 0.0, 65504.0), 0.0);
}
