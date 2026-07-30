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
SWIFT_SOURCES = [
    SCENE_ROOT / "Resources/SceneXRayEffectTextureLoader.swift",
]

HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneRenderDescriptor {
    struct Layer {}
}

enum SceneTextureLoadPurpose: String {
    case premultipliedColor
    case preservedChannels
    case mask
}

final class SceneTextureLoader {}

struct SceneTexturePathResolver {
    let urls: [String: URL]

    func resolveTextureFile(named path: String) -> URL? {
        urls[path]
    }
}

enum SceneXRayRuntimePlanner {
    struct Declaration {
        let effectID: String
        let blendTexturePath: String
        let haloTexturePath: String?
        let opacityMaskPath: String?
        let blendPropertyKey: String?
        let haloPropertyKey: String?
    }

    static var current: Declaration?

    static func declaration(for layer: SceneRenderDescriptor.Layer) -> Declaration? {
        current
    }
}

enum SceneLayerEffectTextureLoader {
    static var textures: [String: MTLTexture] = [:]
    static var purposes: [String: String] = [:]

    static func loadTexture(
        url: URL?,
        label: String,
        purpose: SceneTextureLoadPurpose,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (texture: MTLTexture?, message: String) {
        purposes[label] = purpose.rawValue
        return (
            textures[label],
            textures[label] == nil ? "; \(label) unavailable" : "; \(label) OK"
        )
    }

    static func mappedUVScale(
        for url: URL?,
        texture: MTLTexture?
    ) -> SIMD2<Float> {
        guard texture != nil else { return SIMD2(repeating: 1) }
        return url?.lastPathComponent == "blend.tex"
            ? SIMD2(0.5, 0.75)
            : SIMD2(0.25, 0.5)
    }
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }
        let assetBlend = texture(device)
        let assetHalo = texture(device)
        let assetOpacity = texture(device)
        let propertyBlend = texture(device)
        let propertyHalo = texture(device)
        SceneLayerEffectTextureLoader.textures = [
            "xray blend": assetBlend,
            "xray halo": assetHalo,
            "xray opacity": assetOpacity,
        ]
        SceneXRayRuntimePlanner.current = .init(
            effectID: "layer#xray",
            blendTexturePath: "blend.tex",
            haloTexturePath: "halo.tex",
            opacityMaskPath: "opacity.tex",
            blendPropertyKey: "bottom",
            haloPropertyKey: "style"
        )
        let resolver = SceneTexturePathResolver(urls: [
            "blend.tex": URL(fileURLWithPath: "/fixture/blend.tex"),
            "halo.tex": URL(fileURLWithPath: "/fixture/halo.tex"),
            "opacity.tex": URL(fileURLWithPath: "/fixture/opacity.tex"),
        ])
        let layer = SceneRenderDescriptor.Layer()
        let loader = SceneTextureLoader()

        let propertyResult = SceneXRayEffectTextureLoader.load(
            for: layer,
            resolver: resolver,
            loader: loader,
            device: device,
            preservedUserPropertyTextures: [
                "bottom": propertyBlend,
                "style": propertyHalo,
            ]
        )
        let authoredResult = SceneXRayEffectTextureLoader.load(
            for: layer,
            resolver: resolver,
            loader: loader,
            device: device
        )
        SceneLayerEffectTextureLoader.textures["xray halo"] = nil
        let missingHaloResult = SceneXRayEffectTextureLoader.load(
            for: layer,
            resolver: resolver,
            loader: loader,
            device: device,
            preservedUserPropertyTextures: ["bottom": propertyBlend]
        )

        let payload: [String: Any] = [
            "propertyBlendSelected": propertyResult.textures?.blend === propertyBlend,
            "propertyHaloSelected": propertyResult.textures?.halo === propertyHalo,
            "propertyOpacityAuthored": propertyResult.textures?.opacityMask === assetOpacity,
            "propertyBlendScale": [
                propertyResult.textures?.blendUVScale.x ?? -1,
                propertyResult.textures?.blendUVScale.y ?? -1,
            ],
            "authoredBlendSelected": authoredResult.textures?.blend === assetBlend,
            "authoredHaloSelected": authoredResult.textures?.halo === assetHalo,
            "authoredBlendScale": [
                authoredResult.textures?.blendUVScale.x ?? -1,
                authoredResult.textures?.blendUVScale.y ?? -1,
            ],
            "missingHaloRejected": missingHaloResult.textures == nil,
            "purposes": SceneLayerEffectTextureLoader.purposes,
        ]
        print(String(
            decoding: try JSONSerialization.data(withJSONObject: payload),
            as: UTF8.self
        ))
    }

    static func texture(_ device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        return device.makeTexture(descriptor: descriptor)!
    }
}
'''


class SceneXRayTextureLoaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-xray-textures-"
        )
        directory = Path(cls._temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-xray-textures"
        compilation = subprocess.run(
            [
                swiftc,
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-module-cache-path", str(directory / "module-cache"),
                "-o", str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        if completed.stdout.strip() == "SKIP":
            raise unittest.SkipTest("Metal device is unavailable")
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary_directory.cleanup()

    def test_property_overrides_use_the_preserved_map(self) -> None:
        self.assertTrue(self.result["propertyBlendSelected"])
        self.assertTrue(self.result["propertyHaloSelected"])
        self.assertTrue(self.result["propertyOpacityAuthored"])
        self.assertEqual(self.result["propertyBlendScale"], [1, 1])

    def test_authored_assets_remain_the_fallback(self) -> None:
        self.assertTrue(self.result["authoredBlendSelected"])
        self.assertTrue(self.result["authoredHaloSelected"])
        self.assertEqual(self.result["authoredBlendScale"], [0.5, 0.75])

    def test_missing_required_halo_fails_closed(self) -> None:
        self.assertTrue(self.result["missingHaloRejected"])

    def test_every_xray_slot_requests_its_channel_purpose(self) -> None:
        self.assertEqual(
            self.result["purposes"],
            {
                "xray blend": "preservedChannels",
                "xray halo": "preservedChannels",
                "xray opacity": "mask",
            },
        )


if __name__ == "__main__":
    unittest.main()
