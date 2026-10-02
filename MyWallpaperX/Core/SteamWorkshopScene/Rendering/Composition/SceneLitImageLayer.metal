#include <metal_stdlib>
using namespace metal;

// Project-owned bounded diffuse point/spot lighting in world space.
// The source fragment preserves premultiplied coverage; this is not PBR parity.

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

// Swift mirror: SceneLitImageLayerLightPayload in
// SceneLitImageLayerPipeline.swift. Fixed four point and four spot slots,
// zero-padded per type (the launch light snapshot already admits at most
// SceneLightSnapshot.maximumLightCount lights in authored order).
struct SceneLitImageLayerLightPayload {
    float4 pointPositionRadius0;
    float4 pointPositionRadius1;
    float4 pointPositionRadius2;
    float4 pointPositionRadius3;
    float4 pointColor0;
    float4 pointColor1;
    float4 pointColor2;
    float4 pointColor3;
    float4 spotPositionRadius0;
    float4 spotPositionRadius1;
    float4 spotPositionRadius2;
    float4 spotPositionRadius3;
    float4 spotDirectionCone0;
    float4 spotDirectionCone1;
    float4 spotDirectionCone2;
    float4 spotDirectionCone3;
    float4 spotColorIntensity0;
    float4 spotColorIntensity1;
    float4 spotColorIntensity2;
    float4 spotColorIntensity3;
    float4 spotOuterConeCosines;
    // rgb = ambient, w = hasNormal (0/1)
    float4 ambientHasNormal;
    // x = point count, y = spot count, z/w = unused
    float4 lightCounts;
    float4x4 modelMatrix;
    float4x4 normalBasis;
    float4 normalFrame0;
    float4 normalFrame1;
    uint4 normalSamplingEncoding;
};

// Texture-frame affine transform uses the common source uniform ABI.
static float2 sceneLitImageLayerTextureFrameUV(
    float2 uv,
    constant SceneImageLayerFragmentUniforms &uniforms
) {
    return uniforms.textureFrame0.xy
        + uv.x * uniforms.textureFrame0.zw
        + uv.y * uniforms.textureFrame1.xy;
}

static float sceneLitFalloff(float3 delta, float radius) {
    if (radius <= 0.0) {
        return 0.0;
    }
    return pow(max(0.0, 1.0 - length(delta) / radius), 2.0);
}

fragment float4 sceneLitImageLayerFrag(
    SceneImageLayerVaryings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture2d<float> normalTexture [[texture(1)]],
    constant SceneImageLayerFragmentUniforms &uniforms [[buffer(0)]],
    constant SceneLitImageLayerLightPayload &payload [[buffer(1)]]
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

    const float2 sourceUV = sceneLitImageLayerTextureFrameUV(
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

    // Shared quad convention: +Y up and texture v=0 at the top.
    const float4 local = float4(input.texcoord.x - 0.5, 0.5 - input.texcoord.y, 0, 1);
    const float3 world = (payload.modelMatrix * local).xyz;
    const bool hasNormal = payload.ambientHasNormal.w != 0.0;
    float3 normal = float3(0.0, 0.0, 1.0);
    if (hasNormal) {
        const float2 normalLocalUV = clamp(input.texcoord, 0.0, 1.0);
        const float2 normalUV = payload.normalFrame0.xy
            + normalLocalUV.x * payload.normalFrame0.zw
            + normalLocalUV.y * payload.normalFrame1.xy;
        float3 sampled;
        switch (payload.normalSamplingEncoding.x) {
        case 1u: sampled = normalTexture.sample(linearRepeatSampler, normalUV).xyz; break;
        case 2u: sampled = normalTexture.sample(nearestClampSampler, normalUV).xyz; break;
        case 3u: sampled = normalTexture.sample(nearestRepeatSampler, normalUV).xyz; break;
        default: sampled = normalTexture.sample(linearClampSampler, normalUV).xyz; break;
        }
        if (payload.normalSamplingEncoding.y == 0u) {
            // Full RGB retains authored Z, including the negative hemisphere.
            normal = sampled * 2.0 - 1.0;
            // Opposing encoded directions can cancel under linear filtering.
            if (dot(normal, normal) == 0.0) normal = float3(0, 0, 1);
        } else {
            const float2 xy = payload.normalSamplingEncoding.y == 1u
                ? sampled.xy * 2.0 - 1.0 : sampled.xy;
            normal = float3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
        }
    }
    normal = (payload.normalBasis * float4(normal, 0)).xyz;
    normal /= max(length(normal), 1e-6);

    float4 pointPositionRadius[4] = {
        payload.pointPositionRadius0,
        payload.pointPositionRadius1,
        payload.pointPositionRadius2,
        payload.pointPositionRadius3,
    };
    float4 pointColor[4] = {
        payload.pointColor0,
        payload.pointColor1,
        payload.pointColor2,
        payload.pointColor3,
    };
    float4 spotPositionRadius[4] = {
        payload.spotPositionRadius0,
        payload.spotPositionRadius1,
        payload.spotPositionRadius2,
        payload.spotPositionRadius3,
    };
    float4 spotDirectionCone[4] = {
        payload.spotDirectionCone0,
        payload.spotDirectionCone1,
        payload.spotDirectionCone2,
        payload.spotDirectionCone3,
    };
    float4 spotColorIntensity[4] = {
        payload.spotColorIntensity0,
        payload.spotColorIntensity1,
        payload.spotColorIntensity2,
        payload.spotColorIntensity3,
    };

    float3 lighting = payload.ambientHasNormal.rgb;
    for (int index = 0; index < 4; index++) {
        if (float(index) >= payload.lightCounts.x) {
            break;
        }
        const float3 delta = pointPositionRadius[index].xyz - world;
        const float falloff = sceneLitFalloff(
            delta,
            pointPositionRadius[index].w
        );
        if (falloff <= 0.0) {
            continue;
        }
        const float3 towardLight = delta / max(length(delta), 1e-6);
        const float directionTerm = saturate(dot(normal, towardLight));
        lighting += pointColor[index].rgb
            * pointColor[index].w
            * falloff
            * directionTerm;
    }
    for (int index = 0; index < 4; index++) {
        if (float(index) >= payload.lightCounts.y) {
            break;
        }
        const float3 delta = spotPositionRadius[index].xyz - world;
        const float falloff = sceneLitFalloff(
            delta,
            spotPositionRadius[index].w
        );
        if (falloff <= 0.0) {
            continue;
        }
        const float3 receiverDirection = -delta / max(length(delta), 1e-6);
        const float cosAngle = dot(receiverDirection, spotDirectionCone[index].xyz);
        const float innerCosine = spotDirectionCone[index].w;
        const float outerCosine = payload.spotOuterConeCosines[index];
        const float cone = saturate(
            (cosAngle - outerCosine) / max(innerCosine - outerCosine, 1e-4)
        );
        if (cone <= 0.0) {
            continue;
        }
        const float3 towardLight = delta / max(length(delta), 1e-6);
        const float directionTerm = saturate(dot(normal, towardLight));
        lighting += spotColorIntensity[index].rgb
            * spotColorIntensity[index].w
            * falloff
            * cone
            * directionTerm;
    }

    // Multiply RGB only: alpha, coverage and premultiplied edges stay exact.
    color.rgb *= max(lighting, 0.0);
    return color * uniforms.tint * uniforms.alpha;
}
