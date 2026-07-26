import Metal
import simd

private let sceneShakeShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct ShakeVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct ShakeUniforms {
    float4 boundsAndFriction;
    float4 motion;
    float4 flowUVScale;
};

vertex ShakeVaryings sceneShakeVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    ShakeVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneShakeFrag(
    ShakeVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> flowMap [[texture(1)]],
    texture2d<float> phaseMap [[texture(2)]],
    constant ShakeUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr float twoPi = 6.28318530717958647692;
    float2 flowUV = input.texcoord * uniforms.flowUVScale.xy;
    float flowPhase = phaseMap.sample(linearClamp, flowUV).r * twoPi;
    float2 flowMask = (flowMap.sample(linearClamp, flowUV).rg - float2(0.498)) * 2.0;

    float time = uniforms.motion.x * uniforms.motion.z + flowPhase;
    float offset = sin(fract(time / twoPi) * twoPi);
    offset = offset * 0.498 + 0.5;
    float branch = step(0.0, cos(time));
    float lower = 1.0 - pow(1.0 - offset, uniforms.boundsAndFriction.z);
    float upper = pow(offset, uniforms.boundsAndFriction.w);
    offset = mix(lower, upper, branch);
    offset = saturate(
        (offset - uniforms.boundsAndFriction.x)
            / (uniforms.boundsAndFriction.y - uniforms.boundsAndFriction.x)
    );
    offset = offset * 2.0 - 1.0;

    float2 displacedUV = input.texcoord
        + offset * uniforms.motion.y * uniforms.motion.y * flowMask;
    return source.sample(linearClamp, displacedUV);
}
"""

private struct SceneShakeUniforms {
    let boundsAndFriction: SIMD4<Float>
    let motion: SIMD4<Float>
    let flowUVScale: SIMD4<Float>
}

struct SceneShakePipeline {
    private let state: MTLRenderPipelineState
    private let whitePhaseTexture: MTLTexture
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                source: sceneShakeShaderSource,
                options: options
              ),
              let vertex = library.makeFunction(name: "sceneShakeVert"),
              let fragment = library.makeFunction(name: "sceneShakeFrag"),
              let whitePhaseTexture = Self.makeWhitePhaseTexture(device: device) else {
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
        self.whitePhaseTexture = whitePhaseTexture
        deviceRegistryID = device.registryID
    }

    func encode(
        source: MTLTexture,
        flowMap: MTLTexture,
        phaseMap: MTLTexture?,
        flowUVScale: SIMD2<Float>,
        target: MTLTexture,
        plan: SceneShakeExecutionPlan,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let phase = phaseMap ?? whitePhaseTexture
        guard valid(
            source: source,
            flowMap: flowMap,
            phaseMap: phase,
            target: target,
            flowUVScale: flowUVScale,
            plan: plan,
            time: time,
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
        encoder.setFragmentTexture(flowMap, index: 1)
        encoder.setFragmentTexture(phase, index: 2)
        var uniforms = SceneShakeUniforms(
            boundsAndFriction: SIMD4(
                plan.bounds.x,
                plan.bounds.y,
                plan.friction.x,
                plan.friction.y
            ),
            motion: SIMD4(plan.speed, plan.strength, time, 0),
            flowUVScale: SIMD4(flowUVScale.x, flowUVScale.y, 0, 0)
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneShakeUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(
        source: MTLTexture,
        flowMap: MTLTexture,
        phaseMap: MTLTexture,
        target: MTLTexture,
        flowUVScale: SIMD2<Float>,
        plan: SceneShakeExecutionPlan,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        // flow 只消费 `.rg` 通道：stock 语料是 RG88 容器，legacy 老编辑器包
        // （`2131872317` 系）把同语义 flow 存成 ARGB8888，通道语义一致。
        validTexture(source, format: .bgra8Unorm, usage: .shaderRead)
            && validTexture(
                flowMap,
                formats: [.rg8Unorm, .bgra8Unorm, .rgba8Unorm],
                usage: .shaderRead
            )
            && validTexture(phaseMap, format: .r8Unorm, usage: .shaderRead)
            && validTexture(target, format: .bgra8Unorm, usage: .renderTarget)
            && source.width == target.width
            && source.height == target.height
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && flowUVScale.x.isFinite
            && flowUVScale.y.isFinite
            && (0...1).contains(flowUVScale.x)
            && (0...1).contains(flowUVScale.y)
            && flowUVScale.x > 0
            && flowUVScale.y > 0
            && plan.bounds.x.isFinite
            && plan.bounds.y.isFinite
            && plan.bounds.y > plan.bounds.x
            && plan.friction.x.isFinite
            && plan.friction.y.isFinite
            && (0.01...10).contains(plan.friction.x)
            && (0.01...10).contains(plan.friction.y)
            && plan.speed.isFinite
            && (0...10).contains(plan.speed)
            && plan.strength.isFinite
            && (0.01...0.5).contains(plan.strength)
            && time.isFinite
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && [source, flowMap, phaseMap, target].allSatisfy {
                $0.device.registryID == deviceRegistryID
            }
    }

    private func validTexture(
        _ texture: MTLTexture,
        format: MTLPixelFormat,
        usage: MTLTextureUsage
    ) -> Bool {
        validTexture(texture, formats: [format], usage: usage)
    }

    private func validTexture(
        _ texture: MTLTexture,
        formats: Set<MTLPixelFormat>,
        usage: MTLTextureUsage
    ) -> Bool {
        texture.textureType == .type2D
            && formats.contains(texture.pixelFormat)
            && texture.width > 0
            && texture.height > 0
            && texture.mipmapLevelCount == 1
            && texture.sampleCount == 1
            && texture.usage.contains(usage)
    }

    private static func makeWhitePhaseTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var white = UInt8.max
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &white,
            bytesPerRow: 1
        )
        return texture
    }
}
