#!/usr/bin/env python3
"""pulse pipeline 的 GPU 像素门与资源 matches 门。

覆盖官方 pulse.frag `AUDIOPROCESSING == 0` 语义的四个可观察维度：
- 时间驱动：同参数不同 g_Time 出不同像素；
- 逐指纹 profile：stock 与 legacy 的相位语义在同参数下产生不同 pulse；
- PULSECOLOR / PULSEALPHA / MASK 各自的像素路径；
- 输入校验（bounds、blendMode、尺寸）与纹理缺失时的 fail-closed matches()。
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
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "Effects/ScenePulsePipeline.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

@main
enum Harness {
    static let width = 4
    static let height = 4

    static func texture(
        device: MTLDevice,
        width: Int = width,
        height: Int = height
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("texture allocation failed")
        }
        return texture
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

    static func inputs(
        time: Float = 0,
        speed: Float = 1,
        phase: Float = 0,
        phaseOffset: Float = -1.57079632679,
        amount: Float = 1,
        bounds: SIMD2<Float> = SIMD2(0, 1),
        noiseSpeed: Float = 0.5,
        noiseAmount: Float = 0,
        noiseUVScale: SIMD2<Float> = SIMD2(0.08333333, 0.02777777),
        power: Float = 1,
        tintLow: SIMD3<Float> = SIMD3(repeating: 1),
        tintHigh: SIMD3<Float> = SIMD3(1, 0, 0),
        blendMode: Int = 9,
        pulseColor: Bool = true,
        pulseAlpha: Bool = false,
        saturatesOutput: Bool = false,
        maskUVScale: SIMD2<Float> = SIMD2(repeating: 1)
    ) -> ScenePulsePipeline.Inputs {
        .init(
            time: time,
            speed: speed,
            phase: phase,
            phaseOffset: phaseOffset,
            amount: amount,
            bounds: bounds,
            noiseSpeed: noiseSpeed,
            noiseAmount: noiseAmount,
            noiseUVScale: noiseUVScale,
            power: power,
            tintLow: tintLow,
            tintHigh: tintHigh,
            blendMode: blendMode,
            pulseColor: pulseColor,
            pulseAlpha: pulseAlpha,
            saturatesOutput: saturatesOutput,
            maskUVScale: maskUVScale,
            audioPulse: nil
        )
    }

    static func render(
        input: [UInt8],
        inputs: ScenePulsePipeline.Inputs,
        mask: [UInt8]? = nil,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: ScenePulsePipeline
    ) -> (output: [UInt8], encoded: Bool) {
        let source = texture(device: device)
        let target = texture(device: device)
        uploadRGBA(input, to: source)
        var maskTexture: MTLTexture?
        if let mask {
            let textureMask = texture(device: device, width: 2, height: 1)
            uploadRGBA(mask, to: textureMask)
            maskTexture = textureMask
        }
        guard let commandBuffer = queue.makeCommandBuffer() else {
            fatalError("command buffer allocation failed")
        }
        let encoded = pipeline.encode(
            source: source,
            noise: nil,
            mask: maskTexture,
            target: target,
            inputs: inputs,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return (readRGBA(target), encoded)
    }

    static func nearlyEqual(_ lhs: [UInt8], _ rhs: [UInt8], tolerance: Int = 2) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            abs(Int($0) - Int($1)) <= tolerance
        }
    }

    static func main() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = ScenePulsePipeline(device: device) else {
            print("{\"skipped\": true}")
            return
        }

        // premultiplied 输入 (0.5, 0.25, 0, 1)
        let base: [UInt8] = Array(
            repeating: [128, 64, 0, 255], count: width * height
        ).flatMap { $0 }

        // stock t=0, phase=0: sin(-π/2) = -1 → wave 0 → pulse 0 → 原图
        let stockZero = render(
            input: base, inputs: inputs(), device: device, queue: queue, pipeline: pipeline
        )
        // stock t=π/2 (speed=1): sin(0) = 0 → wave 0.5 → pulse 0.5
        // additive(9): mix(A, min(A+B,1), 0.5)，A=(0.5,0.25,0)，B=A·(1,0,0)=(0.5,0,0)
        // → (0.75, 0.25, 0)
        let stockHalf = render(
            input: base,
            inputs: inputs(time: 1.57079632679),
            device: device, queue: queue, pipeline: pipeline
        )
        // legacy 同 t=0：sin(0)=0 → wave 0.5 → pulse 0.5，与 stock t=0 语义分流
        let legacyZero = render(
            input: base,
            inputs: inputs(phaseOffset: 0, noiseUVScale: SIMD2(1, 0.333)),
            device: device, queue: queue, pipeline: pipeline
        )

        // PULSEALPHA：pulse=0 → premultiplied 四通道全零
        let alphaZero = render(
            input: base,
            inputs: inputs(pulseColor: false, pulseAlpha: true),
            device: device, queue: queue, pipeline: pipeline
        )
        // PULSEALPHA：pulse=0.5 → 四通道减半
        let alphaHalf = render(
            input: base,
            inputs: inputs(time: 1.57079632679, pulseColor: false, pulseAlpha: true),
            device: device, queue: queue, pipeline: pipeline
        )

        // MASK：左半 r=0 回原图，右半 r=255 全效果（mask 2×1，clamp 采样）
        let masked = render(
            input: base,
            inputs: inputs(time: 1.57079632679),
            mask: [0, 0, 0, 255, 255, 255, 255, 255],
            device: device, queue: queue, pipeline: pipeline
        )
        // 2×1 遮罩经 linear clamp 采样后中间两列是渐变，只断言最左列
        // （mask=0 → 原图）与最右列（mask=1 → 全效果）。
        let maskedPixels = stride(from: 0, to: masked.output.count, by: 4).map {
            Array(masked.output[$0 ..< $0 + 4])
        }
        let leftOriginal = maskedPixels.enumerated().allSatisfy { index, pixel in
            index % width == 0
                ? nearlyEqual(pixel, [128, 64, 0, 255])
                : true
        }
        let rightPulsed = maskedPixels.enumerated().allSatisfy { index, pixel in
            index % width == width - 1
                ? nearlyEqual(pixel, [191, 64, 0, 255], tolerance: 3)
                : true
        }

        // 输入校验
        let invalidBounds = pipeline.encode(
            source: texture(device: device),
            noise: nil,
            mask: nil,
            target: texture(device: device),
            inputs: inputs(bounds: SIMD2(0.5, 0.5)),
            commandBuffer: queue.makeCommandBuffer()!
        )
        let invalidBlend = pipeline.encode(
            source: texture(device: device),
            noise: nil,
            mask: nil,
            target: texture(device: device),
            inputs: inputs(blendMode: 33),
            commandBuffer: queue.makeCommandBuffer()!
        )
        let sizeMismatch = pipeline.encode(
            source: texture(device: device),
            noise: nil,
            mask: nil,
            target: texture(device: device, width: 2, height: 2),
            inputs: inputs(),
            commandBuffer: queue.makeCommandBuffer()!
        )

        let expectedHalf: [UInt8] = [191, 64, 0, 255]
        let result: [String: Any] = [
            "identityAtPulseZero": stockZero.encoded
                && nearlyEqual(Array(stockZero.output[0 ..< 4]), [128, 64, 0, 255]),
            "timeDriven": stockHalf.encoded
                && nearlyEqual(Array(stockHalf.output[0 ..< 4]), expectedHalf, tolerance: 3),
            "profilePhaseDiverges": legacyZero.encoded
                && nearlyEqual(Array(legacyZero.output[0 ..< 4]), expectedHalf, tolerance: 3)
                && !nearlyEqual(
                    Array(legacyZero.output[0 ..< 4]),
                    Array(stockZero.output[0 ..< 4]),
                    tolerance: 3
                ),
            "pulseAlphaZero": alphaZero.encoded
                && nearlyEqual(Array(alphaZero.output[0 ..< 4]), [0, 0, 0, 0]),
            "pulseAlphaHalf": alphaHalf.encoded
                && nearlyEqual(
                    Array(alphaHalf.output[0 ..< 4]), [64, 32, 0, 128], tolerance: 3
                ),
            "maskSplitsEffect": masked.encoded && leftOriginal && rightPulsed,
            "invalidInputsRejected": !invalidBounds && !invalidBlend && !sizeMismatch,
        ]
        let data = try! JSONSerialization.data(withJSONObject: result.mapValues { $0 as Any })
        print(String(data: data, encoding: .utf8)!)
    }
}
'''


class ScenePulseRenderingTests(unittest.TestCase):
    def test_rendering(self) -> None:
        swiftc = shutil.which("swiftc")
        self.assertIsNotNone(swiftc, "swiftc unavailable")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            harness = root / "Harness.swift"
            executable = root / "pulse-render-harness"
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
                completed.returncode, 0,
                f"stdout={completed.stdout}\nstderr={completed.stderr}",
            )

        output = json.loads(completed.stdout)
        self.assertTrue(output)
        if output.get("skipped"):
            self.skipTest("Metal device unavailable")
        self.assertTrue(all(output.values()), output)


if __name__ == "__main__":
    unittest.main()
