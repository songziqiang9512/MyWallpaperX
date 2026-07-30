#!/usr/bin/env python3
"""WaterRipple pipeline 的跨时间 GPU 像素门。

使用项目自有的合成网格、法线和遮罩验证：
- alpha=0 的 straight RGBA data 仍能经公共 uploader 驱动 normal/mask；
- 非零 animationSpeed 会让受遮罩区域跨时间变化；
- 遮罩外像素保持原样；
- animationSpeed 与 scrollSpeed 都为零时跨时间稳定。
"""

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
    SOURCE_ROOT / "RenderGraph/SceneEffectMaskSemantics.swift",
    SOURCE_ROOT / "Effects/SceneWaterRippleRuntimePlan.swift",
    SOURCE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SOURCE_ROOT / "Effects/SceneWaterRipplePipeline.swift",
]


HARNESS = r'''
import CoreGraphics
import Foundation
import Metal
import simd

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

struct SceneQuadVertex {
    let position: SIMD2<Float>
    let texcoord: SIMD2<Float>
}

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [Int?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let effects: [EffectDescriptor]
    }
}

@main
enum Harness {
    static let size = 32

    static func texture(
        device: MTLDevice,
        width: Int = size,
        height: Int = size
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        return device.makeTexture(descriptor: descriptor)!
    }

    static func uploadRGBA(_ rgba: [UInt8], to texture: MTLTexture) {
        var bgra = rgba
        for index in stride(from: 0, to: rgba.count, by: 4) {
            bgra[index] = rgba[index + 2]
            bgra[index + 2] = rgba[index]
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: &bgra,
            bytesPerRow: texture.width * 4
        )
    }

    static func readRGBA(_ texture: MTLTexture) -> [UInt8] {
        var bgra = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &bgra,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        var rgba = bgra
        for index in stride(from: 0, to: bgra.count, by: 4) {
            rgba[index] = bgra[index + 2]
            rgba[index + 2] = bgra[index]
        }
        return rgba
    }

    static func sourcePixels() -> [UInt8] {
        (0 ..< size).flatMap { y in
            (0 ..< size).flatMap { x -> [UInt8] in
                let checker = ((x / 2) + (y / 2)).isMultiple(of: 2)
                return checker ? [240, 32, 16, 255] : [12, 180, 236, 255]
            }
        }
    }

    static func normalPixels() -> [UInt8] {
        (0 ..< 8).flatMap { y in
            (0 ..< 8).flatMap { x -> [UInt8] in
                let red: UInt8 = (x + y).isMultiple(of: 2) ? 230 : 26
                let green: UInt8 = (x / 2 + y).isMultiple(of: 2) ? 210 : 46
                return [red, green, 220, 0]
            }
        }
    }

    static func maskPixels() -> [UInt8] {
        (0 ..< size).flatMap { _ in
            (0 ..< size).flatMap { x -> [UInt8] in
                let value: UInt8 = x < size / 2 ? 0 : 255
                return [value, value, value, 0]
            }
        }
    }

    static func dataTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixels: [UInt8]
    ) -> MTLTexture {
        precondition(pixels.count == width * height * 4)
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        guard case let .loaded(texture) = SceneImageTextureUploader.upload(
            image: image,
            purpose: .preservedChannels,
            maxDimension: 4096,
            device: device
        ) else {
            preconditionFailure("straight RGBA data upload failed")
        }
        return texture
    }

    static func render(
        time: Float,
        plan: SceneWaterRippleNormalPlan,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWaterRipplePipeline
    ) -> (encoded: Bool, bytes: [UInt8]) {
        let source = texture(device: device)
        let normal = dataTexture(
            device: device,
            width: 8,
            height: 8,
            pixels: normalPixels()
        )
        let mask = dataTexture(
            device: device,
            width: size,
            height: size,
            pixels: maskPixels()
        )
        let target = texture(device: device)
        uploadRGBA(sourcePixels(), to: source)
        let command = queue.makeCommandBuffer()!
        let encoded = pipeline.encode(
            source: source,
            normalMap: normal,
            target: target,
            plan: plan,
            time: time,
            maskTexture: mask,
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        return (encoded, readRGBA(target))
    }

    static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        (0 ..< lhs.count / 4).filter { pixel in
            let start = pixel * 4
            return lhs[start ..< start + 4] != rhs[start ..< start + 4]
        }.count
    }

    static func leftHalfUnchanged(_ output: [UInt8]) -> Bool {
        let source = sourcePixels()
        return (0 ..< size).allSatisfy { y in
            (0 ..< size / 2 - 1).allSatisfy { x in
                let start = (y * size + x) * 4
                return output[start ..< start + 4] == source[start ..< start + 4]
            }
        }
    }

    static func main() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneWaterRipplePipeline(device: device) else {
            print("{\"skipped\": true}")
            return
        }
        let animatedPlan = SceneWaterRippleNormalPlan(
            animationSpeed: 0.15,
            scale: 1,
            scrollSpeed: 0,
            direction: 0,
            ratio: 1,
            strength: 0.1
        )
        let staticPlan = SceneWaterRippleNormalPlan(
            animationSpeed: 0,
            scale: 1,
            scrollSpeed: 0,
            direction: 0,
            ratio: 1,
            strength: 0.1
        )
        let animatedStart = render(
            time: 0,
            plan: animatedPlan,
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let animatedLater = render(
            time: 8,
            plan: animatedPlan,
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let staticStart = render(
            time: 0,
            plan: staticPlan,
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let staticLater = render(
            time: 8,
            plan: staticPlan,
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let result: [String: Any] = [
            "animatedEncoded": animatedStart.encoded && animatedLater.encoded,
            "animatedChangedPixels": changedPixels(
                animatedStart.bytes, animatedLater.bytes
            ),
            "maskPreservesLeftHalf": leftHalfUnchanged(animatedStart.bytes)
                && leftHalfUnchanged(animatedLater.bytes),
            "zeroSpeedStable": staticStart.encoded
                && staticLater.encoded
                && changedPixels(staticStart.bytes, staticLater.bytes) == 0,
        ]
        let data = try! JSONSerialization.data(withJSONObject: result)
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class SceneWaterRippleRenderingTests(unittest.TestCase):
    def test_time_drives_masked_water_ripple_pixels(self) -> None:
        swiftc = shutil.which("swiftc")
        self.assertIsNotNone(swiftc, "swiftc unavailable")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            harness = root / "Harness.swift"
            executable = root / "water-ripple-render-harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(executable),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(executable)],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                completed.returncode,
                0,
                f"stdout={completed.stdout}\nstderr={completed.stderr}",
            )

        output = json.loads(completed.stdout)
        if output.get("skipped"):
            self.skipTest("Metal device unavailable")
        self.assertTrue(output["animatedEncoded"], output)
        self.assertGreater(output["animatedChangedPixels"], 100, output)
        self.assertTrue(output["maskPreservesLeftHalf"], output)
        self.assertTrue(output["zeroSpeedStable"], output)


if __name__ == "__main__":
    unittest.main()
