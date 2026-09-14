#include <metal_stdlib>
using namespace metal;

// Fixed product shader for the sole image/source compositor. The Swift mirror
// is SceneLayerFragmentUniforms in SceneMetalPipeline.swift.
struct SceneImageLayerQuadVertex {
    float2 position;
    float2 texcoord;
};

struct SceneImageLayerVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct SceneImageLayerFragmentUniforms {
    float time;
    float alpha;
    uint dependencyBlendMode;
    uint usesDependencyBlend;
    float2 cursorUV;
    uint2 sourceSampling;
    float4 tint;
    float4 textureFrame0;
    float4 textureFrame1;
};

static float2 sceneImageLayerTextureFrameUV(
    float2 uv,
    constant SceneImageLayerFragmentUniforms &uniforms
) {
    return uniforms.textureFrame0.xy
        + uv.x * uniforms.textureFrame0.zw
        + uv.y * uniforms.textureFrame1.xy;
}

vertex SceneImageLayerVaryings sceneImageLayerVert(
    uint vertexID [[vertex_id]],
    constant SceneImageLayerQuadVertex *vertices [[buffer(0)]],
    constant float4x4 &modelViewProjection [[buffer(1)]]
) {
    SceneImageLayerVaryings result;
    result.position = modelViewProjection
        * float4(vertices[vertexID].position, 0.0, 1.0);
    result.texcoord = vertices[vertexID].texcoord;
    return result;
}

fragment float4 sceneImageLayerFrag(
    SceneImageLayerVaryings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture2d<float> dependencyTexture [[texture(1)]],
    constant SceneImageLayerFragmentUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClampSampler(
        min_filter::linear,
        mag_filter::linear,
        mip_filter::linear,
        address::clamp_to_edge
    );
    constexpr sampler linearRepeatSampler(
        min_filter::linear,
        mag_filter::linear,
        mip_filter::linear,
        address::repeat
    );
    constexpr sampler nearestClampSampler(
        min_filter::nearest,
        mag_filter::nearest,
        mip_filter::nearest,
        address::clamp_to_edge
    );
    constexpr sampler nearestRepeatSampler(
        min_filter::nearest,
        mag_filter::nearest,
        mip_filter::nearest,
        address::repeat
    );

    const float2 sourceUV = sceneImageLayerTextureFrameUV(
        clamp(input.texcoord, 0.0, 1.0),
        uniforms
    );
    float4 color;
    switch (uniforms.sourceSampling.x) {
    case 1u:
        color = sourceTexture.sample(linearRepeatSampler, sourceUV);
        break;
    case 2u:
        color = sourceTexture.sample(nearestClampSampler, sourceUV);
        break;
    case 3u:
        color = sourceTexture.sample(nearestRepeatSampler, sourceUV);
        break;
    default:
        color = sourceTexture.sample(linearClampSampler, sourceUV);
        break;
    }

    if (uniforms.usesDependencyBlend != 0u) {
        const float3 target = dependencyTexture.sample(
            linearClampSampler,
            clamp(input.texcoord, 0.0, 1.0)
        ).rgb;
        if (uniforms.dependencyBlendMode == 0u) {
            color.rgb = mix(color.rgb, target, color.a);
        } else if (uniforms.dependencyBlendMode == 5u) {
            color.rgb = min(color.rgb, target);
        }
    }

    return color * uniforms.tint * uniforms.alpha;
}
