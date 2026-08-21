#!/usr/bin/env python3
"""Water Ripple 的 effect-instance 纹理身份与 fail-closed。"""

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
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
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

struct SceneWaterRippleExecutionPlan {
    let maskTexturePath: String
    let normalTexturePath: String
}

struct SceneTexturePathResolver {
    let urlsByPath: [String: URL]

    func resolveTextureFile(named path: String) -> URL? {
        urlsByPath[path]
    }
}

struct SceneStockTextureResolver {
    let bundleRoot: URL

    init(bundleRoot: URL) {
        self.bundleRoot = bundleRoot
    }

    static func defaultBundleRoot() -> URL? {
        guard CommandLine.arguments.count == 2 else { return nil }
        return URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
    }

    func textureURL(for path: String) -> URL? {
        bundleRoot.appendingPathComponent(path).appendingPathExtension("png")
    }
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

struct SceneEffectTextureLoadResult {
    let candidate: SceneTextureCandidate?
    let message: String
}

enum SceneLayerEffectTextureLoader {
    static func loadTextureCandidate(
        url: URL?,
        label: String,
        purpose: SceneTextureLoadPurpose,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneEffectTextureLoadResult {
        guard let url else { return .init(candidate: nil, message: "") }
        switch loader.loadCandidate(from: url, purpose: purpose, device: device) {
        case .loaded(let candidate):
            return .init(candidate: candidate, message: "; \(label) OK")
        case .failed:
            return .init(candidate: nil, message: "; \(label) failed")
        }
    }
}

@main
enum Harness {
    static let rippleA = "9#effect#3"
    static let rippleB = "9#effect#4"
    static let maskA = "masks/a"
    static let maskB = "masks/b"
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
        let normalURL = root.appendingPathComponent("normal.png")
        try writeImage(maskAURL, red: 32)
        try writeImage(maskBURL, red: 224)
        try writeImage(normalURL, red: 192)
        let resolver = SceneTexturePathResolver(urlsByPath: [
            maskA: maskAURL,
            maskB: maskBURL,
            normal: normalURL,
        ])
        let layer = SceneRenderDescriptor.Layer(effects: [
            ripple(rippleA, mask: maskA),
            ripple(rippleB, mask: maskB),
        ])
        let loader = SceneTextureLoader()
        let rippleLoaded = SceneWaterRippleEffectTextureLoader.load(
            for: layer,
            effectIDs: [rippleA, rippleB],
            resolver: resolver,
            loader: loader,
            device: device
        )
        let rippleAResources = rippleLoaded.textures[rippleA]
        let rippleBResources = rippleLoaded.textures[rippleB]
        let result: [String: Any] = [
            "rippleKeys": rippleLoaded.textures.keys.sorted(),
            "rippleAMatches": rippleAResources?.resolvedArguments(for: .init(
                maskTexturePath: maskA, normalTexturePath: normal
            )) != nil,
            "rippleBMatches": rippleBResources?.resolvedArguments(for: .init(
                maskTexturePath: maskB, normalTexturePath: normal
            )) != nil,
            "rippleMasksDistinct":
                rippleAResources?.maskBinding?.texture
                    !== rippleBResources?.maskBinding?.texture,
            "rippleNormalShared":
                rippleAResources?.normalBinding?.texture
                    === rippleBResources?.normalBinding?.texture,
            "rippleSlotsTyped":
                rippleAResources?.maskBinding?.slotIndex == 1
                    && rippleAResources?.normalBinding?.slotIndex == 2,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
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
                "rippleAMatches": True,
                "rippleBMatches": True,
                "rippleKeys": ["9#effect#3", "9#effect#4"],
                "rippleMasksDistinct": True,
                "rippleNormalShared": True,
                "rippleSlotsTyped": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
