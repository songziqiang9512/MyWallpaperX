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
IMAGE_LAYER_METAL_SOURCE = SCENE_ROOT / "Rendering/SceneImageLayer.metal"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneTextureSampling.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Resources/SceneTextureCandidate.swift",
    SCENE_ROOT / "Resources/SceneNamedTextureReference.swift",
    SCENE_ROOT / "Resources/SceneTextureSlotBinding.swift",
    SCENE_ROOT / "Resources/SceneFrameTextureRegistry.swift",
    SCENE_ROOT / "Resources/SceneTextureProviderPublication.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader+Candidate.swift",
    SCENE_ROOT / "Resources/SceneMultiImageSpriteResidentBudget.swift",
    SCENE_ROOT / "Resources/SceneMultiImageSpritePlayback.swift",
    SCENE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SCENE_ROOT / "Rendering/SceneImageLayerCompositor+Uniforms.swift",
    SCENE_ROOT / "Rendering/SceneSpriteAnimation.swift",
    SCENE_ROOT / "Rendering/SceneBaseImageTextureCandidateSupport.swift",
    SCENE_ROOT / "Rendering/SceneBaseImageTextureLoad.swift",
    SCENE_ROOT / "Rendering/SceneBaseImageTextureLoad+Ordinary.swift",
]


