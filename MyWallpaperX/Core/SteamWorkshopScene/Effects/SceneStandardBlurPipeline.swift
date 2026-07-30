import Metal
import simd

private struct SceneStandardBlurCombineUniforms {
    var maskUVScale: SIMD2<Float>
    var hasMask: UInt32
    var padding: UInt32 = 0
}

// Stock Blur produces straight-alpha effect output; the final fragment converts it
// back to the premultiplied convention used by the host compositor.
private let sceneStandardBlurShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct StandardBlurVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct StandardBlurCombineUniforms {
    float2 maskUVScale;
    uint hasMask;
    uint padding;
};

vertex StandardBlurVaryings sceneStandardBlurVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    StandardBlurVaryings out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texcoord = texcoords[vertexID];
    return out;
}

fragment float4 sceneStandardBlurDownsampleFrag(
    StandardBlurVaryings in [[stage_in]],
    texture2d<float> source [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
    const float2 signs[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    float4 result = float4(0.0);
    float weight = 0.0;
    for (uint index = 0; index < 4; ++index) {
        float4 value = source.sample(s, in.texcoord + texel * signs[index]);
        result += value * value.a;
        weight += value.a;
    }
    return float4(result.rgb / max(0.001, weight), result.a * 0.25);
}

constant float standardBlurWeights[13] = {
    0.006299, 0.017298, 0.039533, 0.075189, 0.119007, 0.156756, 0.171834,
    0.156756, 0.119007, 0.075189, 0.039533, 0.017298, 0.006299
};

fragment float4 sceneStandardBlurGaussianFrag(
    StandardBlurVaryings in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant float4 &step [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 result = float4(0.0);
    for (uint index = 0; index < 13; ++index) {
        float offset = float(int(index) - 6);
        result += source.sample(s, in.texcoord + step.xy * offset)
            * standardBlurWeights[index];
    }
    return result;
}

fragment float4 sceneStandardBlurCombineFrag(
    StandardBlurVaryings in [[stage_in]],
    texture2d<float> blurredTexture [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    texture2d<float> previousTexture [[texture(2)]],
    sampler maskSampler [[sampler(0)]],
    constant StandardBlurCombineUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 blurred = blurredTexture.sample(s, in.texcoord);
    float4 previous = previousTexture.sample(s, in.texcoord);
    float divisor = blurred.a > 0.0 ? blurred.a : 1.0;
    float4 effectStraight = float4(blurred.rgb / divisor, blurred.a);
    float4 effect = float4(effectStraight.rgb * effectStraight.a, effectStraight.a);
    float mask = uniforms.hasMask == 0u
        ? 1.0
        : maskTexture.sample(maskSampler, in.texcoord * uniforms.maskUVScale).r;
    return mix(previous, effect, clamp(mask, 0.0, 1.0));
}
"""

struct SceneStandardBlurPipeline {
    private let downsampleState: MTLRenderPipelineState
    private let gaussianState: MTLRenderPipelineState
    private let combineState: MTLRenderPipelineState
    private let samplerStates: SceneTextureSamplerStateSet

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(
            source: sceneStandardBlurShaderSource,
            options: options
        ), let vertex = library.makeFunction(name: "sceneStandardBlurVert"),
        let downsample = Self.makeState(
            device: device, vertex: vertex, library: library,
            fragmentName: "sceneStandardBlurDownsampleFrag", pixelFormat: pixelFormat
        ), let gaussian = Self.makeState(
            device: device, vertex: vertex, library: library,
            fragmentName: "sceneStandardBlurGaussianFrag", pixelFormat: pixelFormat
        ), let combine = Self.makeState(
            device: device, vertex: vertex, library: library,
            fragmentName: "sceneStandardBlurCombineFrag", pixelFormat: pixelFormat
        ), let samplerStates = SceneTextureSamplerStateSet(device: device) else {
            return nil
        }
        downsampleState = downsample
        gaussianState = gaussian
        combineState = combine
        self.samplerStates = samplerStates
    }

    func encodeDownsample(
        source: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        encode(state: downsampleState, target: target, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(source, index: 0)
        }
    }

    func encodeGaussian(
        source: MTLTexture,
        target: MTLTexture,
        step: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        encode(state: gaussianState, target: target, commandBuffer: commandBuffer) { encoder in
            encoder.setFragmentTexture(source, index: 0)
            var uniform = SIMD4<Float>(step.x, step.y, 0, 0)
            encoder.setFragmentBytes(
                &uniform, length: MemoryLayout<SIMD4<Float>>.size, index: 0
            )
        }
    }

    func encodeCombine(
        blurred: MTLTexture,
        mask: MTLTexture? = nil,
        maskUVScale: SIMD2<Float> = SIMD2(repeating: 1),
        maskSampling: SceneTextureSampling = .linearClamp,
        previous: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard maskUVScale.x.isFinite,
              maskUVScale.y.isFinite,
              maskUVScale.min() > 0,
              maskUVScale.max() <= 1,
              validMask(mask) else {
            return false
        }
        return encode(
            state: combineState,
            target: target,
            commandBuffer: commandBuffer
        ) { encoder in
            encoder.setFragmentTexture(blurred, index: 0)
            encoder.setFragmentTexture(mask ?? previous, index: 1)
            encoder.setFragmentTexture(previous, index: 2)
            encoder.setFragmentSamplerState(
                samplerStates.state(for: maskSampling),
                index: 0
            )
            var uniforms = SceneStandardBlurCombineUniforms(
                maskUVScale: maskUVScale,
                hasMask: mask == nil ? 0 : 1
            )
            encoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<SceneStandardBlurCombineUniforms>.stride,
                index: 0
            )
        }
    }

    private func validMask(_ mask: MTLTexture?) -> Bool {
        guard let mask else { return true }
        return mask.textureType == .type2D
            && [.r8Unorm, .rg8Unorm, .rgba8Unorm, .bgra8Unorm].contains(mask.pixelFormat)
            && mask.width > 0
            && mask.height > 0
            && mask.mipmapLevelCount > 0
            && mask.sampleCount == 1
            && mask.usage.contains(.shaderRead)
    }

    private func encode(
        state: MTLRenderPipelineState,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        bindings: (MTLRenderCommandEncoder) -> Void
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
        bindings(encoder)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private static func makeState(
        device: MTLDevice,
        vertex: MTLFunction,
        library: MTLLibrary,
        fragmentName: String,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        guard let fragment = library.makeFunction(name: fragmentName) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}
