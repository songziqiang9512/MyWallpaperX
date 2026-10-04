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
    float4 trailHeadJoin;
    float4 trailTailJoin;
};
struct LayerUniforms {
    float4x4 viewProjection;
    float4x4 layerModel;
    float4 basisRight;
    float4 basisUp;
    float2 viewportSize;
    float2 particleSizeScale;
    float4 viewRight;
    float4 viewUp;
    float4 spriteRight;
    float4 spriteUp;
    float4 spriteForward;
    float4 trailLocalNormal;
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

float3 rotateParticle(float3 value, float3 radians) {
    // Match the authored particle basis: clockwise Z, then X, then Y.
    // This is local particle rotation, before orientation and layer scaling.
    float3 c = cos(radians), s = -sin(radians);
    value = float3(c.z * value.x - s.z * value.y,
                   s.z * value.x + c.z * value.y, value.z);
    value = float3(value.x, c.x * value.y - s.x * value.z,
                   s.x * value.y + c.x * value.z);
    return float3(c.y * value.x + s.y * value.z, value.y,
                   -s.y * value.x + c.y * value.z);
}

// Perspective direction differential at the actual endpoint. Extrapolating
// by a complete segment can cross the eye plane although the segment itself
// is visible, reversing the inferred tangent and pinching a valid join.
float2 particlePixelDirection(float4 clipPosition, float3 worldDirection,
                             constant LayerUniforms &uniforms) {
    float4 delta = uniforms.viewProjection * float4(worldDirection, 0.0);
    return (delta.xy * clipPosition.w - clipPosition.xy * delta.w)
        / max(clipPosition.w * clipPosition.w, 0.00000001)
        * max(uniforms.viewportSize, float2(1.0));
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
    float2 layerScale = uniforms.particleSizeScale;
    float3 local = float3(0.0);
    float3 trailWorld = float3(0.0);
    float3 trailAcrossWorld = float3(0.0);
    // Sprite size is width-based; frame aspects remain W/H through blending.
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
        bool joined = particle.frame1B.w > 0.5;
        float4 endpointJoin = quadVertex.position.x > 0.0
            ? particle.trailHeadJoin : particle.trailTailJoin;
        float4 anchor = joined
            ? float4(center.xyz + trailWorld * quadVertex.position.x, 1.0) : center;
        float4 projectedStart = uniforms.viewProjection * anchor;
        float2 pixelVelocity = particlePixelDirection(projectedStart, trailWorld, uniforms);
        float speed = length(pixelVelocity);
        float2 trailDirection = speed > 0.00001
            ? pixelVelocity / speed : float2(1.0, 0.0);
        float2 perpendicular = float2(-trailDirection.y, trailDirection.x);
        if (joined) {
            float3 adjacentWorld = (uniforms.layerModel
                * float4(endpointJoin.xyz, 0.0)).xyz;
            float2 adjacentPixels = particlePixelDirection(projectedStart, adjacentWorld, uniforms);
            float adjacentSpeed = length(adjacentPixels);
            float2 adjacentDirection = adjacentSpeed > 0.00001
                ? adjacentPixels / adjacentSpeed : trailDirection;
            float2 adjacentNormal = float2(-adjacentDirection.y, adjacentDirection.x);
            float2 bisector = perpendicular + adjacentNormal;
            float bisectorLength = length(bisector);
            // Both segments compute the same bounded miter at their shared
            // endpoint. A reversal pinches to zero instead of emitting spikes.
            if (bisectorLength > 0.00001) {
                float2 miter = bisector / bisectorLength;
                perpendicular = miter / max(abs(dot(miter, perpendicular)), 0.25);
            } else {
                perpendicular = float2(0.0);
            }
        }
        float2 rightPixel = particlePixelDirection(projectedStart, uniforms.basisRight.xyz, uniforms);
        float2 upPixel = particlePixelDirection(projectedStart, uniforms.basisUp.xyz, uniforms);
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
        ) * (joined ? endpointJoin.w : particle.positionAndSize.w) * layerScale.x;
        if (!usesDisplacement && uniforms.trailLocalNormal.w > 0.5) {
            // Orient the width before the layer transform. Reconstructing a
            // perpendicular after projection erases nonuniform scale/shear.
            float3x3 linearLayer = float3x3(uniforms.layerModel[0].xyz,
                uniforms.layerModel[1].xyz, uniforms.layerModel[2].xyz);
            // The existing orientation owner supplies the pre-transform
            // plane, including when a layer axis has collapsed to zero.
            float3 localAcross = cross(uniforms.trailLocalNormal.xyz, localDirection);
            float acrossLength = length(localAcross);
            if (acrossLength > 0.00001) {
                float3 affineAcross = linearLayer * (localAcross / acrossLength)
                    * particle.positionAndSize.w;
                float2 affinePixels = particlePixelDirection(projectedStart, affineAcross, uniforms);
                // Retain the established texture-facing sign, without
                // straightening the two independently transformed axes.
                trailAcrossWorld = dot(affinePixels, perpendicular) < 0.0
                    ? -affineAcross : affineAcross;
            }
        }
    } else {
        local = rotateParticle(
            float3(
                quadVertex.position.x * particle.positionAndSize.w,
                quadVertex.position.y * particle.positionAndSize.w / spriteAspect,
                0.0
            ),
            particle.rotationAndAlpha.xyz);
    }
    float3 normal = normalize(cross(uniforms.basisRight.xyz, uniforms.basisUp.xyz));
    float3 offset = isTrail
        ? trailWorld * quadVertex.position.x
            + trailAcrossWorld * quadVertex.position.y
        : uniforms.spriteRight.xyz * local.x
            + uniforms.spriteUp.xyz * local.y
            + uniforms.spriteForward.xyz * local.z;
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
        tangentWorldX = -trailAcrossWorld;
        tangentWorldY = trailWorld;
    } else {
        float3 tangentLocalX = rotateParticle(
            float3(1.0, 0.0, 0.0),
            particle.rotationAndAlpha.xyz);
        float3 tangentLocalY = rotateParticle(
            float3(0.0, 1.0, 0.0),
            particle.rotationAndAlpha.xyz);
        tangentWorldX = uniforms.basisRight.xyz * tangentLocalX.x
                      + uniforms.basisUp.xyz * tangentLocalX.y + normal * tangentLocalX.z;
        tangentWorldY = uniforms.basisRight.xyz * tangentLocalY.x
                      + uniforms.basisUp.xyz * tangentLocalY.y + normal * tangentLocalY.z;
    }
    // Refraction is an amount in screen UVs, independent of card dimensions,
    // projection depth and atlas/trail UV span. Preserve the authored packing:
    // each normal component combines both particle axes against one view axis.
    // A zero-length axis contributes no offset instead of producing NaNs.
    tangentWorldX /= max(length(tangentWorldX), 0.00001);
    tangentWorldY /= max(length(tangentWorldY), 0.00001);
    out.screenTangentX = float2(dot(tangentWorldX, uniforms.viewRight.xyz),
                               dot(tangentWorldY, uniforms.viewRight.xyz));
    out.screenTangentY = float2(dot(tangentWorldX, uniforms.viewUp.xyz),
                               dot(tangentWorldY, uniforms.viewUp.xyz));
    return out;
}

