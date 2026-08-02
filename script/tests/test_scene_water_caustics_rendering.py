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
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "Effects/SceneWaterCausticsPipeline.swift",
]

HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneWaterCausticsExecutionPlan {
    let blendMode: Int
    let brightness: Float
    let glow: Float
    let scale: Float
    let speed: Float
    let timeOffset: Float
    let distortion: Float
    let chromatic: Float
    let blur: Float
    let colorStart: SIMD3<Float>
    let colorEnd: SIMD3<Float>
    let maskTexturePath: String?
    let patternTexturePath: String
    let glowTexturePath: String
    let noiseTexturePath: String
    let offsetTexturePath: String
}

struct SceneWaterCausticsEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?
    let pattern: MTLTexture?
    let patternPath: String
    let glow: MTLTexture?
    let glowPath: String
    let noise: MTLTexture?
    let noisePath: String
    let offset: MTLTexture?
    let offsetPath: String

    func matches(_ plan: SceneWaterCausticsExecutionPlan) -> Bool {
        (plan.maskTexturePath == nil || mask != nil)
            && maskPath == plan.maskTexturePath
            && pattern != nil && patternPath == plan.patternTexturePath
            && glow != nil && glowPath == plan.glowTexturePath
            && noise != nil && noisePath == plan.noiseTexturePath
            && offset != nil && offsetPath == plan.offsetTexturePath
    }
}

@main
enum Harness {
    static let size = 16

