import Metal

private let sceneFilmGrainShaderSource = SceneBlendModeShaderSource.blendFunctions + """

struct FilmGrainVaryings {
    float4 position [[position]];
    float2 uv;
};

struct FilmGrainUniforms {
    float scale;
    float strength;
    float exponent;
    float time;
    int blendMode;
};

vertex FilmGrainVaryings sceneFilmGrainVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    return FilmGrainVaryings { float4(positions[vertexID], 0.0, 1.0), texcoords[vertexID] };
}

fragment float4 sceneFilmGrainFrag(
    FilmGrainVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> noiseTexture [[texture(1)]],
    constant FilmGrainUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr sampler linearRepeat(filter::linear, address::repeat);
    float4 albedo = source.sample(linearClamp, input.uv);
    float aspect = float(source.get_width()) / float(source.get_height());
    float t = fract(u.time);
    float2 aspectScale = float2(aspect, 1.0);
    float2 firstUV = (input.uv + t) * u.scale * aspectScale;
    float2 secondUV = (input.uv - t * 2.5) * u.scale * 0.52 * aspectScale;
    float3 first = noiseTexture.sample(linearRepeat, firstUV).rgb;
    float3 second = noiseTexture.sample(linearRepeat, secondUV).gbr;
    float3 noise = pow(saturate(first * second), float3(u.exponent));
    float3 straightRGB = albedo.a > 1e-6
        ? clamp(albedo.rgb / albedo.a, 0.0, 1.0)
        : float3(0.0);
    albedo.rgb = sceneApplyBlending(u.blendMode, straightRGB, noise, u.strength)
        * albedo.a;
    return albedo;
}
"""

final class SceneFilmGrainPipeline {
    private struct Uniforms {
        var scale: Float
        var strength: Float
        var exponent: Float
        var time: Float
        var blendMode: Int32
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneFilmGrainShaderSource,
                  options: MTLCompileOptions()
              ),
              let vertex = library.makeFunction(name: "sceneFilmGrainVert"),
              let fragment = library.makeFunction(name: "sceneFilmGrainFrag") else {
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
        noise: MTLTexture,
        target: MTLTexture,
        plan: SceneFilmGrainExecutionPlan,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(source: source, noise: noise, target: target),
              source.width == target.width,
              source.height == target.height,
              ObjectIdentifier(source) != ObjectIdentifier(target),
              plan.blendMode == 14,
              plan.greyscale == false,
              plan.scale.isFinite,
              (0...20).contains(plan.scale),
              plan.strength.isFinite,
              (0...5).contains(plan.strength),
              plan.exponent.isFinite,
              (0...5).contains(plan.exponent),
              time.isFinite,
              commandBuffer.commandQueue.device.registryID == deviceRegistryID else {
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
        encoder.setFragmentTexture(noise, index: 1)
        var uniforms = Uniforms(
            scale: plan.scale,
            strength: plan.strength,
            exponent: plan.exponent,
            time: time,
            blendMode: Int32(plan.blendMode)
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

    private func valid(source: MTLTexture, noise: MTLTexture, target: MTLTexture) -> Bool {
        validTexture(source, formats: [.bgra8Unorm], usage: .shaderRead)
            && validTexture(
                noise,
                formats: [.rgba8Unorm, .bgra8Unorm],
                usage: .shaderRead
            )
            && validTexture(target, formats: [.bgra8Unorm], usage: .renderTarget)
            && [source, noise, target].allSatisfy {
                $0.device.registryID == deviceRegistryID
            }
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
            && texture.sampleCount == 1
            && texture.usage.contains(usage)
    }
}
