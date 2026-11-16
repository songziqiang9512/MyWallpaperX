#include <metal_stdlib>
#include "SceneDistanceFog.metalh"
#include "SceneSurfaceResponse.metalh"
using namespace metal;

constant bool sceneStaticModelUsesReflection [[function_constant(0)]];

struct SceneStaticModelVertex {
    float3 position;
    float3 normal;
    float4 tangent;
    float2 uv;
};

struct SceneModelShadowUniforms {
    float4x4 transform;
    float4 positionRadius;
    float4 parameters; // tan(half cone), outer cosine, numerical margin, unused
    uint4 identity; // projection kind, current light index, enabled, unused
};

struct SceneModelTubeUniforms {
    float4 positionRadius;
    float4 directionLength;
    float4 colorIntensity;
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
    float4 cameraPosition; // eye.xyz, authored HDR brightness
    uint4 materialFlags;
    uint4 lightCounts;
    float4 ambientColor;
    float4 skylightColor;
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
    SceneModelShadowUniforms shadows[4];
    float4 surfaceMaterial;
    float4 pointFalloffExponents;
    float4 normalTextureFrame0;
    float4 normalTextureFrame1; // UV y-axis.xy, model handedness.z
    float4 gradientTextureFrame; // center-line origin.xy, x-axis.zw
    float4 rimParameters; // amount, exponent, unused, unused
    float4 specularTintAndColorMode; // specular RGB, Chroma surface-color policy
    float4 pigmentTextureFrame0; // pixel UV origin.xy, x-axis.zw
    float4 pigmentTextureFrame1; // pixel UV y-axis.xy, amount.z, flags.w: R/local-repeat
    float4 spotFalloffExponents;
    float4 pigmentFramePixels; // local width/height.xy and inverse.zw; zero for ordinary textures
    SceneModelTubeUniforms tubes[4];
    float4 tubeFalloffExponents;
    uint tubeCount;
    uint meshIndexElementSize;
};

struct SceneStaticModelRasterVertex {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 uv;
    float2 componentUV;
    float2 normalUV;
    float4 tangent;
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
    out.normalUV = uniforms.normalTextureFrame0.xy
        + modelVertex.uv.x * uniforms.normalTextureFrame0.zw
        + modelVertex.uv.y * uniforms.normalTextureFrame1.xy;
    out.tangent = float4(0.0);
    if (uniforms.materialFlags.z != 0u) {
        out.tangent = float4((uniforms.modelMatrix * float4(modelVertex.tangent.xyz, 0.0)).xyz,
            modelVertex.tangent.w * uniforms.normalTextureFrame1.z);
    }
    return out;
}

// Box width one retains the texel-centered bilinear footprint; width three
// averages neighbouring micro-shadow samples before reconstruction.
// Each caller keeps its geometric receiver-depth correction. The UV remains
// unclamped here so a point-light tap can select its adjacent cube face.
struct SceneShadowFilterTap {
    float2 uv;
    float weight;
};
SceneShadowFilterTap sceneShadowFilterTap(float2 uv, float2 extent, uint index, uint kernelWidth = 1u) {
    float2 pixel = uv * extent - 0.5;
    float2 base = floor(pixel);
    float2 fraction = pixel - base;
    uint axisCount = kernelWidth + 1u;
    uint2 offset(index % axisCount, index / axisCount);
    float2 weight = select(float2(1.0), 1.0 - fraction, offset == uint2(0u));
    weight = select(weight, fraction, offset == uint2(kernelWidth)) / float(kernelWidth);
    return { (base - float(kernelWidth / 2u) + float2(offset) + 0.5) / extent, weight.x * weight.y };
}

float sceneDirectionalVisibility(float3 position, float3 worldEdge0, float3 worldEdge1,
    depth2d<float> shadow, constant SceneModelShadowUniforms &uniforms) {
    float4 projected = uniforms.transform * float4(position, 1.0);
    float3 clip = projected.xyz / projected.w;
    float2 uv = float2(clip.x * 0.5 + 0.5, 0.5 - clip.y * 0.5);
    // Project local edge differences without the light map translation.
    float3 lightEdge0 = (uniforms.transform * float4(worldEdge0, 0.0)).xyz;
    float3 lightEdge1 = (uniforms.transform * float4(worldEdge1, 0.0)).xyz;
    float3 plane = cross(float3(lightEdge0.x * 0.5, -lightEdge0.y * 0.5, lightEdge0.z),
                         float3(lightEdge1.x * 0.5, -lightEdge1.y * 0.5, lightEdge1.z));
    // A triangle tangent to the light direction has no finite depth over light
    // UV; degenerate triangles can also produce a zero Jacobian.
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
    float3 projectionMagnitude = abs(uniforms.transform[0].xyz * position.x)
        + abs(uniforms.transform[1].xyz * position.y)
        + abs(uniforms.transform[2].xyz * position.z)
        + abs(uniforms.transform[3].xyz);
    float depthMagnitude = projectionMagnitude.z
        + dot(abs(depthGradient), (projectionMagnitude.xy + 1.0) * 0.5);
    float2 gatherBase = floor(uv * extent - 0.5) - 1.0;
    float visibility = 0.0;
    for (uint group = 0; group < 4; ++group) {
        uint index = (group & 1u) * 2u + (group >> 1u) * 8u;
        SceneShadowFilterTap tap0 = sceneShadowFilterTap(uv, extent, index, 3u);
        SceneShadowFilterTap tap1 = sceneShadowFilterTap(uv, extent, index + 1u, 3u);
        SceneShadowFilterTap tap2 = sceneShadowFilterTap(uv, extent, index + 4u, 3u);
        SceneShadowFilterTap tap3 = sceneShadowFilterTap(uv, extent, index + 5u, 3u);
        float4 sampleU = clamp(float4(tap0.uv.x, tap1.uv.x, tap2.uv.x, tap3.uv.x),
            0.5 / extent.x, 1.0 - 0.5 / extent.x);
        float4 sampleV = clamp(float4(tap0.uv.y, tap1.uv.y, tap2.uv.y, tap3.uv.y),
            0.5 / extent.y, 1.0 - 0.5 / extent.y);
        float4 correctionX = depthGradient.x * (sampleU - uv.x);
        float4 correctionY = depthGradient.y * (sampleV - uv.y);
        float4 referenceDepth = clip.z + correctionX + correctionY;
        float4 precisionBias = uniforms.parameters.z
            * max(float4(1.0), depthMagnitude + abs(correctionX) + abs(correctionY));
        float2 offset = float2((group & 1u) * 2u, (group >> 1u) * 2u);
        // Gather's wzxy order matches row-major offsets in each 2x2 block.
        float4 sampledDepth = shadow.gather(shadowSampler, (gatherBase + offset + 1.0) / extent).wzxy;
        float4 lit = float4(referenceDepth - precisionBias <= sampledDepth);
        // Taps outside the receiver depth domain retain their unoccluded weight.
        lit = select(lit, float4(1.0), (referenceDepth < 0.0) | (referenceDepth > 1.0));
        visibility += dot(float4(tap0.weight, tap1.weight, tap2.weight, tap3.weight), lit);
    }
    return visibility;
}

