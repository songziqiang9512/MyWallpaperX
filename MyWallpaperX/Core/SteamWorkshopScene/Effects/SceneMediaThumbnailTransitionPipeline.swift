import Metal
import simd

private let sceneMediaThumbnailTransitionShader = """
#include <metal_stdlib>
using namespace metal;

struct MediaTransitionVaryings {
    float4 position [[position]];
    float2 uv;
};

struct MediaTransitionUniforms {
    float4 parameters;
    float2 gradientUVScale;
    float2 padding;
};

vertex MediaTransitionVaryings sceneMediaTransitionVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    MediaTransitionVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.uv = texcoords[vertexID];
    return output;
}

fragment float4 sceneMediaTransitionFrag(
    MediaTransitionVaryings input [[stage_in]],
    texture2d<float> current [[texture(0)]],
    texture2d<float> previous [[texture(1)]],
    texture2d<float> gradient [[texture(2)]],
    sampler gradientSampler [[sampler(0)]],
    constant MediaTransitionUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler colorSampler(
        min_filter::linear, mag_filter::linear, mip_filter::linear,
        address::clamp_to_edge
    );
    float4 currentColor = current.sample(colorSampler, input.uv);
    float4 previousColor = previous.sample(colorSampler, input.uv);
    float amount = uniforms.parameters.x;
    if (amount <= 0.000001) { return currentColor; }
    if (amount >= 0.999999) { return previousColor; }
    float width = uniforms.parameters.y;
    float mask = gradient.sample(
        gradientSampler,
        input.uv * uniforms.gradientUVScale
    ).r;
    float previousWeight = 1.0 - smoothstep(amount - width, amount + width, mask);
    return mix(currentColor, previousColor, previousWeight);
}
"""

struct SceneMediaThumbnailTransitionPipeline {
    private struct Uniforms {
        var parameters: SIMD4<Float>
        var gradientUVScale: SIMD2<Float>
        var padding: SIMD2<Float> = .zero
    }

    private let state: MTLRenderPipelineState
    private let samplers: SceneTextureSamplerStateSet
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice) {
        let options = MTLCompileOptions()
        guard let samplers = SceneTextureSamplerStateSet(device: device),
              let library = try? device.makeLibrary(
                  source: sceneMediaThumbnailTransitionShader,
                  options: options
              ),
              let vertex = library.makeFunction(name: "sceneMediaTransitionVert"),
              let fragment = library.makeFunction(name: "sceneMediaTransitionFrag") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.state = state
        self.samplers = samplers
        deviceRegistryID = device.registryID
    }

    func encode(
        current: MTLTexture,
        previous: MTLTexture,
        gradient: SceneMediaThumbnailTransitionTexture.Arguments,
        target: MTLTexture,
        amount: Float,
        gradientScale: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(
            current: current,
            previous: previous,
            gradient: gradient,
            target: target,
            amount: amount,
            gradientScale: gradientScale,
            commandBuffer: commandBuffer
        ) else { return false }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        ) else { return false }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(current, index: 0)
        encoder.setFragmentTexture(previous, index: 1)
        encoder.setFragmentTexture(gradient.texture, index: 2)
        encoder.setFragmentSamplerState(
            samplers.state(for: gradient.sampling),
            index: 0
        )
        var uniforms = Uniforms(
            parameters: SIMD4(amount, gradientScale, 0, 0),
            gradientUVScale: gradient.uvScale
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
        encoder.endEncoding()
        return true
    }

    private func valid(
        current: MTLTexture,
        previous: MTLTexture,
        gradient: SceneMediaThumbnailTransitionTexture.Arguments,
        target: MTLTexture,
        amount: Float,
        gradientScale: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let colors: Set<MTLPixelFormat> = [.rgba8Unorm, .bgra8Unorm]
        let masks: Set<MTLPixelFormat> = [
            .r8Unorm, .rg8Unorm, .rgba8Unorm, .bgra8Unorm,
        ]
        let textures = [current, previous, gradient.texture, target]
        return amount.isFinite
            && (0...1).contains(amount)
            && gradientScale.isFinite
            && (0.01...0.25).contains(gradientScale)
            && gradient.uvScale.x.isFinite
            && gradient.uvScale.y.isFinite
            && gradient.uvScale.min() > 0
            && gradient.uvScale.max() <= 1
            && !gradient.sampling.usesClampBorderFallback
            && colors.contains(current.pixelFormat)
            && colors.contains(previous.pixelFormat)
            && masks.contains(gradient.texture.pixelFormat)
            && target.pixelFormat == .bgra8Unorm
            && textures.allSatisfy {
                $0.device.registryID == deviceRegistryID
                    && $0.textureType == .type2D
                    && $0.width > 0
                    && $0.height > 0
                    && $0.sampleCount == 1
            }
            && current.usage.contains(.shaderRead)
            && previous.usage.contains(.shaderRead)
            && gradient.texture.usage.contains(.shaderRead)
            && target.usage.contains(.shaderRead)
            && target.usage.contains(.renderTarget)
            && target.width == current.width
            && target.height == current.height
            && textures.dropLast().allSatisfy {
                ObjectIdentifier($0) != ObjectIdentifier(target)
            }
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
    }
}
