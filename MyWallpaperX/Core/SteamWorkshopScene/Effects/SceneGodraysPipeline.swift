import Metal
import simd

/// 官方 godrays 五 pass 的 Metal 等价实现（`CASTER=0` Radial / `NOISE=1` / `COPYBG=0`）。
/// 每个 kernel 逐行对照 stock 2.8.42 shader；combine 消费共享 `ApplyBlending` 表。
private let sceneGodraysShaderSource = SceneBlendModeShaderSource.blendFunctions + """

struct GodraysVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex GodraysVaryings sceneGodraysVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    GodraysVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

struct GodraysDownsampleUniforms {
    float4 thresholdNoise;   // x=threshold, y=noiseAmount, z=noiseSmoothness, w=time
    float4 noiseMotion;      // x=noiseSpeed, y=noiseScale
    float4 maskScaleFlags;   // xy=mask UV scale, z=hasMask, w=hasNoiseTexture
};

fragment float4 sceneGodraysDownsampleFrag(
    GodraysVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    texture2d<float> noiseTexture [[texture(2)]],
    constant GodraysDownsampleUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr sampler linearRepeat(filter::linear, address::repeat);
    float mask = 1.0;
    if (u.maskScaleFlags.z > 0.5) {
        mask = maskTexture.sample(
            linearClamp,
            clamp(input.texcoord * u.maskScaleFlags.xy, 0.0, 1.0)
        ).r;
    }
    float4 sampled = source.sample(linearClamp, input.texcoord);

    // 官方 downsample2.vert 的 NOISE UV：xy = (uv + t*speed)*scale；
    // wz = ((uv.y, -uv.x)*0.633 + (-t, t)*0.5*speed)*scale（注意 wz 分量顺序）。
    float time = u.thresholdNoise.w;
    float speed = u.noiseMotion.x;
    float scale = u.noiseMotion.y;
    float2 noiseUV1 = (input.texcoord + time * speed) * scale;
    float2 wz = (float2(input.texcoord.y, -input.texcoord.x) * 0.633
        + float2(-time, time) * 0.5 * speed) * scale;
    float2 noiseUV2 = float2(wz.y, wz.x);
    float noiseSample = 1.0;
    if (u.maskScaleFlags.w > 0.5) {
        noiseSample = noiseTexture.sample(linearRepeat, noiseUV1).r
            * noiseTexture.sample(linearRepeat, noiseUV2).r;
    }
    noiseSample = mix(sampled.a, sampled.a * noiseSample, u.thresholdNoise.y);

    sampled.rgb *= sampled.a;
    sampled.a = 1.0;
    float4 result = sampled * mask
        * step(u.thresholdNoise.x, dot(float3(0.11, 0.59, 0.3), sampled.rgb));
    result.a *= smoothstep(
        0.5 - u.thresholdNoise.z,
        0.5 + u.thresholdNoise.z,
        noiseSample
    );
    return result;
}

struct GodraysCastUniforms {
    float4 centerLength;     // xy=center, z=rayLength, w=rayIntensity
    float4 colorSamples;     // xyz=colorRays, w=samples50
};

fragment float4 sceneGodraysCastFrag(
    GodraysVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant GodraysCastUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 texCoords = input.texcoord;
    float4 albedo = float4(0.0);
    float2 direction = u.centerLength.xy - texCoords;
    float dist = length(direction);
    direction /= dist;
    dist *= u.centerLength.z;
    texCoords += direction * dist;

    int sampleCount = u.colorSamples.w > 0.5 ? 50 : 30;
    float sampleIntensity = u.colorSamples.w > 0.5 ? 0.1 * (30.0 / 50.0) : 0.1;
    float sampleDrop = float(sampleCount - 1);
    direction = direction * dist / sampleDrop;
    for (int i = 0; i < sampleCount; ++i) {
        float4 sampled = source.sample(linearClamp, texCoords);
        texCoords -= direction;
        albedo += sampled * (float(i) / sampleDrop);
    }

    albedo.rgb *= u.colorSamples.xyz;
    float intensity = u.centerLength.w * sampleIntensity;
    return float4(intensity * albedo.rgb, saturate(intensity * albedo.a));
}

struct GodraysGaussianUniforms {
    float4 step; // xy = 采样步长（官方 v_TexCoord.zw：scale / halfResolution）
    int kernel13;
};

fragment float4 sceneGodraysGaussianFrag(
    GodraysVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant GodraysGaussianUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 uv = input.texcoord;
    float2 d = u.step.xy;
    if (u.kernel13 != 0) {
        float2 o1 = float2(1.4091998770852122) * d;
        float2 o2 = float2(3.2979348079914822) * d;
        float2 o3 = float2(5.2062900776825969) * d;
        return source.sample(linearClamp, uv) * 0.1976406528809576
            + source.sample(linearClamp, uv + o1) * 0.2959855056006557
            + source.sample(linearClamp, uv - o1) * 0.2959855056006557
            + source.sample(linearClamp, uv + o2) * 0.0935333619980593
            + source.sample(linearClamp, uv - o2) * 0.0935333619980593
            + source.sample(linearClamp, uv + o3) * 0.0116608059608062
            + source.sample(linearClamp, uv - o3) * 0.0116608059608062;
    }
    float2 o1 = float2(2.3515644035337887) * d;
    float2 o2 = float2(0.469433779698372) * d;
    float2 o3 = float2(1.4091998770852121) * d;
    float2 o4 = float2(3.0) * d;
    return source.sample(linearClamp, uv + o1) * 0.2028175528299753
        + source.sample(linearClamp, uv + o2) * 0.4044856614512112
        + source.sample(linearClamp, uv - o3) * 0.3213933537319605
        + source.sample(linearClamp, uv - o4) * 0.0713034319868530;
}

struct GodraysCombineUniforms {
    int blendMode;
};

fragment float4 sceneGodraysCombineFrag(
    GodraysVaryings input [[stage_in]],
    texture2d<float> rays [[texture(0)]],
    texture2d<float> source [[texture(1)]],
    constant GodraysCombineUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float4 raySample = rays.sample(linearClamp, input.texcoord);
    float4 albedo = source.sample(linearClamp, input.texcoord);
    if (u.blendMode == 0) {
        return raySample;
    }
    albedo.rgb = sceneApplyBlending(
        u.blendMode, albedo.rgb, raySample.rgb, raySample.a
    );
    albedo.a = saturate(albedo.a + raySample.a);
    return albedo;
}
"""