fragment float4 sceneParticleFrag(
    Varyings in [[stage_in]],
    texture2d<float> texture [[texture(0)]],
    sampler colorSampler [[sampler(0)]],
    constant float4 &parameters [[buffer(0)]]) {
    float4 first = texture.sample(colorSampler, in.uv0 * parameters.xy);
    float4 second = texture.sample(colorSampler, in.uv1 * parameters.xy);
    float4 texel = mix(first, second, in.frameBlend);
    float4 result = texel * in.tint;
    // in.tint already includes particle alpha. Apply texture coverage only
    // after filtering/interpolation, retaining authored RGB at zero alpha.
    result.rgb *= texel.a * parameters.z;
    return result;
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

    float2 backgroundUV = in.position.xy
        / float2(backgroundTexture.get_width(), backgroundTexture.get_height());
    uint normalFlags = uint(parameters.w);
    if ((normalFlags & 4u) == 0u) {
        bool normalUsesFrames = (normalFlags & 1u) != 0u;
        float2 normalUV0 = normalUsesFrames ? in.uv0 : in.baseUV * uvScales.zw;
        float2 normalUV1 = normalUsesFrames ? in.uv1 : normalUV0;
        float4 normalFirst = normalTexture.sample(normalSampler, normalUV0);
        float4 normalSecond = normalTexture.sample(normalSampler, normalUV1);
        float4 packedNormal = mix(normalFirst, normalSecond, in.frameBlend);
        // Shader decoding follows the TEX source format even when a BC3
        // upload was decompressed to RGBA. R is the independent normal mask.
        float2 normalXY = float2(packedNormal.a, packedNormal.g) * 2.0
            - float2((normalFlags & 2u) != 0u ? 0.965 : 1.0, 1.0);
        float refractionWeight = packedNormal.r * in.tint.a;
        backgroundUV += (in.screenTangentX * normalXY.x
            + in.screenTangentY * normalXY.y) * parameters.x * refractionWeight;
    }
    float3 background = backgroundTexture.sample(backgroundSampler, backgroundUV).rgb;

    float coverage = saturate(albedo.a * in.tint.a);
    float3 straightTint = in.tint.a > 0.0 ? in.tint.rgb / in.tint.a : float3(0.0);
    float3 source = background * albedo.rgb * straightTint * parameters.y;
    return float4(source * coverage, coverage);
}
"""
