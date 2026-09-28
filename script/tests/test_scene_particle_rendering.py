#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    REPOSITORY_ROOT / "script/tests/fixtures/SceneParticleFixedGeometryHarness.swift",
    SOURCE_ROOT / "Systems/Input/SceneCameraProjection.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleCameraFrame.swift",
    SOURCE_ROOT / "Systems/Particles/SceneParticleTrailRenderPlan.swift",

    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/ScenePerformanceCounterHub.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Diagnostics/SceneGPUCensus.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureSampling.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureUVTransform.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureCandidate.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneMatrix.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneFramebufferSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleInitializer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleAudioResponsePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleVortex.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRemapValue.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleReduceMovement.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCollisionPlane.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePositionAroundControlPoint.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleDefinitionParser+Operator.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleRenderSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleBoids.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationSupport.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleSimulationDiagnostic.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleCapVelocity.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleControlPointForce.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticlePeriodicEmission.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleStepSnapshotRecorder.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopeTrailPlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRopePlan.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalInstanceBuffer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleRefractionBinding.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleShaderSource.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleSamplerStateSet.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleMetalPipeline.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Particles/SceneParticleDepthTargetPool.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Particles/SceneParticleTextureSource.swift",
]


HARNESS_SOURCE = r'''
import Foundation
import Dispatch
import Metal
import simd

enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor
    case straightAlbedo
    case preservedChannels
    case mask
    case noise
    case flow
    case phase
    case normal
    case depth
    case lookupTable

    var requiresVolumeTexture: Bool {
        self == .lookupTable
    }
}

struct SceneRenderDescriptor {
    struct Layer {
        let utilityLayer: Bool?
        let usesPerspective: Bool?
    }

    struct CameraDescriptor {
        let eye: [Float]
        let center: [Float]
        let up: [Float]
        let orthoWidth: Float?
        let orthoHeight: Float?
        let fovDegrees: Float?
        let perspectiveOverrideFOVDegrees: Float?
        let nearZ: Float
        let farZ: Float
    }
}

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

        let width: Float = 1280
        let height: Float = 832
        let distance: Float = 1000
        let eye = SIMD3(width / 2, height / 2, distance)
        let view = SceneMatrix.lookAt(
            eye: eye, center: SIMD3(width / 2, height / 2, 0), up: SIMD3(0, 1, 0)
        )
        let fov = 2 * atan(height / (2 * distance))
        let projection = SceneMatrix.perspectiveRHMetal(
            fovYRadians: fov, aspect: width / height, near: 0.1, far: 5000
        )
        let viewProjection = projection * view

        let translucent = SceneParticleMetalPipeline.blendConfiguration(for: .translucent)
        let additive = SceneParticleMetalPipeline.blendConfiguration(for: .additive)
        let result: [String: Any] = [
            "instanceStride": MemoryLayout<SceneParticleGPUInstance>.stride,
            "instanceAlignment": MemoryLayout<SceneParticleGPUInstance>.alignment,
            "instanceOffsets": instanceOffsets(),
            "fixedGeometry": try SceneParticleFixedGeometryHarness.run(),
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
            "nearNDC": ndc(projection, SIMD4(0, 0, -0.1, 1)),
            "farNDC": ndc(projection, SIMD4(0, 0, -5000, 1)),
            "sceneCenterNDC": ndc(viewProjection, SIMD4(width / 2, height / 2, 0, 1)),
            "sceneTopRightNDC": ndc(viewProjection, SIMD4(width, height, 0, 1)),
            "invalidPerspectiveIsIdentity": SceneMatrix.perspectiveRHMetal(
                fovYRadians: 0, aspect: 0, near: -1, far: 0
            ) == SceneMatrix.identity(),
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
            "depthAndOverbrightPixel": depthAndOverbrightPixel(),
            "depthTargetLease": depthTargetLeaseContract(),
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
            "cullContract": cullContract(),
            "horizontalTrailBounds": trailBounds(velocity: SIMD3(1, 0, 0)),
            "numericRotationBounds": authoredRotationBounds(0.3),
            "textRotationBounds": authoredRotationBounds("0.3"),
            "explicitZRotationBounds": authoredRotationBounds("0 0 0.3"),
            "explicitXRotationBounds": authoredRotationBounds("0.3 0 0"),
            "broadcastRotationBounds": authoredRotationBounds("0.3 0.3 0.3"),
            "defaultTrailBounds": defaultTrailBounds(),
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
            "colorContract": colorContractTest(),
            "straightInterpolation": straightInterpolationTest(),
            "sequenceEndPixels": sequenceEndPixels(),
            "refractionContract": refractionContractTest(),
            "refractionBasisCases": refractionBasisCases(),
            "refractionTrailBasisCases": refractionTrailBasisCases(),
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
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.spriteForward),
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

    private static func ndc(_ matrix: simd_float4x4, _ point: SIMD4<Float>) -> [Float] {
        let clip = matrix * point
        return [clip.x / clip.w, clip.y / clip.w, clip.z / clip.w]
    }

    private static func renderSmokeTest() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return false }

        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        guard let input = device.makeTexture(descriptor: inputDescriptor) else { return false }
        var white = [UInt8](repeating: 255, count: 4)
        input.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )

        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        guard let output = device.makeTexture(descriptor: outputDescriptor) else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }

        let values = [
            SceneParticleGPUInstance(
                position: SIMD3(-0.25, 0, 0), size: 0.5, rotation: .zero,
                color: SIMD3(repeating: 1), alpha: 1
            ),
            SceneParticleGPUInstance(
                position: SIMD3(0.25, 0, 0), size: 0.5, rotation: SIMD3(0, 0, 0.2),
                color: SIMD3(1, 0, 0), alpha: 0.5
            ),
        ]
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: values) else { return false }
        let emptyInstances = SceneParticleMetalInstanceBuffer()
        let basis = SceneParticleOrientation.screen.basis(
            cameraRight: SIMD3(1, 0, 0), cameraUp: SIMD3(0, 1, 0),
            cameraForward: SIMD3(0, 0, -1)
        )
        let emptyDraw = pipeline.draw(
            texture: input, instances: emptyInstances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(), basis: basis
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        let translucentDraw = pipeline.draw(
            texture: input, instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(), basis: basis
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        let additiveDraw = pipeline.draw(
            texture: input, instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(), basis: basis
            ),
            renderState: particleState(.additive),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        let submitted = instances.markSubmitted(on: command)
        let completed = commitAndWait(command)
        return !emptyDraw && translucentDraw && additiveDraw
            && submitted && completed
            && command.status == .completed && instances.count == 2
    }

    private static func additiveFractionalAlphaPixel() -> [Int] {
        let size = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [] }
        var white: [UInt8] = [255, 255, 255, 255]
        input.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: .zero,
                size: 2,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 0.25
            ),
        ]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return []
        }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            renderState: particleState(.additive),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        output.getBytes(
            &pixel,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, size / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    private static func depthAndOverbrightPixel() -> [Int] {
        let size = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer(),
              let depthLease = pipeline.acquireDepthTarget(width: size, height: size)
        else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let red = device.makeTexture(descriptor: inputDescriptor),
              let green = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [] }
        var redPixel: [UInt8] = [255, 0, 0, 255]
        var greenPixel: [UInt8] = [0, 255, 0, 255]
        red.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &redPixel,
            bytesPerRow: 4
        )
        green.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &greenPixel,
            bytesPerRow: 4
        )
        let near = SceneParticleMetalInstanceBuffer()
        let far = SceneParticleMetalInstanceBuffer()
        guard near.update(device: device, instances: [instance(x: 0, z: 0.2)]),
              far.update(device: device, instances: [instance(x: 0, z: 0.8)]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depthLease.texture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        let uniforms = SceneParticleLayerUniforms(
            viewProjection: SceneMatrix.identity(),
            layerModel: SceneMatrix.identity(),
            basis: SceneParticleOrientation.screen.basis(
                cameraRight: SIMD3(1, 0, 0),
                cameraUp: SIMD3(0, 1, 0),
                cameraForward: SIMD3(0, 0, -1)
            )
        )
        let state = SceneParticlePipelineRenderState(
            blendMode: .translucent,
            cullMode: .none,
            depthTestEnabled: true,
            depthWriteEnabled: true,
            overbright: 0.5
        )
        pipeline.draw(
            texture: red,
            instances: near,
            uniforms: uniforms,
            renderState: state,
            colorSampling: .directImageFallback,
            usesDepthAttachment: true,
            encoder: encoder
        )
        pipeline.draw(
            texture: green,
            instances: far,
            uniforms: uniforms,
            renderState: state,
            colorSampling: .directImageFallback,
            usesDepthAttachment: true,
            encoder: encoder
        )
        encoder.endEncoding()
        guard near.markSubmitted(on: command), far.markSubmitted(on: command) else { return [] }
        depthLease.arm(on: command)
        guard commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        output.getBytes(
            &pixel,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, size / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    private static func depthTargetLeaseContract() -> [String: Bool] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let first = pipeline.acquireDepthTarget(width: 8, height: 8),
              let second = pipeline.acquireDepthTarget(width: 8, height: 8),
              let third = pipeline.acquireDepthTarget(width: 8, height: 8) else { return [:] }
        let rejectsFourth = pipeline.acquireDepthTarget(width: 8, height: 8) == nil
        let firstTexture = first.texture
        first.cancel()
        let replacement = pipeline.acquireDepthTarget(width: 8, height: 8)
        let reusesReleased = replacement?.texture === firstTexture
        replacement?.cancel()
        second.cancel()
        third.cancel()
        guard let command = queue.makeCommandBuffer(),
              let armed = pipeline.acquireDepthTarget(width: 8, height: 8) else { return [:] }
        let armedTexture = armed.texture
        armed.arm(on: command)
        let completed = commitAndWait(command)
        let afterCompletion = pipeline.acquireDepthTarget(width: 8, height: 8)
        let completionReleased = completed && afterCompletion?.texture === armedTexture
        afterCompletion?.cancel()
        return [
            "rejectsFourth": rejectsFourth,
            "reusesReleased": reusesReleased,
            "completionReleased": completionReleased,
        ]
    }

    private static func instanceBufferSlotTest() -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let firstCommand = queue.makeCommandBuffer(),
              let secondCommand = queue.makeCommandBuffer(),
              let thirdCommand = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [instance(x: 1)]),
              let firstBuffer = instances.buffer else {
            return ["available": false]
        }
        let firstValue = firstBuffer.contents()
            .assumingMemoryBound(to: SceneParticleGPUInstance.self)
            .pointee.positionAndSize.x
        let firstSubmitted = instances.markSubmitted(on: firstCommand)

        guard instances.update(device: device, instances: [instance(x: 2)]),
              let secondBuffer = instances.buffer else {
            return ["available": false]
        }
        let firstPreserved = firstBuffer.contents()
            .assumingMemoryBound(to: SceneParticleGPUInstance.self)
            .pointee.positionAndSize.x == firstValue
        let secondSubmitted = instances.markSubmitted(on: secondCommand)

        guard instances.update(device: device, instances: [instance(x: 3)]),
              let thirdBuffer = instances.buffer else {
            return ["available": false]
        }
        let thirdSubmitted = instances.markSubmitted(on: thirdCommand)
        let firstCompleted = commitAndWait(firstCommand)

        guard instances.update(device: device, instances: [instance(x: 4)]),
              let reusedBuffer = instances.buffer else {
            return ["available": false]
        }
        let secondCompleted = commitAndWait(secondCommand)
        let thirdCompleted = commitAndWait(thirdCommand)
        return [
            "available": true,
            "firstSubmitted": firstSubmitted,
            "secondSubmitted": secondSubmitted,
            "thirdSubmitted": thirdSubmitted,
            "firstPreserved": firstPreserved,
            "grewForSecond": firstBuffer !== secondBuffer,
            "grewForThird": firstBuffer !== thirdBuffer && secondBuffer !== thirdBuffer,
            "firstCompleted": firstCompleted,
            "reusedFirst": reusedBuffer === firstBuffer,
            "cleanupCompleted": secondCompleted && thirdCompleted,
        ]
    }

    private static func instanceBufferPendingCancellationTest() -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pendingCommand = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [instance(x: 1)]),
              let firstBuffer = instances.buffer else {
            return ["available": false]
        }
        let pendingCancelled = instances.cancelPending()
        let pendingCleared = instances.currentDrawState() == nil && instances.count == 0
        guard instances.update(device: device, instances: [instance(x: 2)]),
              let secondBuffer = instances.buffer else {
            return ["available": false]
        }
        let reusedAfterPending = secondBuffer === firstBuffer
        let marked = instances.markSubmitted(on: pendingCommand)
        let uncommittedCancelled = instances.cancelUncommittedSubmission(on: pendingCommand)
        let uncommittedCleared = instances.currentDrawState() == nil && instances.count == 0
        guard instances.update(device: device, instances: [instance(x: 3)]),
              let thirdBuffer = instances.buffer else {
            return ["available": false]
        }
        let reusedAfterSubmissionCancel = thirdBuffer === firstBuffer
        let idempotentCancel = !instances.cancelUncommittedSubmission(on: pendingCommand)
        _ = instances.cancelPending()

        guard let committedCommand = queue.makeCommandBuffer(),
              instances.update(device: device, instances: [instance(x: 4)]),
              let committedBuffer = instances.buffer,
              instances.markSubmitted(on: committedCommand) else {
            return ["available": false]
        }
        let cancelInFlightRejected = !instances.cancelPending()
        let inFlightCountPreserved = instances.count == 1
        guard commitAndWait(committedCommand) else {
            return ["available": false]
        }
        let cancelAfterCompletionRejected =
            !instances.cancelUncommittedSubmission(on: committedCommand)
        guard instances.update(device: device, instances: [instance(x: 5)]),
              let afterCompletionBuffer = instances.buffer else {
            return ["available": false]
        }
        let reusedAfterCompletion = afterCompletionBuffer === committedBuffer
        _ = instances.cancelPending()
        return [
            "available": true,
            "pendingCancelled": pendingCancelled,
            "pendingCleared": pendingCleared,
            "reusedAfterPending": reusedAfterPending,
            "marked": marked,
            "uncommittedCancelled": uncommittedCancelled,
            "uncommittedCleared": uncommittedCleared,
            "reusedAfterSubmissionCancel": reusedAfterSubmissionCancel,
            "idempotentCancel": idempotentCancel,
            "cancelInFlightRejected": cancelInFlightRejected,
            "inFlightCountPreserved": inFlightCountPreserved,
            "cancelAfterCompletionRejected": cancelAfterCompletionRejected,
            "reusedAfterCompletion": reusedAfterCompletion,
        ]
    }

    private static func ropeTrailJoinContract(connectParticles: Bool = false) -> [[String: Any]] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue() else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        inputDescriptor.storageMode = .shared
        inputDescriptor.usage = .shaderRead
        let input = device.makeTexture(descriptor: inputDescriptor)!
        var white: [UInt8] = [255, 255, 255, 255]
        input.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                      withBytes: &white, bytesPerRow: 4)
        var transforms = [SceneMatrix.identity(), SceneMatrix.scale(SIMD3(-1.2, 0.8, 1)),
                          SceneMatrix.rotationZ(0.37) * SceneMatrix.scale(SIMD3(0.8, 1.2, 1)),
                          SceneMatrix.identity(), SceneMatrix.identity()]
        if connectParticles { transforms += [SceneMatrix.identity(), SceneMatrix.identity()] }
        return transforms.enumerated().map { transformIndex, model in
            let repeated = transformIndex == 3
            let perspective = transformIndex == 4
            let tapered = transformIndex == 5
            let points: [SIMD3<Float>] = tapered
                ? [SIMD3(-0.7, 0, 0), .zero, SIMD3(0.7, 0, 0)]
                : perspective
                ? [SIMD3(0, 0, -5), SIMD3(0.5, 0, -1), SIMD3(0.6, 0, -0.8)]
                : repeated
                    ? [SIMD3(-0.5, 0, 0), .zero, .zero, SIMD3(0, 0.5, 0)]
                    : [SIMD3(-0.5, 0, 0), .zero, SIMD3(0, 0.5, 0)]
            let projection = perspective ? simd_float4x4(
                SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
                SIMD4(0, 0, -1.01, -1), SIMD4(0, 0, -0.101, 0)
            ) : SceneMatrix.identity()
            let definition = SceneParticleDefinitionParser().parse(root: [
                "maxcount": 1, "material": "materials/particle.json",
                "emitter": [["name": "sphererandom"]],
                "renderer": [["name": "ropetrail", "length": Double(points.count - 1) * 0.5, "segments": points.count - 1, "subdivision": 0]]])
            let plan = SceneParticleRopeTrailPlan(renderer: definition.renderers[0],
                rendererCount: 1, maximumParticleCount: 1)!
            var history = SceneParticleRopeTrailHistory(plan: plan)
            var values: [SceneParticleGPUInstance] = []
            for (i, point) in points.enumerated() {
                values = history.advance(by: i == 0 ? 0 : 0.5,
                    particles: [.init(id: 1, position: point, size: i == 1 ? 0.5 : 0.3,
                                      color: SIMD3(repeating: 1), alpha: 0.5)], layerAlpha: 1)
            }
            if connectParticles {
                let ropeDefinition = SceneParticleDefinitionParser().parse(root: [
                    "maxcount": points.count, "material": "materials/particle.json",
                    "renderer": [["name": "rope", "subdivision": transformIndex == 6 ? 3 : 0]]])
                let rope = SceneParticleRopePlan(renderer: ropeDefinition.renderers[0],
                    rendererCount: 1, maximumParticleCount: points.count)!
                let particles = points.enumerated().map { i, point in
                    let size: Double = tapered ? [0.2, 0.6, 0][i] : (repeated && i == 2 ? 0.8 : 0.3)
                    return SceneParticleState(id: UInt64(i),
                        position: SIMD3(Double(point.x), Double(point.y), Double(point.z)),
                        velocity: .zero, color: SIMD3(repeating: 1), alpha: 0.5,
                        size: size, rotation: .zero, angularVelocity: .zero,
                        age: 0, lifetime: 1, initialColor: SIMD3(repeating: 1),
                        initialAlpha: 0.5, initialSize: size)
                }
                values = rope.instances(particles: particles, layerAlpha: 1)
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: 256, height: 256, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .renderTarget
            let output = device.makeTexture(descriptor: descriptor)!
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            let instances = SceneParticleMetalInstanceBuffer()
            guard instances.update(device: device, instances: values) else { return ["completed": false] }
            pipeline.draw(texture: input, instances: instances,
                uniforms: .init(viewProjection: projection, layerModel: model,
                    basis: SceneParticleOrientation.screen.basis(cameraRight: SIMD3(1, 0, 0),
                        cameraUp: SIMD3(0, 1, 0), cameraForward: SIMD3(0, 0, -1)),
                    viewportSize: SIMD2(256, 256)),
                renderState: particleState(.translucent), colorSampling: .directImageFallback, encoder: encoder)
            encoder.endEncoding()
            guard instances.markSubmitted(on: command), commitAndWait(command), command.status == .completed else {
                return ["completed": false]
            }
            var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
            output.getBytes(&pixels, bytesPerRow: 256 * 4,
                           from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
            let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            let jointX = perspective ? 192 : 128
            let jointCovered = (125...130).allSatisfy { y in
                ((jointX - 3)...(jointX + 2)).allSatisfy { x in pixels[(y * 256 + x) * 4 + 3] >= 127 }
            }
            return ["completed": true, "transform": transformIndex,
                    "maximumAlpha": Int(alphas.max() ?? 0),
                    "visiblePixels": alphas.filter { $0 > 0 }.count,
                    "jointCovered": jointCovered,
                    "columnWidths": [44, 96, 128, 160, 214].map { x in
                        (0..<256).filter { y in pixels[(y * 256 + x) * 4 + 3] > 0 }.count
                    }]
        }
    }

    private static func ropeTrailRenderContract() -> [String: Any] {
        let definition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/particle.json",
            "maxcount": 1,
            "emitter": [["name": "sphererandom"]],
            "renderer": [[
                "name": "ropetrail",
                "length": 1,
                "segments": 4,
                "subdivision": 0,
                "fadealpha": true,
            ]],
        ])
        guard let renderer = definition.renderers.first,
              let plan = SceneParticleRopeTrailPlan(
                renderer: renderer,
                rendererCount: definition.renderers.count,
                maximumParticleCount: 1
              ) else {
            return ["available": false]
        }
        let points: [SIMD2<Float>] = [
            SIMD2(-0.6, -0.6),
            SIMD2(-0.6, -0.2),
            SIMD2(-0.6, 0.2),
            SIMD2(-0.2, 0.2),
            SIMD2(0.2, 0.2),
        ]
        var history = SceneParticleRopeTrailHistory(plan: plan)
        var values: [SceneParticleGPUInstance] = []
        for (index, point) in points.enumerated() {
            values = history.advance(
                by: index == 0 ? 0 : 0.25,
                particles: [SceneParticleRopeTrailParticle(
                    id: 1,
                    position: SIMD3(point.x, point.y, 0),
                    // GPU records expose half the authored particle size. Keep
                    // this raster contract's historical on-screen thickness.
                    size: 0.24,
                    color: SIMD3(repeating: 1),
                    alpha: 1
                )],
                layerAlpha: 1
            )
        }

        let size = 128
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 8,
            height: 32,
            mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else {
            return ["available": false]
        }
        var drop = [UInt8](repeating: 0, count: 8 * 32 * 4)
        for y in 0..<32 {
            for x in 0..<8 {
                let cross = max(0, 1 - abs(Float(x) - 3.5) / 3.5)
                let trail = 1 - Float(y) / 31
                let alpha = UInt8(max(0, min(255, Int(255 * cross * trail))))
                let offset = (y * 8 + x) * 4
                drop[offset] = alpha
                drop[offset + 1] = alpha
                drop[offset + 2] = alpha
                drop[offset + 3] = alpha
            }
        }
        input.replace(
            region: MTLRegionMake2D(0, 0, 8, 32),
            mipmapLevel: 0,
            withBytes: &drop,
            bytesPerRow: 8 * 4
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: values) else {
            return ["available": false]
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return ["available": false]
        }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), commitAndWait(command) else {
            return ["available": false]
        }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        output.getBytes(
            &pixels,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        let visible = (0..<(size * size)).filter { pixels[$0 * 4 + 3] > 0 }
        let xs = visible.map { $0 % size }
        let ys = visible.map { $0 / size }
        let headAlpha = visible
            .filter { $0 % size > 64 && (44...58).contains($0 / size) }
            .map { Int(pixels[$0 * 4 + 3]) }
            .max() ?? 0
        let tailAlpha = visible
            .filter { (20...32).contains($0 % size) && $0 / size > 85 }
            .map { Int(pixels[$0 * 4 + 3]) }
            .max() ?? 0
        return [
            "available": true,
            "instanceCount": values.count,
            "width": (xs.max() ?? 0) - (xs.min() ?? 0) + 1,
            "height": (ys.max() ?? 0) - (ys.min() ?? 0) + 1,
            "visiblePixels": visible.count,
            "headAlpha": headAlpha,
            "tailAlpha": tailAlpha,
            "horizontalSegments": values.filter {
                abs($0.velocityAndTrail.x) > abs($0.velocityAndTrail.y)
            }.count,
            "verticalSegments": values.filter {
                abs($0.velocityAndTrail.y) > abs($0.velocityAndTrail.x)
            }.count,
        ]
    }

    private static func ropeTrailTransformContract() -> [String: Any] {
        let size = 256
        let tail = SIMD3<Float>(-0.35, -0.2, 0)
        let head = SIMD3<Float>(0.45, 0.3, 0)
        let center = (tail + head) * 0.5
        let displacement = head - tail
        let angle = Float.pi / 6
        let scale = SIMD2<Float>(1.4, 0.6)
        let layerModel = simd_float4x4(columns: (
            SIMD4(cos(angle) * scale.x, sin(angle) * scale.x, 0, 0),
            SIMD4(-sin(angle) * scale.y, cos(angle) * scale.y, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0.1, -0.05, 0, 1)
        ))
        let transformedTail = layerModel * SIMD4(tail, 1)
        let transformedHead = layerModel * SIMD4(head, 1)
        let transformedTailXY = SIMD2(transformedTail.x, transformedTail.y)
        let transformedHeadXY = SIMD2(transformedHead.x, transformedHead.y)
        let transformedDisplacement = transformedHeadXY - transformedTailXY
        let direction = simd_normalize(transformedDisplacement)
        let expectedTail = simd_dot(transformedTailXY, direction)
        let expectedHead = simd_dot(transformedHeadXY, direction)

        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 9,
            height: 33,
            mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else {
            return ["available": false]
        }
        var centerline = [UInt8](repeating: 0, count: 9 * 33 * 4)
        for y in 0..<33 {
            for x in 3...5 {
                let offset = (y * 9 + x) * 4
                centerline[offset] = 255
                centerline[offset + 1] = 255
                centerline[offset + 2] = 255
                centerline[offset + 3] = 255
            }
        }
        input.replace(
            region: MTLRegionMake2D(0, 0, 9, 33),
            mipmapLevel: 0,
            withBytes: &centerline,
            bytesPerRow: 9 * 4
        )
        let segmentSize: Float = 0.08
        let frame = SceneParticleFrameTransform.identity.verticalTrailSlice(
            tailPosition: 0,
            headPosition: 1
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: center,
                size: segmentSize,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 1,
                velocity: displacement,
                trailStretch: simd_length(displacement) / segmentSize,
                trailUVRange: SIMD2(0, 1),
                usesTrailDisplacement: true,
                currentFrame: frame
            ),
        ]) else {
            return ["available": false]
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return ["available": false]
        }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: layerModel,
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), commitAndWait(command) else {
            return ["available": false]
        }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        output.getBytes(
            &pixels,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        let projections = (0..<(size * size)).compactMap { index -> Float? in
            guard pixels[index * 4 + 3] > 64 else { return nil }
            let x = Float(index % size) + 0.5
            let y = Float(index / size) + 0.5
            let ndc = SIMD2(
                x / Float(size) * 2 - 1,
                1 - y / Float(size) * 2
            )
            return simd_dot(ndc, direction)
        }
        return [
            "available": true,
            "expectedTail": min(expectedTail, expectedHead),
            "expectedHead": max(expectedTail, expectedHead),
            "observedTail": projections.min() ?? 0,
            "observedHead": projections.max() ?? 0,
            "visiblePixels": projections.count,
        ]
    }

    private static func ropeTrailAspectContract() -> [String: Any] {
        let width = 320
        let height = 180
        let tail = SIMD3<Float>(-0.55, -0.38, 0)
        let head = SIMD3<Float>(0.55, 0.38, 0)
        let displacement = head - tail
        let pathPixelDirection = simd_normalize(SIMD2(
            displacement.x * Float(width),
            -displacement.y * Float(height)
        ))
        let legacyPerpendicular = simd_normalize(SIMD2(
            -displacement.y * Float(width),
            -displacement.x * Float(height)
        ))

        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else {
            return ["available": false]
        }
        let inputWidth = 33
        let inputHeight = 65
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: inputWidth,
            height: inputHeight,
            mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else {
            return ["available": false]
        }
        var crossbar = [UInt8](repeating: 0, count: inputWidth * inputHeight * 4)
        for y in 31...33 {
            for x in 0..<inputWidth {
                let offset = (y * inputWidth + x) * 4
                crossbar[offset] = 255
                crossbar[offset + 1] = 255
                crossbar[offset + 2] = 255
                crossbar[offset + 3] = 255
            }
        }
        input.replace(
            region: MTLRegionMake2D(0, 0, inputWidth, inputHeight),
            mipmapLevel: 0,
            withBytes: &crossbar,
            bytesPerRow: inputWidth * 4
        )
        let segmentSize: Float = 0.42
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: (tail + head) * 0.5,
                size: segmentSize,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 1,
                velocity: displacement,
                trailStretch: simd_length(displacement) / segmentSize,
                trailUVRange: SIMD2(0, 1),
                usesTrailDisplacement: true,
                currentFrame: SceneParticleFrameTransform.identity.verticalTrailSlice(
                    tailPosition: 0,
                    headPosition: 1
                )
            ),
        ]) else {
            return ["available": false]
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return ["available": false]
        }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                ),
                viewportSize: SIMD2(Float(width), Float(height))
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), commitAndWait(command) else {
            return ["available": false]
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        output.getBytes(
            &pixels,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        let points = (0..<(width * height)).compactMap { index -> SIMD2<Float>? in
            guard pixels[index * 4 + 3] > 64 else { return nil }
            return SIMD2(
                Float(index % width) + 0.5,
                Float(index / width) + 0.5
            )
        }
        guard points.count > 2 else {
            return ["available": true, "visiblePixels": points.count]
        }
        let mean = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
        let covariance = points.reduce(SIMD3<Float>.zero) { partial, point in
            let delta = point - mean
            return partial + SIMD3(
                delta.x * delta.x,
                delta.x * delta.y,
                delta.y * delta.y
            )
        } / Float(points.count)
        let angle = 0.5 * atan2(
            2 * covariance.y,
            covariance.x - covariance.z
        )
        let crossPixelDirection = SIMD2(cos(angle), sin(angle))
        let discriminant = sqrt(
            (covariance.x - covariance.z) * (covariance.x - covariance.z)
                + 4 * covariance.y * covariance.y
        )
        let majorVariance = (covariance.x + covariance.z + discriminant) * 0.5
        let minorVariance = (covariance.x + covariance.z - discriminant) * 0.5
        return [
            "available": true,
            "visiblePixels": points.count,
            "absoluteDot": abs(simd_dot(
                pathPixelDirection,
                crossPixelDirection
            )),
            "legacyAbsoluteDot": abs(simd_dot(
                pathPixelDirection,
                legacyPerpendicular
            )),
            "varianceRatio": majorVariance / max(minorVariance, 0.0001),
        ]
    }

    private static func authoredRotationBounds(_ value: Any) -> [String: Int] {
        let data = try! JSONSerialization.data(withJSONObject: [
            "initializer": [["name": "rotationrandom", "min": value, "max": value]]
        ])
        let definition = try! SceneParticleDefinitionParser().parse(data: data)
        let angles = definition.initializers[0].minimum!.vectorValue!
        return spriteBounds(currentAspect: 0.25, nextAspect: 0.25, frameMix: 0,
                            rotation: SIMD3(Float(angles[0]), Float(angles[1]), Float(angles[2])),
                            marked: true)
    }

    private static func defaultTrailBounds() -> [String: [[String: Int]]] {
        let plans = [
            "omitted": SceneParticleTrailRenderPlan(length: 0.007, minimumLength: nil, maximumLength: nil)!,
            "explicit": SceneParticleTrailRenderPlan(length: 0.007, minimumLength: 0, maximumLength: 10)!,
            "fixed": SceneParticleTrailRenderPlan(length: 0.007, minimumLength: 1, maximumLength: 1)!
        ]
        return plans.mapValues { plan in
            [100.0, 200.0, 400.0].map { speed in
                trailBounds(velocity: SIMD3(Float(speed), 0, 0),
                            stretch: plan.stretch(for: SIMD3(speed, 0, 0)))
            }
        }
    }

    private static func trailBounds(
        velocity: SIMD3<Float>,
        layerModel: simd_float4x4 = SceneMatrix.identity(),
        rope: Bool = false,
        sizeIsWorldSpace: Bool = false,
        particleSize: Float = 0.2,
        stretch: Float = 4,
        viewProjection: simd_float4x4 = SceneMatrix.identity(),
        basis: SceneParticleOrientationBasis = .init(right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0))
    ) -> [String: Int] {
        let size = 256
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [:] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [:] }
        var white = [UInt8](repeating: 255, count: 4)
        input.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )
        let instances = SceneParticleMetalInstanceBuffer()
        let values = [SceneParticleGPUInstance(
            position: .zero, size: particleSize, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: 1,
            velocity: rope ? velocity * 0.12 : velocity, trailStretch: stretch,
            usesTrailDisplacement: rope,
            trailHeadDirection: rope ? velocity * 0.12 : nil,
            trailTailDirection: rope ? velocity * 0.12 : nil,
            trailEndpointSizes: rope ? SIMD2(repeating: particleSize) : nil
        )]
        guard instances.update(device: device, instances: values) else { return [:] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [:] }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: viewProjection,
                layerModel: layerModel,
                basis: basis, viewportSize: SIMD2(256, 256), sizeIsWorldSpace: sizeIsWorldSpace
            ),
            renderState: particleState(.translucent),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), commitAndWait(command) else { return [:] }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        output.getBytes(
            &pixels,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        var minimumX = size
        var minimumY = size
        var maximumX = -1
        var maximumY = -1
        for y in 0..<size {
            for x in 0..<size where pixels[(y * size + x) * 4 + 3] > 0 {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }
        return [
            "width": maximumX >= minimumX ? maximumX - minimumX + 1 : 0,
            "height": maximumY >= minimumY ? maximumY - minimumY + 1 : 0,
        ]
    }


    private static func uprightGeometryContract() -> [String: Any] {
        func camera(_ roll: Float, canvas: Bool = false, eye: [Float] = [0, 0, 3], authoredUp: [Float]? = nil) -> SceneParticleCameraFrame {
            let angle = roll * .pi / 180
            return SceneParticleCameraFrame(camera: .init(
                eye: eye, center: [0, 0, 0], up: authoredUp ?? [-sin(angle), cos(angle), 0],
                orthoWidth: canvas ? 2 : nil, orthoHeight: canvas ? 2 : nil,
                fovDegrees: 50, perspectiveOverrideFOVDegrees: 50,
                nearZ: 0.01, farZ: 100), viewportSize: CGSize(width: 256, height: 256))
        }
        let model = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.identity(), parallaxOffset: .zero)
        let rotated = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.rotationZ(.pi / 2), parallaxOffset: .zero)
        let scaled = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.rotationZ(.pi / 2) * SceneMatrix.scale(SIMD3(2, 3, 1)),
            parallaxOffset: .zero)
        let mirrored = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.scale(SIMD3(1, -2, 1)), parallaxOffset: .zero)
        let zero = SceneMatrix.scale(SIMD3<Float>(1, 0, 1))
        var rows: [String: Any] = [:]
        func row(_ frame: SceneParticleCameraFrame, _ orientation: SceneParticleOrientation,
                 _ model: simd_float4x4, projection: simd_float4x4 = SceneMatrix.identity(),
                 expectedBasis: SceneParticleOrientationBasis = .init(right: SIMD3(1, 0, 0), up: SIMD3(0, -1, 0))) -> [String: Any] {
            let basis = frame.basis(for: orientation, layerModel: model)
            return ["right": vector(basis.right), "up": vector(basis.up),
                "pixels": spriteBounds(currentAspect: 0.5, nextAspect: 0.5, frameMix: 0,
                    marked: true, viewProjection: projection, basis: basis),
                "expectedPixels": spriteBounds(currentAspect: 0.5, nextAspect: 0.5, frameMix: 0,
                    marked: true, viewProjection: projection, basis: expectedBasis)]
        }
        for roll: Float in [0, 89, 90, 91, 180] {
            let frame = camera(roll)
            rows["roll\(Int(roll))"] = row(frame, .worldUpright, model)
            rows["localRoll\(Int(roll))"] = row(frame, .upright, model)
            rows["projectedRoll\(Int(roll))"] = row(frame, .worldUpright, model,
                projection: frame.perspectiveViewProjection)
        }
        let frame = camera(0)
        let rotatedExpected = SceneParticleOrientationBasis(right: SIMD3(0, 1, 0), up: SIMD3(1, 0, 0))
        rows["localRotated"] = row(frame, .upright, rotated, expectedBasis: rotatedExpected)
        rows["localScaled"] = row(frame, .upright, scaled, expectedBasis: rotatedExpected)
        rows["worldRotated"] = row(frame, .worldUpright, rotated)
        rows["screenRotated"] = row(frame, .screen, rotated, expectedBasis: rotatedExpected)
        rows["screenWorldRotated"] = row(frame, .worldScreen, rotated)
        rows["screenScaled"] = row(frame, .screen, scaled,
            expectedBasis: .init(right: SIMD3(0, 1, 0), up: SIMD3(1, 0, 0),
                localGeometry: simd_float3x3(SIMD3(0, 2, 0), SIMD3(3, 0, 0), SIMD3(0, 0, -1))))
        let tilt = SceneParticleCameraFrame.particleLayerModel(
            worldFrame: SceneMatrix.rotationX(.pi / 3), parallaxOffset: .zero)
        rows["screenTilted"] = row(frame, .screen, tilt,
            expectedBasis: .init(right: SIMD3(1, 0, 0), up: SIMD3(0, -0.5, -sqrt(0.75)),
                localGeometry: simd_float3x3(SIMD3(1, 0, 0), SIMD3(0, -0.5, -sqrt(0.75)),
                    SIMD3(0, sqrt(0.75), -0.5))))
        rows["localMirrored"] = row(frame, .upright, mirrored,
            expectedBasis: .init(right: SIMD3(-1, 0, 0), up: SIMD3(0, 1, 0)))
        rows["zeroAxis"] = row(frame, .upright, zero)
        let tilted = camera(0, eye: [0, 2, 3])
        rows["tilted"] = row(tilted, .worldUpright, model,
            projection: tilted.perspectiveViewProjection)
        let canvas = camera(0, canvas: true)
        rows["canvas"] = row(canvas, .upright, model, projection: canvas.perspectiveViewProjection * SceneMatrix.translation(SIMD3(1, 1, 0)))
        let pole = SceneParticleOrientation.upright.basis(cameraRight: SIMD3(1, 1, 0),
            cameraUp: SIMD3(0, 0, 1), cameraForward: SIMD3(0, -1, 0))
        let degenerate = SceneParticleOrientation.upright.basis(cameraRight: SIMD3(0, 1, 0),
            cameraUp: SIMD3(0, 0, 1), cameraForward: SIMD3(0, -1, 0))
        let fixedAxis = SIMD3<Float>(0, 1, 0)
        var fixedSame = true
        for orientation: SceneParticleOrientation in [.fixed, .worldFixed] {
            let vectors = orientation.fixedBasisVectors(axis: fixedAxis, layerModel: rotated)
            let legacy = frame.basis(for: orientation, fixedRight: vectors.right, fixedUp: vectors.up)
            let current = frame.basis(for: orientation, layerModel: rotated, orientationAxis: fixedAxis)
            fixedSame = fixedSame && legacy.right == current.right && legacy.up == current.up
        }
        var trails: [String: [String: Int]] = [:]
        for roll: Float in [0, 89, 90, 91, 180] {
            let rolled = camera(roll)
            trails["roll\(Int(roll))"] = trailBounds(velocity: SIMD3(1, 0, 0),
                viewProjection: rolled.perspectiveViewProjection,
                basis: rolled.basis(for: .upright, layerModel: model))
        }
        trails["tilted"] = trailBounds(velocity: SIMD3(1, 0, 0),
            viewProjection: tilted.perspectiveViewProjection,
            basis: tilted.basis(for: .upright, layerModel: model))
        let poleFrame = camera(0, eye: [0, 3, 0], authoredUp: [0, 0, 1])
        trails["pole"] = trailBounds(velocity: SIMD3(1, 0, 0),
            viewProjection: poleFrame.perspectiveViewProjection,
            basis: poleFrame.basis(for: .upright, layerModel: model))
        return ["rows": rows, "trails": trails, "poleRight": vector(pole.right), "poleUp": vector(pole.up),
            "degenerateRight": vector(degenerate.right), "degenerateUp": vector(degenerate.up),
            "fixedDirectionsUnchanged": fixedSame,
            "screenRolledUp": vector(camera(90).basis(for: .screen).up)]
    }

    private static func spriteBounds(
        currentAspect: Float,
        nextAspect: Float,
        frameMix: Float,
        rotation: SIMD3<Float> = .zero,
        layerModel: simd_float4x4 = SceneMatrix.identity(),
        marked: Bool = false,
        viewProjection: simd_float4x4 = SceneMatrix.identity(),
        basis: SceneParticleOrientationBasis = .init(right: SIMD3(1, 0, 0), up: SIMD3(0, 1, 0))
    ) -> [String: Int] {
        let size = 256
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [:] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [:] }
        var white: [UInt8] = marked ? [255, 0, 0, 255, 0, 255, 0, 255] : [UInt8](repeating: 255, count: 8)
        input.replace(
            region: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 8
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: SIMD3(0.125, -0.25, 0.5),
                size: 0.5,
                rotation: rotation,
                color: SIMD3(repeating: 1),
                alpha: 1,
                currentFrameAspect: currentAspect,
                nextFrameAspect: nextAspect,
                frameMix: frameMix
            ),
        ]) else { return [:] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [:] }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: viewProjection,
                layerModel: layerModel,
                basis: basis
            ),
            renderState: particleState(.translucent),
            colorSampling: marked ? SceneParticleTextureSampling(texFlags: 3) : .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        guard instances.markSubmitted(on: command), commitAndWait(command) else { return [:] }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        output.getBytes(
            &pixels,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        let visible = (0..<(size * size)).filter { pixels[$0 * 4 + 3] > 0 }
        let xs = visible.map { $0 % size }
        let ys = visible.map { $0 / size }
        let red = visible.filter { pixels[$0 * 4 + 2] > 200 && pixels[$0 * 4 + 1] < 30 }
        let green = visible.filter { pixels[$0 * 4 + 1] > 200 && pixels[$0 * 4 + 2] < 30 }
        func center(_ points: [Int], x: Bool) -> Int {
            guard !points.isEmpty else { return -1 }
            return Int((Double(points.reduce(0) { $0 + (x ? $1 % size : $1 / size) }) / Double(points.count) * 1000).rounded())
        }
        return [
            "redX1000": center(red, x: true), "redY1000": center(red, x: false),
            "greenX1000": center(green, x: true), "greenY1000": center(green, x: false),
            "width": (xs.max() ?? -1) - (xs.min() ?? 0) + 1,
            "height": (ys.max() ?? -1) - (ys.min() ?? 0) + 1,
            "centerX2": (xs.max() ?? -1) + (xs.min() ?? 0),
            "centerY2": (ys.max() ?? -1) + (ys.min() ?? 0),
        ]
    }

    private static func sequenceEndPixels() -> [[String: Any]] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return [] }
        var pixels: [UInt8] = [255,0,0,255, 0,0,255,255]
        texture.replace(region: MTLRegionMake2D(0,0,2,1), mipmapLevel: 0,
                        withBytes: &pixels, bytesPerRow: 8)
        func frame(_ index: Int) -> SceneParticleFrameTransform {
            .init(origin: SIMD2(index == 0 ? 0.25 : 0.75,0.5), xAxis: .zero, yAxis: .zero)
        }
        var rows: [[String: Any]] = []
        for prepared in [false, true] {
            for blend in [false, true] {
                for age: Float in [0.25, 0.5, 0.75, 0.999, 1, 1.25] {
                    let selected = SceneParticleSpriteFrameSelector.select(
                        mode: .sequence, frameDurations: [1,1],
                        frameEndTimes: prepared ? [1,2] : nil,
                        totalDuration: prepared ? 2 : nil,
                        age: age, lifetime: 1, particleID: 1, blendsFrames: blend)!
                    let observed = centerPixel(texture: texture,
                        currentFrame: frame(selected.currentIndex),
                        nextFrame: frame(selected.nextIndex), frameMix: selected.mix)
                    rows.append(["prepared":prepared,"blend":blend,"age":age,"bgra":observed])
                }
            }
        }
        return rows
    }

    private static func straightInterpolationTest() -> [[String: Any]] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return [] }
        var pixels: [UInt8] = [255,0,0,0, 0,0,255,255]
        texture.replace(region: MTLRegionMake2D(0,0,2,1), mipmapLevel: 0,
                        withBytes: &pixels, bytesPerRow: 8)
        func frame(_ u: Float) -> SceneParticleFrameTransform {
            .init(origin: SIMD2(u,0.5), xAxis: .zero, yAxis: .zero)
        }
        var rows: [[String: Any]] = []
        for additive in [false, true] {
            for alpha: Float in [0.4, 1] {
                for background: Float in [0, 0.125] {
                    for overbright: Float in [0.5, 1] {
                        for mix: Float in [0, 0.25, 0.5, 0.75, 1] {
                            for spatial in [false, true] {
                                let observed = centerPixel(texture: texture,
                                    currentFrame: frame(spatial ? 0.25 + mix * 0.5 : 0.25),
                                    nextFrame: spatial ? nil : frame(0.75),
                                    frameMix: spatial ? 0 : mix, particleAlpha: alpha,
                                    blendMode: additive ? .additive : .translucent,
                                    background: background, overbright: overbright)
                                rows.append(["additive": additive, "alpha": alpha,
                                    "background": background, "overbright": overbright,
                                    "mix": mix, "spatial": spatial, "bgra": observed])
                            }
                        }
                    }
                }
            }
        }
        return rows
    }

    private static func colorContractTest() -> [String: Any] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [:] }
        let r8Descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: 2, height: 2, mipmapped: false
        )
        r8Descriptor.usage = .shaderRead
        r8Descriptor.storageMode = .shared
        guard let r8 = device.makeTexture(descriptor: r8Descriptor) else { return [:] }
        var gray = [UInt8](repeating: 200, count: 4)
        r8.replace(
            region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
            withBytes: &gray, bytesPerRow: 2
        )
        let rawR8 = centerPixel(texture: r8)
        guard let adaptedR8Texture = SceneParticleColorTextureAdapter.adapt(r8) else {
            return [:]
        }
        let adaptedR8 = centerPixel(texture: adaptedR8Texture)

        let rgDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Unorm, width: 2, height: 2, mipmapped: true
        )
        rgDescriptor.usage = .shaderRead
        rgDescriptor.storageMode = .shared
        guard let rg = device.makeTexture(descriptor: rgDescriptor) else { return [:] }
        var luminanceAlpha = [UInt8](repeating: 0, count: 8)
        for index in 0..<4 {
            luminanceAlpha[index * 2] = 255
            luminanceAlpha[index * 2 + 1] = 128
        }
        rg.replace(
            region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
            withBytes: &luminanceAlpha, bytesPerRow: 4
        )
        var secondMip: [UInt8] = [64, 64]
        rg.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 1,
            withBytes: &secondMip, bytesPerRow: 2
        )
        guard let adaptedRG = SceneParticleColorTextureAdapter.adapt(rg) else {
            return [:]
        }
        guard let secondMipView = adaptedRG.makeTextureView(
            pixelFormat: adaptedRG.pixelFormat, textureType: .type2D,
            levels: 1..<2, slices: 0..<1, swizzle: adaptedRG.swizzle) else { return [:] }
        return [
            "rawR8": rawR8, "adaptedR8": adaptedR8,
            "rgMipCount": adaptedRG.mipmapLevelCount,
            "rgPixel": centerPixel(texture: adaptedRG),
            "rgSecondMip": centerPixel(texture: secondMipView),
        ]
    }

    private static func refractionBasis(
        rotation: SIMD3<Float> = .zero,
        basis: SceneParticleOrientationBasis = .init(right: SIMD3(1,0,0), up: SIMD3(0,1,0)),
        viewBasis: SceneParticleOrientationBasis = .init(right: SIMD3(1,0,0), up: SIMD3(0,1,0)),
        particleSize: Float = 2,
        aspect: Float = 1,
        model: simd_float4x4 = SceneMatrix.identity(),
        projection: simd_float4x4 = SceneMatrix.identity(),
        position: SIMD3<Float> = SIMD3(0,0,0.5),
        trailVelocity: SIMD3<Float>? = nil,
        joinDirection: SIMD3<Float>? = nil
    ) -> [Float] {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let source = sceneParticleShaderSource + """
        fragment float4 readRefractionBasis(Varyings in [[stage_in]]) {
            return float4(in.screenTangentX, in.screenTangentY);
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil) else { return [] }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "sceneParticleVert")
        descriptor.fragmentFunction = library.makeFunction(name: "readRefractionBasis")
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return [] }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
            width: 32, height: 32, mipmapped: false)
        td.usage = .renderTarget; td.storageMode = .shared
        guard let target = device.makeTexture(descriptor: td) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(99,99,99,99)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        encoder.setRenderPipelineState(pipeline)
        var quad: [SIMD4<Float>] = [SIMD4(-0.5,-0.5,0,1), SIMD4(0.5,-0.5,1,1),
                                  SIMD4(-0.5,0.5,0,0), SIMD4(0.5,0.5,1,0)]
        var instance = SceneParticleGPUInstance(position: position, size: particleSize,
            rotation: rotation, color: SIMD3(repeating: 1), alpha: 1,
            velocity: trailVelocity ?? .zero,
            trailStretch: trailVelocity == nil ? nil : 2,
            usesTrailDisplacement: trailVelocity != nil,
            trailHeadDirection: joinDirection, trailTailDirection: joinDirection,
            trailEndpointSizes: joinDirection == nil ? nil : SIMD2(repeating: particleSize),
            currentFrameAspect: aspect)
        var uniforms = SceneParticleLayerUniforms(viewProjection: projection, layerModel: model,
            basis: basis, viewportSize: SIMD2(32,32), viewBasis: viewBasis)
        encoder.setVertexBytes(&quad, length: quad.count * 16, index: 0)
        encoder.setVertexBytes(&instance, length: MemoryLayout<SceneParticleGPUInstance>.stride, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SceneParticleLayerUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return [] }
        var pixels = [Float](repeating: 0, count: 32 * 32 * 4)
        target.getBytes(&pixels, bytesPerRow: 32 * 16, from: MTLRegionMake2D(0,0,32,32), mipmapLevel: 0)
        // Tangents are constant per Sprite. Select a covered pixel, allowing
        // the camera/depth cases to move the card without coupling the oracle
        // to a particular raster sample.
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index] != 99 {
            return Array(pixels[index..<index+4])
        }
        return [99,99,99,99]
    }

    private static func refractionBasisCases() -> [[Float]] {
        let tilted = SceneParticleOrientationBasis(
            right: SIMD3(sqrt(0.5),0,-sqrt(0.5)), up: SIMD3(0,1,0))
        let turned = SceneParticleOrientationBasis(right: SIMD3(0,1,0), up: SIMD3(-1,0,0))
        let mixed = SIMD3<Float>(0.2,-0.4,0.7)
        let camera = SceneParticleCameraFrame(camera: .init(
            eye: [3,2,5], center: [0,0,0], up: [0,1,0],
            orthoWidth: nil, orthoHeight: nil, fovDegrees: 50,
            perspectiveOverrideFOVDegrees: nil, nearZ: 0.01, farZ: 100),
            viewportSize: CGSize(width: 512,height: 384))
        let canvas = SceneParticleCameraFrame(camera: .init(
            eye: [0,0,0], center: [0,0,-1], up: [0,1,0],
            orthoWidth: 1920, orthoHeight: 1080, fovDegrees: nil,
            perspectiveOverrideFOVDegrees: 50, nearZ: 0.01, farZ: 10000),
            viewportSize: CGSize(width: 512,height: 384))
        let cameraBasis = camera.basis(for: .screen)
        return [
            refractionBasis(),
            refractionBasis(rotation: SIMD3(0,0,Float.pi/2)),
            refractionBasis(rotation: SIMD3(0,0,-Float.pi/2)),
            refractionBasis(rotation: mixed),
            refractionBasis(rotation: SIMD3(Float.pi/4,0,0), basis: tilted),
            refractionBasis(rotation: SIMD3(Float.pi/4,0,0), basis: tilted, viewBasis: tilted),
            refractionBasis(rotation: mixed, viewBasis: tilted),
            refractionBasis(rotation: mixed, basis: turned),
            refractionBasis(rotation: mixed, particleSize: 3, aspect: 0.25,
                model: SceneMatrix.scale(SIMD3(2,3,1))),
            refractionBasis(rotation: mixed, projection: SceneMatrix.perspectiveRHMetal(
                fovYRadians: 1, aspect: 1.5, near: 0.01, far: 100), position: SIMD3(0,0,-5)),
            refractionBasis(rotation: mixed, projection: SceneMatrix.perspectiveRHMetal(
                fovYRadians: 1, aspect: 1.5, near: 0.01, far: 100), position: SIMD3(1,0,-8)),
            refractionBasis(rotation: mixed, basis: cameraBasis, viewBasis: cameraBasis,
                projection: camera.perspectiveViewProjection, position: .zero),
            refractionBasis(rotation: mixed, basis: canvas.basis(for: .screen),
                viewBasis: canvas.basis(for: .screen), particleSize: 200,
                projection: canvas.perspectiveViewProjection, position: SIMD3(960,540,0)),
        ]
    }

    private static func refractionTrailBasisCases() -> [[Float]] {
        [
            refractionBasis(trailVelocity: SIMD3(1,0,0)),
            refractionBasis(model: SceneMatrix.scale(SIMD3(-1,2,1)), trailVelocity: SIMD3(1,0,0)),
            refractionBasis(trailVelocity: SIMD3(1,0,0), joinDirection: SIMD3(0,1,0)),
            refractionBasis(trailVelocity: .zero),
            refractionBasis(particleSize: 0, trailVelocity: SIMD3(1,0,0)),
            refractionBasis(trailVelocity: SIMD3(1,0,0), joinDirection: SIMD3(-1,0,0)),
            refractionBasis(particleSize: 0.0000001, trailVelocity: SIMD3(1,0,0)),
        ]
    }

    private static func refractionContractTest() -> [String: Any] {
        let neutral = refractedCenter(normalX: 128, amount: 0.25)
        let shifted = refractedCenter(normalX: 255, amount: 0.25)
        let trailNeutral = refractedCenter(
            normalX: 128,
            normalY: 128,
            amount: 0.25,
            trailVelocity: SIMD3(1, 0, 0),
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let trailAlong = refractedCenter(
            normalX: 128,
            normalY: 255,
            amount: 0.25,
            trailVelocity: SIMD3(1, 0, 0),
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let trailAcross = refractedCenter(
            normalX: 255,
            normalY: 128,
            amount: 0.25,
            trailVelocity: SIMD3(1, 0, 0),
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let magnitudeNeutral = refractedCenter(
            normalX: 128,
            normalY: 128,
            amount: 0.25,
            trailVelocity: SIMD3(0.4, 0, 0),
            trailStretch: 2,
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let fullSpanShortStretch = refractedCenter(
            normalX: 128,
            normalY: 255,
            amount: 0.25,
            trailVelocity: SIMD3(0.4, 0, 0),
            trailStretch: 2,
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let fullSpanLongStretch = refractedCenter(
            normalX: 128,
            normalY: 255,
            amount: 0.25,
            trailVelocity: SIMD3(0.4, 0, 0),
            trailStretch: 8,
            trailUVRange: SIMD2(0, 1),
            usesTrailDisplacement: true
        )
        let halfSpanLongStretch = refractedCenter(
            normalX: 128,
            normalY: 255,
            amount: 0.25,
            trailVelocity: SIMD3(0.4, 0, 0),
            trailStretch: 8,
            trailUVRange: SIMD2(0.25, 0.75),
            usesTrailDisplacement: true
        )
        return [
            "neutral": neutral,
            "shifted": shifted,
            "maskedOut": refractedCenter(normalX: 255, amount: 0.25, normalMask: 0),
            "halfMask": refractedCenter(normalX: 255, amount: 0.25, normalMask: 128),
            "halfAlpha": refractedCenter(normalX: 255, amount: 0.25, particleAlpha: 0.5),
            "halfMaskHalfAlpha": refractedCenter(normalX: 255, amount: 0.25,
                normalMask: 128, particleAlpha: 0.5),
            "zeroAlpha": refractedCenter(normalX: 255, amount: 0.25, particleAlpha: 0),
            "halfAlbedo": refractedCenter(normalX: 255, amount: 0.25, albedoAlpha: 128),
            "rotatedShiftedX": refractedCenter(normalX: 255, amount: 0.25,
                rotation: SIMD3(0, 0, Float.pi / 2)),
            "reverseRotatedShiftedX": refractedCenter(normalX: 255, amount: 0.25,
                rotation: SIMD3(0, 0, -Float.pi / 2)),
            "tallShiftedX": refractedCenter(normalX: 255, amount: 0.25, spriteAspect: 0.25),
            "squareShiftedY": refractedCenter(normalX: 128, normalY: 255, amount: 0.1),
            "tallShiftedY": refractedCenter(normalX: 128, normalY: 255, amount: 0.1, spriteAspect: 0.25),
            "trailNeutral": trailNeutral,
            "trailAlong": trailAlong,
            "trailAcross": trailAcross,
            "magnitudeNeutral": magnitudeNeutral,
            "fullSpanShortStretch": fullSpanShortStretch,
            "fullSpanLongStretch": fullSpanLongStretch,
            "halfSpanLongStretch": halfSpanLongStretch,
            "budget64MiBAllows4K": SceneFramebufferSnapshot.byteCost(
                width: 3840, height: 2160
            ).map { $0 <= SceneFramebufferSnapshot.defaultByteBudget } ?? false,
            "budget64MiBRejects8K": SceneFramebufferSnapshot.byteCost(
                width: 7680, height: 4320
            ).map { $0 > SceneFramebufferSnapshot.defaultByteBudget } ?? false,
        ]
    }

    private static func refractedCenter(
        normalX: UInt8,
        normalY: UInt8 = 128,
        amount: Float,
        trailVelocity: SIMD3<Float>? = nil,
        trailStretch: Float = 2,
        trailUVRange: SIMD2<Float>? = nil,
        usesTrailDisplacement: Bool = false,
        spriteAspect: Float = 1,
        rotation: SIMD3<Float> = .zero,
        normalMask: UInt8 = 255,
        particleAlpha: Float = 1,
        albedoAlpha: UInt8 = 255
    ) -> [Int] {
        let size = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        targetDescriptor.storageMode = .shared
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: targetDescriptor),
              let color = device.makeTexture(descriptor: inputDescriptor),
              let normal = device.makeTexture(descriptor: inputDescriptor) else { return [] }
        var background = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                background[offset] = UInt8(20 + x * 20)
                background[offset + 1] = UInt8(30 + y * 10)
                background[offset + 2] = 40
                background[offset + 3] = 255
            }
        }
        target.replace(
            region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
            withBytes: &background, bytesPerRow: size * 4
        )
        var white: [UInt8] = [255, 255, 255, albedoAlpha]
        var packedNormal: [UInt8] = [normalMask, normalY, 0, normalX]
        color.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )
        normal.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &packedNormal, bytesPerRow: 4
        )
        guard let captured = pipeline.snapshot(target: target, commandBuffer: command) else {
            return []
        }
        let instances = SceneParticleMetalInstanceBuffer()
        let instance = SceneParticleGPUInstance(
            position: .zero,
            size: 2,
            rotation: rotation,
            color: SIMD3(repeating: 1),
            alpha: particleAlpha,
            velocity: trailVelocity ?? .zero,
            trailStretch: trailVelocity == nil ? nil : trailStretch,
            trailUVRange: trailUVRange,
            usesTrailDisplacement: usesTrailDisplacement,
            currentFrameAspect: spriteAspect
        )
        guard instances.update(device: device, instances: [instance]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        pipeline.drawRefraction(
            texture: color,
            binding: SceneParticleRefractionBinding(
                normalTexture: normal,
                amount: amount,
                overbright: 1,
                colorEncoding: .rgba,
                normalUsesParticleFrames: false,
                normalUVScale: SIMD2(repeating: 1),
                normalSampling: .directImageFallback,
                normalFormat: .rgba8888
            ),
            background: captured,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0), cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            renderState: particleState(.translucent),
            colorUVScale: SIMD2(repeating: 1),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        instances.markSubmitted(on: command)
        guard commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        target.getBytes(
            &pixel, bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, size / 2, 1, 1), mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    private static func samplerPixels() -> [String: Any] {
        [
            "clamp": sampledCenter(
                sampling: SceneParticleTextureSampling(texFlags: 2)
            ),
            "repeat": sampledCenter(
                sampling: SceneParticleTextureSampling(texFlags: 0)
            ),
        ]
    }

    private static func mipSamplerPixels() -> [String: Any] {
        [
            "linear": sampledMipCenter(
                sampling: SceneParticleTextureSampling(texFlags: 2),
                mipmapped: true
            ),
            "nearest": sampledMipCenter(
                sampling: SceneParticleTextureSampling(texFlags: 3),
                mipmapped: true
            ),
            "singleLevel": sampledMipCenter(
                sampling: SceneParticleTextureSampling(texFlags: 2),
                mipmapped: false
            ),
        ]
    }

    private static func sampledMipCenter(
        sampling: SceneParticleTextureSampling,
        mipmapped: Bool
    ) -> [Int] {
        let outputSize = 64
        let inputSize = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: inputSize,
            height: inputSize,
            mipmapped: mipmapped
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: outputSize,
            height: outputSize,
            mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [] }
        for level in 0..<input.mipmapLevelCount {
            let width = max(input.width >> level, 1)
            let height = max(input.height >> level, 1)
            let color: [UInt8] = mipmapped
                ? (level == 0 ? [255, 0, 0, 255] : [0, 255, 0, 255])
                : [0, 0, 255, 255]
            var texels = [UInt8]()
            texels.reserveCapacity(width * height * 4)
            for _ in 0..<(width * height) {
                texels.append(contentsOf: color)
            }
            input.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: level,
                withBytes: &texels,
                bytesPerRow: width * 4
            )
        }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: .zero,
                // Preserve the intended four-pixel minification footprint
                // after the authored-size to GPU-half-size conversion.
                size: 0.125,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 1
            ),
        ]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return []
        }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            renderState: particleState(.translucent),
            colorSampling: sampling,
            encoder: encoder
        )
        encoder.endEncoding()
        instances.markSubmitted(on: command)
        guard commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        output.getBytes(
            &pixel,
            bytesPerRow: outputSize * 4,
            from: MTLRegionMake2D(outputSize / 2, outputSize / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    private static func sampledCenter(
        sampling: SceneParticleTextureSampling
    ) -> [Int] {
        let size = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false
        )
        inputDescriptor.usage = .shaderRead
        inputDescriptor.storageMode = .shared
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let input = device.makeTexture(descriptor: inputDescriptor),
              let output = device.makeTexture(descriptor: outputDescriptor) else { return [] }
        var texels: [UInt8] = [
            0, 255, 0, 255, 0, 255, 0, 255,
            255, 0, 0, 255, 255, 0, 0, 255,
        ]
        input.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: &texels,
            bytesPerRow: 8
        )
        let frame = SceneParticleFrameTransform(
            origin: SIMD2(0, 1),
            xAxis: SIMD2(1, 0),
            yAxis: SIMD2(0, 1)
        )
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [
            SceneParticleGPUInstance(
                position: .zero,
                size: 2,
                rotation: .zero,
                color: SIMD3(repeating: 1),
                alpha: 1,
                currentFrame: frame
            ),
        ]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return []
        }
        pipeline.draw(
            texture: input,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0),
                    cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            renderState: particleState(.translucent),
            colorSampling: sampling,
            encoder: encoder
        )
        encoder.endEncoding()
        instances.markSubmitted(on: command)
        guard commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        output.getBytes(
            &pixel,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, size / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    private static func cullContract() -> [String: [Int]] {
        guard let device = MTLCreateSystemDefaultDevice() else { return [:] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return [:] }
        var white = [UInt8](repeating: 255, count: 4)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
            withBytes: &white, bytesPerRow: 4
        )
        return [
            "frontBackCull": centerPixel(texture: texture, cullMode: .back),
            "reversedBackCull": centerPixel(
                texture: texture, cullMode: .back, reversesWinding: true
            ),
            "reversedNoCull": centerPixel(
                texture: texture, cullMode: .none, reversesWinding: true
            ),
        ]
    }

    /// Draws one full-alpha particle with the given texture and returns the
    /// blended BGRA center pixel, exercising the real sampler and swizzle.
    private static func centerPixel(
        texture: MTLTexture,
        cullMode: SceneParticlePipelineCullMode = .none,
        reversesWinding: Bool = false,
        currentFrame: SceneParticleFrameTransform = .identity,
        nextFrame: SceneParticleFrameTransform? = nil,
        frameMix: Float = 0,
        particleAlpha: Float = 1,
        blendMode: SceneParticlePipelineBlendMode = .translucent,
        background: Float = 0,
        overbright: Float = 1
    ) -> [Int] {
        let size = 8
        guard let device = MTLCreateSystemDefaultDevice(),
              let pipeline = SceneParticleMetalPipeline(device: device),
              let queue = device.makeCommandQueue(),
              let command = queue.makeCommandBuffer() else { return [] }
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false
        )
        outputDescriptor.usage = .renderTarget
        outputDescriptor.storageMode = .shared
        guard let output = device.makeTexture(descriptor: outputDescriptor) else { return [] }
        let instances = SceneParticleMetalInstanceBuffer()
        guard instances.update(device: device, instances: [SceneParticleGPUInstance(
            position: .zero, size: 2, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: particleAlpha,
            currentFrame: currentFrame, nextFrame: nextFrame, frameMix: frameMix
        )]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(Double(background), Double(background), Double(background), 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        pipeline.draw(
            texture: texture,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientationBasis(
                    right: SIMD3(reversesWinding ? -1 : 1, 0, 0),
                    up: SIMD3(0, 1, 0)
                )
            ),
            renderState: SceneParticlePipelineRenderState(blendMode: blendMode, cullMode: cullMode, overbright: overbright),
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        instances.markSubmitted(on: command)
        guard commitAndWait(command) else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        output.getBytes(
            &pixel,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(size / 2, size / 2, 1, 1),
            mipmapLevel: 0
        )
        return pixel.map(Int.init)
    }

    private static func instance(x: Float, z: Float = 0) -> SceneParticleGPUInstance {
        SceneParticleGPUInstance(
            position: SIMD3(x, 0, z), size: 1, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: 1
        )
    }

    private static func commitAndWait(_ command: MTLCommandBuffer) -> Bool {
        let completion = DispatchSemaphore(value: 0)
        command.addCompletedHandler { _ in completion.signal() }
        command.commit()
        return completion.wait(timeout: .now() + 5) == .success && command.status == .completed
    }
}
'''


class SceneParticleRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-render-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-render"
        subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-framework", "Metal", "-o", str(cls.binary),
            ],
            check=True, capture_output=True, text=True,
        )
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_sprite_rotation_matches_authored_basis_sign_and_mixed_axis_order(self) -> None:
        # Public stock ComputeParticleTangents through the existing production
        # normalizer + glslang/SPIRV-Cross was read back on Metal. Positive Z
        # turns the right vector toward -Y; (.2,-.4,.7) produces basis right
        # (.754306,-.631376,-.179960), up (.534191,.749596,-.390826).
        clockwise = self.result["clockwiseSpriteMarkers"]
        counterclockwise = self.result["counterclockwiseSpriteMarkers"]
        for value in [clockwise, counterclockwise]:
            self.assertEqual([value["width"], value["height"]], [128, 32])
            self.assertEqual([value["centerX2"], value["centerY2"]], [287, 319])
            self.assertAlmostEqual(value["redX1000"], value["greenX1000"], delta=1000)
        self.assertLess(clockwise["redY1000"], clockwise["greenY1000"])
        self.assertGreater(counterclockwise["redY1000"], counterclockwise["greenY1000"])
        mixed = self.result["mixedAxisSpriteMarkers"]
        self.assertAlmostEqual(mixed["width"], 32 * .754306 + 128 * .534191, delta=2)
        self.assertAlmostEqual(mixed["height"], 32 * .631376 + 128 * .749596, delta=2)
        self.assertAlmostEqual(mixed["greenX1000"] - mixed["redX1000"], 16 * .754306 * 1000, delta=1000)
        self.assertAlmostEqual(mixed["greenY1000"] - mixed["redY1000"], 16 * .631376 * 1000, delta=1000)
        self.assertEqual([mixed["centerX2"], mixed["centerY2"]], [287, 319])
        oriented = self.result["orientedSpriteMarkers"]
        self.assertEqual([oriented["width"], oriented["height"]], [32, 128])
        self.assertLess(oriented["redX1000"], oriented["greenX1000"])
        self.assertAlmostEqual(oriented["redY1000"], oriented["greenY1000"], delta=1000)
        refract = self.result["refractionContract"]
        self.assertEqual(refract["rotatedShiftedX"], [100, 90, 40, 255])
        self.assertEqual(refract["reverseRotatedShiftedX"], [100, 50, 40, 255])

    def test_fixed_sprite_geometry_preserves_full_model_transform(self) -> None:
        results = [r for r in self.result["fixedGeometry"] if not r["mode"].startswith("localScreen")]
        if not results:
            self.skipTest("Metal vertex readback is unavailable")
        oracle = json.loads((REPOSITORY_ROOT / "script/tests/fixtures/scene_particle_fixed_geometry.json").read_text())
        self.assertEqual(len(results), len(oracle["cases"]))
        for actual, expected in zip(results, oracle["cases"]):
            with self.subTest(mode=expected["mode"], case=expected["name"]):
                self.assertEqual((actual["name"], actual["mode"]), (expected["name"], expected["mode"]))
                # Full vertex positions cover reflection, shear, signed depth,
                # arbitrary fixed axes, translation, and singular transforms.
                # Existing world-size/world-fixed/world-screen/upright modes and
                # normalized refraction direction are explicit controls.
                for field in ["positions", "tangents"]:
                    for av, ev in zip(actual[field], expected[field]):
                        for a, e in zip(av, ev):
                            self.assertAlmostEqual(a, e, delta=0.00002)

    def test_local_screen_singular_geometry_keeps_gpu_outputs_finite(self) -> None:
        results = [r for r in self.result["fixedGeometry"] if r["mode"].startswith("localScreen")]
        self.assertEqual(len(results), 26)
        for row in results:
            with self.subTest(mode=row["mode"], case=row["name"]):
                for field in ["positions", "tangents"]:
                    self.assertTrue(all(math.isfinite(v) for values in row[field] for v in values))
        collapsed = next(r for r in results if r["mode"] == "localScreen" and r["name"] == "parallelXY")
        self.assertTrue(all(abs(p[0] - 0.1) < 0.00002 for p in collapsed["positions"]))

    def test_cpu_and_msl_instance_layouts_match(self) -> None:
        self.assertEqual(self.result["instanceStride"], 160)
        self.assertEqual(self.result["instanceAlignment"], 16)
        self.assertEqual(self.result["instanceOffsets"], [0, 16, 32, 48, 64, 80, 96, 112, 128, 144])
        self.assertEqual(self.result["uniformStride"], 256)
        self.assertEqual(self.result["uniformOffsets"], [0, 64, 128, 144, 160, 168, 176, 192, 208, 224, 240])

    def test_lifetime_sprite_selection_and_frame_blending(self) -> None:
        self.assertEqual(self.result["sequence"]["current"], 2)
        self.assertTrue(self.result["finiteExtremesAreSafe"])
        self.assertTrue(self.result["invalidPhasesRejected"])
        self.assertEqual(self.result["sequence"]["next"], 2)
        self.assertAlmostEqual(self.result["sequence"]["mix"], 0.5, places=6)
        self.assertEqual(self.result["preparedTimeline"], self.result["sequence"])
        self.assertEqual(self.result["noBlend"], {"current": 2, "next": 2, "mix": 0})
        self.assertEqual(self.result["reverse"], self.result["sequence"])
        self.assertGreater(len(set(self.result["randomIndices"])), 1)
        self.assertTrue(self.result["randomNoBlend"])
        self.assertTrue(self.result["modeSequence"])
        self.assertTrue(self.result["modeRandom"])

    def test_sequence_last_frame_holds_until_cycle_boundary_on_gpu(self) -> None:
        rows = self.result["sequenceEndPixels"]
        self.assertEqual(len(rows), 24)
        for row in rows:
            with self.subTest(prepared=row["prepared"], blend=row["blend"], age=row["age"]):
                phase = row["age"] % 1
                blue = 1 if phase >= 0.5 else (phase * 2 if row["blend"] else 0)
                expected = [255 * blue, 0, 255 * (1 - blue), 255]
                self.assertEqual(len(row["bgra"]), 4)
                for actual, wanted in zip(row["bgra"], expected):
                    self.assertAlmostEqual(actual, wanted, delta=2)

    def test_orientation_bases_are_authored_and_orthonormal(self) -> None:
        self.assertTrue(self.result["orientationDefault"])
        self.assertEqual(self.result["trailFrame"], [0, 1, 0, -1, 1, 0])
        self.assertEqual(self.result["screenRight"], [1, 0, 0])
        self.assertEqual(self.result["screenUp"], [0, 1, 0])
        self.assertEqual(self.result["uprightRight"], [1, 0, 0])
        self.assertEqual(self.result["uprightUp"], [0, -1, 0])
        self.assertEqual(self.result["fixedRight"], [0, 1, 0])
        self.assertEqual(self.result["fixedUp"], [0, 0, 1])
        self.assertNotEqual(self.result["localFixedRight"], self.result["worldFixedRight"])
        self.assertEqual(self.result["worldFixedRight"], [1, 0, 0])
        self.assertEqual(self.result["worldFixedUp"], [0, -1, 0])

    def test_metal_right_handed_perspective_matches_scene_camera(self) -> None:
        self.assertAlmostEqual(self.result["nearNDC"][2], 0, places=5)
        self.assertAlmostEqual(self.result["farNDC"][2], 1, places=5)
        for actual, expected in zip(self.result["sceneCenterNDC"], [0, 0, 0.99992]):
            self.assertAlmostEqual(actual, expected, places=4)
        for actual, expected in zip(self.result["sceneTopRightNDC"][:2], [1, 1]):
            self.assertAlmostEqual(actual, expected, places=5)
        self.assertTrue(self.result["invalidPerspectiveIsIdentity"])

    def test_both_blend_states_compile_and_encode_instanced_draws(self) -> None:
        self.assertEqual(self.result["translucentBlend"], [True, True, True, True])
        self.assertEqual(self.result["additiveBlend"], [True, True, True, True])
        self.assertTrue(self.result["metalDraw"])

    def test_additive_fractional_alpha_is_applied_once(self) -> None:
        pixel = self.result["additiveFractionalAlphaPixel"]
        if not pixel:
            self.skipTest("Metal offscreen draw is unavailable")
        for channel in pixel:
            self.assertAlmostEqual(channel, 64, delta=2)

    def test_depth_state_rejects_far_fragment_and_overbright_scales_rgb_only(self) -> None:
        pixel = self.result["depthAndOverbrightPixel"]
        if not pixel:
            self.skipTest("Metal depth draw is unavailable")
        self.assertEqual(pixel[0], 0)
        self.assertEqual(pixel[1], 0)
        self.assertAlmostEqual(pixel[2], 128, delta=2)
        self.assertEqual(pixel[3], 255)
        self.assertEqual(
            self.result["depthTargetLease"],
            {
                "rejectsFourth": True,
                "reusesReleased": True,
                "completionReleased": True,
            },
        )

    def test_non_square_sprite_geometry_tracks_current_and_blended_frame_aspect(self) -> None:
        wide = self.result["spriteAspectBounds"]
        blended = self.result["blendedSpriteAspectBounds"]
        if not wide or not blended:
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertGreater(wide["width"], wide["height"] * 1.8)
        self.assertGreater(blended["width"], blended["height"] * 1.1)
        self.assertLess(blended["width"], blended["height"] * 1.4)

    def test_sprite_size_is_width_based_and_center_does_not_move(self) -> None:
        square = self.result["squareSpriteBounds"]
        wide = self.result["spriteAspectBounds"]
        tall = self.result["tallSpriteBounds"]
        rotated = self.result["rotatedTallSpriteBounds"]
        scaled = self.result["scaledTallSpriteBounds"]
        blended = self.result["blendedSpriteAspectBounds"]
        self.assertTrue(square, "Metal GPU readback is required")
        self.assertEqual([square["width"], square["height"]], [32, 32])
        self.assertEqual([wide["width"], wide["height"]], [32, 16])
        self.assertEqual([tall["width"], tall["height"]], [32, 128])
        self.assertEqual([rotated["width"], rotated["height"]], [128, 32])
        self.assertEqual([scaled["width"], scaled["height"]], [64, 64])
        self.assertEqual(blended["width"], 32)
        self.assertAlmostEqual(blended["height"], 32 / 1.25, delta=1)
        for value in [wide, tall, rotated, blended]:
            self.assertEqual(value["centerX2"], square["centerX2"])
            self.assertEqual(value["centerY2"], square["centerY2"])
        self.assertEqual([scaled["centerX2"], scaled["centerY2"]], [191, 287])

    def test_normal_cull_maps_to_back_faces_and_nocull_remains_two_sided(self) -> None:
        contract = self.result["cullContract"]
        if not contract.get("frontBackCull"):
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertGreater(contract["frontBackCull"][3], 240)
        self.assertEqual(contract["reversedBackCull"], [0, 0, 0, 0])
        self.assertGreater(contract["reversedNoCull"][3], 240)

    def test_upright_preserves_system_or_world_axis_under_camera_roll(self) -> None:
        contract = self.result["uprightGeometry"]
        rows = contract["rows"]
        for name, row in rows.items():
            with self.subTest(name=name):
                self.assertEqual(row["pixels"], row["expectedPixels"])
                self.assertGreater(row["pixels"]["width"], 0)
                self.assertGreater(row["pixels"]["height"], 0)
        for roll in [0, 89, 90, 91, 180]:
            for prefix in ["roll", "localRoll", "projectedRoll"]:
                self.assertEqual(rows[f"{prefix}{roll}"]["right"], [1, 0, 0])
                self.assertEqual(rows[f"{prefix}{roll}"]["up"], [0, -1, 0])
        for name in ["localRotated", "localScaled"]:
            for actual, expected in zip(rows[name]["up"], [1, 0, 0]):
                self.assertAlmostEqual(actual, expected, places=5)
        self.assertEqual(rows["worldRotated"]["up"], [0, -1, 0])
        self.assertEqual(rows["localMirrored"]["up"], [0, 1, 0])
        self.assertTrue(contract["fixedDirectionsUnchanged"])
        for actual, expected in zip(rows["screenRotated"]["up"], [1, 0, 0]):
            self.assertAlmostEqual(actual, expected, places=5)
        self.assertEqual(rows["screenWorldRotated"]["up"], [0, -1, 0])
        self.assertGreater(rows["screenRotated"]["pixels"]["width"],
                           rows["screenRotated"]["pixels"]["height"])
        self.assertAlmostEqual(rows["screenTilted"]["up"][1], -0.5, places=5)
        self.assertAlmostEqual(contract["screenRolledUp"][0], 1, places=5)

    def test_upright_sprite_trail_renders_under_roll_and_tilt(self) -> None:
        trails = self.result["uprightGeometry"]["trails"]
        for name, metrics in trails.items():
            with self.subTest(name=name):
                if name == "pole":
                    # The vertical card is viewed exactly edge-on; GPU completes
                    # and retains the clear target, without invented thickness.
                    self.assertEqual(metrics, {"width": 0, "height": 0})
                else:
                    self.assertGreater(metrics["width"], 0)
                    self.assertGreater(metrics["height"], 0)
                    self.assertLess(metrics["width"], 256)
                    self.assertLess(metrics["height"], 256)

    def test_upright_parallel_view_fallback_keeps_authoritative_axis(self) -> None:
        contract = self.result["uprightGeometry"]
        for prefix in ["pole", "degenerate"]:
            self.assertEqual(contract[f"{prefix}Right"], [1, 0, 0])
            self.assertEqual(contract[f"{prefix}Up"], [0, -1, 0])
        self.assertEqual(contract["rows"]["zeroAxis"]["up"], [0, -1, 0])

    def test_sprite_trails_align_and_stretch_along_velocity(self) -> None:
        horizontal = self.result["horizontalTrailBounds"]
        vertical = self.result["verticalTrailBounds"]
        rotated = self.result["rotatedTrailBounds"]
        self.assertGreater(horizontal["width"], horizontal["height"] * 2.5)
        self.assertGreater(vertical["height"], vertical["width"] * 2.5)
        self.assertGreater(rotated["height"], rotated["width"] * 2.5)

    def test_numeric_and_text_rotation_reach_distinct_gpu_geometry(self) -> None:
        numeric = self.result["numericRotationBounds"]
        text = self.result["textRotationBounds"]
        self.assertGreater(numeric["width"], 0)
        self.assertEqual(numeric, self.result["explicitZRotationBounds"])
        self.assertEqual(text, self.result["explicitXRotationBounds"])
        self.assertNotEqual(numeric, text)
        self.assertNotEqual(numeric, self.result["broadcastRotationBounds"])

    def test_omitted_trail_bounds_change_actual_gpu_extent_with_speed(self) -> None:
        bounds = self.result["defaultTrailBounds"]
        self.assertEqual(bounds["omitted"], bounds["explicit"])
        widths = [item["width"] for item in bounds["omitted"]]
        self.assertGreater(widths[1], widths[0] + 3)
        self.assertGreater(widths[2], widths[1] + 3)
        self.assertEqual(len({item["height"] for item in bounds["omitted"]}), 1)
        self.assertEqual(len({item["width"] for item in bounds["fixed"]}), 1)
        self.assertGreater(bounds["fixed"][0]["width"], 0)

    def test_general_worldspace_size_is_independent_of_layer_scale(self) -> None:
        baseline = self.result["worldIdentityWidth"]
        world = self.result["worldScaledWidth"]
        local = self.result["localScaledWidth"]
        mirror = self.result["worldMirroredWidth"]
        override = self.result["worldSizeOverrideWidth"]
        self.assertGreater(baseline["height"], 0)
        self.assertEqual(world["height"], baseline["height"])
        self.assertEqual(mirror["height"], baseline["height"])
        self.assertGreater(local["height"], world["height"] * 8)
        self.assertGreater(world["width"], baseline["width"] * 8)
        self.assertGreater(override["height"], world["height"] * 3)

    def test_rope_trail_joins_have_no_gap_or_double_alpha(self) -> None:
        results = self.result["ropeTrailJoins"]
        self.assertEqual(len(results), 5)
        for result in results:
            with self.subTest(transform=result.get("transform")):
                self.assertTrue(result["completed"])
                self.assertTrue(result["jointCovered"])
                self.assertGreater(result["visiblePixels"], 1000)
                self.assertLessEqual(result["maximumAlpha"], 129)

    def test_rope_particle_joins_have_no_gap_or_double_alpha(self) -> None:
        results = self.result["ropeJoins"]
        self.assertEqual(len(results), 7)
        for result in results:
            with self.subTest(transform=result.get("transform")):
                self.assertTrue(result["completed"])
                self.assertTrue(result["jointCovered"])
                self.assertGreater(result["visiblePixels"], 1000)
                self.assertLessEqual(result["maximumAlpha"], 129)
        taper = results[5]["columnWidths"]
        self.assertLess(taper[0], taper[1])
        self.assertLess(taper[1], taper[2])
        self.assertGreater(taper[2], taper[3])
        self.assertGreater(taper[3], taper[4])
        self.assertLessEqual(taper[4], 2)

    def test_rope_trail_history_draws_a_multisegment_fading_path(self) -> None:
        contract = self.result["ropeTrailRender"]
        if not contract["available"]:
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertEqual(contract["instanceCount"], 4)
        self.assertEqual(contract["horizontalSegments"], 2)
        self.assertEqual(contract["verticalSegments"], 2)
        self.assertGreater(contract["width"], 45)
        self.assertGreater(contract["height"], 45)
        self.assertGreater(contract["visiblePixels"], 400)
        self.assertGreater(contract["headAlpha"], contract["tailAlpha"] * 2)

    def test_rope_segment_endpoints_follow_the_transformed_history_displacement(self) -> None:
        contract = self.result["ropeTrailTransform"]
        if not contract["available"]:
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertGreater(contract["visiblePixels"], 100)
        pixel_tolerance = 5 / 256 * 2
        self.assertLessEqual(
            abs(contract["observedTail"] - contract["expectedTail"]),
            pixel_tolerance,
        )
        self.assertLessEqual(
            abs(contract["observedHead"] - contract["expectedHead"]),
            pixel_tolerance,
        )

    def test_diagonal_rope_cross_section_is_perpendicular_in_wide_viewport_pixels(self) -> None:
        contract = self.result["ropeTrailAspect"]
        if not contract["available"]:
            self.skipTest("Metal offscreen draw is unavailable")
        self.assertGreater(contract["visiblePixels"], 100)
        self.assertGreater(contract["varianceRatio"], 4)
        self.assertGreater(contract["legacyAbsoluteDot"], 0.35)
        self.assertLess(contract["absoluteDot"], 0.12)

    def test_color_contract_adapts_r8_and_rg88_particle_textures(self) -> None:
        contract = self.result["colorContract"]
        raw = contract["rawR8"]
        adapted = contract["adaptedR8"]
        if not raw or not adapted:
            self.skipTest("Metal offscreen draw is unavailable")
        # 未适配的 r8Unorm 采样得 (r,0,0,1):BGRA 读回蓝/绿为 0、红为灰度。
        self.assertEqual(raw[0], 0)
        self.assertEqual(raw[1], 0)
        self.assertGreater(raw[2], 150)
        # R8 straight white/alpha becomes premultiplied white at the fragment boundary.
        self.assertGreater(adapted[0], 150)
        self.assertEqual(adapted[0], adapted[1])
        self.assertEqual(adapted[1], adapted[2])
        self.assertEqual(adapted[2], adapted[3])
        self.assertEqual(contract["rgMipCount"], 2)
        self.assertEqual(contract["rgPixel"], [128, 128, 128, 128])
        self.assertEqual(contract["rgSecondMip"], [16, 16, 16, 64])

    def test_straight_color_filtering_precedes_texture_coverage(self) -> None:
        rows = self.result["straightInterpolation"]
        self.assertEqual(len(rows), 160)
        for row in rows:
            with self.subTest(**{k: v for k, v in row.items() if k != "bgra"}):
                t, a = row["mix"], row["alpha"]
                coverage = t * a
                background = row["background"] * (1 if row["additive"] else 1 - coverage)
                gain = coverage * row["overbright"]
                expected = [(t * gain + background) * 255, background * 255,
                            ((1 - t) * gain + background) * 255, coverage * 255]
                self.assertEqual(len(row["bgra"]), 4)
                for observed, value in zip(row["bgra"], expected):
                    self.assertAlmostEqual(observed, min(255, value), delta=2)

    def test_in_flight_instance_slots_are_not_reused_until_completion(self) -> None:
        slots = self.result["instanceBufferSlots"]
        self.assertTrue(slots["available"])
        self.assertTrue(slots["firstSubmitted"])
        self.assertTrue(slots["secondSubmitted"])
        self.assertTrue(slots["thirdSubmitted"])
        self.assertTrue(slots["firstPreserved"])
        self.assertTrue(slots["grewForSecond"])
        self.assertTrue(slots["grewForThird"])
        self.assertTrue(slots["firstCompleted"])
        self.assertTrue(slots["reusedFirst"])
        self.assertTrue(slots["cleanupCompleted"])

    def test_uncommitted_particle_slots_are_cancelled_and_reusable(self) -> None:
        slots = self.result["instanceBufferPendingCancellation"]
        self.assertTrue(slots["available"])
        self.assertTrue(slots["pendingCancelled"])
        self.assertTrue(slots["pendingCleared"])
        self.assertTrue(slots["reusedAfterPending"])
        self.assertTrue(slots["marked"])
        self.assertTrue(slots["uncommittedCancelled"])
        self.assertTrue(slots["uncommittedCleared"])
        self.assertTrue(slots["reusedAfterSubmissionCancel"])
        self.assertTrue(slots["idempotentCancel"])
        self.assertTrue(slots["cancelInFlightRejected"])
        self.assertTrue(slots["inFlightCountPreserved"])
        self.assertTrue(slots["cancelAfterCompletionRejected"])
        self.assertTrue(slots["reusedAfterCompletion"])

    def test_refraction_mask_and_particle_alpha_attenuate_displacement(self) -> None:
        value = self.result["refractionContract"]
        # The 8x8 framebuffer has a 20/texel blue gradient. Full displacement
        # is two texels (amount 0.25 screen UV). Mask changes the sampled location; particle alpha
        # changes both location and compositing coverage. Albedo alpha only
        # changes coverage. These are independent authored channels.
        expected = {
            "maskedOut": 100, "halfMask": 120, "halfAlpha": 110,
            "halfMaskHalfAlpha": 105, "zeroAlpha": 100, "halfAlbedo": 120,
        }
        for name, blue in expected.items():
            with self.subTest(name=name):
                self.assertEqual(len(value[name]), 4)
                self.assertLessEqual(abs(value[name][0] - blue), 1)
                self.assertLessEqual(abs(value[name][1] - 70), 1)
                self.assertEqual(value[name][2:], [40, 255])

    def test_refraction_samples_the_preceding_framebuffer_with_bounded_snapshot(self) -> None:
        contract = self.result["refractionContract"]
        neutral = contract["neutral"]
        shifted = contract["shifted"]
        if not neutral or not shifted:
            self.skipTest("Metal refraction draw is unavailable")
        # The center's original BGRA is [100,70,40,255]. A neutral normal must
        # preserve it; +X moves the sampled blue gradient toward larger values.
        self.assertLessEqual(max(abs(a - b) for a, b in zip(
            neutral, [100, 70, 40, 255]
        )), 2)
        self.assertGreater(shifted[0], neutral[0] + 15)
        self.assertEqual(shifted[1], neutral[1])
        self.assertTrue(contract["budget64MiBAllows4K"])
        self.assertTrue(contract["budget64MiBRejects8K"])

    def test_rope_trail_refraction_rotates_normal_axes_into_path_space(self) -> None:
        contract = self.result["refractionContract"]
        neutral = contract["trailNeutral"]
        along = contract["trailAlong"]
        across = contract["trailAcross"]
        if not neutral or not along or not across:
            self.skipTest("Metal refraction draw is unavailable")
        # Public REFRACT packing combines both particle axes against each
        # view axis. For rightward trail geometry, +normalY samples left;
        # +normalX samples down. It is not the UV-to-position Jacobian.
        self.assertLess(along[0], neutral[0] - 15)
        self.assertLessEqual(abs(along[1] - neutral[1]), 2)
        self.assertGreater(across[1], neutral[1] + 8)
        self.assertLessEqual(abs(across[0] - neutral[0]), 2)

    def test_sprite_refraction_amount_is_independent_of_texture_aspect(self) -> None:
        value = self.result["refractionContract"]
        self.assertTrue(value["tallShiftedX"])
        self.assertEqual(value["tallShiftedX"], value["shifted"])
        self.assertEqual(value["squareShiftedY"], value["tallShiftedY"])
        self.assertGreater(value["squareShiftedY"][1], value["neutral"][1])

    def test_rope_trail_refraction_amount_is_independent_of_uv_span_and_stretch(self) -> None:
        value = self.result["refractionContract"]
        self.assertTrue(value["fullSpanShortStretch"])
        self.assertLess(value["fullSpanShortStretch"][0], value["magnitudeNeutral"][0] - 15)
        self.assertEqual(value["fullSpanShortStretch"], value["fullSpanLongStretch"])
        self.assertEqual(value["fullSpanShortStretch"], value["halfSpanLongStretch"])

    def test_refraction_basis_matches_public_shader_direction_contract(self) -> None:
        # RGBA32Float oracle from public ComputeParticleTangents and
        # ComputeScreenRefractionTangents through the production compiler.
        expected = [
            [1,0,0,1], [0,1,-1,0], [0,-1,1,0],
            [.75430655,.53419143,-.63137633,.74959618],
            [.70710677,-.5,0,.70710677], [1,0,0,.70710677],
            [.66062647,.65408611,-.63137633,.74959618],
            [.63137633,-.74959624,.75430655,.53419149],
        ]
        actual = self.result["refractionBasisCases"]
        self.assertEqual(len(actual), 13)
        # Size, aspect, anisotropic layer scale, position and projection depth
        # do not set Sprite REFRACT strength. A tilted native camera supplies
        # its own view basis, independent of the fixed particle orientation.
        expected += [expected[3]] * 5
        for index, (observed, reference) in enumerate(zip(actual, expected)):
            with self.subTest(index=index):
                self.assertEqual(len(observed), 4)
                for component, target in zip(observed, reference):
                    self.assertAlmostEqual(component, target, delta=0.00001)

    def test_trail_refraction_directions_remain_bounded_at_joins_and_collapses(self) -> None:
        values = self.result["refractionTrailBasisCases"]
        self.assertEqual(len(values), 7)
        for value in values[:3]:
            self.assertEqual(len(value), 4)
            self.assertTrue(all(-1.00001 <= component <= 1.00001 for component in value))
        for actual, expected in zip(values[:2], [[0,1,-1,0],[0,-1,1,0]]):
            for component, target in zip(actual, expected):
                self.assertAlmostEqual(component, target, delta=0.00001)
        # Completed zero-area geometry leaves the clear target untouched.
        # Failure to compile/encode/complete returns [] instead of this marker.
        for value in values[3:]:
            self.assertEqual(value, [99,99,99,99])

    def test_tex_flags_select_filter_and_address_modes_without_cross_talk(self) -> None:
        values = self.result["texSampling"]
        self.assertEqual(values["default"], {
            "filter": "linear",
            "address": "clampToEdge",
            "clampBorderFallback": False,
        })
        self.assertEqual(values["flags0"], {
            "filter": "linear",
            "address": "repeatWrap",
            "clampBorderFallback": False,
        })
        self.assertEqual(values["flags1"]["filter"], "nearest")
        self.assertEqual(values["flags1"]["address"], "repeatWrap")
        self.assertEqual(values["flags2"]["filter"], "linear")
        self.assertEqual(values["flags2"]["address"], "clampToEdge")
        self.assertEqual(values["flags3"]["filter"], "nearest")
        self.assertEqual(values["flags3"]["address"], "clampToEdge")
        self.assertEqual(values["flags4"], values["flags0"])
        self.assertEqual(values["alphaPriority"], values["flags0"])
        self.assertEqual(values["flags8"]["address"], "clampToEdge")
        self.assertTrue(values["flags8"]["clampBorderFallback"])

    def test_repeat_sampler_restores_sprite_frame_uvs_beyond_one(self) -> None:
        pixels = self.result["samplerPixels"]
        clamp = pixels["clamp"]
        repeat = pixels["repeat"]
        if not clamp or not repeat:
            self.skipTest("Metal sampler draw is unavailable")
        # Frame UV V=1...2:clamp collapses onto the red lower edge,repeat wraps
        # into the green/red atlas instead of stretching that edge across the quad.
        self.assertGreater(clamp[2], 240)
        self.assertLess(clamp[1], 5)
        self.assertGreater(repeat[1], clamp[1] + 40)
        self.assertNotEqual(repeat, clamp)

    def test_sampler_uses_authored_mip_chain_and_preserves_single_level_textures(
        self,
    ) -> None:
        pixels = self.result["mipSamplerPixels"]
        linear = pixels["linear"]
        nearest = pixels["nearest"]
        single_level = pixels["singleLevel"]
        if not linear or not nearest or not single_level:
            self.skipTest("Metal mip sampler draw is unavailable")
        # BGRA: the minified multi-level texture selects green lower mips,
        # while the single-level texture remains blue at LOD0.
        self.assertGreater(linear[1], 240)
        self.assertLess(linear[2], 5)
        self.assertGreater(nearest[1], 240)
        self.assertLess(nearest[2], 5)
        self.assertGreater(single_level[0], 240)
        self.assertLess(single_level[1], 5)


if __name__ == "__main__":
    unittest.main()
