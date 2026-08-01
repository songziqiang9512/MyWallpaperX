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
    float2 viewportSize;
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
    bool isTrail = particle.velocityAndTrail.w >= 0.0;
    float2 layerScale = float2(length(uniforms.layerModel[0].xyz),
                               length(uniforms.layerModel[1].xyz));
    float3 local = float3(0.0);
    float3 trailWorld = float3(0.0);
    float3 trailAcrossWorld = float3(0.0);
    float spriteAspect = max(mix(
        particle.frame0B.z,
        particle.frame0B.w,
        saturate(particle.colorAndFrameMix.w)
    ), 0.00001);
    if (isTrail) {
        bool usesDisplacement = particle.frame1B.z > 0.5;
        float velocityLength = length(particle.velocityAndTrail.xyz);
        float3 localDirection = velocityLength > 0.00001
            ? particle.velocityAndTrail.xyz / velocityLength
            : float3(1.0, 0.0, 0.0);
        float3 localTrail = usesDisplacement
            ? particle.velocityAndTrail.xyz
            : localDirection * particle.positionAndSize.w * particle.velocityAndTrail.w;
        trailWorld = (uniforms.layerModel * float4(localTrail, 0.0)).xyz;
        float4 projectedStart = uniforms.viewProjection * center;
        float4 projectedEnd = uniforms.viewProjection
            * float4(center.xyz + trailWorld * 0.001, 1.0);
        float2 velocity = projectedEnd.xy / max(abs(projectedEnd.w), 0.00001)
            - projectedStart.xy / max(abs(projectedStart.w), 0.00001);
        float2 pixelVelocity = velocity * max(uniforms.viewportSize, float2(1.0));
        float speed = length(pixelVelocity);
        float2 trailDirection = speed > 0.00001
            ? pixelVelocity / speed : float2(1.0, 0.0);
        float2 perpendicular = float2(-trailDirection.y, trailDirection.x);
        float4 projectedRight = uniforms.viewProjection
            * float4(center.xyz + uniforms.basisRight.xyz, 1.0);
        float4 projectedUp = uniforms.viewProjection
            * float4(center.xyz + uniforms.basisUp.xyz, 1.0);
        float2 rightPixel = (
            projectedRight.xy / max(abs(projectedRight.w), 0.00001)
                - projectedStart.xy / max(abs(projectedStart.w), 0.00001)
        ) * uniforms.viewportSize;
        float2 upPixel = (
            projectedUp.xy / max(abs(projectedUp.w), 0.00001)
                - projectedStart.xy / max(abs(projectedStart.w), 0.00001)
        ) * uniforms.viewportSize;
        float determinant = rightPixel.x * upPixel.y - rightPixel.y * upPixel.x;
        float2 acrossCoefficients = perpendicular;
        if (abs(determinant) > 0.00001) {
            float2 targetPixel = perpendicular * max(length(rightPixel), 0.00001);
            acrossCoefficients = float2(
                (targetPixel.x * upPixel.y - targetPixel.y * upPixel.x)
                    / determinant,
                (rightPixel.x * targetPixel.y - rightPixel.y * targetPixel.x)
                    / determinant
            );
        }
        trailAcrossWorld = (
            uniforms.basisRight.xyz * acrossCoefficients.x
                + uniforms.basisUp.xyz * acrossCoefficients.y
        ) * particle.positionAndSize.w * layerScale.x;
    } else {
        local = rotateXYZ(
            float3(
                quadVertex.position.x * particle.positionAndSize.w * spriteAspect,
                quadVertex.position.y * particle.positionAndSize.w,
                0.0
            ),
            particle.rotationAndAlpha.xyz);
    }
    float3 normal = normalize(cross(uniforms.basisRight.xyz, uniforms.basisUp.xyz));
    float3 offset = isTrail
        ? trailWorld * quadVertex.position.x
            + trailAcrossWorld * quadVertex.position.y
        : uniforms.basisRight.xyz * local.x * layerScale.x
            + uniforms.basisUp.xyz * local.y * layerScale.y
            + normal * local.z;
    Varyings out;
    out.position = uniforms.viewProjection * float4(center.xyz + offset, 1.0);
    out.baseUV = isTrail
        ? float2(
            quadVertex.texcoord.y,
            1.0 - mix(particle.frame0B.z, particle.frame0B.w, quadVertex.texcoord.x)
        )
        : quadVertex.texcoord;
    out.uv0 = particle.frame0A.xy + quadVertex.texcoord.x * particle.frame0A.zw
            + quadVertex.texcoord.y * particle.frame0B.xy;
    out.uv1 = particle.frame1A.xy + quadVertex.texcoord.x * particle.frame1A.zw
            + quadVertex.texcoord.y * particle.frame1B.xy;
    float alpha = saturate(particle.rotationAndAlpha.w);
    out.tint = float4(max(particle.colorAndFrameMix.xyz, 0.0) * alpha, alpha);
    out.frameBlend = saturate(particle.colorAndFrameMix.w);
    float3 tangentWorldX;
    float3 tangentWorldY;
    if (isTrail) {
        float trailUVSpan = max(abs(particle.frame0B.w - particle.frame0B.z), 0.00001);
        tangentWorldX = -trailAcrossWorld;
        tangentWorldY = trailWorld / trailUVSpan;
    } else {
        float3 tangentLocalX = rotateXYZ(
            float3(particle.positionAndSize.w * spriteAspect, 0.0, 0.0),
            particle.rotationAndAlpha.xyz);
        float3 tangentLocalY = rotateXYZ(
            float3(0.0, particle.positionAndSize.w, 0.0),
            particle.rotationAndAlpha.xyz);
        tangentWorldX = uniforms.basisRight.xyz * tangentLocalX.x * layerScale.x
                      + uniforms.basisUp.xyz * tangentLocalX.y * layerScale.y;
        tangentWorldY = uniforms.basisRight.xyz * tangentLocalY.x * layerScale.x
                      + uniforms.basisUp.xyz * tangentLocalY.y * layerScale.y;
    }
    float4 centerClip = uniforms.viewProjection * center;
    float4 tangentClipX = uniforms.viewProjection
        * float4(center.xyz + tangentWorldX, 1.0);
    float4 tangentClipY = uniforms.viewProjection
        * float4(center.xyz + tangentWorldY, 1.0);
    float2 centerNDC = centerClip.xy / max(abs(centerClip.w), 0.00001);
    float2 tangentNDCX = tangentClipX.xy / max(abs(tangentClipX.w), 0.00001);
    float2 tangentNDCY = tangentClipY.xy / max(abs(tangentClipY.w), 0.00001);
    float2 screenTangentX = (tangentNDCX - centerNDC) * float2(0.5, -0.5);
    float2 screenTangentY = (tangentNDCY - centerNDC) * float2(0.5, -0.5);
    out.screenTangentX = screenTangentX;
    out.screenTangentY = screenTangentY;
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
