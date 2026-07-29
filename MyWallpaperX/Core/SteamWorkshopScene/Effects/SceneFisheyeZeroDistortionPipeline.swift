import Metal
import simd

private let sceneFisheyeZeroDistortionShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct SceneFisheyeZeroDistortionVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct SceneFisheyeZeroDistortionUniforms {
    float2 center;
    float size;
};

vertex SceneFisheyeZeroDistortionVaryings sceneFisheyeZeroDistortionVert(
    uint vertexID [[vertex_id]]
) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    SceneFisheyeZeroDistortionVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneFisheyeZeroDistortionFrag(
    SceneFisheyeZeroDistortionVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant SceneFisheyeZeroDistortionUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float radius = uniforms.size * 0.5;
    float inside = distance(input.texcoord, uniforms.center) <= radius ? 1.0 : 0.0;
    // Scene textures are premultiplied. Clip every channel so transparent pixels
    // remain valid inputs to the shared source-over compositor.
    return source.sample(linearClamp, input.texcoord) * inside;
}
"""

struct SceneFisheyeZeroDistortionPipeline {
    struct Uniforms {
        var center: SIMD2<Float>
        var size: Float
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneFisheyeZeroDistortionShaderSource,
                  options: nil
              ),
              let vertex = library.makeFunction(
                  name: "sceneFisheyeZeroDistortionVert"
              ),
              let fragment = library.makeFunction(
                  name: "sceneFisheyeZeroDistortionFrag"
              ) else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let state = try? device.makeRenderPipelineState(
            descriptor: descriptor
        ) else {
            return nil
        }
        self.state = state
        deviceRegistryID = device.registryID
    }

    func encode(
        source: MTLTexture,
        target: MTLTexture,
        uniforms: Uniforms,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(
            source: source,
            target: target,
            uniforms: uniforms,
            commandBuffer: commandBuffer
        ) else {
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
        var uniforms = uniforms
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(
        source: MTLTexture,
        target: MTLTexture,
        uniforms: Uniforms,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        source.textureType == .type2D
            && target.textureType == .type2D
            && source.pixelFormat == .bgra8Unorm
            && target.pixelFormat == .bgra8Unorm
            && source.width > 0
            && source.width == target.width
            && source.height > 0
            && source.height == target.height
            && source.mipmapLevelCount == 1
            && target.mipmapLevelCount == 1
            && source.sampleCount == 1
            && target.sampleCount == 1
            && source.usage.contains(.shaderRead)
            && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && uniforms.center.x.isFinite
            && uniforms.center.y.isFinite
            && (0 ... 1).contains(uniforms.center.x)
            && (0 ... 1).contains(uniforms.center.y)
            && uniforms.size.isFinite
            && (0 ... 4).contains(uniforms.size)
            && uniforms.size > 0
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && source.device.registryID == deviceRegistryID
            && target.device.registryID == deviceRegistryID
    }
}
