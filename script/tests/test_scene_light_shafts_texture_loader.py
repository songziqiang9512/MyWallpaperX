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
STOCK_ROOT = ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle"
SOURCES = [
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneStockTextureResolver.swift",
    SCENE_ROOT / "Resources/SceneLightShaftsEffectTextureLoader.swift",
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

struct SceneLightShaftsExecutionPlan {
    let noiseTexturePath: String
    let gradientTexturePath: String
}

enum SceneAuthoredLightShaftsPlanner {
    static let noiseTexturePath = "materials/util/noise"
    static let gradientTexturePath = "materials/gradient/gradient_iridescent"
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
        let localURL = temporary.appendingPathComponent("local.png")
        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeImage(localURL)
        let corruptURL = temporary.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: corruptURL)
        guard let stock = SceneStockTextureResolver(bundleRoot: stockRoot) else {
            throw HarnessError.invalidStockRoot
        }
        let id = "80#effect#81"
        let layer = SceneRenderDescriptor.Layer(effects: [.init(
            id: id,
            file: "effects/lightshafts/effect.json"
        )])
        let loader = SceneTextureLoader()
        let stockResult = SceneLightShaftsEffectTextureLoader.load(
            for: layer,
            effectIDs: [id],
            resolver: SceneTexturePathResolver(localURL: nil),
            loader: loader,
            device: device,
            stockResolver: stock
        )
        let localResult = SceneLightShaftsEffectTextureLoader.load(
            for: layer,
            effectIDs: [id],
            resolver: SceneTexturePathResolver(localURL: localURL),
            loader: loader,
            device: device,
            stockResolver: stock
        )
        let corruptResult = SceneLightShaftsEffectTextureLoader.load(
            for: layer,
            effectIDs: [id],
            resolver: SceneTexturePathResolver(localURL: corruptURL),
            loader: loader,
            device: device,
            stockResolver: stock
        )
        let missingResult = SceneLightShaftsEffectTextureLoader.load(
            for: layer,
            effectIDs: [id],
            resolver: SceneTexturePathResolver(localURL: nil),
            loader: loader,
            device: device,
            stockResolver: nil
        )
        let plan = SceneLightShaftsExecutionPlan(
            noiseTexturePath: "materials/util/noise",
            gradientTexturePath: "materials/gradient/gradient_iridescent"
        )
        let result: [String: Any] = [
            "stockMatches": stockResult.textures[id]?.matches(plan) ?? false,
            "localMatches": localResult.textures[id]?.matches(plan) ?? false,
            "localWidth": localResult.textures[id]?.noise?.width ?? 0,
            "stockWidth": stockResult.textures[id]?.noise?.width ?? 0,
            "corruptRejected": !(corruptResult.textures[id]?.matches(plan) ?? false),
            "missingRejected": !(missingResult.textures[id]?.matches(plan) ?? false),
            "missingReported": missingResult.message.contains("light shafts noise missing")
                && missingResult.message.contains("light shafts gradient missing"),
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
                  url as CFURL,
                  "public.png" as CFString,
                  1,
                  nil
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


class SceneLightShaftsTextureLoaderTests(unittest.TestCase):
    def test_local_then_stock_resolution_and_fail_closed_decode(self) -> None:
        if shutil.which("swiftc") is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(prefix="scene-light-shafts-loader-") as directory:
            temporary = Path(directory)
            harness = temporary / "Harness.swift"
            binary = temporary / "scene-light-shafts-loader"
            harness.write_text(HARNESS, encoding="utf-8")
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
                    "-framework",
                    "ImageIO",
                    "-framework",
                    "CoreGraphics",
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(STOCK_ROOT), str(temporary / "runtime")],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        self.assertTrue(result["stockMatches"], result)
        self.assertTrue(result["localMatches"], result)
        self.assertEqual(result["localWidth"], 2, result)
        self.assertNotEqual(result["stockWidth"], result["localWidth"], result)
        self.assertTrue(result["corruptRejected"], result)
        self.assertTrue(result["missingRejected"], result)
        self.assertTrue(result["missingReported"], result)


if __name__ == "__main__":
    unittest.main()
