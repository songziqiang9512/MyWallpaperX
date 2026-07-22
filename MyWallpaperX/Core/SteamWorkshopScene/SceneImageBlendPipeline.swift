import Metal
import simd

private let sceneImageBlendShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct BlendVaryings {
    float4 position [[position]];
    float2 uv;
};

vertex BlendVaryings sceneImageBlendVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    BlendVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.uv = texcoords[vertexID];
    return output;
}

fragment float4 sceneImageBlendFrag(
    BlendVaryings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture2d<float> blendTexture [[texture(1)]],
    constant float4 &parameters [[buffer(0)]]
) {
    constexpr sampler sampler2d(filter::linear, address::clamp_to_edge);
    float4 source = sourceTexture.sample(sampler2d, input.uv);
    float4 blend = blendTexture.sample(sampler2d, input.uv);
    float coverageScale = clamp(parameters.x * parameters.y, 0.0, 1.0);
    float overlayAlpha = blend.a * coverageScale;
    float compositeAlpha = overlayAlpha + source.a * (1.0 - overlayAlpha);
    float3 compositeRGB = blend.rgb * coverageScale
        + source.rgb * (1.0 - overlayAlpha);

    float outputAlpha = parameters.z > 0.5 ? compositeAlpha : source.a;
    float3 outputRGB = compositeAlpha > 0.00001
        ? compositeRGB * (outputAlpha / compositeAlpha)
        : float3(0.0);
    return float4(outputRGB, outputAlpha);
}
"""

struct SceneImageBlendPipeline {
    private let state: MTLRenderPipelineState

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(
            source: sceneImageBlendShaderSource,
            options: options
        ), let vertex = library.makeFunction(name: "sceneImageBlendVert"),
        let fragment = library.makeFunction(name: "sceneImageBlendFrag") else {
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
        blend: MTLTexture,
        target: MTLTexture,
        multiply: Float,
        alphaMultiply: Float,
        writesAlpha: Bool,
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
        encoder.setFragmentTexture(blend, index: 1)
        var parameters = SIMD4(multiply, alphaMultiply, writesAlpha ? 1 : 0, 0)
        encoder.setFragmentBytes(&parameters, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }
}
