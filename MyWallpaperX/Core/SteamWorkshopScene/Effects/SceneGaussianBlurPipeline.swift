import Metal
import simd

private let sceneGaussianBlurShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct BlurVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex BlurVaryings sceneGaussianBlurVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    BlurVaryings out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texcoord = texcoords[vertexID];
    return out;
}

fragment float4 sceneGaussianBlurFrag(
    BlurVaryings in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant float4 &step [[buffer(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 offset = step.xy;
    float4 color = source.sample(s, in.texcoord) * 0.2270270270;
    color += source.sample(s, in.texcoord + offset * 1.3846153846) * 0.3162162162;
    color += source.sample(s, in.texcoord - offset * 1.3846153846) * 0.3162162162;
    color += source.sample(s, in.texcoord + offset * 3.2307692308) * 0.0702702703;
    color += source.sample(s, in.texcoord - offset * 3.2307692308) * 0.0702702703;
    return color;
}
"""

struct SceneGaussianBlurPipeline {
    private let state: MTLRenderPipelineState

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(source: sceneGaussianBlurShaderSource, options: options),
              let vertex = library.makeFunction(name: "sceneGaussianBlurVert"),
              let fragment = library.makeFunction(name: "sceneGaussianBlurFrag") else {
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
        target: MTLTexture,
        step: SIMD2<Float>,
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
        var stepUniform = SIMD4<Float>(step.x, step.y, 0, 0)
        encoder.setFragmentBytes(&stepUniform, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }
}
