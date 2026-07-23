import Metal
import simd

private let sceneGradientColorShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct GradientVaryings {
    float4 position [[position]];
    float2 uv;
};

struct GradientUniforms {
    float4 color1;
    float4 color2;
    float4 parameters;
    uint4 options;
};

vertex GradientVaryings sceneGradientColorVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    GradientVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.uv = texcoords[vertexID];
    return output;
}

float3 gradientRGBToHSV(float3 color) {
    float4 k = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(color.bg, k.wz), float4(color.gb, k.xy), step(color.b, color.g));
    float4 q = mix(float4(p.xyw, color.r), float4(color.r, p.yzx), step(p.x, color.r));
    float delta = q.x - min(q.w, q.y);
    return float3(
        abs(q.z + (q.w - q.y) / (6.0 * delta + 1e-10)),
        delta / (q.x + 1e-10),
        q.x
    );
}

float3 gradientHSVToRGB(float3 color) {
    float3 rgb = clamp(abs(fract(color.xxx + float3(0.0, 2.0 / 3.0, 1.0 / 3.0))
        * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return color.z * mix(float3(1.0), rgb, color.y);
}

fragment float4 sceneGradientColorFrag(
    GradientVaryings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant GradientUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler sampler2d(filter::linear, address::clamp_to_edge);
    float4 source = sourceTexture.sample(sampler2d, input.uv);
    float coordinate = uniforms.options.x == 1u ? input.uv.y : input.uv.x;
    float distance = pow(coordinate, uniforms.parameters.x)
        + sin(uniforms.parameters.w * uniforms.parameters.z);
    float3 gradient = mix(uniforms.color1.rgb, uniforms.color2.rgb, distance);
    float3 hsv = gradientRGBToHSV(gradient);
    hsv.x = fract(hsv.x + uniforms.parameters.w * uniforms.parameters.y);
    gradient = gradientHSVToRGB(hsv);

    float alpha = source.a;
    float3 sourceStraight = alpha > 0.00001 ? source.rgb / alpha : gradient;
    float3 edgeSafeSource = mix(gradient, sourceStraight, alpha);
    float3 result = mix(edgeSafeSource, gradient, uniforms.color1.a);
    return float4(result * alpha, alpha);
}
"""

private struct SceneGradientColorUniforms {
    let color1: SIMD4<Float>
    let color2: SIMD4<Float>
    let parameters: SIMD4<Float>
    let options: SIMD4<UInt32>
}

struct SceneGradientColorPipeline {
    private let state: MTLRenderPipelineState

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard let library = try? device.makeLibrary(
            source: sceneGradientColorShaderSource,
            options: options
        ), let vertex = library.makeFunction(name: "sceneGradientColorVert"),
        let fragment = library.makeFunction(name: "sceneGradientColorFrag") else {
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
        target: MTLTexture,
        plan: SceneGradientColorPlan,
        time: Float,
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
        var uniforms = SceneGradientColorUniforms(
            color1: SIMD4(plan.color1, plan.opacity),
            color2: SIMD4(plan.color2, 0),
            parameters: SIMD4(plan.amount, plan.hueSpeed, plan.oscillate, time),
            options: SIMD4(UInt32(plan.axis), 0, 0, 0)
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneGradientColorUniforms>.size,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }
}
