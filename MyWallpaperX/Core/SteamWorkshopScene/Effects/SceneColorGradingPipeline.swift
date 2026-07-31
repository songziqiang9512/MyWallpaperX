import Metal
import simd

private let sceneColorGradingShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct ColorGradingVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct ColorGradingUniforms {
    float4 adjustments; // luminance, saturation, vibrance, opacity
    float4 channelInfluence;
};

vertex ColorGradingVaryings sceneColorGradingVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    ColorGradingVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

static inline float sceneLuma(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

static inline float3 sceneAdjustLuminance(
    float3 color,
    float luma,
    float adjustment
) {
    if (adjustment == 0.0) { return color; }
    if (luma > 1e-6) {
        return color * (max(luma + adjustment, 0.0) / luma);
    }
    return adjustment > 0.0 ? float3(adjustment) : float3(0.0);
}

fragment float4 sceneColorGradingFrag(
    ColorGradingVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant ColorGradingUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float4 albedo = source.sample(linearClamp, input.texcoord);
    float sourceAlpha = albedo.a;
    if (sourceAlpha <= 1e-6) { return float4(0.0); }

    float3 base = clamp(albedo.rgb / sourceAlpha, 0.0, 1.0);
    float luma = sceneLuma(base);
    float3 graded = sceneAdjustLuminance(base, luma, u.adjustments.x);
    graded = mix(float3(luma), graded, 1.0 + u.adjustments.y);

    float chroma = max(graded.r, max(graded.g, graded.b))
        - min(graded.r, min(graded.g, graded.b));
    float vibrance = u.adjustments.z;
    float vibranceWeight = 1.0 + vibrance * (1.0 - sign(vibrance) * chroma);
    graded = mix(float3(luma), graded, vibranceWeight);

    float3 channelWeight = u.channelInfluence.xyz * u.adjustments.w;
    float3 result = mix(base, graded, channelWeight);
    return float4(clamp(result, 0.0, 1.0) * sourceAlpha, sourceAlpha);
}
"""

struct SceneColorGradingPipeline {
    private struct Uniforms {
        var adjustments: SIMD4<Float>
        var channelInfluence: SIMD4<Float>
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneColorGradingShaderSource,
                  options: nil
              ),
              let vertex = library.makeFunction(name: "sceneColorGradingVert"),
              let fragment = library.makeFunction(name: "sceneColorGradingFrag") else {
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
        plan: SceneColorGradingExecutionPlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(plan),
              valid(source: source, target: target, commandBuffer: commandBuffer) else {
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
            adjustments: SIMD4(
                plan.luminance,
                plan.saturation,
                plan.vibrance,
                plan.opacity
            ),
            channelInfluence: SIMD4(plan.channelInfluence, 0)
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(_ plan: SceneColorGradingExecutionPlan) -> Bool {
        [plan.luminance, plan.saturation, plan.vibrance].allSatisfy {
            $0.isFinite && (-1 ... 1).contains($0)
        }
            && plan.opacity.isFinite && (0 ... 1).contains(plan.opacity)
            && [
                plan.channelInfluence.x,
                plan.channelInfluence.y,
                plan.channelInfluence.z,
            ].allSatisfy(\.isFinite)
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
