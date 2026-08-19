import Metal

private let sceneOpacityShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct OpacityVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex OpacityVaryings sceneOpacityVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    OpacityVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

struct OpacityUniforms {
    float alpha;
    float maskScaleX;
    float maskScaleY;
    uint hasMask;
};

fragment float4 sceneOpacityFrag(
    OpacityVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> mask [[texture(1)]],
    constant OpacityUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    // 官方 opacity.frag: `albedo.a *= mask * g_UserAlpha`。这里的 source 是 premultiplied，
    // 等价形式是四个通道一起乘。遮罩 UV 沿用官方 opacity.vert 的
    // `g_Texture1Resolution.zw / .xy` 修正，由 maskScale 传入。
    float opacity = uniforms.alpha;
    if (uniforms.hasMask != 0u) {
        float2 maskUV = input.texcoord * float2(uniforms.maskScaleX, uniforms.maskScaleY);
        opacity *= mask.sample(linearClamp, maskUV).r;
    }
    return source.sample(linearClamp, input.texcoord) * opacity;
}
"""

struct SceneOpacityPipeline {
    private struct Uniforms {
        var alpha: Float
        var maskScaleX: Float
        var maskScaleY: Float
        var hasMask: UInt32
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                source: sceneOpacityShaderSource,
                options: options
              ), let vertex = library.makeFunction(name: "sceneOpacityVert"),
              let fragment = library.makeFunction(name: "sceneOpacityFrag") else {
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
        alpha: Float,
        mask: MTLTexture?,
        maskUVScale: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard alpha.isFinite,
              (0...1).contains(alpha),
              valid(source: source, target: target, commandBuffer: commandBuffer),
              validMask(mask, commandBuffer: commandBuffer),
              maskUVScale.x.isFinite,
              maskUVScale.y.isFinite,
              maskUVScale.min() > 0,
              maskUVScale.max() <= 1 else {
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
        var uniforms = Uniforms(
            alpha: alpha,
            maskScaleX: maskUVScale.x,
            maskScaleY: maskUVScale.y,
            hasMask: mask == nil ? 0 : 1
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

    private func validMask(_ mask: MTLTexture?, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let mask else { return true }
        return mask.textureType == .type2D
            && mask.width > 0
            && mask.height > 0
            && mask.sampleCount == 1
            && mask.usage.contains(.shaderRead)
            && mask.device.registryID == deviceRegistryID
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
            && source.height > 0
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
}