// Absolute multiplication scales for a cross product, without cancellation.
float3 sceneShadowCrossMagnitude(float3 a, float3 b) {
    a = abs(a); b = abs(b);
    return a.yzx * b.zxy + a.zxy * b.yzx;
}

struct SceneShadowReceiverPlane {
    float3 position;
    float3 normal;
    float3 normalMagnitude;
    float height;
    float heightMagnitude;
    bool valid;
};

SceneShadowReceiverPlane sceneShadowReceiverPlane(float3 position, float3 origin,
    float3x3 basis, float3 worldEdge0, float3 worldEdge1) {
    SceneShadowReceiverPlane result = {};
    float3 relative = position - origin;
    float3 q = basis * relative;
    result.position = q;
    float3 a = basis * worldEdge0, b = basis * worldEdge1;
    float aScale = max(max(abs(a.x), abs(a.y)), abs(a.z));
    float bScale = max(max(abs(b.x), abs(b.y)), abs(b.z));
    // Degenerate mesh edges cannot define a receiver plane.
    if (aScale == 0.0 || bScale == 0.0) return result;
    a /= aScale; b /= bScale;
    float3 n = cross(a, b);
    float nScale = max(max(abs(n.x), abs(n.y)), abs(n.z));
    if (nScale == 0.0 || !isfinite(nScale)) return result;
    n /= nScale;
    float h = dot(n, q);
    float3x3 absoluteBasis(abs(basis[0]), abs(basis[1]), abs(basis[2]));
    // Propagate the actual relative-position, rotation, cross and dot scales.
    // Eight epsilons is a conservative project margin, not an interpolation
    // error theorem. The paired near-contact controls constrain its usefulness.
    float3 qMagnitude = absoluteBasis * (abs(position) + abs(origin) + abs(relative));
    float3 aMagnitude = absoluteBasis * abs(worldEdge0) / aScale + abs(a);
    float3 bMagnitude = absoluteBasis * abs(worldEdge1) / bScale + abs(b);
    float3 nMagnitude = (sceneShadowCrossMagnitude(a, b)
        + sceneShadowCrossMagnitude(aMagnitude, b)
        + sceneShadowCrossMagnitude(a, bMagnitude)) / nScale + abs(n);
    float hMagnitude = dot(abs(n), abs(q) + qMagnitude) + dot(nMagnitude, abs(q));
    result.normal = n;
    result.normalMagnitude = nMagnitude;
    result.height = h;
    result.heightMagnitude = hMagnitude;
    result.valid = true;
    return result;
}

float sceneSpotVisibility(float3 position, float3 worldEdge0, float3 worldEdge1,
    depth2d<float> shadow, constant SceneModelShadowUniforms &uniforms) {
    float3x3 basis(uniforms.transform[0].xyz, uniforms.transform[1].xyz, uniforms.transform[2].xyz);
    float3 relative = position - uniforms.positionRadius.xyz;
    float3 q = basis * relative;
    float radius = uniforms.positionRadius.w;
    if (!all(isfinite(q)) || q.z <= 0.0 || length(q) >= radius) return 1.0;
    float tangent = uniforms.parameters.x;
    float2 uv = float2(0.5 + q.x / (2.0 * tangent * q.z),
                      0.5 - q.y / (2.0 * tangent * q.z));
    if (any(uv < 0.0) || any(uv > 1.0)) return 1.0;
    SceneShadowReceiverPlane plane = sceneShadowReceiverPlane(position,
        uniforms.positionRadius.xyz, basis, worldEdge0, worldEdge1);
    if (!plane.valid) return 1.0;
    float3 n = plane.normal, nMagnitude = plane.normalMagnitude;
    float h = plane.height, hMagnitude = plane.heightMagnitude;
    constexpr sampler shadowSampler(coord::normalized, address::clamp_to_edge,
                                    filter::nearest, compare_func::less_equal);
    float2 extent = float2(shadow.get_width(), shadow.get_height());
    float visibility = 0.0;
    for (uint index = 0; index < 4; ++index) {
        SceneShadowFilterTap tap = sceneShadowFilterTap(uv, extent, index);
        float2 sampleUV = clamp(tap.uv, 0.5 / extent, 1.0 - 0.5 / extent);
        float3 ray((2.0 * sampleUV.x - 1.0) * tangent,
                   (1.0 - 2.0 * sampleUV.y) * tangent, 1.0);
        float denominator = dot(n, ray);
        float distance = h / denominator;
        float referenceDepth = distance / radius;
        // A finite footprint can cross a tangent, the apex, sphere or cone.
        // Such a tap has no valid forward receiver-plane depth in this map.
        if (denominator == 0.0 || !isfinite(referenceDepth) || distance <= 0.0
            || distance * length(ray) >= radius
            || 1.0 / length(ray) < uniforms.parameters.y) {
            visibility += tap.weight;
            continue;
        }
        float3 rayMagnitude((2.0 * abs(sampleUV.x) + 1.0) * tangent + abs(ray.x),
                            (2.0 * abs(sampleUV.y) + 1.0) * tangent + abs(ray.y), 0.0);
        float denominatorMagnitude = dot(abs(n), abs(ray) + rayMagnitude) + dot(nMagnitude, abs(ray));
        float depthMagnitude = (hMagnitude + abs(distance) * denominatorMagnitude)
            / abs(denominator) / radius + abs(referenceDepth);
        float precisionBias = uniforms.parameters.z * max(1.0, depthMagnitude);
        if (!isfinite(precisionBias)) { visibility += tap.weight; continue; }
        visibility += tap.weight * shadow.sample_compare(shadowSampler, sampleUV, referenceDepth - precisionBias);
    }
    return visibility;
}

