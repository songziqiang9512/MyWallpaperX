let sceneParticleShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct QuadVertex { float2 position; float2 texcoord; };
struct ParticleInstance {
    float4 positionAndSize;
    float4 rotationAndAlpha;
    float4 colorAndFrameMix;
    float4 frame0A;
    float4 frame0B;
    float4 frame1A;
    float4 frame1B;
    float4 velocityAndTrail;
};
struct LayerUniforms {
    float4x4 viewProjection;
    float4x4 layerModel;
    float4 basisRight;
    float4 basisUp;
};
struct Varyings {
    float4 position [[position]];
    float2 baseUV;
    float2 uv0;
    float2 uv1;
    float2 screenTangentX;
    float2 screenTangentY;
    float4 tint;
    float frameBlend;
};

float3 rotateXYZ(float3 value, float3 radians) {
    float3 c = cos(radians), s = sin(radians);
    value = float3(value.x, c.x * value.y - s.x * value.z,
                   s.x * value.y + c.x * value.z);
    value = float3(c.y * value.x + s.y * value.z, value.y,
                   -s.y * value.x + c.y * value.z);
    return float3(c.z * value.x - s.z * value.y,
                  s.z * value.x + c.z * value.y, value.z);
}

vertex Varyings sceneParticleVert(
    uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
    constant QuadVertex *quad [[buffer(0)]],
    device const ParticleInstance *instances [[buffer(1)]],
    constant LayerUniforms &uniforms [[buffer(2)]]) {
    QuadVertex quadVertex = quad[vertexID];
    ParticleInstance particle = instances[instanceID];
    float4 center = uniforms.layerModel * float4(particle.positionAndSize.xyz, 1.0);
    float3 local;
    if (particle.velocityAndTrail.w >= 0.0) {
        float3 worldVelocity = (uniforms.layerModel
            * float4(particle.velocityAndTrail.xyz, 0.0)).xyz;
        float4 projectedStart = uniforms.viewProjection * center;
        float4 projectedEnd = uniforms.viewProjection
            * float4(center.xyz + worldVelocity * 0.001, 1.0);
        float2 velocity = projectedEnd.xy / max(abs(projectedEnd.w), 0.00001)
            - projectedStart.xy / max(abs(projectedStart.w), 0.00001);
        float speed = length(velocity);
        float2 direction = speed > 0.00001 ? velocity / speed : float2(1.0, 0.0);
        float2 perpendicular = float2(-direction.y, direction.x);
        float2 aligned = direction * quadVertex.position.x
            * particle.positionAndSize.w * particle.velocityAndTrail.w
            + perpendicular * quadVertex.position.y * particle.positionAndSize.w;
        local = float3(aligned, 0.0);
    } else {
        local = rotateXYZ(
            float3(quadVertex.position * particle.positionAndSize.w, 0.0),
            particle.rotationAndAlpha.xyz);
    }
    float3 normal = normalize(cross(uniforms.basisRight.xyz, uniforms.basisUp.xyz));
    float2 layerScale = float2(length(uniforms.layerModel[0].xyz),
                               length(uniforms.layerModel[1].xyz));
    float3 offset = uniforms.basisRight.xyz * local.x * layerScale.x
                  + uniforms.basisUp.xyz * local.y * layerScale.y
                  + normal * local.z;
    Varyings out;
    out.position = uniforms.viewProjection * float4(center.xyz + offset, 1.0);
    out.baseUV = quadVertex.texcoord;
    out.uv0 = particle.frame0A.xy + quadVertex.texcoord.x * particle.frame0A.zw
            + quadVertex.texcoord.y * particle.frame0B.xy;
    out.uv1 = particle.frame1A.xy + quadVertex.texcoord.x * particle.frame1A.zw
            + quadVertex.texcoord.y * particle.frame1B.xy;
    float alpha = saturate(particle.rotationAndAlpha.w);
    out.tint = float4(max(particle.colorAndFrameMix.xyz, 0.0) * alpha, alpha);
    out.frameBlend = saturate(particle.colorAndFrameMix.w);
    float3 tangentLocalX = rotateXYZ(
        float3(particle.positionAndSize.w, 0.0, 0.0),
        particle.rotationAndAlpha.xyz);
    float3 tangentLocalY = rotateXYZ(
        float3(0.0, particle.positionAndSize.w, 0.0),
        particle.rotationAndAlpha.xyz);
    float3 tangentWorldX = uniforms.basisRight.xyz * tangentLocalX.x * layerScale.x
                         + uniforms.basisUp.xyz * tangentLocalX.y * layerScale.y;
    float3 tangentWorldY = uniforms.basisRight.xyz * tangentLocalY.x * layerScale.x
                         + uniforms.basisUp.xyz * tangentLocalY.y * layerScale.y;
    float4 centerClip = uniforms.viewProjection * center;
    float4 tangentClipX = uniforms.viewProjection
        * float4(center.xyz + tangentWorldX, 1.0);
    float4 tangentClipY = uniforms.viewProjection
        * float4(center.xyz + tangentWorldY, 1.0);
    float2 centerNDC = centerClip.xy / max(abs(centerClip.w), 0.00001);
    float2 tangentNDCX = tangentClipX.xy / max(abs(tangentClipX.w), 0.00001);
    float2 tangentNDCY = tangentClipY.xy / max(abs(tangentClipY.w), 0.00001);
    out.screenTangentX = (tangentNDCX - centerNDC) * float2(0.5, -0.5);
    out.screenTangentY = (tangentNDCY - centerNDC) * float2(0.5, -0.5);
    return out;
}

