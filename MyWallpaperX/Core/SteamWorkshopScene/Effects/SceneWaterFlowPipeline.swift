import Metal
import simd

private struct SceneWaterFlowUniforms {
    var flow: SIMD4<Float>
    var maskUVScale: SIMD2<Float>
    var padding: SIMD2<Float> = .zero
}

private let sceneWaterFlowShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct WaterFlowVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct WaterFlowUniforms {
    float4 flow;
    float2 maskUVScale;
    float2 padding;
};

vertex WaterFlowVaryings sceneWaterFlowVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    WaterFlowVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneWaterFlowFrag(
    WaterFlowVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> flowTexture [[texture(1)]],
    texture2d<float> phaseTexture [[texture(2)]],
    constant WaterFlowUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr sampler linearRepeat(filter::linear, address::repeat);
    float time = uniforms.flow.x;
    float speed = uniforms.flow.y;
    float strength = uniforms.flow.z;
    float phaseScale = uniforms.flow.w;

    float phase = phaseTexture.sample(linearRepeat, input.texcoord * phaseScale).r;
    float2 flowColors = flowTexture.sample(
        linearClamp,
        clamp(input.texcoord * uniforms.maskUVScale, 0.0, 1.0)
    ).rg;
    float2 flowMask = (flowColors - float2(0.498)) * 2.0;
    float flowAmount = length(flowMask);

    float4 cycles = fract(float4(
        time * speed,
        time * speed + 0.5,
        0.25 + time * speed,
        0.25 + time * speed + 0.5
    ));
    float blend = 2.0 * abs(cycles.x - 0.5);
    float blend2 = 2.0 * abs(cycles.z - 0.5);
    cycles -= 0.5;

    float4 offset = float4(flowMask.xyxy * strength * 0.1) * cycles.xxyy;
    float4 offset2 = float4(flowMask.xyxy * strength * 0.1) * cycles.zzww;
    float4 albedo = source.sample(linearClamp, input.texcoord);
    float4 flowed = mix(
        source.sample(linearClamp, input.texcoord + offset.xy),
        source.sample(linearClamp, input.texcoord + offset.zw),
        blend
    );
    float4 flowed2 = mix(
        source.sample(linearClamp, input.texcoord + offset2.xy),
        source.sample(linearClamp, input.texcoord + offset2.zw),
        blend2
    );
    flowed = mix(flowed, flowed2, smoothstep(0.2, 0.8, phase));
    return mix(albedo, flowed, flowAmount);
}
"""

struct SceneWaterFlowPipeline {
    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneWaterFlowShaderSource,
                  options: options
              ),
              let vertex = library.makeFunction(name: "sceneWaterFlowVert"),
              let fragment = library.makeFunction(name: "sceneWaterFlowFrag") else {
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
        flowTexture: MTLTexture,
        phaseTexture: MTLTexture,
        target: MTLTexture,
        plan: SceneWaterFlowExecutionPlan,
        time: Float,
        maskUVScale: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(
            source: source,
            flowTexture: flowTexture,
            phaseTexture: phaseTexture,
            target: target,
            plan: plan,
            time: time,
            maskUVScale: maskUVScale,
            commandBuffer: commandBuffer
        ) else {
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
        encoder.setFragmentTexture(flowTexture, index: 1)
        encoder.setFragmentTexture(phaseTexture, index: 2)
        var uniforms = SceneWaterFlowUniforms(
            flow: SIMD4(time, plan.speed, plan.strength, plan.phaseScale),
            maskUVScale: maskUVScale
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneWaterFlowUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(
        source: MTLTexture,
        flowTexture: MTLTexture,
        phaseTexture: MTLTexture,
        target: MTLTexture,
        plan: SceneWaterFlowExecutionPlan,
        time: Float,
        maskUVScale: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let auxiliaryFormats: Set<MTLPixelFormat> = [
            .r8Unorm, .rg8Unorm, .rgba8Unorm, .bgra8Unorm,
        ]
        return time.isFinite
            && (0.01...2).contains(plan.speed)
            && (0.01...2).contains(plan.strength)
            && (0.01...10).contains(plan.phaseScale)
            && maskUVScale.x.isFinite
            && maskUVScale.y.isFinite
            && maskUVScale.x > 0
            && maskUVScale.y > 0
            && maskUVScale.x <= 1
            && maskUVScale.y <= 1
            && source.textureType == .type2D
            && flowTexture.textureType == .type2D
            && phaseTexture.textureType == .type2D
            && target.textureType == .type2D
            && source.pixelFormat == .bgra8Unorm
            && auxiliaryFormats.contains(flowTexture.pixelFormat)
            && auxiliaryFormats.contains(phaseTexture.pixelFormat)
            && target.pixelFormat == .bgra8Unorm
            && source.width > 0
            && source.width == target.width
            && source.height > 0
            && source.height == target.height
            && flowTexture.width > 0
            && flowTexture.height > 0
            && phaseTexture.width > 0
            && phaseTexture.height > 0
            && source.mipmapLevelCount == 1
            && flowTexture.mipmapLevelCount == 1
            && phaseTexture.mipmapLevelCount == 1
            && target.mipmapLevelCount == 1
            && source.sampleCount == 1
            && flowTexture.sampleCount == 1
            && phaseTexture.sampleCount == 1
            && target.sampleCount == 1
            && source.usage.contains(.shaderRead)
            && flowTexture.usage.contains(.shaderRead)
            && phaseTexture.usage.contains(.shaderRead)
            && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && source.device.registryID == deviceRegistryID
            && flowTexture.device.registryID == deviceRegistryID
            && phaseTexture.device.registryID == deviceRegistryID
            && target.device.registryID == deviceRegistryID
    }
}
