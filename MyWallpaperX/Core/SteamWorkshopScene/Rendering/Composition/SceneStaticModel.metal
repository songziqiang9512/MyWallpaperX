#include <metal_stdlib>
using namespace metal;

struct SceneStaticModelVertex {
    float3 position;
    float3 normal;
    float4 tangent;
    float2 uv;
};

struct SceneStaticModelUniforms {
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float3x3 normalMatrix;
    float4 textureFrame0;
    float4 textureFrame1;
    float4 componentTextureFrame0;
    float4 componentTextureFrame1;
    float4 materialColorAndOpacity;
    float4 emissiveColorAndBrightness;
    float4 viewTintFrontAndExponent;
    float4 viewTintBackAndEnabled;
    float4 cameraPosition;
    uint4 materialFlags;
    uint4 lightCounts;
    float4 ambientColor;
    float4 distanceFogColor;
    float4 distanceFogRange;
    float4 lightDirectionIntensity[4];
    float4 lightColor[4];
    float4 pointPositionRadius[4];
    float4 pointColorIntensity[4];
    float4 spotPositionRadius[4];
    float4 spotDirectionInnerCosine[4];
    float4 spotColorIntensity[4];
    float4 spotOuterCosines;
    float4x4 worldToShadowClip;
    float4 shadowParameters;
};

struct SceneStaticModelRasterVertex {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 uv;
    float2 componentUV;
};

vertex SceneStaticModelRasterVertex sceneStaticModelVertex(
    uint vertexID [[vertex_id]],
    constant SceneStaticModelVertex *vertices [[buffer(0)]],
    constant SceneStaticModelUniforms &uniforms [[buffer(1)]]) {
    SceneStaticModelVertex modelVertex = vertices[vertexID];
    SceneStaticModelRasterVertex out;
    float4 worldPosition = uniforms.modelMatrix * float4(modelVertex.position, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPosition;
    out.worldPosition = worldPosition.xyz;
    float3 transformedNormal = uniforms.normalMatrix * modelVertex.normal;
    float transformedLengthSquared = dot(transformedNormal, transformedNormal);
    out.normal = transformedLengthSquared > 1e-12
        ? transformedNormal * rsqrt(transformedLengthSquared)
        : float3(0.0, 0.0, 1.0);
    out.uv = uniforms.textureFrame0.xy
        + modelVertex.uv.x * uniforms.textureFrame0.zw
        + modelVertex.uv.y * uniforms.textureFrame1.xy;
    out.componentUV = uniforms.componentTextureFrame0.xy
        + modelVertex.uv.x * uniforms.componentTextureFrame0.zw
        + modelVertex.uv.y * uniforms.componentTextureFrame1.xy;
    return out;
}

float sceneDirectionalVisibility(float3 position, depth2d<float> shadow,
    constant SceneStaticModelUniforms &uniforms) {
    float4 projected = uniforms.worldToShadowClip * float4(position, 1.0);
    float3 clip = projected.xyz / projected.w;
    float2 uv = float2(clip.x * 0.5 + 0.5, 0.5 - clip.y * 0.5);
    // The directional light projection is orthographic. Differentiate world
    // position before its affine projection so small geometry does not lose
    // its UV/depth slope by subtracting separately rounded translated values.
    float3 lightDX = (uniforms.worldToShadowClip * float4(dfdx(position), 0.0)).xyz;
    float3 lightDY = (uniforms.worldToShadowClip * float4(dfdy(position), 0.0)).xyz;
    float3 plane = cross(float3(lightDX.x * 0.5, -lightDX.y * 0.5, lightDX.z),
                         float3(lightDY.x * 0.5, -lightDY.y * 0.5, lightDY.z));
    // A triangle tangent to the light direction has no finite depth over light
    // UV; screen-degenerate helper quads can also produce a zero Jacobian.
    // Keep this optional visibility local to the receiver fragment.
    if (plane.z == 0.0) return 1.0;
    float2 depthGradient = -plane.xy / plane.z;
    if (!all(isfinite(depthGradient))) return 1.0;
    if (any(uv < 0.0) || any(uv > 1.0) || clip.z < 0.0 || clip.z > 1.0) return 1.0;
    constexpr sampler shadowSampler(coord::normalized, address::clamp_to_edge,
                                    filter::nearest, compare_func::less_equal);
    float2 extent = float2(shadow.get_width(), shadow.get_height());
    // Affine projection can cancel large world-coordinate terms even when the
    // resulting clip value is small. Propagate those Float32 arithmetic scales
    // through UV conversion and the receiver-plane slope, using the same
    // fixed numerical margin as the final reference-depth additions.
    float3 projectionMagnitude = abs(uniforms.worldToShadowClip[0].xyz * position.x)
        + abs(uniforms.worldToShadowClip[1].xyz * position.y)
        + abs(uniforms.worldToShadowClip[2].xyz * position.z)
        + abs(uniforms.worldToShadowClip[3].xyz);
    float depthMagnitude = projectionMagnitude.z
        + dot(abs(depthGradient), (projectionMagnitude.xy + 1.0) * 0.5);
    float visibility = 0.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 pixel = clamp(floor(uv * extent) + float2(x, y), float2(0.0), extent - 1.0);
            float2 sampleUV = (pixel + 0.5) / extent;
            float2 correction = depthGradient * (sampleUV - uv);
            float referenceDepth = clip.z + correction.x + correction.y;
            // Near-tangent receiver planes can leave the map's depth domain
            // within this finite filter footprint. Clear depth is not an
            // occluder beyond that domain; retain this tap's unoccluded weight.
            if (referenceDepth < 0.0 || referenceDepth > 1.0) {
                visibility += 1.0;
                continue;
            }
            float precisionBias = uniforms.shadowParameters.y
                * max(1.0, depthMagnitude + abs(correction.x) + abs(correction.y));
            visibility += shadow.sample_compare(shadowSampler, sampleUV, referenceDepth - precisionBias);
        }
    }
    return visibility / 9.0;
}

