import Metal
import simd

// Quad vertex laid out to match the MSL struct QuadVertex below.
// Position is in model space (unit quad centered at origin); the model
// matrix scales it to the layer's size and places it in world space.
struct SceneQuadVertex {
    var position: SIMD2<Float>
    var texcoord: SIMD2<Float>
}

enum SceneLayerBlendMode {
    case sourceOver
    case additive
}

// Bitmask of effects the fragment shader applies inline. Each bit toggles a
// hand-written shader path that approximates the corresponding Wallpaper
// Engine effect. These are not faithful HLSL→MSL translations, just minimal
// visual stand-ins so animated layers move plausibly instead of sitting flat.
struct SceneEffectFlags: OptionSet {
    let rawValue: UInt32
    init(rawValue: UInt32) { self.rawValue = rawValue }

    static let foliagesway          = SceneEffectFlags(rawValue: 1 << 0)
    static let waterwaves           = SceneEffectFlags(rawValue: 1 << 1)
    static let cursorripple         = SceneEffectFlags(rawValue: 1 << 2)
    static let chromaticaberration  = SceneEffectFlags(rawValue: 1 << 3)
    static let irisMask             = SceneEffectFlags(rawValue: 1 << 4)
    static let opacityMask          = SceneEffectFlags(rawValue: 1 << 5)
    static let hasWaterMask         = SceneEffectFlags(rawValue: 1 << 6)
    static let shake                = SceneEffectFlags(rawValue: 1 << 7)
    static let hasShakeMask         = SceneEffectFlags(rawValue: 1 << 8)
    static let hasFoliageMask       = SceneEffectFlags(rawValue: 1 << 9)
    static let dependencyBlend      = SceneEffectFlags(rawValue: 1 << 10)
}

// Per-layer uniform packed for setFragmentBytes. Layout matches MSL struct
// LayerFragmentUniforms below; all vector fields stay 16-byte aligned.
struct SceneLayerFragmentUniforms {
    var time: Float
    var alpha: Float
    var effectFlags: UInt32
    var dependencyBlendMode: UInt32
    var cursorUV: SIMD2<Float>   // cursor in layer-local UV space ([0..1])
    var _pad1: SIMD2<Float>      // pad to 32 bytes
    var tint: SIMD4<Float>
    var effectParams0: SIMD4<Float>
    var effectParams1: SIMD4<Float>
    var effectParams2: SIMD4<Float>
    var effectParams3: SIMD4<Float>
    var effectParams4: SIMD4<Float>
    var effectParams5: SIMD4<Float>
    var textureFrame0: SIMD4<Float>
    var textureFrame1: SIMD4<Float>
}

// Embedded MSL. Vertex shader transforms a unit quad by an MVP supplied in
// buffer(1). Fragment shader optionally distorts UVs based on effectFlags
// before sampling and multiplies the result by per-layer alpha.
private let imageLayerShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct QuadVertex {
    float2 position;
    float2 texcoord;
};

struct QuadVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct LayerFragmentUniforms {
    float time;
    float alpha;
    uint  effectFlags;
    uint  dependencyBlendMode;
    float2 cursorUV;
    float2 _pad1;
    float4 tint;
    float4 effectParams0;
    float4 effectParams1;
    float4 effectParams2;
    float4 effectParams3;
    float4 effectParams4;
    float4 effectParams5;
    float4 textureFrame0;
    float4 textureFrame1;
};

float2 textureFrameUV(float2 uv, constant LayerFragmentUniforms &u) {
    return u.textureFrame0.xy
        + uv.x * u.textureFrame0.zw
        + uv.y * u.textureFrame1.xy;
}

constant uint EFFECT_FOLIAGESWAY         = 1u << 0;
constant uint EFFECT_WATERWAVES          = 1u << 1;
constant uint EFFECT_CURSORRIPPLE        = 1u << 2;
constant uint EFFECT_CHROMATICABERRATION = 1u << 3;
constant uint EFFECT_IRIS_MASK           = 1u << 4;
constant uint EFFECT_OPACITY_MASK        = 1u << 5;
constant uint EFFECT_HAS_WATER_MASK      = 1u << 6;
constant uint EFFECT_SHAKE               = 1u << 7;
constant uint EFFECT_HAS_SHAKE_MASK      = 1u << 8;
constant uint EFFECT_HAS_FOLIAGE_MASK    = 1u << 9;
constant uint EFFECT_DEPENDENCY_BLEND    = 1u << 10;

