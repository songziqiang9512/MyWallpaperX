import Metal

private let sceneColorKeyShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct ColorKeyVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex ColorKeyVaryings sceneColorKeyVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    ColorKeyVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

struct ColorKeyUniforms {
    float4 keyColorAndAlpha;
    float fuzziness;
    float tolerance;
    uint invert;
    uint flatten;
};

fragment float4 sceneColorKeyFrag(
    ColorKeyVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant ColorKeyUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float4 albedo = source.sample(linearClamp, input.texcoord);
    float delta = dot(
        abs(uniforms.keyColorAndAlpha.rgb - albedo.rgb),
        float3(1.0)
    );
    float blend = smoothstep(
        0.001,
        0.002 + uniforms.fuzziness,
        delta - uniforms.tolerance
    );
    if (uniforms.invert != 0u) {
        blend = 1.0 - blend;
    }
    albedo.a *= mix(uniforms.keyColorAndAlpha.a, 1.0, blend);
    if (uniforms.flatten != 0u) {
        albedo.rgb *= albedo.a;
    }
    return albedo;
}
"""

struct SceneColorKeyPipeline {
    private struct Uniforms {
        var keyColorAndAlpha: SIMD4<Float>
        var fuzziness: Float
        var tolerance: Float
        var invert: UInt32
        var flatten: UInt32
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneColorKeyShaderSource,
                  options: nil
              ),
              let vertex = library.makeFunction(name: "sceneColorKeyVert"),
              let fragment = library.makeFunction(name: "sceneColorKeyFrag") else {
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
        plan: SceneColorKeyExecutionPlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(plan), valid(source: source, target: target, commandBuffer: commandBuffer)
        else {
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
        var uniforms = Uniforms(
            keyColorAndAlpha: SIMD4(plan.keyColor, plan.keyAlpha),
            fuzziness: plan.fuzziness,
            tolerance: plan.tolerance,
            invert: plan.invert ? 1 : 0,
            flatten: plan.flatten ? 1 : 0
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(_ plan: SceneColorKeyExecutionPlan) -> Bool {
        plan.keyAlpha.isFinite && (0...1).contains(plan.keyAlpha)
            && plan.fuzziness.isFinite && (0...3).contains(plan.fuzziness)
            && plan.tolerance.isFinite && (0...3).contains(plan.tolerance)
            && [plan.keyColor.x, plan.keyColor.y, plan.keyColor.z].allSatisfy {
                $0.isFinite && (0...1).contains($0)
            }
    }

    private func valid(
        source: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        source.textureType == .type2D
            && target.textureType == .type2D
            && source.pixelFormat == .bgra8Unorm
            && target.pixelFormat == .bgra8Unorm
            && source.width > 0 && source.width == target.width
            && source.height > 0 && source.height == target.height
            && source.mipmapLevelCount == 1 && target.mipmapLevelCount == 1
            && source.sampleCount == 1 && target.sampleCount == 1
            && source.usage.contains(.shaderRead)
            && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && source.device.registryID == deviceRegistryID
            && target.device.registryID == deviceRegistryID
    }
}
