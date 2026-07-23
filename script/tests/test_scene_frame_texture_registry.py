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
        let replacementFallbackTexture = texture()
        let propertyTexture = texture()
        let replacementPropertyTexture = texture()
        let systemTexture = texture()
        let replacementSystemTexture = texture()
        let namedTexture = texture()
        let optionalProperty = SceneFrameTextureIdentity.userProperty("cover")
        let persistentProperty = SceneFrameTextureIdentity.userProperty("persistent-cover")
        let system = SceneFrameTextureIdentity.system("$mediaThumbnail")
        let fallback = SceneFrameTextureIdentity.layerSource(7)
        let selection = SceneFrameTextureSelection(candidates: [optionalProperty, fallback])
        let firstEpoch = registry.beginFrame(
            layerSources: [7: fallbackTexture],
            userPropertyTextures: ["persistent-cover": propertyTexture],
            systemTextures: ["$mediaThumbnail": systemTexture]
        )
        let firstFallback = registry.resolve(SceneFrameTextureSelection(candidates: [fallback]))!
        let firstProperty = registry.resolve(SceneFrameTextureSelection(candidates: [persistentProperty]))!
        let firstSystem = registry.resolve(SceneFrameTextureSelection(candidates: [system]))!
        let absent = registry.resolve(selection)
        registry.set(.pending, for: optionalProperty)
        let pending = registry.resolve(selection)
        registry.set(.unavailable, for: optionalProperty)
        let unavailable = registry.resolve(selection)
        registry.set(.ready(propertyTexture), for: optionalProperty)
        let ready = registry.resolve(selection)

        let primary = SceneNamedTextureReference(providerLayerID: 42, variant: .primary)
        let secondary = SceneNamedTextureReference(providerLayerID: 42, variant: .secondary)
        let named = SceneFrameTextureIdentity.namedLayerTarget(primary)
        registry.set(.ready(namedTexture), for: named)
        let firstNamed = registry.resolve(SceneFrameTextureSelection(candidates: [named]))!
        let primaryReady = registry.texture(for: named) === namedTexture
        let secondaryIsolated = registry.texture(
            for: .namedLayerTarget(secondary)
        ) == nil

        let secondEpoch = registry.beginFrame(
            layerSources: [7: fallbackTexture],
            userPropertyTextures: ["persistent-cover": propertyTexture],
            systemTextures: ["$mediaThumbnail": systemTexture]
        )
        let secondFallback = registry.resolve(SceneFrameTextureSelection(candidates: [fallback]))!
        let secondProperty = registry.resolve(SceneFrameTextureSelection(candidates: [persistentProperty]))!
        let secondSystem = registry.resolve(SceneFrameTextureSelection(candidates: [system]))!
        let namedCleared = registry.texture(for: named) == nil
        registry.set(.ready(namedTexture), for: named)
        let secondNamed = registry.resolve(SceneFrameTextureSelection(candidates: [named]))!

        registry.beginFrame(
            layerSources: [7: replacementFallbackTexture],
            userPropertyTextures: ["persistent-cover": replacementPropertyTexture],
            systemTextures: ["$mediaThumbnail": replacementSystemTexture]
        )
        let replacedFallback = registry.resolve(SceneFrameTextureSelection(candidates: [fallback]))!
        let replacedProperty = registry.resolve(SceneFrameTextureSelection(candidates: [persistentProperty]))!
        let replacedSystem = registry.resolve(SceneFrameTextureSelection(candidates: [system]))!

        registry.beginFrame(layerSources: [:])
        let persistentEntriesCleared = registry.texture(for: fallback) == nil
            && registry.texture(for: persistentProperty) == nil
            && registry.texture(for: system) == nil

        registry.beginFrame(
            layerSources: [7: fallbackTexture],
            userPropertyTextures: ["persistent-cover": propertyTexture],
            systemTextures: ["$mediaThumbnail": systemTexture]
        )
        let restoredFallback = registry.resolve(SceneFrameTextureSelection(candidates: [fallback]))!
        let restoredProperty = registry.resolve(SceneFrameTextureSelection(candidates: [persistentProperty]))!
        let restoredSystem = registry.resolve(SceneFrameTextureSelection(candidates: [system]))!

        let result: [String: Any] = [
            "frameEpochAdvanced": secondEpoch == firstEpoch + 1,
            "persistentGenerationsStable": secondFallback.generation == firstFallback.generation
                && secondProperty.generation == firstProperty.generation
                && secondSystem.generation == firstSystem.generation,
            "replacementGenerationsAdvanced": replacedFallback.generation > secondFallback.generation
                && replacedProperty.generation > secondProperty.generation
                && replacedSystem.generation > secondSystem.generation,
            "restoredGenerationsAdvanced": restoredFallback.generation > replacedFallback.generation
                && restoredProperty.generation > replacedProperty.generation
                && restoredSystem.generation > replacedSystem.generation,
            "absentFallback": absent?.usedFallback == true && absent?.texture === fallbackTexture,
            "pendingFallback": pending?.usedFallback == true && pending?.texture === fallbackTexture,
            "unavailableFallback": unavailable?.usedFallback == true
                && unavailable?.texture === fallbackTexture,
            "readyOverride": ready?.usedFallback == false && ready?.texture === propertyTexture,
            "primaryReady": primaryReady,
            "secondaryIsolated": secondaryIsolated,
            "namedCleared": namedCleared,
            "namedGenerationAdvanced": secondNamed.generation == firstNamed.generation + 1,
            "persistentEntriesCleared": persistentEntriesCleared,
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
            "frameEpochAdvanced",
            "primaryReady",
            "secondaryIsolated",
            "namedCleared",
            "namedGenerationAdvanced",
        ):
            self.assertTrue(self.result[key], key)

    def test_persistent_resource_generations_change_only_with_publication(self) -> None:
        for key in (
            "persistentGenerationsStable",
            "replacementGenerationsAdvanced",
            "restoredGenerationsAdvanced",
            "persistentEntriesCleared",
        ):
            self.assertTrue(self.result[key], key)


if __name__ == "__main__":
    unittest.main()