struct SceneGodraysPipeline {
    private struct DownsampleUniforms {
        var thresholdNoise: SIMD4<Float>
        var noiseMotion: SIMD4<Float>
        var maskScaleFlags: SIMD4<Float>
    }

    private struct CastUniforms {
        var centerLength: SIMD4<Float>
        var colorSamples: SIMD4<Float>
    }

    private struct GaussianUniforms {
        var step: SIMD4<Float>
        var kernel13: Int32
    }

    private struct CombineUniforms {
        var blendMode: Int32
    }

    private let downsampleState: MTLRenderPipelineState
    private let castState: MTLRenderPipelineState
    private let gaussianState: MTLRenderPipelineState
    private let combineState: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: sceneGodraysShaderSource,
                  options: MTLCompileOptions()
              ),
              let vertex = library.makeFunction(name: "sceneGodraysVert")
        else {
            return nil
        }
        func state(_ fragmentName: String) -> MTLRenderPipelineState? {
            guard let fragment = library.makeFunction(name: fragmentName) else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let downsampleState = state("sceneGodraysDownsampleFrag"),
              let castState = state("sceneGodraysCastFrag"),
              let gaussianState = state("sceneGodraysGaussianFrag"),
              let combineState = state("sceneGodraysCombineFrag")
        else {
            return nil
        }
        self.downsampleState = downsampleState
        self.castState = castState
        self.gaussianState = gaussianState
        self.combineState = combineState
        deviceRegistryID = device.registryID
    }

    func encodeDownsample(
        source: MTLTexture,
        mask: MTLTexture?,
        maskUVScale: SIMD2<Float>,
        noise: MTLTexture?,
        target: MTLTexture,
        plan: SceneGodraysPlan,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard time.isFinite,
              validColor(source, usage: .shaderRead),
              validColor(target, usage: .renderTarget),
              mask.map({ validColor($0, usage: .shaderRead) }) ?? true,
              noise.map({ validColor($0, usage: .shaderRead) }) ?? true
        else {
            return false
        }
        var uniforms = DownsampleUniforms(
            thresholdNoise: SIMD4(
                plan.threshold, plan.noiseAmount, plan.noiseSmoothness, time
            ),
            noiseMotion: SIMD4(plan.noiseSpeed, plan.noiseScale, 0, 0),
            maskScaleFlags: SIMD4(
                maskUVScale.x, maskUVScale.y,
                mask != nil ? 1 : 0,
                noise != nil ? 1 : 0
            )
        )
        return draw(
            state: downsampleState,
            textures: [source, mask ?? source, noise ?? source],
            uniforms: &uniforms,
            length: MemoryLayout<DownsampleUniforms>.stride,
            target: target,
            commandBuffer: commandBuffer
        )
    }

    func encodeCast(
        source: MTLTexture,
        target: MTLTexture,
        plan: SceneGodraysPlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard validColor(source, usage: .shaderRead),
              validColor(target, usage: .renderTarget)
        else {
            return false
        }
        var uniforms = CastUniforms(
            centerLength: SIMD4(
                plan.center.x, plan.center.y, plan.rayLength, plan.rayIntensity
            ),
            colorSamples: SIMD4(
                plan.colorRays.x, plan.colorRays.y, plan.colorRays.z,
                plan.samples50 ? 1 : 0
            )
        )
        return draw(
            state: castState,
            textures: [source],
            uniforms: &uniforms,
            length: MemoryLayout<CastUniforms>.stride,
            target: target,
            commandBuffer: commandBuffer
        )
    }

    func encodeGaussian(
        source: MTLTexture,
        target: MTLTexture,
        plan: SceneGodraysPlan,
        vertical: Bool,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard validColor(source, usage: .shaderRead),
              validColor(target, usage: .renderTarget),
              source.width > 0, source.height > 0
        else {
            return false
        }
        // 官方 gaussian.vert：step = scale / g_Texture0Resolution（半分辨率 RT）。
        let step = vertical
            ? SIMD2<Float>(0, plan.blurScaleY.y / Float(source.height))
            : SIMD2<Float>(plan.blurScaleX.x / Float(source.width), 0)
        var uniforms = GaussianUniforms(
            step: SIMD4(step.x, step.y, 0, 0),
            kernel13: plan.kernel13 ? 1 : 0
        )
        return draw(
            state: gaussianState,
            textures: [source],
            uniforms: &uniforms,
            length: MemoryLayout<GaussianUniforms>.stride,
            target: target,
            commandBuffer: commandBuffer
        )
    }

    func encodeCombine(
        rays: MTLTexture,
        source: MTLTexture,
        target: MTLTexture,
        plan: SceneGodraysPlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard (0 ... SceneBlendModeShaderSource.maximumMode).contains(plan.blendMode),
              validColor(rays, usage: .shaderRead),
              validColor(source, usage: .shaderRead),
              validColor(target, usage: .renderTarget),
              source.width == target.width,
              source.height == target.height
        else {
            return false
        }
        var uniforms = CombineUniforms(blendMode: Int32(plan.blendMode))
        return draw(
            state: combineState,
            textures: [rays, source],
            uniforms: &uniforms,
            length: MemoryLayout<CombineUniforms>.stride,
            target: target,
            commandBuffer: commandBuffer
        )
    }

    private func draw<Uniforms>(
        state: MTLRenderPipelineState,
        textures: [MTLTexture],
        uniforms: inout Uniforms,
        length: Int,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard commandBuffer.commandQueue.device.registryID == deviceRegistryID,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return false
        }
        encoder.setRenderPipelineState(state)
        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.setFragmentBytes(&uniforms, length: length, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func validColor(_ texture: MTLTexture, usage: MTLTextureUsage) -> Bool {
        texture.textureType == .type2D
            && [.bgra8Unorm, .rgba8Unorm, .r8Unorm].contains(texture.pixelFormat)
            && texture.width > 0
            && texture.height > 0
            && texture.mipmapLevelCount == 1
            && texture.sampleCount == 1
            && texture.usage.contains(usage)
            && texture.device.registryID == deviceRegistryID
    }
}
