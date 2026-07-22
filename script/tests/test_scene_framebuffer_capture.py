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
    SOURCE_ROOT / "SceneGPUCompletionTelemetry.swift",
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
        let refusedWithoutPool = mainPass.withReadableTarget { readableTarget, _ in
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
                    finalCompositeAlpha: 1,
                    dependencyEffect: nil
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
        } ?? true
        let drew = mainPass.withReadableTarget { readableTarget, _ in
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
                    finalCompositeAlpha: 1,
                    dependencyEffect: nil
                ),
                pipeline: pipeline,
                mainPass: mainPass
            )
        } ?? false
        let telemetry = SceneGPUCompletionTelemetry(phase: "utility-capture")
        telemetry.record(layerID: 701, encoded: drew, on: commandBuffer)
        telemetry.record(layerID: 702, encoded: false, on: commandBuffer)
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }

        let noDependency = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: nil, alpha: 1
        )
        let normalDependency = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 0, alpha: 1
        )
        let darkenDependency = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 5, alpha: 1
        )
        let darkenHalfAlpha = try dependencyBlendPixel(
            device: device, queue: queue, pipeline: pipeline, compositor: compositor,
            blendMode: 5, alpha: 0.5
        )

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
            "noDependencyBGRA": noDependency,
            "normalDependencyBGRA": normalDependency,
            "darkenDependencyBGRA": darkenDependency,
            "darkenHalfAlphaBGRA": darkenHalfAlpha,
            "fragmentUniformSize": MemoryLayout<SceneLayerFragmentUniforms>.size,
            "dependencyBlendModeOffset": MemoryLayout<SceneLayerFragmentUniforms>.offset(
                of: \SceneLayerFragmentUniforms.dependencyBlendMode
            ) ?? -1,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func dependencyBlendPixel(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline,
        compositor: SceneImageLayerCompositor,
        blendMode: Int?,
        alpha: Float
    ) throws -> [UInt8] {
        guard let source = makeTexture(device: device, size: 8, usage: .shaderRead),
              let dependency = makeTexture(device: device, size: 8, usage: .shaderRead),
              let target = makeTexture(
                  device: device, size: 8, usage: [.renderTarget, .shaderRead]
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.metalUnavailable
        }
        fill(source, bgra: [32, 64, 128, 128])
        fill(dependency, bgra: [192, 32, 64, 255])
        let layer = SceneRenderDescriptor.Layer(
            contentKind: "image", colorRGB: nil, colorBlendMode: nil, effects: []
        )
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let drew = compositor.draw(
            SceneImageLayerDrawRequest(
                layer: layer,
                texture: source,
                masks: .empty,
                textureFrame: .identity,
                mvp: SceneMatrix.scale(SIMD3<Float>(2, 2, 1)),
                uniforms: SceneImageLayerUniformValues(
                    time: 0, alpha: alpha, cursorUV: .zero
                ),
                offscreenTexturePool: nil,
                offscreenSize: nil,
                requiresSourceCopy: false,
                finalCompositeAlpha: nil,
                dependencyEffect: blendMode.map {
                    SceneDependencyEffectInput(texture: dependency, blendMode: $0)
                }
            ),
            pipeline: pipeline,
            mainPass: mainPass
        )
        guard drew else { throw HarnessError.drawRefused }
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.commandFailed }
        return pixel(target, x: 4, y: 4)
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

    static func fill(_ texture: MTLTexture, bgra: [UInt8]) {
        var bytes = [UInt8]()
        bytes.reserveCapacity(texture.width * texture.height * 4)
        for _ in 0..<(texture.width * texture.height) {
            bytes.append(contentsOf: bgra)
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
        case drawRefused
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

    def test_dependency_blend_modes_preserve_source_alpha(self) -> None:
        self.assert_pixel_close(self.result["noDependencyBGRA"], [32, 64, 128, 128])
        self.assert_pixel_close(self.result["normalDependencyBGRA"], [112, 48, 96, 128])
        self.assert_pixel_close(self.result["darkenDependencyBGRA"], [32, 32, 64, 128])
        self.assert_pixel_close(self.result["darkenHalfAlphaBGRA"], [16, 16, 32, 64])

    def test_dependency_mode_reuses_uniform_padding_without_layout_growth(self) -> None:
        self.assertEqual(self.result["fragmentUniformSize"], 144)
        self.assertEqual(self.result["dependencyBlendModeOffset"], 12)

    def assert_pixel_close(self, actual: list[int], expected: list[int]) -> None:
        self.assertEqual(len(actual), len(expected))
        for component, wanted in zip(actual, expected):
            self.assertLessEqual(abs(component - wanted), 1)


if __name__ == "__main__":
    unittest.main()
