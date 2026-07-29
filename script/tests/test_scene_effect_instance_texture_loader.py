#!/usr/bin/env python3
"""Foliage Sway / Water Ripple 的 effect-instance 纹理身份与 fail-closed。"""

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
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneFoliageSwayEffectTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneWaterRippleEffectTextureLoader.swift",
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

struct SceneFoliageSwayExecutionPlan {
    let maskTexturePath: String
    let noiseTexturePath: String
}

struct SceneWaterRippleExecutionPlan {
    let maskTexturePath: String
    let normalTexturePath: String
}

enum SceneAuthoredFoliageSwayPlanner {
    static let noiseAssetPath = "util/noise"
}

struct SceneTexturePathResolver {
    let urlsByPath: [String: URL]

    func resolveTextureFile(named path: String) -> URL? {
        urlsByPath[path]
    }
}

struct SceneStockTextureResolver {
    init(bundleRoot: URL) {}
    static func defaultBundleRoot() -> URL? { nil }
    func textureURL(for path: String) -> URL? { nil }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let textureSlots: [String?]
        }
        let id: String
        let file: String
        let passes: [PassDescriptor]
    }
    struct Layer {
        let effects: [EffectDescriptor]
    }
}

enum SceneEffectMaskSemantics {
    static func maskPath(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> String? {
        pass.textureSlots.indices.contains(1) ? pass.textureSlots[1] : nil
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
    static let foliageA = "9#effect#0"
    static let foliageB = "9#effect#1"
    static let foliageExcluded = "9#effect#2"
    static let rippleA = "9#effect#3"
    static let rippleB = "9#effect#4"
    static let maskA = "masks/a"
    static let maskB = "masks/b"
    static let missingMask = "masks/missing"
    static let noise = "util/noise"
    static let normal = "effects/waterripplenormal"

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw HarnessError.invalidArguments
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let maskAURL = root.appendingPathComponent("mask-a.png")
        let maskBURL = root.appendingPathComponent("mask-b.png")
        let noiseURL = root.appendingPathComponent("noise.png")
        let normalURL = root.appendingPathComponent("normal.png")
        try writeImage(maskAURL, red: 32)
        try writeImage(maskBURL, red: 224)
        try writeImage(noiseURL, red: 128)
        try writeImage(normalURL, red: 192)
        let resolver = SceneTexturePathResolver(urlsByPath: [
            maskA: maskAURL,
            maskB: maskBURL,
            noise: noiseURL,
            normal: normalURL,
        ])
        let layer = SceneRenderDescriptor.Layer(effects: [
            foliage(foliageA, mask: maskA),
            foliage(foliageB, mask: maskB),
            foliage(foliageExcluded, mask: missingMask),
            ripple(rippleA, mask: maskA),
            ripple(rippleB, mask: maskB),
        ])
        let loader = SceneTextureLoader()
        let foliageLoaded = SceneFoliageSwayEffectTextureLoader.load(
            for: layer,
            effectIDs: [foliageA, foliageB],
            resolver: resolver,
            loader: loader,
            device: device
        )
        let foliageMissing = SceneFoliageSwayEffectTextureLoader.load(
            for: layer,
            effectIDs: [foliageExcluded],
            resolver: resolver,
            loader: loader,
            device: device
        )
        let rippleLoaded = SceneWaterRippleEffectTextureLoader.load(
            for: layer,
            effectIDs: [rippleA, rippleB],
            resolver: resolver,
            loader: loader,
            device: device
        )
        let foliageAResources = foliageLoaded.textures[foliageA]
        let foliageBResources = foliageLoaded.textures[foliageB]
        let rippleAResources = rippleLoaded.textures[rippleA]
        let rippleBResources = rippleLoaded.textures[rippleB]
        let result: [String: Any] = [
            "foliageKeys": foliageLoaded.textures.keys.sorted(),
            "foliageAMatches": foliageAResources?.matches(.init(
                maskTexturePath: maskA, noiseTexturePath: noise
            )) ?? false,
            "foliageBMatches": foliageBResources?.matches(.init(
                maskTexturePath: maskB, noiseTexturePath: noise
            )) ?? false,
            "foliageMasksDistinct": foliageAResources?.mask !== foliageBResources?.mask,
            "foliageNoiseShared": foliageAResources?.noise === foliageBResources?.noise,
            "missingFoliageFailsClosed": !(foliageMissing.textures[foliageExcluded]?
                .matches(.init(maskTexturePath: missingMask, noiseTexturePath: noise))
                ?? false),
            "rippleKeys": rippleLoaded.textures.keys.sorted(),
            "rippleAMatches": rippleAResources?.matches(.init(
                maskTexturePath: maskA, normalTexturePath: normal
            )) ?? false,
            "rippleBMatches": rippleBResources?.matches(.init(
                maskTexturePath: maskB, normalTexturePath: normal
            )) ?? false,
            "rippleMasksDistinct": rippleAResources?.mask !== rippleBResources?.mask,
            "rippleNormalShared": rippleAResources?.normal === rippleBResources?.normal,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func foliage(
        _ id: String,
        mask: String
    ) -> SceneRenderDescriptor.EffectDescriptor {
        .init(
            id: id,
            file: "effects/foliagesway/effect.json",
            passes: [.init(textureSlots: [nil, mask, noise])]
        )
    }

    static func ripple(
        _ id: String,
        mask: String
    ) -> SceneRenderDescriptor.EffectDescriptor {
        .init(
            id: id,
            file: "effects/waterripple/effect.json",
            passes: [.init(textureSlots: [nil, mask, normal])]
        )
    }

    static func writeImage(_ url: URL, red: UInt8) throws {
        let bytes: [UInt8] = [red, 0, 0, 255]
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: 1,
                  height: 1,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.last.rawValue
                  ),
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
class SceneEffectInstanceTextureLoaderTests(unittest.TestCase):
    def test_effect_resources_are_keyed_by_descriptor_id(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-effect-instance-loader-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "effect-instance-loader-test"
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
                [str(binary), str(root / "runtime")],
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
                "foliageAMatches": True,
                "foliageBMatches": True,
                "foliageKeys": ["9#effect#0", "9#effect#1"],
                "foliageMasksDistinct": True,
                "foliageNoiseShared": True,
                "missingFoliageFailsClosed": True,
                "rippleAMatches": True,
                "rippleBMatches": True,
                "rippleKeys": ["9#effect#3", "9#effect#4"],
                "rippleMasksDistinct": True,
                "rippleNormalShared": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
