import Metal
import simd

private struct SceneCursorRippleApplyUniforms {
    var currentAndPreviousX: SIMD4<Float>
    var previousYScaleDeltaActive: SIMD4<Float>
}

private struct SceneCursorRippleSimulateUniforms {
    var decaySpeedDeltaMasked: SIMD4<Float>
    var maskUVScale: SIMD2<Float>
    var padding: SIMD2<Float> = .zero
}

private struct SceneCursorRippleCombineUniforms {
    var strength: Float
    var padding: SIMD3<Float> = .zero
}

private let sceneCursorRippleShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct CursorRippleVaryings {
    float4 position [[position]];
    float2 uv;
};

struct CursorRippleApplyUniforms {
    float4 currentAndPreviousX;
    float4 previousYScaleDeltaActive;
};

struct CursorRippleSimulateUniforms {
    float4 decaySpeedDeltaMasked;
    float2 maskUVScale;
    float2 padding;
};

struct CursorRippleCombineUniforms {
    float strength;
    float3 padding;
};

vertex CursorRippleVaryings sceneCursorRippleVert(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    const float2 texcoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    CursorRippleVaryings output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.uv = texcoords[vertexID];
    return output;
}

float2 decodeRippleState(float4 value) {
    return float2(value.r - value.g, value.b - value.a);
}

float4 encodeRippleState(float2 value) {
    value = clamp(value, -1.0, 1.0);
    float2 positive = max(value, 0.0);
    float2 negative = max(-value, 0.0);
    return float4(positive.x, negative.x, positive.y, negative.y);
}

fragment float4 sceneCursorRippleApplyFrag(
    CursorRippleVaryings input [[stage_in]],
    texture2d<float> history [[texture(0)]],
    constant CursorRippleApplyUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 state = decodeRippleState(history.sample(linearClamp, input.uv));
    float2 current = u.currentAndPreviousX.xy;
    float2 previous = float2(
        u.currentAndPreviousX.z,
        u.previousYScaleDeltaActive.x
    );
    float scale = u.previousYScaleDeltaActive.y;
    float frameDelta = u.previousYScaleDeltaActive.z;
    float active = u.previousYScaleDeltaActive.w;

    float2 segment = current - previous;
    float segmentLengthSquared = dot(segment, segment);
    float projection = segmentLengthSquared > 1e-8
        ? clamp(dot(input.uv - previous, segment) / segmentLengthSquared, 0.0, 1.0)
        : 0.0;
    float2 nearest = previous + segment * projection;
    float aspect = float(history.get_width()) / max(1.0, float(history.get_height()));
    float2 scaledDelta = (input.uv - nearest) * float2(aspect, 1.0);
    float radius = clamp(0.03 / max(scale, 0.15), 0.012, 0.12);
    float falloff = saturate(1.0 - length(scaledDelta) / radius);
    float movement = min(length(segment) * 100.0, 1.0);
    float timeWeight = min(frameDelta * 60.0, 1.5);
    state.y += falloff * falloff * movement * timeWeight * active * 0.7;
    return encodeRippleState(state);
}

float2 rippleStateAt(texture2d<float> state, int2 coordinate) {
    int2 maximum = int2(state.get_width(), state.get_height()) - 1;
    return decodeRippleState(state.read(uint2(clamp(coordinate, int2(0), maximum))));
}

