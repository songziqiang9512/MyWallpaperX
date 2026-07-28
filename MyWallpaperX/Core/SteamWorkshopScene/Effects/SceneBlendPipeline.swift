import Metal
import simd

private let sceneBlendShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct BlendVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct BlendUniforms {
    float multiply;
    float2 blendUVScale;
    float padding;
};

vertex BlendVaryings sceneAuthoredBlendVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    BlendVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneAuthoredBlendFrag(
    BlendVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> blend [[texture(1)]],
    constant BlendUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearClamp(
        min_filter::linear,
        mag_filter::linear,
        mip_filter::linear,
        address::clamp_to_edge
    );
    float4 albedo = source.sample(linearClamp, input.texcoord);
    float4 overlay = blend.sample(
        linearClamp,
        clamp(input.texcoord * uniforms.blendUVScale, 0.0, 1.0)
    );
    // Host textures are premultiplied; run authored Blend math in straight RGB.
    float3 sourceStraight = albedo.a > 0.00001 ? albedo.rgb / albedo.a : float3(0.0);
    float3 overlayStraight = overlay.a > 0.00001 ? overlay.rgb / overlay.a : float3(0.0);
    float3 blendedStraight = mix(
        sourceStraight,
        overlayStraight,
        uniforms.multiply * overlay.a
    );
    albedo.rgb = clamp(blendedStraight, 0.0, 1.0) * albedo.a;
    return albedo;
}
"""

struct SceneBlendPipeline {
    private struct Uniforms {
        var multiply: Float
        var blendUVScale: SIMD2<Float>
        var padding: Float = 0
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(source: sceneBlendShaderSource, options: options),
              let vertex = library.makeFunction(name: "sceneAuthoredBlendVert"),
              let fragment = library.makeFunction(name: "sceneAuthoredBlendFrag") else {
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
        blend: MTLTexture,
        target: MTLTexture,
        multiply: Float,
        blendUVScale: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(
            source: source,
            blend: blend,
            target: target,
            multiply: multiply,
            blendUVScale: blendUVScale,
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
        encoder.setFragmentTexture(blend, index: 1)
        var uniforms = Uniforms(multiply: multiply, blendUVScale: blendUVScale)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(
        source: MTLTexture,
        blend: MTLTexture,
        target: MTLTexture,
        multiply: Float,
        blendUVScale: SIMD2<Float>,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let readableFormats: Set<MTLPixelFormat> = [.rgba8Unorm, .bgra8Unorm]
        let textures = [source, blend, target]
        return multiply.isFinite
            && (0...2).contains(multiply)
            && blendUVScale.x.isFinite
            && blendUVScale.y.isFinite
            && blendUVScale.min() > 0
            && blendUVScale.max() <= 1
            && textures.allSatisfy { texture in
                texture.textureType == .type2D
                    && texture.width > 0
                    && texture.height > 0
                    && texture.mipmapLevelCount > 0
                    && texture.sampleCount == 1
                    && texture.device.registryID == deviceRegistryID
            }
            && readableFormats.contains(source.pixelFormat)
            && readableFormats.contains(blend.pixelFormat)
            && target.pixelFormat == .bgra8Unorm
            && source.usage.contains(.shaderRead)
            && blend.usage.contains(.shaderRead)
            && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(blend)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && ObjectIdentifier(blend) != ObjectIdentifier(target)
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
    }
}
