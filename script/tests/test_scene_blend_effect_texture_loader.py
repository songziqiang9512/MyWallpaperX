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
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SCENE_ROOT / "Resources/SceneBlendEffectTextureLoader.swift",
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

struct SceneBlendExecutionPlan {
    let assetTexturePath: String
    let userPropertyKey: String?
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
        let effects: [EffectDescriptor]
    }
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
        switch loader.loadCandidate(from: url, purpose: purpose, device: device) {
        case .loaded(let candidate):
            return (candidate, "; \(label) OK \(url.lastPathComponent)")
        case .failed(let outcome):
            switch outcome {
            case .loaded:
                return (nil, "; \(label) typed candidate unavailable")
            case .unsupportedFormat(let ext):
                return (nil, "; \(label) unsupported \(ext)")
            case .unsupportedTexFormat(let code):
                return (nil, "; \(label) unsupported .tex format \(code)")
            case .texNoEmbeddedImage:
                return (nil, "; \(label) has no embedded image")
            case .texContainsVideoPayload:
                return (nil, "; \(label) is mp4 payload")
            case .decodeFailed(let message):
                return (nil, "; \(label) decode failed (\(message))")
            case .textureAllocationFailed(let width, let height):
                return (nil, "; \(label) allocation failed at \(width)x\(height)")
            }
        }
    }
}

