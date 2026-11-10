#include <metal_stdlib>
using namespace metal;

struct ScenePointVolumeVertex {
    float4 position [[position]];
    float2 clip;
};

struct ScenePointVolumeLight {
    float4 centerAndRadius;
    float4 radianceAndExponent;
};

struct ScenePointVolumeCamera {
    float4 originAndNear;
    float4 forwardAndFar;
    float4 horizontal;
    float4 vertical;
};

vertex ScenePointVolumeVertex scenePointVolumeVertex(uint vertexID [[vertex_id]]) {
    const float2 clip = float2(vertexID == 1 ? 3.0 : -1.0, vertexID == 2 ? 3.0 : -1.0);
    return {float4(clip, 0.0, 1.0), clip};
}

static float integrateVolumeSegment(float start, float end, float offsetSquared, float exponent) {
    const float middle = (start + end) * 0.5;
    const float halfLength = (end - start) * 0.5;
    const float4 nodes = float4(-0.86113631, -0.33998104, 0.33998104, 0.86113631);
    const float4 weights = float4(0.34785485, 0.65214515, 0.65214515, 0.34785485);
    const float4 t = middle + nodes * halfLength;
    const float4 distance = sqrt(offsetSquared + t * t);
    return halfLength * dot(weights, powr(max(0.0, 1.0 - distance), float4(exponent)));
}

static float integratedPointVolume(
    float3 nearPoint, float3 direction, float rayLength, ScenePointVolumeLight light
) {
    const float radius = light.centerAndRadius.w;
    const float3 offset = (nearPoint - light.centerAndRadius.xyz) / radius;
    const float axis = -dot(offset, direction);
    const float3 perpendicular = offset + axis * direction;
    const float perpendicularSquared = dot(perpendicular, perpendicular);
    const float chordSquared = 1.0 - perpendicularSquared;
    if (chordSquared <= 0.0) return 0.0;

    const float halfChord = sqrt(chordSquared);
    const float start = max(-axis, -halfChord);
    const float end = min(rayLength / radius - axis, halfChord);
    if (end <= start) return 0.0;

    const float exponent = light.radianceAndExponent.w;
    if (exponent == 0.0) return end - start;
    // A single interval would oversample the narrow peak of a center crossing.
    if (start < 0.0 && end > 0.0) {
        return integrateVolumeSegment(start, 0.0, perpendicularSquared, exponent)
            + integrateVolumeSegment(0.0, end, perpendicularSquared, exponent);
    }
    return integrateVolumeSegment(start, end, perpendicularSquared, exponent);
}

fragment float4 scenePointVolumeFragment(
    ScenePointVolumeVertex input [[stage_in]],
    constant ScenePointVolumeLight *lights [[buffer(0)]],
    constant ScenePointVolumeCamera &camera [[buffer(1)]],
    constant uint &count [[buffer(2)]],
    depth2d<float, access::read> depth [[texture(0)]]
) {
    const float sceneDepth = depth.read(uint2(input.position.xy));
    const float near = camera.originAndNear.w;
    const float far = camera.forwardAndFar.w;
    const float viewDepth = sceneDepth == 0.0 ? far : near / mix(near / far, 1.0, sceneDepth);
    const float3 ray = camera.forwardAndFar.xyz
        + input.clip.x * camera.horizontal.xyz + input.clip.y * camera.vertical.xyz;
    const float rayScale = length(ray);
    const float rayLength = (viewDepth - near) * rayScale;
    const float3 nearPoint = camera.originAndNear.xyz + ray * near;
    const float3 direction = ray / rayScale;
    float3 result = float3(0.0);
    for (uint index = 0; index < count; ++index) {
        result += lights[index].radianceAndExponent.xyz *
            integratedPointVolume(nearPoint, direction, rayLength, lights[index]);
    }
    return float4(result, 0.0);
}
