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
HOST_SOURCE = SOURCE_ROOT / "Runtime/SceneDesktopWallpaperHost.swift"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneTexDataReader.swift",
    SOURCE_ROOT / "Format/SceneTexContainer.swift",
    SOURCE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SOURCE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SOURCE_ROOT / "Resources/SceneTextureLoader.swift",
    SOURCE_ROOT / "Properties/SceneUserPropertyTextureLoader.swift",
]

HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import ImageIO
import Metal

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        cacheDirectory: URL,
        device: MTLDevice
    ) {
        return nil
    }
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingDirectory }
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }

        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let pngURL = directory.appendingPathComponent("cover.png")
        let jpegURL = directory.appendingPathComponent("photo.jpeg")
        let jpgURL = directory.appendingPathComponent("photo-alias.jpg")
        let invalidURL = directory.appendingPathComponent("broken.png")
        let unsupportedURL = directory.appendingPathComponent("disguised.gif")
        try writeImage(pngURL, type: "public.png")
        try writeImage(jpegURL, type: "public.jpeg")
        try Data(contentsOf: jpegURL).write(to: jpgURL)
        try Data("not an image".utf8).write(to: invalidURL)
        try Data(contentsOf: pngURL).write(to: unsupportedURL)

        let loader = SceneUserPropertyTextureLoader()
        let result = loader.load(
            urlsByPropertyKey: [
                "png": pngURL,
                "jpeg": jpegURL,
                "jpg": jpgURL,
                "broken": invalidURL,
                "unsupported": unsupportedURL,
            ],
            device: device
        )
        let retry = loader.load(
            urlsByPropertyKey: ["png": invalidURL],
            device: device
        )
        let empty = loader.load(urlsByPropertyKey: [:], device: device)
        let dimensions = result.textures.mapValues { ["width": $0.width, "height": $0.height] }
        let payload: [String: Any] = [
            "loadedKeys": result.textures.keys.sorted(),
            "dimensions": dimensions,
            "reportLines": result.reportLines,
            "retryLoadedKeys": retry.textures.keys.sorted(),
            "retryReportLines": retry.reportLines,
            "emptyLoadedKeys": empty.textures.keys.sorted(),
            "emptyReportLines": empty.reportLines,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func writeImage(_ url: URL, type: String) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 3,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 12,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type as CFString,
            1,
            nil
           ) else {
            throw HarnessError.imageWrite
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HarnessError.imageWrite }
    }

    private enum HarnessError: Error {
        case missingDirectory
        case noMetal
        case imageWrite
    }
}
'''


class SceneUserPropertyTextureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-user-property-textures-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-user-property-textures"
        compilation = subprocess.run(
            [
                swiftc,
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-framework", "CoreGraphics",
                "-framework", "ImageIO",
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        fixture_directory = directory / "fixture"
        completed = subprocess.run(
            [str(cls.binary), str(fixture_directory)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_png_and_both_jpeg_extensions_load(self) -> None:
        self.assertEqual(self.result["loadedKeys"], ["jpeg", "jpg", "png"])
        self.assertEqual(self.result["reportLines"][0], "sceneUserTextureRequestedCount: 5")
        self.assertEqual(self.result["reportLines"][-1], "sceneUserTextureLoadedCount: 3")
        self.assertEqual(
            self.result["dimensions"],
            {
                "jpeg": {"height": 2, "width": 3},
                "jpg": {"height": 2, "width": 3},
                "png": {"height": 2, "width": 3},
            },
        )

    def test_corrupt_and_unsupported_files_fail_closed(self) -> None:
        report = "\n".join(self.result["reportLines"])
        self.assertIn("broken", report)
        self.assertIn("unsupported", report)
        self.assertNotIn("broken", self.result["loadedKeys"])
        self.assertNotIn("unsupported", self.result["loadedKeys"])

    def test_failed_retry_does_not_retain_an_old_texture(self) -> None:
        self.assertEqual(self.result["retryLoadedKeys"], [])
        self.assertEqual(
            [self.result["retryReportLines"][0], self.result["retryReportLines"][-1]],
            ["sceneUserTextureRequestedCount: 1", "sceneUserTextureLoadedCount: 0"],
        )

    def test_empty_input_is_a_noop(self) -> None:
        self.assertEqual(self.result["emptyLoadedKeys"], [])
        self.assertEqual(self.result["emptyReportLines"], [])

    def test_surface_rebuild_reopens_security_scoped_urls(self) -> None:
        source = HOST_SOURCE.read_text(encoding="utf-8")
        rebuild = source.split("private func rebuildSurfaces(", maxsplit=1)[1]
        rebuild = rebuild.split("private func teardownSurfaces", maxsplit=1)[0]
        self.assertIn("startAccessingSecurityScopedResource()", rebuild)
        self.assertIn("stopAccessingSecurityScopedResource()", rebuild)
        self.assertLess(
            rebuild.index("startAccessingSecurityScopedResource()"),
            rebuild.index("SceneMetalView("),
        )


if __name__ == "__main__":
    unittest.main()
