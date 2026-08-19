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
    SOURCE_ROOT / "Effects/SceneOpacityPipeline.swift",
    SOURCE_ROOT / "Effects/SceneOpacityRenderer.swift",
]


HARNESS = r'''
import Foundation
import Metal

@main
enum Harness {
    static let width = 2
    static let height = 2

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat = .bgra8Unorm,
        width: Int = width,
        height: Int = height,
        mipmapped: Bool = false,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget]
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: mipmapped
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("texture allocation failed")
        }
        return texture
    }

    static func arrayTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = 1
        descriptor.arrayLength = 2
        descriptor.mipmapLevelCount = 1
        descriptor.sampleCount = 1
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("array texture allocation failed")
        }
        return texture
    }

    static func multisampleTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DMultisample
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = 1
        descriptor.arrayLength = 1
        descriptor.mipmapLevelCount = 1
        descriptor.sampleCount = 4
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("multisample texture allocation failed")
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

    static func render(
        input: [UInt8],
        alpha: Float,
        mask: [UInt8]? = nil,
        maskUVScale: SIMD2<Float> = SIMD2(repeating: 1),
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneOpacityPipeline
    ) -> (output: [UInt8], rendererReturnedOutput: Bool) {
        let source = texture(device: device)
        let target = texture(device: device)
        uploadRGBA(input, to: source)
        var maskTexture: MTLTexture?
        if let mask {
            let loaded = texture(device: device)
            uploadRGBA(mask, to: loaded)
            maskTexture = loaded
        }
        guard let command = queue.makeCommandBuffer() else {
            fatalError("command allocation failed")
        }
        let rendered = SceneOpacityRenderer.render(
            alpha: alpha,
            mask: maskTexture,
            maskUVScale: maskUVScale,
            inputTexture: source,
            outputTexture: target,
            pipeline: pipeline,
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            fatalError("opacity command failed: \(String(describing: command.error))")
        }
        return (readRGBA(target), rendered === target)
    }

    static func rejectionChecks(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneOpacityPipeline
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let wrongFormat = texture(device: device, format: .rgba8Unorm)
        let wrongExtent = texture(device: device, width: width - 1)
        let mipmapped = texture(device: device, mipmapped: true)
        let sourceWrongUsage = texture(device: device, usage: [.renderTarget])
        let targetWrongUsage = texture(device: device, usage: [.shaderRead])
        let non2D = arrayTexture(device: device)
        let multisample = multisampleTexture(device: device)
        let maskNoRead = texture(device: device, usage: [.renderTarget])
        guard let command = queue.makeCommandBuffer() else {
            fatalError("command allocation failed")
        }
        func encoded(
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target,
            alpha: Float = 0.5,
            mask: MTLTexture? = nil,
            maskUVScale: SIMD2<Float> = SIMD2(repeating: 1)
        ) -> Bool {
            pipeline.encode(
                source: candidateSource,
                target: candidateTarget,
                alpha: alpha,
                mask: mask,
                maskUVScale: maskUVScale,
                commandBuffer: command
            )
        }
        return [
            "sameTexture": !encoded(source: source, target: source),
            "wrongSourceFormat": !encoded(source: wrongFormat),
            "wrongTargetFormat": !encoded(target: wrongFormat),
            "wrongExtent": !encoded(target: wrongExtent),
            "sourceMipmapped": !encoded(source: mipmapped),
            "targetMipmapped": !encoded(target: mipmapped),
            "sourceWrongUsage": !encoded(source: sourceWrongUsage),
            "targetWrongUsage": !encoded(target: targetWrongUsage),
            "sourceNon2D": !encoded(source: non2D),
            "targetNon2D": !encoded(target: non2D),
            "sourceMultisample": !encoded(source: multisample),
            "targetMultisample": !encoded(target: multisample),
            "nanAlpha": !encoded(alpha: .nan),
            "infiniteAlpha": !encoded(alpha: .infinity),
            "negativeAlpha": !encoded(alpha: -0.001),
            "overflowAlpha": !encoded(alpha: 1.001),
            "maskNon2D": !encoded(mask: non2D),
            "maskMultisample": !encoded(mask: multisample),
            "maskWrongUsage": !encoded(mask: maskNoRead),
            "nanMaskScale": !encoded(mask: source, maskUVScale: SIMD2(.nan, 1)),
            "zeroMaskScale": !encoded(mask: source, maskUVScale: SIMD2(0, 1)),
            "overflowMaskScale": !encoded(mask: source, maskUVScale: SIMD2(1, 1.001)),
            "wrongPipelineFormat": SceneOpacityPipeline(
                device: device,
                pixelFormat: .rgba8Unorm
            ) == nil,
        ]
    }

    static func crossDeviceChecks(
        device: MTLDevice,
        pipeline: SceneOpacityPipeline
    ) -> [String: Bool] {
        guard let alternate = MTLCopyAllDevices().first(where: {
            $0.registryID != device.registryID
        }), let primaryQueue = device.makeCommandQueue(),
        let alternateQueue = alternate.makeCommandQueue(),
        let primaryCommand = primaryQueue.makeCommandBuffer(),
        let alternateCommand = alternateQueue.makeCommandBuffer() else {
            return ["available": false, "source": true, "target": true, "queue": true,
                    "mask": true]
        }
        let primarySource = texture(device: device)
        let primaryTarget = texture(device: device)
        let alternateSource = texture(device: alternate)
        let alternateTarget = texture(device: alternate)
        func encoded(
            source: MTLTexture,
            target: MTLTexture,
            mask: MTLTexture? = nil,
            command: MTLCommandBuffer
        ) -> Bool {
            pipeline.encode(
                source: source,
                target: target,
                alpha: 0.5,
                mask: mask,
                maskUVScale: SIMD2(repeating: 1),
                commandBuffer: command
            )
        }
        return [
            "available": true,
            "source": !encoded(
                source: alternateSource, target: primaryTarget, command: primaryCommand
            ),
            "target": !encoded(
                source: primarySource, target: alternateTarget, command: primaryCommand
            ),
            "queue": !encoded(
                source: primarySource, target: primaryTarget, command: alternateCommand
            ),
            "mask": !encoded(
                source: primarySource, target: primaryTarget,
                mask: alternateSource, command: primaryCommand
            ),
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneOpacityPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let input: [UInt8] = [
            200, 100, 50, 200,
            0, 64, 128, 192,
            32, 16, 8, 64,
            255, 255, 255, 255,
        ]
        let identity = render(
            input: input, alpha: 1, device: device, queue: queue, pipeline: pipeline
        )
        let quarter = render(
            input: input, alpha: 0.25, device: device, queue: queue, pipeline: pipeline
        )
        let zero = render(
            input: input, alpha: 0, device: device, queue: queue, pipeline: pipeline
        )
        let mask: [UInt8] = [
            255, 0, 0, 255,
            128, 0, 0, 255,
            0, 0, 0, 255,
            64, 0, 0, 255,
        ]
        let masked = render(
            input: input, alpha: 0.5, mask: mask,
            device: device, queue: queue, pipeline: pipeline
        )
        let maskedHalfScale = render(
            input: input, alpha: 0.5, mask: mask, maskUVScale: SIMD2(0.5, 0.5),
            device: device, queue: queue, pipeline: pipeline
        )
        let result: [String: Any] = [
            "metalUnavailable": false,
            "input": input,
            "mask": mask,
            "identity": identity.output,
            "quarter": quarter.output,
            "zero": zero.output,
            "masked": masked.output,
            "maskedHalfScale": maskedHalfScale.output,
            "rendererReturnedOutput": identity.rendererReturnedOutput,
            "rejections": rejectionChecks(
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


class SceneOpacityRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-opacity-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-opacity-rendering"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-o", str(binary),
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

    def test_alpha_one_preserves_all_premultiplied_channels(self) -> None:
        self.assertEqual(self.result["identity"], self.result["input"])
        self.assertTrue(self.result["rendererReturnedOutput"])

    def test_fractional_alpha_scales_every_rgba_channel(self) -> None:
        expected = [round(value * 0.25) for value in self.result["input"]]
        for actual, reference in zip(self.result["quarter"], expected):
            self.assertAlmostEqual(actual, reference, delta=1)
        for index, value in enumerate(self.result["quarter"]):
            if index % 4 != 3:
                self.assertLessEqual(value, self.result["quarter"][(index // 4) * 4 + 3])

    def test_alpha_zero_clears_every_channel(self) -> None:
        self.assertEqual(self.result["zero"], [0] * len(self.result["input"]))

    def test_mask_red_channel_multiplies_alpha_per_texel(self) -> None:
        # 官方 opacity.frag 的 MASK 分支是 `albedo.a *= mask * g_UserAlpha`。源纹理是
        # premultiplied，等价形式为四通道同乘 mask.r × alpha。四个 texel 的 mask.r 互不相同，
        # 因此这条断言同时排除了「遮罩被丢掉」和「遮罩按常量取一次」两种实现。
        source = self.result["input"]
        mask = self.result["mask"]
        expected = [
            source[index] * 0.5 * (mask[(index // 4) * 4] / 255.0)
            for index in range(len(source))
        ]
        for actual, reference in zip(self.result["masked"], expected):
            self.assertAlmostEqual(actual, reference, delta=1)

    def test_mask_uv_scale_reaches_the_shader(self) -> None:
        # 官方 opacity.vert 用 `g_Texture1Resolution.zw / .xy` 修正遮罩 UV。换一个缩放值必须
        # 改变采样结果，否则说明 maskUVScale 根本没送到 shader。
        self.assertNotEqual(self.result["maskedHalfScale"], self.result["masked"])

    def test_invalid_alpha_and_resources_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()))

    def test_cross_device_resources_and_queue_fail_closed_when_available(self) -> None:
        checks = self.result["crossDevice"]
        if not checks["available"]:
            self.skipTest("a second Metal device is unavailable")
        self.assertTrue(checks["source"])
        self.assertTrue(checks["target"])
        self.assertTrue(checks["queue"])


if __name__ == "__main__":
    unittest.main()
