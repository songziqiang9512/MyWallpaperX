import Metal
import simd

/// 官方 pulse.frag `AUDIOPROCESSING == 0` 分支的 Metal 等价实现，
/// 相位偏移、noise UV 系数与输出 clamp 按 [ScenePulseShaderProfile] 逐指纹取值。
///
/// 与官方的两处已知偏差，均沿用项目 premultiplied 合成链的既有边界：
/// - `PULSEALPHA` 在官方 straight alpha 下只乘 `albedo.a`，这里四通道同乘；
/// - `PULSECOLOR` 的 `ApplyBlending` 直接作用在 premultiplied rgb 上（同 Tint backend）。
private let scenePulseShaderSource = SceneBlendModeShaderSource.blendFunctions + """

struct PulseVaryings {
    float4 position [[position]];
    float2 texcoord;
};

struct ScenePulseUniforms {
    float4 tintLow;            // xyz = g_TintColor1
    float4 tintHigh;           // xyz = g_TintColor2
    float4 boundsMaskScale;    // xy = g_PulseThresholds, zw = mask UV scale
    float4 timeSpeedPhaseAmount;
    float4 noiseSpeedAmountPower; // x = noiseSpeed, y = noiseAmount, z = power, w = phaseOffset
    // x: CPU 侧按官方 CreateAudioResponse 求出的 pulse；y: 是否启用 AUDIOPROCESSING
    float4 audio;
    float4 noiseUVScale;       // xy = profile 的 noise UV 时间系数
    int blendMode;
    int pulseColor;
    int pulseAlpha;
    int flags;                 // bit0 = hasNoise, bit1 = hasMask, bit2 = saturate output
};

vertex PulseVaryings scenePulseVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    PulseVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.texcoord = texcoords[vertexID];
    return output;
}

fragment float4 scenePulseFrag(
    PulseVaryings input [[stage_in]],
    texture2d<float> source [[texture(0)]],
    texture2d<float> noiseTexture [[texture(1)]],
    texture2d<float> maskTexture [[texture(2)]],
    constant ScenePulseUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    constexpr sampler linearRepeat(filter::linear, address::repeat);
    float time = u.timeSpeedPhaseAmount.x;
    // 官方 pulse.frag 先无条件 `pulse = v_Pulse`，再在 `#if AUDIOPROCESSING == 0`
    // 分支里用时间驱动值整体覆盖。启用 audio 后 speed/phase/amount/bounds/noise/power
    // 都不参与，pulse 即 CreateAudioResponse 的结果。
    float pulse;
    if (u.audio.y > 0.5) {
        pulse = u.audio.x;
    } else {
        float wave = sin(time * u.timeSpeedPhaseAmount.y
            + (u.timeSpeedPhaseAmount.z + u.noiseSpeedAmountPower.w)) * 0.5 + 0.5;
        pulse = smoothstep(u.boundsMaskScale.x, u.boundsMaskScale.y, wave)
            * u.timeSpeedPhaseAmount.w;
        if ((u.flags & 1) != 0) {
            float2 noiseUV = float2(time * u.noiseUVScale.x, time * u.noiseUVScale.y)
                * u.noiseSpeedAmountPower.x;
            pulse += noiseTexture.sample(linearRepeat, noiseUV).r
                * u.noiseSpeedAmountPower.y;
        }
        pulse = pow(pulse, u.noiseSpeedAmountPower.z);
    }

    float4 sampled = source.sample(linearClamp, input.texcoord);
    float4 albedo = sampled;
    if (u.pulseColor != 0) {
        albedo.rgb = sceneApplyBlending(
            u.blendMode,
            albedo.rgb * u.tintLow.xyz,
            albedo.rgb * u.tintHigh.xyz,
            pulse
        );
    }
    if (u.pulseAlpha != 0) {
        albedo *= pulse;
    }
    if ((u.flags & 2) != 0) {
        float2 maskUV = input.texcoord * u.boundsMaskScale.zw;
        float mask = maskTexture.sample(linearClamp, maskUV).r;
        albedo = mix(sampled, albedo, mask);
    }
    if ((u.flags & 4) != 0) {
        return saturate(albedo);
    }
    return float4(max(float3(0.0), albedo.rgb), albedo.a);
}
"""