fragment float4 sceneParticleFrag(
    Varyings in [[stage_in]],
    texture2d<float> texture [[texture(0)]],
    sampler colorSampler [[sampler(0)]],
    constant float2 &colorUVScale [[buffer(0)]]) {
    float4 first = texture.sample(colorSampler, in.uv0 * colorUVScale);
    float4 second = texture.sample(colorSampler, in.uv1 * colorUVScale);
    return mix(first, second, in.frameBlend) * in.tint;
}

fragment float4 sceneParticleRefractFrag(
    Varyings in [[stage_in]],
    texture2d<float> colorTexture [[texture(0)]],
    texture2d<float> normalTexture [[texture(1)]],
    texture2d<float> backgroundTexture [[texture(2)]],
    sampler colorSampler [[sampler(0)]],
    sampler normalSampler [[sampler(1)]],
    constant float4 &parameters [[buffer(0)]],
    constant float4 &uvScales [[buffer(1)]]) {
    constexpr sampler backgroundSampler(filter::linear, address::clamp_to_edge);
    float4 colorFirst = colorTexture.sample(colorSampler, in.uv0 * uvScales.xy);
    float4 colorSecond = colorTexture.sample(colorSampler, in.uv1 * uvScales.xy);
    float4 albedo = mix(colorFirst, colorSecond, in.frameBlend);
    if (parameters.z > 0.5) {
        albedo = float4(albedo.r, albedo.r, albedo.r, albedo.g);
    }

    bool normalUsesFrames = fmod(parameters.w, 2.0) > 0.5;
    bool additive = parameters.w > 1.5;
    float2 normalUV0 = normalUsesFrames ? in.uv0 : in.baseUV * uvScales.zw;
    float2 normalUV1 = normalUsesFrames ? in.uv1 : normalUV0;
    float4 normalFirst = normalTexture.sample(normalSampler, normalUV0);
    float4 normalSecond = normalTexture.sample(normalSampler, normalUV1);
    float4 packedNormal = mix(normalFirst, normalSecond, in.frameBlend);
    float2 normalXY = float2(packedNormal.a, packedNormal.g) * 2.0 - 1.0;
    float2 backgroundUV = in.position.xy
        / float2(backgroundTexture.get_width(), backgroundTexture.get_height());
    backgroundUV += (in.screenTangentX * normalXY.x
        + in.screenTangentY * normalXY.y) * parameters.x;
    float3 background = backgroundTexture.sample(backgroundSampler, backgroundUV).rgb;

    float coverage = saturate(albedo.a * in.tint.a);
    float3 straightTint = in.tint.a > 0.0 ? in.tint.rgb / in.tint.a : float3(0.0);
    float3 source = background * albedo.rgb * straightTint * parameters.y;
    return float4(additive ? source : source * coverage, coverage);
}
"""
