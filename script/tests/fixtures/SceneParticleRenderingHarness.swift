@main
enum Harness {
    static func main() throws {
        let sequence = SceneParticleSpriteFrameSelector.select(
            mode: .sequence, frameDurations: [1, 1, 2],
            age: 3.75, lifetime: 10, sequenceMultiplier: 2,
            particleID: 7, blendsFrames: true
        )!
        let noBlend = SceneParticleSpriteFrameSelector.select(
            mode: .sequence, frameDurations: [1, 1, 2],
            age: 3.75, lifetime: 10, sequenceMultiplier: 2,
            particleID: 7, blendsFrames: false
        )!
        let prepared = SceneParticleSpriteFrameSelector.select(
            mode: .sequence, frameDurations: [1, 1, 2],
            frameEndTimes: [1, 2, 4], totalDuration: 4,
            age: 3.75, lifetime: 10, sequenceMultiplier: 2,
            particleID: 7, blendsFrames: true
        )!
        let reverse = SceneParticleSpriteFrameSelector.select(
            mode: .sequence, frameDurations: [1, 1, 2],
            age: 2.5, lifetime: 10, sequenceMultiplier: -1,
            particleID: 7, blendsFrames: true
        )!
        let random = (0..<16).map { id in
            SceneParticleSpriteFrameSelector.select(
                mode: .randomFrame, frameDurations: [1, 1, 1, 1],
                age: 9, lifetime: 10, sequenceMultiplier: 4,
                particleID: UInt64(id), blendsFrames: true
            )!
        }
        let finiteExtremesAreSafe = [false, true].allSatisfy { prepared in
            let sample = SceneParticleSpriteFrameSelector.select(
                mode: .sequence, frameDurations: [1, 1, 2],
                frameEndTimes: prepared ? [1, 2, 4] : nil,
                totalDuration: prepared ? 4 : nil,
                age: .greatestFiniteMagnitude, lifetime: .leastNonzeroMagnitude,
                sequenceMultiplier: .greatestFiniteMagnitude,
                particleID: 7, blendsFrames: true
            )
            return sample?.currentIndex == 0 && sample?.mix == 0
        }
        let invalidPhasesRejected = [Float.nan, .infinity, -.infinity].allSatisfy { value in
            [(value, Float(1), Float(1)), (Float(1), value, Float(1)),
             (Float(1), Float(1), value)].allSatisfy { age, lifetime, multiplier in
                SceneParticleSpriteFrameSelector.select(
                    mode: .sequence, frameDurations: [1, 1, 2],
                    age: age, lifetime: lifetime, sequenceMultiplier: multiplier,
                    particleID: 7, blendsFrames: true
                ) == nil
            }
        }

        let screen = SceneParticleOrientation.screen.basis(
            cameraRight: SIMD3(2, 0, 0), cameraUp: SIMD3(1, 3, 0),
            cameraForward: SIMD3(0, 0, -1)
        )
        let upright = SceneParticleOrientation.upright.basis(
            cameraRight: SIMD3(1, 0, 0), cameraUp: SIMD3(0, 1, 0),
            cameraForward: SIMD3(0, 0, -1)
        )
        let fixed = SceneParticleOrientation.fixed.basis(
            cameraRight: SIMD3(1, 0, 0), cameraUp: SIMD3(0, 1, 0),
            cameraForward: SIMD3(0, 0, -1),
            fixedRight: SIMD3(0, 1, 0), fixedUp: SIMD3(0, 0, 1)
        )
        let rotatedLayer = SceneMatrix.rotationZ(.pi / 2)
            * SceneMatrix.scale(SIMD3<Float>(2, 3, 1))
        let localFixedVectors = SceneParticleOrientation.fixed.fixedBasisVectors(
            axis: SIMD3(0, 0, 1),
            layerModel: rotatedLayer
        )
        let worldFixedVectors = SceneParticleOrientation.worldFixed.fixedBasisVectors(
            axis: SIMD3(0, 0, 1),
            layerModel: rotatedLayer
        )

        let translucent = SceneParticleMetalPipeline.blendConfiguration(for: .translucent)
        let additive = SceneParticleMetalPipeline.blendConfiguration(for: .additive)
        var result: [String: Any] = [
            "instanceStride": MemoryLayout<SceneParticleGPUInstance>.stride,
            "instanceAlignment": MemoryLayout<SceneParticleGPUInstance>.alignment,
            "instanceOffsets": instanceOffsets(),
            "fixedGeometry": try SceneParticleFixedGeometryHarness.run(),
            "rasterGeometry": try SceneParticleFixedGeometryHarness.rasterProfiles(),
            "uniformStride": MemoryLayout<SceneParticleLayerUniforms>.stride,
            "uniformOffsets": uniformOffsets(),
            "sequence": selection(sequence),
            "finiteExtremesAreSafe": finiteExtremesAreSafe,
            "invalidPhasesRejected": invalidPhasesRejected,
            "preparedTimeline": selection(prepared),
            "noBlend": selection(noBlend),
            "reverse": selection(reverse),
            "randomIndices": random.map(\.currentIndex),
            "randomNoBlend": random.allSatisfy { $0.currentIndex == $0.nextIndex && $0.mix == 0 },
            "modeSequence": SceneParticleSpriteAnimationMode(authoredValue: "Sequence") == .sequence,
            "modeRandom": SceneParticleSpriteAnimationMode(authoredValue: "randomframe") == .randomFrame,
            "orientationDefault": SceneParticleOrientation(authoredValue: nil) == .screen,
            "trailFrame": frame(
                SceneParticleFrameTransform.identity.orientedForTrail(true)
            ),
            "screenRight": vector(screen.right),
            "screenUp": vector(screen.up),
            "uprightRight": vector(upright.right),
            "uprightUp": vector(upright.up),
            "fixedRight": vector(fixed.right),
            "fixedUp": vector(fixed.up),
            "localFixedRight": vector(localFixedVectors.right),
            "worldFixedRight": vector(worldFixedVectors.right),
            "worldFixedUp": vector(worldFixedVectors.up),
            "translucentBlend": [
                translucent.sourceRGB == .one,
                translucent.destinationRGB == .oneMinusSourceAlpha,
                translucent.sourceAlpha == .one,
                translucent.destinationAlpha == .oneMinusSourceAlpha,
            ],
            // 官方 genericparticle 上传 straight RGB/alpha 并以 SRC_ALPHA, ONE
            // 合成。当前 Metal 主链在 shader 边界已经 premultiply，所以等价
            // 合同是 ONE, ONE；不能再次乘 sourceAlpha 形成 alpha²。
            "additiveBlend": [
                additive.sourceRGB == .one,
                additive.destinationRGB == .one,
                additive.sourceAlpha == .one,
                additive.destinationAlpha == .oneMinusSourceAlpha,
            ],
            "additiveFractionalAlphaPixel": additiveFractionalAlphaPixel(),
            "metalDraw": renderSmokeTest(),
            "uprightGeometry": uprightGeometryContract(),
            "spriteAspectBounds": spriteBounds(
                currentAspect: 2, nextAspect: 2, frameMix: 0
            ),
            "blendedSpriteAspectBounds": spriteBounds(
                currentAspect: 0.5, nextAspect: 2, frameMix: 0.5
            ),
            "squareSpriteBounds": spriteBounds(currentAspect: 1, nextAspect: 1, frameMix: 0),
            "clockwiseSpriteMarkers": spriteBounds(currentAspect: 0.25, nextAspect: 0.25,
                frameMix: 0, rotation: SIMD3(0, 0, Float.pi / 2), marked: true),
            "counterclockwiseSpriteMarkers": spriteBounds(currentAspect: 0.25, nextAspect: 0.25,
                frameMix: 0, rotation: SIMD3(0, 0, -Float.pi / 2), marked: true),
            "mixedAxisSpriteMarkers": spriteBounds(currentAspect: 0.25, nextAspect: 0.25,
                frameMix: 0, rotation: SIMD3(0.2, -0.4, 0.7), marked: true),
            "orientedSpriteMarkers": spriteBounds(currentAspect: 0.25, nextAspect: 0.25,
                frameMix: 0, rotation: SIMD3(0, 0, Float.pi / 2), marked: true,
                basis: .init(right: SIMD3(0, 1, 0), up: SIMD3(-1, 0, 0))),
            "tallSpriteBounds": spriteBounds(currentAspect: 0.25, nextAspect: 0.25, frameMix: 0),
            "rotatedTallSpriteBounds": spriteBounds(
                currentAspect: 0.25, nextAspect: 0.25, frameMix: 0,
                rotation: SIMD3(0, 0, Float.pi / 2)
            ),
            "scaledTallSpriteBounds": spriteBounds(
                currentAspect: 0.25, nextAspect: 0.25, frameMix: 0,
                layerModel: SceneMatrix.scale(SIMD3(-2, 0.5, 1))
            ),
            "horizontalTrailBounds": trailBounds(velocity: SIMD3(1, 0, 0)),
            "numericRotationBounds": authoredRotationBounds(0.3),
            "textRotationBounds": authoredRotationBounds("0.3"),
            "explicitZRotationBounds": authoredRotationBounds("0 0 0.3"),
            "explicitXRotationBounds": authoredRotationBounds("0.3 0 0"),
            "broadcastRotationBounds": authoredRotationBounds("0.3 0.3 0.3"),
            "defaultTrailBounds": defaultTrailBounds(),
            "trailAspectBounds": [
                "square": trailBounds(velocity: SIMD3(1, 0, 0), stretch: 2),
                "tall": trailBounds(velocity: SIMD3(1, 0, 0), stretch: 2, currentAspect: 0.25),
                "wide": trailBounds(velocity: SIMD3(1, 0, 0), stretch: 2, currentAspect: 4),
                "blended": trailBounds(velocity: SIMD3(1, 0, 0), stretch: 2,
                    currentAspect: 0.25, nextAspect: 0.75, frameMix: 0.5),
                "minimum": trailBounds(velocity: SIMD3(1, 0, 0), stretch:
                    SceneParticleTrailRenderPlan(length: 0.01, minimumLength: 2, maximumLength: 3)!
                        .stretch(for: SIMD3(0.0, 0, 0)), currentAspect: 0.25),
                "maximum": trailBounds(velocity: SIMD3(1, 0, 0), stretch:
                    SceneParticleTrailRenderPlan(length: 0.01, minimumLength: 2, maximumLength: 3)!
                        .stretch(for: SIMD3(10000.0, 0, 0)), currentAspect: 0.25),
                "displacementSquare": trailBounds(velocity: SIMD3(1, 0, 0), rope: true),
                "displacementTall": trailBounds(velocity: SIMD3(1, 0, 0), rope: true, currentAspect: 0.25),
            ],
            "localScaledWidth": trailBounds(velocity: SIMD3(1, 0, 0),
                layerModel: SceneMatrix.scale(SIMD3(10, 10, 1)), rope: true),
            "worldScaledWidth": trailBounds(velocity: SIMD3(1, 0, 0),
                layerModel: SceneMatrix.scale(SIMD3(10, 10, 1)), rope: true, sizeIsWorldSpace: true),
            "worldIdentityWidth": trailBounds(velocity: SIMD3(1, 0, 0), rope: true, sizeIsWorldSpace: true),
            "worldMirroredWidth": trailBounds(velocity: SIMD3(1, 0, 0),
                layerModel: SceneMatrix.scale(SIMD3(-10, 3, 1)), rope: true, sizeIsWorldSpace: true),
            "worldSizeOverrideWidth": trailBounds(velocity: SIMD3(1, 0, 0),
                layerModel: SceneMatrix.scale(SIMD3(10, 10, 1)), rope: true, sizeIsWorldSpace: true, particleSize: 0.8),
            "verticalTrailBounds": trailBounds(velocity: SIMD3(0, 1, 0)),
            "rotatedTrailBounds": trailBounds(
                velocity: SIMD3(1, 0, 0),
                layerModel: simd_float4x4(columns: (
                    SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
                    SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
                ))
            ),
            "ropeTrailRender": ropeTrailRenderContract(),
            "ropeTrailJoins": ropeTrailJoinContract(),
            "ropeJoins": ropeTrailJoinContract(connectParticles: true),
            "ropeTrailTransform": ropeTrailTransformContract(),
            "ropeTrailAspect": ropeTrailAspectContract(),
            "instanceBufferSlots": instanceBufferSlotTest(),
            "instanceBufferPendingCancellation": instanceBufferPendingCancellationTest(),
            "topologyRetirement": topologyRetirementTest(),
            "colorContract": colorContractTest(),
            "straightInterpolation": straightInterpolationTest(),
            "sequenceEndPixels": sequenceEndPixels(),
            "refractionContract": refractionContractTest(),
            "refractionBasisCases": refractionBasisCases(),
            "refractionTrailBasisCases": refractionTrailBasisCases(),
            "rasterRefraction": rasterRefractionCases(),
            "rasterDepth": rasterDepthCases(),
            "texSampling": [
                "default": sampling(.directImageFallback),
                "flags0": sampling(SceneParticleTextureSampling(texFlags: 0)),
                "flags1": sampling(SceneParticleTextureSampling(texFlags: 1)),
                "flags2": sampling(SceneParticleTextureSampling(texFlags: 2)),
                "flags3": sampling(SceneParticleTextureSampling(texFlags: 3)),
                "flags4": sampling(SceneParticleTextureSampling(texFlags: 4)),
                "flags8": sampling(SceneParticleTextureSampling(texFlags: 8)),
                "alphaPriority": sampling(
                    SceneParticleTextureSampling(texFlags: 524_288)
                ),
            ],
            "samplerPixels": samplerPixels(),
            "mipSamplerPixels": mipSamplerPixels(),
        ]
        result.merge(SceneParticleCameraRenderingHarness.run()) { _, current in current }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func instanceOffsets() -> [Int] {
        [
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.positionAndSize),
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.rotationAndAlpha),
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.colorAndFrameMix),
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.frame0A),
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.frame0B),
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.frame1A),
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.frame1B),
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.velocityAndTrail),
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.trailHeadJoin),
            MemoryLayout<SceneParticleGPUInstance>.offset(of: \.trailTailJoin),
        ].compactMap { $0 }
    }

    private static func frame(_ value: SceneParticleFrameTransform) -> [Float] {
        [
            value.origin.x, value.origin.y,
            value.xAxis.x, value.xAxis.y,
            value.yAxis.x, value.yAxis.y,
        ]
    }

    private static func uniformOffsets() -> [Int] {
        [
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.viewProjection),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.layerModel),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.basisRight),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.basisUp),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.viewportSize),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.particleSizeScale),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.viewRight),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.viewUp),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.spriteRight),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.spriteUp),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.spriteForward), MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.trailLocalNormal),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.rasterClipX),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.rasterClipY),
        ].compactMap { $0 }
    }

    private static func selection(_ value: SceneParticleSpriteFrameSelection) -> [String: Any] {
        ["current": value.currentIndex, "next": value.nextIndex, "mix": value.mix]
    }

    private static func vector(_ value: SIMD3<Float>) -> [Float] {
        [value.x, value.y, value.z]
    }

    private static func sampling(
        _ value: SceneParticleTextureSampling
    ) -> [String: Any] {
        [
            "filter": value.filter.rawValue,
            "address": value.addressMode.rawValue,
            "clampBorderFallback": value.usesClampBorderFallback,
        ]
    }

    private static func particleState(
        _ blendMode: SceneParticlePipelineBlendMode,
        cullMode: SceneParticlePipelineCullMode = .none
    ) -> SceneParticlePipelineRenderState {
        SceneParticlePipelineRenderState(
            blendMode: blendMode,
            cullMode: cullMode
        )
    }
}