// Columns map face coordinates to world-relative coordinates. This fixed
// layout matches the CPU caster bases; ties select X, then Y, then Z.
constant float3x3 scenePointFaceToWorld[6] = {
    float3x3(float3(0, 0, -1), float3(0, 1, 0), float3(1, 0, 0)),
    float3x3(float3(0, 0, 1), float3(0, 1, 0), float3(-1, 0, 0)),
    float3x3(float3(0, 0, 1), float3(1, 0, 0), float3(0, 1, 0)),
    float3x3(float3(0, 0, -1), float3(1, 0, 0), float3(0, -1, 0)),
    float3x3(float3(1, 0, 0), float3(0, 1, 0), float3(0, 0, 1)),
    float3x3(float3(-1, 0, 0), float3(0, 1, 0), float3(0, 0, -1))
};
uint scenePointShadowFace(float3 direction) {
    float3 magnitude = abs(direction);
    if (magnitude.x >= magnitude.y && magnitude.x >= magnitude.z) return direction.x >= 0.0 ? 0u : 1u;
    if (magnitude.y >= magnitude.z) return direction.y >= 0.0 ? 2u : 3u;
    return direction.z >= 0.0 ? 4u : 5u;
}


float2 scenePointShadowUV(float3 local) {
    // Exact face ties must stay at 0/1 before floor chooses the filter
    // footprint; fast reciprocal cancellation can move zero below the face.
    float2 ratio = precise::divide(local.xy, float2(local.z));
    return fma(float2(0.5, -0.5), ratio, float2(0.5));
}

float scenePointVisibility(float3 position, float3 worldEdge0, float3 worldEdge1,
    depth2d<float> shadow, constant SceneModelShadowUniforms &uniforms) {
    SceneShadowReceiverPlane plane = sceneShadowReceiverPlane(position,
        uniforms.positionRadius.xyz, float3x3(1.0), worldEdge0, worldEdge1);
    float3 q = plane.position;
    float radialDistance = length(q), radius = uniforms.positionRadius.w;
    // A coincident light has zero direct contribution; finite authored/world
    // values can also overflow relative-position or distance arithmetic.
    if (!plane.valid || !isfinite(radialDistance) || radialDistance == 0.0 || radialDistance >= radius) return 1.0;
    uint centerFace = scenePointShadowFace(q);
    float3 center = transpose(scenePointFaceToWorld[centerFace]) * q;
    float2 uv = scenePointShadowUV(center);
    float2 faceExtent = float2(shadow.get_width() / 3, shadow.get_height() / 2);
    float3 n = plane.normal;
    constexpr sampler shadowSampler(coord::normalized, address::clamp_to_edge,
                                    filter::nearest, compare_func::less_equal);
    float visibility = 0.0;
    for (uint index = 0; index < 4; ++index) {
        SceneShadowFilterTap tap = sceneShadowFilterTap(uv, faceExtent, index);
        // Do not clamp to the center face: this ray may cross an edge or
        // corner. Requantize on its chosen face, then use THAT texel's ray.
        float2 initialUV = tap.uv;
        float3 initialRay = scenePointFaceToWorld[centerFace]
            * float3(2.0 * initialUV.x - 1.0, 1.0 - 2.0 * initialUV.y, 1.0);
        uint face = scenePointShadowFace(initialRay);
        float3 local = transpose(scenePointFaceToWorld[face]) * initialRay;
        float2 projectedUV = scenePointShadowUV(local);
        float2 pixel = clamp(floor(projectedUV * faceExtent), float2(0.0), faceExtent - 1.0);
        float2 sampleUV = (pixel + 0.5) / faceExtent;
        float3 localRay(2.0 * sampleUV.x - 1.0, 1.0 - 2.0 * sampleUV.y, 1.0);
        float3 ray = scenePointFaceToWorld[face] * localRay;
        float rayLength = length(ray), denominator = dot(n, ray);
        float distance = plane.height / denominator;
        float referenceDepth = distance * rayLength / radius;
        // A real receiver plane can meet adjacent rays behind the light,
        // outside its sphere or at a tangent. Keep this tap's filter weight.
        if (denominator == 0.0 || !isfinite(referenceDepth) || distance <= 0.0 || referenceDepth >= 1.0) {
            visibility += tap.weight;
            continue;
        }
        float3 localMagnitude(2.0 * abs(sampleUV.x) + 1.0 + abs(localRay.x),
                              2.0 * abs(sampleUV.y) + 1.0 + abs(localRay.y), 0.0);
        // Face transforms only permute/sign components. Propagate the
        // actual plane/ray quotient and radial length, not an axial bias.
        float3 rayMagnitude = abs(scenePointFaceToWorld[face] * localMagnitude);
        float denominatorMagnitude = dot(abs(n), abs(ray) + rayMagnitude)
            + dot(plane.normalMagnitude, abs(ray));
        float distanceMagnitude = (plane.heightMagnitude + abs(distance) * denominatorMagnitude)
            / abs(denominator) + abs(distance);
        float lengthMagnitude = dot(abs(ray), abs(ray) + rayMagnitude) / rayLength + rayLength;
        float depthMagnitude = (rayLength * distanceMagnitude + abs(distance) * lengthMagnitude)
            / radius + abs(referenceDepth);
        float precisionBias = uniforms.parameters.z * max(1.0, depthMagnitude);
        if (!isfinite(precisionBias)) { visibility += tap.weight; continue; }
        float2 tile = float2(face % 3u, face / 3u);
        float2 atlasUV = (tile + sampleUV) / float2(3.0, 2.0);
        visibility += tap.weight * shadow.sample_compare(shadowSampler, atlasUV, referenceDepth - precisionBias);
    }
    return visibility;
}

