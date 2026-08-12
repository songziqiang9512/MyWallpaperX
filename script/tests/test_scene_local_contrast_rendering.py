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
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Extent.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetTable.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetTable+Mapped.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphCommandRuntime.swift",
    SOURCE_ROOT / "Effects/SceneLocalContrastPipeline.swift",
    SOURCE_ROOT / "Effects/SceneLocalContrastRenderer.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    var cursorRipple: SceneCursorRippleExecutionPlan? { nil }
    var supportsUnifiedFullFrameComposeStage: Bool { false }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias TargetPlan = SceneGraphRenderTargetPlan
    typealias TargetTable = SceneGraphRenderTargetTable

    static let width = 8
    static let height = 8
    static let layerID = 23
    static let effect = Graph.EffectKey(
        layerID: layerID,
        effectIndex: 0,
        descriptorID: "23#effect#0"
    )
    static let inputIdentity = identity(.layerSource)
    static let outputIdentity = identity(.effectOutput, effect: effect)
    static let quarterAIdentity = identity(
        .framebuffer,
        effect: effect,
        name: "_rt_QuarterCompoBuffer1"
    )
    static let quarterBIdentity = identity(
        .framebuffer,
        effect: effect,
        name: "_rt_QuarterCompoBuffer2"
    )

    static func identity(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func logicalTarget(
        identity: Graph.TextureIdentity,
        format: TargetPlan.TextureFormat,
        firstWrite: Int,
        lastWrite: Int,
        firstRead: Int,
        lastRead: Int
    ) -> TargetPlan.LogicalTarget {
        .init(
            identity: identity,
            extent: .init(width: 2, height: 2),
            format: format,
            isUnique: false,
            lifetime: .init(
                firstWriteNodeIndex: firstWrite,
                lastWriteNodeIndex: lastWrite,
                firstReadNodeIndex: firstRead,
                lastReadNodeIndex: lastRead
            ),
            initialClear: nil
        )
    }

    static func makeTable(
        device: MTLDevice,
        intermediateFormat: TargetPlan.TextureFormat = .rgba8888
    ) -> TargetTable {
        let plan = TargetPlan.testingPlan(
            layerID: layerID,
            input: inputIdentity,
            output: outputIdentity,
            inputExtent: .init(width: width, height: height),
            logicalTargets: [
                logicalTarget(
                    identity: quarterAIdentity,
                    format: intermediateFormat,
                    firstWrite: 0,
                    lastWrite: 2,
                    firstRead: 1,
                    lastRead: 3
                ),
                logicalTarget(
                    identity: quarterBIdentity,
                    format: intermediateFormat,
                    firstWrite: 1,
                    lastWrite: 1,
                    firstRead: 2,
                    lastRead: 2
                ),
            ]
        )
        guard case .success(let table) = TargetTable.make(
            plan: plan,
            device: device,
            byteBudget: 1_000_000
        ) else {
            fatalError("target table allocation failed")
        }
        return table
    }

    static func inputPixelsBGRA() -> [UInt8] {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let red = UInt8(90 + x * 8 + y * 2)
                let green = UInt8(170 - x * 3 - y * 6)
                let blue = UInt8(100 + ((x * 11 + y * 7) % 60))
                let alpha = UInt8(50 + ((x * 23 + y * 31) % 180))
                pixels.append(contentsOf: [blue, green, red, alpha])
            }
        }
        return pixels
    }

    static func sharedTexture(
        device: MTLDevice,
        format: MTLPixelFormat,
        width: Int,
        height: Int
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("shared texture allocation failed")
        }
        return texture
    }

    static func uploadInput(
        _ pixels: [UInt8],
        to texture: MTLTexture,
        device: MTLDevice,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let staging = sharedTexture(
            device: device,
            format: .bgra8Unorm,
            width: width,
            height: height
        )
        var bytes = pixels
        staging.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: &bytes,
            bytesPerRow: width * 4
        )
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
        blit.copy(
            from: staging,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: width, height: height, depth: 1),
            to: texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        return true
    }

    static func enqueueReadback(
        source: MTLTexture,
        device: MTLDevice,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        let target = sharedTexture(
            device: device,
            format: source.pixelFormat,
            width: source.width,
            height: source.height
        )
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: source.width, height: source.height, depth: 1),
            to: target,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        return target
    }

    static func bytes(from texture: MTLTexture) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &result,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return result
    }

    static func logicalRGBA(_ bytes: [UInt8], format: MTLPixelFormat) -> [UInt8] {
        guard format == .bgra8Unorm else { return bytes }
        var result = bytes
        for index in stride(from: 0, to: bytes.count, by: 4) {
            result[index] = bytes[index + 2]
            result[index + 2] = bytes[index]
        }
        return result
    }

    static func finish(_ commandBuffer: MTLCommandBuffer) -> Bool {
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return commandBuffer.status == .completed
    }

    static func runRenderer(
        strength: Float,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneLocalContrastPipeline,
        input: [UInt8]
    ) -> [String: Any] {
        let table = makeTable(device: device)
        guard let quarterA = table.texture(for: quarterAIdentity),
              let quarterB = table.texture(for: quarterBIdentity),
              let command = queue.makeCommandBuffer(),
              uploadInput(input, to: table.inputTexture, device: device, commandBuffer: command),
              SceneLocalContrastRenderer.render(
                targets: table,
                quarterAIdentity: quarterAIdentity,
                quarterBIdentity: quarterBIdentity,
                strength: strength,
                pipeline: pipeline,
                commandBuffer: command
              ) === table.outputTexture,
              let outputReadback = enqueueReadback(
                source: table.outputTexture,
                device: device,
                commandBuffer: command
              ), let quarterAReadback = enqueueReadback(
                source: quarterA,
                device: device,
                commandBuffer: command
              ), let quarterBReadback = enqueueReadback(
                source: quarterB,
                device: device,
                commandBuffer: command
              ), finish(command) else {
            fatalError("renderer execution failed")
        }
        return [
            "output": logicalRGBA(bytes(from: outputReadback), format: .bgra8Unorm),
            "quarterA": bytes(from: quarterAReadback),
            "quarterB": bytes(from: quarterBReadback),
            "inputOutputBGRA": table.inputTexture.pixelFormat == .bgra8Unorm
                && table.outputTexture.pixelFormat == .bgra8Unorm,
            "intermediatesRGBA": quarterA.pixelFormat == .rgba8Unorm
                && quarterB.pixelFormat == .rgba8Unorm,
            "quarterSize": [quarterA.width, quarterA.height],
        ]
    }

    static func runStages(
        strength: Float,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneLocalContrastPipeline,
        input: [UInt8]
    ) -> [String: Any] {
        let table = makeTable(device: device)
        guard let quarterA = table.texture(for: quarterAIdentity),
              let quarterB = table.texture(for: quarterBIdentity),
              let command = queue.makeCommandBuffer(),
              uploadInput(input, to: table.inputTexture, device: device, commandBuffer: command),
              pipeline.encodeDownsample(
                source: table.inputTexture,
                target: quarterA,
                commandBuffer: command
              ), let downsample = enqueueReadback(
                source: quarterA,
                device: device,
                commandBuffer: command
              ), pipeline.encodeGaussian(
                source: quarterA,
                target: quarterB,
                step: SIMD2(1 / Float(quarterA.width), 0),
                commandBuffer: command
              ), let horizontal = enqueueReadback(
                source: quarterB,
                device: device,
                commandBuffer: command
              ), pipeline.encodeGaussian(
                source: quarterB,
                target: quarterA,
                step: SIMD2(0, 1 / Float(quarterA.height)),
                commandBuffer: command
              ), let vertical = enqueueReadback(
                source: quarterA,
                device: device,
                commandBuffer: command
              ), pipeline.encodeCombine(
                blurred: quarterA,
                previous: table.inputTexture,
                strength: strength,
                target: table.outputTexture,
                commandBuffer: command
              ), let output = enqueueReadback(
                source: table.outputTexture,
                device: device,
                commandBuffer: command
              ), finish(command) else {
            fatalError("staged execution failed")
        }
        return [
            "downsample": bytes(from: downsample),
            "horizontal": bytes(from: horizontal),
            "vertical": bytes(from: vertical),
            "output": logicalRGBA(bytes(from: output), format: .bgra8Unorm),
        ]
    }

    static func rejectionChecks(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneLocalContrastPipeline
    ) -> [String: Bool] {
        let table = makeTable(device: device)
        let wrongFormatTable = makeTable(device: device, intermediateFormat: .rgbaBackbuffer)
        let otherEffect = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 1,
            descriptorID: "23#effect#1"
        )
        let foreignIdentity = identity(.framebuffer, effect: otherEffect, name: "foreign")
        guard let command = queue.makeCommandBuffer(),
              let secondCommand = queue.makeCommandBuffer(),
              let thirdCommand = queue.makeCommandBuffer(),
              let fourthCommand = queue.makeCommandBuffer() else {
            fatalError("command allocation failed")
        }
        return [
            "foreignIdentity": SceneLocalContrastRenderer.render(
                targets: table,
                quarterAIdentity: foreignIdentity,
                quarterBIdentity: quarterBIdentity,
                strength: 1,
                pipeline: pipeline,
                commandBuffer: command
            ) == nil,
            "swappedIdentity": SceneLocalContrastRenderer.render(
                targets: table,
                quarterAIdentity: quarterBIdentity,
                quarterBIdentity: quarterAIdentity,
                strength: 1,
                pipeline: pipeline,
                commandBuffer: secondCommand
            ) == nil,
            "wrongFormat": SceneLocalContrastRenderer.render(
                targets: wrongFormatTable,
                quarterAIdentity: quarterAIdentity,
                quarterBIdentity: quarterBIdentity,
                strength: 1,
                pipeline: pipeline,
                commandBuffer: thirdCommand
            ) == nil,
            "invalidStrength": SceneLocalContrastRenderer.render(
                targets: table,
                quarterAIdentity: quarterAIdentity,
                quarterBIdentity: quarterBIdentity,
                strength: .nan,
                pipeline: pipeline,
                commandBuffer: fourthCommand
            ) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneLocalContrastPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let inputBGRA = inputPixelsBGRA()
        let zero = runRenderer(
            strength: 0,
            device: device,
            queue: queue,
            pipeline: pipeline,
            input: inputBGRA
        )
        let fractional = runRenderer(
            strength: 0.32,
            device: device,
            queue: queue,
            pipeline: pipeline,
            input: inputBGRA
        )
        let full = runRenderer(
            strength: 1,
            device: device,
            queue: queue,
            pipeline: pipeline,
            input: inputBGRA
        )
        let stages = runStages(
            strength: 0.32,
            device: device,
            queue: queue,
            pipeline: pipeline,
            input: inputBGRA
        )
        let result: [String: Any] = [
            "metalUnavailable": false,
            "input": logicalRGBA(inputBGRA, format: .bgra8Unorm),
            "zero": zero,
            "fractional": fractional,
            "full": full,
            "stages": stages,
            "rejections": rejectionChecks(device: device, queue: queue, pipeline: pipeline),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneLocalContrastRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-local-contrast-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-local-contrast-rendering"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-D",
                "SCENE_GRAPH_TESTING",
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
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_renderer_matches_the_explicit_four_stage_order(self) -> None:
        stages = self.result["stages"]
        fractional = self.result["fractional"]
        self.assertEqual(stages["output"], fractional["output"])
        self.assertEqual(stages["vertical"], fractional["quarterA"])
        self.assertEqual(stages["horizontal"], fractional["quarterB"])
        self.assertNotEqual(stages["downsample"], stages["horizontal"])
        self.assertNotEqual(stages["horizontal"], stages["vertical"])

    def test_stage_outputs_match_the_stock_default_kernel_golden(self) -> None:
        expected = {
            "downsample": [
                107, 155, 131, 73, 136, 146, 126, 85,
                112, 134, 129, 75, 146, 120, 136, 98,
            ],
            "horizontal": [
                119, 151, 129, 78, 124, 150, 128, 80,
                126, 128, 132, 85, 132, 126, 133, 88,
            ],
            "vertical": [
                122, 141, 130, 81, 127, 140, 130, 83,
                123, 138, 131, 82, 129, 136, 131, 85,
            ],
        }
        for stage, golden in expected.items():
            for actual, reference in zip(self.result["stages"][stage], golden):
                self.assertAlmostEqual(actual, reference, delta=1)

    def test_uses_bgra_edges_and_rgba_quarter_targets(self) -> None:
        fractional = self.result["fractional"]
        self.assertTrue(fractional["inputOutputBGRA"])
        self.assertTrue(fractional["intermediatesRGBA"])
        self.assertEqual(fractional["quarterSize"], [2, 2])
        self.assertEqual(len(self.result["stages"]["downsample"]), 16)

    def test_strength_matches_the_stock_linear_combine_and_channel_order(self) -> None:
        source = self.result["input"]
        zero = self.result["zero"]["output"]
        fractional = self.result["fractional"]["output"]
        full = self.result["full"]["output"]
        self.assertEqual(zero, source)
        for index in range(0, len(source), 4):
            for channel in range(3):
                expected = source[index + channel] + 0.32 * (
                    full[index + channel] - source[index + channel]
                )
                self.assertAlmostEqual(
                    fractional[index + channel], expected, delta=2
                )
        for channel in range(3):
            self.assertTrue(
                any(
                    abs(full[index + channel] - source[index + channel]) >= 3
                    for index in range(0, len(source), 4)
                )
            )

    def test_preserves_source_alpha_for_every_strength(self) -> None:
        source_alpha = self.result["input"][3::4]
        self.assertGreater(len(set(source_alpha)), 8)
        for key in ("zero", "fractional", "full"):
            self.assertEqual(self.result[key]["output"][3::4], source_alpha)
        self.assertGreater(len(set(self.result["stages"]["downsample"][3::4])), 1)

    def test_rejects_wrong_formats_identities_and_nonfinite_strength(self) -> None:
        self.assertEqual(
            self.result["rejections"],
            {
                "foreignIdentity": True,
                "invalidStrength": True,
                "swappedIdentity": True,
                "wrongFormat": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
