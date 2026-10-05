#include <metal_stdlib>
using namespace metal;

// SDR export of the already-composited display-referred sRGB scene.
// Preserve ordinary colors and white; HDR overbrightening has already
// contributed to Bloom. The surface supplies its fixed transfer and headroom.

struct SceneDisplayMappingVaryings {
    float4 position [[position]];
    float2 texcoord;
};

// Author shaders can produce non-finite channels; keep the failure local.
float sceneDisplayMapChannel(float c, float linearHeadroom) {
    if (!isfinite(c) || c <= 0.0) return 0.0;
    if (linearHeadroom == 0.0) return min(c, 1.0);
    // Decode only at the terminal: raw/history and authored blending stay in
    // their established display-referred domain. Bound before pow as well.
    float encodedLimit = 1.055 * pow(linearHeadroom, 1.0 / 2.4) - 0.055;
    c = min(c, encodedLimit);
    float linear = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
    return min(linear, linearHeadroom);
}

vertex SceneDisplayMappingVaryings sceneDisplayMappingVertex(
    uint vertexID [[vertex_id]]
) {
    // Fullscreen quad as a 4-vertex triangle strip (NDC, identity transform),
    // same shape as the bloom post-process "effect" camera.
    float x = (vertexID == 1 || vertexID == 3) ? 1.0 : -1.0;
    float y = (vertexID >= 2) ? 1.0 : -1.0;
    float2 p = float2(x, y);
    SceneDisplayMappingVaryings result;
    result.position = float4(p, 0.0, 1.0);
    // Metal texture V grows downward while NDC Y grows upward — flip V so
    // the top-left of the screen samples the top-left of the source.
    result.texcoord = float2((p.x + 1.0) * 0.5, (1.0 - p.y) * 0.5);
    return result;
}

fragment float4 sceneDisplayMappingFragment(
    SceneDisplayMappingVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant float &linearHeadroom [[buffer(0)]]
) {
    // Nearest sampling keeps texel identity for this 1:1 terminal pass.
    constexpr sampler pointSampler(
        mag_filter::nearest, min_filter::nearest,
        address::clamp_to_edge, coord::normalized
    );
    float4 sampleValue = source.sample(pointSampler, input.texcoord);
    float3 mapped = float3(
        sceneDisplayMapChannel(sampleValue.r, linearHeadroom),
        sceneDisplayMapChannel(sampleValue.g, linearHeadroom),
        sceneDisplayMapChannel(sampleValue.b, linearHeadroom));
    // Product input is the opaque composite cleared with alpha=1. Copy alpha;
    // saturation does not establish arbitrary transparent-output semantics.
    return float4(mapped, sampleValue.a);
}
