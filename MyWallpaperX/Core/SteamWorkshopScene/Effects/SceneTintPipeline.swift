import Metal
import simd

private let sceneTintShaderSource = SceneBlendModeShaderSource.blendFunctions + """

struct TintVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct SceneTintUniforms {
    float4 colorAlpha;
    float4 maskScaleFlags; // xy = mask UV scale, z = hasMask, w = maskMultiplies
    int blendMode;
};

vertex TintVaryings sceneTintVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    TintVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneTintFrag(
    TintVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    constant SceneTintUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float4 albedo = source.sample(linearClamp, input.texcoord);
    // 官方语义：遮罩是 ApplyBlending 的混合权重，不动 alpha 通道。
    // stock 与 g_BlendAlpha 相乘；legacy 指纹覆盖 g_BlendAlpha。
    float mask = u.colorAlpha.w;
    if (u.maskScaleFlags.z > 0.5) {
        float sampled = maskTexture.sample(
            linearClamp,
            clamp(input.texcoord * u.maskScaleFlags.xy, 0.0, 1.0)
        ).r;
        mask = u.maskScaleFlags.w > 0.5 ? mask * sampled : sampled;
    }
    float sourceAlpha = albedo.a;
    float3 straightRGB = sourceAlpha > 1e-6
        ? clamp(albedo.rgb / sourceAlpha, 0.0, 1.0)
        : float3(0.0);
    float3 blended = clamp(
        sceneApplyBlending(u.blendMode, straightRGB, u.colorAlpha.xyz, mask),
        0.0,
        1.0
    );
    if (u.blendMode == 0) {
        return float4(blended, 1.0);
    }
    return float4(blended * sourceAlpha, sourceAlpha);
}
"""

struct SceneTintPipeline {
    private struct Uniforms {
        var colorAlpha: SIMD4<Float>
        var maskScaleFlags: SIMD4<Float>
        var blendMode: Int32
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        let options = MTLCompileOptions()
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneTintShaderSource,
                  options: options
              ), let vertex = library.makeFunction(name: "sceneTintVert"),
              let fragment = library.makeFunction(name: "sceneTintFrag")
        else {
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
        mask: MTLTexture? = nil,
        maskUVScale: SIMD2<Float> = SIMD2(repeating: 1),
        maskMultipliesBlendAlpha: Bool = true,
        target: MTLTexture,
        color: SIMD3<Float>,
        alpha: Float,
        blendMode: Int,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard alpha.isFinite,
              (0 ... 1).contains(alpha),
              color.x.isFinite, color.y.isFinite, color.z.isFinite,
              (0 ... SceneBlendModeShaderSource.maximumMode).contains(blendMode),
              valid(source: source, target: target, commandBuffer: commandBuffer),
              validMask(mask, maskUVScale: maskUVScale)
        else {
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
            colorAlpha: SIMD4<Float>(color.x, color.y, color.z, alpha),
            maskScaleFlags: SIMD4<Float>(
                maskUVScale.x,
                maskUVScale.y,
                mask != nil ? 1 : 0,
                maskMultipliesBlendAlpha ? 1 : 0
            ),
            blendMode: Int32(blendMode)
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

    private func validMask(_ mask: MTLTexture?, maskUVScale: SIMD2<Float>) -> Bool {
        guard let mask else { return true }
        let supportedFormats: Set<MTLPixelFormat> = [.r8Unorm, .rgba8Unorm, .bgra8Unorm]
        return maskUVScale.x.isFinite
            && maskUVScale.y.isFinite
            && (0...1).contains(maskUVScale.x)
            && (0...1).contains(maskUVScale.y)
            && maskUVScale.x > 0
            && maskUVScale.y > 0
            && mask.textureType == .type2D
            && supportedFormats.contains(mask.pixelFormat)
            && mask.width > 0
            && mask.height > 0
            && mask.mipmapLevelCount > 0
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
