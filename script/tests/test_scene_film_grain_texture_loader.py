#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneStockTextureResolver.swift",
    SCENE_ROOT / "Resources/SceneFilmGrainEffectTextureLoader.swift",
]


HARNESS = r'''
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

struct SceneFilmGrainExecutionPlan {
    let noiseTexturePath: String
}

enum SceneAuthoredFilmGrainPlanner {
    static let noiseTexturePath = "util/noise"
}

struct SceneTexturePathResolver {
    let localURL: URL?

    func resolveTextureFile(named: String) -> URL? {
        localURL
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        let id: String
        let file: String
    }

    struct Layer {
        let effects: [EffectDescriptor]
    }
}

enum SceneLayerEffectTextureLoader {
    static func loadTexture(
        url: URL?,
        label: String,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (texture: MTLTexture?, message: String) {
        guard let url else { return (nil, "; \(label) missing") }
        switch loader.load(from: url, device: device) {
        case .loaded(let texture):
            return (texture, "")
        default:
            return (nil, "; \(label) failed")
        }
    }
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 3,
              let device = MTLCreateSystemDefaultDevice() else {
            throw HarnessError.invalidArguments
        }
        let stockRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let temporary = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let localURL = temporary.appendingPathComponent("materials/util/noise.png")
        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeImage(localURL)
        let corruptURL = temporary.appendingPathComponent("materials/util/corrupt.png")
        try Data("not an image".utf8).write(to: corruptURL)

        guard let stock = SceneStockTextureResolver(bundleRoot: stockRoot) else {
            throw HarnessError.invalidStockRoot
        }
        let layer = SceneRenderDescriptor.Layer(effects: [.init(
            id: "20#effect#702",
            file: "effects/filmgrain/effect.json"
        )])
        let effectIDs: Set<String> = ["20#effect#702"]
        let loader = SceneTextureLoader()
        let stockResult = SceneFilmGrainEffectTextureLoader.load(
            for: layer,
            effectIDs: effectIDs,
            resolver: SceneTexturePathResolver(localURL: nil),
            loader: loader,
            device: device,
            stockResolver: stock
        )
        let localResult = SceneFilmGrainEffectTextureLoader.load(
            for: layer,
            effectIDs: effectIDs,
            resolver: SceneTexturePathResolver(localURL: localURL),
            loader: loader,
            device: device,
            stockResolver: stock
        )
        let corruptResult = SceneFilmGrainEffectTextureLoader.load(
            for: layer,
            effectIDs: effectIDs,
            resolver: SceneTexturePathResolver(localURL: corruptURL),
            loader: loader,
            device: device,
            stockResolver: stock
        )
        let missingResult = SceneFilmGrainEffectTextureLoader.load(
            for: layer,
            effectIDs: effectIDs,
            resolver: SceneTexturePathResolver(localURL: nil),
            loader: loader,
            device: device,
            stockResolver: nil
        )
        let stockTexture = stockResult.textures["20#effect#702"]?.noise
        let localTexture = localResult.textures["20#effect#702"]?.noise
        let result: [String: Any] = [
            "stockLoaded": stockTexture != nil,
            "stockPathMatches": stockResult.textures["20#effect#702"]?.matches(
                SceneFilmGrainExecutionPlan(noiseTexturePath: "util/noise")
            ) ?? false,
            "localLoaded": localTexture != nil,
            "localWidth": localTexture?.width ?? 0,
            "stockWidth": stockTexture?.width ?? 0,
            "corruptStayedFailed": corruptResult.textures["20#effect#702"]?.noise == nil,
            "missingStayedFailed": missingResult.textures["20#effect#702"]?.noise == nil,
            "missingReported": missingResult.message.contains("film grain noise missing"),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func writeImage(_ url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytes: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 255,
        ]
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: 2,
                  height: 2,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: 8,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, "public.png" as CFString, 1, nil
              ) else {
            throw HarnessError.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.imageCreationFailed
        }
    }

    enum HarnessError: Error {
        case invalidArguments
        case invalidStockRoot
        case imageCreationFailed
    }
}
'''


class SceneFilmGrainTextureLoaderTests(unittest.TestCase):
    def test_local_then_stock_resolution_and_fail_closed_decode(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-film-grain-loader-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "scene-film-grain-loader"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun", "--sdk", "macosx", "swiftc",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework", "Metal",
                    "-framework", "ImageIO",
                    "-framework", "CoreGraphics",
                    "-o", str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(STOCK_ROOT), str(root / "runtime")],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(result["stockLoaded"], result)
        self.assertTrue(result["stockPathMatches"], result)
        self.assertTrue(result["localLoaded"], result)
        self.assertEqual(result["localWidth"], 2, result)
        self.assertNotEqual(result["stockWidth"], result["localWidth"], result)
        self.assertTrue(result["corruptStayedFailed"], result)
        self.assertTrue(result["missingStayedFailed"], result)
        self.assertTrue(result["missingReported"], result)


if __name__ == "__main__":
    unittest.main()
