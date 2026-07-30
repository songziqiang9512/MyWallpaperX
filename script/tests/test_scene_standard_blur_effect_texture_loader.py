#!/usr/bin/env python3

"""Production Standard Blur mask loader → typed candidate contract."""

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
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SCENE_ROOT / "Resources/SceneEffectTextureLoadResult.swift",
    SCENE_ROOT / "Rendering/SceneTextureMappedUVScale.swift",
    SCENE_ROOT / "Resources/SceneLayerEffectTextureLoader+TextureLoading.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectMaskSemantics.swift",
    SCENE_ROOT / "Resources/SceneStandardBlurEffectTextureLoader.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

final class SceneVideoTextureSource {
    init?(
        layerID: Int,
        mp4PayloadData: Data,
        cacheDirectory: URL,
        device: MTLDevice
    ) { return nil }
}

struct SceneStandardBlurPlan {
    let effectDescriptorID: String
    let maskTexturePath: String?
}

struct SceneTexturePathResolver {
    let urlsByPath: [String: URL]

    func resolveTextureFile(named path: String) -> URL? {
        urlsByPath[path]
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let textureSlots: [String?]
            let combos: [String: Int]
        }

        let id: String
        let file: String
        let passes: [PassDescriptor]
    }

    struct Layer {
        let effects: [EffectDescriptor]
    }
}

enum SceneLayerEffectTextureLoader {}

@main
enum Harness {
    static let effectID = "530#effect#0"
    static let maskPath = "materials/test/padded-mask"

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-standard-blur-candidate-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let validURL = directory.appendingPathComponent("padded-mask.tex")
        let invalidURL = directory.appendingPathComponent("invalid-mask.tex")
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4
        ).write(to: validURL)
        try rawR8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 8,
            imageHeight: 4
        ).write(to: invalidURL)

        let loader = SceneTextureLoader()
        let valid = load(url: validURL, loader: loader, device: device)
        let invalid = load(url: invalidURL, loader: loader, device: device)
        let missing = load(url: nil, loader: loader, device: device)
        let candidate = valid.textures[effectID]?.maskCandidate
        let scale = candidate?.axisAlignedMappedUVScale(expectedPurpose: .mask)
        let result: [String: Any] = [
            "available": true,
            "candidateLoaded": candidate != nil,
            "identityIsFile": identityIsFile(candidate),
            "generationIsFile": generationIsFile(candidate),
            "purposeIsMask": candidate?.purpose == .mask,
            "physical": [
                Int(candidate?.physicalSize.width ?? -1),
                Int(candidate?.physicalSize.height ?? -1),
            ],
            "mapped": [
                Int(candidate?.mappedSize.width ?? -1),
                Int(candidate?.mappedSize.height ?? -1),
            ],
            "scale": [scale?.x ?? -1, scale?.y ?? -1],
            "sampling": [
                candidate?.sampling.filter.rawValue ?? "",
                candidate?.sampling.addressMode.rawValue ?? "",
            ],
            "matches": valid.textures[effectID]?.matches(
                .init(effectDescriptorID: effectID, maskTexturePath: maskPath)
            ) ?? false,
            "wrongPathRejected": !(valid.textures[effectID]?.matches(
                .init(effectDescriptorID: effectID, maskTexturePath: "other")
            ) ?? false),
            "invalidRejected":
                invalid.textures[effectID]?.maskCandidate == nil,
            "invalidReported": invalid.message.contains(
                "inconsistent physical/mapped dimensions"
            ),
            "missingRejected":
                missing.textures[effectID]?.maskCandidate == nil,
            "missingReported": missing.message.contains("mask missing"),
        ]
        print(String(
            decoding: try JSONSerialization.data(
                withJSONObject: result,
                options: [.sortedKeys]
            ),
            as: UTF8.self
        ))
    }

    static func load(
        url: URL?,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneStandardBlurEffectTextures], message: String) {
        let empty = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            textureSlots: [],
            combos: [:]
        )
        let combine = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            textureSlots: [nil, maskPath],
            combos: ["MASK": 1]
        )
        return SceneStandardBlurEffectTextureLoader.load(
            for: .init(effects: [.init(
                id: effectID,
                file: "effects/blur/effect.json",
                passes: [empty, empty, empty, combine]
            )]),
            effectIDs: [effectID],
            resolver: .init(urlsByPath: url.map { [maskPath: $0] } ?? [:]),
            loader: loader,
            device: device
        )
    }

    static func identityIsFile(_ candidate: SceneTextureCandidate?) -> Bool {
        guard let candidate, case .file = candidate.identity else { return false }
        return true
    }

    static func generationIsFile(_ candidate: SceneTextureCandidate?) -> Bool {
        guard let candidate, case .file = candidate.generation else { return false }
        return true
    }

    static func rawR8Tex(
        textureWidth: UInt32,
        textureHeight: UInt32,
        imageWidth: UInt32,
        imageHeight: UInt32
    ) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(9, to: &data)
        append(3, to: &data)
        append(textureWidth, to: &data)
        append(textureHeight, to: &data)
        append(imageWidth, to: &data)
        append(imageHeight, to: &data)
        append(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        append(1, to: &data)
        append(1, to: &data)
        append(textureWidth, to: &data)
        append(textureHeight, to: &data)
        append(0, to: &data)
        append(0, to: &data)
        let payload = Data(
            repeating: 127,
            count: Int(textureWidth * textureHeight)
        )
        append(UInt32(payload.count), to: &data)
        data.append(payload)
        return data
    }

    static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneStandardBlurEffectTextureLoaderTests(unittest.TestCase):
    def test_loader_publishes_padded_mask_as_one_typed_candidate(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-standard-blur-candidate-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "standard-blur-candidate-test"
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
                [str(binary)],
                check=True,
                capture_output=True,
                text=True,
            )
        result = json.loads(completed.stdout)
        if not result["available"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            result,
            {
                "available": True,
                "candidateLoaded": True,
                "generationIsFile": True,
                "identityIsFile": True,
                "invalidRejected": True,
                "invalidReported": True,
                "mapped": [4, 4],
                "matches": True,
                "missingRejected": True,
                "missingReported": True,
                "physical": [8, 4],
                "purposeIsMask": True,
                "sampling": ["nearest", "clampToEdge"],
                "scale": [0.5, 1],
                "wrongPathRejected": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
