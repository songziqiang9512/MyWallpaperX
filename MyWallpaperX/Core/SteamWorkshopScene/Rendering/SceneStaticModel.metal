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
    float4 ambientAndCount;
    float4 lightDirectionIntensity[4];
    float4 lightColor[4];
    float4 spotPositionRadius[4];
    float4 spotDirectionInnerCosine[4];
    float4 spotColorIntensity[4];
    float4 spotOuterCosines;
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

fragment half4 sceneStaticModelFragment(
    SceneStaticModelRasterVertex in [[stage_in]],
    texture2d<half> colorTexture [[texture(0)]],
    texture2d<half> componentTexture [[texture(1)]],
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
        ? uniforms.ambientAndCount.xyz
        : float3(1.0);
    uint lightCount = uint(uniforms.ambientAndCount.w);
    for (uint lightIndex = 0;
         receivesLighting && lightIndex < min(lightCount, 4u);
         ++lightIndex) {
        float4 light = uniforms.lightDirectionIntensity[lightIndex];
        float diffuse = max(dot(normal, light.xyz), 0.0);
        lighting += uniforms.lightColor[lightIndex].xyz * light.w * diffuse;
    }
    uint spotCount = receivesLighting ? uniforms.materialFlags.z : 0u;
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
    // Static-model inputs preserve straight texture channels. Convert the
    // material result to the existing premultiplied main-pass contract here.
    return half4(litColor * outputAlpha, outputAlpha);
}