// The admitted material response is shared by all model lamp kinds. Callers
// retain each lamp's attenuation and multiply visibility across both lobes.
static float3 sceneStaticModelSurfaceResponse(float3 normal, float3 view,
    float3 light, float signedNoL, float3 surfaceColor, float2 material,
    texture2d<float> gradientTexture, sampler gradientSampler,
    float4 gradientFrame, uint gradientChannels, float rimWeight, float3 specularTint) {
    const float noL = clamp(signedNoL, 0.0, 1.0);
    float3 diffuseCosine = float3(noL);
    if (gradientChannels != 0u) {
        const float coordinate = clamp(0.5 + 0.5 * signedNoL, 0.0, 1.0);
        const float2 uv = gradientFrame.xy + coordinate * gradientFrame.zw;
        const float3 lookup = gradientTexture.sample(gradientSampler, uv, level(0.0)).rgb;
        diffuseCosine = gradientChannels == 1u ? float3(lookup.r) : lookup;
    }
    diffuseCosine += noL * rimWeight;
    const SceneSurfaceWeights weights = sceneSurfaceResponse(normal, view,
        light, clamp(surfaceColor, 0.0, 1.0), material.x, material.y, true,
        SceneSurfaceAnalyticSchlick, noL, diffuseCosine);
    return (surfaceColor * weights.diffuse + weights.specular * specularTint) / M_PI_F;
}