HARNESS = r'''
import Foundation
import CoreGraphics
import Darwin
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

final class SceneSourceUpdateTransaction {
    private var rollbacks: [() -> Void] = []

    func registerRollback(_ action: @escaping () -> Void) {
        rollbacks.append(action)
    }

    func commit() { rollbacks.removeAll() }
}

enum SceneGraphExecutionResetReason { case test }

final class StubResolvedMaterialRuntime {
    var shouldDeferFrame = false
    func invalidate(reason: SceneGraphExecutionResetReason) { _ = reason }
}

struct SceneImageLayerCompositor {
    var resolvedMaterialRuntime: StubResolvedMaterialRuntime? = nil
}

struct SceneRenderDescriptor {
    struct Layer {
        let contentKind: String
        let brightness: Double?
    }
}

struct SceneDependencyEffectInput {
    let blendMode: Int
}

struct SceneImageLayerUniformValues {
    let time: Float
    let alpha: Float
    let cursorUV: SIMD2<Float>
    let tint: SIMD3<Float>
}

struct SceneLayerEffectSourceExtent {
    let pixelSize: CGSize
}

struct SceneImageLayerDrawRequest {
    let layer: SceneRenderDescriptor.Layer
    let texture: MTLTexture
    let uniforms: SceneImageLayerUniformValues
    let dependencyEffect: SceneDependencyEffectInput?
    let effectSourceExtent: SceneLayerEffectSourceExtent?
    let sourceSample: SceneBaseImageTextureSample?

    func resolvedBaseTextureSample() -> SceneBaseImageTextureSample? {
        sourceSample
    }
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"available\":false}")
            return
        }
        let shaderSource = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        let imageLayerLibrary = try device.makeLibrary(
            source: shaderSource,
            options: nil
        )
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
        let missingURL = directory.appendingPathComponent("missing-mask.tex")
        let spriteURL = directory.appendingPathComponent("sprite-mask.tex")
        let crossImageSpriteURL = directory.appendingPathComponent(
            "cross-image-sprite.tex"
        )
        let rotatedCrossImageSpriteURL = directory.appendingPathComponent(
            "rotated-cross-image-sprite.tex"
        )
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
        let nearestRepeatColorURL = directory.appendingPathComponent(
            "nearest-repeat-color.tex"
        )
        let clampBorderColorURL = directory.appendingPathComponent(
            "clamp-border-color.tex"
        )
        let unknownSamplerColorURL = directory.appendingPathComponent(
            "unknown-sampler-color.tex"
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
        let normalizedStraightAlbedoJPEGURL = directory.appendingPathComponent(
            "normalized-straight-albedo-jpeg.tex"
        )
        let normalizedStraightAlbedoPNGURL = directory.appendingPathComponent(
            "normalized-straight-albedo-png.tex"
        )
        let transparentStraightAlbedoPNGURL = directory.appendingPathComponent(
            "transparent-straight-albedo-png.tex"
        )
        let mipNormalizedStraightAlbedoPNGURL = directory.appendingPathComponent(
            "mip-normalized-straight-albedo-png.tex"
        )
        let paddedStraightAlbedoJPEGURL = directory.appendingPathComponent(
            "padded-straight-albedo-jpeg.tex"
        )
        let mislabeledTexb4StraightAlbedoPNGURL = directory.appendingPathComponent(
            "mislabeled-texb4-straight-albedo-png.tex"
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
        try crossImageSpriteBC3Tex().write(to: crossImageSpriteURL)
        try crossImageSpriteBC3Tex(rotatedSecondFrame: true)
            .write(to: rotatedCrossImageSpriteURL)
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
        try rawRGBA8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 1
        ).write(to: nearestRepeatColorURL)
        try rawRGBA8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 8
        ).write(to: clampBorderColorURL)
        try rawRGBA8Tex(
            textureWidth: 4,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 16
        ).write(to: unknownSamplerColorURL)
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
            textureWidth: 4097,
            textureHeight: 2,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try jpegData(width: 4097, height: 2),
            containerVersion: "TEXB0003",
            freeImageFormat: 2,
            mipWidth: 4097,
            mipHeight: 2
        ).write(to: normalizedStraightAlbedoJPEGURL)
        try embeddedImageTex(
            textureWidth: 4097,
            textureHeight: 2,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try opaquePNGData(width: 4097, height: 2),
            containerVersion: "TEXB0003",
            freeImageFormat: 13,
            mipWidth: 4097,
            mipHeight: 2
        ).write(to: normalizedStraightAlbedoPNGURL)
        try embeddedImageTex(
            textureWidth: 4097,
            textureHeight: 2,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try pngData(width: 4097, height: 2),
            containerVersion: "TEXB0003",
            freeImageFormat: 13,
            mipWidth: 4097,
            mipHeight: 2
        ).write(to: transparentStraightAlbedoPNGURL)
        try embeddedImageTex(
            textureWidth: 8192,
            textureHeight: 2,
            imageWidth: 8192,
            imageHeight: 2,
            payload: try pngData(width: 8192, height: 2),
            containerVersion: "TEXB0003",
            freeImageFormat: 13,
            mipWidth: 8192,
            mipHeight: 2,
            additionalMips: [
                (4096, 1, try pngData(width: 4096, height: 1)),
            ]
        ).write(to: mipNormalizedStraightAlbedoPNGURL)
        try embeddedImageTex(
            textureWidth: 8192,
            textureHeight: 4,
            imageWidth: 4096,
            imageHeight: 2,
            payload: try jpegData(width: 8192, height: 4),
            containerVersion: "TEXB0003",
            freeImageFormat: 2,
            mipWidth: 8192,
            mipHeight: 4
        ).write(to: paddedStraightAlbedoJPEGURL)
        try embeddedImageTex(
            textureWidth: 4097,
            textureHeight: 2,
            imageWidth: 4097,
            imageHeight: 2,
            payload: try opaquePNGData(width: 4097, height: 2),
            containerVersion: "TEXB0004",
            freeImageFormat: 2,
            mipMetadataEntryCount: 2,
            mipWidth: 4097,
            mipHeight: 2
        ).write(to: mislabeledTexb4StraightAlbedoPNGURL)
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
        let spriteTextureLoader = SceneMultiImageSpriteTextureLoader()
        let missingSourceKeyUnavailable = loader.sourceKey(for: missingURL) == nil
        let missingMetadataRejected: Bool
        switch loader.loadCandidate(
            from: missingURL,
            purpose: .mask,
            device: device
        ) {
        case .failed(.decodeFailed(let message)):
            missingMetadataRejected = message.contains("file metadata unavailable")
        default:
            missingMetadataRejected = false
        }
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
        let normalizedStraightAlbedoJPEG = try candidate(loader.loadCandidate(
            from: normalizedStraightAlbedoJPEGURL,
            purpose: .straightAlbedo,
            device: device
        ))
        let normalizedStraightAlbedoPNG = try candidate(loader.loadCandidate(
            from: normalizedStraightAlbedoPNGURL,
            purpose: .straightAlbedo,
            device: device
        ))
        let transparentStraightAlbedoPNGRejected: Bool
        switch loader.loadCandidate(
            from: transparentStraightAlbedoPNGURL,
            purpose: .straightAlbedo,
            device: device
        ) {
        case .loaded:
            transparentStraightAlbedoPNGRejected = false
        case .failed:
            transparentStraightAlbedoPNGRejected = true
        }
        let mipNormalizedStraightAlbedoPNG = try candidate(
            loader.loadCandidate(
                from: mipNormalizedStraightAlbedoPNGURL,
                purpose: .straightAlbedo,
                device: device
            )
        )
        let mipNormalizedStraightAlbedoPixel = try readFirstPixel(
            texture: mipNormalizedStraightAlbedoPNG.texture,
            device: device
        )
        let paddedStraightAlbedoJPEGRejected = rejectedDimensions(
            loader.loadCandidate(
                from: paddedStraightAlbedoJPEGURL,
                purpose: .straightAlbedo,
                device: device
            )
        )
        let mislabeledTexb4StraightAlbedoPNGRejected = rejectedDimensions(
            loader.loadCandidate(
                from: mislabeledTexb4StraightAlbedoPNGURL,
                purpose: .straightAlbedo,
                device: device
            )
        )
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
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let baseCropped = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: croppedColorURL,
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let clampBorderBaseLoadRejected: Bool
        switch SceneBaseImageTextureLoad.load(
            from: clampBorderColorURL,
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ) {
        case .failed(.decodeFailed(let message)):
            clampBorderBaseLoadRejected = message.contains("clamp-border")
                && message.contains("rawFlags=8")
        default:
            clampBorderBaseLoadRejected = false
        }
        let unknownSamplerBaseLoadRejected: Bool
        switch SceneBaseImageTextureLoad.load(
            from: unknownSamplerColorURL,
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ) {
        case .failed(.decodeFailed(let message)):
            unknownSamplerBaseLoadRejected = message.contains("unknown")
                && message.contains("rawFlags=16")
        default:
            unknownSamplerBaseLoadRejected = false
        }
        let baseNearestRepeat = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: nearestRepeatColorURL,
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let basePaddedSpecialized = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: url,
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let baseSpritePlayback = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: spriteURL,
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let baseCrossImageSprite = try baseLoaded(
            SceneBaseImageTextureLoad.load(
                from: crossImageSpriteURL,
                usesPuppet: false,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
        )
        let baseRotatedCrossImageSprite = try baseLoaded(
            SceneBaseImageTextureLoad.load(
                from: rotatedCrossImageSpriteURL,
                usesPuppet: false,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
        )
        let baseBudgetLimitedCrossImageSprite = try baseLoaded(
            SceneBaseImageTextureLoad.load(
                from: crossImageSpriteURL,
                usesPuppet: false,
                loader: loader,
                spriteTextureLoader: SceneMultiImageSpriteTextureLoader(
                    residentByteBudget: 1
                ),
                device: device
            )
        )
        guard let crossImageAnimation = baseCrossImageSprite.animation,
              let commandQueue = device.makeCommandQueue() else {
            throw HarnessError.loadFailed
        }
        let firstFrameCommandBuffer = commandQueue.makeCommandBuffer()!
        let firstFrameTransaction = SceneSourceUpdateTransaction()
        crossImageAnimation.encode(
            sceneTime: 0,
            commandBuffer: firstFrameCommandBuffer,
            transaction: firstFrameTransaction
        )
        firstFrameCommandBuffer.commit()
        firstFrameTransaction.commit()
        firstFrameCommandBuffer.waitUntilCompleted()
        let crossImageFrame0Pixel = try readFirstPixel(
            texture: baseCrossImageSprite.texture,
            device: device
        )
        let secondFrameCommandBuffer = commandQueue.makeCommandBuffer()!
        let secondFrameTransaction = SceneSourceUpdateTransaction()
        crossImageAnimation.encode(
            sceneTime: 0.04,
            commandBuffer: secondFrameCommandBuffer,
            transaction: secondFrameTransaction
        )
        secondFrameCommandBuffer.commit()
        secondFrameTransaction.commit()
        secondFrameCommandBuffer.waitUntilCompleted()
        let crossImageFrame1Pixel = try readFirstPixel(
            texture: baseCrossImageSprite.texture,
            device: device
        )
        let crossImageTransform = crossImageAnimation.transform(at: 0.04)
        let basePuppetSpecialized = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: croppedColorURL,
            usesPuppet: true,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let baseUnparsedSpecialized = try baseLoaded(SceneBaseImageTextureLoad.load(
            from: unparsedFallbackURL,
            usesPuppet: false,
            loader: loader,
            spriteTextureLoader: spriteTextureLoader,
            device: device
        ))
        let baseCandidateFailureTerminal = baseRejectedDimensions(
            SceneBaseImageTextureLoad.load(
                from: mismatchedPhysicalURL,
                usesPuppet: false,
                loader: loader,
                spriteTextureLoader: spriteTextureLoader,
                device: device
            )
        )
        guard let baseDirectCandidate = baseDirect.candidate else {
            throw HarnessError.loadFailed
        }
        let mappedNearestCandidate = copy(
            baseDirectCandidate,
            mappedSize: CGSize(
                width: baseDirectCandidate.physicalSize.width / 2,
                height: baseDirectCandidate.physicalSize.height
            ),
            uvTransform: SceneTextureUVTransform(
                origin: .zero,
                xAxis: SIMD2(0.5, 0),
                yAxis: SIMD2(0, 1)
            ),
            sampling: SceneTextureSampling(texFlags: 1)
        )
        let mappedNearestSample = SceneBaseImageTextureCandidateResolver.sample(
            candidate: mappedNearestCandidate,
            sourceTexture: mappedNearestCandidate.texture
        )
        let clampBorderSample = SceneBaseImageTextureCandidateResolver.sample(
            candidate: copy(
                baseDirectCandidate,
                sampling: SceneTextureSampling(texFlags: 8)
            ),
            sourceTexture: baseDirectCandidate.texture
        )
        let unknownFlagsSample = SceneBaseImageTextureCandidateResolver.sample(
            candidate: copy(
                baseDirectCandidate,
                sampling: SceneTextureSampling(texFlags: 16)
            ),
            sourceTexture: baseDirectCandidate.texture
        )
        guard let mappedNearestSample else { throw HarnessError.loadFailed }
        let compositor = SceneImageLayerCompositor()
        let values = SceneImageLayerUniformValues(
            time: 0,
            alpha: 1,
            cursorUV: .zero,
            tint: SIMD3(repeating: 1)
        )
        let sourceUniforms = compositor.sourceFragmentUniforms(
            for: .init(
                layer: .init(contentKind: "image", brightness: nil),
                texture: baseDirect.texture,
                uniforms: values,
                dependencyEffect: nil,
                effectSourceExtent: nil,
                sourceSample: mappedNearestSample
            ),
            routesOffscreen: true
        )
        let sourceFragmentUniformCarriesCandidateAtom =
            sourceUniforms?.sourceSampling == SIMD2(3, 0)
                && sourceUniforms?.textureFrame0
                    == mappedNearestSample.textureFrame.uniform0
                && sourceUniforms?.textureFrame1
                    == mappedNearestSample.textureFrame.uniform1
        let styledSourceUniforms = compositor.sourceFragmentUniforms(
            for: .init(
                layer: .init(contentKind: "image", brightness: 1.5),
                texture: baseDirect.texture,
                uniforms: .init(
                    time: 0,
                    alpha: 0.5,
                    cursorUV: .zero,
                    tint: SIMD3(0.2, 0.4, 0.6)
                ),
                dependencyEffect: nil,
                effectSourceExtent: nil,
                sourceSample: mappedNearestSample
            ),
            routesOffscreen: true
        )
        let styledTint = styledSourceUniforms?.tint
        let sourceFragmentUniformCarriesAuthoredStyle =
            styledSourceUniforms?.alpha == 0.5
                && abs((styledTint?.x ?? 0) - 0.3) < 0.000_001
                && abs((styledTint?.y ?? 0) - 0.6) < 0.000_001
                && abs((styledTint?.z ?? 0) - 0.9) < 0.000_001
                && styledTint?.w == 1
        let zeroAlphaPixel = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: .init(
                    time: 0,
                    alpha: 0,
                    cursorUV: .zero,
                    tint: SIMD3(repeating: 1)
                ),
                textureFrame: .identity,
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil
            ),
            library: imageLayerLibrary,
            device: device
        )
        let wrappedInterior = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(0.25, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: SceneTextureSampling(texFlags: 3)
            ),
            library: imageLayerLibrary,
            device: device
        )
        let repeatedOutside = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(1.25, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: mappedNearestSample.sampling
            ),
            library: imageLayerLibrary,
            device: device
        )
        let clampedOutside = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(1.25, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: SceneTextureSampling(texFlags: 3)
            ),
            library: imageLayerLibrary,
            device: device
        )
        let nearestBetweenTexels = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(0.375, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: SceneTextureSampling(texFlags: 3)
            ),
            library: imageLayerLibrary,
            device: device
        )
        let linearBetweenTexels = try renderSample(
            texture: baseDirect.texture,
            uniforms: compositor.makeFragmentUniforms(
                values: values,
                textureFrame: constantTextureFrame(SIMD2(0.375, 0.25)),
                tint: SIMD3(repeating: 1),
                dependencyBlendMode: nil,
                sourceSampling: SceneTextureSampling(texFlags: 2)
            ),
            library: imageLayerLibrary,
            device: device
        )
        var baseStore = SceneBaseImageTextureStore()
        baseStore.set(
            baseDirect.texture,
            candidate: baseDirect.candidate,
            layerID: 7
        )
        let initialBasePublication = baseStore.publications[7]
        let staticCandidatePublicationPreservesRevision =
            initialBasePublication?.candidate.identity
                == baseDirect.candidate?.identity
            && initialBasePublication?.candidate.generation
                == baseDirect.candidate?.generation
            && initialBasePublication?.candidate.purpose
                == baseDirect.candidate?.purpose
            && initialBasePublication?.candidate.content
                == baseDirect.candidate?.content
            && initialBasePublication?.candidate.uvTransform.xAxis
                == baseDirect.candidate?.uvTransform.xAxis
            && initialBasePublication?.candidate.sampling
                == baseDirect.candidate?.sampling
            && initialBasePublication?.isComplete == true
        baseStore[7] = baseCropped.texture
        let baseStoreReplacementClearsCandidate =
            baseStore.candidates[7] == nil
                && baseStore.publications[7] == nil
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
        let mismatchedPublicationSnapshot = baseStore.snapshot(
            textures: [7: baseDirect.texture],
            explicitLayerSources: [
                7: SceneTextureProviderPublication(
                    requestIdentity: .layerSource(7),
                    candidate: baseCropped.candidate!,
                    contentGeneration: 1
                )
            ]
        )
        let baseSnapshotRejectsMismatchedPublication =
            mismatchedPublicationSnapshot[7] == nil
                && mismatchedPublicationSnapshot.explicitLayerSources[7] == nil
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
        let oversizedPhysical = copy(
            first,
            physicalSize: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: first.physicalSize.height
            )
        )
        let overflowingTransform = copy(
            first,
            uvTransform: SceneTextureUVTransform(
                origin: .zero,
                xAxis: SIMD2(Float.greatestFiniteMagnitude, 0),
                yAxis: SIMD2(0, Float.greatestFiniteMagnitude)
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
        let clampBorder = copy(
            first,
            sampling: SceneTextureSampling(texFlags: 8)
        )
        let firstBinding = SceneTextureSlotBinding(
            slotIndex: 0,
            candidate: first
        )
        let lastBinding = SceneTextureSlotBinding(
            slotIndex: 7,
            candidate: first
        )
        let rotatedBinding = SceneTextureSlotBinding(
            slotIndex: 1,
            candidate: rotated
        )
        let clampBorderBinding = SceneTextureSlotBinding(
            slotIndex: 1,
            candidate: clampBorder
        )
        let firstBindingScale = firstBinding?.axisAlignedUVScale(
            expectedSlotIndex: 0,
            expectedPurpose: .mask,
            allowedPixelFormats: [.r8Unorm]
        )

        guard let originalSource = loader.sourceKey(for: url) else {
            throw HarnessError.loadFailed
        }
        let originalStatus = try fileStatus(url)
        let originalGeneration = first.generation
        Thread.sleep(forTimeInterval: 0.01)
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 3,
            payloadByte: 64
        ).write(to: url)
        try restoreTimestamps(originalStatus, at: url)
        guard let inPlaceSource = loader.sourceKey(for: url) else {
            throw HarnessError.loadFailed
        }
        let inPlaceStableMetadata =
            inPlaceSource.size == originalSource.size
                && inPlaceSource.modifiedAtBits == originalSource.modifiedAtBits
                && inPlaceSource.fileSystemID == originalSource.fileSystemID
                && inPlaceSource.fileID == originalSource.fileID
        let inPlaceStatusChangeDetected =
            inPlaceSource.statusChangedAtSeconds
                != originalSource.statusChangedAtSeconds
                || inPlaceSource.statusChangedAtNanoseconds
                    != originalSource.statusChangedAtNanoseconds
        let restoredMetadata = try candidate(loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        ))
        try rawR8Tex(
            textureWidth: 8,
            textureHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
            flags: 3,
            payloadByte: 32
        ).write(to: url, options: .atomic)
        try restoreTimestamps(originalStatus, at: url)
        guard let atomicSource = loader.sourceKey(for: url) else {
            throw HarnessError.loadFailed
        }
        let atomicReplaceMetadataPreconditions =
            atomicSource.size == inPlaceSource.size
                && atomicSource.modifiedAtBits == inPlaceSource.modifiedAtBits
                && atomicSource.fileSystemID == inPlaceSource.fileSystemID
                && atomicSource.fileID != inPlaceSource.fileID
        let atomicReplacement = try candidate(loader.loadCandidate(
            from: url,
            purpose: .mask,
            device: device
        ))
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
            "firstAuthoredFormat": first.authoredFormat?.rawValue ?? UInt32.max,
            "sameCandidateTexture": first.texture === repeated.texture,
            "sameCandidateGeneration": first.generation == repeated.generation,
            "sameResourceIdentityAcrossPurpose": first.identity == flow.identity,
            "sameGenerationAcrossPurpose": first.generation == flow.generation,
            "purposeCacheSeparated": first.texture !== flow.texture,
            "wrongPurposeRejected": wrongPurposeRejected,
            "slotBindingRangeAccepted":
                firstBinding != nil && lastBinding != nil,
            "slotBindingRangeRejected":
                SceneTextureSlotBinding(slotIndex: -1, candidate: first) == nil
                    && SceneTextureSlotBinding(
                        slotIndex: 8,
                        candidate: first
                    ) == nil,
            "slotBindingMetadataAtomic":
                firstBinding?.texture === first.texture
                    && firstBinding?.identity == first.identity
                    && firstBinding?.generation == first.generation
                    && firstBinding?.purpose == first.purpose
                    && firstBinding?.physicalMappedResolution
                        == SIMD4(8, 4, 4, 4)
                    && firstBinding?.physicalTexelSize == SIMD2(0.125, 0.25)
                    && firstBinding?.mappedTexelSize == SIMD2(0.25, 0.25)
                    && firstBinding?.mipmapLevelCount == 1,
            "slotBindingScale": [
                firstBindingScale?.x ?? -1,
                firstBindingScale?.y ?? -1,
            ],
            "slotBindingWrongSlotRejected":
                firstBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 1,
                    expectedPurpose: .mask,
                    allowedPixelFormats: [.r8Unorm]
                ) == nil,
            "slotBindingWrongPurposeRejected":
                firstBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 0,
                    expectedPurpose: .flow,
                    allowedPixelFormats: [.r8Unorm]
                ) == nil,
            "slotBindingWrongFormatRejected":
                firstBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 0,
                    expectedPurpose: .mask,
                    allowedPixelFormats: [.rg8Unorm]
                ) == nil,
            "slotBindingIdentityRequirementRejected":
                firstBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 0,
                    expectedPurpose: .mask,
                    allowedPixelFormats: [.r8Unorm],
                    requiresIdentityUV: true
                ) == nil,
            "slotBindingInvalidCandidateRejected":
                SceneTextureSlotBinding(
                    slotIndex: 0,
                    candidate: invalidPhysical
                ) == nil,
            "slotBindingOversizedPhysicalRejected":
                SceneTextureSlotBinding(
                    slotIndex: 0,
                    candidate: oversizedPhysical
                ) == nil,
            "slotBindingOverflowingTransformRejected":
                SceneTextureSlotBinding(
                    slotIndex: 0,
                    candidate: overflowingTransform
                ) == nil,
            "slotBindingPreservesRotatedUV":
                rotatedBinding?.uvTransform.xAxis
                    == rotated.uvTransform.xAxis
                    && rotatedBinding?.axisAlignedUVScale(
                        expectedSlotIndex: 1,
                        expectedPurpose: .mask,
                        allowedPixelFormats: [.r8Unorm]
                    ) == nil,
            "slotBindingClampBorderRejected":
                clampBorderBinding?.axisAlignedUVScale(
                    expectedSlotIndex: 1,
                    expectedPurpose: .mask,
                    allowedPixelFormats: [.r8Unorm]
                ) == nil,
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
            "mappedTexb3JPEGOpaque":
                mappedTexb3JPEG.content == .color(.resolved(.opaque)),
            "mappedTexb3PNGPreservesAlphaContract":
                mappedTexb3EmbeddedColor.content
                    == .color(.resolved(.premultipliedAlpha)),
            "normalizedStraightAlbedoJPEGIdentity":
                normalizedStraightAlbedoJPEG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2(repeating: 1)
                    && normalizedStraightAlbedoJPEG.texture.width == 4096
                    && normalizedStraightAlbedoJPEG.texture.height == 1,
            "normalizedStraightAlbedoPNGIdentity":
                normalizedStraightAlbedoPNG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2(repeating: 1)
                    && normalizedStraightAlbedoPNG.texture.width == 4096
                    && normalizedStraightAlbedoPNG.texture.height == 1,
            "transparentStraightAlbedoPNGRejected":
                transparentStraightAlbedoPNGRejected,
            "mipNormalizedStraightAlbedoPNG":
                mipNormalizedStraightAlbedoPNG.axisAlignedMappedUVScale(
                    expectedPurpose: .straightAlbedo
                ) == SIMD2(repeating: 1)
                    && mipNormalizedStraightAlbedoPNG.texture.width == 4096
                    && mipNormalizedStraightAlbedoPNG.texture.height == 1
                    && mipNormalizedStraightAlbedoPNG.texture.mipmapLevelCount == 1
                    && mipNormalizedStraightAlbedoPNG.content
                        == .color(.resolved(.straightAlpha)),
            "mipNormalizedStraightAlbedoPixel":
                mipNormalizedStraightAlbedoPixel,
            "paddedStraightAlbedoJPEGRejected":
                paddedStraightAlbedoJPEGRejected,
            "mislabeledTexb4StraightAlbedoPNGRejected":
                mislabeledTexb4StraightAlbedoPNGRejected,
            "mappedTexb2MipRejected": mappedTexb2MipRejected,
            "baseDirectCandidate": baseDirect.candidate != nil,
            "baseCroppedCandidate": baseCropped.candidate != nil,
            "baseNearestRepeatCandidate":
                baseNearestRepeat.candidate?.sampling.filter == .nearest
                    && baseNearestRepeat.candidate?.sampling.addressMode
                        == .repeatWrap
                    && baseNearestRepeat.candidate?.sampling.rawFlags == 1,
            "mappedNearestCandidateSample":
                mappedNearestSample.textureFrame.xAxis == SIMD2(0.5, 0)
                    && mappedNearestSample.textureFrame.yAxis == SIMD2(0, 1)
                    && mappedNearestSample.sampling.imageLayerUniformMode == 3,
            "clampBorderBaseSampleRejected": clampBorderSample == nil,
            "clampBorderBaseLoadRejected": clampBorderBaseLoadRejected,
            "unknownFlagsBaseSampleRejected": unknownFlagsSample == nil,
            "unknownSamplerBaseLoadRejected": unknownSamplerBaseLoadRejected,
            "samplerFailureDoesNotPoisonSiblingLoad":
                baseNearestRepeat.candidate != nil,
            "imageShaderUsesAuthoredRepeatSampler":
                repeatedOutside == wrappedInterior
                    && repeatedOutside != clampedOutside,
            "imageShaderUsesAuthoredNearestFilter":
                nearestBetweenTexels != linearBetweenTexels,
            "sourceFragmentUniformCarriesCandidateAtom":
                sourceFragmentUniformCarriesCandidateAtom,
            "sourceFragmentUniformCarriesAuthoredStyle":
                sourceFragmentUniformCarriesAuthoredStyle,
            "zeroAlphaPixel": zeroAlphaPixel,
            "basePaddedR8Specialized":
                basePaddedSpecialized.candidate == nil
                    && basePaddedSpecialized.message.contains("specialized authored binding"),
            "baseSpritePlayback":
                baseSpritePlayback.candidate == nil
                    && baseSpritePlayback.animation != nil,
            "baseCrossImageSpritePlayback":
                baseCrossImageSprite.candidate == nil
                    && baseCrossImageSprite.animation != nil
                    && baseCrossImageSprite.message.contains(
                        "cross-image sprite playback"
                    )
                    && baseCrossImageSprite.texture.width == 4
                    && baseCrossImageSprite.texture.height == 4
                    && crossImageTransform.origin == .zero
                    && crossImageTransform.xAxis == SIMD2(1, 0)
                    && crossImageTransform.yAxis == SIMD2(0, 1),
            "baseCrossImageFrame0Pixel": crossImageFrame0Pixel,
            "baseCrossImageFrame1Pixel": crossImageFrame1Pixel,
            "baseRotatedCrossImageSpriteFailsClosed":
                baseRotatedCrossImageSprite.candidate == nil
                    && baseRotatedCrossImageSprite.animation == nil
                    && baseRotatedCrossImageSprite.message.contains(
                        "specialized authored load (multi-image TEX)"
                    ),
            "baseBudgetLimitedCrossImageSpriteFailsClosed":
                baseBudgetLimitedCrossImageSprite.candidate == nil
                    && baseBudgetLimitedCrossImageSprite.animation == nil
                    && baseBudgetLimitedCrossImageSprite.message.contains(
                        "resident budget exceeded"
                    ),
            "basePuppetSpecialized":
                basePuppetSpecialized.candidate == nil
                    && basePuppetSpecialized.message.contains("puppet atlas"),
            "baseUnparsedSpecialized":
                baseUnparsedSpecialized.candidate == nil
                    && baseUnparsedSpecialized.message.contains("unparsed TEX"),
            "baseCandidateFailureTerminal": baseCandidateFailureTerminal,
            "baseStoreReplacementClearsCandidate":
                baseStoreReplacementClearsCandidate,
            "staticCandidatePublicationPreservesRevision":
                staticCandidatePublicationPreservesRevision,
            "baseSnapshotDropsMismatchedCandidate":
                baseSnapshotDropsMismatchedCandidate,
            "baseSnapshotRejectsMismatchedPublication":
                baseSnapshotRejectsMismatchedPublication,
            "generationChangedAfterRewrite": originalGeneration != refreshed.generation,
            "textureChangedAfterRewrite": first.texture !== refreshed.texture,
            "generationChangedWithRestoredSizeAndMTime":
                originalGeneration != restoredMetadata.generation,
            "textureChangedWithRestoredSizeAndMTime":
                first.texture !== restoredMetadata.texture,
            "inPlaceStableMetadata": inPlaceStableMetadata,
            "inPlaceStatusChangeDetected": inPlaceStatusChangeDetected,
            "atomicReplaceMetadataPreconditions":
                atomicReplaceMetadataPreconditions,
            "generationChangedAfterAtomicReplace":
                restoredMetadata.generation != atomicReplacement.generation,
            "textureChangedAfterAtomicReplace":
                restoredMetadata.texture !== atomicReplacement.texture,
            "missingSourceKeyUnavailable": missingSourceKeyUnavailable,
            "missingMetadataRejected": missingMetadataRejected,
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
        uvTransform: SceneTextureUVTransform? = nil,
        sampling: SceneTextureSampling? = nil
    ) -> SceneTextureCandidate {
        SceneTextureCandidate(
            texture: source.texture,
            identity: source.identity,
            generation: source.generation,
            purpose: source.purpose,
            content: source.content,
            physicalSize: physicalSize ?? source.physicalSize,
            mappedSize: mappedSize ?? source.mappedSize,
            uvTransform: uvTransform ?? source.uvTransform,
            sampling: sampling ?? source.sampling,
            authoredFormat: source.authoredFormat
        )
    }

    static func filePath(_ identity: SceneTextureResourceIdentity) -> String? {
        guard case .file(let path) = identity else { return nil }
        return path
    }

    static func generationByteCount(
        _ generation: SceneTextureResourceGeneration
    ) -> UInt64? {
        guard case .file(let byteCount, _, _) = generation else { return nil }
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
        mipHeight: UInt32? = nil,
        payloadByte: UInt8 = 127
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
            repeating: payloadByte,
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

    static func crossImageSpriteBC3Tex(
        rotatedSecondFrame: Bool = false
    ) -> Data {
        func block(
            alpha: UInt8,
            colorLow: UInt8,
            colorHigh: UInt8
        ) -> Data {
            Data([
                alpha, alpha, 0, 0, 0, 0, 0, 0,
                colorLow, colorHigh, 0, 0, 0, 0, 0, 0,
            ])
        }

        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(4, to: &data)
        append(4, to: &data)
        append(4, to: &data)
        append(4, to: &data)
        append(4, to: &data)
        append(4, to: &data)
        append(0, to: &data)
        data.append(Data("TEXB0002\0".utf8))
        append(2, to: &data)
        for payload in [
            block(alpha: 128, colorLow: 0x00, colorHigh: 0xF8),
            block(alpha: 64, colorLow: 0xE0, colorHigh: 0x07),
        ] {
            append(1, to: &data)
            append(4, to: &data)
            append(4, to: &data)
            append(0, to: &data)
            append(0, to: &data)
            append(UInt32(payload.count), to: &data)
            data.append(payload)
        }
        data.append(Data("TEXS0002\0".utf8))
        append(2, to: &data)
        appendSpriteFrame(
            imageIndex: 0,
            duration: 0.035,
            coordinates: [0, 0, 4, 0, 0, 4],
            to: &data
        )
        appendSpriteFrame(
            imageIndex: 1,
            duration: 0.035,
            coordinates: rotatedSecondFrame
                ? [0, 0, 0, 4, 4, 0]
                : [0, 0, 4, 0, 0, 4],
            to: &data
        )
        return data
    }

    static func appendSpriteFrame(
        imageIndex: UInt32,
        duration: Float,
        coordinates: [Float],
        to data: inout Data
    ) {
        append(imageIndex, to: &data)
        appendFloat(duration, to: &data)
        for coordinate in coordinates {
            appendFloat(coordinate, to: &data)
        }
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
        imageHeight: UInt32,
        flags: UInt32 = 2
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
            payload: payload,
            flags: flags
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
        mipMetadataEntryCount: UInt32 = 0,
        mipWidth: UInt32? = nil,
        mipHeight: UInt32? = nil,
        additionalMips: [(UInt32, UInt32, Data)] = [],
        flags: UInt32 = 2
    ) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        append(0, to: &data)
        append(flags, to: &data)
        append(textureWidth, to: &data)
        append(textureHeight, to: &data)
        append(imageWidth, to: &data)
        append(imageHeight, to: &data)
        append(0, to: &data)
        data.append(Data("\(containerVersion)\0".utf8))
        append(1, to: &data)
        if containerVersion == "TEXB0003" {
            append(freeImageFormat, to: &data)
        } else if containerVersion == "TEXB0004" {
            append(freeImageFormat, to: &data)
            append(mipMetadataEntryCount, to: &data)
        }
        let mips = [
            (mipWidth ?? textureWidth, mipHeight ?? textureHeight, payload),
        ] + additionalMips
        append(UInt32(mips.count), to: &data)
        for (width, height, mipPayload) in mips {
            for entry in 0..<mipMetadataEntryCount {
                append(0, to: &data)
                append(0, to: &data)
                data.append(Data("metadata-\(entry)\0".utf8))
                append(0, to: &data)
            }
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

    static func opaquePNGData(width: Int, height: Int) throws -> Data {
        let pixels = Data(repeating: 127, count: width * height * 3)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 24,
                  bytesPerRow: width * 3,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.none.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw HarnessError.imageCreationFailed
        }
        return try encodeImage(image, type: "public.png" as CFString)
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
              ) else {
            throw HarnessError.imageCreationFailed
        }
        return try encodeImage(image, type: type)
    }

    static func encodeImage(_ image: CGImage, type: CFString) throws -> Data {
        guard let data = CFDataCreateMutable(nil, 0),
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

    static func fileStatus(_ url: URL) throws -> Darwin.stat {
        var status = Darwin.stat()
        guard url.path.withCString({ Darwin.lstat($0, &status) }) == 0 else {
            throw HarnessError.metadataFailed
        }
        return status
    }

    static func restoreTimestamps(
        _ status: Darwin.stat,
        at url: URL
    ) throws {
        let timestamps = [status.st_atimespec, status.st_mtimespec]
        let result = timestamps.withUnsafeBufferPointer { buffer in
            url.path.withCString {
                Darwin.utimensat(AT_FDCWD, $0, buffer.baseAddress, 0)
            }
        }
        guard result == 0 else { throw HarnessError.metadataFailed }
    }

    static func readFirstPixel(
        texture: MTLTexture,
        device: MTLDevice
    ) throws -> [Int] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let staging = device.makeTexture(descriptor: descriptor),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw HarnessError.loadFailed
        }
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(
                width: texture.width,
                height: texture.height,
                depth: 1
            ),
            to: staging,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw HarnessError.loadFailed
        }
        var bytes = [UInt8](repeating: 0, count: 4)
        staging.getBytes(
            &bytes,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )
        return bytes.map(Int.init)
    }

    static func renderSample(
        texture: MTLTexture,
        uniforms: SceneLayerFragmentUniforms,
        library: MTLLibrary,
        device: MTLDevice
    ) throws -> [Int] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: descriptor),
              let pipeline = SceneImageLayerPipeline(
                  device: device,
                  pixelFormat: .rgba8Unorm,
                  library: library
              ),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw HarnessError.loadFailed
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: pass
        ) else { throw HarnessError.loadFailed }
        pipeline.bind(encoder: encoder)
        var mvp = matrix_identity_float4x4
        mvp.columns.0.x = 2
        mvp.columns.1.y = 2
        pipeline.drawLayer(
            texture: texture,
            mvp: mvp,
            uniforms: uniforms,
            encoder: encoder
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw HarnessError.loadFailed
        }
        return try readFirstPixel(texture: target, device: device)
    }

    static func constantTextureFrame(
        _ uv: SIMD2<Float>
    ) -> SceneTextureUVTransform {
        .init(origin: uv, xAxis: .zero, yAxis: .zero)
    }

    enum HarnessError: Error {
        case loadFailed
        case imageCreationFailed
        case metadataFailed
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
                    "MetalPerformanceShaders",
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
                [str(binary), str(IMAGE_LAYER_METAL_SOURCE)],
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
                "baseBudgetLimitedCrossImageSpriteFailsClosed": True,
                "baseCandidateFailureTerminal": True,
                "baseCrossImageFrame0Pixel": [128, 0, 0, 128],
                "baseCrossImageFrame1Pixel": [0, 64, 0, 64],
                "baseCrossImageSpritePlayback": True,
                "baseCroppedCandidate": True,
                "baseDirectCandidate": True,
                "baseNearestRepeatCandidate": True,
                "basePaddedR8Specialized": True,
                "basePuppetSpecialized": True,
                "baseRotatedCrossImageSpriteFailsClosed": True,
                "baseSpritePlayback": True,
                "baseSnapshotDropsMismatchedCandidate": True,
                "baseSnapshotRejectsMismatchedPublication": True,
                "baseStoreReplacementClearsCandidate": True,
                "staticCandidatePublicationPreservesRevision": True,
                "baseUnparsedSpecialized": True,
                "croppedColorMapped": [4, 4],
                "croppedColorPhysical": [4, 4],
                "croppedColorScale": [1, 1],
                "decodedMismatchTexb3Rejected": True,
                "diagnosticCarriesContract": True,
                "emptySpriteRejected": True,
                "firstMapped": [4, 4],
                "firstPhysical": [8, 4],
                "firstPixelFormat": 10,
                "firstAuthoredFormat": 9,
                "firstSampling": ["nearest", "clampToEdge"],
                "firstScale": [0.5, 1],
                "generationChangedAfterRewrite": True,
                "generationChangedWithRestoredSizeAndMTime": True,
                "generationChangedAfterAtomicReplace": True,
                "generationIsFile": True,
                "identityIsCanonicalFile": True,
                "imageShaderUsesAuthoredNearestFilter": True,
                "imageShaderUsesAuthoredRepeatSampler": True,
                "inPlaceStableMetadata": True,
                "inPlaceStatusChangeDetected": True,
                "invalidMappedRejected": True,
                "invalidPhysicalRejected": True,
                "mismatchedPhysicalRejected": True,
                "missingMetadataRejected": True,
                "missingSourceKeyUnavailable": True,
                "mappedEmbeddedColorIdentity": True,
                "mappedEmbeddedNormalRejected": True,
                "mappedNearestCandidateSample": True,
                "freeFormatMismatchTexb3Rejected": True,
                "lowerMipMismatchTexb3Rejected": True,
                "malformedTexb3EmbeddedRejected": True,
                "mappedTexb2MipRejected": True,
                "mappedTexb3EmbeddedColorIdentity": True,
                "mappedTexb3EmbeddedNormalIdentity": True,
                "mappedTexb3JPEGIdentity": True,
                "mappedTexb3JPEGOpaque": True,
                "mappedTexb3PNGPreservesAlphaContract": True,
                "normalizedStraightAlbedoJPEGIdentity": True,
                "normalizedStraightAlbedoPNGIdentity": True,
                "paddedStraightAlbedoJPEGRejected": True,
                "mislabeledTexb4StraightAlbedoPNGRejected": True,
                "mipNormalizedStraightAlbedoPNG": True,
                "mipNormalizedStraightAlbedoPixel": [127, 127, 127, 127],
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
                "slotBindingClampBorderRejected": True,
                "slotBindingIdentityRequirementRejected": True,
                "slotBindingInvalidCandidateRejected": True,
                "slotBindingMetadataAtomic": True,
                "slotBindingOverflowingTransformRejected": True,
                "slotBindingOversizedPhysicalRejected": True,
                "slotBindingPreservesRotatedUV": True,
                "slotBindingRangeAccepted": True,
                "slotBindingRangeRejected": True,
                "slotBindingScale": [0.5, 1],
                "slotBindingWrongFormatRejected": True,
                "slotBindingWrongPurposeRejected": True,
                "slotBindingWrongSlotRejected": True,
                "sourceFragmentUniformCarriesCandidateAtom": True,
                "sourceFragmentUniformCarriesAuthoredStyle": True,
                "textureChangedAfterRewrite": True,
                "textureChangedAfterAtomicReplace": True,
                "textureChangedWithRestoredSizeAndMTime": True,
                "transparentStraightAlbedoPNGRejected": True,
                "atomicReplaceMetadataPreconditions": True,
                "clampBorderBaseSampleRejected": True,
                "clampBorderBaseLoadRejected": True,
                "translatedRejected": True,
                "unparsedFallbackRejected": True,
                "unknownFlagsBaseSampleRejected": True,
                "unknownSamplerBaseLoadRejected": True,
                "zeroAlphaPixel": [0, 0, 0, 255],
                "samplerFailureDoesNotPoisonSiblingLoad": True,
                "wrongPurposeRejected": True,
                "wrongOutputRejected": True,
                "zeroMappedRejected": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
