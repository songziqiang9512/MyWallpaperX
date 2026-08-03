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
    SCENE_ROOT / "Resources/SceneResourceIndex.swift",
    SCENE_ROOT / "Resources/SceneResourceView.swift",
    SCENE_ROOT / "Resources/SceneTexturePathResolver.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE_ROOT / "Resources/SceneBlendEffectTextureLoader.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneBlendExecutionPlan {
    let assetTexturePath: String
    let userPropertyKey: String?
}

struct SceneTextureLoader {}

enum SceneTextureLoadPurpose: Hashable {
    case premultipliedColor
    case preservedChannels
    case depth
}

struct SceneUserPropertyTextureIdentity: Hashable {
    let propertyKey: String
    let purpose: SceneTextureLoadPurpose

    init?(propertyKey: String, purpose: SceneTextureLoadPurpose) {
        guard !propertyKey.isEmpty else { return nil }
        self.propertyKey = propertyKey
        self.purpose = purpose
    }
}

enum SceneFrameTextureIdentity: Equatable {
    case materialUserProperty(SceneUserPropertyTextureIdentity)
}

struct SceneTextureCandidate {
    let texture: MTLTexture
}

struct SceneTextureProviderPublication {
    let requestIdentity: SceneFrameTextureIdentity
    let candidate: SceneTextureCandidate
    let isComplete: Bool
}

enum SceneTextureProviderState {
    case ready(SceneTextureProviderPublication)
    case absent
    case pending
    case unavailable
}

struct SceneTextureSlotBinding {
    let slotIndex: Int
    let candidate: SceneTextureCandidate

    init?(slotIndex: Int, candidate: SceneTextureCandidate) {
        guard (0..<8).contains(slotIndex) else { return nil }
        self.slotIndex = slotIndex
        self.candidate = candidate
    }

    var texture: MTLTexture { candidate.texture }

    func axisAlignedUVScale(
        expectedSlotIndex: Int,
        expectedPurpose: SceneTextureLoadPurpose,
        allowedPixelFormats: Set<MTLPixelFormat>,
        requiresIdentityUV: Bool = false
    ) -> SIMD2<Float>? {
        slotIndex == expectedSlotIndex ? SIMD2(repeating: 1) : nil
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let texturePaths: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
        }

        let id: String
        let file: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let imagePath: String?
        let effects: [EffectDescriptor]
    }

    struct ModelMaterialLink {
        let modelPath: String
        let materialPath: String?
    }

    struct MaterialPassDescriptor {
        let materialPath: String
        let texturePaths: [String]
    }

    let modelMaterialLinks: [ModelMaterialLink]
    let materialPasses: [MaterialPassDescriptor]
}

