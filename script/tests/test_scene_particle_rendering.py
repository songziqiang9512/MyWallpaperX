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
    SOURCE_ROOT / "Rendering/SceneMatrix.swift",
    SOURCE_ROOT / "Particles/SceneParticleRenderSupport.swift",
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
            "screenRight": vector(screen.right),
            "screenUp": vector(screen.up),
            "uprightRight": vector(upright.right),
            "uprightUp": vector(upright.up),
            "fixedRight": vector(fixed.right),
            "fixedUp": vector(fixed.up),
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
            "instanceBufferSlots": instanceBufferSlotTest(),
            "colorContract": colorContractTest(),
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

    private static func uniformOffsets() -> [Int] {
        [
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.viewProjection),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.layerModel),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.basisRight),
            MemoryLayout<SceneParticleLayerUniforms>.offset(of: \.basisUp),
        ].compactMap { $0 }
    }

    private static func selection(_ value: SceneParticleSpriteFrameSelection) -> [String: Any] {
        ["current": value.currentIndex, "next": value.nextIndex, "mix": value.mix]
    }

    private static func vector(_ value: SIMD3<Float>) -> [Float] {
        [value.x, value.y, value.z]
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
            blendMode: .translucent, encoder: encoder
        )
        pipeline.draw(
            texture: input, instances: instances,
            uniforms: SceneParticleLayerUniforms(
                viewProjection: SceneMatrix.identity(),
                layerModel: SceneMatrix.identity(), basis: basis
            ),
            blendMode: .additive, encoder: encoder
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
            pixelFormat: .rg8Unorm, width: 2, height: 2, mipmapped: false
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
        let adaptedRG = SceneParticleColorTextureAdapter.adapt(rg, device: device)
        var expanded = [UInt8](repeating: 0, count: 4)
        if adaptedRG.pixelFormat == .rgba8Unorm {
            adaptedRG.getBytes(
                &expanded,
                bytesPerRow: adaptedRG.width * 4,
                from: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0
            )
        }
        return [
            "rawR8": rawR8,
            "adaptedR8": adaptedR8,
            "rgExpandedFormatIsRGBA": adaptedRG.pixelFormat == .rgba8Unorm,
            "rgExpandedPixel": expanded.map(Int.init),
        ]
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
        self.assertEqual(self.result["uniformStride"], 160)
        self.assertEqual(self.result["uniformOffsets"], [0, 64, 128, 144])

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
        self.assertEqual(self.result["screenRight"], [1, 0, 0])
        self.assertEqual(self.result["screenUp"], [0, 1, 0])
        self.assertEqual(self.result["uprightRight"], [1, 0, 0])
        self.assertEqual(self.result["uprightUp"], [0, 1, 0])
        self.assertEqual(self.result["fixedRight"], [0, 1, 0])
        self.assertEqual(self.result["fixedUp"], [0, 0, 1])

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
        self.assertEqual(contract["rgExpandedPixel"], [128, 128, 128, 128])

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


if __name__ == "__main__":
    unittest.main()
