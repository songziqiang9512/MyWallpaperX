import Metal
import simd

private let sceneBloomShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct BloomVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct BloomUniforms {
    float4 thresholdGammaRadiusIntensity;
    float4 tint;
};

vertex BloomVaryings sceneBloomVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    BloomVaryings out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texcoord = texcoords[vertexID];
    return out;
}

fragment float4 sceneBloomThresholdFrag(
    BloomVaryings in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant BloomUniforms &u [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 color = source.sample(s, in.texcoord);
    float threshold = u.thresholdGammaRadiusIntensity.x;
    float gamma = u.thresholdGammaRadiusIntensity.y;
    float brightness = max(max(color.r, color.g), color.b);
    float gate = smoothstep(threshold, min(1.0, threshold + 0.2), brightness);
    float3 highlight = pow(max(color.rgb, float3(0.0)), float3(gamma)) * gate;
    return float4(highlight, color.a * gate);
}

fragment float4 sceneBloomCompositeFrag(
    BloomVaryings in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> bloom [[texture(1)]],
    constant BloomUniforms &u [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 base = source.sample(s, in.texcoord);
    float3 glow = bloom.sample(s, in.texcoord).rgb
        * u.tint.rgb
        * u.thresholdGammaRadiusIntensity.w;
    return float4(min(base.rgb + glow, float3(1.0)), base.a);
}
"""

private struct SceneBloomUniforms {
    let thresholdGammaRadiusIntensity: SIMD4<Float>
    let tint: SIMD4<Float>
}

struct SceneBloomPipeline {
    private let thresholdState: MTLRenderPipelineState
    private let compositeState: MTLRenderPipelineState

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(source: sceneBloomShaderSource, options: options),
              let vertex = library.makeFunction(name: "sceneBloomVert"),
              let threshold = library.makeFunction(name: "sceneBloomThresholdFrag"),
              let composite = library.makeFunction(name: "sceneBloomCompositeFrag"),
              let thresholdState = Self.makeState(
                device: device,
                vertex: vertex,
                fragment: threshold,
                pixelFormat: pixelFormat
              ),
              let compositeState = Self.makeState(
                device: device,
                vertex: vertex,
                fragment: composite,
                pixelFormat: pixelFormat
              ) else {
            return nil
        }
        self.thresholdState = thresholdState
        self.compositeState = compositeState
    }

    func encodeThreshold(
        source: MTLTexture,
        target: MTLTexture,
        plan: SceneBloomPlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        encode(
            state: thresholdState,
            source: source,
            secondary: source,
            target: target,
            plan: plan,
            commandBuffer: commandBuffer
        )
    }

    func encodeComposite(
        source: MTLTexture,
        bloom: MTLTexture,
        target: MTLTexture,
        plan: SceneBloomPlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        encode(
            state: compositeState,
            source: source,
            secondary: bloom,
            target: target,
            plan: plan,
            commandBuffer: commandBuffer
        )
    }

    private func encode(
        state: MTLRenderPipelineState,
        source: MTLTexture,
        secondary: MTLTexture,
        target: MTLTexture,
        plan: SceneBloomPlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(secondary, index: 1)
        var uniforms = SceneBloomUniforms(
            thresholdGammaRadiusIntensity: SIMD4(
                plan.threshold,
                plan.gamma,
                plan.radius,
                plan.intensity
            ),
            tint: SIMD4(plan.tint, 0)
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneBloomUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private static func makeState(
        device: MTLDevice,
        vertex: MTLFunction,
        fragment: MTLFunction,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}
