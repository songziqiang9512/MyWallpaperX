import Metal
import simd

private let sceneWaterCausticsShaderSource = SceneBlendModeShaderSource.blendFunctions + """

struct CausticsVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct CausticsUniforms {
    float4 params0; // brightness, glow, scale, speed
    float4 params1; // timeOffset, distortion, chromatic, blur
    float4 colorStart;
    float4 colorEnd;
    float4 maskScaleRatio; // mask xy, aspect ratio, hasMask
    int blendMode;
};

vertex CausticsVaryings sceneWaterCausticsVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    CausticsVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 sceneWaterCausticsFrag(
    CausticsVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    texture2d<float> patternTexture [[texture(2)]],
    texture2d<float> noiseTexture [[texture(3)]],
    texture2d<float> offsetTexture [[texture(4)]],
    texture2d<float> glowTexture [[texture(5)]],
    constant CausticsUniforms &u [[buffer(0)]],
    constant float &frameTime [[buffer(1)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr sampler linearRepeat(filter::linear, address::repeat);
    float4 albedo = source.sample(linearClamp, input.texcoord);
    float mask = 1.0;
    if (u.maskScaleRatio.w > 0.5) {
        mask = maskTexture.sample(
            linearClamp, clamp(input.texcoord * u.maskScaleRatio.xy, 0.0, 1.0)
        ).r;
    }

    float2 coords = input.texcoord;
    coords.x *= u.maskScaleRatio.z;
    coords *= u.params0.z;
    float2 noiseCoords = coords * 0.02;
    float2 noiseCoords2 = coords * 0.0333;
    float2 blendCoords = coords * 0.01333;
    float2 shiftCoords = coords * 0.05;
    float time = frameTime * u.params0.w + u.params1.x;
    noiseCoords.x += time * 0.005;
    noiseCoords2.y += time * 0.004111;
    blendCoords += time * 0.003777;
    shiftCoords += time * 0.01;

    float4 shift = offsetTexture.sample(linearRepeat, shiftCoords) * 2.0 - 1.0;
    float4 noise0 = noiseTexture.sample(linearRepeat, noiseCoords) * 2.0 - 1.0;
    float4 noise1 = noiseTexture.sample(linearRepeat, noiseCoords2) * 2.0 - 1.0;
    coords += (noise0.xy + noise1.xy) * (0.025 * u.params1.y);
    coords += shift.rg * u.params1.y;

    float2 left = coords - float2(0.01 * u.params1.z, 0.0);
    float2 right = coords + float2(0.01 * u.params1.z, 0.0);
    float3 caustics = float3(
        patternTexture.sample(linearRepeat, left).r,
        patternTexture.sample(linearRepeat, coords).r,
        patternTexture.sample(linearRepeat, right).r
    );
    float glowSample = glowTexture.sample(linearRepeat, coords).r;
    float4 blendNoise = noiseTexture.sample(linearRepeat, blendCoords);
    caustics = mix(caustics, float3(glowSample), u.params1.w);
    float sampleValue = dot(caustics, float3(0.33333));
    sampleValue = smoothstep(
        blendNoise.x * 0.8,
        1.0 - blendNoise.y * 0.2,
        sampleValue + glowSample * u.params0.y
    );
    float3 effectColor = u.params0.x
        * mix(u.colorStart.xyz, u.colorEnd.xyz, blendNoise.x) * caustics;

    float alpha = albedo.a;
    float3 straight = alpha > 1e-6 ? clamp(albedo.rgb / alpha, 0.0, 1.0) : float3(0.0);
    float3 blended = max(float3(0.0), sceneApplyBlending(
        u.blendMode, straight, effectColor, mask * sampleValue
    ));
    return float4(blended * alpha, alpha);
}
"""