fragment half4 sceneStaticModelFragment(
    SceneStaticModelRasterVertex in [[stage_in]],
    uint primitiveID [[primitive_id]],
    device const SceneStaticModelVertex *vertices [[buffer(0)]],
    device const ushort *indices [[buffer(2)]],
    texture2d<float> colorTexture [[texture(0)]],
    texture2d<half> componentTexture [[texture(1)]],
    texture2d<float> normalTexture [[texture(7)]],
    texture2d<float> gradientTexture [[texture(8)]],
    texture2d<float> pigmentTexture [[texture(9)]],
    array<depth2d<float>, 4> shadowTextures [[texture(2)]],
    texture2d<float> reflectionTexture [[texture(6), function_constant(sceneStaticModelUsesReflection)]],
    sampler colorSampler [[sampler(0)]],
    sampler componentSampler [[sampler(1)]],
    sampler normalSampler [[sampler(2)]],
    sampler gradientSampler [[sampler(3)]],
    sampler pigmentSampler [[sampler(4)]],
    constant SceneStaticModelUniforms &uniforms [[buffer(1)]]) {
    bool receivesLighting = (uniforms.materialFlags.y & 2u) == 0u;
    float3 worldEdge0 = float3(0.0), worldEdge1 = float3(0.0);
    if (receivesLighting && uniforms.shadows[0].identity.z != 0u) {
        uint base = primitiveID * 3u;
        device const uint *wide = reinterpret_cast<device const uint *>(indices);
        uint3 face = uniforms.meshIndexElementSize == 4u
            ? uint3(wide[base], wide[base + 1u], wide[base + 2u])
            : uint3(indices[base], indices[base + 1u], indices[base + 2u]);
        float3 anchor = vertices[face.x].position;
        // Subpixel screen derivatives need not preserve the drawn face plane.
        worldEdge0 = (uniforms.modelMatrix * float4(vertices[face.y].position - anchor, 0.0)).xyz;
        worldEdge1 = (uniforms.modelMatrix * float4(vertices[face.z].position - anchor, 0.0)).xyz;
    }
    float4 albedo = colorTexture.sample(colorSampler, in.uv);
    if ((uniforms.materialFlags.x & 2u) != 0u) {
        albedo.rgb = albedo.a > 0.0
            ? albedo.rgb / albedo.a
            : float3(0.0);
    }
    float4 surfaceMaterial = uniforms.surfaceMaterial;
    const uint components = uniforms.materialFlags.y >> 2u;
    float4 componentMaps = float4(0.0);
    if (components != 0u) {
        componentMaps = float4(componentTexture.sample(componentSampler, in.componentUV));
        if ((components & 1u) != 0u) surfaceMaterial.x = componentMaps.r;
        if ((components & 2u) != 0u) surfaceMaterial.y = componentMaps.g;
        if ((components & 4u) != 0u) surfaceMaterial.w *= componentMaps.b;
    }
    bool surfaceEnabled = surfaceMaterial.z != 0.0;
    const bool chroma = uniforms.specularTintAndColorMode.w > 0.5;
    float3 surfaceColor = albedo.rgb;
    if (uniforms.materialFlags.w != 0) {
        float luminancePeak = max(albedo.r, max(albedo.g, albedo.b));
        float3 tinted = luminancePeak * uniforms.materialColorAndOpacity.xyz;
        surfaceColor = mix(albedo.rgb, tinted, albedo.a);
    } else if (!chroma) {
        surfaceColor *= uniforms.materialColorAndOpacity.xyz;
    }
    float normalLengthSquared = dot(in.normal, in.normal);
    float3 normal = normalLengthSquared > 1e-12
        ? in.normal * rsqrt(normalLengthSquared)
        : float3(0.0, 0.0, 1.0);
    // Fixed unit-normal official probes give 0, .25, .5, .75, 1 as
    // normal Y goes from -1 to +1 (2026-10-09); no interior floor or cap.
    float ambientRamp = 0.5 + 0.5 * normal.y;
    float3 lighting = receivesLighting
        ? uniforms.ambientColor.xyz * ambientRamp
            + uniforms.skylightColor.xyz * (1.0 - ambientRamp)
        : float3(1.0);
    if (uniforms.materialFlags.z != 0u) {
        float4 sampled = normalTexture.sample(normalSampler, in.normalUV);
        float3 tangentNormal;
        switch (uniforms.materialFlags.z) {
            case 1u: tangentNormal = sampled.xyz * 2.0 - 1.0; break;
            default: {
                float2 xy = uniforms.materialFlags.z == 2u ? sampled.rg * 2.0 - 1.0
                    : uniforms.materialFlags.z == 5u ? sampled.rg
                    : float2(sampled.a * 2.0 - 1.0,
                        sampled.g * 2.0 - (uniforms.materialFlags.z == 4u ? 0.965 : 1.0));
                tangentNormal = float3(xy, sqrt(saturate(1.0 - dot(xy, xy))));
                break;
            }
        }
        float3 tangent = in.tangent.xyz - normal * dot(normal, in.tangent.xyz);
        float tangentLength = dot(tangent, tangent);
        if (tangentLength > 1e-12) {
            tangent *= rsqrt(tangentLength);
            float3 bitangent = cross(normal, tangent) * in.tangent.w;
            float3 perturbed = tangent * tangentNormal.x + bitangent * tangentNormal.y
                + normal * tangentNormal.z;
            float perturbedLength = dot(perturbed, perturbed);
            if (perturbedLength > 1e-12) normal = perturbed * rsqrt(perturbedLength);
        }
    }
    float outputAlpha = uniforms.materialColorAndOpacity.w * (
        (uniforms.materialFlags.x & 1u) != 0u ? albedo.a : 1.0
    );
    // Keep implicit texture samples and receiver-plane derivatives before
    // coverage rejection; uncovered texels need no light or shadow work.
    if (outputAlpha <= 0.0) {
        discard_fragment();
    }
    float3 surfaceRadiance = float3(0.0);
    float3 towardCamera = uniforms.cameraPosition.xyz - in.worldPosition;
    float viewLengthSquared = dot(towardCamera, towardCamera);
    float3 viewDirection = viewLengthSquared > 1e-8
        ? towardCamera * rsqrt(viewLengthSquared)
        : float3(0.0, 0.0, 1.0);
    float3 viewTint = float3(1.0);
    const bool hasViewTint = uniforms.viewTintBackAndEnabled.w > 0.5;
    if (hasViewTint) {
        float facing = dot(viewDirection, normal);
        // Unmasked facing is signed; only the masked response uses exponent.
        float frontWeight = uniforms.materialFlags.w != 0u
            ? pow(clamp(facing, 0.0, 1.0), uniforms.viewTintFrontAndExponent.w)
            : facing;
        viewTint = mix(uniforms.viewTintBackAndEnabled.xyz,
            uniforms.viewTintFrontAndExponent.xyz, frontWeight);
    }
    float3 specularTint = uniforms.specularTintAndColorMode.xyz;
    if (chroma) {
        if (uniforms.materialFlags.w != 0u) {
            viewTint = mix(float3(1.0), viewTint, float(albedo.a));
            specularTint = mix(float3(1.0), specularTint, float(albedo.a));
        }
        if (hasViewTint) surfaceColor *= viewTint;
    }
    float rimWeight = 0.0;
    if (uniforms.rimParameters.x > 0.0
        && (uniforms.lightCounts.x | uniforms.lightCounts.y | uniforms.lightCounts.z | uniforms.tubeCount) != 0u) {
        const float edge = 1.0 - saturate(abs(dot(normal, viewDirection)));
        const float curve = uniforms.rimParameters.y == 0.0 ? 1.0 : pow(edge, uniforms.rimParameters.y);
        rimWeight = uniforms.rimParameters.x * curve;
    }
    float directionalVisibility[4] = {1.0, 1.0, 1.0, 1.0};
    float spotVisibility[4] = {1.0, 1.0, 1.0, 1.0};
    float pointVisibility[4] = {1.0, 1.0, 1.0, 1.0};
    for (uint slot = 0; receivesLighting && slot < 4; ++slot) {
        constant SceneModelShadowUniforms &map = uniforms.shadows[slot];
        if (map.identity.z == 0u) continue;
        if (map.identity.x == 0u) {
            directionalVisibility[map.identity.y] = sceneDirectionalVisibility(
                in.worldPosition, worldEdge0, worldEdge1, shadowTextures[slot], map);
        } else if (map.identity.x == 1u) {
            spotVisibility[map.identity.y] = sceneSpotVisibility(
                in.worldPosition, worldEdge0, worldEdge1, shadowTextures[slot], map);
        } else {
            pointVisibility[map.identity.y] = scenePointVisibility(
                in.worldPosition, worldEdge0, worldEdge1, shadowTextures[slot], map);
        }
    }
    uint lightCount = uniforms.lightCounts.x;
    for (uint lightIndex = 0;
         receivesLighting && lightIndex < min(lightCount, 4u);
         ++lightIndex) {
        float4 light = uniforms.lightDirectionIntensity[lightIndex];
        float signedNoL = dot(normal, light.xyz);
        float visibility = directionalVisibility[lightIndex];
        if (surfaceEnabled) {
            surfaceRadiance += sceneStaticModelSurfaceResponse(normal, viewDirection,
                light.xyz, signedNoL, surfaceColor, surfaceMaterial.xy,
                gradientTexture, gradientSampler, uniforms.gradientTextureFrame, uniforms.lightCounts.w,
                rimWeight, specularTint)
                * uniforms.lightColor[lightIndex].xyz * light.w * visibility;
        } else {
            lighting += uniforms.lightColor[lightIndex].xyz * light.w * max(signedNoL, 0.0) * visibility;
        }
    }
    uint pointCount = receivesLighting ? uniforms.lightCounts.y : 0u;
    for (uint lightIndex = 0; lightIndex < min(pointCount, 4u); ++lightIndex) {
        float4 positionRadius = uniforms.pointPositionRadius[lightIndex];
        float3 toLight = positionRadius.xyz - in.worldPosition;
        float distanceSquared = dot(toLight, toLight);
        if (distanceSquared == 0.0) {
            continue;
        }
        float distanceToLight = sqrt(distanceSquared);
        float3 directionTowardLight = toLight / distanceToLight;
        float radial = sceneRadialFalloff(distanceToLight, positionRadius.w,
            uniforms.pointFalloffExponents[lightIndex]);
        if (radial <= 0.0) continue;
        float signedNoL = dot(normal, directionTowardLight);
        float4 colorIntensity = uniforms.pointColorIntensity[lightIndex];
        if (surfaceEnabled) {
            surfaceRadiance += sceneStaticModelSurfaceResponse(normal, viewDirection,
                directionTowardLight, signedNoL, surfaceColor, surfaceMaterial.xy,
                gradientTexture, gradientSampler, uniforms.gradientTextureFrame, uniforms.lightCounts.w,
                rimWeight, specularTint)
                * colorIntensity.xyz * colorIntensity.w
                * radial * pointVisibility[lightIndex];
        } else {
            lighting += colorIntensity.xyz * colorIntensity.w * radial * max(signedNoL, 0.0) * pointVisibility[lightIndex];
        }
    }
    uint spotCount = receivesLighting ? uniforms.lightCounts.z : 0u;
    for (uint lightIndex = 0; lightIndex < min(spotCount, 4u); ++lightIndex) {
        float4 positionRadius = uniforms.spotPositionRadius[lightIndex];
        float3 toLight = positionRadius.xyz - in.worldPosition;
        float distanceSquared = dot(toLight, toLight);
        if (distanceSquared == 0.0) {
            continue;
        }
        float distanceToLight = sqrt(distanceSquared);
        float3 directionTowardLight = toLight / distanceToLight;
        float radial = sceneRadialFalloff(distanceToLight, positionRadius.w,
            uniforms.spotFalloffExponents[lightIndex]);
        if (radial <= 0.0) continue;
        float4 directionInner = uniforms.spotDirectionInnerCosine[lightIndex];
        float coneDot = dot(directionInner.xyz, -directionTowardLight);
        float outerCosine = uniforms.spotOuterCosines[lightIndex];
        float cone = directionInner.w > outerCosine + 1e-5
            ? smoothstep(outerCosine, directionInner.w, coneDot)
            : step(outerCosine, coneDot);
        float signedNoL = dot(normal, directionTowardLight);
        float4 colorIntensity = uniforms.spotColorIntensity[lightIndex];
        if (surfaceEnabled) {
            surfaceRadiance += sceneStaticModelSurfaceResponse(normal, viewDirection,
                directionTowardLight, signedNoL, surfaceColor, surfaceMaterial.xy,
                gradientTexture, gradientSampler, uniforms.gradientTextureFrame, uniforms.lightCounts.w,
                rimWeight, specularTint)
                * colorIntensity.xyz * colorIntensity.w
                * radial * cone * spotVisibility[lightIndex];
        } else {
            lighting += colorIntensity.xyz * colorIntensity.w
                * radial * cone * max(signedNoL, 0.0) * spotVisibility[lightIndex];
        }
    }
    const uint tubeCount = receivesLighting && surfaceEnabled ? uniforms.tubeCount : 0u;
    for (uint lightIndex = 0; lightIndex < min(tubeCount, 4u); ++lightIndex) {
        constant SceneModelTubeUniforms &tube = uniforms.tubes[lightIndex];
        const float along = clamp(dot(in.worldPosition - tube.positionRadius.xyz,
            tube.directionLength.xyz), 0.0, tube.directionLength.w);
        const float3 toLight = tube.positionRadius.xyz
            + tube.directionLength.xyz * along - in.worldPosition;
        const float distanceSquared = dot(toLight, toLight);
        if (distanceSquared == 0.0) continue;
        const float distanceToLight = sqrt(distanceSquared);
        const float radial = sceneRadialFalloff(distanceToLight, tube.positionRadius.w,
            uniforms.tubeFalloffExponents[lightIndex]);
        if (radial <= 0.0) continue;
        const float3 directionTowardLight = toLight / distanceToLight;
        surfaceRadiance += sceneStaticModelSurfaceResponse(normal, viewDirection,
            directionTowardLight, dot(normal, directionTowardLight), surfaceColor, surfaceMaterial.xy,
            gradientTexture, gradientSampler, uniforms.gradientTextureFrame, uniforms.lightCounts.w,
            rimWeight, specularTint) * tube.colorIntensity.xyz * tube.colorIntensity.w * radial;
    }
    if (uniforms.pigmentTextureFrame1.z > 0.0
        && (uniforms.lightCounts.x | uniforms.lightCounts.y | uniforms.lightCounts.z | uniforms.tubeCount) != 0u) {
        const uint pigmentFlags = uint(uniforms.pigmentTextureFrame1.w);
        float2 pixel = in.position.xy;
        if (uniforms.pigmentFramePixels.x > 0.0) {
            const float2 extent = uniforms.pigmentFramePixels.xy;
            if ((pigmentFlags & 2u) != 0u) {
                pixel -= floor(pixel * uniforms.pigmentFramePixels.zw) * extent;
            } else {
                pixel = clamp(pixel, float2(0.5), extent - 0.5);
            }
        }
        const float2 uv = uniforms.pigmentTextureFrame0.xy
            + pixel.x * uniforms.pigmentTextureFrame0.zw
            + pixel.y * uniforms.pigmentTextureFrame1.xy;
        const float3 noise = pigmentTexture.sample(pigmentSampler, uv, level(0.0)).rgb;
        const float neutral = saturate((pigmentFlags & 1u) != 0u
            ? noise.r : dot(noise, float3(1.0 / 3.0)));
        // Modulate only shadowed direct radiance; ambient and emission follow.
        surfaceRadiance *= 1.0 + uniforms.pigmentTextureFrame1.z * (2.0 * neutral - 1.0);
    }
    if (!chroma && hasViewTint) {
        surfaceColor *= viewTint;
        surfaceRadiance *= viewTint;
    }
    float3 litColor = surfaceColor * lighting;
    if (surfaceEnabled) litColor += surfaceRadiance;
    const float emissiveMask = saturate(componentMaps.a);
    if ((components & 8u) != 0u) {
        float emissive = emissiveMask * uniforms.emissiveColorAndBrightness.w;
        // The mask scales additional radiance; brightness is not a mix weight.
        // Keep finite HDR energy through fog and coverage before half storage.
        float3 emittedColor = min(
            float3(surfaceColor) * uniforms.emissiveColorAndBrightness.xyz,
            float3(MAXFLOAT)
        ) * emissive;
        litColor = min(litColor + emittedColor, float3(MAXFLOAT));
    }
    if (sceneStaticModelUsesReflection && surfaceMaterial.w > 0.0) {
        constexpr sampler reflectionSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
        const float2 extent(reflectionTexture.get_width(), reflectionTexture.get_height());
        const float4 clipNormal = uniforms.viewProjectionMatrix * float4(normal, 0.0);
        // Clip W keeps the camera-axis scale through reverse-depth projection.
        const float2 screenNormal = normalize(float3(clipNormal.xy, clipNormal.w)).xy;
        const float facing = saturate(abs(dot(normal, viewDirection)));
        const float2 shift = screenNormal * float2(1.5, -1.5 * extent.x / extent.y) * pow(facing, 4.0);
        const float2 uv = in.position.xy / extent + shift;
        const float2 edge = smoothstep(float2(-0.3), float2(0.0), uv)
            * (1.0 - smoothstep(float2(1.0), float2(1.3), uv));
        const float mip = surfaceMaterial.y * float(reflectionTexture.get_num_mip_levels() - 1);
        const float3 incident = reflectionTexture.sample(reflectionSampler, uv, level(mip)).rgb;
        const float weight = edge.x * edge.y * (1.0 - facing) * surfaceMaterial.w;
        const float3 reflected = pow(max(float3(0.001), incident * weight), 2.0 - surfaceMaterial.x);
        litColor += saturate(reflected);
    }
    if (surfaceEnabled) litColor *= uniforms.cameraPosition.w;
    if ((uniforms.materialFlags.x & 4u) != 0u && (components & 8u) != 0u) {
        const float excessEmission = emissiveMask * max(0.0, uniforms.emissiveColorAndBrightness.w - 1.0);
        if (excessEmission > 0.0) {
            litColor += (litColor * uniforms.emissiveColorAndBrightness.xyz) * excessEmission;
        }
    }
    litColor = sceneDistanceFog(litColor,
        towardCamera,
        uniforms.distanceFogColor, uniforms.distanceFogRange);
    // Static-model inputs preserve straight texture channels. Convert the
    // material result to the existing premultiplied main-pass contract here.
    return half4(half3(clamp(litColor * outputAlpha, 0.0, 65504.0)), half(outputAlpha));
}

