#!/usr/bin/env python3

"""Typed texture candidate metadata, generation, and fail-closed UV gates."""

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
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SCENE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SCENE_ROOT / "Rendering/SceneSpriteAnimation.swift",
    SCENE_ROOT / "Rendering/SceneBaseImageTextureLoad.swift",
]


HARNESS = r'''
import Foundation
import CoreGraphics
import ImageIO
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

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mwx-texture-candidate-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("padded-mask.tex")
        let spriteURL = directory.appendingPathComponent("sprite-mask.tex")
        let zeroMappedURL = directory.appendingPathComponent("zero-mapped-mask.tex")
        let oversizedMappedURL = directory.appendingPathComponent(
            "oversized-mapped-mask.tex"
        )
        let mismatchedPhysicalURL = directory.appendingPathComponent(
            "mismatched-physical-mask.tex"
        )
        let emptySpriteURL = directory.appendingPathComponent("empty-sprite-mask.tex")
        let fallbackPNGURL = directory.appendingPathComponent("fallback.png")
        let unparsedFallbackURL = directory.appendingPathComponent(
            "unparsed-fallback-mask.tex"
        )
        let croppedColorURL = directory.appendingPathComponent(
            "cropped-color.tex"
        )
        let normalizedColorURL = directory.appendingPathComponent(
            "normalized-color.tex"
        )
        let wrongOutputURL = directory.appendingPathComponent(
            "wrong-output-color.tex"
        )
        let mappedEmbeddedURL = directory.appendingPathComponent(
            "mapped-embedded-color.tex"
        )
        let mappedTexb3EmbeddedURL = directory.appendingPathComponent(
            "mapped-texb3-embedded-color.tex"
        )
        let malformedTexb3EmbeddedURL = directory.appendingPathComponent(
            "malformed-texb3-embedded-color.tex"
        )
        let decodedMismatchTexb3URL = directory.appendingPathComponent(
            "decoded-mismatch-texb3-embedded-color.tex"
        )
        let lowerMipMismatchTexb3URL = directory.appendingPathComponent(
            "lower-mip-mismatch-texb3-embedded-color.tex"
        )
        let freeFormatMismatchTexb3URL = directory.appendingPathComponent(
            "free-format-mismatch-texb3-embedded-color.tex"
        )
        let mappedTexb3JPEGURL = directory.appendingPathComponent(
            "mapped-texb3-embedded-color-jpeg.tex"
        )
        let mappedTexb2MipURL = directory.appendingPathComponent(
            "mapped-texb2-mip-color.tex"
        )
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 3
        ).write(to: url)
        try spriteR8Tex().write(to: spriteURL)
        try rawR8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 0,
            imageHeight: 4,
            flags: 0
        ).write(to: zeroMappedURL)
        try rawR8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 8,
            imageHeight: 4,
            flags: 0
        ).write(to: oversizedMappedURL)
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 0,
            mipWidth: 4,
            mipHeight: 4
        ).write(to: mismatchedPhysicalURL)
        try emptySpriteR8Tex().write(to: emptySpriteURL)
        try writeImage(fallbackPNGURL)
        var unparsedFallback = Data("invalid TEX header ".utf8)
        unparsedFallback.append(try Data(contentsOf: fallbackPNGURL))
        try unparsedFallback.write(to: unparsedFallbackURL)
        try rawRGBA8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4
        ).write(to: croppedColorURL)
        try embeddedImageTex(
            textureWidth: 8192,
            textureHeight: 4,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try pngData(width: 4097, height: 2)
        ).write(to: normalizedColorURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 3)
        ).write(to: wrongOutputURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4)
        ).write(to: mappedEmbeddedURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            mipWidth: 4,
            mipHeight: 4,
            additionalMips: [
                (2, 2, try pngData(width: 2, height: 2)),
            ]
        ).write(to: mappedTexb3EmbeddedURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            mipWidth: 5,
            mipHeight: 4
        ).write(to: malformedTexb3EmbeddedURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 3, height: 4),
            containerVersion: "TEXB0003",
            mipWidth: 4,
            mipHeight: 4
        ).write(to: decodedMismatchTexb3URL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            mipWidth: 4,
            mipHeight: 4,
            additionalMips: [
                (2, 2, try pngData(width: 1, height: 2)),
            ]
        ).write(to: lowerMipMismatchTexb3URL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            freeImageFormat: 2,
            mipWidth: 4,
            mipHeight: 4
        ).write(to: freeFormatMismatchTexb3URL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try jpegData(width: 4, height: 4),
            containerVersion: "TEXB0003",
            freeImageFormat: 2,
            mipWidth: 4,
            mipHeight: 4,
            additionalMips: [
                (2, 2, try jpegData(width: 2, height: 2)),
            ]
        ).write(to: mappedTexb3JPEGURL)
        try embeddedImageTex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            payload: try pngData(width: 4, height: 4),
            containerVersion: "TEXB0002",
            mipWidth: 4,
            mipHeight: 4
        ).write(to: mappedTexb2MipURL)

        let loader = SceneTextureLoader()
        let first = try candidate(loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        ))
        let repeated = try candidate(loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        ))
        let flow = try candidate(loader.loadCandidate(
            from: url,
            purpose: .flow,
            device: device
        ))
        let spriteRejected: Bool
        switch loader.loadCandidate(
            from: spriteURL,
            purpose: .mask,
            device: device
        ) {
        case .failed(.decodeFailed(let message)):
            spriteRejected = message.contains("one non-sprite image")
        default:
            spriteRejected = false
        }
        let zeroMappedRejected = rejectedDimensions(
            loader.loadCandidate(
                from: zeroMappedURL,
                purpose: .mask,
                device: device
            )
        )
        let oversizedMappedRejected = rejectedDimensions(
            loader.loadCandidate(
                from: oversizedMappedURL,
                purpose: .mask,
                device: device
            )
        )
        let mismatchedPhysicalRejected = rejectedDimensions(
            loader.loadCandidate(
                from: mismatchedPhysicalURL,
                purpose: .mask,
                device: device
            )
        )
        let emptySpriteRejected = rejectedNonSprite(
            loader.loadCandidate(
                from: emptySpriteURL,
                purpose: .mask,
                device: device
            )
        )
        let unparsedFallbackRejected = rejectedUnparsedMetadata(
            loader.loadCandidate(
                from: unparsedFallbackURL,
                purpose: .mask,
                device: device
            )
        )
        let croppedColor = try candidate(loader.loadCandidate(
            from: croppedColorURL,
            purpose: .premultipliedColor,
            device: device
        ))
        let normalizedColor = try candidate(loader.loadCandidate(
            from: normalizedColorURL,
            purpose: .premultipliedColor,
            device: device
        ))
        let wrongOutputRejected = rejectedDimensions(
            loader.loadCandidate(
                from: wrongOutputURL,
                purpose: .premultipliedColor,
                device: device
            )
        )
        let mappedEmbeddedColor = try candidate(loader.loadCandidate(
            from: mappedEmbeddedURL,
            purpose: .premultipliedColor,
            device: device
        ))
        let mappedEmbeddedNormalRejected = rejectedDimensions(
            loader.loadCandidate(
                from: mappedEmbeddedURL,
                purpose: .normal,
                device: device
            )
        )
        let mappedTexb3EmbeddedColor = try candidate(loader.loadCandidate(
            from: mappedTexb3EmbeddedURL,
            purpose: .premultipliedColor,
            device: device
        ))
        let mappedTexb3EmbeddedNormal = try candidate(loader.loadCandidate(
            from: mappedTexb3EmbeddedURL,
            purpose: .normal,
            device: device
        ))
        let malformedTexb3EmbeddedRejected = rejectedDimensions(
            loader.loadCandidate(
                from: malformedTexb3EmbeddedURL,
                purpose: .premultipliedColor,
                device: device
            )
        )
        let decodedMismatchTexb3Rejected = rejectedDimensions(
            loader.loadCandidate(
                from: decodedMismatchTexb3URL,
                purpose: .premultipliedColor,
                device: device
            )
        )
        let lowerMipMismatchTexb3Rejected = rejectedDimensions(
            loader.loadCandidate(
                from: lowerMipMismatchTexb3URL,
                purpose: .premultipliedColor,
                device: device
            )
        )
        let freeFormatMismatchTexb3Rejected = rejectedDimensions(
            loader.loadCandidate(
                from: freeFormatMismatchTexb3URL,
                purpose: .premultipliedColor,
                device: device
            )
        )
        let mappedTexb3JPEG = try candidate(loader.loadCandidate(
            from: mappedTexb3JPEGURL,
            purpose: .premultipliedColor,
            device: device
        ))
        let mappedTexb2MipRejected = rejectedDimensions(
            loader.loadCandidate(
                from: mappedTexb2MipURL,
                purpose: .premultipliedColor,
                device: device
            )
        )
        let baseDirect = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: fallbackPNGURL,
            usesPuppet: false,
            loader: loader,
            device: device
        ))
        let baseCropped = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: croppedColorURL,
            usesPuppet: false,
            loader: loader,
            device: device
        ))
        let basePaddedLegacy = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: url,
            usesPuppet: false,
            loader: loader,
            device: device
        ))
        let baseSpriteLegacy = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: spriteURL,
            usesPuppet: false,
            loader: loader,
            device: device
        ))
        let basePuppetLegacy = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: croppedColorURL,
            usesPuppet: true,
            loader: loader,
            device: device
        ))
        let baseUnparsedLegacy = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: unparsedFallbackURL,
            usesPuppet: false,
            loader: loader,
            device: device
        ))
        let baseCandidateFailureTerminal = baseRejectedDimensions(
            SceneBaseImageTextureLoad.load(
                from: mismatchedPhysicalURL,
                usesPuppet: false,
                loader: loader,
                device: device
            )
        )
        var baseStore = SceneBaseImageTextureStore()
        baseStore.set(
            baseDirect.texture,
            candidate: baseDirect.candidate,
            layerID: 7
        )
        baseStore[7] = baseCropped.texture
        let baseStoreReplacementClearsCandidate =
            baseStore.candidates[7] == nil
        baseStore.set(
            baseDirect.texture,
            candidate: baseDirect.candidate,
            layerID: 7
        )
        let mismatchedSnapshot = baseStore.snapshot(
            textures: [7: baseCropped.texture]
        )
        let baseSnapshotDropsMismatchedCandidate =
            mismatchedSnapshot.candidate(
                for: 7,
                matching: baseCropped.texture
            ) == nil
        let firstScale = first.axisAlignedMappedUVScale(expectedPurpose: .mask)
        let croppedColorScale = croppedColor.axisAlignedMappedUVScale(
            expectedPurpose: .premultipliedColor
        )
        let normalizedColorScale = normalizedColor.axisAlignedMappedUVScale(
            expectedPurpose: .premultipliedColor
        )

        let wrongPurposeRejected =
            first.axisAlignedMappedUVScale(expectedPurpose: .flow) == nil
        let invalidPhysical = copy(
            first,
            physicalSize: CGSize(
                width: first.physicalSize.width + 1,
                height: first.physicalSize.height
            )
        )
        let invalidMapped = copy(
            first,
            mappedSize: CGSize(
                width: first.physicalSize.width + 1,
                height: first.mappedSize.height
            )
        )
        let translated = copy(
            first,
            uvTransform: SceneTextureUVTransform(
                origin: SIMD2(0.1, 0),
                xAxis: first.uvTransform.xAxis,
                yAxis: first.uvTransform.yAxis
            )
        )
        let rotated = copy(
            first,
            uvTransform: SceneTextureUVTransform(
                origin: .zero,
                xAxis: SIMD2(0, first.uvTransform.xAxis.x),
                yAxis: SIMD2(first.uvTransform.yAxis.y, 0)
            )
        )

        let originalGeneration = first.generation
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 8,
            imageWidth: 8,
            imageHeight: 8,
            flags: 0
        ).write(to: url)
        let refreshed = try candidate(loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        ))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let result: [String: Any] = [
            "available": true,
            "identityIsCanonicalFile": filePath(first.identity)
                == url.resolvingSymlinksInPath().standardizedFileURL.path,
            "generationIsFile": generationByteCount(first.generation) != nil,
            "firstPhysical": [
                Int(first.physicalSize.width), Int(first.physicalSize.height),
            ],
            "firstMapped": [
                Int(first.mappedSize.width), Int(first.mappedSize.height),
            ],
            "firstScale": [firstScale?.x ?? -1, firstScale?.y ?? -1],
            "firstSampling": [
                first.sampling.filter.rawValue,
                first.sampling.addressMode.rawValue,
            ],
            "firstPixelFormat": first.pixelFormat.rawValue,
            "sameCandidateTexture": first.texture === repeated.texture,
            "sameCandidateGeneration": first.generation == repeated.generation,
            "sameResourceIdentityAcrossPurpose": first.identity == flow.identity,
            "sameGenerationAcrossPurpose": first.generation == flow.generation,
            "purposeCacheSeparated": first.texture !== flow.texture,
            "wrongPurposeRejected": wrongPurposeRejected,
            "invalidPhysicalRejected": invalidPhysical
                .axisAlignedMappedUVScale(expectedPurpose: .mask) == nil,
            "invalidMappedRejected": invalidMapped
                .axisAlignedMappedUVScale(expectedPurpose: .mask) == nil,
            "translatedRejected": translated
                .axisAlignedMappedUVScale(expectedPurpose: .mask) == nil,
            "rotatedRejected": rotated
                .axisAlignedMappedUVScale(expectedPurpose: .mask) == nil,
            "spriteRejected": spriteRejected,
            "zeroMappedRejected": zeroMappedRejected,
            "oversizedMappedRejected": oversizedMappedRejected,
            "mismatchedPhysicalRejected": mismatchedPhysicalRejected,
            "emptySpriteRejected": emptySpriteRejected,
            "unparsedFallbackRejected": unparsedFallbackRejected,
            "croppedColorPhysical": [
                Int(croppedColor.physicalSize.width),
                Int(croppedColor.physicalSize.height),
            ],
            "croppedColorMapped": [
                Int(croppedColor.mappedSize.width),
                Int(croppedColor.mappedSize.height),
            ],
            "croppedColorScale": [
                croppedColorScale?.x ?? -1,
                croppedColorScale?.y ?? -1,
            ],
            "normalizedColorPhysical": [
                Int(normalizedColor.physicalSize.width),
                Int(normalizedColor.physicalSize.height),
            ],
            "normalizedColorMapped": [
                Int(normalizedColor.mappedSize.width),
                Int(normalizedColor.mappedSize.height),
            ],
            "normalizedColorScale": [
                normalizedColorScale?.x ?? -1,
                normalizedColorScale?.y ?? -1,
            ],
            "wrongOutputRejected": wrongOutputRejected,
            "mappedEmbeddedColorIdentity":
                mappedEmbeddedColor.axisAlignedMappedUVScale(
                    expectedPurpose: .premultipliedColor
                ) == SIMD2(repeating: 1),
            "mappedEmbeddedNormalRejected": mappedEmbeddedNormalRejected,
            "mappedTexb3EmbeddedColorIdentity":
                mappedTexb3EmbeddedColor.axisAlignedMappedUVScale(
                    expectedPurpose: .premultipliedColor
                ) == SIMD2(repeating: 1),
            "mappedTexb3EmbeddedNormalIdentity":
                mappedTexb3EmbeddedNormal.axisAlignedMappedUVScale(
                    expectedPurpose: .normal
                ) == SIMD2(repeating: 1),
            "malformedTexb3EmbeddedRejected": malformedTexb3EmbeddedRejected,
            "decodedMismatchTexb3Rejected": decodedMismatchTexb3Rejected,
            "lowerMipMismatchTexb3Rejected": lowerMipMismatchTexb3Rejected,
            "freeFormatMismatchTexb3Rejected":
                freeFormatMismatchTexb3Rejected,
            "mappedTexb3JPEGIdentity":
                mappedTexb3JPEG.axisAlignedMappedUVScale(
                    expectedPurpose: .premultipliedColor
                ) == SIMD2(repeating: 1),
            "mappedTexb2MipRejected": mappedTexb2MipRejected,
            "baseDirectCandidate": baseDirect.candidate != nil,
            "baseCroppedCandidate": baseCropped.candidate != nil,
            "basePaddedR8Legacy":
                basePaddedLegacy.candidate == nil
                    && basePaddedLegacy.message.contains("legacy binding"),
            "baseSpriteLegacy":
                baseSpriteLegacy.candidate == nil
                    && baseSpriteLegacy.animation != nil,
            "basePuppetLegacy":
                basePuppetLegacy.candidate == nil
                    && basePuppetLegacy.message.contains("puppet atlas"),
            "baseUnparsedLegacy":
                baseUnparsedLegacy.candidate == nil
                    && baseUnparsedLegacy.message.contains("unparsed TEX"),
            "baseCandidateFailureTerminal": baseCandidateFailureTerminal,
            "baseStoreReplacementClearsCandidate":
                baseStoreReplacementClearsCandidate,
            "baseSnapshotDropsMismatchedCandidate":
                baseSnapshotDropsMismatchedCandidate,
            "generationChangedAfterRewrite": originalGeneration != refreshed.generation,
            "textureChangedAfterRewrite": first.texture !== refreshed.texture,
            "refreshedPhysical": [
                Int(refreshed.physicalSize.width), Int(refreshed.physicalSize.height),
            ],
            "refreshedGenerationMatchesFileSize":
                generationByteCount(refreshed.generation)
                    == (attributes[.size] as? NSNumber)?.uint64Value,
            "diagnosticCarriesContract":
                first.diagnosticSummary.contains("purpose=mask")
                    && first.diagnosticSummary.contains("physical=8x4")
                    && first.diagnosticSummary.contains("mapped=4x4")
                    && first.diagnosticSummary.contains("sampling=nearest/clampToEdge"),
        ]
        print(String(
            decoding: try JSONSerialization.data(
                withJSONObject: result,
                options: [.sortedKeys]
            ),
            as: UTF8.self
        ))
    }

    static func candidate(
        _ outcome: SceneTextureCandidateLoadOutcome
    ) throws -> SceneTextureCandidate {
        guard case .loaded(let candidate) = outcome else {
            throw HarnessError.loadFailed
        }
        return candidate
    }

    static func baseLoaded(
        _ outcome: SceneBaseImageTextureLoad.Outcome
    ) throws -> SceneBaseImageTextureLoad.Loaded {
        guard case .loaded(let loaded) = outcome else {
            throw HarnessError.loadFailed
        }
        return loaded
    }

    static func copy(
        _ source: SceneTextureCandidate,
        physicalSize: CGSize? = nil,
        mappedSize: CGSize? = nil,
        uvTransform: SceneTextureUVTransform? = nil
    ) -> SceneTextureCandidate {
        SceneTextureCandidate(
            texture: source.texture,
            identity: source.identity,
            generation: source.generation,
            purpose: source.purpose,
            physicalSize: physicalSize ?? source.physicalSize,
            mappedSize: mappedSize ?? source.mappedSize,
            uvTransform: uvTransform ?? source.uvTransform,
            sampling: source.sampling
        )
    }

    static func filePath(_ identity: SceneTextureResourceIdentity) -> String? {
        guard case .file(let path) = identity else { return nil }
        return path
    }

    static func generationByteCount(
        _ generation: SceneTextureResourceGeneration
    ) -> UInt64? {
        guard case .file(let byteCount, _) = generation else { return nil }
        return byteCount
    }

    static func rejectedDimensions(
        _ outcome: SceneTextureCandidateLoadOutcome
    ) -> Bool {
        guard case .failed(.decodeFailed(let message)) = outcome else {
            return false
        }
        return message.contains("inconsistent physical/mapped dimensions")
    }

    static func baseRejectedDimensions(
        _ outcome: SceneBaseImageTextureLoad.Outcome
    ) -> Bool {
        guard case .failed(.decodeFailed(let message)) = outcome else {
            return false
        }
        return message.contains("inconsistent physical/mapped dimensions")
    }

    static func rejectedNonSprite(
        _ outcome: SceneTextureCandidateLoadOutcome
    ) -> Bool {
        guard case .failed(.decodeFailed(let message)) = outcome else {
            return false
        }
        return message.contains("one non-sprite image")
    }

    static func rejectedUnparsedMetadata(
        _ outcome: SceneTextureCandidateLoadOutcome
    ) -> Bool {
        guard case .failed(.decodeFailed(let message)) = outcome else {
            return false
        }
        return message.contains("requires parsed TEX metadata")
    }

    static func rawR8Tex(
        textureWidth: UInt32,
        textureHeight: UInt32,
        imageWidth: UInt32,
        imageHeight: UInt32,
        flags: UInt32,
        mipWidth: UInt32? = nil,
        mipHeight: UInt32? = nil
    ) -> Data {
        let storedWidth = mipWidth ?? textureWidth
        let storedHeight = mipHeight ?? textureHeight
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(9, to: &data)
        append(flags, to: &data)
        append(textureWidth, to: &data)
        append(textureHeight, to: &data)
        append(imageWidth, to: &data)
        append(imageHeight, to: &data)
        append(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        append(1, to: &data)
        append(1, to: &data)
        append(storedWidth, to: &data)
        append(storedHeight, to: &data)
        append(0, to: &data)
        append(0, to: &data)
        let payload = Data(
            repeating: 127,
            count: Int(storedWidth * storedHeight)
        )
        append(UInt32(payload.count), to: &data)
        data.append(payload)
        return data
    }

    static func spriteR8Tex() -> Data {
        var data = rawR8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 4
        )
        data.append(Data("TEXS0002\0".utf8))
        append(1, to: &data)
        append(0, to: &data)
        appendFloat(0.1, to: &data)
        for value: Float in [1, 0, 0, 4, 4, 0] {
            appendFloat(value, to: &data)
        }
        return data
    }

    static func emptySpriteR8Tex() -> Data {
        var data = rawR8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 4
        )
        data.append(Data("TEXS0002\0".utf8))
        append(0, to: &data)
        return data
    }

    static func rawRGBA8Tex(
        textureWidth: UInt32,
        textureHeight: UInt32,
        imageWidth: UInt32,
        imageHeight: UInt32
    ) -> Data {
        let payload = Data(
            repeating: 127,
            count: Int(textureWidth * textureHeight * 4)
        )
        return embeddedImageTex(
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            payload: payload
        )
    }

    static func embeddedImageTex(
        textureWidth: UInt32,
        textureHeight: UInt32,
        imageWidth: UInt32,
        imageHeight: UInt32,
        payload: Data,
        containerVersion: String = "TEXB0002",
        freeImageFormat: UInt32 = 13,
        mipWidth: UInt32? = nil,
        mipHeight: UInt32? = nil,
        additionalMips: [(UInt32, UInt32, Data)] = []
    ) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(0, to: &data)
        append(2, to: &data)
        append(textureWidth, to: &data)
        append(textureHeight, to: &data)
        append(imageWidth, to: &data)
        append(imageHeight, to: &data)
        append(0, to: &data)
        data.append(Data("\(containerVersion)\0".utf8))
        append(1, to: &data)
        if containerVersion == "TEXB0003" {
            append(freeImageFormat, to: &data)
        }
        let mips = [
            (mipWidth ?? textureWidth, mipHeight ?? textureHeight, payload),
        ] + additionalMips
        append(UInt32(mips.count), to: &data)
        for (width, height, mipPayload) in mips {
            append(width, to: &data)
            append(height, to: &data)
            append(0, to: &data)
            append(0, to: &data)
            append(UInt32(mipPayload.count), to: &data)
            data.append(mipPayload)
        }
        return data
    }

    static func pngData(width: Int, height: Int) throws -> Data {
        try encodedImageData(
            width: width,
            height: height,
            type: "public.png" as CFString
        )
    }

    static func jpegData(width: Int, height: Int) throws -> Data {
        try encodedImageData(
            width: width,
            height: height,
            type: "public.jpeg" as CFString
        )
    }

    static func encodedImageData(
        width: Int,
        height: Int,
        type: CFString
    ) throws -> Data {
        let pixels = Data(repeating: 127, count: width * height * 4)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.last.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  data,
                  type,
                  1,
                  nil
              ) else {
            throw HarnessError.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.imageCreationFailed
        }
        return data as Data
    }

    static func writeImage(_ url: URL) throws {
        let pixels: [UInt8] = [
            231, 17, 149, 0,
            200, 100, 50, 64,
            17, 203, 41, 255,
            89, 7, 211, 128,
        ]
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: 2,
                  height: 2,
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
            throw HarnessError.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.imageCreationFailed
        }
    }

    static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    static func appendFloat(_ value: Float, to data: inout Data) {
        var littleEndian = value.bitPattern.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    enum HarnessError: Error {
        case loadFailed
        case imageCreationFailed
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneTextureCandidateTests(unittest.TestCase):
    def test_candidate_keeps_texture_and_slot_metadata_atomic(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-texture-candidate-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "texture-candidate-test"
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
                "baseCandidateFailureTerminal": True,
                "baseCroppedCandidate": True,
                "baseDirectCandidate": True,
                "basePaddedR8Legacy": True,
                "basePuppetLegacy": True,
                "baseSpriteLegacy": True,
                "baseSnapshotDropsMismatchedCandidate": True,
                "baseStoreReplacementClearsCandidate": True,
                "baseUnparsedLegacy": True,
                "croppedColorMapped": [4, 4],
                "croppedColorPhysical": [4, 4],
                "croppedColorScale": [1, 1],
                "decodedMismatchTexb3Rejected": True,
                "diagnosticCarriesContract": True,
                "emptySpriteRejected": True,
                "firstMapped": [4, 4],
                "firstPhysical": [8, 4],
                "firstPixelFormat": 10,
                "firstSampling": ["nearest", "clampToEdge"],
                "firstScale": [0.5, 1],
                "generationChangedAfterRewrite": True,
                "generationIsFile": True,
                "identityIsCanonicalFile": True,
                "invalidMappedRejected": True,
                "invalidPhysicalRejected": True,
                "mismatchedPhysicalRejected": True,
                "mappedEmbeddedColorIdentity": True,
                "mappedEmbeddedNormalRejected": True,
                "freeFormatMismatchTexb3Rejected": True,
                "lowerMipMismatchTexb3Rejected": True,
                "malformedTexb3EmbeddedRejected": True,
                "mappedTexb2MipRejected": True,
                "mappedTexb3EmbeddedColorIdentity": True,
                "mappedTexb3EmbeddedNormalIdentity": True,
                "mappedTexb3JPEGIdentity": True,
                "normalizedColorMapped": [4096, 1],
                "normalizedColorPhysical": [4096, 1],
                "normalizedColorScale": [1, 1],
                "oversizedMappedRejected": True,
                "purposeCacheSeparated": True,
                "refreshedGenerationMatchesFileSize": True,
                "refreshedPhysical": [8, 8],
                "rotatedRejected": True,
                "sameCandidateGeneration": True,
                "sameCandidateTexture": True,
                "sameGenerationAcrossPurpose": True,
                "sameResourceIdentityAcrossPurpose": True,
                "spriteRejected": True,
                "textureChangedAfterRewrite": True,
                "translatedRejected": True,
                "unparsedFallbackRejected": True,
                "wrongPurposeRejected": True,
                "wrongOutputRejected": True,
                "zeroMappedRejected": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
