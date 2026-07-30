#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Rendering/SceneMatrix.swift",
    SOURCE_ROOT / "Rendering/SceneFramebufferSnapshot.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleRenderSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleSimulationSupport.swift",
    SOURCE_ROOT / "Particles/SceneParticleStepSnapshotRecorder.swift",
    SOURCE_ROOT / "Particles/SceneParticleRopeTrailPlan.swift",
    SOURCE_ROOT / "Particles/SceneParticleMetalInstanceBuffer.swift",
    SOURCE_ROOT / "Particles/SceneParticleRefractionBinding.swift",
    SOURCE_ROOT / "Particles/SceneParticleShaderSource.swift",
    SOURCE_ROOT / "Particles/SceneParticleSamplerStateSet.swift",
    SOURCE_ROOT / "Particles/SceneParticleMetalPipeline.swift",
    SOURCE_ROOT / "Particles/SceneParticleTextureSource.swift",
]


HARNESS_SOURCE = r'''
import Foundation
import Dispatch
import Metal
import simd

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
            "uniformStride": MemoryLayout<SceneParticleLayerUniforms>.stride,
            "uniformOffsets": uniformOffsets(),
            "sequence": selection(sequence),
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
            // additive 源因子取 sourceAlpha:shader 输出已是 premultiplied,再乘一次
            // 粒子 alpha 对齐官方 CPU premultiply + (SRC_ALPHA, ONE) 的 additive 合同
            //(官方 genericparticle.frag 输出 straight,作者靠 alpha 调 additive 强度)。
            "additiveBlend": [
                additive.sourceRGB == .sourceAlpha,
                additive.destinationRGB == .one,
                additive.sourceAlpha == .one,
                additive.destinationAlpha == .oneMinusSourceAlpha,
            ],
            "metalDraw": renderSmokeTest(),
            "horizontalTrailBounds": trailBounds(velocity: SIMD3(1, 0, 0)),
            "verticalTrailBounds": trailBounds(velocity: SIMD3(0, 1, 0)),
            "rotatedTrailBounds": trailBounds(
                velocity: SIMD3(1, 0, 0),
                layerModel: simd_float4x4(columns: (
                    SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0),
                    SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
                ))
            ),
            "ropeTrailRender": ropeTrailRenderContract(),
            "ropeTrailTransform": ropeTrailTransformContract(),
            "ropeTrailAspect": ropeTrailAspectContract(),
            "instanceBufferSlots": instanceBufferSlotTest(),
            "colorContract": colorContractTest(),
            "refractionContract": refractionContractTest(),
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
        let basis = SceneParticleOrientation.screen.basis(
            cameraRight: SIMD3(1, 0, 0), cameraUp: SIMD3(0, 1, 0),
            cameraForward: SIMD3(0, 0, -1)
        )
        pipeline.draw(
            texture: input, instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(), basis: basis
            ),
            blendMode: .translucent,
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        pipeline.draw(
            texture: input, instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(), basis: basis
            ),
            blendMode: .additive,
            colorSampling: .directImageFallback,
            encoder: encoder
        )
        encoder.endEncoding()
        let submitted = instances.markSubmitted(on: command)
        let completed = commitAndWait(command)
        return submitted && completed && command.status == .completed && instances.count == 2
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

    private static func ropeTrailRenderContract() -> [String: Any] {
        let definition = SceneParticleDefinitionParser().parse(root: [
            "material": "materials/particle.json",
            "maxcount": 1,
            "emitter": [["name": "sphererandom"]],
            "renderer": [[
                "name": "ropetrail",
                "length": 1,
                "segments": 4,
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
                    size: 0.12,
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
            blendMode: .translucent,
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
            blendMode: .translucent,
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
            blendMode: .translucent,
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

    private static func trailBounds(
        velocity: SIMD3<Float>,
        layerModel: simd_float4x4 = SceneMatrix.identity()
    ) -> [String: Int] {
        let size = 64
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
            position: .zero, size: 0.2, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: 1,
            velocity: velocity, trailStretch: 4
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
                viewProjection: SceneMatrix.identity(),
                layerModel: layerModel,
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0), cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            blendMode: .translucent,
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
        let adaptedR8 = centerPixel(
            texture: SceneParticleColorTextureAdapter.adapt(r8, device: device)
        )

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
        let adaptedRG = SceneParticleColorTextureAdapter.adapt(rg, device: device)
        var expanded = [UInt8](repeating: 0, count: 4)
        var expandedSecondMip = [UInt8](repeating: 0, count: 4)
        if adaptedRG.pixelFormat == .rgba8Unorm {
            adaptedRG.getBytes(
                &expanded,
                bytesPerRow: adaptedRG.width * 4,
                from: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0
            )
            adaptedRG.getBytes(
                &expandedSecondMip,
                bytesPerRow: 4,
                from: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 1
            )
        }
        return [
            "rawR8": rawR8,
            "adaptedR8": adaptedR8,
            "rgExpandedFormatIsRGBA": adaptedRG.pixelFormat == .rgba8Unorm,
            "rgExpandedMipCount": adaptedRG.mipmapLevelCount,
            "rgExpandedPixel": expanded.map(Int.init),
            "rgExpandedSecondMip": expandedSecondMip.map(Int.init),
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
        usesTrailDisplacement: Bool = false
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
        var white: [UInt8] = [255, 255, 255, 255]
        var packedNormal: [UInt8] = [0, normalY, 0, normalX]
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
            rotation: .zero,
            color: SIMD3(repeating: 1),
            alpha: 1,
            velocity: trailVelocity ?? .zero,
            trailStretch: trailVelocity == nil ? nil : trailStretch,
            trailUVRange: trailUVRange,
            usesTrailDisplacement: usesTrailDisplacement
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
                normalSampling: .directImageFallback
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
            blendMode: .translucent,
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
                size: 0.0625,
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
            blendMode: .translucent,
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
            blendMode: .translucent,
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

    /// Draws one full-alpha particle with the given texture and returns the
    /// blended BGRA center pixel, exercising the real sampler and swizzle.
    private static func centerPixel(texture: MTLTexture) -> [Int] {
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
            color: SIMD3(repeating: 1), alpha: 1
        )]) else { return [] }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return [] }
        pipeline.draw(
            texture: texture,
            instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(),
                basis: SceneParticleOrientation.screen.basis(
                    cameraRight: SIMD3(1, 0, 0), cameraUp: SIMD3(0, 1, 0),
                    cameraForward: SIMD3(0, 0, -1)
                )
            ),
            blendMode: .translucent,
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

    private static func instance(x: Float) -> SceneParticleGPUInstance {
        SceneParticleGPUInstance(
            position: SIMD3(x, 0, 0), size: 1, rotation: .zero,
            color: SIMD3(repeating: 1), alpha: 1
        )
    }

    private static func commitAndWait(_ command: MTLCommandBuffer) -> Bool {
        let completion = DispatchSemaphore(value: 0)
        command.addCompletedHandler { _ in completion.signal() }
        command.commit()
        return completion.wait(timeout: .now() + 5) == .success
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

    def test_cpu_and_msl_instance_layouts_match(self) -> None:
        self.assertEqual(self.result["instanceStride"], 128)
        self.assertEqual(self.result["instanceAlignment"], 16)
        self.assertEqual(self.result["instanceOffsets"], [0, 16, 32, 48, 64, 80, 96, 112])
        self.assertEqual(self.result["uniformStride"], 176)
        self.assertEqual(self.result["uniformOffsets"], [0, 64, 128, 144, 160])

    def test_lifetime_sprite_selection_and_frame_blending(self) -> None:
        self.assertEqual(self.result["sequence"]["current"], 2)
        self.assertEqual(self.result["sequence"]["next"], 0)
        self.assertAlmostEqual(self.result["sequence"]["mix"], 0.5, places=6)
        self.assertEqual(self.result["noBlend"], {"current": 2, "next": 2, "mix": 0})
        self.assertEqual(self.result["reverse"], self.result["sequence"])
        self.assertGreater(len(set(self.result["randomIndices"])), 1)
        self.assertTrue(self.result["randomNoBlend"])
        self.assertTrue(self.result["modeSequence"])
        self.assertTrue(self.result["modeRandom"])

    def test_orientation_bases_are_authored_and_orthonormal(self) -> None:
        self.assertTrue(self.result["orientationDefault"])
        self.assertEqual(self.result["trailFrame"], [0, 1, 0, -1, 1, 0])
        self.assertEqual(self.result["screenRight"], [1, 0, 0])
        self.assertEqual(self.result["screenUp"], [0, 1, 0])
        self.assertEqual(self.result["uprightRight"], [1, 0, 0])
        self.assertEqual(self.result["uprightUp"], [0, 1, 0])
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

    def test_sprite_trails_align_and_stretch_along_velocity(self) -> None:
        horizontal = self.result["horizontalTrailBounds"]
        vertical = self.result["verticalTrailBounds"]
        rotated = self.result["rotatedTrailBounds"]
        self.assertGreater(horizontal["width"], horizontal["height"] * 2.5)
        self.assertGreater(vertical["height"], vertical["width"] * 2.5)
        self.assertGreater(rotated["height"], rotated["width"] * 2.5)

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
        # 适配后 swizzle rrrr:灰白(B==G==R)且保持预乘白合同。
        self.assertGreater(adapted[0], 150)
        self.assertEqual(adapted[0], adapted[1])
        self.assertEqual(adapted[1], adapted[2])
        self.assertEqual(adapted[2], adapted[3])
        # RG88 luminance+alpha 展开为预乘 RGBA:255*128/255=128,alpha=128。
        self.assertTrue(contract["rgExpandedFormatIsRGBA"])
        self.assertEqual(contract["rgExpandedMipCount"], 2)
        self.assertEqual(contract["rgExpandedPixel"], [128, 128, 128, 128])
        self.assertEqual(contract["rgExpandedSecondMip"], [16, 16, 16, 64])

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
        # For a trail moving right, texture +Y follows the path and samples
        # farther right in the blue X gradient. Texture +X is -perpendicular,
        # crossing the trail downward in the green Y gradient.
        self.assertGreater(along[0], neutral[0] + 15)
        self.assertLessEqual(abs(along[1] - neutral[1]), 2)
        self.assertGreater(across[1], neutral[1] + 8)
        self.assertLessEqual(abs(across[0] - neutral[0]), 2)

    def test_rope_trail_refraction_uses_displacement_per_uv_span(self) -> None:
        contract = self.result["refractionContract"]
        neutral = contract["magnitudeNeutral"]
        short_stretch = contract["fullSpanShortStretch"]
        long_stretch = contract["fullSpanLongStretch"]
        half_span = contract["halfSpanLongStretch"]
        if not neutral or not short_stretch or not long_stretch or not half_span:
            self.skipTest("Metal refraction draw is unavailable")
        short_delta = short_stretch[0] - neutral[0]
        long_delta = long_stretch[0] - neutral[0]
        half_delta = half_span[0] - neutral[0]
        self.assertGreater(short_delta, 3)
        self.assertLessEqual(abs(long_delta - short_delta), 2)
        self.assertGreater(half_delta, short_delta * 1.7)
        self.assertLess(half_delta, short_delta * 2.3)
        for shifted in (short_stretch, long_stretch, half_span):
            self.assertLessEqual(abs(shifted[1] - neutral[1]), 2)

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