enum SceneLayerEffectTextureLoader {
    static func loadTextureCandidate(
        url: URL?,
        label: String,
        purpose: SceneTextureLoadPurpose,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (candidate: SceneTextureCandidate?, message: String) {
        guard let url else { return (nil, "") }
        let source: String
        if url.path.contains("/package/") {
            source = "package"
        } else if url.path.contains("/loose/") {
            source = "loose"
        } else if url.path.contains("/stock/") {
            source = "stock"
        } else {
            return (nil, "; unexpected source")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return (nil, "; allocation failed")
        }
        texture.label = source
        return (SceneTextureCandidate(texture: texture), "; \(label) OK \(source)")
    }
}

@main
enum Harness {
    static let effectID = "blend-effect"
    static let assetPath = "materials/blend.tex"
    static let propertyKey = "custombackground"

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.invalidArguments }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let package = root.appendingPathComponent("package", isDirectory: true)
        let loose = root.appendingPathComponent("loose", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let stock = root.appendingPathComponent("stock", isDirectory: true)
        for directory in [package, loose, empty, stock] {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("materials", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for directory in [package, loose, stock] {
            try Data(directory.lastPathComponent.utf8).write(
                to: directory.appendingPathComponent(assetPath)
            )
        }

        let propertyIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: propertyKey,
            purpose: .premultipliedColor
        )!
        let authored = load(
            resolver: resolver(package: package, loose: loose, stock: stock),
            userPropertyTextureStates: [propertyIdentity: .absent],
            device: device
        )
        let looseFallback = load(
            resolver: resolver(package: nil, loose: loose, stock: stock),
            userPropertyTextureStates: [propertyIdentity: .absent],
            device: device
        )
        let stockFallback = load(
            resolver: resolver(package: nil, loose: empty, stock: stock),
            userPropertyTextureStates: [propertyIdentity: .absent],
            device: device
        )
        let propertyTexture = makeTexture(device: device, label: "property")
        let propertyCandidate = SceneTextureCandidate(texture: propertyTexture)
        let property = load(
            resolver: resolver(package: package, loose: loose, stock: stock),
            userPropertyTextureStates: [
                propertyIdentity: .ready(.init(
                    requestIdentity: .materialUserProperty(propertyIdentity),
                    candidate: propertyCandidate,
                    isComplete: true
                )),
            ],
            device: device
        )
        let missing = load(
            resolver: resolver(package: nil, loose: empty, stock: nil),
            userPropertyTextureStates: [propertyIdentity: .absent],
            device: device
        )

        let result: [String: Any] = [
            "packageWins": authored.textures[effectID]?.blendBinding?.texture.label == "package",
            "looseWinsWithoutPackage":
                looseFallback.textures[effectID]?.blendBinding?.texture.label == "loose",
            "stockFillsMissingAuthorAsset":
                stockFallback.textures[effectID]?.blendBinding?.texture.label == "stock",
            "propertyWins":
                property.textures[effectID]?.blendBinding?.texture === propertyTexture,
            "missingFailsClosed": missing.textures[effectID] == nil,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func resolver(package: URL?, loose: URL, stock: URL?) -> SceneTexturePathResolver {
        SceneTexturePathResolver(
            resourceView: SceneResourceView(
                projectRootURL: loose,
                packageRootURL: package,
                stockAssetsRootURL: stock
            ),
            descriptor: SceneRenderDescriptor(modelMaterialLinks: [], materialPasses: [])
        )
    }

    static func load(
        resolver: SceneTexturePathResolver,
        userPropertyTextureStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ],
        device: MTLDevice
    ) -> (textures: [String: SceneBlendEffectTextures], message: String) {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: [assetPath],
            textureSlots: [nil, assetPath],
            userTextureInputs: [nil, .init(kind: .property, value: propertyKey)]
        )
        let layer = SceneRenderDescriptor.Layer(imagePath: nil, effects: [.init(
            id: effectID,
            file: "effects/blend/effect.json",
            visible: true,
            passes: [pass]
        )])
        return SceneBlendEffectTextureLoader.load(
            for: layer,
            effectIDs: [effectID],
            resolver: resolver,
            loader: SceneTextureLoader(),
            device: device,
            userPropertyTextureStates: userPropertyTextureStates
        )
    }

    static func makeTexture(device: MTLDevice, label: String) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.label = label
        return texture
    }

    enum HarnessError: Error { case invalidArguments }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneBlendResourceRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-blend-resource-routing-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        binary = root / "scene-blend-resource-routing"
        harness.write_text(HARNESS, encoding="utf-8")
        completed = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Metal",
                "-module-cache-path",
                str(root / "module-cache"),
                "-o",
                str(binary),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        runtime = root / "runtime"
        completed = subprocess.run(
            [str(binary), str(runtime)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        if completed.stdout.strip() == "SKIP":
            cls.temporary_directory.cleanup()
            raise unittest.SkipTest("Metal is unavailable")
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_author_roots_precede_stock_for_the_same_candidate(self) -> None:
        self.assertTrue(self.result["packageWins"], self.result)
        self.assertTrue(self.result["looseWinsWithoutPackage"], self.result)

    def test_stock_fills_only_a_missing_author_asset(self) -> None:
        self.assertTrue(self.result["stockFillsMissingAuthorAsset"], self.result)

    def test_property_texture_has_highest_priority(self) -> None:
        self.assertTrue(self.result["propertyWins"], self.result)

    def test_missing_texture_fails_closed(self) -> None:
        self.assertTrue(self.result["missingFailsClosed"], self.result)


if __name__ == "__main__":
    unittest.main()
