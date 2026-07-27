#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Effects/SceneShakePipeline.swift",
    SOURCE_ROOT / "Effects/SceneShakeRenderer.swift",
]

HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneAuthoredEffectRenderPlan {
    struct EffectKey: Equatable {
        let layerID: Int
        let effectIndex: Int
        let descriptorID: String
    }
}

struct SceneShakeExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
    let bounds: SIMD2<Float>
    let friction: SIMD2<Float>
    let speed: Float
    let strength: Float
}

struct SceneShakeEffectTextures {
    let flow: MTLTexture?
    let phase: MTLTexture?
    let flowUVScale: SIMD2<Float>
    let flowPath: String
    let phasePath: String?

    func matches(_ plan: SceneShakeExecutionPlan) -> Bool {
        flow != nil
            && flowPath == "masks/flow"
            && phasePath == (phase == nil ? nil : "masks/phase")
    }
}

@main
enum Harness {
    static let size = 16
    static let effectKey = SceneAuthoredEffectRenderPlan.EffectKey(
        layerID: 20,
        effectIndex: 0,
        descriptorID: "20#effect#0"
    )

    static func plan(
        bounds: SIMD2<Float> = SIMD2(0, 1),
        friction: SIMD2<Float> = SIMD2(1, 1),
        speed: Float = 1,
        strength: Float = 0.5
    ) -> SceneShakeExecutionPlan {
        .init(
            effectKey: effectKey,
            bounds: bounds,
            friction: friction,
            speed: speed,
            strength: strength
        )
    }

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat = .bgra8Unorm,
        width: Int = size,
        height: Int = size,
        mipmapped: Bool = false,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget],
        type: MTLTextureType = .type2D,
        sampleCount: Int = 1
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = type
        descriptor.pixelFormat = format
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = 1
        descriptor.arrayLength = type == .type2DArray ? 2 : 1
        descriptor.mipmapLevelCount = mipmapped ? 2 : 1
        descriptor.sampleCount = sampleCount
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func sourceBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                bytes[offset] = UInt8(x * 12)
                bytes[offset + 1] = UInt8(y * 12)
                bytes[offset + 2] = UInt8((x + y) * 6)
                bytes[offset + 3] = 255
            }
        }
        return bytes
    }

    static func uploadBGRA(_ bytes: [UInt8], to texture: MTLTexture) {
        bytes.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: texture.width * 4
            )
        }
    }

    static func readBGRA(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return bytes
    }

    static func flowTexture(device: MTLDevice, localized: Bool = true) -> MTLTexture {
        let texture = self.texture(
            device: device,
            format: .rg8Unorm,
            usage: .shaderRead
        )
        var bytes = [UInt8](repeating: 127, count: size * size * 2)
        if localized {
            for y in 5...10 {
                for x in 5...10 {
                    let offset = (y * size + x) * 2
                    bytes[offset] = 255
                    bytes[offset + 1] = 127
                }
            }
        } else {
            for index in stride(from: 0, to: bytes.count, by: 2) {
                bytes[index] = 255
            }
        }
        bytes.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: size * 2
            )
        }
        return texture
    }

    static func phaseTexture(device: MTLDevice, value: UInt8 = 255) -> MTLTexture {
        let texture = self.texture(
            device: device,
            format: .r8Unorm,
            width: 1,
            height: 1,
            usage: .shaderRead
        )
        var byte = value
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &byte,
            bytesPerRow: 1
        )
        return texture
    }

    static func render(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneShakePipeline,
        source: MTLTexture,
        flow: MTLTexture,
        phase: MTLTexture?,
        plan: SceneShakeExecutionPlan = plan(),
        time: Float,
        flowUVScale: SIMD2<Float> = SIMD2(1, 1)
    ) -> (bytes: [UInt8], returnedOutput: Bool, completed: Bool) {
        let target = texture(device: device)
        let command = queue.makeCommandBuffer()!
        let resources = SceneShakeEffectTextures(
            flow: flow,
            phase: phase,
            flowUVScale: flowUVScale,
            flowPath: "masks/flow",
            phasePath: phase == nil ? nil : "masks/phase"
        )
        let rendered = SceneShakeRenderer.render(
            plan: plan,
            resources: resources,
            time: time,
            audioPulse: nil,
            inputTexture: source,
            outputTexture: target,
            pipeline: pipeline,
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        return (
            readBGRA(target),
            rendered === target,
            command.status == .completed
        )
    }

    static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        (0..<(lhs.count / 4)).filter { pixel in
            let offset = pixel * 4
            return (0..<4).contains { channel in
                abs(Int(lhs[offset + channel]) - Int(rhs[offset + channel])) > 1
            }
        }.count
    }

    static func cornerChangedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        var count = 0
        for y in [0, 1, 14, 15] {
            for x in [0, 1, 14, 15] {
                let offset = (y * size + x) * 4
                if (0..<4).contains(where: {
                    abs(Int(lhs[offset + $0]) - Int(rhs[offset + $0])) > 1
                }) {
                    count += 1
                }
            }
        }
        return count
    }

    static func rejectionChecks(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneShakePipeline
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let flow = flowTexture(device: device)
        let phase = phaseTexture(device: device)
        let wrongBGRA = texture(device: device, format: .rgba8Unorm)
        let wrongExtent = texture(device: device, width: size - 1)
        let mipmapped = texture(device: device, mipmapped: true)
        let sourceWrongUsage = texture(device: device, usage: .renderTarget)
        let targetWrongUsage = texture(device: device, usage: .shaderRead)
        let wrongFlowFormat = texture(
            device: device,
            format: .r8Unorm,
            usage: .shaderRead
        )
        let wrongPhaseFormat = texture(
            device: device,
            format: .rg8Unorm,
            usage: .shaderRead
        )
        let non2D = texture(device: device, type: .type2DArray)
        let command = queue.makeCommandBuffer()!
        func encoded(
            source candidateSource: MTLTexture = source,
            flow candidateFlow: MTLTexture = flow,
            phase candidatePhase: MTLTexture = phase,
            target candidateTarget: MTLTexture = target,
            flowUVScale: SIMD2<Float> = SIMD2(1, 1),
            plan candidatePlan: SceneShakeExecutionPlan = plan(),
            time: Float = 1.5707963
        ) -> Bool {
            pipeline.encode(
                source: candidateSource,
                flowMap: candidateFlow,
                phaseMap: candidatePhase,
                flowUVScale: flowUVScale,
                target: candidateTarget,
                plan: candidatePlan,
                time: time,
                audioPulse: nil,
                commandBuffer: command
            )
        }
        var badBounds = plan(); badBounds = plan(bounds: SIMD2(0.5, 0.5))
        let checks = [
            "sameTexture": !encoded(source: source, target: source),
            "wrongSourceFormat": !encoded(source: wrongBGRA),
            "wrongTargetFormat": !encoded(target: wrongBGRA),
            "wrongExtent": !encoded(target: wrongExtent),
            "sourceMipmapped": !encoded(source: mipmapped),
            "targetMipmapped": !encoded(target: mipmapped),
            "sourceWrongUsage": !encoded(source: sourceWrongUsage),
            "targetWrongUsage": !encoded(target: targetWrongUsage),
            "wrongFlowFormat": !encoded(flow: wrongFlowFormat),
            "wrongPhaseFormat": !encoded(phase: wrongPhaseFormat),
            "sourceNon2D": !encoded(source: non2D),
            "targetNon2D": !encoded(target: non2D),
            "zeroUVScale": !encoded(flowUVScale: SIMD2(0, 1)),
            "overflowUVScale": !encoded(flowUVScale: SIMD2(1.01, 1)),
            "nanUVScale": !encoded(flowUVScale: SIMD2(.nan, 1)),
            "invalidBounds": !encoded(plan: badBounds),
            "invalidFriction": !encoded(plan: plan(friction: SIMD2(0, 1))),
            "invalidSpeed": !encoded(plan: plan(speed: 10.1)),
            "invalidStrength": !encoded(plan: plan(strength: 0)),
            "nanTime": !encoded(time: .nan),
            "wrongPipelineFormat": SceneShakePipeline(
                device: device,
                pixelFormat: .rgba8Unorm
            ) == nil,
        ]
        return checks
    }

    static func resourceRejections(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneShakePipeline
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let flow = flowTexture(device: device)
        let command = queue.makeCommandBuffer()!
        func rendered(_ resources: SceneShakeEffectTextures) -> Bool {
            SceneShakeRenderer.render(
                plan: plan(),
                resources: resources,
                time: 1,
                audioPulse: nil,
                inputTexture: source,
                outputTexture: target,
                pipeline: pipeline,
                commandBuffer: command
            ) != nil
        }
        return [
            "missingFlow": !rendered(.init(
                flow: nil,
                phase: nil,
                flowUVScale: SIMD2(1, 1),
                flowPath: "masks/flow",
                phasePath: nil
            )),
            "wrongFlowPath": !rendered(.init(
                flow: flow,
                phase: nil,
                flowUVScale: SIMD2(1, 1),
                flowPath: "masks/other",
                phasePath: nil
            )),
        ]
    }

    static func crossDeviceChecks(
        device: MTLDevice,
        pipeline: SceneShakePipeline
    ) -> [String: Bool] {
        guard let alternate = MTLCopyAllDevices().first(where: {
            $0.registryID != device.registryID
        }), let primaryQueue = device.makeCommandQueue(),
        let alternateQueue = alternate.makeCommandQueue(),
        let primaryCommand = primaryQueue.makeCommandBuffer(),
        let alternateCommand = alternateQueue.makeCommandBuffer() else {
            return ["available": false, "source": true, "flow": true, "phase": true,
                    "target": true, "queue": true]
        }
        let primarySource = texture(device: device)
        let primaryFlow = flowTexture(device: device)
        let primaryPhase = phaseTexture(device: device)
        let primaryTarget = texture(device: device)
        let alternateSource = texture(device: alternate)
        let alternateFlow = flowTexture(device: alternate)
        let alternatePhase = phaseTexture(device: alternate)
        let alternateTarget = texture(device: alternate)
        func encoded(
            source: MTLTexture = primarySource,
            flow: MTLTexture = primaryFlow,
            phase: MTLTexture = primaryPhase,
            target: MTLTexture = primaryTarget,
            command: MTLCommandBuffer = primaryCommand
        ) -> Bool {
            pipeline.encode(
                source: source,
                flowMap: flow,
                phaseMap: phase,
                flowUVScale: SIMD2(1, 1),
                target: target,
                plan: plan(),
                time: 1,
                audioPulse: nil,
                commandBuffer: command
            )
        }
        return [
            "available": true,
            "source": !encoded(source: alternateSource),
            "flow": !encoded(flow: alternateFlow),
            "phase": !encoded(phase: alternatePhase),
            "target": !encoded(target: alternateTarget),
            "queue": !encoded(command: alternateCommand),
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneShakePipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let source = texture(device: device)
        let input = sourceBytes()
        uploadBGRA(input, to: source)
        let flow = flowTexture(device: device)
        let white = phaseTexture(device: device)
        let fallback = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            source: source,
            flow: flow,
            phase: nil,
            time: 1.5707963
        )
        let explicitWhite = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            source: source,
            flow: flow,
            phase: white,
            time: 1.5707963
        )
        let later = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            source: source,
            flow: flow,
            phase: nil,
            time: 4.712389
        )
        let result: [String: Any] = [
            "metalUnavailable": false,
            "changedPixels": changedPixels(input, fallback.bytes),
            "cornerChangedPixels": cornerChangedPixels(input, fallback.bytes),
            "timeChangedPixels": changedPixels(fallback.bytes, later.bytes),
            "whiteFallbackMatches": fallback.bytes == explicitWhite.bytes,
            "rendererReturnedOutput": fallback.returnedOutput,
            "commandsCompleted": fallback.completed && explicitWhite.completed && later.completed,
            "rejections": rejectionChecks(device: device, queue: queue, pipeline: pipeline),
            "resourceRejections": resourceRejections(
                device: device,
                queue: queue,
                pipeline: pipeline
            ),
            "crossDevice": crossDeviceChecks(device: device, pipeline: pipeline),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneShakeRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-shake-rendering-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-shake-rendering"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_flow_map_moves_only_the_authored_region_and_uses_scene_time(self) -> None:
        self.assertGreater(self.result["changedPixels"], 20)
        self.assertEqual(self.result["cornerChangedPixels"], 0)
        self.assertGreater(self.result["timeChangedPixels"], 20)
        self.assertTrue(self.result["rendererReturnedOutput"])
        self.assertTrue(self.result["commandsCompleted"])

    def test_missing_phase_uses_the_authored_white_fallback(self) -> None:
        self.assertTrue(self.result["whiteFallbackMatches"])

    def test_invalid_textures_uniforms_and_resources_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()))
        self.assertTrue(all(self.result["resourceRejections"].values()))

    def test_cross_device_resources_and_queue_fail_closed_when_available(self) -> None:
        checks = self.result["crossDevice"]
        if not checks["available"]:
            self.skipTest("a second Metal device is unavailable")
        self.assertTrue(all(value for key, value in checks.items() if key != "available"))


if __name__ == "__main__":
    unittest.main()
