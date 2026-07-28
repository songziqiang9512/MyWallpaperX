#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PIPELINE = (
    ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneLightShaftsPipeline.swift"
)


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneQuadVertex {
    var position: SIMD2<Float>
    var texcoord: SIMD2<Float>
}

struct SceneLightShaftsExecutionPlan {
    let points: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    let feather: SIMD2<Float>
    let scale: SIMD2<Float>
    let smoothness: Float
    let speed: Float
    let intensity: Float
    let exponent: Float
    let noiseTexturePath: String
    let gradientTexturePath: String
}

struct SceneLightShaftsEffectTextures {
    let noise: MTLTexture?
    let gradient: MTLTexture?
    let noisePath: String
    let gradientPath: String

    func matches(_ plan: SceneLightShaftsExecutionPlan) -> Bool {
        noise != nil
            && gradient != nil
            && noisePath == plan.noiseTexturePath
            && gradientPath == plan.gradientTexturePath
    }
}

@main
enum Harness {
    static let size = 64

    static func texture(
        device: MTLDevice,
        width: Int,
        height: Int,
        format: MTLPixelFormat,
        usage: MTLTextureUsage
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func upload(
        _ bytes: [UInt8],
        width: Int,
        height: Int,
        to texture: MTLTexture
    ) {
        var value = bytes
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: &value,
            bytesPerRow: width * 4
        )
    }

    static func makeResources(device: MTLDevice) -> SceneLightShaftsEffectTextures {
        let noise = texture(
            device: device,
            width: 8,
            height: 8,
            format: .rgba8Unorm,
            usage: [.shaderRead]
        )
        let noiseBytes = (0..<(8 * 8)).flatMap { index -> [UInt8] in
            let x = index % 8
            let y = index / 8
            return [
                UInt8((x * 31 + y * 17) % 256),
                UInt8((x * 11 + y * 47 + 71) % 256),
                UInt8((x * 53 + y * 7 + 29) % 256),
                255,
            ]
        }
        upload(noiseBytes, width: 8, height: 8, to: noise)
        let gradient = texture(
            device: device,
            width: 2,
            height: 1,
            format: .rgba8Unorm,
            usage: [.shaderRead]
        )
        upload(
            [255, 64, 16, 255, 16, 128, 255, 255],
            width: 2,
            height: 1,
            to: gradient
        )
        return .init(
            noise: noise,
            gradient: gradient,
            noisePath: "materials/util/noise",
            gradientPath: "materials/gradient/gradient_iridescent"
        )
    }

    static func plan() -> SceneLightShaftsExecutionPlan {
        .init(
            points: (
                SIMD2<Float>(0.2, 0.2),
                SIMD2<Float>(0.8, 0.2),
                SIMD2<Float>(0.8, 0.8),
                SIMD2<Float>(0.2, 0.8)
            ),
            feather: SIMD2<Float>(0.12, 0.12),
            scale: SIMD2<Float>(0.8, 0.5),
            smoothness: 0.85,
            speed: 0.7,
            intensity: 2.5,
            exponent: 0.6,
            noiseTexturePath: "materials/util/noise",
            gradientTexturePath: "materials/gradient/gradient_iridescent"
        )
    }

    static func render(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneLightShaftsPipeline,
        resources: SceneLightShaftsEffectTextures,
        time: Float,
        alpha: Float
    ) -> (accepted: Bool, bytes: [UInt8]) {
        let target = texture(
            device: device,
            width: size,
            height: size,
            format: .bgra8Unorm,
            usage: [.renderTarget]
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        let accepted = pipeline.draw(
            plan: plan(),
            resources: resources,
            mvp: simd_float4x4(diagonal: SIMD4<Float>(0.002, 0.002, 1, 1)),
            time: time,
            alpha: alpha,
            encoder: encoder
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        target.getBytes(
            &bytes,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return (accepted, bytes)
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneLightShaftsPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let resources = makeResources(device: device)
        let first = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            time: 0,
            alpha: 1
        )
        let second = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            time: 1.25,
            alpha: 1
        )
        let half = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            time: 0,
            alpha: 0.5
        )
        let invalid = render(
            device: device,
            queue: queue,
            pipeline: pipeline,
            resources: resources,
            time: 0,
            alpha: 1.1
        )
        let alphaValues = stride(from: 3, to: first.bytes.count, by: 4).map {
            first.bytes[$0]
        }
        let halfAlpha = stride(from: 3, to: half.bytes.count, by: 4).map {
            half.bytes[$0]
        }
        let premultiplied = stride(from: 0, to: first.bytes.count, by: 4)
            .allSatisfy { offset in
                max(
                    first.bytes[offset],
                    first.bytes[offset + 1],
                    first.bytes[offset + 2]
                ) <= first.bytes[offset + 3]
            }
        let centerOffset = ((size / 2) * size + size / 2) * 4
        let result: [String: Any] = [
            "metalUnavailable": false,
            "accepted": first.accepted && second.accepted && half.accepted,
            "invalidRejected": !invalid.accepted,
            "centerAlpha": first.bytes[centerOffset + 3],
            "cornerAlpha": first.bytes[3],
            "nonzeroPixels": alphaValues.filter { $0 > 0 }.count,
            "premultiplied": premultiplied,
            "timeChangesOutput": first.bytes != second.bytes,
            "halfAlphaLower": (halfAlpha.max() ?? 0) < (alphaValues.max() ?? 0),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneLightShaftsRenderingTests(unittest.TestCase):
    def test_quad_is_animated_feathered_and_premultiplied(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-light-shafts-rendering-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-light-shafts-rendering"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    str(PIPELINE),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        if result["metalUnavailable"]:
            self.skipTest("Metal is unavailable")
        self.assertTrue(result["accepted"], result)
        self.assertTrue(result["invalidRejected"], result)
        self.assertGreater(result["centerAlpha"], 0, result)
        self.assertEqual(result["cornerAlpha"], 0, result)
        self.assertGreater(result["nonzeroPixels"], 0, result)
        self.assertTrue(result["premultiplied"], result)
        self.assertTrue(result["timeChangesOutput"], result)
        self.assertTrue(result["halfAlphaLower"], result)


if __name__ == "__main__":
    unittest.main()
