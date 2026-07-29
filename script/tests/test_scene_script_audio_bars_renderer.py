#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
RENDERER_SOURCE = (
    SCENE_ROOT / "Rendering/SceneScriptAudioBarsRenderer.swift"
)
SOURCES = [
    SCENE_ROOT / "Rendering/SceneMatrix.swift",
    SCENE_ROOT / "Runtime/SceneAudioSpectrum.swift",
    SCENE_ROOT / "Rendering/SceneScriptAudioBarsGeometry.swift",
    SCENE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SCENE_ROOT / "Rendering/SceneMainPassEncoder.swift",
    SCENE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SCENE_ROOT / "Properties/SceneDynamicLayerValues.swift",
    RENDERER_SOURCE,
]


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneScriptAudioBarsPlan {
    enum SpectrumChannel {
        case average
    }

    enum Alignment {
        case centre
        case bottom
        case top
    }

    enum FirstStepPolicy {
        case ownerAtBaseOrigin
        case advanceBeforeFirstBar
    }

    let layerID: Int
    let sourceSHA256: String
    let host: String
    let modelPath: String
    let materialPath: String
    let texturePath: String
    let barCount: Int
    let audioResolution: Int
    let channel: SpectrumChannel
    let widthMultiplier: Float
    let heightMultiplier: Float
    let depthMultiplier: Float
    let xStep: Float
    let yStep: Float
    let angleDegrees: Float
    let alignment: Alignment
    let firstStepPolicy: FirstStepPolicy

    func height(forSpectrumValue value: Float) -> Float {
        value * heightMultiplier
    }

    func stepIndex(forBarIndex index: Int) -> Int {
        switch firstStepPolicy {
        case .ownerAtBaseOrigin:
            index
        case .advanceBeforeFirstBar:
            index + 1
        }
    }
}

struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let originXYZ: [Float]?
        let sizeWH: [Float]?
        let alpha: Double?
        let colorRGB: [Float]?
        // These fields exist only to prove the renderer never reads them.
        let scaleXYZ: [Float]?
        let anglesXYZ: [Float]?
    }
}

struct SceneFrameContext {
    let sceneTime: TimeInterval
    let dynamicValues: SceneDynamicSnapshot
    let audioSpectrum: SceneAudioSpectrumSnapshot
}

struct SceneMetalRenderer {}

// The production neutral helper lives with sprite animation. Keep this focused
// harness independent from TEX parsing while preserving the same uniform shape.
extension SceneLayerFragmentUniforms {
    static func neutral(
        alpha: Float = 1,
        dependencyBlendMode: Int? = nil
    ) -> SceneLayerFragmentUniforms {
        SceneLayerFragmentUniforms(
            time: 0,
            alpha: alpha,
            effectFlags: 0,
            dependencyBlendMode: UInt32(dependencyBlendMode ?? 0),
            cursorUV: .zero,
            _pad1: .zero,
            tint: SIMD4(repeating: 1),
            effectParams0: .zero,
            effectParams1: .zero,
            effectParams2: .zero,
            effectParams3: .zero,
            effectParams4: .zero,
            effectParams5: SIMD4(1, 1, 0, 0),
            textureFrame0: SIMD4(0, 0, 1, 0),
            textureFrame1: SIMD4(0, 1, 0, 0)
        )
    }
}

final class TextureToken {}

@main
enum Harness {
    static let width = 256
    static let height = 128
    static let layerID = 7

    static func plan(
        widthMultiplier: Float = 1
    ) -> SceneScriptAudioBarsPlan {
        SceneScriptAudioBarsPlan(
            layerID: layerID,
            sourceSHA256: "fixture-source",
            host: "fixture-host",
            modelPath: "fixture/model.json",
            materialPath: "fixture/material.json",
            texturePath: "fixture/texture.tex",
            barCount: 64,
            audioResolution: 64,
            channel: .average,
            widthMultiplier: widthMultiplier,
            heightMultiplier: 40,
            depthMultiplier: 1,
            xStep: 0.028,
            yStep: 0,
            angleDegrees: 0,
            alignment: .centre,
            firstStepPolicy: .ownerAtBaseOrigin
        )
    }

