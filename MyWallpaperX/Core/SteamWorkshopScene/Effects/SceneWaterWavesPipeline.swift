import Metal
import simd

private struct SceneWaterWavesUniforms {
    var wave0: SIMD4<Float>
    var wave1: SIMD4<Float>
}

private let sceneWaterWavesShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct WaterWavesVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct WaterWavesUniforms {
    float4 wave0;
    float4 wave1;
};

vertex WaterWavesVaryings sceneWaterWavesVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    WaterWavesVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneWaterWavesFrag(
    WaterWavesVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    constant WaterWavesUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float time = uniforms.wave0.x;
    float directionAngle = uniforms.wave0.y;
    float speed = uniforms.wave0.z;
    float scale = uniforms.wave0.w;
    float exponent = uniforms.wave1.x;
    float strength = uniforms.wave1.y;
    float2 maskUVScale = uniforms.wave1.zw;

    float2 direction = float2(-sin(directionAngle), cos(directionAngle));
    float distance = time * speed + dot(input.texcoord, direction) * scale;
    float value = sin(distance);
    value = sign(value) * pow(abs(value), exponent);

    // maskUVScale == 0 是「无遮罩」哨兵（v1 无绑图实例，等价 mask=1）；
    // 合法遮罩的 UV scale 恒 > 0（pipeline 入口校验）。
    float mask = 1.0;
    if (maskUVScale.x > 0.0) {
        mask = maskTexture.sample(
            linearClamp,
            clamp(input.texcoord * maskUVScale, 0.0, 1.0)
        ).r;
    }
    float2 offset = float2(direction.y, -direction.x);
    float2 sampleUV = input.texcoord + value * offset * strength * strength * mask;
    return source.sample(linearClamp, sampleUV);
}
"""

struct SceneWaterWavesPipeline {
    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneWaterWavesShaderSource,
                  options: options
              ),
              let vertex = library.makeFunction(name: "sceneWaterWavesVert"),
              let fragment = library.makeFunction(name: "sceneWaterWavesFrag") else {
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
        mask: MTLTexture?,
        target: MTLTexture,
        plan: SceneWaterWavesExecutionPlan,
        time: Float,
        maskUVScale: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(
            source: source,
            mask: mask,
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
        encoder.setFragmentTexture(mask ?? source, index: 1)
        // mask 为 nil 时以 maskUVScale = 0 作 shader 侧「无遮罩」哨兵（等价 mask=1）。
        let effectiveMaskUVScale = mask == nil ? SIMD2<Float>(repeating: 0) : maskUVScale
        var uniforms = SceneWaterWavesUniforms(
            wave0: SIMD4(time, plan.direction, plan.speed, plan.scale),
            wave1: SIMD4(
                plan.exponent, plan.strength,
                effectiveMaskUVScale.x, effectiveMaskUVScale.y
            )
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneWaterWavesUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(
        source: MTLTexture,
        mask: MTLTexture?,
        target: MTLTexture,
        plan: SceneWaterWavesExecutionPlan,
        time: Float,
        maskUVScale: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard time.isFinite
            && plan.direction.isFinite
            && (0.01...50).contains(plan.speed)
            && (0.01...1000).contains(plan.scale)
            && (0.51...4).contains(plan.exponent)
            && (0.01...1).contains(plan.strength)
            && source.textureType == .type2D
            && target.textureType == .type2D
            && source.pixelFormat == .bgra8Unorm
            && target.pixelFormat == .bgra8Unorm
            && source.width > 0
            && source.width == target.width
            && source.height > 0
            && source.height == target.height
            && source.mipmapLevelCount > 0
            && target.mipmapLevelCount == 1
            && source.sampleCount == 1
            && target.sampleCount == 1
            && source.usage.contains(.shaderRead)
            && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && source.device.registryID == deviceRegistryID
            && target.device.registryID == deviceRegistryID else {
            return false
        }
        guard let mask else { return true }
        let supportedMaskFormats: Set<MTLPixelFormat> = [
            .r8Unorm, .rgba8Unorm, .bgra8Unorm,
        ]
        return maskUVScale.x.isFinite
            && maskUVScale.y.isFinite
            && (0...1).contains(maskUVScale.x)
            && (0...1).contains(maskUVScale.y)
            && maskUVScale.x > 0
            && maskUVScale.y > 0
            && mask.textureType == .type2D
            && supportedMaskFormats.contains(mask.pixelFormat)
            && mask.width > 0
            && mask.height > 0
            && mask.mipmapLevelCount > 0
            && mask.sampleCount == 1
            && mask.usage.contains(.shaderRead)
            && mask.device.registryID == deviceRegistryID
    }
}
