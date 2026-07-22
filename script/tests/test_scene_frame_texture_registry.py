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
SWIFT_SOURCES = [
    SOURCE_ROOT / "SceneNamedTextureReference.swift",
    SOURCE_ROOT / "SceneFrameTextureRegistry.swift",
]

HARNESS_SOURCE = r'''
import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "SceneFrameTextureRegistryTests", code: 1)
        }
        func texture() -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: 4,
                height: 4,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .renderTarget]
            return device.makeTexture(descriptor: descriptor)!
        }

        let registry = SceneFrameTextureRegistry()
        let fallbackTexture = texture()
        let propertyTexture = texture()
        let namedTexture = texture()
        let property = SceneFrameTextureIdentity.userProperty("cover")
        let selection = SceneFrameTextureSelection(candidates: [property, .layerSource(7)])
        let firstGeneration = registry.beginFrame(layerSources: [7: fallbackTexture])
        let absent = registry.resolve(selection)
        registry.set(.pending, for: property)
        let pending = registry.resolve(selection)
        registry.set(.unavailable, for: property)
        let unavailable = registry.resolve(selection)
        registry.set(.ready(propertyTexture), for: property)
        let ready = registry.resolve(selection)

        let primary = SceneNamedTextureReference(providerLayerID: 42, variant: .primary)
        let secondary = SceneNamedTextureReference(providerLayerID: 42, variant: .secondary)
        registry.set(.ready(namedTexture), for: .namedLayerTarget(primary))
        let primaryReady = registry.texture(for: .namedLayerTarget(primary)) === namedTexture
        let secondaryIsolated = registry.texture(for: .namedLayerTarget(secondary)) == nil
        let secondGeneration = registry.beginFrame(layerSources: [7: fallbackTexture])
        let namedCleared = registry.texture(for: .namedLayerTarget(primary)) == nil

        let result: [String: Any] = [
            "generationAdvanced": secondGeneration == firstGeneration + 1,
            "absentFallback": absent?.usedFallback == true && absent?.texture === fallbackTexture,
            "pendingFallback": pending?.usedFallback == true && pending?.texture === fallbackTexture,
            "unavailableFallback": unavailable?.usedFallback == true
                && unavailable?.texture === fallbackTexture,
            "readyOverride": ready?.usedFallback == false && ready?.texture === propertyTexture,
            "primaryReady": primaryReady,
            "secondaryIsolated": secondaryIsolated,
            "namedCleared": namedCleared,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneFrameTextureRegistryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-texture-registry-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = root / "texture-registry"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_ready_provider_wins_and_unready_provider_falls_back(self) -> None:
        for key in (
            "absentFallback",
            "pendingFallback",
            "unavailableFallback",
            "readyOverride",
        ):
            self.assertTrue(self.result[key], key)

    def test_named_target_identity_and_frame_lifetime_are_preserved(self) -> None:
        for key in (
            "generationAdvanced",
            "primaryReady",
            "secondaryIsolated",
            "namedCleared",
        ):
            self.assertTrue(self.result[key], key)


if __name__ == "__main__":
    unittest.main()
