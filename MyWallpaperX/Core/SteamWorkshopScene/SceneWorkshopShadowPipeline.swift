import Metal
import simd

private let sceneWorkshopShadowShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct WorkshopShadowVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct WorkshopShadowUniforms {
    float4 colorAndAlpha;
    float4 borderAndOffset;
};

vertex WorkshopShadowVaryings sceneWorkshopShadowVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    WorkshopShadowVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneWorkshopShadowFrag(
    WorkshopShadowVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant WorkshopShadowUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(
        filter::linear,
        address::clamp_to_edge
    );
    float4 albedo = source.sample(linearClamp, input.texcoord);
    float2 reflectedCoord = input.texcoord + uniforms.borderAndOffset.yz;
    float4 reflected = source.sample(linearClamp, reflectedCoord);
    float border = uniforms.borderAndOffset.x;
    float reflectionAlpha = uniforms.colorAndAlpha.a;

    if (albedo.a > border || reflected.a <= 0.0) {
        return albedo;
    }

    float3 straightAlbedo = albedo.a > 0.00001
        ? clamp(albedo.rgb / albedo.a, 0.0, 1.0)
        : float3(0.0);
    float3 straightResult = mix(
        straightAlbedo,
        uniforms.colorAndAlpha.rgb,
        reflectionAlpha
    );
    float resultAlpha = min(1.0, albedo.a + reflected.a * reflectionAlpha);
    return float4(straightResult * resultAlpha, resultAlpha);
}
"""

private struct SceneWorkshopShadowUniforms {
    let colorAndAlpha: SIMD4<Float>
    let borderAndOffset: SIMD4<Float>
}

struct SceneWorkshopShadowPipeline {
    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                source: sceneWorkshopShadowShaderSource,
                options: options
              ), let vertex = library.makeFunction(name: "sceneWorkshopShadowVert"),
              let fragment = library.makeFunction(name: "sceneWorkshopShadowFrag") else {
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
        plan: SceneWorkshopShadowExecutionPlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(source: source, target: target, commandBuffer: commandBuffer),
              valid(plan: plan) else {
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
        var uniforms = SceneWorkshopShadowUniforms(
            colorAndAlpha: SIMD4(plan.color, plan.alpha),
            borderAndOffset: SIMD4(
                plan.drawBorder,
                plan.offset.x / 100,
                plan.offset.y / 100,
                0
            )
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneWorkshopShadowUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
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
            && source.width > 0
            && source.width == target.width
            && source.height == target.height
            && source.mipmapLevelCount == 1
            && target.mipmapLevelCount == 1
            && source.sampleCount == 1
            && target.sampleCount == 1
            && source.usage.contains(.shaderRead)
            && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && source.device.registryID == deviceRegistryID
            && target.device.registryID == deviceRegistryID
    }

    private func valid(plan: SceneWorkshopShadowExecutionPlan) -> Bool {
        plan.alpha.isFinite
            && (0...1).contains(plan.alpha)
            && plan.drawBorder.isFinite
            && (0...1).contains(plan.drawBorder)
            && plan.offset.x.isFinite
            && plan.offset.y.isFinite
            && plan.color.x.isFinite
            && plan.color.y.isFinite
            && plan.color.z.isFinite
            && (0...1).contains(plan.color.x)
            && (0...1).contains(plan.color.y)
            && (0...1).contains(plan.color.z)
    }
}
