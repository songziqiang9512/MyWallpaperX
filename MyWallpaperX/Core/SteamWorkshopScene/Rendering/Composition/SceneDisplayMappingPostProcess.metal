#include <metal_stdlib>
using namespace metal;

// D2 stage B — fixed product shaders for the terminal SDR knee/shoulder
// display mapping. Applied once at the unique compositor output over
// display-referred sRGB values (no transfer or primaries transform).

struct SceneDisplayMappingVaryings {
    float4 position [[position]];
    float2 texcoord;
};

// Same finite-input contract as SceneDisplayMappingCurve. Author shaders can
// produce non-finite channels; keep those local to the affected channel.
float sceneDisplayMapChannel(float c) {
    if (!isfinite(c) || c <= 0.0) return 0.0;
    return c <= 0.5 ? c : 1.0 - 0.25 / c;
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
    texture2d<float> source [[texture(0)]]
) {
    // Nearest sampling keeps texel identity for this 1:1 terminal pass.
    constexpr sampler pointSampler(
        mag_filter::nearest, min_filter::nearest,
        address::clamp_to_edge, coord::normalized
    );
    float4 sampleValue = source.sample(pointSampler, input.texcoord);
    float3 mapped = float3(
        sceneDisplayMapChannel(sampleValue.r),
        sceneDisplayMapChannel(sampleValue.g),
        sceneDisplayMapChannel(sampleValue.b));
    // Product input is the opaque composite cleared with alpha=1. Copy alpha;
    // nonlinear RGB mapping does not preserve arbitrary premultiplied edges.
    return float4(mapped, sampleValue.a);
}
