#include <metal_stdlib>
#include "SceneDistanceFog.metalh"
using namespace metal;

constant bool weightsSourceAlpha [[function_constant(0)]];

// Fixed product shader for the sole image/source compositor. The Swift mirror
// is SceneLayerFragmentUniforms in SceneMetalPipeline.swift.
struct SceneImageLayerQuadVertex {
    float2 position;
    float2 texcoord;
    float vertexCoverage;
};

struct SceneImageLayerVaryings {
    float4 position [[position]];
    float2 texcoord;
    float vertexCoverage;
    float2 modelPosition;
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
    SceneImageDistanceFogUniforms distanceFog;
};

static float2 sceneImageLayerTextureFrameUV(
    float2 uv,
    constant SceneImageLayerFragmentUniforms &uniforms
) {
    return uniforms.textureFrame0.xy
        + uv.x * uniforms.textureFrame0.zw
        + uv.y * uniforms.textureFrame1.xy;
}

// Preserve ordinary arithmetic, but do not let intermediate overflow or
// underflow erase a finite HDR contribution after opacity/coverage. Unlike the lit storage
// calculation this product is signed and has no radiance clamp.
static float4 sceneImageLayerModulation(float4 color, float4 sourceCoverage,
    float4 tint, float alpha, float vertexCoverage, float clipCoverage,
    bool preservesStraightRGB) {
    const float4 alphaFactors = preservesStraightRGB ? float4(1, 1, 1, alpha) : float4(alpha);
    const float4 vertexFactors = preservesStraightRGB ? float4(1, 1, 1, vertexCoverage) : float4(vertexCoverage);
    const float4 clipFactors = preservesStraightRGB ? float4(1, 1, 1, clipCoverage) : float4(clipCoverage);
    float4 result = color * sourceCoverage * tint * alphaFactors * vertexFactors * clipFactors;
    for (uint channel = 0; channel < 4; ++channel) {
        if (isfinite(result[channel]) && (result[channel] != 0.0
            || color[channel] == 0.0 || sourceCoverage[channel] == 0.0
            || tint[channel] == 0.0 || alphaFactors[channel] == 0.0
            || vertexFactors[channel] == 0.0 || clipFactors[channel] == 0.0)) continue;
        const float factors[6] = {color[channel], sourceCoverage[channel],
            tint[channel], alphaFactors[channel], vertexFactors[channel], clipFactors[channel]};
        float mantissa = 1.0;
        int exponent = 0;
        bool finiteInputs = true;
        for (uint index = 0; index < 6; ++index) {
            if (!isfinite(factors[index])) {
                finiteInputs = false;
                break;
            }
            int componentExponent;
            mantissa *= frexp(factors[index], componentExponent);
            exponent += componentExponent;
        }
        if (finiteInputs) result[channel] = ldexp(mantissa, exponent);
    }
    return result;
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
    result.vertexCoverage = vertices[vertexID].vertexCoverage;
    result.modelPosition = vertices[vertexID].position;
    return result;
}

fragment float4 sceneImageLayerFrag(
    SceneImageLayerVaryings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture2d<float> dependencyTexture [[texture(1)]],
    texture2d<float> clipMask [[texture(2)]],
    constant SceneImageLayerFragmentUniforms &uniforms [[buffer(0)]],
    constant float4 &clipTransform [[buffer(1)]]
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
    constexpr sampler linearClipSampler(filter::linear, address::clamp_to_zero);
    const float clipCoverage = clipTransform.z == 0.0 ? 1.0
        : clipMask.sample(linearClipSampler,
            input.modelPosition * clipTransform.zw + clipTransform.xy).r;

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

    // Storage representation and additive weighting are separate boundaries.
    // Association happens here for a straight final draw; source capture
    // keeps straight RGB and applies opacity only to coverage. True PMA
    // producers already carried their authored coverage into RGB.
    if (uniforms.sourceSampling.y == 1u) color.rgb *= color.a;

    // Keep layer opacity linear: source coverage belongs to the authored
    // effect output, while uniforms.alpha belongs to the final layer.
    const float4 sourceCoverage =
        is_function_constant_defined(weightsSourceAlpha) && weightsSourceAlpha
        ? float4(color.aaa, 1.0) : float4(1.0);
    float4 result = sceneImageLayerModulation(color, sourceCoverage, uniforms.tint,
        uniforms.alpha, input.vertexCoverage, clipCoverage, (uniforms.sourceSampling.y & 2u) != 0u);
    result.rgb = sceneImageDistanceFog(result.rgb, input.modelPosition,
        uniforms.distanceFog, result.a * sourceCoverage.x);
    return result;
}
