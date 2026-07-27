import Metal
import simd

private let sceneSpinShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct SceneSpinVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct SceneSpinUniforms {
    float2 center;
    float size;
    float feather;
    float speed;
    float ratio;
    float angle;
    float phase;
    float time;
};

float2 sceneSpinRotate(float2 value, float angle) {
    float sine = sin(angle);
    float cosine = cos(angle);
    return float2(
        cosine * value.x - sine * value.y,
        sine * value.x + cosine * value.y
    );
}

vertex SceneSpinVaryings sceneSpinVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    SceneSpinVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneSpinFrag(
    SceneSpinVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant SceneSpinUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float aspect = float(source.get_width()) / float(source.get_height());
    float2 local = input.texcoord - uniforms.center;
    local.x *= aspect;

    float2 elliptical = sceneSpinRotate(local, uniforms.angle);
    elliptical.x *= uniforms.ratio;
    float2 maskLocal = sceneSpinRotate(elliptical, -uniforms.angle);

    float rotation = uniforms.speed * uniforms.time
        + uniforms.phase * 6.28318530718;
    float2 warped = sceneSpinRotate(elliptical, rotation);
    warped.x /= uniforms.ratio;
    warped = sceneSpinRotate(warped, -uniforms.angle);
    warped.x /= aspect;
    warped += uniforms.center;

    float2 repeated = fract(warped);
    float4 original = source.sample(linearClamp, input.texcoord);
    float4 spun = source.sample(linearClamp, repeated);
    float mask = smoothstep(
        uniforms.size + uniforms.feather + 0.00001,
        uniforms.size - uniforms.feather,
        length(maskLocal)
    );
    return mix(original, spun, mask);
}
"""

struct SceneSpinPipeline {
    struct Uniforms {
        var center: SIMD2<Float>
        var size: Float
        var feather: Float
        var speed: Float
        var ratio: Float
        var angle: Float
        var phase: Float
        var time: Float
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(source: sceneSpinShaderSource, options: nil),
              let vertex = library.makeFunction(name: "sceneSpinVert"),
              let fragment = library.makeFunction(name: "sceneSpinFrag") else {
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
        uniforms: Uniforms,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(source: source, target: target, uniforms: uniforms, commandBuffer: commandBuffer)
        else { return false }

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        var uniforms = uniforms
        encoder.setRenderPipelineState(state)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
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
        source.textureType == .type2D && target.textureType == .type2D
            && source.pixelFormat == .bgra8Unorm && target.pixelFormat == .bgra8Unorm
            && source.width > 0 && source.width == target.width
            && source.height > 0 && source.height == target.height
            && source.mipmapLevelCount == 1 && target.mipmapLevelCount == 1
            && source.sampleCount == 1 && target.sampleCount == 1
            && source.usage.contains(.shaderRead) && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && uniforms.center.x.isFinite && uniforms.center.y.isFinite
            && uniforms.size.isFinite && uniforms.feather.isFinite
            && uniforms.speed.isFinite && uniforms.ratio.isFinite && uniforms.ratio > 0
            && uniforms.angle.isFinite && uniforms.phase.isFinite && uniforms.time.isFinite
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && source.device.registryID == deviceRegistryID
            && target.device.registryID == deviceRegistryID
    }
}
