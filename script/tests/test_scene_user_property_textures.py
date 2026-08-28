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
HOST_SOURCE = SOURCE_ROOT / "Runtime/SceneDesktopWallpaperHost.swift"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "Format/SceneTexDataReader.swift",
    SOURCE_ROOT / "Format/SceneTexContainer.swift",
    SOURCE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SOURCE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SOURCE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SOURCE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SOURCE_ROOT / "Resources/SceneTextureLoader.swift",
    SOURCE_ROOT / "Resources/SceneTextureSampling.swift",
    SOURCE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SOURCE_ROOT / "Resources/SceneTextureCandidate.swift",
    SOURCE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SOURCE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SOURCE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    SOURCE_ROOT / "Resources/SceneFrameTextureRegistry.swift",
    SOURCE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SOURCE_ROOT / "Properties/SceneUserPropertyTextureLoader.swift",
]

HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import ImageIO
import Metal

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

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingDirectory }
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }

        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let pngURL = directory.appendingPathComponent("cover.png")
        let jpegURL = directory.appendingPathComponent("photo.jpeg")
        let jpgURL = directory.appendingPathComponent("photo-alias.jpg")
        let invalidURL = directory.appendingPathComponent("broken.png")
        let unsupportedURL = directory.appendingPathComponent("disguised.gif")
        try writeStraightPNG(pngURL)
        try writeImage(jpegURL, type: "public.jpeg")
        try Data(contentsOf: jpegURL).write(to: jpgURL)
        try Data("not an image".utf8).write(to: invalidURL)
        try Data(contentsOf: pngURL).write(to: unsupportedURL)

        let loader = SceneUserPropertyTextureLoader()
        let absentIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "not-selected",
            purpose: .premultipliedColor
        )!
        let maskIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "png",
            purpose: .mask
        )!
        let brokenFlowIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "broken",
            purpose: .flow
        )!
        let jpegStraightIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "jpeg",
            purpose: .straightAlbedo
        )!
        let pngStraightIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "png",
            purpose: .straightAlbedo
        )!
        let pngPreservedIdentity = SceneUserPropertyTextureIdentity(
            propertyKey: "png",
            purpose: .preservedChannels
        )!
        let result = loader.load(
            urlsByPropertyKey: [
                "png": pngURL,
                "jpeg": jpegURL,
                "jpg": jpgURL,
                "broken": invalidURL,
                "unsupported": unsupportedURL,
            ],
            requestedIdentities: [
                absentIdentity, maskIdentity, brokenFlowIdentity,
                jpegStraightIdentity, pngStraightIdentity,
                pngPreservedIdentity,
            ],
            device: device
        )
        let sharedLoader = SceneTextureLoader()
        let embeddedDataOutcome = SceneTextureMipUploader.uploadEmbeddedDataImages(
            [.init(width: 2, height: 1, data: try Data(contentsOf: pngURL))],
            purpose: .preservedChannels,
            device: device
        )
        guard let embeddedDataOutcome else { throw HarnessError.textureRead }
        let embeddedStraightAlbedoOutcome = SceneTextureMipUploader.uploadEmbeddedDataImages(
            [.init(width: 3, height: 2, data: try Data(contentsOf: jpegURL))],
            purpose: .straightAlbedo,
            device: device
        )
        guard let embeddedStraightAlbedoOutcome else {
            throw HarnessError.textureRead
        }
        let premultipliedDataRejected = SceneImageTextureUploader.rgbaData(
            image: try makePremultipliedImage(),
            width: 1,
            height: 1,
            purpose: .preservedChannels
        ) == nil
        let resizedDataRejected = SceneImageTextureUploader.rgbaData(
            image: try makeStraightImage(),
            width: 2,
            height: 1,
            purpose: .preservedChannels
        ) == nil
        let decodedDataRejected = SceneImageTextureUploader.rgbaData(
            image: try makeImage(
                pixels: [231, 17, 149, 0],
                alphaInfo: .last,
                decode: [1, 0, 1, 0, 1, 0]
            ),
            width: 1,
            height: 1,
            purpose: .preservedChannels
        ) == nil
        guard let resizedOpaqueAlbedo = SceneImageTextureUploader.rgbaData(
            image: try makeOpaqueImage(),
            width: 1,
            height: 1,
            purpose: .straightAlbedo
        ) else {
            throw HarnessError.textureRead
        }
        let resizedTransparentAlbedoRejected = SceneImageTextureUploader.rgbaData(
            image: try makeStraightImage(),
            width: 2,
            height: 1,
            purpose: .straightAlbedo
        ) == nil
        let premultipliedAlbedoRejected = SceneImageTextureUploader.rgbaData(
            image: try makePremultipliedImage(),
            width: 1,
            height: 1,
            purpose: .straightAlbedo
        ) == nil
        guard let explicitBigData = SceneImageTextureUploader.rgbaData(
            image: try makeImage(
                pixels: [231, 17, 149, 0],
                alphaInfo: .last,
                byteOrder: .byteOrder32Big
            ),
            width: 1,
            height: 1,
            purpose: .preservedChannels
        ), let explicitLittleData = SceneImageTextureUploader.rgbaData(
            image: try makeImage(
                pixels: [149, 17, 231, 0],
                alphaInfo: .first,
                byteOrder: .byteOrder32Little
            ),
            width: 1,
            height: 1,
            purpose: .preservedChannels
        ) else {
            throw HarnessError.textureRead
        }
        let firstCached = sharedLoader.load(from: pngURL, device: device)
        let secondCached = sharedLoader.load(from: pngURL, device: device)
        let firstPreserved = sharedLoader.load(
            from: pngURL,
            purpose: .preservedChannels,
            device: device
        )
        let secondPreserved = sharedLoader.load(
            from: pngURL,
            purpose: .preservedChannels,
            device: device
        )
        let reusedTexture: Bool
        let reusedPreservedTexture: Bool
        let differentPurposeTexture: Bool
        if case let .loaded(first) = firstCached,
           case let .loaded(second) = secondCached,
           case let .loaded(preservedFirst) = firstPreserved,
           case let .loaded(preservedSecond) = secondPreserved {
            reusedTexture = first === second
            reusedPreservedTexture = preservedFirst === preservedSecond
            differentPurposeTexture = first !== preservedFirst
        } else {
            reusedTexture = false
            reusedPreservedTexture = false
            differentPurposeTexture = false
        }
        let reversedLoader = SceneTextureLoader()
        let reversedPreserved = reversedLoader.load(
            from: pngURL,
            purpose: .preservedChannels,
            device: device
        )
        let reversedColor = reversedLoader.load(from: pngURL, device: device)
        try Data("changed user image".utf8).write(to: pngURL)
        let changedFileInvalidatedCache: Bool
        if case .decodeFailed = sharedLoader.load(from: pngURL, device: device) {
            changedFileInvalidatedCache = true
        } else {
            changedFileInvalidatedCache = false
        }
        let retry = loader.load(
            urlsByPropertyKey: ["png": invalidURL],
            device: device
        )
        let empty = loader.load(urlsByPropertyKey: [:], device: device)
        let dimensions = result.textures.mapValues { ["width": $0.width, "height": $0.height] }
        let candidate = result.textureCandidates["png"]
        let preservedDimensions = result.preservedTextures.mapValues {
            ["width": $0.width, "height": $0.height]
        }
        let straightAlbedoDimensions = result.straightAlbedoTextures.mapValues {
            ["width": $0.width, "height": $0.height]
        }
        let publicationTokens = result.publications.keys.map(\.reportToken).sorted()
        let publicationAtomsComplete = result.publications.allSatisfy {
            identity, publication in
            publication.isComplete
                && identity.purpose == publication.candidate.purpose
                && publication.requestIdentity
                    == .materialUserProperty(identity)
                && publication.contentGeneration == 1
        }
        let publicationTexturesMatchPurpose = result.publications.allSatisfy {
            identity, publication in
            switch identity.purpose {
            case .premultipliedColor:
                return result.textures[identity.propertyKey] === publication.texture
            case .straightAlbedo:
                return result.straightAlbedoTextures[identity.propertyKey]
                    === publication.texture
            case .preservedChannels:
                return result.preservedTextures[identity.propertyKey] === publication.texture
            default:
                guard case let .ready(statePublication) =
                        result.providerStates[identity] else { return false }
                return statePublication.texture === publication.texture
            }
        }
        let unavailableTokens = result.providerStates.compactMap {
            identity, state -> String? in
            guard case .unavailable = state else { return nil }
            return identity.reportToken
        }.sorted()
        let absentTokens = result.providerStates.compactMap {
            identity, state -> String? in
            guard case .absent = state else { return nil }
            return identity.reportToken
        }.sorted()
        let payload: [String: Any] = [
            "loadedKeys": result.textures.keys.sorted(),
            "candidateKeys": result.textureCandidates.keys.sorted(),
            "candidateSharesTexture": candidate?.texture === result.textures["png"],
            "candidatePurpose": candidate?.purpose == .premultipliedColor,
            "candidatePhysicalMapped": [
                candidate?.physicalSize.width ?? -1,
                candidate?.physicalSize.height ?? -1,
                candidate?.mappedSize.width ?? -1,
                candidate?.mappedSize.height ?? -1,
            ],
            "preservedLoadedKeys": result.preservedTextures.keys.sorted(),
            "straightAlbedoLoadedKeys": result.straightAlbedoTextures.keys.sorted(),
            "dimensions": dimensions,
            "preservedDimensions": preservedDimensions,
            "straightAlbedoDimensions": straightAlbedoDimensions,
            "publicationTokens": publicationTokens,
            "publicationAtomsComplete": publicationAtomsComplete,
            "publicationTexturesMatchPurpose": publicationTexturesMatchPurpose,
            "unavailableTokens": unavailableTokens,
            "absentTokens": absentTokens,
            "colorPixels": try pixels(result.textures["png"]),
            "preservedPixels": try pixels(result.preservedTextures["png"]),
            "reversedColorPixels": try pixels(reversedColor),
            "reversedPreservedPixels": try pixels(reversedPreserved),
            "embeddedDataPixels": try pixels(embeddedDataOutcome),
            "embeddedStraightAlbedoPixels": try pixels(embeddedStraightAlbedoOutcome),
            "reportLines": result.reportLines,
            "retryLoadedKeys": retry.textures.keys.sorted(),
            "retryCandidateKeys": retry.textureCandidates.keys.sorted(),
            "retryPublicationTokens": retry.publications.keys.map(\.reportToken).sorted(),
            "retryUnavailableTokens": retry.providerStates.compactMap {
                identity, state -> String? in
                guard case .unavailable = state else { return nil }
                return identity.reportToken
            }.sorted(),
            "retryPreservedLoadedKeys": retry.preservedTextures.keys.sorted(),
            "retryReportLines": retry.reportLines,
            "emptyLoadedKeys": empty.textures.keys.sorted(),
            "emptyCandidateKeys": empty.textureCandidates.keys.sorted(),
            "emptyPreservedLoadedKeys": empty.preservedTextures.keys.sorted(),
            "emptyStraightAlbedoLoadedKeys": empty.straightAlbedoTextures.keys.sorted(),
            "emptyPublicationTokens": empty.publications.keys.map(\.reportToken).sorted(),
            "emptyProviderStateCount": empty.providerStates.count,
            "emptyReportLines": empty.reportLines,
            "reusedTexture": reusedTexture,
            "reusedPreservedTexture": reusedPreservedTexture,
            "differentPurposeTexture": differentPurposeTexture,
            "changedFileInvalidatedCache": changedFileInvalidatedCache,
            "premultipliedDataRejected": premultipliedDataRejected,
            "resizedDataRejected": resizedDataRejected,
            "decodedDataRejected": decodedDataRejected,
            "resizedOpaqueAlbedo": [UInt8](resizedOpaqueAlbedo),
            "resizedTransparentAlbedoRejected": resizedTransparentAlbedoRejected,
            "premultipliedAlbedoRejected": premultipliedAlbedoRejected,
            "explicitBigPixels": [UInt8](explicitBigData),
            "explicitLittlePixels": [UInt8](explicitLittleData),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func writeStraightPNG(_ url: URL) throws {
        let pixels = Data([
            231, 17, 149, 0,
            200, 100, 50, 64,
        ])
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: 2,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 8,
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
            throw HarnessError.imageWrite
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HarnessError.imageWrite }
    }

    private static func writeImage(_ url: URL, type: String) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 3,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 12,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type as CFString,
            1,
            nil
           ) else {
            throw HarnessError.imageWrite
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw HarnessError.imageWrite }
    }

    private static func makePremultipliedImage() throws -> CGImage {
        try makeImage(
            pixels: [12, 8, 4, 16],
            alphaInfo: .premultipliedLast
        )
    }

    private static func makeStraightImage() throws -> CGImage {
        try makeImage(
            pixels: [231, 17, 149, 0],
            alphaInfo: .last
        )
    }

    private static func makeOpaqueImage() throws -> CGImage {
        guard let provider = CGDataProvider(data: Data([
            240, 80, 40, 0,
            40, 160, 220, 0,
        ]) as CFData),
              let image = CGImage(
                  width: 2,
                  height: 1,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: 8,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw HarnessError.imageWrite
        }
        return image
    }

    private static func makeImage(
        pixels: [UInt8],
        alphaInfo: CGImageAlphaInfo,
        byteOrder: CGBitmapInfo = .byteOrderDefault,
        decode: [CGFloat]? = nil
    ) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: alphaInfo.rawValue | byteOrder.rawValue
                ),
                provider: provider,
                decode: decode,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw HarnessError.imageWrite
        }
        return image
    }

    private static func pixels(_ texture: MTLTexture?) throws -> [UInt8] {
        guard let texture else { throw HarnessError.textureRead }
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return bytes
    }

    private static func pixels(_ outcome: SceneTextureLoadOutcome) throws -> [UInt8] {
        guard case let .loaded(texture) = outcome else { throw HarnessError.textureRead }
        return try pixels(texture)
    }

    private enum HarnessError: Error {
        case missingDirectory
        case noMetal
        case imageWrite
        case textureRead
    }
}
'''


class SceneUserPropertyTextureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-user-property-textures-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-user-property-textures"
        compilation = subprocess.run(
            [
                swiftc,
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-framework", "CoreGraphics",
                "-framework", "ImageIO",
                "-module-cache-path", str(directory / "module-cache"),
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        fixture_directory = directory / "fixture"
        completed = subprocess.run(
            [str(cls.binary), str(fixture_directory)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_png_and_both_jpeg_extensions_load(self) -> None:
        self.assertEqual(self.result["loadedKeys"], ["jpeg", "jpg", "png"])
        self.assertEqual(self.result["candidateKeys"], ["jpeg", "jpg", "png"])
        self.assertEqual(self.result["reportLines"][0], "sceneUserTextureRequestedCount: 5")
        self.assertEqual(self.result["reportLines"][-3], "sceneUserTextureLoadedCount: 3")
        self.assertEqual(
            self.result["reportLines"][-2],
            "sceneUserTextureStraightAlbedoLoadedCount: 2",
        )
        self.assertEqual(
            self.result["reportLines"][-1],
            "sceneUserTexturePreservedLoadedCount: 1",
        )
        self.assertEqual(
            self.result["dimensions"],
            {
                "jpeg": {"height": 2, "width": 3},
                "jpg": {"height": 2, "width": 3},
                "png": {"height": 1, "width": 2},
            },
        )

    def test_color_textures_publish_atomic_candidates(self) -> None:
        self.assertTrue(self.result["candidateSharesTexture"])
        self.assertTrue(self.result["candidatePurpose"])
        self.assertEqual(self.result["candidatePhysicalMapped"], [2, 1, 2, 1])

    def test_all_requested_roles_publish_purpose_qualified_atoms(self) -> None:
        self.assertEqual(
            self.result["publicationTokens"],
            [
                "property:3#jpg:premultiplied-color",
                "property:3#png:mask",
                "property:3#png:premultiplied-color",
                "property:3#png:preserved-channels",
                "property:3#png:straight-albedo",
                "property:4#jpeg:premultiplied-color",
                "property:4#jpeg:straight-albedo",
            ],
        )
        self.assertTrue(self.result["publicationAtomsComplete"])
        self.assertTrue(self.result["publicationTexturesMatchPurpose"])
        self.assertEqual(
            self.result["unavailableTokens"],
            [
                "property:11#unsupported:premultiplied-color",
                "property:6#broken:flow",
                "property:6#broken:premultiplied-color",
            ],
        )
        self.assertEqual(
            self.result["absentTokens"],
            ["property:12#not-selected:premultiplied-color"],
        )

    def test_requested_property_has_a_separate_preserved_texture(self) -> None:
        self.assertEqual(self.result["preservedLoadedKeys"], ["png"])
        self.assertEqual(
            self.result["preservedDimensions"],
            {"png": {"height": 1, "width": 2}},
        )
        self.assertTrue(self.result["differentPurposeTexture"])

    def test_xray_property_roles_publish_separate_straight_albedo(self) -> None:
        self.assertEqual(
            self.result["straightAlbedoLoadedKeys"],
            ["jpeg", "png"],
        )
        self.assertEqual(
            self.result["straightAlbedoDimensions"],
            {
                "jpeg": {"height": 2, "width": 3},
                "png": {"height": 1, "width": 2},
            },
        )

    def test_png_channel_purpose_preserves_hidden_and_straight_rgb(self) -> None:
        self.assertEqual(
            self.result["preservedPixels"],
            [231, 17, 149, 0, 200, 100, 50, 64],
        )
        self.assertEqual(
            self.result["colorPixels"],
            [0, 0, 0, 0, 50, 25, 13, 64],
        )
        self.assertEqual(
            self.result["reversedPreservedPixels"],
            self.result["preservedPixels"],
        )
        self.assertEqual(
            self.result["reversedColorPixels"],
            self.result["colorPixels"],
        )
        self.assertEqual(
            self.result["embeddedDataPixels"],
            self.result["preservedPixels"],
        )

    def test_premultiplied_data_input_fails_closed(self) -> None:
        self.assertTrue(self.result["premultipliedDataRejected"])
        self.assertTrue(self.result["resizedDataRejected"])
        self.assertTrue(self.result["decodedDataRejected"])

    def test_straight_albedo_only_resizes_explicitly_opaque_images(self) -> None:
        self.assertEqual(self.result["resizedOpaqueAlbedo"][-1], 255)
        self.assertTrue(self.result["embeddedStraightAlbedoPixels"])
        self.assertEqual(
            set(self.result["embeddedStraightAlbedoPixels"][3::4]),
            {255},
        )
        self.assertTrue(self.result["resizedTransparentAlbedoRejected"])
        self.assertTrue(self.result["premultipliedAlbedoRejected"])

    def test_explicit_32_bit_byte_orders_preserve_rgba_channels(self) -> None:
        expected = [231, 17, 149, 0]
        self.assertEqual(self.result["explicitBigPixels"], expected)
        self.assertEqual(self.result["explicitLittlePixels"], expected)

    def test_corrupt_and_unsupported_files_fail_closed(self) -> None:
        report = "\n".join(self.result["reportLines"])
        self.assertIn("broken", report)
        self.assertIn("unsupported", report)
        self.assertNotIn("broken", self.result["loadedKeys"])
        self.assertNotIn("unsupported", self.result["loadedKeys"])

    def test_failed_retry_does_not_retain_an_old_texture(self) -> None:
        self.assertEqual(self.result["retryLoadedKeys"], [])
        self.assertEqual(self.result["retryCandidateKeys"], [])
        self.assertEqual(self.result["retryPublicationTokens"], [])
        self.assertEqual(
            self.result["retryUnavailableTokens"],
            ["property:3#png:premultiplied-color"],
        )
        self.assertEqual(
            [
                self.result["retryReportLines"][0],
                self.result["retryReportLines"][-3],
                self.result["retryReportLines"][-2],
                self.result["retryReportLines"][-1],
            ],
            [
                "sceneUserTextureRequestedCount: 1",
                "sceneUserTextureLoadedCount: 0",
                "sceneUserTextureStraightAlbedoLoadedCount: 0",
                "sceneUserTexturePreservedLoadedCount: 0",
            ],
        )
        self.assertEqual(self.result["retryPreservedLoadedKeys"], [])

    def test_empty_input_is_a_noop(self) -> None:
        self.assertEqual(self.result["emptyLoadedKeys"], [])
        self.assertEqual(self.result["emptyCandidateKeys"], [])
        self.assertEqual(self.result["emptyPreservedLoadedKeys"], [])
        self.assertEqual(self.result["emptyStraightAlbedoLoadedKeys"], [])
        self.assertEqual(self.result["emptyPublicationTokens"], [])
        self.assertEqual(self.result["emptyProviderStateCount"], 0)
        self.assertEqual(self.result["emptyReportLines"], [])

    def test_loader_reuses_unchanged_textures_but_invalidates_changed_user_files(self) -> None:
        self.assertTrue(self.result["reusedTexture"])
        self.assertTrue(self.result["reusedPreservedTexture"])
        self.assertTrue(self.result["changedFileInvalidatedCache"])

    def test_surface_rebuild_reopens_security_scoped_urls(self) -> None:
        source = HOST_SOURCE.read_text(encoding="utf-8")
        rebuild = source.split("private func rebuildSurfaces(", maxsplit=1)[1]
        rebuild = rebuild.split("private func teardownSurfaces", maxsplit=1)[0]
        self.assertIn("startAccessingSecurityScopedResource()", rebuild)
        self.assertIn("stopAccessingSecurityScopedResource()", rebuild)
        self.assertLess(
            rebuild.index("startAccessingSecurityScopedResource()"),
            rebuild.index("SceneMetalView("),
        )


if __name__ == "__main__":
    unittest.main()