struct SceneStaticModelShadowUniforms {
    float4x4 modelToLightClip;
    float4x4 modelMatrix;
    float4x4 worldToLight;
    float4 positionRadius;
    float4 projectionParameters;
    float4 viewport; // origin.xy, face extent.zw
    float4 textureFrame0;
    float4 textureFrame1;
    float4 coverage;
};
struct SceneStaticModelShadowVertexOut {
    float4 position [[position]];
    float2 uv;
    float3 lightPosition; // orthographic clip.xyz or perspective light coordinates
};
vertex float4 sceneStaticModelCameraDepthVertex(
    uint vertexID [[vertex_id]], constant SceneStaticModelVertex *vertices [[buffer(0)]],
    constant float4x4 &modelToClip [[buffer(1)]]) {
    return modelToClip * float4(vertices[vertexID].position, 1.0);
}

vertex SceneStaticModelShadowVertexOut sceneStaticModelShadowVertex(
    uint vertexID [[vertex_id]], constant SceneStaticModelVertex *vertices [[buffer(0)]],
    constant SceneStaticModelShadowUniforms &uniforms [[buffer(1)]]) {
    SceneStaticModelVertex modelVertex = vertices[vertexID];
    SceneStaticModelShadowVertexOut out;
    out.position = uniforms.modelToLightClip * float4(modelVertex.position, 1.0);
    out.lightPosition = out.position.xyz;
    out.uv = uniforms.textureFrame0.xy + modelVertex.uv.x * uniforms.textureFrame0.zw
        + modelVertex.uv.y * uniforms.textureFrame1.xy;
    return out;
}
void sceneStaticModelShadowCoverage(float2 uv, texture2d<float> albedo,
    sampler albedoSampler, constant SceneStaticModelShadowUniforms &uniforms) {
    float coverage = uniforms.coverage.x;
    if (uniforms.coverage.y != 0.0) coverage *= albedo.sample(albedoSampler, uv).a;
    if (coverage <= 0.5) discard_fragment();
}
struct SceneStaticModelShadowDepth { float depth [[depth(any)]]; };
SceneStaticModelShadowDepth sceneStaticModelDirectionalShadowDepth(
    SceneStaticModelShadowVertexOut in, float3 barycentric, bool correctCoverage,
    texture2d<float> albedo, sampler albedoSampler,
    constant SceneStaticModelShadowUniforms &uniforms) {
    // Reconstruct the authored triangle plane at the actual texel center;
    // interpolated clip coordinates follow the snapped raster triangle.
    float3 dx = dfdx(in.lightPosition), dy = dfdy(in.lightPosition);
    float3 plane = cross(dx, dy);
    float2 uv = (in.position.xy - uniforms.viewport.xy) / uniforms.viewport.zw;
    float2 clipXY = float2(2.0 * uv.x - 1.0, 1.0 - 2.0 * uv.y);
    float depth = in.lightPosition.z - dot(plane.xy / plane.z, clipXY - in.lightPosition.xy);
    float3 baryDX = dfdx(barycentric), baryDY = dfdy(barycentric);
    sceneStaticModelShadowCoverage(in.uv, albedo, albedoSampler, uniforms);
    if (correctCoverage) {
        float2 delta = clipXY - in.lightPosition.xy;
        float2 screenDelta = float2(delta.x * dy.y - delta.y * dy.x,
            dx.x * delta.y - dx.y * delta.x) / plane.z;
        float3 correctionX = baryDX * screenDelta.x, correctionY = baryDY * screenDelta.y;
        float3 corrected = barycentric + correctionX + correctionY;
        // Raster snapping can cover a texel outside the original triangle.
        // Its infinite plane must not become an occluder there.
        float3 margin = 8.0 * 1.1920928955078125e-7
            * (1.0 + abs(barycentric) + abs(correctionX) + abs(correctionY));
        if (any(corrected < -margin)) discard_fragment();
    }
    if (plane.z == 0.0 || !isfinite(depth) || depth < 0.0 || depth > 1.0) discard_fragment();
    return {depth};
}
fragment SceneStaticModelShadowDepth sceneStaticModelShadowFragment(
    SceneStaticModelShadowVertexOut in [[stage_in]],
    texture2d<float> albedo [[texture(0)]], sampler albedoSampler [[sampler(0)]],
    constant SceneStaticModelShadowUniforms &uniforms [[buffer(1)]]) {
    return sceneStaticModelDirectionalShadowDepth(in, float3(0.0), false, albedo, albedoSampler, uniforms);
}
fragment SceneStaticModelShadowDepth sceneStaticModelCoveredShadowFragment(
    SceneStaticModelShadowVertexOut in [[stage_in]], float3 barycentric [[barycentric_coord]],
    texture2d<float> albedo [[texture(0)]], sampler albedoSampler [[sampler(0)]],
    constant SceneStaticModelShadowUniforms &uniforms [[buffer(1)]]) {
    return sceneStaticModelDirectionalShadowDepth(in, barycentric, true, albedo, albedoSampler, uniforms);
}
vertex SceneStaticModelShadowVertexOut sceneStaticModelSpotShadowVertex(
    uint vertexID [[vertex_id]], constant SceneStaticModelVertex *vertices [[buffer(0)]],
    constant SceneStaticModelShadowUniforms &uniforms [[buffer(1)]]) {
    SceneStaticModelVertex modelVertex = vertices[vertexID];
    float3 world = (uniforms.modelMatrix * float4(modelVertex.position, 1.0)).xyz;
    float3 q = (uniforms.worldToLight * float4(world - uniforms.positionRadius.xyz, 0.0)).xyz;
    SceneStaticModelShadowVertexOut out;
    // Homogeneous clipping retains the forward part of triangles crossing the
    // light's apex plane. Fragment axial depth needs no arbitrary positive near.
    out.position = float4(q.xy / uniforms.projectionParameters.x, 0.0, q.z);
    out.lightPosition = q;
    out.uv = uniforms.textureFrame0.xy + modelVertex.uv.x * uniforms.textureFrame0.zw
        + modelVertex.uv.y * uniforms.textureFrame1.xy;
    return out;
}
float2 sceneStaticModelPerspectiveShadowDepth(SceneStaticModelShadowVertexOut in,
    texture2d<float> albedo, sampler albedoSampler,
    constant SceneStaticModelShadowUniforms &uniforms) {
    // Interpolated q stays on the triangle plane, but raster snapping shifts
    // its ray. Derivatives precede every branch and coverage discard.
    float3 n = cross(dfdx(in.lightPosition), dfdy(in.lightPosition));
    float2 uv = (in.position.xy - uniforms.viewport.xy) / uniforms.viewport.zw;
    float3 ray((2.0 * uv.x - 1.0) * uniforms.projectionParameters.x,
               (1.0 - 2.0 * uv.y) * uniforms.projectionParameters.x, 1.0);
    float denominator = dot(n, ray);
    float distance = dot(n, in.lightPosition) / denominator;
    float radialDistance = distance * length(ray);
    sceneStaticModelShadowCoverage(in.uv, albedo, albedoSampler, uniforms);
    // Edge-on triangles have no finite forward intersection for this ray.
    if (denominator == 0.0 || !isfinite(distance) || distance <= 0.0
        || radialDistance >= uniforms.positionRadius.w) discard_fragment();
    return float2(distance, radialDistance) / uniforms.positionRadius.w;
}
fragment SceneStaticModelShadowDepth sceneStaticModelSpotShadowFragment(
    SceneStaticModelShadowVertexOut in [[stage_in]],
    texture2d<float> albedo [[texture(0)]], sampler albedoSampler [[sampler(0)]],
    constant SceneStaticModelShadowUniforms &uniforms [[buffer(1)]]) {
    return {sceneStaticModelPerspectiveShadowDepth(in, albedo, albedoSampler, uniforms).x};
}
fragment SceneStaticModelShadowDepth sceneStaticModelPointShadowFragment(
    SceneStaticModelShadowVertexOut in [[stage_in]],
    texture2d<float> albedo [[texture(0)]], sampler albedoSampler [[sampler(0)]],
    constant SceneStaticModelShadowUniforms &uniforms [[buffer(1)]]) {
    return {sceneStaticModelPerspectiveShadowDepth(in, albedo, albedoSampler, uniforms).y};
}
