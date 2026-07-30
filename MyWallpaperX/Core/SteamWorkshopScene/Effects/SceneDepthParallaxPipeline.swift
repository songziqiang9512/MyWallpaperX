import Metal
import simd

private struct SceneDepthParallaxUniforms {
    var pointerAndScale: SIMD4<Float>
    var parameters: SIMD4<Float>
    var depthUVScale: SIMD4<Float>
}

private let sceneDepthParallaxShader = """
#include <metal_stdlib>
using namespace metal;

struct Varyings {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float4 pointerAndScale;
    float4 parameters;
    float4 depthUVScale;
};

vertex Varyings sceneDepthParallaxVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    constexpr float2 uvs[] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    Varyings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.uv = uvs[vertexID];
    return output;
}

fragment float4 sceneDepthParallaxFragment(
    Varyings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> depthTexture [[texture(1)]],
    sampler depthSampler [[sampler(0)]],
    constant Uniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 baseUV = clamp(input.uv, 0.0, 1.0);
    float2 pointer = uniforms.pointerAndScale.xy;
    float2 scale = uniforms.pointerAndScale.zw;
    float sensitivity = uniforms.parameters.x;
    float center = uniforms.parameters.y;
    uint sampleCount = uint(uniforms.parameters.z);
    float2 mappedScale = uniforms.depthUVScale.xy;
    float2 parallax = (pointer - 0.5) * scale * sensitivity * 0.04;

    float2 outputUV;
    if (sampleCount <= 1u) {
        float depth = depthTexture.sample(
            depthSampler,
            clamp(baseUV * mappedScale, 0.0, mappedScale)
        ).r;
        outputUV = baseUV + parallax * (depth - center);
    } else {
        float bestError = 2.0;
        float2 bestUV = baseUV;
        for (uint index = 0u; index < 64u; ++index) {
            if (index >= sampleCount) {
                break;
            }
            float layerDepth = float(index) / float(sampleCount - 1u);
            float2 candidateUV = baseUV + parallax * (layerDepth - center);
            float sampledDepth = depthTexture.sample(
                depthSampler,
                clamp(candidateUV * mappedScale, 0.0, mappedScale)
            ).r;
            float error = abs(sampledDepth - layerDepth);
            if (error < bestError) {
                bestError = error;
                bestUV = candidateUV;
            }
        }
        outputUV = bestUV;
    }
    return source.sample(linearClamp, clamp(outputUV, 0.0, 1.0));
}
"""

struct SceneDepthParallaxPipeline {
    private let state: MTLRenderPipelineState
    private let samplerStates: SceneTextureSamplerStateSet

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let samplerStates = SceneTextureSamplerStateSet(device: device),
              let library = try? device.makeLibrary(
                  source: sceneDepthParallaxShader,
                  options: MTLCompileOptions()
              ),
              let vertex = library.makeFunction(
                  name: "sceneDepthParallaxVertex"
              ),
              let fragment = library.makeFunction(
                  name: "sceneDepthParallaxFragment"
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
        self.samplerStates = samplerStates
    }

    func encode(
        source: MTLTexture,
        depth: MTLTexture,
        target: MTLTexture,
        plan: SceneDepthParallaxExecutionPlan,
        cursorUV: SIMD2<Float>,
        depthUVScale: SIMD2<Float>,
        depthSampling: SceneTextureSampling,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard source !== target,
              source.textureType == .type2D,
              depth.textureType == .type2D,
              target.textureType == .type2D,
              source.pixelFormat == .bgra8Unorm,
              target.pixelFormat == .bgra8Unorm,
              depth.pixelFormat == .r8Unorm,
              source.width == target.width,
              source.height == target.height,
              source.usage.contains(.shaderRead),
              depth.usage.contains(.shaderRead),
              target.usage.contains(.renderTarget),
              cursorUV.x.isFinite,
              cursorUV.y.isFinite,
              plan.scale.x.isFinite,
              plan.scale.y.isFinite,
              plan.sensitivity.isFinite,
              plan.center.isFinite,
              depthUVScale.x.isFinite,
              depthUVScale.y.isFinite,
              depthUVScale.x > 0,
              depthUVScale.y > 0,
              depthUVScale.x <= 1,
              depthUVScale.y <= 1,
              !depthSampling.usesClampBorderFallback else {
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
        var uniforms = SceneDepthParallaxUniforms(
            pointerAndScale: SIMD4(
                cursorUV.x,
                cursorUV.y,
                plan.scale.x,
                plan.scale.y
            ),
            parameters: SIMD4(
                plan.sensitivity,
                plan.center,
                Float(plan.quality.sampleCount),
                0
            ),
            depthUVScale: SIMD4(depthUVScale.x, depthUVScale.y, 0, 0)
        )
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(depth, index: 1)
        encoder.setFragmentSamplerState(
            samplerStates.state(for: depthSampling),
            index: 0
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneDepthParallaxUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
        encoder.endEncoding()
        return true
    }
}
