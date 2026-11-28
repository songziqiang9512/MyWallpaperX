#include <metal_stdlib>
using namespace metal;

struct SpotLightVertex {
    float2 position;
    float2 texcoord;
    float vertexCoverage;
};

struct SpotLightVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct SpotLightUniforms {
    float4 color;
    float innerRatio;
    float density;
    float exponent;
    float volumetricsExponent;
    float intensity;
};

vertex SpotLightVaryings sceneSpotLightVert(
    uint vertexID [[vertex_id]],
    constant SpotLightVertex *vertices [[buffer(0)]],
    constant float4x4 &mvp [[buffer(1)]]
) {
    SpotLightVaryings out;
    out.position = mvp * float4(vertices[vertexID].position, 0.0, 1.0);
    out.texcoord = vertices[vertexID].texcoord;
    return out;
}

fragment float4 sceneSpotLightFrag(
    SpotLightVaryings input [[stage_in]],
    constant SpotLightUniforms &u [[buffer(0)]]
) {
    float along = saturate(input.texcoord.x);
    float across = abs(input.texcoord.y * 2.0 - 1.0);
    float coneCoordinate = across / max(along, 0.0005);
    float cone = 1.0 - smoothstep(u.innerRatio, 1.0, coneCoordinate);
    float originFade = smoothstep(0.0, 0.035, along);
    float reach = pow(
        saturate(1.0 - along),
        max(u.volumetricsExponent * 0.42, 0.1)
    );
    float profile = pow(
        saturate(cone),
        max(u.exponent * 0.38, 0.2)
    ) * originFade * reach;
    float opticalDepth = max(u.density, 0.0) * 0.22 * profile;
    float opacity = saturate(
        (1.0 - exp(-opticalDepth)) * saturate(u.intensity / 100.0)
    ) * u.color.a;
    float colorBoost = 0.8 + saturate(u.intensity / 100.0) * 0.45;
    float3 color = saturate(u.color.rgb * colorBoost);
    return float4(color * opacity, opacity);
}