struct SceneWaterCausticsPipeline {
    private struct Uniforms {
        var params0: SIMD4<Float>
        var params1: SIMD4<Float>
        var colorStart: SIMD4<Float>
        var colorEnd: SIMD4<Float>
        var maskScaleRatio: SIMD4<Float>
        var blendMode: Int32
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneWaterCausticsShaderSource, options: MTLCompileOptions()
              ),
              let vertex = library.makeFunction(name: "sceneWaterCausticsVert"),
              let fragment = library.makeFunction(name: "sceneWaterCausticsFrag")
        else { return nil }
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
        resources: SceneWaterCausticsEffectTextures,
        target: MTLTexture,
        plan: SceneWaterCausticsExecutionPlan,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(
            source: source, resources: resources, target: target,
            plan: plan, time: time, commandBuffer: commandBuffer
        ), let pattern = resources.pattern, let glow = resources.glow,
           let noise = resources.noise, let offset = resources.offset
        else { return false }
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
        encoder.setFragmentTexture(resources.mask ?? source, index: 1)
        encoder.setFragmentTexture(pattern, index: 2)
        encoder.setFragmentTexture(noise, index: 3)
        encoder.setFragmentTexture(offset, index: 4)
        encoder.setFragmentTexture(glow, index: 5)
        var uniforms = Uniforms(
            params0: SIMD4(plan.brightness, plan.glow, plan.scale, plan.speed),
            params1: SIMD4(plan.timeOffset, plan.distortion, plan.chromatic, plan.blur),
            colorStart: SIMD4(plan.colorStart.x, plan.colorStart.y, plan.colorStart.z, 0),
            colorEnd: SIMD4(plan.colorEnd.x, plan.colorEnd.y, plan.colorEnd.z, 0),
            maskScaleRatio: SIMD4(
                resources.maskUVScale.x, resources.maskUVScale.y,
                Float(source.width) / Float(source.height), resources.mask == nil ? 0 : 1
            ),
            blendMode: Int32(plan.blendMode)
        )
        var frameTime = time
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&frameTime, length: MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func valid(
        source: MTLTexture,
        resources: SceneWaterCausticsEffectTextures,
        target: MTLTexture,
        plan: SceneWaterCausticsExecutionPlan,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let textures = [resources.pattern, resources.glow, resources.noise, resources.offset]
        let supported: Set<MTLPixelFormat> = [.r8Unorm, .rg8Unorm, .rgba8Unorm, .bgra8Unorm]
        return time.isFinite && resources.matches(plan)
            && source.textureType == .type2D && target.textureType == .type2D
            && source.pixelFormat == .bgra8Unorm && target.pixelFormat == .bgra8Unorm
            && source.width > 0 && source.width == target.width
            && source.height > 0 && source.height == target.height
            && source.mipmapLevelCount == 1 && target.mipmapLevelCount == 1
            && source.sampleCount == 1 && target.sampleCount == 1
            && source.usage.contains(.shaderRead) && target.usage.contains(.renderTarget)
            && ObjectIdentifier(source) != ObjectIdentifier(target)
            && commandBuffer.commandQueue.device.registryID == deviceRegistryID
            && ([source, target] + textures.compactMap { $0 }).allSatisfy {
                $0.device.registryID == deviceRegistryID
            }
            && textures.allSatisfy { texture in
                guard let texture else { return false }
                return texture.textureType == .type2D && supported.contains(texture.pixelFormat)
                    && texture.width > 0 && texture.height > 0 && texture.sampleCount == 1
                    && texture.mipmapLevelCount > 0 && texture.usage.contains(.shaderRead)
            }
            && validMask(resources.mask, scale: resources.maskUVScale, formats: supported)
    }

    private func validMask(
        _ mask: MTLTexture?, scale: SIMD2<Float>, formats: Set<MTLPixelFormat>
    ) -> Bool {
        guard let mask else { return true }
        return scale.x.isFinite && scale.y.isFinite && scale.x > 0 && scale.y > 0
            && scale.x <= 1 && scale.y <= 1 && mask.textureType == .type2D
            && formats.contains(mask.pixelFormat) && mask.width > 0 && mask.height > 0
            && mask.mipmapLevelCount > 0 && mask.sampleCount == 1
            && mask.usage.contains(.shaderRead) && mask.device.registryID == deviceRegistryID
    }
}
