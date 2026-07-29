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
STOCK_PHASE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/materials/particle"
    / "normal_ring_smooth.tex"
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneWaterFlowBuiltInPhaseTexture.swift",
    SCENE_ROOT / "Resources/SceneWaterFlowEffectTextureLoader.swift",
]


HARNESS = r'''
import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

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

struct SceneWaterFlowExecutionPlan {
    let flowTexturePath: String
    let phaseTexturePath: String
}

struct SceneTexturePathResolver {
    let urlsByPath: [String: URL]

    func resolveTextureFile(named path: String) -> URL? {
        urlsByPath[path]
    }
}

struct SceneRenderDescriptor {
    struct EffectPass {
        let textureSlots: [String?]
    }

    struct EffectDescriptor {
        let id: String
        let file: String
        let passes: [EffectPass]
    }

    struct Layer {
        let effects: [EffectDescriptor]
    }
}

enum SceneLayerEffectTextureLoader {
    static func loadTexture(
        url: URL?,
        label: String,
        purpose: SceneTextureLoadPurpose,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (texture: MTLTexture?, message: String) {
        guard let url else { return (nil, "") }
        switch loader.load(from: url, purpose: purpose, device: device) {
        case .loaded(let texture):
            return (texture, "; \(label) OK")
        case .decodeFailed(let message):
            return (nil, "; \(label) decode failed (\(message))")
        default:
            return (nil, "; \(label) failed")
        }
    }

    static func mappedUVScale(for: URL?, texture: MTLTexture?) -> SIMD2<Float> {
        SIMD2(repeating: 1)
    }
}

@main
enum Harness {
    static let effectID = "86#effect#1"
    static let flowPath = "workshop/water_flow"
    static let stockPhasePath = "particle/normal_ring_smooth"

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw HarnessError.invalidArguments
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }
        let stockPhase = URL(fileURLWithPath: CommandLine.arguments[1])
        let temporary = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: true
        )
        let flowURL = temporary.appendingPathComponent("flow.png")
        let corruptURL = temporary.appendingPathComponent("corrupt.png")
        try writeImage(flowURL)
        try Data("not an image".utf8).write(to: corruptURL)

        let loader = SceneTextureLoader()
        let valid = load(
            phasePath: stockPhasePath,
            urlsByPath: [flowPath: flowURL, stockPhasePath: stockPhase],
            loader: loader,
            device: device
        )
        let missing = load(
            phasePath: stockPhasePath,
            urlsByPath: [flowPath: flowURL],
            loader: loader,
            device: device
        )
        let corrupt = load(
            phasePath: stockPhasePath,
            urlsByPath: [flowPath: flowURL, stockPhasePath: corruptURL],
            loader: loader,
            device: device
        )
        let unknown = load(
            phasePath: "particle/unknown",
            urlsByPath: [flowPath: flowURL],
            loader: loader,
            device: device
        )

        let validTextures = valid.textures[effectID]
        let missingTextures = missing.textures[effectID]
        let corruptTextures = corrupt.textures[effectID]
        let result: [String: Any] = [
            "validPhaseLoaded": validTextures?.phase != nil,
            "validPhasePreservedMips": (validTextures?.phase?.mipmapLevelCount ?? 0) > 1,
            "validMatches": validTextures?.matches(plan(phasePath: stockPhasePath)) ?? false,
            "missingUsesBuiltIn": missingTextures?.phase?.label
                == "Scene Water Flow built-in normal_ring_smooth",
            "missingMatches": missingTextures?.matches(plan(phasePath: stockPhasePath)) ?? false,
            "corruptStayedFailed": corruptTextures?.phase == nil,
            "corruptDoesNotMatch": !(corruptTextures?.matches(
                plan(phasePath: stockPhasePath)
            ) ?? false),
            "corruptReported": corrupt.message.contains("decode failed"),
            "unknownStayedFailed": unknown.textures[effectID]?.phase == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func load(
        phasePath: String,
        urlsByPath: [String: URL],
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneWaterFlowEffectTextures], message: String) {
        SceneWaterFlowEffectTextureLoader.load(
            for: .init(effects: [.init(
                id: effectID,
                file: "effects/waterflow/effect.json",
                passes: [.init(textureSlots: [nil, flowPath, phasePath])]
            )]),
            effectIDs: [effectID],
            resolver: .init(urlsByPath: urlsByPath),
            loader: loader,
            device: device
        )
    }

    static func plan(phasePath: String) -> SceneWaterFlowExecutionPlan {
        .init(flowTexturePath: flowPath, phaseTexturePath: phasePath)
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
        case imageCreationFailed
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneWaterFlowEffectTextureLoaderTests(unittest.TestCase):
    def test_missing_phase_falls_back_but_resolved_corrupt_phase_fails_closed(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-waterflow-loader-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "waterflow-loader-test"
            harness.write_text(HARNESS, encoding="utf-8")
            compilation = subprocess.run(
                [
                    "xcrun",
                    "--sdk",
                    "macosx",
                    "swiftc",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-framework",
                    "Metal",
                    "-framework",
                    "ImageIO",
                    "-framework",
                    "CoreGraphics",
                    "-module-cache-path",
                    str(root / "module-cache"),
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            completed = subprocess.run(
                [str(binary), str(STOCK_PHASE), str(root / "runtime")],
                check=True,
                capture_output=True,
                text=True,
            )
        if completed.stdout.strip() == "SKIP":
            self.skipTest("Metal is unavailable")
        result = json.loads(completed.stdout)
        self.assertEqual(
            result,
            {
                "corruptDoesNotMatch": True,
                "corruptReported": True,
                "corruptStayedFailed": True,
                "missingMatches": True,
                "missingUsesBuiltIn": True,
                "unknownStayedFailed": True,
                "validMatches": True,
                "validPhaseLoaded": True,
                "validPhasePreservedMips": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
