#!/usr/bin/env python3
"""Opacity/Tint loaders publish the shared typed effect texture binding."""

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
    SCENE_ROOT / "Resources/SceneOpacityEffectTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTintEffectTextureLoader.swift",
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

struct SceneOpacityExecutionPlan { let maskTexturePath: String? }
struct SceneTintExecutionPlan { let maskTexturePath: String? }

struct SceneTexturePathResolver {
    let urlsByPath: [String: URL]
    func resolveTextureFile(named path: String) -> URL? { urlsByPath[path] }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [String]
            let combos: [String: Int]
        }
        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }
    struct Layer { let effects: [EffectDescriptor] }
}

enum SceneLayerEffectTextureLoader {}

@main
enum Harness {
    static let path = "masks/padded"
    static let missingPath = "masks/missing"

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-opacity-tint-shared-binding-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("padded-mask.tex")
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4
        ).write(to: url)
        let resolver = SceneTexturePathResolver(urlsByPath: [path: url])
        let loader = SceneTextureLoader()
        let opacity = SceneOpacityEffectTextureLoader.load(
            for: .init(effects: [
                effect(id: "opacity-ready", file: "effects/opacity/effect.json", mask: path),
                effect(id: "opacity-missing", file: "effects/opacity/effect.json", mask: missingPath),
            ]),
            resolver: resolver,
            loader: loader,
            device: device
        )
        let tint = SceneTintEffectTextureLoader.load(
            for: .init(effects: [
                effect(id: "tint-ready", file: "effects/tint/effect.json", mask: path),
                effect(id: "tint-absent", file: "effects/tint/effect.json", mask: nil),
                effect(id: "tint-missing", file: "effects/tint/effect.json", mask: missingPath),
            ]),
            effectIDs: ["tint-ready", "tint-absent", "tint-missing"],
            resolver: resolver,
            loader: loader,
            device: device
        )
        let opacityReady = opacity.textures["opacity-ready"]!
        let tintReady = tint.textures["tint-ready"]!
        let result: [String: Any] = [
            "available": true,
            "opacityReady": opacityReady.state == .ready
                && opacityReady.binding.purpose == .mask
                && opacityReady.binding.matches(path: path)
                && opacityReady.matches(.init(maskTexturePath: path)),
            "opacityGeneration": isFile(opacityReady.generation),
            "opacityScale": opacityReady.maskUVScale == SIMD2<Float>(0.5, 1),
            "opacityMissing": opacity.textures["opacity-missing"]?.state == .unavailable,
            "tintReady": tintReady.state == .ready
                && tintReady.binding.purpose == .mask
                && tintReady.matches(.init(maskTexturePath: path)),
            "tintGeneration": isFile(tintReady.generation),
            "tintScale": tintReady.maskUVScale == SIMD2<Float>(0.5, 1),
            "tintAbsent": tint.textures["tint-absent"]?.state == .absent
                && tint.textures["tint-absent"]?.matches(.init(maskTexturePath: nil)) == true,
            "tintMissing": tint.textures["tint-missing"]?.state == .unavailable
                && tint.textures["tint-missing"]?.matches(
                    .init(maskTexturePath: missingPath)
                ) == false,
        ]
        print(String(
            decoding: try JSONSerialization.data(
                withJSONObject: result,
                options: [.sortedKeys]
            ),
            as: UTF8.self
        ))
    }

    static func effect(
        id: String,
        file: String,
        mask: String?
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let paths = mask.map { [$0] } ?? []
        let slots: [String?] = mask.map { [nil, $0] } ?? []
        return .init(
            id: id,
            file: file,
            visible: true,
            passes: [.init(
                passIndex: 0,
                texturePaths: paths,
                textureSlots: slots,
                userTextureInputs: [],
                combos: mask == nil ? [:] : ["MASK": 1]
            )]
        )
    }

    static func isFile(_ generation: SceneTextureResourceGeneration?) -> Bool {
        guard case .file? = generation else { return false }
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
        let payload = Data(repeating: 127, count: Int(textureWidth * textureHeight))
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
class SceneOpacityTintSharedTextureBindingTests(unittest.TestCase):
    def test_loaders_publish_shared_typed_mask_state(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-opacity-tint-binding-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "opacity-tint-binding-test"
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
                    "-o",
                    str(binary),
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            execution = subprocess.run(
                [str(binary)], capture_output=True, text=True, check=False
            )
            self.assertEqual(execution.returncode, 0, execution.stderr)
            result = json.loads(execution.stdout)
            if not result.get("available", False):
                self.skipTest("Metal device unavailable")
            self.assertTrue(all(result.values()), result)


if __name__ == "__main__":
    unittest.main()
