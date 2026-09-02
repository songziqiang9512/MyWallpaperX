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
    float4 materialColorAndOpacity;
    uint4 materialFlags;
    float4 ambientAndCount;
    float4 lightDirectionIntensity[4];
    float4 lightColor[4];
};

struct SceneStaticModelRasterVertex {
    float4 position [[position]];
    float3 normal;
    float2 uv;
};

vertex SceneStaticModelRasterVertex sceneStaticModelVertex(
    uint vertexID [[vertex_id]],
    constant SceneStaticModelVertex *vertices [[buffer(0)]],
    constant SceneStaticModelUniforms &uniforms [[buffer(1)]]) {
    SceneStaticModelVertex modelVertex = vertices[vertexID];
    SceneStaticModelRasterVertex out;
    float4 worldPosition = uniforms.modelMatrix * float4(modelVertex.position, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPosition;
    float3 transformedNormal = uniforms.normalMatrix * modelVertex.normal;
    float transformedLengthSquared = dot(transformedNormal, transformedNormal);
    out.normal = transformedLengthSquared > 1e-12
        ? transformedNormal * rsqrt(transformedLengthSquared)
        : float3(0.0, 0.0, 1.0);
    out.uv = uniforms.textureFrame0.xy
        + modelVertex.uv.x * uniforms.textureFrame0.zw
        + modelVertex.uv.y * uniforms.textureFrame1.xy;
    return out;
}

fragment half4 sceneStaticModelFragment(
    SceneStaticModelRasterVertex in [[stage_in]],
    texture2d<half> colorTexture [[texture(0)]],
    sampler colorSampler [[sampler(0)]],
    constant SceneStaticModelUniforms &uniforms [[buffer(1)]]) {
    half4 albedo = colorTexture.sample(colorSampler, in.uv);
    float normalLengthSquared = dot(in.normal, in.normal);
    float3 normal = normalLengthSquared > 1e-12
        ? in.normal * rsqrt(normalLengthSquared)
        : float3(0.0, 0.0, 1.0);
    float3 lighting = uniforms.ambientAndCount.xyz;
    uint lightCount = uint(uniforms.ambientAndCount.w);
    for (uint lightIndex = 0; lightIndex < min(lightCount, 4u); ++lightIndex) {
        float4 light = uniforms.lightDirectionIntensity[lightIndex];
        float diffuse = max(dot(normal, light.xyz), 0.0);
        lighting += uniforms.lightColor[lightIndex].xyz * light.w * diffuse;
    }
    lighting = lighting / (float3(1.0) + lighting);

    half authoredOpacity = half(uniforms.materialColorAndOpacity.w);
    half outputAlpha = authoredOpacity * (
        uniforms.materialFlags.x != 0 ? albedo.a : half(1.0)
    );
    half3 litColor = albedo.rgb
        * half3(uniforms.materialColorAndOpacity.xyz)
        * half3(lighting);
    // Static-model inputs preserve straight texture channels. Convert the
    // material result to the existing premultiplied main-pass contract here.
    return half4(litColor * outputAlpha, outputAlpha);
}
