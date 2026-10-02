#include <metal_stdlib>
using namespace metal;

// Project-owned bounded direct material response in world space.
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
    float4 material;
    float4 view;
    float4 mapFrame0;
    float4 mapFrame1;
    uint4 mapSamplingComponents;
    float4 emission;
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

// Finite author coordinates can overflow a squared length or subtraction.
// An undefined geometric direction closes only that direct-light term.
static float3 sceneLitDirection(float3 delta) {
    const float scale = max(max(abs(delta.x), abs(delta.y)), abs(delta.z));
    if (!(scale > 0.0) || !isfinite(scale)) return float3(0.0);
    return normalize(delta / scale);
}

static float sceneLitFalloff(float3 delta, float radius) {
    const float scale = max(max(abs(delta.x), abs(delta.y)), abs(delta.z));
    if (!(scale > 0.0) || !isfinite(scale)) return 0.0;
    const float distanceRatio = (scale / radius) * length(delta / scale);
    const float remaining = max(0.0, 1.0 - distanceRatio);
    return remaining * remaining;
}

// Complete covered/tinted contribution, before the rgba16f store. Factoring
// exponents prevents finite bright lamps times tiny opacity from overflowing
// before coverage. The result stays HDR; 65504 is storage, not tone mapping.
static float sceneLitStoredTerm(float response, float intensity, float lightColor,
    float falloff, float coveredColor, float tint, float opacity) {
    const float factors[7] = {response, intensity, lightColor, falloff,
        coveredColor, tint, opacity};
    float product = 1.0;
    bool needsScaling = false;
    for (uint i = 0; i < 7; ++i) {
        if (!(factors[i] > 0.0)) return 0.0;
        product *= factors[i];
        needsScaling = needsScaling || !isfinite(product) || product < 0x1p-126f;
    }
    if (!needsScaling) return min(65504.0, product);
    float mantissa = 1.0;
    int exponent = 0;
    for (uint i = 0; i < 7; ++i) {
        int componentExponent;
        mantissa *= frexp(factors[i], componentExponent);
        exponent += componentExponent;
    }
    int normalizationExponent;
    mantissa = frexp(mantissa, normalizationExponent);
    exponent += normalizationExponent;
    if (exponent > 16) return 65504.0;
    return min(65504.0, ldexp(mantissa, exponent));
}

static float3 sceneLitDirect(float3 normal, float3 view, float3 light,
    float4 source, float4 material, float3 lightColor, float intensity,
    float falloff, float3 tint, float opacity) {
    const float noL = clamp(dot(normal, light), 0.0, 1.0);
    float3 diffuseWeight = float3(noL);
    float3 specularWeight = float3(0.0);
    if (material.z != 0.0) {
        const float metallic = material.x;
        const float3 reflectance = clamp(source.rgb / source.a, 0.0, 1.0);
        const float3 f0 = mix(float3(0.04), reflectance, metallic);
        float3 fresnel = f0;
        const float noV = clamp(dot(normal, view), 0.0, 1.0);
        if (noL > 0.0 && noV > 0.0) {
            const float3 halfway = normalize(light + view);
            const float noH = clamp(dot(normal, halfway), 0.0, 1.0);
            const float voH = clamp(dot(view, halfway), 0.0, 1.0);
            const float slope = max(0.01, material.y * material.y);
            const float a2 = slope * slope;
            const float h2 = noH * noH;
            const float distributionDenominator = (1.0 - h2) + a2 * h2;
            // pi cancels the GGX distribution pi in the legacy lamp units.
            const float scaledDistribution = a2 /
                (distributionDenominator * distributionDenominator);
            const float visibilityScale = max(noL, noV);
            const float l = noL / visibilityScale, v = noV / visibilityScale;
            const float visibilityDenominator = l * sqrt(a2 + (1.0-a2)*noV*noV)
                + v * sqrt(a2 + (1.0-a2)*noL*noL);
            // Height-correlated Smith, already multiplied by outgoing NoL.
            const float weightedVisibility = 0.5 * l / visibilityDenominator;
            const float grazing = pow(1.0 - voH, 5.0);
            fresnel = f0 + (1.0 - f0) * grazing;
            specularWeight = fresnel * (scaledDistribution * weightedVisibility);
        }
        diffuseWeight = (1.0-metallic) * (1.0-fresnel) * noL;
    }
    float3 result;
    for (uint channel = 0; channel < 3; ++channel) {
        const float diffuse = sceneLitStoredTerm(diffuseWeight[channel], intensity,
            lightColor[channel], falloff, source[channel], tint[channel], opacity);
        const float specular = sceneLitStoredTerm(specularWeight[channel], intensity,
            lightColor[channel], falloff, source.a, tint[channel], opacity);
        result[channel] = min(65504.0, diffuse + specular);
    }
    return result;
}