    static func texture(
        device: MTLDevice,
        usage: MTLTextureUsage
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func bytes(_ body: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let value = body(x, y)
                let offset = (y * size + x) * 4
                result[offset] = value.0
                result[offset + 1] = value.1
                result[offset + 2] = value.2
                result[offset + 3] = value.3
            }
        }
        return result
    }

    static func upload(_ bytes: [UInt8], to texture: MTLTexture) {
        bytes.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: size * 4
            )
        }
    }

    static func read(_ texture: MTLTexture) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(
            &result,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return result
    }

    static func pixel(_ bytes: [UInt8], x: Int, y: Int) -> [UInt8] {
        let offset = (y * size + x) * 4
        return Array(bytes[offset..<(offset + 4)])
    }

    static func allPixelsArePremultiplied(_ bytes: [UInt8]) -> Bool {
        stride(from: 0, to: bytes.count, by: 4).allSatisfy { offset in
            let alpha = Int(bytes[offset + 3])
            return Int(bytes[offset]) <= alpha + 1
                && Int(bytes[offset + 1]) <= alpha + 1
                && Int(bytes[offset + 2]) <= alpha + 1
        }
    }

    static func alphaMatches(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        stride(from: 3, to: lhs.count, by: 4).allSatisfy { lhs[$0] == rhs[$0] }
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneWaterCausticsPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }

        let source = texture(device: device, usage: .shaderRead)
        let sourceBytes = bytes { x, y in
            guard (3...12).contains(x), (3...12).contains(y) else { return (0, 0, 0, 0) }
            return (32, 48, 96, 128)
        }
        upload(sourceBytes, to: source)

        let pattern = texture(device: device, usage: .shaderRead)
        upload(bytes { x, y in
            let value: UInt8 = ((x + y) % 4 < 2) ? 245 : 18
            return (value, value, value, 255)
        }, to: pattern)
        let glow = texture(device: device, usage: .shaderRead)
        upload(bytes { x, y in
            let value = UInt8((x * 31 + y * 17) % 256)
            return (value, value, value, 255)
        }, to: glow)
        let noise = texture(device: device, usage: .shaderRead)
        upload(bytes { x, y in
            let red = UInt8((x * 53 + y * 29) % 256)
            let green = UInt8((x * 19 + y * 47) % 256)
            return (red, green, 255 &- red, 255)
        }, to: noise)
        let offset = texture(device: device, usage: .shaderRead)
        upload(bytes { x, y in
            let red = UInt8((x * 37 + y * 11) % 256)
            let green = UInt8((x * 7 + y * 61) % 256)
            return (red, green, 255 &- green, 255)
        }, to: offset)

        let plan = SceneWaterCausticsExecutionPlan(
            blendMode: 8,
            brightness: 1.5,
            glow: 0.6,
            scale: 2,
            speed: 5,
            timeOffset: 0,
            distortion: 1,
            chromatic: 1,
            blur: 0.2,
            colorStart: SIMD3(0.7, 0.9, 1),
            colorEnd: SIMD3(0.4, 0.6, 1),
            maskTexturePath: nil,
            patternTexturePath: "pattern",
            glowTexturePath: "glow",
            noiseTexturePath: "noise",
            offsetTexturePath: "offset"
        )
        let resources = SceneWaterCausticsEffectTextures(
            mask: nil,
            maskUVScale: SIMD2(repeating: 1),
            maskPath: nil,
            pattern: pattern,
            patternPath: "pattern",
            glow: glow,
            glowPath: "glow",
            noise: noise,
            noisePath: "noise",
            offset: offset,
            offsetPath: "offset"
        )
        let missingPattern = SceneWaterCausticsEffectTextures(
            mask: nil,
            maskUVScale: SIMD2(repeating: 1),
            maskPath: nil,
            pattern: nil,
            patternPath: "pattern",
            glow: glow,
            glowPath: "glow",
            noise: noise,
            noisePath: "noise",
            offset: offset,
            offsetPath: "offset"
        )
        let output0 = texture(device: device, usage: [.shaderRead, .renderTarget])
        let output1 = texture(device: device, usage: [.shaderRead, .renderTarget])
        let command = queue.makeCommandBuffer()!
        let firstEncoded = pipeline.encode(
            source: source,
            resources: resources,
            target: output0,
            plan: plan,
            time: 0,
            commandBuffer: command
        )
        let secondEncoded = pipeline.encode(
            source: source,
            resources: resources,
            target: output1,
            plan: plan,
            time: 100,
            commandBuffer: command
        )
        let missingRejected = !pipeline.encode(
            source: source,
            resources: missingPattern,
            target: output1,
            plan: plan,
            time: 0,
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        precondition(command.status == .completed)

        let first = read(output0)
        let second = read(output1)
        let result: [String: Any] = [
            "metalUnavailable": false,
            "encoded": firstEncoded && secondEncoded,
            "missingPatternRejected": missingRejected,
            "transparentCorner": pixel(first, x: 0, y: 0),
            "center": pixel(first, x: 7, y: 7),
            "sourceCenter": pixel(sourceBytes, x: 7, y: 7),
            "alphaPreserved": alphaMatches(sourceBytes, first) && alphaMatches(sourceBytes, second),
            "premultiplied": allPixelsArePremultiplied(first) && allPixelsArePremultiplied(second),
            "timeVarying": first != second,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneWaterCausticsRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-water-caustics-rendering-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-water-caustics-rendering"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-module-cache-path",
                str(root / "module-cache"),
                "-framework",
                "Metal",
                "-o",
                str(binary),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        executed = subprocess.run(
            [str(binary)],
            check=False,
            capture_output=True,
            text=True,
        )
        if executed.returncode != 0:
            raise RuntimeError(executed.stderr)
        cls.result = json.loads(executed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_caustics_executes_with_time_variation_and_strict_resources(self) -> None:
        self.assertTrue(self.result["encoded"])
        self.assertTrue(self.result["timeVarying"])
        self.assertTrue(self.result["missingPatternRejected"])
        self.assertNotEqual(self.result["center"], self.result["sourceCenter"])

    def test_caustics_preserves_alpha_and_premultiplied_transparency(self) -> None:
        self.assertEqual(self.result["transparentCorner"], [0, 0, 0, 0])
        self.assertTrue(self.result["alphaPreserved"])
        self.assertTrue(self.result["premultiplied"])


if __name__ == "__main__":
    unittest.main()
