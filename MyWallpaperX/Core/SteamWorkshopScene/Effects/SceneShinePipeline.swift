import Metal
import simd

/// Project-owned Shine implementation: thresholded luminance seeds several
/// rotating directional rays, then applies a separable Gaussian blur and the
/// authored blend mode. The stock sources are not compiled or translated.
private let sceneShineShaderSource = SceneBlendModeShaderSource.blendFunctions + """

struct ShineVaryings {
    float4 position [[position]];
    float2 texcoord;
};

vertex ShineVaryings sceneShineVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    ShineVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

struct ShineDownsampleUniforms {
    float4 thresholdNoise; // threshold, amount, scale, speed
    float4 maskTime;       // mask scale xy, has mask, time
};

fragment float4 sceneShineDownsampleFrag(
    ShineVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    texture2d<float> noiseTexture [[texture(2)]],
    constant ShineDownsampleUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr sampler linearRepeat(filter::linear, address::repeat);
    float4 sampled = source.sample(linearClamp, input.texcoord);
    float mask = 1.0;
    if (u.maskTime.z > 0.5) {
        float2 maskUV = clamp(input.texcoord * u.maskTime.xy, 0.0, 1.0);
        mask = maskTexture.sample(linearClamp, maskUV).r;
    }

    float time = u.maskTime.w * u.thresholdNoise.w;
    float scale = u.thresholdNoise.z;
    float2 noiseUV1 = (input.texcoord + float2(time, -time * 0.7)) * scale;
    float2 centered = input.texcoord - 0.5;
    float2 noiseUV2 = float2(-centered.y, centered.x) * (scale * 0.71)
        + float2(-time * 0.53, time * 0.89);
    float noise = noiseTexture.sample(linearRepeat, noiseUV1).r
        * noiseTexture.sample(linearRepeat, noiseUV2).r;
    float modulation = mix(1.0, clamp(0.35 + noise * 1.3, 0.0, 1.5),
        u.thresholdNoise.y);

    float3 premultiplied = sampled.rgb * sampled.a;
    float luminance = dot(premultiplied, float3(0.2126, 0.7152, 0.0722));
    float gate = smoothstep(
        u.thresholdNoise.x,
        min(1.0, u.thresholdNoise.x + 0.04),
        luminance
    );
    return float4(
        premultiplied * gate * mask,
        sampled.a * gate * mask * modulation
    );
}

struct ShineCastUniforms {
    float4 directionLength; // direction, speed, length, intensity
    float4 colorAspect;     // color rgb, target aspect
    int4 counts;            // edge count, sample count
    float time;
};

fragment float4 sceneShineCastFrag(
    ShineVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant ShineCastUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float4 accumulated = float4(0.0);
    float totalWeight = 0.0;
    int edges = clamp(u.counts.x, 2, 5);
    int samples = clamp(u.counts.y, 4, 50);
    float baseAngle = u.directionLength.x + u.time * u.directionLength.y;
    float aspect = max(u.colorAspect.w, 0.001);

    for (int edge = 0; edge < 5; ++edge) {
        if (edge >= edges) { break; }
        float angle = baseAngle + 6.28318530718 * float(edge) / float(edges);
        float2 direction = normalize(float2(cos(angle) / aspect, sin(angle)));
        for (int index = 1; index <= 50; ++index) {
            if (index > samples) { break; }
            float progress = float(index) / float(samples);
            float weight = progress * (2.0 - progress);
            float2 uv = input.texcoord + direction
                * (u.directionLength.z * progress);
            accumulated += source.sample(linearClamp, uv) * weight;
            totalWeight += weight;
        }
    }

    float energy = u.directionLength.w / max(totalWeight / sqrt(float(edges)), 1.0);
    accumulated.rgb *= u.colorAspect.rgb * energy;
    accumulated.a = saturate(accumulated.a * energy);
    return accumulated;
}

struct ShineGaussianUniforms {
    float4 stepSigma; // step xy, sigma, radius
};

fragment float4 sceneShineGaussianFrag(
    ShineVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    constant ShineGaussianUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    int radius = clamp(int(u.stepSigma.w), 1, 6);
    float sigma = max(u.stepSigma.z, 0.5);
    float4 sum = float4(0.0);
    float weightSum = 0.0;
    for (int offset = -6; offset <= 6; ++offset) {
        if (abs(offset) > radius) { continue; }
        float distance = float(offset);
        float weight = exp(-(distance * distance) / (2.0 * sigma * sigma));
        sum += source.sample(
            linearClamp,
            input.texcoord + u.stepSigma.xy * distance
        ) * weight;
        weightSum += weight;
    }
    return sum / max(weightSum, 0.0001);
}

struct ShineCombineUniforms {
    int blendMode;
};

fragment float4 sceneShineCombineFrag(
    ShineVaryings input [[stage_in]],
    texture2d<float> rays [[texture(0)]],
    texture2d<float> source [[texture(1)]],
    constant ShineCombineUniforms &u [[buffer(0)]]
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

struct SceneShinePipeline {
    private struct DownsampleUniforms {
        var thresholdNoise: SIMD4<Float>
        var maskTime: SIMD4<Float>
    }

    private struct CastUniforms {
        var directionLength: SIMD4<Float>
        var colorAspect: SIMD4<Float>
        var counts: SIMD4<Int32>
        var time: Float
    }

    private struct GaussianUniforms {
        var stepSigma: SIMD4<Float>
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
                  source: sceneShineShaderSource,
                  options: MTLCompileOptions()
              ),
              let vertex = library.makeFunction(name: "sceneShineVert")
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
        guard let downsampleState = state("sceneShineDownsampleFrag"),
              let castState = state("sceneShineCastFrag"),
              let gaussianState = state("sceneShineGaussianFrag"),
              let combineState = state("sceneShineCombineFrag")
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
        noise: MTLTexture,
        target: MTLTexture,
        plan: SceneShineExecutionPlan,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard time.isFinite,
              validColor(source, usage: .shaderRead),
              validColor(target, usage: .renderTarget),
              mask.map({ validColor($0, usage: .shaderRead) }) ?? true,
              validColor(noise, usage: .shaderRead)
        else {
            return false
        }
        var uniforms = DownsampleUniforms(
            thresholdNoise: SIMD4(
                plan.threshold, plan.noiseAmount, plan.noiseScale, plan.noiseSpeed
            ),
            maskTime: SIMD4(
                maskUVScale.x, maskUVScale.y, mask == nil ? 0 : 1, time
            )
        )
        return draw(
            state: downsampleState,
            textures: [source, mask ?? source, noise],
            uniforms: &uniforms,
            target: target,
            commandBuffer: commandBuffer
        )
    }

    func encodeCast(
        source: MTLTexture,
        target: MTLTexture,
        plan: SceneShineExecutionPlan,
        time: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard time.isFinite,
              validColor(source, usage: .shaderRead),
              validColor(target, usage: .renderTarget),
              (2 ... 5).contains(plan.edgeCount),
              [4, 8, 15, 30, 50].contains(plan.sampleCount)
        else {
            return false
        }
        var uniforms = CastUniforms(
            directionLength: SIMD4(
                plan.direction, plan.rotationSpeed, plan.rayLength, plan.rayIntensity
            ),
            colorAspect: SIMD4(
                plan.rayColor.x, plan.rayColor.y, plan.rayColor.z,
                Float(source.width) / Float(source.height)
            ),
            counts: SIMD4(Int32(plan.edgeCount), Int32(plan.sampleCount), 0, 0),
            time: time
        )
        return draw(
            state: castState,
            textures: [source],
            uniforms: &uniforms,
            target: target,
            commandBuffer: commandBuffer
        )
    }

    func encodeGaussian(
        source: MTLTexture,
        target: MTLTexture,
        plan: SceneShineExecutionPlan,
        vertical: Bool,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard validColor(source, usage: .shaderRead),
              validColor(target, usage: .renderTarget),
              [1, 3, 6].contains(plan.kernelRadius)
        else {
            return false
        }
        let step = vertical
            ? SIMD2<Float>(0, plan.blurScaleY.y / Float(source.height))
            : SIMD2<Float>(plan.blurScaleX.x / Float(source.width), 0)
        let sigma = max(Float(plan.kernelRadius) * 0.52, 0.75)
        var uniforms = GaussianUniforms(
            stepSigma: SIMD4(step.x, step.y, sigma, Float(plan.kernelRadius))
        )
        return draw(
            state: gaussianState,
            textures: [source],
            uniforms: &uniforms,
            target: target,
            commandBuffer: commandBuffer
        )
    }

    func encodeCombine(
        rays: MTLTexture,
        source: MTLTexture,
        target: MTLTexture,
        plan: SceneShineExecutionPlan,
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
            target: target,
            commandBuffer: commandBuffer
        )
    }

    private func draw<Uniforms>(
        state: MTLRenderPipelineState,
        textures: [MTLTexture],
        uniforms: inout Uniforms,
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
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private func validColor(_ texture: MTLTexture, usage: MTLTextureUsage) -> Bool {
        texture.textureType == .type2D
            && [.bgra8Unorm, .rgba8Unorm, .r8Unorm].contains(texture.pixelFormat)
            && texture.width > 0
            && texture.height > 0
            && (usage.contains(.renderTarget)
                ? texture.mipmapLevelCount == 1
                : texture.mipmapLevelCount > 0)
            && texture.sampleCount == 1
            && texture.usage.contains(usage)
            && texture.device.registryID == deviceRegistryID
    }
}
