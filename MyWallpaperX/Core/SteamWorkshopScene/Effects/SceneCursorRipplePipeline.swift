import Foundation
import Metal
import simd

private struct SceneCursorRippleApplyUniforms {
    var currentAndPreviousX: SIMD4<Float>
    var previousYScaleDeltaActive: SIMD4<Float>
    var movementPressed: SIMD2<Float>
    var padding: SIMD2<Float> = .zero
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
    float2 movementPressed;
    float2 padding;
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

fragment float4 sceneCursorRippleApplyFrag(
    CursorRippleVaryings input [[stage_in]],
    texture2d<float> history [[texture(0)]],
    constant CursorRippleApplyUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float4 state = history.sample(linearClamp, input.uv);
    float2 current = u.currentAndPreviousX.xy;
    float2 previous = float2(
        u.currentAndPreviousX.z,
        u.previousYScaleDeltaActive.x
    );
    float scale = max(0.0001, u.previousYScaleDeltaActive.y);
    float frameDelta = u.previousYScaleDeltaActive.z;
    float active = u.previousYScaleDeltaActive.w;

    float2 line = current - previous;
    float lineLength = length(line) + 0.0001;
    float2 lineDirection = line / lineLength;
    float distanceOnLine = dot(lineDirection, input.uv - previous);
    float rayMask = (
        (distanceOnLine >= 0.0 && distanceOnLine <= lineLength)
        || lineLength <= 0.1
    ) ? 1.0 : 0.0;
    distanceOnLine = saturate(distanceOnLine / lineLength) * lineLength;
    float2 nearest = previous + lineDirection * distanceOnLine;
    float simulationScale = 60.0 / scale;
    float aspect = float(history.get_height())
        / max(1.0, float(history.get_width()));
    float2 impulse = (input.uv - nearest)
        * float2(simulationScale, simulationScale * aspect);
    float pointerDistance = saturate(1.0 - length(impulse)) * rayMask;
    float timeAmount = frameDelta / 0.02;
    float inputStrength = pointerDistance * timeAmount
        * (u.currentAndPreviousX.w * 100.0 + u.movementPressed.y * 5.0)
        * active;
    float2 direction = clamp(impulse, -1.0, 1.0);
    float4 added = float4(
        max(direction.x, 0.0) * inputStrength,
        max(direction.y, 0.0) * inputStrength,
        max(-direction.x, 0.0) * inputStrength,
        max(-direction.y, 0.0) * inputStrength
    );
    return state + added;
}

fragment float4 sceneCursorRippleSimulateFrag(
    CursorRippleVaryings input [[stage_in]],
    texture2d<float> stateTexture [[texture(0)]],
    texture2d<float> maskTexture [[texture(1)]],
    constant CursorRippleSimulateUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float decay = u.decaySpeedDeltaMasked.x;
    float speed = u.decaySpeedDeltaMasked.y;
    float frameDelta = u.decaySpeedDeltaMasked.z;
    float2 texel = 1.0 / float2(
        stateTexture.get_width(), stateTexture.get_height()
    );
    float2 outsideOffset = texel * 100.0 * speed * frameDelta;
    float2 insideOffset = outsideOffset * 1.61;
    float2 uv = input.uv;

    float4 up = max(
        stateTexture.sample(linearClamp, uv + float2(0.0, -insideOffset.y)),
        max(
            stateTexture.sample(linearClamp, uv - outsideOffset),
            stateTexture.sample(
                linearClamp, uv + float2(outsideOffset.x, -outsideOffset.y)
            )
        )
    );
    float4 down = max(
        stateTexture.sample(linearClamp, uv + float2(0.0, insideOffset.y)),
        max(
            stateTexture.sample(
                linearClamp, uv + float2(-outsideOffset.x, outsideOffset.y)
            ),
            stateTexture.sample(linearClamp, uv + outsideOffset)
        )
    );
    float4 left = max(
        stateTexture.sample(linearClamp, uv + float2(-insideOffset.x, 0.0)),
        max(
            stateTexture.sample(linearClamp, uv - outsideOffset),
            stateTexture.sample(
                linearClamp, uv + float2(-outsideOffset.x, outsideOffset.y)
            )
        )
    );
    float4 right = max(
        stateTexture.sample(linearClamp, uv + float2(insideOffset.x, 0.0)),
        max(
            stateTexture.sample(
                linearClamp, uv + float2(outsideOffset.x, -outsideOffset.y)
            ),
            stateTexture.sample(linearClamp, uv + outsideOffset)
        )
    );

    float4 force = float4(
        up.x + down.x + left.x,
        up.y + left.y + right.y,
        up.z + down.z + right.z,
        down.w + left.w + right.w
    ) / 3.0;

    float reflectUp = step(1.0 - texel.y, uv.y);
    float reflectDown = step(uv.y, texel.y);
    float reflectLeft = step(1.0 - texel.x, uv.x);
    float reflectRight = step(uv.x, texel.x);
    float activeMask = 1.0;
    if (u.decaySpeedDeltaMasked.w > 0.5) {
        float2 maskUV = clamp(uv * u.maskUVScale, 0.0, 1.0);
        activeMask = 1.0 - step(
            0.5, maskTexture.sample(linearClamp, maskUV).r
        );
        float2 maskOffset = insideOffset * u.maskUVScale;
        float maskUp = maskTexture.sample(
            linearClamp, clamp(maskUV + float2(0.0, -maskOffset.y), 0.0, 1.0)
        ).r * activeMask;
        float maskDown = maskTexture.sample(
            linearClamp, clamp(maskUV + float2(0.0, maskOffset.y), 0.0, 1.0)
        ).r * activeMask;
        float maskLeft = maskTexture.sample(
            linearClamp, clamp(maskUV + float2(-maskOffset.x, 0.0), 0.0, 1.0)
        ).r * activeMask;
        float maskRight = maskTexture.sample(
            linearClamp, clamp(maskUV + float2(maskOffset.x, 0.0), 0.0, 1.0)
        ).r * activeMask;
        reflectDown = step(0.5, reflectDown + maskUp);
        reflectUp = step(0.5, reflectUp + maskDown);
        reflectRight = step(0.5, reflectRight + maskLeft);
        reflectLeft = step(0.5, reflectLeft + maskRight);
    }

    float4 unreflected = force;
    force.y = mix(force.y, unreflected.w, reflectDown);
    force.w = mix(force.w, unreflected.y, reflectUp);
    force.x = mix(force.x, unreflected.z, reflectRight);
    force.z = mix(force.z, unreflected.x, reflectLeft);
    float drop = max(
        1.001 / 255.0,
        1.5 / 255.0 * (frameDelta / 0.02) * decay
    );
    return (force - drop) * activeMask;
}

fragment float4 sceneCursorRippleCombineFrag(
    CursorRippleVaryings input [[stage_in]],
    texture2d<float> stateTexture [[texture(0)]],
    texture2d<float> sourceTexture [[texture(1)]],
    constant CursorRippleCombineUniforms &u [[buffer(0)]]
) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float4 state = stateTexture.sample(linearClamp, input.uv);
    state *= state;
    float2 direction = float2(state.r - state.b, state.g - state.a);
    float2 displacedUV = clamp(
        input.uv - direction * (0.1 * u.strength),
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
#if DEBUG
    private let visibleOutputEvidence: SceneCursorRippleVisibleOutputEvidence?
#endif

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
#if DEBUG
        visibleOutputEvidence = SceneCursorRippleVisibleOutputEvidence(device: device)
#endif
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
        pointerMovement: Float,
        primaryButtonIsDown: Bool,
        frameTime: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let validationFailure = validationFailure(
            history: history, intermediate: intermediate, source: source,
            output: output, mask: mask, maskUVScale: maskUVScale,
            plan: plan, currentCursorUV: currentCursorUV,
            previousCursorUV: previousCursorUV,
            pointerMovement: pointerMovement, frameTime: frameTime,
            commandBuffer: commandBuffer
        ) else { return encodeValidated(
            history: history,
            intermediate: intermediate,
            source: source,
            output: output,
            mask: mask,
            maskUVScale: maskUVScale,
            plan: plan,
            currentCursorUV: currentCursorUV,
            previousCursorUV: previousCursorUV,
            pointerIsInside: pointerIsInside,
            previousPointerIsInside: previousPointerIsInside,
            pointerMovement: pointerMovement,
            primaryButtonIsDown: primaryButtonIsDown,
            frameTime: frameTime,
            commandBuffer: commandBuffer
        ) }
        NSLog(
            "MWX DEBUG SCENE: phase=cursor-ripple-encode failure=%@",
            validationFailure
        )
        return false
    }

