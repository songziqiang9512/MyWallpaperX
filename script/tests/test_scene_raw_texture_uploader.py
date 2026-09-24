#!/usr/bin/env python3

"""Metal tests for static raw TEX padding crop and animated atlas preservation."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/Textures/SceneCompressedTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneTextureMipUploader.swift",
]

HARNESS = r'''
import Foundation
import Metal
import CoreGraphics

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
    case texContainsVideoPayload
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }
        if let mode = CommandLine.arguments.dropFirst().first {
            if mode.hasPrefix("extent-") {
                let parts = mode.split(separator: "-")
                let size = Int(parts[2])!
                let width = parts.last == "height" ? 4 : size
                let height = parts.last == "height" ? size : 4
                let image = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )!.makeImage()!
                let lower = CGContext(
                    data: nil, width: width / 2, height: height / 2, bitsPerComponent: 8,
                    bytesPerRow: (width / 2) * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )!.makeImage()!
                let bc = parts[1] == "bc" || parts[1] == "bccrop" || parts[1] == "native"
                let crop = parts[1] == "crop" || parts[1] == "bccrop"
                let payload = Data(repeating: 0, count: bc
                    ? ((width + 3) / 4) * ((height + 3) / 4) * 16
                    : width * height * 4)
                let container = SceneTexContainer(
                    format: bc ? 4 : 0, flags: 2,
                    textureWidth: width, textureHeight: height,
                    imageWidth: crop ? min(width, 8) : width,
                    imageHeight: crop ? min(height, 8) : height,
                    containerVersion: .texb0001, freeImageFormat: -1, isVideoMp4: false,
                    images: [.init(mips: [.init(width: width, height: height, data: payload)])],
                    spriteFrames: []
                )
                let outcome: SceneTextureLoadOutcome?
                switch parts[1] {
                case "embedded":
                    outcome = SceneTextureMipUploader.uploadEmbeddedImages([image, lower], device: device)
                case "data":
                    outcome = SceneTextureMipUploader.uploadEmbeddedDataImages(
                        [image, lower], purpose: .preservedChannels,
                        maximumDimension: Int.max, device: device
                    )
                case "native":
                    outcome = SceneCompressedTextureUploader.uploadNativeImage(
                        .init(mips: container.mips), pixelFormat: .bc3_rgba, device: device
                    )
                case "bc", "bccrop":
                    outcome = SceneCompressedTextureUploader.upload(
                        container: container, pixelFormat: .bc3_rgba,
                        purpose: .premultipliedColor,
                        device: device
                    )
                default:
                    outcome = SceneTextureMipUploader.uploadRawRGBA(container: container, device: device)
                }
                if case let .loaded(texture) = outcome {
                    print("\(texture.width)x\(texture.height)")
                } else { print("rejected") }
                return
            }
            var bytes = Data("TEXV0005\0TEXI0001\0".utf8)
            func append(_ value: UInt32) {
                var value = value.littleEndian
                withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
            }
            let height: UInt32 = mode == "raw-thin" ? 1 : .max
            for value: UInt32 in [mode.hasPrefix("raw") ? 0 : 4, 2,
                                  .max, height, 1, 1, 0] { append(value) }
            bytes.append(Data("TEXB0001\0".utf8))
            for value: UInt32 in [1, 1, .max, height, 4] { append(value) }
            bytes.append(Data(repeating: 0, count: 4))
            let container = try SceneTexContainerReader().read(data: bytes)
            let outcome = mode == "raw-data"
                ? SceneTextureMipUploader.uploadRaw(
                    container: container, pixelFormat: .rgba8Unorm,
                    bytesPerPixel: 4, device: device
                )
                : mode.hasPrefix("raw")
                ? SceneTextureMipUploader.uploadRawRGBA(container: container, device: device)
                : SceneCompressedTextureUploader.upload(
                    container: container, pixelFormat: .bc3_rgba,
                    purpose: mode == "bc-data" ? .preservedChannels : .premultipliedColor,
                    device: device
                )
            if case .decodeFailed = outcome { print("rejected") }
            else { print("unexpected-success") }
            return
        }
        let staticOutcome = SceneTextureMipUploader.uploadRawRGBA(
            container: makeContainer(flags: 2),
            device: device
        )
        let animatedOutcome = SceneTextureMipUploader.uploadRawRGBA(
            container: makeContainer(flags: 4),
            device: device
        )
        let invalidAuthoredSizeOutcome = SceneTextureMipUploader.uploadRawRGBA(
            container: makeContainer(flags: 2, imageWidth: 5),
            device: device
        )
        guard case let .loaded(staticTexture) = staticOutcome,
              case let .loaded(animatedTexture) = animatedOutcome,
              case let .loaded(invalidAuthoredSizeTexture) = invalidAuthoredSizeOutcome else {
            throw HarnessError.uploadFailed
        }
        var result: [String: Any] = [
            "staticSize": [staticTexture.width, staticTexture.height],
            "staticMipCount": staticTexture.mipmapLevelCount,
            "staticBasePixels": readRGBA(
                texture: staticTexture,
                level: 0,
                width: 2,
                height: 3
            ),
            "staticSecondMipPixel": readRGBA(
                texture: staticTexture,
                level: 1,
                width: 1,
                height: 1
            ),
            "animatedSize": [animatedTexture.width, animatedTexture.height],
            "invalidAuthoredSize": [
                invalidAuthoredSizeTexture.width,
                invalidAuthoredSizeTexture.height,
            ],
        ]
        func summary(_ outcome: SceneTextureLoadOutcome?) -> String {
            switch outcome {
            case let .loaded(texture):
                return "\(texture.width)x\(texture.height):\(texture.mipmapLevelCount)"
            case .decodeFailed: return "rejected"
            case nil: return "rejected"
            default: return "unexpected-failure"
            }
        }
        for (name, sizes, imageSize) in [
            ("complete", [8, 4, 2, 1], 8),
            ("partial", [8, 4], 8),
            ("cropped", [8, 4, 2, 1], 3),
            ("excess", [8, 4, 2, 1, 1], 8),
            ("excessCropped", [8, 4, 2, 1, 1], 3),
            ("one", [1], 1),
            ("excessOne", [1, 1], 1),
            ("gap", [8, 2], 8),
        ] {
            let raw = mipContainer(sizes: sizes, imageSize: imageSize, format: 0)
            result["raw_" + name] = summary(SceneTextureMipUploader.uploadRawRGBA(
                container: raw, device: device
            ))
            let bc = mipContainer(sizes: sizes, imageSize: imageSize, format: 7)
            result["bc_" + name] = summary(SceneCompressedTextureUploader.upload(
                container: bc, pixelFormat: .bc1_rgba,
                purpose: .premultipliedColor, device: device
            ))
            // BC5 has no CPU decoder, exercising the native upload boundary.
            let native = mipContainer(sizes: sizes, imageSize: imageSize, format: 5)
            if device.supportsBCTextureCompression {
                result["native_" + name] = summary(SceneCompressedTextureUploader.upload(
                    container: native, pixelFormat: .bc5_rgSnorm,
                    purpose: .preservedChannels, device: device
                ))
            }
            let images = sizes.map { size in
                CGContext(
                    data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )!.makeImage()!
            }
            result["embedded_" + name] = summary(
                SceneTextureMipUploader.uploadEmbeddedImages(images, device: device)
            )
            result["data_" + name] = summary(
                SceneTextureMipUploader.uploadEmbeddedDataImages(
                    images, purpose: .preservedChannels, device: device
                )
            )
        }
        result["nativeSupported"] = device.supportsBCTextureCompression
        result["raw_corruptTail"] = summary(SceneTextureMipUploader.uploadRawRGBA(
            container: mipContainer(sizes: [8, 4, 2, 1], imageSize: 3, format: 0, corruptTail: true),
            device: device
        ))
        result["bc_corruptTail"] = summary(SceneCompressedTextureUploader.upload(
            container: mipContainer(sizes: [8, 4, 2, 1], imageSize: 3, format: 7, corruptTail: true),
            pixelFormat: .bc1_rgba, purpose: .premultipliedColor, device: device
        ))
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: result)
        )
    }

    static func mipContainer(
        sizes: [Int], imageSize: Int, format: UInt32, corruptTail: Bool = false
    ) -> SceneTexContainer {
        SceneTexContainer(
            format: format, flags: 2,
            textureWidth: sizes[0], textureHeight: sizes[0],
            imageWidth: imageSize, imageHeight: imageSize,
            containerVersion: .texb0002, freeImageFormat: -1, isVideoMp4: false,
            images: [.init(mips: sizes.enumerated().map { index, size in
                let byteCount = format == 0 ? size * size * 4
                    : ((size + 3) / 4) * ((size + 3) / 4) * (format == 7 ? 8 : 16)
                let count = corruptTail && index == sizes.count - 1 ? 0 : byteCount
                return .init(width: size, height: size, data: Data(repeating: 255, count: count))
            })], spriteFrames: []
        )
    }

    static func makeContainer(
        flags: UInt32,
        imageWidth: Int = 2
    ) -> SceneTexContainer {
        let base: [UInt8] = [
            100, 50, 20, 128, 20, 40, 60, 255, 1, 2, 3, 255, 4, 5, 6, 255,
            7, 8, 9, 255, 10, 11, 12, 255, 13, 14, 15, 255, 16, 17, 18, 255,
            19, 20, 21, 255, 22, 23, 24, 255, 25, 26, 27, 255, 28, 29, 30, 255,
            31, 32, 33, 255, 34, 35, 36, 255, 37, 38, 39, 255, 40, 41, 42, 255,
        ]
        let second: [UInt8] = [
            80, 40, 20, 128, 1, 2, 3, 255,
            4, 5, 6, 255, 7, 8, 9, 255,
        ]
        return SceneTexContainer(
            format: 0,
            flags: flags,
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: imageWidth,
            imageHeight: 3,
            containerVersion: .texb0002,
            freeImageFormat: -1,
            isVideoMp4: false,
            images: [.init(mips: [
                .init(width: 4, height: 4, data: Data(base)),
                .init(width: 2, height: 2, data: Data(second)),
            ])],
            spriteFrames: []
        )
    }

    static func readRGBA(
        texture: MTLTexture,
        level: Int,
        width: Int,
        height: Int
    ) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &data,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: level
        )
        return data
    }

    enum HarnessError: Error { case uploadFailed }
}
'''


class SceneRawTextureUploaderTests(unittest.TestCase):
    def test_cropping_does_not_hide_corrupt_discarded_payload(self) -> None:
        self.assertEqual(self.result["raw_corruptTail"], "rejected")
        self.assertEqual(self.result["bc_corruptTail"], "rejected")

    def test_mip_upload_boundaries(self) -> None:
        routes = ["raw", "bc", "embedded", "data"]
        if self.result["nativeSupported"]:
            routes.append("native")
        for route in routes:
            for case in ("excess", "excessCropped", "excessOne", "gap"):
                with self.subTest(route=route, case=case):
                    self.assertEqual(self.result[f"{route}_{case}"], "rejected")
            for case, expected in (("complete", "8x8:4"), ("partial", "8x8:2"), ("one", "1x1:1")):
                with self.subTest(route=route, case=case):
                    self.assertEqual(self.result[f"{route}_{case}"], expected)
            expected = "3x3:2" if route in ("raw", "bc") else "8x8:4"
            self.assertEqual(self.result[f"{route}_cropped"], expected)

    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        harness = tmp / "harness.swift"
        harness.write_text(HARNESS)
        binary = tmp / "harness"
        cls.binary = binary
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")
        execution = subprocess.run(
            [str(binary)],
            capture_output=True,
            text=True,
        )
        if execution.returncode != 0:
            raise AssertionError(f"harness execution failed:\n{execution.stderr}")
        if execution.stdout.strip() == "SKIP":
            raise unittest.SkipTest("Metal device is unavailable")
        cls.result = json.loads(execution.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "_tmp"):
            cls._tmp.cleanup()

    def test_static_single_image_is_cropped_to_authored_dimensions(self) -> None:
        self.assertEqual(self.result["staticSize"], [2, 3])
        self.assertEqual(self.result["staticMipCount"], 2)

    def test_uint32_tex_dimensions_fail_without_trapping(self) -> None:
        for mode in ("raw", "raw-data", "raw-thin", "bc-color", "bc-data"):
            with self.subTest(mode=mode):
                result = subprocess.run(
                    [str(self.binary), mode], capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "rejected")

    def test_metal_axis_limit_is_checked_before_allocation(self) -> None:
        for route in ("raw", "bc", "native", "embedded", "data", "crop", "bccrop"):
            for axis in ("width", "height"):
                for size in (16384, 16385):
                    with self.subTest(route=route, axis=axis, size=size):
                        result = subprocess.run(
                            [str(self.binary), f"extent-{route}-{size}-{axis}"],
                            capture_output=True, text=True,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)
                        expected = "rejected" if size > 16384 else (
                            f"{size}x4" if axis == "width" else f"4x{size}"
                        )
                        if route in ("crop", "bccrop"):
                            expected = "8x4" if axis == "width" else "4x8"
                        self.assertEqual(result.stdout.strip(), expected)

    def test_static_crop_uses_top_left_rows_and_premultiplies_rgba(self) -> None:
        self.assertEqual(
            self.result["staticBasePixels"],
            [
                50, 25, 10, 128, 20, 40, 60, 255,
                7, 8, 9, 255, 10, 11, 12, 255,
                19, 20, 21, 255, 22, 23, 24, 255,
            ],
        )
        self.assertEqual(self.result["staticSecondMipPixel"], [40, 20, 10, 128])

    def test_animated_raw_texture_preserves_physical_atlas_dimensions(self) -> None:
        self.assertEqual(self.result["animatedSize"], [4, 4])

    def test_invalid_authored_dimensions_preserve_physical_texture(self) -> None:
        self.assertEqual(self.result["invalidAuthoredSize"], [4, 4])


if __name__ == "__main__":
    unittest.main()