fragment float4 sceneCursorRippleSimulateFrag(
    CursorRippleVaryings input [[stage_in]],
    texture2d<float> stateTexture [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    constant CursorRippleSimulateUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    int2 coordinate = int2(input.position.xy);
    float2 state = rippleStateAt(stateTexture, coordinate);
    float height = state.x;
    float velocity = state.y;
    float laplacian =
        rippleStateAt(stateTexture, coordinate + int2(1, 0)).x
        + rippleStateAt(stateTexture, coordinate + int2(-1, 0)).x
        + rippleStateAt(stateTexture, coordinate + int2(0, 1)).x
        + rippleStateAt(stateTexture, coordinate + int2(0, -1)).x
        - height * 4.0;

    float decay = u.decaySpeedDeltaMasked.x;
    float speed = u.decaySpeedDeltaMasked.y;
    float stepWeight = clamp(u.decaySpeedDeltaMasked.z * 60.0, 0.0, 2.0);
    float propagation = mix(0.08, 0.24, speed);
    velocity += laplacian * propagation * stepWeight;
    velocity *= pow(mix(0.992, 0.91, decay), stepWeight);
    height = clamp(height + velocity * stepWeight, -1.0, 1.0);

    if (u.decaySpeedDeltaMasked.w > 0.5) {
        // Collision masks store painted/blocked pixels as white.
        float mask = maskTexture.sample(
            linearClamp,
            clamp(input.uv * u.maskUVScale, 0.0, 1.0)
        ).r;
        float active = 1.0 - step(0.5, mask);
        height *= active;
        velocity *= active;
    }
    return encodeRippleState(float2(height, velocity));
}

fragment float4 sceneCursorRippleCombineFrag(
    CursorRippleVaryings input [[stage_in]],
    texture2d<float> stateTexture [[texture(0)]],
    texture2d<float> sourceTexture [[texture(1)]],
    constant CursorRippleCombineUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 texel = 1.0 / float2(stateTexture.get_width(), stateTexture.get_height());
    float left = decodeRippleState(
        stateTexture.sample(linearClamp, input.uv - float2(texel.x, 0.0))
    ).x;
    float right = decodeRippleState(
        stateTexture.sample(linearClamp, input.uv + float2(texel.x, 0.0))
    ).x;
    float up = decodeRippleState(
        stateTexture.sample(linearClamp, input.uv - float2(0.0, texel.y))
    ).x;
    float down = decodeRippleState(
        stateTexture.sample(linearClamp, input.uv + float2(0.0, texel.y))
    ).x;
    float2 gradient = float2(right - left, down - up);
    float2 displacedUV = clamp(
        input.uv + gradient * (0.008 + 0.032 * u.strength),
        0.0,
        1.0
    );
    return sourceTexture.sample(linearClamp, displacedUV);
}
"""

struct SceneCursorRipplePipeline {
    private let applyState: MTLRenderPipelineState
    private let simulateState: MTLRenderPipelineState
    private let combineState: MTLRenderPipelineState
    private let deviceRegistryID: UInt64

    init?(device: MTLDevice) {
        let renderStates = SceneCursorRippleExecutionPlan.RenderStates.supported
        guard let library = try? device.makeLibrary(
            source: sceneCursorRippleShaderSource,
            options: MTLCompileOptions()
        ), let vertex = library.makeFunction(name: "sceneCursorRippleVert"),
           let applyState = Self.makeState(
               device: device, library: library, vertex: vertex,
               fragment: "sceneCursorRippleApplyFrag", format: .rgba8Unorm,
               renderState: renderStates.applyForce,
               alphaWriting: .enabled
           ),
           let simulateState = Self.makeState(
               device: device, library: library, vertex: vertex,
               fragment: "sceneCursorRippleSimulateFrag", format: .rgba8Unorm,
               renderState: renderStates.simulateForce,
               alphaWriting: .enabled
           ),
           let combineState = Self.makeState(
               device: device, library: library, vertex: vertex,
               fragment: "sceneCursorRippleCombineFrag", format: .bgra8Unorm,
               renderState: renderStates.combine,
               alphaWriting: .unspecified
           ) else {
            return nil
        }
        self.applyState = applyState
        self.simulateState = simulateState
        self.combineState = combineState
        deviceRegistryID = device.registryID
    }

    func encode(
        history: MTLTexture,
        intermediate: MTLTexture,
        source: MTLTexture,
        output: MTLTexture,
        mask: MTLTexture?,
        maskUVScale: SIMD2<Float>,
        plan: SceneCursorRippleExecutionPlan,
        currentCursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        previousPointerIsInside: Bool,
        frameTime: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard valid(
            history: history, intermediate: intermediate, source: source,
            output: output, mask: mask, maskUVScale: maskUVScale,
            plan: plan, currentCursorUV: currentCursorUV,
            previousCursorUV: previousCursorUV, frameTime: frameTime,
            commandBuffer: commandBuffer
        ) else {
            return false
        }
        let active = pointerIsInside && previousPointerIsInside
        var apply = SceneCursorRippleApplyUniforms(
            currentAndPreviousX: SIMD4(
                currentCursorUV.x, currentCursorUV.y, previousCursorUV.x, 0
            ),
            previousYScaleDeltaActive: SIMD4(
                previousCursorUV.y, plan.rippleScale, min(frameTime, 1 / 30),
                active ? 1 : 0
            )
        )
        guard encode(
            state: applyState, textures: [history], target: intermediate,
            bytes: &apply, commandBuffer: commandBuffer
        ) else {
            return false
        }
        var simulate = SceneCursorRippleSimulateUniforms(
            decaySpeedDeltaMasked: SIMD4(
                plan.decay, plan.speed, min(frameTime, 1 / 30), mask == nil ? 0 : 1
            ),
            maskUVScale: maskUVScale
        )
        guard encode(
            state: simulateState, textures: [intermediate, mask ?? intermediate],
            target: history, bytes: &simulate, commandBuffer: commandBuffer
        ) else {
            return false
        }
        var combine = SceneCursorRippleCombineUniforms(strength: plan.strength)
        return encode(
            state: combineState, textures: [history, source], target: output,
            bytes: &combine, commandBuffer: commandBuffer
        )
    }

    private func valid(
        history: MTLTexture,
        intermediate: MTLTexture,
        source: MTLTexture,
        output: MTLTexture,
        mask: MTLTexture?,
        maskUVScale: SIMD2<Float>,
        plan: SceneCursorRippleExecutionPlan,
        currentCursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>,
        frameTime: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let textures = [history, intermediate, source, output]
        guard plan.renderStates.matchesSupportedTuple,
              [256, 512].contains(plan.simulationResolution),
              (0...2).contains(plan.rippleScale),
              (0...1).contains(plan.decay),
              (0...1).contains(plan.speed),
              (0...1).contains(plan.strength),
              currentCursorUV.x.isFinite, currentCursorUV.y.isFinite,
              previousCursorUV.x.isFinite, previousCursorUV.y.isFinite,
              frameTime.isFinite, frameTime >= 0,
              history.pixelFormat == .rgba8Unorm,
              intermediate.pixelFormat == .rgba8Unorm,
              history.width == intermediate.width,
              history.height == intermediate.height,
              max(history.width, history.height) <= plan.simulationResolution,
              source.pixelFormat == .bgra8Unorm,
              output.pixelFormat == .bgra8Unorm,
              source.width == output.width, source.height == output.height,
              Set(textures.map(ObjectIdentifier.init)).count == textures.count,
              textures.allSatisfy({
                  $0.textureType == .type2D && $0.sampleCount == 1
                      && $0.device.registryID == deviceRegistryID
              }),
              commandBuffer.commandQueue.device.registryID == deviceRegistryID else {
            return false
        }
        guard let mask else { return plan.maskTexturePath == nil }
        return plan.maskTexturePath != nil
            && maskUVScale.x.isFinite && maskUVScale.y.isFinite
            && (0...1).contains(maskUVScale.x) && (0...1).contains(maskUVScale.y)
            && maskUVScale.x > 0 && maskUVScale.y > 0
            && [.r8Unorm, .rgba8Unorm, .bgra8Unorm].contains(mask.pixelFormat)
            && mask.textureType == .type2D && mask.sampleCount == 1
            && mask.usage.contains(.shaderRead)
            && mask.device.registryID == deviceRegistryID
    }

    private func encode<T>(
        state: MTLRenderPipelineState,
        textures: [MTLTexture],
        target: MTLTexture,
        bytes: inout T,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.setRenderPipelineState(state)
        encoder.setCullMode(.none)
        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        withUnsafeBytes(of: &bytes) {
            encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        return true
    }

    private static func makeState(
        device: MTLDevice,
        library: MTLLibrary,
        vertex: MTLFunction,
        fragment name: String,
        format: MTLPixelFormat,
        renderState: SceneMaterialRenderState,
        alphaWriting: SceneMaterialRenderState.AlphaWriting
    ) -> MTLRenderPipelineState? {
        guard renderState.matchesFullscreenOverwrite(alphaWriting: alphaWriting),
              let fragment = library.makeFunction(name: name) else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = format
        attachment.isBlendingEnabled = false
        attachment.writeMask = .all
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}