    private func encodeValidated(
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
        pointerMovement: Float,
        primaryButtonIsDown: Bool,
        frameTime: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let active = pointerIsInside && previousPointerIsInside
        var apply = SceneCursorRippleApplyUniforms(
            currentAndPreviousX: SIMD4(
                currentCursorUV.x, currentCursorUV.y,
                previousCursorUV.x, pointerMovement
            ),
            previousYScaleDeltaActive: SIMD4(
                previousCursorUV.y, plan.rippleScale, frameTime,
                active ? 1 : 0
            ),
            movementPressed: SIMD2(pointerMovement, primaryButtonIsDown ? 1 : 0)
        )
        guard encode(
            state: applyState, textures: [history], target: intermediate,
            bytes: &apply, commandBuffer: commandBuffer
        ) else {
            return false
        }
        var simulate = SceneCursorRippleSimulateUniforms(
            decaySpeedDeltaMasked: SIMD4(
                plan.decay, plan.speed, frameTime, mask == nil ? 0 : 1
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
        let combined = encode(
            state: combineState, textures: [history, source], target: output,
            bytes: &combine, commandBuffer: commandBuffer
        )
#if DEBUG
        if combined {
            visibleOutputEvidence?.encode(
                source: source,
                output: output,
                plan: plan,
                currentCursorUV: currentCursorUV,
                previousCursorUV: previousCursorUV,
                pointerIsInside: pointerIsInside,
                previousPointerIsInside: previousPointerIsInside,
                pointerMovement: pointerMovement,
                commandBuffer: commandBuffer
            )
            encodeDebugEvidence(
                texture: history,
                plan: plan,
                currentCursorUV: currentCursorUV,
                previousCursorUV: previousCursorUV,
                pointerIsInside: pointerIsInside,
                previousPointerIsInside: previousPointerIsInside,
                pointerMovement: pointerMovement,
                hasMask: mask != nil,
                frameTime: frameTime,
                commandBuffer: commandBuffer
            )
        }
#endif
        return combined
    }

#if DEBUG
    private func encodeDebugEvidence(
        texture: MTLTexture,
        plan: SceneCursorRippleExecutionPlan,
        currentCursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>,
        pointerIsInside: Bool,
        previousPointerIsInside: Bool,
        pointerMovement: Float,
        hasMask: Bool,
        frameTime: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        guard Self.debugEvidenceEnabled else { return }
        let unalignedBytesPerRow = texture.width * 4
        let bytesPerRow = (unalignedBytesPerRow + 255) & ~255
        let byteCount = bytesPerRow * texture.height
        guard byteCount > 0,
              let readback = texture.device.makeBuffer(
                  length: byteCount,
                  options: .storageModeShared
              ), let blit = commandBuffer.makeBlitCommandEncoder() else {
            NSLog(
                "MWX DEBUG SCENE: phase=cursor-ripple-state layer=%d effect=%d descriptor=%@ status=readback-unavailable",
                plan.layerID,
                plan.effectKey.effectIndex,
                plan.effectKey.descriptorID
            )
            return
        }
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(
                width: texture.width,
                height: texture.height,
                depth: 1
            ),
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: byteCount
        )
        blit.endEncoding()
        let width = texture.width
        let height = texture.height
        let outputIdentity = String(describing: ObjectIdentifier(texture))
        commandBuffer.addCompletedHandler { buffer in
            guard buffer.status == .completed else {
                NSLog(
                    "MWX DEBUG SCENE: phase=cursor-ripple-state layer=%d effect=%d descriptor=%@ status=gpu-%ld",
                    plan.layerID,
                    plan.effectKey.effectIndex,
                    plan.effectKey.descriptorID,
                    buffer.status.rawValue
                )
                return
            }
            let bytes = readback.contents().assumingMemoryBound(to: UInt8.self)
            var minimumX = width
            var minimumY = height
            var maximumX = -1
            var maximumY = -1
            var activePixels = 0
            var maximumChannel = 0
            var channelSum: UInt64 = 0
            for y in 0 ..< height {
                let row = bytes.advanced(by: y * bytesPerRow)
                for x in 0 ..< width {
                    let pixel = row.advanced(by: x * 4)
                    var active = false
                    for channel in 0 ..< 4 {
                        let value = Int(pixel[channel])
                        active = active || value > 0
                        maximumChannel = max(maximumChannel, value)
                        channelSum += UInt64(value)
                    }
                    if active {
                        activePixels += 1
                        minimumX = min(minimumX, x)
                        minimumY = min(minimumY, y)
                        maximumX = max(maximumX, x)
                        maximumY = max(maximumY, y)
                    }
                }
            }
            NSLog(
                "MWX DEBUG SCENE: phase=cursor-ripple-state layer=%d effect=%d descriptor=%@ status=completed width=%d height=%d output=%@ activePixels=%d bounds=%d,%d,%d,%d max=%d sum=%llu current=%.6f,%.6f previous=%.6f,%.6f inside=%@ previousInside=%@ movement=%.6f mask=%@ frameTime=%.6f decay=%.6f speed=%.6f scale=%.6f strength=%.6f",
                plan.layerID,
                plan.effectKey.effectIndex,
                plan.effectKey.descriptorID,
                width,
                height,
                outputIdentity,
                activePixels,
                minimumX,
                minimumY,
                maximumX,
                maximumY,
                maximumChannel,
                channelSum,
                currentCursorUV.x,
                currentCursorUV.y,
                previousCursorUV.x,
                previousCursorUV.y,
                pointerIsInside ? "true" : "false",
                previousPointerIsInside ? "true" : "false",
                pointerMovement,
                hasMask ? "true" : "false",
                frameTime,
                plan.decay,
                plan.speed,
                plan.rippleScale,
                plan.strength
            )
        }
    }

    private static let debugEvidenceEnabled =
        ProcessInfo.processInfo.environment[
            "MYWALLPAPERX_SCENE_DEBUG_CURSOR_RIPPLE_EVIDENCE"
        ] == "1"
#endif

    private func validationFailure(
        history: MTLTexture,
        intermediate: MTLTexture,
        source: MTLTexture,
        output: MTLTexture,
        mask: MTLTexture?,
        maskUVScale: SIMD2<Float>,
        plan: SceneCursorRippleExecutionPlan,
        currentCursorUV: SIMD2<Float>,
        previousCursorUV: SIMD2<Float>,
        pointerMovement: Float,
        frameTime: Float,
        commandBuffer: MTLCommandBuffer
    ) -> String? {
        let textures = [history, intermediate, source, output]
        guard plan.renderStates.matchesSupportedTuple,
              [256, 512].contains(plan.simulationResolution),
              (0...2).contains(plan.rippleScale),
              (0...4).contains(plan.decay),
              (0...2).contains(plan.speed),
              (0...5).contains(plan.strength),
              currentCursorUV.x.isFinite, currentCursorUV.y.isFinite,
              previousCursorUV.x.isFinite, previousCursorUV.y.isFinite,
              pointerMovement.isFinite, pointerMovement >= 0,
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
            if !plan.renderStates.matchesSupportedTuple {
                return "render-state"
            }
            if ![256, 512].contains(plan.simulationResolution)
                || !(0...2).contains(plan.rippleScale)
                || !(0...4).contains(plan.decay)
                || !(0...2).contains(plan.speed)
                || !(0...5).contains(plan.strength) {
                return "plan-values"
            }
            if !currentCursorUV.x.isFinite || !currentCursorUV.y.isFinite
                || !previousCursorUV.x.isFinite || !previousCursorUV.y.isFinite
                || !pointerMovement.isFinite || pointerMovement < 0
                || !frameTime.isFinite || frameTime < 0 {
                return "frame-input"
            }
            if history.pixelFormat != .rgba8Unorm
                || intermediate.pixelFormat != .rgba8Unorm
                || history.width != intermediate.width
                || history.height != intermediate.height
                || max(history.width, history.height) > plan.simulationResolution {
                return "history-target"
            }
            if source.pixelFormat != .bgra8Unorm
                || output.pixelFormat != .bgra8Unorm
                || source.width != output.width || source.height != output.height {
                return "full-frame-target"
            }
            if Set(textures.map(ObjectIdentifier.init)).count != textures.count {
                return "texture-alias"
            }
            if !textures.allSatisfy({
                $0.textureType == .type2D && $0.sampleCount == 1
                    && $0.device.registryID == deviceRegistryID
            }) {
                return "texture-device"
            }
            return "command-buffer-device"
        }
        guard let mask else {
            return plan.maskTexturePath == nil ? nil : "mask-missing"
        }
        return plan.maskTexturePath != nil
            && maskUVScale.x.isFinite && maskUVScale.y.isFinite
            && (0...1).contains(maskUVScale.x) && (0...1).contains(maskUVScale.y)
            && maskUVScale.x > 0 && maskUVScale.y > 0
            && [.r8Unorm, .rgba8Unorm, .bgra8Unorm].contains(mask.pixelFormat)
            && mask.textureType == .type2D && mask.sampleCount == 1
            && mask.usage.contains(.shaderRead)
            && mask.device.registryID == deviceRegistryID ? nil : "mask-contract"
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