fragment half4 sceneStaticModelFragment(
    SceneStaticModelRasterVertex in [[stage_in]],
    texture2d<half> colorTexture [[texture(0)]],
    texture2d<half> componentTexture [[texture(1)]],
    depth2d<float> shadowTexture [[texture(2)]],
    sampler colorSampler [[sampler(0)]],
    sampler componentSampler [[sampler(1)]],
    constant SceneStaticModelUniforms &uniforms [[buffer(1)]]) {
    half4 albedo = colorTexture.sample(colorSampler, in.uv);
    if ((uniforms.materialFlags.x & 2u) != 0u) {
        albedo.rgb = albedo.a > half(1e-5)
            ? albedo.rgb / albedo.a
            : half3(0.0);
    }
    float normalLengthSquared = dot(in.normal, in.normal);
    float3 normal = normalLengthSquared > 1e-12
        ? in.normal * rsqrt(normalLengthSquared)
        : float3(0.0, 0.0, 1.0);
    bool receivesLighting = (uniforms.materialFlags.y & 2u) == 0u;
    float3 lighting = receivesLighting
        ? uniforms.ambientColor.xyz
        : float3(1.0);
    uint lightCount = uniforms.lightCounts.x;
    for (uint lightIndex = 0;
         receivesLighting && lightIndex < min(lightCount, 4u);
         ++lightIndex) {
        float4 light = uniforms.lightDirectionIntensity[lightIndex];
        float diffuse = max(dot(normal, light.xyz), 0.0);
        float visibility = uniforms.shadowParameters.x == float(lightIndex)
            ? sceneDirectionalVisibility(in.worldPosition, shadowTexture, uniforms) : 1.0;
        lighting += uniforms.lightColor[lightIndex].xyz * light.w * diffuse * visibility;
    }
    uint pointCount = receivesLighting ? uniforms.lightCounts.y : 0u;
    for (uint lightIndex = 0; lightIndex < min(pointCount, 4u); ++lightIndex) {
        float4 positionRadius = uniforms.pointPositionRadius[lightIndex];
        float3 toLight = positionRadius.xyz - in.worldPosition;
        float distanceSquared = dot(toLight, toLight);
        if (distanceSquared <= 1e-8) {
            continue;
        }
        float distanceToLight = sqrt(distanceSquared);
        float3 directionTowardLight = toLight / distanceToLight;
        float radial = clamp(
            1.0 - distanceToLight / max(positionRadius.w, 1e-4),
            0.0,
            1.0
        );
        radial *= radial;
        float diffuse = max(dot(normal, directionTowardLight), 0.0);
        float4 colorIntensity = uniforms.pointColorIntensity[lightIndex];
        lighting += colorIntensity.xyz * colorIntensity.w * radial * diffuse;
    }
    uint spotCount = receivesLighting ? uniforms.lightCounts.z : 0u;
    for (uint lightIndex = 0; lightIndex < min(spotCount, 4u); ++lightIndex) {
        float4 positionRadius = uniforms.spotPositionRadius[lightIndex];
        float3 toLight = positionRadius.xyz - in.worldPosition;
        float distanceSquared = dot(toLight, toLight);
        if (distanceSquared <= 1e-8) {
            continue;
        }
        float distanceToLight = sqrt(distanceSquared);
        float3 directionTowardLight = toLight / distanceToLight;
        float radial = clamp(
            1.0 - distanceToLight / max(positionRadius.w, 1e-4),
            0.0,
            1.0
        );
        radial *= radial;
        float4 directionInner = uniforms.spotDirectionInnerCosine[lightIndex];
        float coneDot = dot(directionInner.xyz, -directionTowardLight);
        float outerCosine = uniforms.spotOuterCosines[lightIndex];
        float cone = directionInner.w > outerCosine + 1e-5
            ? smoothstep(outerCosine, directionInner.w, coneDot)
            : step(outerCosine, coneDot);
        float diffuse = max(dot(normal, directionTowardLight), 0.0);
        float4 colorIntensity = uniforms.spotColorIntensity[lightIndex];
        lighting += colorIntensity.xyz * colorIntensity.w
            * radial * cone * diffuse;
    }
    half authoredOpacity = half(uniforms.materialColorAndOpacity.w);
    half outputAlpha = authoredOpacity * (
        (uniforms.materialFlags.x & 1u) != 0u ? albedo.a : half(1.0)
    );
    // A fully uncovered texel must not occlude later material parts through
    // the depth buffer. Tint-mask alpha is excluded by the coverage flag.
    if (outputAlpha <= half(0.0)) {
        discard_fragment();
    }
    half3 surfaceColor;
    if (uniforms.materialFlags.w != 0) {
        half luminancePeak = max(albedo.r, max(albedo.g, albedo.b));
        half3 tinted = luminancePeak
            * half3(uniforms.materialColorAndOpacity.xyz);
        surfaceColor = mix(albedo.rgb, tinted, albedo.a);
    } else {
        surfaceColor = albedo.rgb
            * half3(uniforms.materialColorAndOpacity.xyz);
    }
    if (uniforms.viewTintBackAndEnabled.w > 0.5) {
        float3 towardCamera = uniforms.cameraPosition.xyz - in.worldPosition;
        float viewLengthSquared = dot(towardCamera, towardCamera);
        float3 viewDirection = viewLengthSquared > 1e-8
            ? towardCamera * rsqrt(viewLengthSquared)
            : float3(0.0, 0.0, 1.0);
        float facing = clamp(dot(viewDirection, normal), 0.0, 1.0);
        float frontWeight = pow(
            facing,
            max(uniforms.viewTintFrontAndExponent.w, 0.01)
        );
        half3 viewTint = mix(
            half3(uniforms.viewTintBackAndEnabled.xyz),
            half3(uniforms.viewTintFrontAndExponent.xyz),
            half(frontWeight)
        );
        surfaceColor *= viewTint;
    }
    half3 litColor = surfaceColor * half3(lighting);
    if ((uniforms.materialFlags.y & 1u) != 0u) {
        half emissive = clamp(
            componentTexture.sample(componentSampler, in.componentUV).a
                * half(uniforms.emissiveColorAndBrightness.w),
            half(0.0),
            half(1.0)
        );
        half3 emittedColor = surfaceColor
            * half3(uniforms.emissiveColorAndBrightness.xyz);
        litColor = mix(litColor, emittedColor, emissive);
    }
    if (uniforms.distanceFogColor.w > 0.5) {
        float4 range = uniforms.distanceFogRange;
        float distanceFromCamera = length(uniforms.cameraPosition.xyz - in.worldPosition);
        float fraction = clamp((distanceFromCamera - range.x) / (range.y - range.x), 0.0, 1.0);
        half density = half(mix(range.z, range.w, fraction));
        litColor = mix(litColor, half3(uniforms.distanceFogColor.xyz), density);
    }
    // Static-model inputs preserve straight texture channels. Convert the
    // material result to the existing premultiplied main-pass contract here.
    return half4(litColor * outputAlpha, outputAlpha);
}

