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
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
]

HARNESS = r'''
import Foundation
import Metal

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
        let result: [String: Any] = [
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
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: result)
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
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        harness = tmp / "harness.swift"
        harness.write_text(HARNESS)
        binary = tmp / "harness"
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