    static func layer(size: [Float] = [0.02, 0.02]) -> SceneRenderDescriptor.Layer {
        SceneRenderDescriptor.Layer(
            id: layerID,
            originXYZ: [-0.9, 1, 0],
            sizeWH: size,
            alpha: 0.9,
            colorRGB: [1, 1, 1],
            scaleXYZ: [99, 99, 99],
            anglesXYZ: [1.2, 2.3, 3.4]
        )
    }

    static func spectrum() -> SceneAudioSpectrumSnapshot {
        var bands = Array(repeating: Float.zero, count: 64)
        bands[0] = 2
        bands[1] = 1
        bands[2] = 0.5
        return SceneAudioSpectrumSnapshot(
            left: Array(repeating: 0, count: 16),
            right: Array(repeating: 0, count: 16),
            left64: bands,
            right64: bands,
            generation: 1
        )
    }

    static func dynamicSnapshot() -> SceneDynamicSnapshot {
        let alpha = SceneDynamicTarget.layer(layerID: layerID, field: .alpha)
        let color = SceneDynamicTarget.layer(layerID: layerID, field: .color)
        return SceneDynamicSnapshotResolver().resolve(
            frameIndex: 0,
            generation: 1,
            definitions: [
                SceneDynamicTargetDefinition(
                    target: alpha,
                    valueType: .scalar,
                    authoredValue: .scalar(0.9)
                ),
                SceneDynamicTargetDefinition(
                    target: color,
                    valueType: .vector3,
                    authoredValue: .vector3(1, 1, 1)
                ),
            ],
            sceneScriptValues: [
                alpha: .scalar(0.5),
                color: .vector3(0.25, 0.5, 1),
            ]
        ).snapshot
    }

    static func frameContext() -> SceneFrameContext {
        SceneFrameContext(
            sceneTime: 3.5,
            dynamicValues: dynamicSnapshot(),
            audioSpectrum: spectrum()
        )
    }

    static func encodingMetrics() -> [String: Any] {
        let token = TextureToken()
        var bindCount = 0
        var drawCount = 0
        var textureIDs: Set<ObjectIdentifier> = []
        var observedTimes: Set<Float> = []
        let matrices = Array(
            repeating: matrix_identity_float4x4,
            count: SceneScriptAudioBarsGeometry.instanceBudget
        )
        var uniforms = SceneLayerFragmentUniforms.neutral(alpha: 0.5)
        uniforms.time = 3.5
        let encoded = SceneScriptAudioBarsDrawLoop.encode(
            texture: token,
            matrices: matrices,
            uniforms: uniforms,
            bind: { bindCount += 1 },
            draw: { texture, _, uniforms in
                drawCount += 1
                textureIDs.insert(ObjectIdentifier(texture))
                observedTimes.insert(uniforms.time)
            }
        )
        var invalidBindCount = 0
        var invalidDrawCount = 0
        let invalidRejected = !SceneScriptAudioBarsDrawLoop.encode(
            texture: token,
            matrices: Array(matrices.dropLast()),
            uniforms: uniforms,
            bind: { invalidBindCount += 1 },
            draw: { _, _, _ in invalidDrawCount += 1 }
        )
        return [
            "encoded": encoded,
            "bindCount": bindCount,
            "drawCount": drawCount,
            "uniqueTextureCount": textureIDs.count,
            "observedTimeCount": observedTimes.count,
            "invalidRejected": invalidRejected,
            "invalidBindCount": invalidBindCount,
            "invalidDrawCount": invalidDrawCount,
        ]
    }

