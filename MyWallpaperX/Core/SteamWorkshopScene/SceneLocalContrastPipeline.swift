import Metal
import simd

private let sceneLocalContrastShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct LocalContrastVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex LocalContrastVaryings sceneLocalContrastVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    LocalContrastVaryings out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texcoord = texcoords[vertexID];
    return out;
}

fragment float4 sceneLocalContrastDownsampleFrag(
    LocalContrastVaryings in [[stage_in]],
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

constant float localContrastWeights[13] = {
    0.006299, 0.017298, 0.039533, 0.075189, 0.119007, 0.156756, 0.171834,
    0.156756, 0.119007, 0.075189, 0.039533, 0.017298, 0.006299
};

fragment float4 sceneLocalContrastGaussianFrag(
    LocalContrastVaryings in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant float4 &step [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 result = float4(0.0);
    for (uint index = 0; index < 13; ++index) {
        float offset = float(int(index) - 6);
        result += source.sample(s, in.texcoord + step.xy * offset)
            * localContrastWeights[index];
    }
    return result;
}

fragment float4 sceneLocalContrastCombineFrag(
    LocalContrastVaryings in [[stage_in]],
    texture2d<float> blurredTexture [[texture(0)]],
    texture2d<float> previousTexture [[texture(2)]],
    constant float &strength [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 blurred = blurredTexture.sample(s, in.texcoord);
    float4 albedo = previousTexture.sample(s, in.texcoord);
    float3 enhanced = albedo.rgb + (albedo.rgb - blurred.rgb) * strength;
    return float4(enhanced, albedo.a);
}
"""

struct SceneLocalContrastPipeline {
    private let downsampleState: MTLRenderPipelineState
    private let gaussianState: MTLRenderPipelineState
    private let combineState: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(
            source: sceneLocalContrastShaderSource,
            options: options
        ), let vertex = library.makeFunction(name: "sceneLocalContrastVert"),
        let downsample = Self.makeState(
            device: device,
            vertex: vertex,
            library: library,
            fragmentName: "sceneLocalContrastDownsampleFrag",
            pixelFormat: .rgba8Unorm
        ), let gaussian = Self.makeState(
            device: device,
            vertex: vertex,
            library: library,
            fragmentName: "sceneLocalContrastGaussianFrag",
            pixelFormat: .rgba8Unorm
        ), let combine = Self.makeState(
            device: device,
            vertex: vertex,
            library: library,
            fragmentName: "sceneLocalContrastCombineFrag",
            pixelFormat: .bgra8Unorm
        ) else {
            return nil
        }
        downsampleState = downsample
        gaussianState = gaussian
        combineState = combine
        deviceRegistryID = device.registryID
    }

    func encodeDownsample(
        source: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard validTexture(source, format: .bgra8Unorm, usage: .shaderRead),
              validTexture(target, format: .rgba8Unorm, usage: .renderTarget),
              target.width == max(1, source.width / 4),
              target.height == max(1, source.height / 4),
              distinct(source, target),
              validDevice([source, target], commandBuffer: commandBuffer) else {
            return false
        }
        return encode(
            state: downsampleState,
            target: target,
            commandBuffer: commandBuffer
        ) { encoder in
            encoder.setFragmentTexture(source, index: 0)
        }
    }

    func encodeGaussian(
        source: MTLTexture,
        target: MTLTexture,
        step: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard validTexture(source, format: .rgba8Unorm, usage: .shaderRead),
              validTexture(target, format: .rgba8Unorm, usage: .renderTarget),
              source.width == target.width,
              source.height == target.height,
              step.x.isFinite,
              step.y.isFinite,
              step.x >= 0,
              step.y >= 0,
              (step.x == 0) != (step.y == 0),
              distinct(source, target),
              validDevice([source, target], commandBuffer: commandBuffer) else {
            return false
        }
        return encode(
            state: gaussianState,
            target: target,
            commandBuffer: commandBuffer
        ) { encoder in
            encoder.setFragmentTexture(source, index: 0)
            var uniform = SIMD4<Float>(step.x, step.y, 0, 0)
            encoder.setFragmentBytes(
                &uniform,
                length: MemoryLayout<SIMD4<Float>>.size,
                index: 0
            )
        }
    }

    func encodeCombine(
        blurred: MTLTexture,
        previous: MTLTexture,
        strength: Float,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard validTexture(blurred, format: .rgba8Unorm, usage: .shaderRead),
              validTexture(previous, format: .bgra8Unorm, usage: .shaderRead),
              validTexture(target, format: .bgra8Unorm, usage: .renderTarget),
              previous.width == target.width,
              previous.height == target.height,
              blurred.width == max(1, previous.width / 4),
              blurred.height == max(1, previous.height / 4),
              strength.isFinite,
              (0...5).contains(strength),
              distinct(blurred, previous),
              distinct(blurred, target),
              distinct(previous, target),
              validDevice([blurred, previous, target], commandBuffer: commandBuffer) else {
            return false
        }
        return encode(
            state: combineState,
            target: target,
            commandBuffer: commandBuffer
        ) { encoder in
            encoder.setFragmentTexture(blurred, index: 0)
            encoder.setFragmentTexture(previous, index: 2)
            var uniform = strength
            encoder.setFragmentBytes(
                &uniform,
                length: MemoryLayout<Float>.size,
                index: 0
            )
        }
    }

    private func validTexture(
        _ texture: MTLTexture,
        format: MTLPixelFormat,
        usage: MTLTextureUsage
    ) -> Bool {
        texture.textureType == .type2D
            && texture.pixelFormat == format
            && texture.width > 0
            && texture.height > 0
            && texture.mipmapLevelCount == 1
            && texture.sampleCount == 1
            && texture.usage.contains(usage)
    }

    private func validDevice(
        _ textures: [MTLTexture],
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && textures.allSatisfy { $0.device.registryID == deviceRegistryID }
    }

    private func distinct(_ lhs: MTLTexture, _ rhs: MTLTexture) -> Bool {
        ObjectIdentifier(lhs) != ObjectIdentifier(rhs)
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