fragment float4 sceneLitImageLayerFrag(
    SceneImageLayerVaryings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture2d<float> normalTexture [[texture(1)]],
    texture2d<float> materialMapTexture [[texture(2)]],
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

    if (color.a <= 0.0) return float4(0.0);

    // Shared quad convention: +Y up and texture v=0 at the top.
    const float4 local = float4(input.texcoord.x - 0.5, 0.5 - input.texcoord.y, 0, 1);
    const float3 world = (payload.modelMatrix * local).xyz;
    const bool hasNormal = payload.ambientHasNormal.w != 0.0;
    float4 material = payload.material;
    float4 mapped = float4(0.0);
    const uint components = payload.mapSamplingComponents.y;
    if (components != 0u) {
        const float2 localUV = clamp(input.texcoord, 0.0, 1.0);
        const float2 mapUV = payload.mapFrame0.xy
            + localUV.x * payload.mapFrame0.zw + localUV.y * payload.mapFrame1.xy;
        switch (payload.mapSamplingComponents.x) {
        case 1u: mapped = materialMapTexture.sample(linearRepeatSampler, mapUV); break;
        case 2u: mapped = materialMapTexture.sample(nearestClampSampler, mapUV); break;
        case 3u: mapped = materialMapTexture.sample(nearestRepeatSampler, mapUV); break;
        default: mapped = materialMapTexture.sample(linearClampSampler, mapUV); break;
        }
        if ((components & 1u) != 0u) material.x = mapped.r;
        if ((components & 2u) != 0u) material.y = mapped.g;
    }

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

    const float3 view = sceneLitDirection(payload.view.xyz - world * payload.view.w);
    float3 radiance;
    for (uint channel = 0; channel < 3; ++channel) {
        radiance[channel] = sceneLitStoredTerm(1.0, payload.ambientHasNormal[channel],
            1.0, 1.0, color[channel], uniforms.tint[channel], uniforms.alpha);
    }
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
        const float3 towardLight = sceneLitDirection(delta);
        radiance = min(float3(65504.0), radiance + sceneLitDirect(normal, view,
            towardLight, color, material, pointColor[index].rgb,
            pointColor[index].w, falloff, uniforms.tint.rgb, uniforms.alpha));
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
        const float3 receiverDirection = -sceneLitDirection(delta);
        const float cosAngle = dot(receiverDirection, spotDirectionCone[index].xyz);
        const float innerCosine = spotDirectionCone[index].w;
        const float outerCosine = payload.spotOuterConeCosines[index];
        const float cone = saturate(
            (cosAngle - outerCosine) / max(innerCosine - outerCosine, 1e-4)
        );
        if (cone <= 0.0) {
            continue;
        }
        const float3 towardLight = sceneLitDirection(delta);
        radiance = min(float3(65504.0), radiance + sceneLitDirect(normal, view,
            towardLight, color, material, spotColorIntensity[index].rgb,
            spotColorIntensity[index].w, falloff * cone, uniforms.tint.rgb, uniforms.alpha));
    }

    if ((components & 8u) != 0u) {
        for (uint channel = 0; channel < 3; ++channel) {
            const float emission = sceneLitStoredTerm(mapped.a, payload.emission.w,
                payload.emission[channel], 1.0, color.a, uniforms.tint[channel], uniforms.alpha);
            radiance[channel] = min(65504.0, radiance[channel] + emission);
        }
    }

    // Emission and lighting share coverage; neither changes alpha.
    return float4(radiance, color.a * uniforms.tint.a * uniforms.alpha);
}