    static func texture(
        device: MTLDevice,
        usage: MTLTextureUsage,
        width: Int,
        height: Int
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)
    }

    static func whiteTexture(device: MTLDevice) -> MTLTexture? {
        guard let texture = texture(
            device: device,
            usage: .shaderRead,
            width: 1,
            height: 1
        ) else {
            return nil
        }
        var pixel: [UInt8] = [255, 255, 255, 255]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixel,
            bytesPerRow: 4
        )
        return texture
    }

    static func pixels(_ texture: MTLTexture) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return pixels
    }

    static func verticalCoverage(
        _ pixels: [UInt8],
        barIndex: Int
    ) -> Int {
        let worldX = -0.9 + Float(barIndex) * 0.028
        let centerX = Int(round((worldX + 1) * 0.5 * Float(width - 1)))
        var rows: Set<Int> = []
        for y in 0..<height {
            for x in max(0, centerX - 1)...min(width - 1, centerX + 1) {
                let alpha = pixels[(y * width + x) * 4 + 3]
                if alpha > 0 {
                    rows.insert(y)
                }
            }
        }
        return rows.count
    }

    static func centerPixel(
        _ pixels: [UInt8],
        barIndex: Int
    ) -> [Int] {
        let worldX = -0.9 + Float(barIndex) * 0.028
        let x = Int(round((worldX + 1) * 0.5 * Float(width - 1)))
        let offset = ((height / 2) * width + x) * 4
        return (0..<4).map { Int(pixels[offset + $0]) }
    }

    static func gpuMetrics() -> [String: Any]? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneImageLayerPipeline(
                  device: device,
                  pixelFormat: .rgba8Unorm,
                  blendMode: .sourceOver
              ),
              let source = whiteTexture(device: device),
              let target = texture(
                  device: device,
                  usage: [.renderTarget, .shaderRead],
                  width: width,
                  height: height
              ),
              let commandBuffer = queue.makeCommandBuffer() else {
            return nil
        }

        let renderer = SceneMetalRenderer()
        let mainPass = SceneMainPassEncoder(
            commandBuffer: commandBuffer,
            target: target,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let encoded = renderer.renderSceneScriptAudioBars(
            plan: plan(),
            layer: layer(),
            texture: source,
            pipeline: pipeline,
            frameContext: frameContext(),
            sceneOrthoHeight: 2,
            viewProjection: SceneMatrix.translation(SIMD3(0, -1, 0)),
            mainPass: mainPass
        )
        mainPass.finishEnsuringClear()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard encoded, commandBuffer.status == .completed else {
            return ["encoded": false]
        }
        let output = pixels(target)

        guard let invalidCommand = queue.makeCommandBuffer(),
              let invalidTarget = texture(
                  device: device,
                  usage: [.renderTarget, .shaderRead],
                  width: width,
                  height: height
              ) else {
            return ["encoded": false]
        }
        let invalidPass = SceneMainPassEncoder(
            commandBuffer: invalidCommand,
            target: invalidTarget,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        let invalidGeometryRejected = !renderer.renderSceneScriptAudioBars(
            plan: plan(),
            layer: layer(size: [0, 0.02]),
            texture: source,
            pipeline: pipeline,
            frameContext: frameContext(),
            sceneOrthoHeight: 2,
            viewProjection: SceneMatrix.translation(SIMD3(0, -1, 0)),
            mainPass: invalidPass
        )
        invalidPass.finishEnsuringClear()
        invalidCommand.commit()
        invalidCommand.waitUntilCompleted()

        guard let finishedCommand = queue.makeCommandBuffer(),
              let finishedTarget = texture(
                  device: device,
                  usage: [.renderTarget, .shaderRead],
                  width: width,
                  height: height
              ) else {
            return ["encoded": false]
        }
        let finishedPass = SceneMainPassEncoder(
            commandBuffer: finishedCommand,
            target: finishedTarget,
            clearColor: MTLClearColorMake(0, 0, 0, 0)
        )
        finishedPass.finishEnsuringClear()
        let encoderFailureRejected = !renderer.renderSceneScriptAudioBars(
            plan: plan(),
            layer: layer(),
            texture: source,
            pipeline: pipeline,
            frameContext: frameContext(),
            sceneOrthoHeight: 2,
            viewProjection: SceneMatrix.translation(SIMD3(0, -1, 0)),
            mainPass: finishedPass
        )
        finishedCommand.commit()
        finishedCommand.waitUntilCompleted()

        return [
            "encoded": true,
            "visiblePixelCount": stride(
                from: 3,
                to: output.count,
                by: 4
            ).reduce(0) { $0 + (output[$1] > 0 ? 1 : 0) },
            "doubleAmplitudeCoverage": verticalCoverage(output, barIndex: 0),
            "unitAmplitudeCoverage": verticalCoverage(output, barIndex: 1),
            "halfAmplitudeCoverage": verticalCoverage(output, barIndex: 2),
            "unitCenterPixel": centerPixel(output, barIndex: 1),
            "invalidGeometryRejected": invalidGeometryRejected,
            "encoderFailureRejected": encoderFailureRejected,
        ]
    }

    static func main() throws {
        let gpu = gpuMetrics()
        let result: [String: Any] = [
            "encoding": encodingMetrics(),
            "metalUnavailable": gpu == nil,
            "gpu": gpu ?? [:],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneScriptAudioBarsRendererTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-script-audio-bars-renderer-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-script-audio-bars-renderer"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def require_metal(self) -> dict[str, object]:
        if self.result["metalUnavailable"]:
            self.skipTest("Metal is unavailable")
        return self.result["gpu"]

    def test_encoding_loop_binds_once_and_reuses_one_texture_for_64_draws(self) -> None:
        encoding = self.result["encoding"]
        self.assertTrue(encoding["encoded"])
        self.assertEqual(encoding["bindCount"], 1)
        self.assertEqual(encoding["drawCount"], 64)
        self.assertEqual(encoding["uniqueTextureCount"], 1)
        self.assertEqual(encoding["observedTimeCount"], 1)
        self.assertTrue(encoding["invalidRejected"])
        self.assertEqual(encoding["invalidBindCount"], 0)
        self.assertEqual(encoding["invalidDrawCount"], 0)

    def test_renderer_never_reads_authored_scale_or_angles(self) -> None:
        source = RENDERER_SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("scaleXYZ", source)
        self.assertNotIn("anglesXYZ", source)
        self.assertIn("SceneLayerFragmentUniforms.neutral(", source)
        self.assertIn("SceneDynamicLayerValues.alpha(", source)
        self.assertIn("SceneDynamicLayerValues.color(", source)

    def test_gpu_draws_dynamic_tint_and_alpha_with_source_over(self) -> None:
        gpu = self.require_metal()
        self.assertTrue(gpu["encoded"], gpu)
        self.assertGreater(gpu["visiblePixelCount"], 0)
        expected = [32, 64, 128, 128]
        for actual, component in zip(gpu["unitCenterPixel"], expected):
            self.assertAlmostEqual(actual, component, delta=3)

    def test_gpu_preserves_spectrum_values_above_one(self) -> None:
        gpu = self.require_metal()
        double = gpu["doubleAmplitudeCoverage"]
        unit = gpu["unitAmplitudeCoverage"]
        half = gpu["halfAmplitudeCoverage"]
        self.assertGreater(double, int(unit * 1.7), gpu)
        self.assertGreater(unit, int(half * 1.7), gpu)

    def test_invalid_geometry_and_finished_encoder_fail_closed(self) -> None:
        gpu = self.require_metal()
        self.assertTrue(gpu["invalidGeometryRejected"])
        self.assertTrue(gpu["encoderFailureRejected"])


if __name__ == "__main__":
    unittest.main()
