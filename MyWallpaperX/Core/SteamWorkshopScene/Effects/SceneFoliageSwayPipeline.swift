import Metal
import simd

private let sceneFoliageSwayShader = """
#include <metal_stdlib>
using namespace metal;

struct FoliageVaryings {
    float4 position [[position]];
    float2 uv;
};

struct FoliageUniforms {
    float4 motion; // strength, speed, phase, power
    float4 noise;  // scale, ratio, direction, time
    float2 maskUVScale;
    float hasMask;
    float padding;
};

vertex FoliageVaryings sceneFoliageSwayVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    FoliageVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.uv = texcoords[vertexID];
    return output;
}

float4 sceneFoliageSignedPower(float4 value, float power) {
    return pow(abs(value), float4(power)) * sign(value);
}

fragment float4 sceneFoliageSwayFrag(
    FoliageVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    texture2d<float> noiseTexture [[texture(2)]],
    constant FoliageUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr sampler linearRepeat(filter::linear, address::repeat);
    float2 uv = input.uv;
    float mask = 1.0;
    if (u.hasMask > 0.5) {
        mask = maskTexture.sample(
            linearClamp,
            clamp(uv * u.maskUVScale, 0.0, 1.0)
        ).r;
    }
    float sourceAspect = float(source.get_width()) / max(float(source.get_height()), 1.0);
    float aspect = max(sourceAspect * u.noise.y, 0.001);
    float sine = sin(u.noise.z);
    float cosine = cos(u.noise.z);
    float2 directionScale = float2(
        cosine / aspect - sine * aspect,
        sine / aspect + cosine * aspect
    );
    float2 rotatedUV = float2(
        cosine * uv.x - sine * uv.y,
        sine * uv.x + cosine * uv.y
    );
    float sampledNoise = noiseTexture.sample(
        linearRepeat,
        uv * u.noise.x
    ).g;
    float phase = (
        sampledNoise * 6.2831853 + rotatedUV.x * 10.0 + rotatedUV.y * 5.0
    ) * u.motion.z;
    float4 waves = sceneFoliageSignedPower(
        sin(phase + u.motion.y * u.noise.w
            * float4(1.0, -0.16161616, 0.0083333, -0.00019841)),
        u.motion.w
    );
    float4 crossWaves = sceneFoliageSignedPower(
        sin(0.4 + phase + u.motion.y * u.noise.w
            * float4(-0.5, 0.041666666, -0.0013888889, 0.000024801587)),
        u.motion.w
    );
    float amplitude = u.motion.x * u.motion.x * 0.005 * mask;
    uv.x += directionScale.x * (waves.x + waves.y + waves.z + waves.w) * amplitude;
    uv.y += directionScale.y
        * (crossWaves.x + crossWaves.y + crossWaves.z + crossWaves.w) * amplitude;
    return source.sample(linearClamp, uv);
}
"""

struct SceneFoliageSwayPipeline {
    private struct Uniforms {
        var motion: SIMD4<Float>
        var noise: SIMD4<Float>
        var maskUVScale: SIMD2<Float>
        var hasMask: Float
        var padding: Float = 0
    }

    private let state: MTLRenderPipelineState

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let library = try? device.makeLibrary(
            source: sceneFoliageSwayShader,
            options: MTLCompileOptions()
        ),
        let vertex = library.makeFunction(name: "sceneFoliageSwayVert"),
        let fragment = library.makeFunction(name: "sceneFoliageSwayFrag")
        else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.state = state
    }

    func encode(
        source: MTLTexture,
        mask: MTLTexture?,
        noise: MTLTexture,
        target: MTLTexture,
        plan: SceneFoliageSwayPlan,
        maskUVScale: SIMD2<Float>,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard source !== target,
              time.isFinite,
              validMask(mask, uvScale: maskUVScale) else {
            return false
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else {
            return false
        }
        var uniforms = Uniforms(
            motion: SIMD4(plan.strength, plan.speed, plan.phase, plan.power),
            noise: SIMD4(plan.noiseScale, plan.ratio, plan.direction, time),
            maskUVScale: maskUVScale,
            hasMask: mask == nil ? 0 : 1
        )
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 0
        )
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(mask ?? source, index: 1)
        encoder.setFragmentTexture(noise, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func validMask(
        _ mask: MTLTexture?,
        uvScale: SIMD2<Float>
    ) -> Bool {
        guard mask != nil else { return true }
        return uvScale.x.isFinite
            && uvScale.y.isFinite
            && uvScale.x > 0
            && uvScale.y > 0
    }
}