float foliageNoise(float2 point) {
    float2 cell = floor(point);
    float2 blend = fract(point);
    blend = blend * blend * (3.0 - 2.0 * blend);
    float a = fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
    float b = fract(sin(dot(cell + float2(1.0, 0.0), float2(127.1, 311.7))) * 43758.5453);
    float c = fract(sin(dot(cell + float2(0.0, 1.0), float2(127.1, 311.7))) * 43758.5453);
    float d = fract(sin(dot(cell + float2(1.0, 1.0), float2(127.1, 311.7))) * 43758.5453);
    return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

float4 foliageSignedPower(float4 value, float power) {
    return pow(abs(value), float4(power)) * sign(value);
}

vertex QuadVaryings sceneImageLayerVert(
    uint vid [[vertex_id]],
    constant QuadVertex *verts [[buffer(0)]],
    constant float4x4 &mvp [[buffer(1)]]
) {
    QuadVaryings out;
    out.position = mvp * float4(verts[vid].position, 0.0, 1.0);
    out.texcoord = verts[vid].texcoord;
    return out;
}

fragment float4 sceneImageLayerFrag(
    QuadVaryings in [[stage_in]],
    texture2d<float> tex [[texture(0)]],
    texture2d<float> shakeMaskTex [[texture(1)]],
    texture2d<float> waterMaskTex [[texture(2)]],
    texture2d<float> foliageMaskTex [[texture(3)]],
    texture2d<float> auxMaskTex [[texture(4)]],
    texture2d<float> dependencyTex [[texture(5)]],
    constant LayerFragmentUniforms &u [[buffer(0)]]
) {
    constexpr sampler s(
        min_filter::linear,
        mag_filter::linear,
        mip_filter::linear,
        address::clamp_to_edge
    );
    float2 uv = in.texcoord;
    float shakeMask = 1.0;
    if ((u.effectFlags & EFFECT_HAS_SHAKE_MASK) != 0u) {
        shakeMask = shakeMaskTex.sample(s, uv).r;
    }
    float waterMask = 1.0;
    if ((u.effectFlags & EFFECT_HAS_WATER_MASK) != 0u) {
        waterMask = waterMaskTex.sample(s, uv).r;
    }
    float foliageMask = 1.0;
    if ((u.effectFlags & EFFECT_HAS_FOLIAGE_MASK) != 0u) {
        foliageMask = foliageMaskTex.sample(
            s,
            clamp(uv * u.effectParams5.xy, 0.0, 1.0)
        ).r;
    }
    float auxMask = 1.0;
    bool usesAuxMask = (u.effectFlags & (EFFECT_IRIS_MASK | EFFECT_OPACITY_MASK)) != 0u;
    if (usesAuxMask) {
        auxMask = auxMaskTex.sample(s, uv).r;
    }

    if ((u.effectFlags & EFFECT_FOLIAGESWAY) != 0u) {
        float strength = u.effectParams3.x;
        float speed = u.effectParams3.y;
        float phaseAmount = u.effectParams3.z;
        float power = u.effectParams3.w;
        float noiseScale = u.effectParams4.x;
        float ratio = u.effectParams4.y;
        float direction = u.effectParams4.z;
        float sourceAspect = float(tex.get_width()) / max(float(tex.get_height()), 1.0);
        float aspect = max(sourceAspect * ratio, 0.001);
        float sine = sin(direction);
        float cosine = cos(direction);
        float2 directionScale = float2(
            cosine / aspect - sine * aspect,
            sine / aspect + cosine * aspect
        );
        float2 rotatedUV = float2(
            cosine * uv.x - sine * uv.y,
            sine * uv.x + cosine * uv.y
        );
        float noise = foliageNoise(uv * max(noiseScale, 0.0001) * 32.0);
        float phase = (noise * 6.2831853 + rotatedUV.x * 10.0 + rotatedUV.y * 5.0)
            * phaseAmount;
        float4 waves = foliageSignedPower(
            sin(phase + speed * u.time * float4(1.0, -0.16161616, 0.0083333, -0.00019841)),
            power
        );
        float4 crossWaves = foliageSignedPower(
            sin(0.4 + phase + speed * u.time * float4(-0.5, 0.041666666, -0.0013888889, 0.000024801587)),
            power
        );
        float amplitude = strength * strength * 0.005 * foliageMask;
        uv.x += directionScale.x * (waves.x + waves.y + waves.z + waves.w) * amplitude;
        uv.y += directionScale.y
            * (crossWaves.x + crossWaves.y + crossWaves.z + crossWaves.w) * amplitude;
    }

    // shake: simple left-right breathing-style translation using the authored
    // speed/strength pair. Wallpaper Engine supports more masks and direction
    // controls than this first-stage runtime currently carries.
    if ((u.effectFlags & EFFECT_SHAKE) != 0u) {
        float speed = max(u.effectParams3.x, 0.001);
        float strength = max(u.effectParams3.y, 0.0);
        float friction = max(u.effectParams3.z, 0.001);
        float wave = sin(u.time * speed * 6.2831853);
        wave = sign(wave) * pow(abs(wave), friction);
        uv.x += wave * strength * 0.010 * shakeMask;
    }

    // waterwaves / waterripple: directional local distortion driven by the
    // layer's own mask + authored parameters.
    if ((u.effectFlags & EFFECT_WATERWAVES) != 0u) {
        float scale = max(u.effectParams2.x, 0.001);
        float speed = max(u.effectParams2.y, 0.001);
        float strength = max(u.effectParams2.z, 0.0);
        float direction = u.effectParams2.w;
        float2 axis = float2(cos(direction), sin(direction));
        float2 normal = float2(-axis.y, axis.x);
        float phase = dot(uv, axis) * scale * 6.2831853;
        float wave0 = sin(phase + u.time * speed);
        float wave1 = cos(phase * 0.67 + u.time * speed * 0.73);
        uv += normal * (wave0 * strength * 0.020) * waterMask;
        uv += axis   * (wave1 * strength * 0.010) * waterMask;
    }

    // cursorripple: concentric ring around the cursor position in this
    // layer's UV space, attenuated by distance so the effect is local.
    if ((u.effectFlags & EFFECT_CURSORRIPPLE) != 0u) {
        float2 d = uv - u.cursorUV;
        float dist = length(d);
        float decay = exp(-dist * 7.0);
        if (decay > 0.005) {
            float wave = sin(dist * 32.0 - u.time * 6.0) * decay;
            float2 dir = dist > 0.0001 ? d / dist : float2(0.0);
            uv += dir * wave * 0.006 * foliageMask;
        }
    }

    float2 sampleUV = uv;
    if ((u.effectFlags & EFFECT_IRIS_MASK) != 0u) {
        float irisScaleX = u.effectParams0.x;
        float irisScaleY = u.effectParams0.y;
        float irisSpeed = u.effectParams0.z;
        float irisPhase = u.effectParams0.w;
        float irisRough = u.effectParams1.x;
        float irisNoise = u.effectParams1.y;

        float t = (u.time * irisSpeed) + irisPhase;
        float lowDt = floor(t);
        float2 motion2 = sin(1.9 * float2(lowDt, lowDt + 1.0));
        float4 motion4 = sin(2.5 * float4(lowDt, lowDt, lowDt + 1.0, lowDt + 1.0) + float4(1.0, 2.0, 1.0, 2.0));
        float2 moveStart = motion2.xx + motion4.xy;
        float2 moveEnd = motion2.yy + motion4.zw;
        float blend = smoothstep(1.0 - irisRough, 1.0, cos(fract(t) * 3.14159265) * -0.5 + 0.5);
        float2 irisOffset = mix(moveStart, moveEnd, blend);
        irisOffset.x += sin(t) * irisNoise;
        irisOffset.y += cos(t) * irisNoise;
        irisOffset *= float2(irisScaleX, irisScaleY) * 0.001;
        sampleUV += irisOffset * auxMask;
    }

    // chromaticaberration: per-channel UV offset along the radial direction
    // (distance from the texture center) producing a subtle RGB fringe.
    float4 color;
    if ((u.effectFlags & EFFECT_CHROMATICABERRATION) != 0u) {
        float2 d = sampleUV - 0.5;
        float2 off = d * 0.004;
        float r = tex.sample(s, textureFrameUV(clamp(sampleUV - off, 0.0, 1.0), u)).r;
        float g = tex.sample(s, textureFrameUV(clamp(sampleUV,       0.0, 1.0), u)).g;
        float b = tex.sample(s, textureFrameUV(clamp(sampleUV + off, 0.0, 1.0), u)).b;
        float a = tex.sample(s, textureFrameUV(clamp(sampleUV,       0.0, 1.0), u)).a;
        color = float4(r, g, b, a);
    } else {
        color = tex.sample(s, textureFrameUV(clamp(sampleUV, 0.0, 1.0), u));
    }

    if ((u.effectFlags & EFFECT_OPACITY_MASK) != 0u) {
        float opacity = auxMask * u.effectParams1.z;
        color *= opacity;
    }

    if ((u.effectFlags & EFFECT_DEPENDENCY_BLEND) != 0u) {
        float3 target = dependencyTex.sample(s, clamp(in.texcoord, 0.0, 1.0)).rgb;
        if (u.dependencyBlendMode == 0u) {
            color.rgb = mix(color.rgb, target, color.a);
        } else if (u.dependencyBlendMode == 5u) {
            color.rgb = min(color.rgb, target);
        }
    }

    return color * u.tint * u.alpha;
}
"""

struct SceneImageLayerPipeline {
    let state: MTLRenderPipelineState

    // Unit quad centered at origin, +Y up. The vertex MVP scales/translates it
    // into world space. UV convention: top-left (0,0) -> matches the flip done
    // by SceneTextureLoader.
    //
    // triangleStrip order: BL → BR → TL → TR.
    private static let unitQuadVertices: [SceneQuadVertex] = [
        SceneQuadVertex(position: SIMD2(-0.5, -0.5), texcoord: SIMD2(0, 1)),
        SceneQuadVertex(position: SIMD2( 0.5, -0.5), texcoord: SIMD2(1, 1)),
        SceneQuadVertex(position: SIMD2(-0.5,  0.5), texcoord: SIMD2(0, 0)),
        SceneQuadVertex(position: SIMD2( 0.5,  0.5), texcoord: SIMD2(1, 0))
    ]

    init?(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        blendMode: SceneLayerBlendMode = .sourceOver
    ) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(source: imageLayerShaderSource, options: options),
              let vertFn = library.makeFunction(name: "sceneImageLayerVert"),
              let fragFn = library.makeFunction(name: "sceneImageLayerFrag") else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertFn
        descriptor.fragmentFunction = fragFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        // Premultiplied source-over: data was uploaded via CGContext with
        // premultipliedLast, so rgb is already alpha-scaled.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = blendMode == .additive ? .one : .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.state = state
    }

    // Sets pipeline state + vertex quad buffer once per encoder. Call drawLayer
    // per layer after binding.
    func bind(encoder: MTLRenderCommandEncoder) {
        encoder.setRenderPipelineState(state)
        var vertices = Self.unitQuadVertices
        encoder.setVertexBytes(
            &vertices,
            length: vertices.count * MemoryLayout<SceneQuadVertex>.stride,
            index: 0
        )
    }

    func drawLayer(
        texture: MTLTexture,
        shakeMaskTexture: MTLTexture?,
        waterMaskTexture: MTLTexture?,
        foliageMaskTexture: MTLTexture?,
        auxMaskTexture: MTLTexture?,
        dependencyTexture: MTLTexture? = nil,
        mvp: simd_float4x4,
        uniforms: SceneLayerFragmentUniforms,
        encoder: MTLRenderCommandEncoder
    ) {
        var mvpCopy = mvp
        encoder.setVertexBytes(&mvpCopy, length: MemoryLayout<simd_float4x4>.size, index: 1)
        var uniformsCopy = uniforms
        encoder.setFragmentBytes(&uniformsCopy, length: MemoryLayout<SceneLayerFragmentUniforms>.size, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(shakeMaskTexture ?? texture, index: 1)
        encoder.setFragmentTexture(waterMaskTexture ?? texture, index: 2)
        encoder.setFragmentTexture(foliageMaskTexture ?? texture, index: 3)
        encoder.setFragmentTexture(auxMaskTexture ?? texture, index: 4)
        encoder.setFragmentTexture(dependencyTexture ?? texture, index: 5)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
