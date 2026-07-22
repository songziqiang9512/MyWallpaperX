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
    SOURCE_ROOT / "SceneMatrix.swift",
    SOURCE_ROOT / "SceneMetalPipeline.swift",
    SOURCE_ROOT / "SceneSpriteAnimation.swift",
    SOURCE_ROOT / "SceneMainPassEncoder.swift",
    SOURCE_ROOT / "SceneOffscreenTexturePool.swift",
    SOURCE_ROOT / "SceneGaussianBlurPipeline.swift",
    SOURCE_ROOT / "SceneBloomPipeline.swift",
    SOURCE_ROOT / "SceneWaterRipplePipeline.swift",
    SOURCE_ROOT / "ScenePerspectiveOpacityPipeline.swift",
    SOURCE_ROOT / "SceneEffectMaskSemantics.swift",
    SOURCE_ROOT / "SceneWaterRippleRuntimePlan.swift",
    SOURCE_ROOT / "SceneInlineEffectRuntime.swift",
    SOURCE_ROOT / "SceneEffectRuntimeSupport.swift",
    SOURCE_ROOT / "SceneEffectRuntimePlan.swift",
    SOURCE_ROOT / "SceneOffscreenEffectRenderer.swift",
    SOURCE_ROOT / "SceneImageLayerCompositor.swift",
    SOURCE_ROOT / "SceneUtilityCaptureTelemetry.swift",
]

HARNESS_SOURCE = r'''
import Foundation
import Metal
import simd

struct SceneDocument {
    struct ShaderValue {
        let components: [Double]?
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let texturePaths: [String]
            let textureSlots: [String?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let contentKind: String
        let colorRGB: [Float]?
        let colorBlendMode: Int?
        let effects: [EffectDescriptor]
    }
}

struct SceneTexContainer {
    struct SpriteFrame {
        let imageIndex: Int
        let duration: Float
        let origin: SIMD2<Float>
        let xAxis: SIMD2<Float>
        let yAxis: SIMD2<Float>
    }
    let spriteFrames: [SpriteFrame]
}

struct SceneTexContainerReader {
    func read(data: Data) throws -> SceneTexContainer {
        SceneTexContainer(spriteFrames: [])
    }
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneImageLayerPipeline(device: device),
              let compositor = SceneImageLayerCompositor(device: device),
              let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fillQuadrants(source)

        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 1)
        )
        guard let baseEncoder = mainPass.encoder() else { throw HarnessError.encoderUnavailable }
        pipeline.bind(encoder: baseEncoder)
        pipeline.drawLayer(
            texture: source,
            shakeMaskTexture: nil,
            waterMaskTexture: nil,
            foliageMaskTexture: nil,
            auxMaskTexture: nil,
            mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
            uniforms: .neutral(),
            encoder: baseEncoder
        )

        let layer = SceneRenderDescriptor.Layer(
            contentKind: "composition",
            colorRGB: nil,
            colorBlendMode: nil,
            effects: []
        )
        let pool = SceneOffscreenTexturePool(device: device)
        let refusedWithoutPool = mainPass.withReadableTarget { readableTarget in
            compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: readableTarget,
                    masks: .empty,
                    textureFrame: .identity,
                    mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                    uniforms: SceneImageLayerUniformValues(
                        time: 0, alpha: 1, cursorUV: .zero
                    ),
                    offscreenTexturePool: nil,
                    offscreenSize: nil,
                    requiresSourceCopy: true,
                    finalCompositeAlpha: 1
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
        } ?? true
        let drew = mainPass.withReadableTarget { readableTarget in
            compositor.draw(
                SceneImageLayerDrawRequest(
                    layer: layer,
                    texture: readableTarget,
                    masks: .empty,
                    textureFrame: SceneTextureUVTransform(
                        origin: .zero,
                        xAxis: SIMD2(0.5, 0),
                        yAxis: SIMD2(0, 0.5)
                    ),
                    mvp: SceneMatrix.scale(SIMD3<Float>(1, 1, 1)),
                    uniforms: SceneImageLayerUniformValues(
                        time: 0, alpha: 1, cursorUV: .zero
                    ),
                    offscreenTexturePool: pool,
                    offscreenSize: CGSize(width: 4, height: 4),
                    requiresSourceCopy: true,
                    finalCompositeAlpha: 1
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
        } ?? false
        let telemetry = SceneUtilityCaptureTelemetry()
        telemetry.record(layerID: 701, encoded: drew, on: commandBuffer)
        telemetry.record(layerID: 702, encoded: false, on: commandBuffer)
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }

        let limited = pool.textures(width: 4_000, height: 2_000)
        let evictionPool = SceneOffscreenTexturePool(
            device: device, maxDimension: 64, byteBudget: 1_000
        )
        let firstSmall = evictionPool.textures(width: 8, height: 8)?.primary
        _ = evictionPool.textures(width: 16, height: 16)
        let secondSmall = evictionPool.textures(width: 8, height: 8)?.primary

        let result: [String: Any] = [
            "drew": drew,
            "refusedWithoutPool": refusedWithoutPool,
            "centerBGRA": pixel(target, x: 4, y: 4),
            "bottomRightBGRA": pixel(target, x: 7, y: 7),
            "limitedSize": [limited?.primary.width ?? 0, limited?.primary.height ?? 0],
            "evicted": firstSmall !== secondSmall,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func makeTexture(
        device: MTLDevice,
        size: Int,
        usage: MTLTextureUsage
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    static func fillQuadrants(_ texture: MTLTexture) {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        for y in 0..<texture.height {
            for x in 0..<texture.width {
                let color: [UInt8]
                switch (x >= texture.width / 2, y >= texture.height / 2) {
                case (false, false): color = [0, 0, 255, 255]
                case (true, false): color = [0, 255, 0, 255]
                case (false, true): color = [255, 0, 0, 255]
                case (true, true): color = [255, 255, 255, 255]
                }
                let offset = (y * texture.width + x) * 4
                bytes.replaceSubrange(offset..<(offset + 4), with: color)
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: texture.width * 4
        )
    }

    static func pixel(_ texture: MTLTexture, x: Int, y: Int) -> [UInt8] {
        var value = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &value,
            bytesPerRow: 4,
            from: MTLRegionMake2D(x, y, 1, 1),
            mipmapLevel: 0
        )
        return value
    }

    enum HarnessError: Error {
        case metalUnavailable
        case encoderUnavailable
        case commandFailed
    }
}
'''


class SceneFramebufferCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-framebuffer-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-framebuffer-capture"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        cls.stderr = completed.stderr

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_current_frame_can_be_captured_without_read_write_aliasing(self) -> None:
        self.assertTrue(self.result["drew"])
        self.assertFalse(self.result["refusedWithoutPool"])
        self.assertEqual(self.result["centerBGRA"], [0, 0, 255, 255])
        self.assertEqual(self.result["bottomRightBGRA"], [255, 255, 255, 255])

    def test_pool_clamps_large_targets_and_evicts_over_budget_entries(self) -> None:
        self.assertEqual(self.result["limitedSize"], [2048, 1024])
        self.assertTrue(self.result["evicted"])

    def test_capture_telemetry_waits_for_gpu_completion(self) -> None:
        self.assertIn("phase=utility-capture layer=701 status=succeeded", self.stderr)
        self.assertIn("phase=utility-capture layer=702 status=failed", self.stderr)


if __name__ == "__main__":
    unittest.main()
