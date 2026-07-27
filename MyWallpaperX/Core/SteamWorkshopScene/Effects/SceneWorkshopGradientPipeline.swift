import Metal

private let sceneWorkshopGradientShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct WorkshopGradientVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex WorkshopGradientVaryings sceneWorkshopGradientVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    WorkshopGradientVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneWorkshopGradientFrag(
    WorkshopGradientVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr float3 colors[6] = {
        float3(1.0, 0.0, 0.0),
        float3(1.0, 0.6470588235294118, 0.0),
        float3(0.0, 0.0, 1.0),
        float3(0.0, 1.0, 1.0),
        float3(1.0, 0.0, 1.0),
        float3(1.0, 1.0, 0.0)
    };
    constexpr float gamma = 2.2;

    float2 size = float2(source.get_width(), source.get_height());
    float ratio = size.x / size.y;
    float2 coordinate = input.texcoord / (0.5 * float2(1.0, ratio));
    coordinate *= float2(1.0, ratio);
    if (size.x < size.y) {
        coordinate.x *= ratio;
    } else if (size.x > size.y) {
        coordinate.y /= ratio;
    }
    float colorIndex = fmod(length(coordinate) * 5.0, 6.0);
    if (colorIndex < 0.0) colorIndex += 6.0;

    float3 weighted = float3(0.0);
    float totalWeight = 0.0;
    for (int index = 0; index < 6; ++index) {
        float distance = abs(colorIndex - float(index));
        distance = min(distance, 6.0 - distance);
        float weight = 1.0 - smoothstep(0.0, 1.0, distance);
        weighted += pow(colors[index], float3(gamma)) * weight;
        totalWeight += weight;
    }
    float3 gradient = pow(weighted / max(totalWeight, 1e-6), float3(1.0 / gamma));
    float4 scene = source.sample(linearClamp, input.texcoord);
    return float4(gradient, scene.a);
}
"""

struct SceneWorkshopGradientPipeline {
    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneWorkshopGradientShaderSource,
                  options: nil
              ),
              let vertex = library.makeFunction(name: "sceneWorkshopGradientVert"),
              let fragment = library.makeFunction(name: "sceneWorkshopGradientFrag") else {
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
        deviceRegistryID = device.registryID
    }

    func encode(
        source: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(source: source, target: target, commandBuffer: commandBuffer) else {
            return false
        }
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
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(
        source: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        source.textureType == .type2D && target.textureType == .type2D
            && source.pixelFormat == .bgra8Unorm && target.pixelFormat == .bgra8Unorm
            && source.width > 0 && source.width == target.width
            && source.height > 0 && source.height == target.height
            && source.mipmapLevelCount == 1 && target.mipmapLevelCount == 1
            && source.sampleCount == 1 && target.sampleCount == 1
            && source.usage.contains(.shaderRead) && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && source.device.registryID == deviceRegistryID
            && target.device.registryID == deviceRegistryID
    }
}