@main
enum Harness {
    static let effectID = "342#effect#344"
    static let assetPath = "generated-background.tex"
    static let propertyKey = "custombackground"

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw HarnessError.invalidArguments
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }

        let temporary = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: true
        )
        let pngURL = temporary.appendingPathComponent("generated.png")
        let texURL = temporary.appendingPathComponent(assetPath)
        let corruptURL = temporary.appendingPathComponent("corrupt.png")
        try writeImage(pngURL, width: 4, height: 4)
        try writeTex(
            texURL,
            imageData: Data(contentsOf: pngURL),
            physicalWidth: 4,
            physicalHeight: 4,
            mappedWidth: 2,
            mappedHeight: 3
        )
        try Data("not an image".utf8).write(to: corruptURL)

        let propertyTexture = makeTexture(
            device: device,
            width: 7,
            height: 5,
            label: "property override"
        )
        let propertyCandidate = candidate(
            texture: propertyTexture,
            identity: "property:\(propertyKey)"
        )
        let validInputs: [SceneEffectTextureInput?] = [
            nil,
            .init(kind: .property, value: propertyKey),
        ]
        let property = load(
            inputs: validInputs,
            urlsByPath: [assetPath: texURL],
            userPropertyTextureCandidates: [propertyKey: propertyCandidate],
            device: device
        )
        let fallback = load(
            inputs: validInputs,
            urlsByPath: [assetPath: texURL],
            userPropertyTextureCandidates: [:],
            device: device
        )
        let missing = load(
            inputs: validInputs,
            urlsByPath: [:],
            userPropertyTextureCandidates: [:],
            device: device
        )
        let corrupt = load(
            inputs: validInputs,
            urlsByPath: [assetPath: corruptURL],
            userPropertyTextureCandidates: [:],
            device: device
        )
        let system = load(
            inputs: [nil, .init(kind: .system, value: "$mediaThumbnail")],
            urlsByPath: [assetPath: texURL],
            userPropertyTextureCandidates: [propertyKey: propertyCandidate],
            device: device
        )
        let emptyProperty = load(
            inputs: [nil, .init(kind: .property, value: "")],
            urlsByPath: [assetPath: texURL],
            userPropertyTextureCandidates: [propertyKey: propertyCandidate],
            device: device
        )
        let malformed = load(
            inputs: [.init(kind: .property, value: propertyKey)],
            urlsByPath: [assetPath: texURL],
            userPropertyTextureCandidates: [propertyKey: propertyCandidate],
            device: device
        )

        let propertyTextures = property.textures[effectID]
        let fallbackTextures = fallback.textures[effectID]
        let exactPlan = SceneBlendExecutionPlan(
            assetTexturePath: "GENERATED-BACKGROUND.TEX",
            userPropertyKey: propertyKey
        )
        let wrongAssetPlan = SceneBlendExecutionPlan(
            assetTexturePath: "different.tex",
            userPropertyKey: propertyKey
        )
        let wrongPropertyPlan = SceneBlendExecutionPlan(
            assetTexturePath: assetPath,
            userPropertyKey: "different-property"
        )
        let propertyArguments = propertyTextures?.resolvedArguments(for: exactPlan)
        let fallbackArguments = fallbackTextures?.resolvedArguments(for: exactPlan)

        let result: [String: Any] = [
            "propertyWins": propertyArguments?.blend.texture === propertyTexture,
            "propertyUsesIdentityUV": propertyArguments?.uvScale == SIMD2(repeating: 1),
            "propertyReported": property.message.contains(
                "blend property texture OK \(propertyKey)"
            ),
            "fallbackLoadedAuthoredTex": fallbackArguments?.blend.texture !== propertyTexture
                && fallbackArguments?.blend.texture.width == 4
                && fallbackArguments?.blend.texture.height == 4,
            "fallbackMappedUV": [
                fallbackArguments?.uvScale.x ?? -1,
                fallbackArguments?.uvScale.y ?? -1,
            ],
            "fallbackReported": fallback.message.contains("blend effect texture OK"),
            "missingStayedFailed": missing.textures[effectID] == nil,
            "missingReported": missing.message.contains(
                "blend effect texture missing \(assetPath)"
            ),
            "corruptStayedFailed": corrupt.textures[effectID] == nil,
            "corruptReported": corrupt.message.contains("decode failed"),
            "systemRejected": system.textures[effectID] == nil,
            "emptyPropertyRejected": emptyProperty.textures[effectID] == nil,
            "malformedInputsRejected": malformed.textures[effectID] == nil,
            "normalizedMatch": fallbackArguments != nil,
            "wrongAssetDoesNotMatch":
                fallbackTextures?.resolvedArguments(for: wrongAssetPlan) == nil,
            "wrongPropertyDoesNotMatch": !(
                fallbackTextures?.resolvedArguments(for: wrongPropertyPlan) != nil
            ),
            "bindingCarriesCandidate": fallbackArguments?.blend.identity
                == fallbackArguments?.blend.candidate.identity,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func load(
        inputs: [SceneEffectTextureInput?],
        urlsByPath: [String: URL],
        userPropertyTextureCandidates: [String: SceneTextureCandidate],
        device: MTLDevice
    ) -> (textures: [String: SceneBlendEffectTextures], message: String) {
        let pass = SceneRenderDescriptor.EffectDescriptor.PassDescriptor(
            passIndex: 0,
            texturePaths: [assetPath],
            textureSlots: [nil, assetPath],
            userTextureInputs: inputs
        )
        let layer = SceneRenderDescriptor.Layer(effects: [.init(
            id: effectID,
            file: "effects/blend/effect.json",
            visible: true,
            passes: [pass]
        )])
        return SceneBlendEffectTextureLoader.load(
            for: layer,
            effectIDs: [effectID],
            resolver: .init(urlsByPath: urlsByPath),
            loader: SceneTextureLoader(),
            device: device,
            userPropertyTextureCandidates: userPropertyTextureCandidates
        )
    }

    static func candidate(
        texture: MTLTexture,
        identity: String
    ) -> SceneTextureCandidate {
        SceneTextureCandidate(
            texture: texture,
            identity: .builtIn(name: identity),
            generation: .immutable(revision: 1),
            purpose: .premultipliedColor,
            physicalSize: CGSize(width: texture.width, height: texture.height),
            mappedSize: CGSize(width: texture.width, height: texture.height),
            uvTransform: .identity,
            sampling: .directImageFallback
        )
    }

    static func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        label: String
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        texture.label = label
        return texture
    }

    static func writeTex(
        _ url: URL,
        imageData: Data,
        physicalWidth: UInt32,
        physicalHeight: UInt32,
        mappedWidth: UInt32,
        mappedHeight: UInt32
    ) throws {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(0, to: &data)
        append(0, to: &data)
        append(physicalWidth, to: &data)
        append(physicalHeight, to: &data)
        append(mappedWidth, to: &data)
        append(mappedHeight, to: &data)
        append(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        append(1, to: &data)
        append(1, to: &data)
        append(physicalWidth, to: &data)
        append(physicalHeight, to: &data)
        append(0, to: &data)
        append(0, to: &data)
        append(UInt32(imageData.count), to: &data)
        data.append(imageData)
        try data.write(to: url)
    }

    static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    static func writeImage(_ url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytes = [UInt8](repeating: 127, count: width * height * 4)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
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
class SceneBlendEffectTextureLoaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-blend-effect-texture-loader-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        binary = root / "blend-effect-texture-loader-test"
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
        if compilation.returncode != 0:
            cls.temporary_directory.cleanup()
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary), str(root / "runtime")],
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

    def test_property_texture_wins_and_missing_property_falls_back(self) -> None:
        self.assertTrue(self.result["propertyWins"], self.result)
        self.assertTrue(self.result["propertyUsesIdentityUV"], self.result)
        self.assertTrue(self.result["propertyReported"], self.result)
        self.assertTrue(self.result["fallbackLoadedAuthoredTex"], self.result)
        self.assertTrue(self.result["fallbackReported"], self.result)

    def test_authored_tex_mapped_uv_scale_is_retained(self) -> None:
        self.assertEqual(self.result["fallbackMappedUV"], [0.5, 0.75], self.result)

    def test_missing_and_corrupt_authored_assets_fail_closed(self) -> None:
        for key in (
            "missingStayedFailed",
            "missingReported",
            "corruptStayedFailed",
            "corruptReported",
        ):
            self.assertTrue(self.result[key], (key, self.result))

    def test_malformed_and_system_user_texture_inputs_are_rejected(self) -> None:
        for key in (
            "systemRejected",
            "emptyPropertyRejected",
            "malformedInputsRejected",
        ):
            self.assertTrue(self.result[key], (key, self.result))

    def test_texture_identity_match_requires_asset_and_property(self) -> None:
        for key in (
            "normalizedMatch",
            "wrongAssetDoesNotMatch",
            "wrongPropertyDoesNotMatch",
            "bindingCarriesCandidate",
        ):
            self.assertTrue(self.result[key], (key, self.result))


if __name__ == "__main__":
    unittest.main()