struct ScenePulsePipeline {
    struct Inputs {
        let time: Float
        let speed: Float
        let phase: Float
        let phaseOffset: Float
        let amount: Float
        let bounds: SIMD2<Float>
        let noiseSpeed: Float
        let noiseAmount: Float
        let noiseUVScale: SIMD2<Float>
        let power: Float
        let tintLow: SIMD3<Float>
        let tintHigh: SIMD3<Float>
        let blendMode: Int
        let pulseColor: Bool
        let pulseAlpha: Bool
        let saturatesOutput: Bool
        let maskUVScale: SIMD2<Float>
        /// `nil` 表示作者未启用 AUDIOPROCESSING，走时间驱动路径。
        let audioPulse: Float?
    }

    private struct Uniforms {
        var tintLow: SIMD4<Float>
        var tintHigh: SIMD4<Float>
        var boundsMaskScale: SIMD4<Float>
        var timeSpeedPhaseAmount: SIMD4<Float>
        var noiseSpeedAmountPower: SIMD4<Float>
        var noiseUVScale: SIMD4<Float>
        var audio: SIMD4<Float>
        var blendMode: Int32
        var pulseColor: Int32
        var pulseAlpha: Int32
        var flags: Int32
    }

    private let state: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard pixelFormat == .bgra8Unorm,
              let library = try? device.makeLibrary(
                  source: scenePulseShaderSource,
                  options: MTLCompileOptions()
              ),
              let vertex = library.makeFunction(name: "scenePulseVert"),
              let fragment = library.makeFunction(name: "scenePulseFrag")
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
        noise: MTLTexture?,
        mask: MTLTexture?,
        target: MTLTexture,
        inputs: Inputs,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard validInputs(inputs),
              valid(source: source, target: target, commandBuffer: commandBuffer)
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
        encoder.setFragmentTexture(noise ?? source, index: 1)
        encoder.setFragmentTexture(mask ?? source, index: 2)
        var uniforms = Uniforms(
            tintLow: SIMD4(inputs.tintLow, 0),
            tintHigh: SIMD4(inputs.tintHigh, 0),
            boundsMaskScale: SIMD4(
                inputs.bounds.x, inputs.bounds.y,
                inputs.maskUVScale.x, inputs.maskUVScale.y
            ),
            timeSpeedPhaseAmount: SIMD4(
                inputs.time, inputs.speed, inputs.phase, inputs.amount
            ),
            noiseSpeedAmountPower: SIMD4(
                inputs.noiseSpeed, inputs.noiseAmount, inputs.power, inputs.phaseOffset
            ),
            noiseUVScale: SIMD4(
                inputs.noiseUVScale.x, inputs.noiseUVScale.y, 0, 0
            ),
            audio: SIMD4(
                inputs.audioPulse ?? 0,
                inputs.audioPulse == nil ? 0 : 1,
                0,
                0
            ),
            blendMode: Int32(inputs.blendMode),
            pulseColor: inputs.pulseColor ? 1 : 0,
            pulseAlpha: inputs.pulseAlpha ? 1 : 0,
            flags: (noise != nil ? 1 : 0)
                | (mask != nil ? 2 : 0)
                | (inputs.saturatesOutput ? 4 : 0)
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

    private func validInputs(_ inputs: Inputs) -> Bool {
        let scalars = [
            inputs.time, inputs.speed, inputs.phase, inputs.phaseOffset, inputs.amount,
            inputs.bounds.x, inputs.bounds.y,
            inputs.noiseSpeed, inputs.noiseAmount, inputs.power,
            inputs.noiseUVScale.x, inputs.noiseUVScale.y,
            inputs.maskUVScale.x, inputs.maskUVScale.y,
        ]
        let colors = [inputs.tintLow, inputs.tintHigh]
        return scalars.allSatisfy(\.isFinite)
            && colors.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
            }
            && inputs.bounds.x < inputs.bounds.y
            && (0 ... SceneBlendModeShaderSource.maximumMode).contains(inputs.blendMode)
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