struct SceneStaticModelShadowUniforms {
    float4x4 modelToLightClip;
    float4 textureFrame0;
    float4 textureFrame1;
    float4 coverage;
};
struct SceneStaticModelShadowVertexOut {
    float4 position [[position]];
    float2 uv;
};
vertex SceneStaticModelShadowVertexOut sceneStaticModelShadowVertex(
    uint vertexID [[vertex_id]], constant SceneStaticModelVertex *vertices [[buffer(0)]],
    constant SceneStaticModelShadowUniforms &uniforms [[buffer(1)]]) {
    SceneStaticModelVertex modelVertex = vertices[vertexID];
    SceneStaticModelShadowVertexOut out;
    out.position = uniforms.modelToLightClip * float4(modelVertex.position, 1.0);
    out.uv = uniforms.textureFrame0.xy + modelVertex.uv.x * uniforms.textureFrame0.zw
        + modelVertex.uv.y * uniforms.textureFrame1.xy;
    return out;
}
fragment void sceneStaticModelShadowFragment(
    SceneStaticModelShadowVertexOut in [[stage_in]],
    texture2d<half> albedo [[texture(0)]], sampler albedoSampler [[sampler(0)]],
    constant SceneStaticModelShadowUniforms &uniforms [[buffer(1)]]) {
    float coverage = uniforms.coverage.x;
    if (uniforms.coverage.y != 0.0) coverage *= float(albedo.sample(albedoSampler, in.uv).a);
    if (coverage <= 0.5) discard_fragment();
}
