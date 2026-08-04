#!/usr/bin/env python3

"""Metal tests for purpose-aware BC upload and static sprite fallback."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
HOST_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost.swift"
HOST_LAUNCH_SOURCE = SCENE_ROOT / "Runtime/SceneDesktopWallpaperHost+Launch.swift"
METAL_VIEW_SOURCE = SCENE_ROOT / "Rendering/SceneMetalView.swift"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneMultiImageSpriteResidentBudget.swift",
    SCENE_ROOT / "Runtime/SceneTextureAnimationPlaybackPlan.swift",
    SCENE_ROOT / "Resources/SceneTextureAnimationPlaybackClock.swift",
    SCENE_ROOT / "Resources/SceneMultiImageSpritePlayback.swift",
    SCENE_ROOT / "Resources/SceneTextureUVTransform.swift",
    SCENE_ROOT / "Rendering/SceneMetalPipeline.swift",
    SCENE_ROOT / "Rendering/SceneSpriteAnimation.swift",
]

HARNESS = r'''
import Foundation
import Metal

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

    func cancel() {
        let actions = rollbacks
        rollbacks.removeAll()
        for action in actions.reversed() { action() }
    }
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noDevice }
        let width = 4096
        let height = 4097
        let block = [UInt8](
            [128, 128, 0, 0, 0, 0, 0, 0]
            + [0x00, 0xF8, 0, 0, 0, 0, 0, 0]
        )
        let blockCount = ((width + 3) / 4) * ((height + 3) / 4)
        var data = Data(count: blockCount * block.count)
        data.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for index in 0 ..< blockCount {
                for offset in block.indices {
                    bytes[index * block.count + offset] = block[offset]
                }
            }
        }
        let mip = SceneTexContainer.Mip(width: width, height: height, data: data)
        let frame0 = SceneTexContainer.SpriteFrame(
            imageIndex: 0,
            duration: 0.035,
            origin: .zero,
            xAxis: SIMD2(4.0 / Float(width), 0),
            yAxis: SIMD2(0, 4.0 / Float(height))
        )
        let frame1 = SceneTexContainer.SpriteFrame(
            imageIndex: 1,
            duration: 0.035,
            origin: .zero,
            xAxis: frame0.xAxis,
            yAxis: frame0.yAxis
        )
        let container = makeContainer(mip: mip, frames: [frame0, frame1])
        let outcome = SceneCompressedTextureUploader.upload(
            container: container,
            pixelFormat: .bc3_rgba,
            purpose: .premultipliedColor,
            device: device
        )
        var result: [String: Any] = [:]
        if case let .loaded(texture) = outcome {
            result["loaded"] = true
            result["width"] = texture.width
            result["height"] = texture.height
            result["pixelFormat"] = texture.pixelFormat.rawValue
            result["firstPixel"] = try readFirstPixel(texture: texture, device: device)
        } else {
            result["loaded"] = false
        }

        let rotated = SceneTexContainer.SpriteFrame(
            imageIndex: 0,
            duration: 0.035,
            origin: .zero,
            xAxis: SIMD2(0, 4.0 / Float(height)),
            yAxis: SIMD2(4.0 / Float(width), 0)
        )
        let rejected = SceneCompressedTextureUploader.upload(
            container: makeContainer(mip: mip, frames: [rotated, frame1]),
            pixelFormat: .bc3_rgba,
            purpose: .premultipliedColor,
            device: device
        )
        if case let .decodeFailed(message) = rejected {
            result["rotatedFailure"] = message
        }

        let mipmapped = SceneCompressedTextureUploader.upload(
            container: makeMipmappedContainer(),
            pixelFormat: .bc1_rgba,
            purpose: .premultipliedColor,
            device: device
        )
        if case let .loaded(texture) = mipmapped {
            result["mipmapLevelCount"] = texture.mipmapLevelCount
            result["secondMipPixel"] = try readFirstPixel(
                texture: texture,
                level: 1,
                device: device
            )
        }
        let parsed = try SceneTexContainerReader().read(data: makeTwoImageTex())
        result["parsedImageCount"] = parsed.images.count
        result["parsedMipCounts"] = parsed.images.map { $0.mips.count }
        result["parsedFirstBytes"] = parsed.images.map { Int($0.mips[0].data[0]) }

        let animated = makeAnimatedColorContainer()
        let source = SceneTextureLoader.SourceKey(
            path: "/fixture/cross-image-sprite.tex",
            size: 32,
            modifiedAtBits: 1,
            fileSystemID: 2,
            fileID: 3,
            statusChangedAtSeconds: 4,
            statusChangedAtNanoseconds: 5
        )
        let animationLoader = SceneMultiImageSpriteTextureLoader()
        if case let .loaded(playback) = animationLoader.playback(
            source: source,
            container: animated,
            device: device,
            sourceIsCurrent: { true }
        ) {
            result["crossImageAnimationAccepted"] = true
            let queue = device.makeCommandQueue()!
            do {
                let abandonedBuffer = queue.makeCommandBuffer()!
                let abandonedTransaction = SceneSourceUpdateTransaction()
                playback.encode(
                    sceneTime: 0,
                    wallDate: Date(timeIntervalSince1970: 0),
                    commandBuffer: abandonedBuffer,
                    transaction: abandonedTransaction
                )
                abandonedTransaction.cancel()
            }
            let firstBuffer = queue.makeCommandBuffer()!
            let firstTransaction = SceneSourceUpdateTransaction()
            playback.encode(
                sceneTime: 0,
                wallDate: Date(timeIntervalSince1970: 0),
                commandBuffer: firstBuffer,
                transaction: firstTransaction
            )
            firstBuffer.commit()
            firstTransaction.commit()
            firstBuffer.waitUntilCompleted()
            result["crossImageFrame0Pixel"] = try readFirstPixel(
                texture: playback.texture,
                device: device
            )
            let secondBuffer = queue.makeCommandBuffer()!
            let secondTransaction = SceneSourceUpdateTransaction()
            playback.encode(
                sceneTime: 0.04,
                wallDate: Date(timeIntervalSince1970: 0),
                commandBuffer: secondBuffer,
                transaction: secondTransaction
            )
            secondBuffer.commit()
            secondTransaction.commit()
            secondBuffer.waitUntilCompleted()
            result["crossImageFrame1Pixel"] = try readFirstPixel(
                texture: playback.texture,
                device: device
            )
        } else {
            result["crossImageAnimationAccepted"] = false
        }

        let submissionTracker = SceneSpriteFrameSubmissionTracker()
        let firstSubmission = submissionTracker.begin(frameIndex: 0)
        result["sameFrameSubmissionDeduplicated"] =
            firstSubmission != nil
                && submissionTracker.begin(frameIndex: 0) == nil
        if let firstSubmission {
            submissionTracker.complete(firstSubmission, succeeded: false)
            submissionTracker.cancel(firstSubmission)
        }
        let retriedSubmission = submissionTracker.begin(frameIndex: 0)
        result["failedSubmissionCanRetry"] = retriedSubmission != nil
        let newerSubmission = submissionTracker.begin(frameIndex: 1)
        if let retriedSubmission {
            submissionTracker.complete(retriedSubmission, succeeded: false)
        }
        result["staleFailureKeepsNewerSubmission"] =
            newerSubmission != nil
                && submissionTracker.begin(frameIndex: 1) == nil
        if let newerSubmission {
            submissionTracker.cancel(newerSubmission)
        }
        result["cancelledSubmissionCanRetry"] =
            submissionTracker.begin(frameIndex: 1) != nil

        guard let residentCosts = SceneMultiImageSpriteTextureCost.estimate(
            container: animated,
            pixelFormat: .bc3_rgba,
            outputWidth: 4,
            outputHeight: 4,
            device: device
        ) else {
            throw HarnessError.load
        }
        result["usesDeviceAllocationCost"] =
            residentCosts.source + residentCosts.destination > 96
        let boundedLoader = SceneMultiImageSpriteTextureLoader(
            residentByteBudget: residentCosts.source
                + residentCosts.destination * 2
        )
        var boundedFirst: SceneMultiImageSpritePlayback? = try playback(
            boundedLoader.playback(
            source: source,
            container: animated,
            device: device,
            sourceIsCurrent: { true }
        ))
        let boundedSecond = try playback(boundedLoader.playback(
            source: source,
            container: animated,
            device: device,
            sourceIsCurrent: { true }
        ))
        let boundedThird = boundedLoader.playback(
            source: source,
            container: animated,
            device: device,
            sourceIsCurrent: { true }
        )
        if case let .unsupported(detail) = boundedThird {
            result["residentBudgetDeduplicatesSource"] =
                boundedFirst?.texture !== boundedSecond.texture
                    && detail.contains("resident budget exceeded")
        } else {
            result["residentBudgetDeduplicatesSource"] = false
        }
        boundedFirst = nil
        if case .loaded = boundedLoader.playback(
            source: source,
            container: animated,
            device: device,
            sourceIsCurrent: { true }
        ) {
            result["releasedDestinationRestoresBudget"] = true
        } else {
            result["releasedDestinationRestoresBudget"] = false
        }

        let revisionLoader = SceneMultiImageSpriteTextureLoader(
            residentByteBudget: residentCosts.source
                + residentCosts.destination
        )
        var revisionChecks = 0
        let staleRevision = revisionLoader.playback(
            source: source,
            container: animated,
            device: device,
            sourceIsCurrent: {
                revisionChecks += 1
                return revisionChecks == 1
            }
        )
        let stableRevision = revisionLoader.playback(
            source: source,
            container: animated,
            device: device,
            sourceIsCurrent: { true }
        )
        if case let .unsupported(detail) = staleRevision,
           case .loaded = stableRevision {
            result["revisionChangeFailsWithoutConsumingBudget"] =
                detail.contains("file changed while loading")
        } else {
            result["revisionChangeFailsWithoutConsumingBudget"] = false
        }

        result["bc1AnimationAccepted"] = accepts(
            makeAnimatedColorContainer(format: 7),
            sourcePath: "/fixture/cross-image-bc1.tex",
            device: device
        )
        result["bc2AnimationAccepted"] = accepts(
            makeAnimatedColorContainer(format: 6),
            sourcePath: "/fixture/cross-image-bc2.tex",
            device: device
        )
        let defaultFrames = animated.spriteFrames
        let fractionalFrame = SceneTexContainer.SpriteFrame(
            imageIndex: 0,
            duration: 0.035,
            origin: SIMD2(0.125, 0),
            xAxis: SIMD2(0.5, 0),
            yAxis: SIMD2(0, 1)
        )
        let outOfRangeFrame = SceneTexContainer.SpriteFrame(
            imageIndex: 2,
            duration: 0.035,
            origin: .zero,
            xAxis: SIMD2(1, 0),
            yAxis: SIMD2(0, 1)
        )
        let nonFiniteFrame = SceneTexContainer.SpriteFrame(
            imageIndex: 0,
            duration: 0.035,
            origin: SIMD2(.nan, 0),
            xAxis: SIMD2(1, 0),
            yAxis: SIMD2(0, 1)
        )
        result["fractionalFrameRejected"] = rejectsAdmission(
            makeAnimatedColorContainer(
                frames: [fractionalFrame, defaultFrames[1]]
            ),
            device: device
        )
        result["outOfRangeImageRejected"] = rejectsAdmission(
            makeAnimatedColorContainer(
                frames: [outOfRangeFrame, defaultFrames[1]]
            ),
            device: device
        )
        result["nonFiniteFrameRejected"] = rejectsAdmission(
            makeAnimatedColorContainer(
                frames: [nonFiniteFrame, defaultFrames[1]]
            ),
            device: device
        )
        result["seventeenImagesRejected"] = rejectsAdmission(
            makeAnimatedColorContainer(
                images: Array(repeating: animated.images[0], count: 17)
            ),
            device: device
        )
        let differentSizeImage = SceneTexContainer.Image(mips: [
            .init(width: 8, height: 4, data: Data(repeating: 0, count: 32))
        ])
        result["differentFrameSizesRejected"] = rejectsAdmission(
            makeAnimatedColorContainer(
                images: [animated.images[0], differentSizeImage]
            ),
            device: device
        )
        let oversizedSourceImage = SceneTexContainer.Image(mips: [
            .init(width: 16_385, height: 4, data: Data())
        ])
        result["oversizedSourceRejected"] = rejectsAdmission(
            makeAnimatedColorContainer(
                images: [oversizedSourceImage, oversizedSourceImage]
            ),
            device: device
        )
        let oversizedOutputImage = SceneTexContainer.Image(mips: [
            .init(width: 8_192, height: 4, data: Data())
        ])
        result["oversizedOutputRejected"] = rejectsAdmission(
            makeAnimatedColorContainer(
                images: [oversizedOutputImage, oversizedOutputImage]
            ),
            device: device
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-bc-purpose-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let textureURL = directory.appendingPathComponent("independent-green-alpha.tex")
        try makeIndependentGreenAlphaTex().write(to: textureURL)
        let loader = SceneTextureLoader()
        let color1 = try loaded(loader.load(from: textureURL, device: device))
        let color2 = try loaded(loader.load(from: textureURL, device: device))
        let data1 = try loaded(loader.loadDataTexture(from: textureURL, device: device))
        let data2 = try loaded(loader.loadDataTexture(from: textureURL, device: device))
        result["colorPurposePixel"] = try readFirstPixel(texture: color1, device: device)
        result["dataPurposePixel"] = try readFirstPixel(texture: data1, device: device)
        result["sameColorCacheIdentity"] = color1 === color2
        result["sameDataCacheIdentity"] = data1 === data2
        result["differentPurposeIdentity"] = color1 !== data1
        let semanticPurposes: [(String, SceneTextureLoadPurpose)] = [
            ("straightAlbedo", .straightAlbedo),
            ("preservedChannels", .preservedChannels),
            ("mask", .mask),
            ("noise", .noise),
            ("flow", .flow),
            ("phase", .phase),
            ("normal", .normal),
        ]
        var semanticTextures: [MTLTexture] = []
        var semanticPixels: [String: [UInt8]] = [:]
        var semanticCacheStable = true
        for (label, purpose) in semanticPurposes {
            let first = try loaded(loader.load(
                from: textureURL,
                purpose: purpose,
                device: device
            ))
            let second = try loaded(loader.load(
                from: textureURL,
                purpose: purpose,
                device: device
            ))
            semanticTextures.append(first)
            semanticPixels[label] = try readFirstPixel(texture: first, device: device)
            semanticCacheStable = semanticCacheStable && first === second
        }
        var semanticIdentitiesDistinct = true
        for left in semanticTextures.indices {
            for right in semanticTextures.indices where left < right {
                semanticIdentitiesDistinct =
                    semanticIdentitiesDistinct && semanticTextures[left] !== semanticTextures[right]
            }
        }
        result["semanticPurposePixels"] = semanticPixels
        result["semanticPurposeCacheStable"] = semanticCacheStable
        result["semanticPurposeIdentitiesDistinct"] = semanticIdentitiesDistinct

        let dataFirstLoader = SceneTextureLoader()
        let dataFirst = try loaded(dataFirstLoader.loadDataTexture(from: textureURL, device: device))
        let colorSecond = try loaded(dataFirstLoader.load(from: textureURL, device: device))
        result["dataFirstPurposePixel"] = try readFirstPixel(texture: dataFirst, device: device)
        result["colorSecondPurposePixel"] = try readFirstPixel(texture: colorSecond, device: device)

        let paddedURL = directory.appendingPathComponent("padded-independent-green-alpha.tex")
        try makeIndependentGreenAlphaTex(textureWidth: 8, imageWidth: 4).write(to: paddedURL)
        let paddedColor = try loaded(loader.load(from: paddedURL, device: device))
        let paddedData = try loaded(loader.loadDataTexture(from: paddedURL, device: device))
        result["paddedColorSize"] = [paddedColor.width, paddedColor.height]
        result["paddedDataSize"] = [paddedData.width, paddedData.height]
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: result)
        )
    }

    static func makeContainer(
        mip: SceneTexContainer.Mip,
        frames: [SceneTexContainer.SpriteFrame]
    ) -> SceneTexContainer {
        SceneTexContainer(
            format: 4,
            flags: 4,
            textureWidth: mip.width,
            textureHeight: mip.height,
            imageWidth: mip.width,
            imageHeight: mip.height,
            containerVersion: .texb0002,
            freeImageFormat: -1,
            isVideoMp4: false,
            images: [.init(mips: [mip]), .init(mips: [mip])],
            spriteFrames: frames
        )
    }

    static func makeMipmappedContainer() -> SceneTexContainer {
        let redBlock = Data([0x00, 0xF8, 0, 0, 0, 0, 0, 0])
        let greenBlock = Data([0xE0, 0x07, 0, 0, 0, 0, 0, 0])
        return SceneTexContainer(
            format: 7,
            flags: 2,
            textureWidth: 8,
            textureHeight: 8,
            imageWidth: 8,
            imageHeight: 8,
            containerVersion: .texb0002,
            freeImageFormat: -1,
            isVideoMp4: false,
            images: [.init(mips: [
                .init(width: 8, height: 8, data: redBlock + redBlock + redBlock + redBlock),
                .init(width: 4, height: 4, data: greenBlock)
            ])],
            spriteFrames: []
        )
    }

    static func makeAnimatedColorContainer(
        format: UInt32 = 4,
        images authoredImages: [SceneTexContainer.Image]? = nil,
        frames authoredFrames: [SceneTexContainer.SpriteFrame]? = nil
    ) -> SceneTexContainer {
        func block(
            alpha: UInt8,
            colorLow: UInt8,
            colorHigh: UInt8
        ) -> Data {
            let bc3 = Data([
                alpha, alpha, 0, 0, 0, 0, 0, 0,
                colorLow, colorHigh, 0, 0, 0, 0, 0, 0,
            ])
            return format == 7 ? bc3.suffix(8) : bc3
        }
        let red = SceneTexContainer.Mip(
            width: 4, height: 4, data: block(alpha: 128, colorLow: 0x00, colorHigh: 0xF8)
        )
        let green = SceneTexContainer.Mip(
            width: 4, height: 4, data: block(alpha: 64, colorLow: 0xE0, colorHigh: 0x07)
        )
        let frame0 = SceneTexContainer.SpriteFrame(
            imageIndex: 0, duration: 0.035, origin: .zero,
            xAxis: SIMD2(1, 0), yAxis: SIMD2(0, 1)
        )
        let frame1 = SceneTexContainer.SpriteFrame(
            imageIndex: 1, duration: 0.035, origin: .zero,
            xAxis: SIMD2(1, 0), yAxis: SIMD2(0, 1)
        )
        let images = authoredImages ?? [
            .init(mips: [red]),
            .init(mips: [green]),
        ]
        let frames = authoredFrames ?? [frame0, frame1]
        return SceneTexContainer(
            format: format, flags: 4, textureWidth: 4, textureHeight: 4,
            imageWidth: 4, imageHeight: 4, containerVersion: .texb0002,
            freeImageFormat: -1, isVideoMp4: false,
            images: images,
            spriteFrames: frames
        )
    }

    static func accepts(
        _ container: SceneTexContainer,
        sourcePath: String,
        device: MTLDevice
    ) -> Bool {
        let source = SceneTextureLoader.SourceKey(
            path: sourcePath,
            size: 32,
            modifiedAtBits: 1,
            fileSystemID: 2,
            fileID: 3,
            statusChangedAtSeconds: 4,
            statusChangedAtNanoseconds: 5
        )
        if case .loaded = SceneMultiImageSpriteTextureLoader().playback(
            source: source,
            container: container,
            device: device,
            sourceIsCurrent: { true }
        ) {
            return true
        }
        return false
    }

    static func rejectsAdmission(
        _ container: SceneTexContainer,
        device: MTLDevice
    ) -> Bool {
        let source = SceneTextureLoader.SourceKey(
            path: "/fixture/rejected-\(UUID().uuidString).tex",
            size: 32,
            modifiedAtBits: 1,
            fileSystemID: 2,
            fileID: 3,
            statusChangedAtSeconds: 4,
            statusChangedAtNanoseconds: 5
        )
        if case let .unsupported(detail) =
            SceneMultiImageSpriteTextureLoader().playback(
                source: source,
                container: container,
                device: device,
                sourceIsCurrent: { true }
            ) {
            return detail.contains("unsupported image, codec, or frame layout")
        }
        return false
    }

    static func makeTwoImageTex() -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(7)
        append(0)
        append(4)
        append(4)
        append(4)
        append(4)
        append(0)
        data.append(Data("TEXB0002\0".utf8))
        append(2)
        for marker: UInt8 in [17, 29] {
            append(1)
            append(4)
            append(4)
            append(0)
            append(0)
            append(8)
            data.append(Data(repeating: marker, count: 8))
        }
        return data
    }

    static func makeIndependentGreenAlphaTex(
        textureWidth: UInt32 = 4,
        imageWidth: UInt32 = 4
    ) -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(4)
        append(0)
        append(textureWidth)
        append(4)
        append(imageWidth)
        append(4)
        append(0)
        data.append(Data("TEXB0002\0".utf8))
        append(1)
        append(1)
        append(textureWidth)
        append(4)
        append(0)
        append(0)
        let block = Data([
            64, 64, 0, 0, 0, 0, 0, 0,
            0xE0, 0x07, 0xE0, 0x07, 0, 0, 0, 0,
        ])
        let blockCount = Int((textureWidth + 3) / 4)
        append(UInt32(block.count * blockCount))
        for _ in 0..<blockCount { data.append(block) }
        return data
    }

    static func loaded(_ outcome: SceneTextureLoadOutcome) throws -> MTLTexture {
        guard case let .loaded(texture) = outcome else { throw HarnessError.load }
        return texture
    }

    static func playback(
        _ outcome: SceneMultiImageSpriteTextureLoader.Outcome
    ) throws -> SceneMultiImageSpritePlayback {
        guard case let .loaded(playback) = outcome else { throw HarnessError.load }
        return playback
    }

    static func readFirstPixel(
        texture: MTLTexture,
        level: Int = 0,
        device: MTLDevice
    ) throws -> [UInt8] {
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let buffer = device.makeBuffer(length: 4) else { throw HarnessError.noDevice }
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: level,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: 1, height: 1, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: 4,
            destinationBytesPerImage: 4
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.gpu }
        let pointer = buffer.contents().bindMemory(to: UInt8.self, capacity: 4)
        return Array(UnsafeBufferPointer(start: pointer, count: 4))
    }

    enum HarnessError: Error { case noDevice, gpu, load }
}
'''


class SceneBCTextureUploaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        harness = tmp / "harness.swift"
        harness.write_text(HARNESS)
        binary = tmp / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")
        completed = subprocess.run([str(binary)], capture_output=True, text=True)
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_over_budget_multi_image_bc3_uses_premultiplied_static_first_frame(self) -> None:
        self.assertTrue(self.result["loaded"])
        self.assertEqual((self.result["width"], self.result["height"]), (4, 4))
        red, green, blue, alpha = self.result["firstPixel"]
        self.assertLessEqual(abs(red - 128), 1)
        self.assertEqual((green, blue), (0, 0))
        self.assertLessEqual(abs(alpha - 128), 1)

    def test_rotated_cross_image_first_frame_fails_closed(self) -> None:
        self.assertIn("static first-frame region", self.result["rotatedFailure"])

    def test_single_image_bc_upload_preserves_authored_mip_chain(self) -> None:
        self.assertEqual(self.result["mipmapLevelCount"], 2)
        red, green, blue, alpha = self.result["secondMipPixel"]
        self.assertEqual((red, green, blue, alpha), (0, 255, 0, 255))

    def test_tex_reader_preserves_every_image_payload(self) -> None:
        self.assertEqual(self.result["parsedImageCount"], 2)
        self.assertEqual(self.result["parsedMipCounts"], [1, 1])
        self.assertEqual(self.result["parsedFirstBytes"], [17, 29])

    def test_cross_image_sprite_animation_selects_and_premultiplies_each_image(self) -> None:
        self.assertTrue(self.result["crossImageAnimationAccepted"])
        self.assertEqual(self.result["crossImageFrame0Pixel"], [128, 0, 0, 128])
        self.assertEqual(self.result["crossImageFrame1Pixel"], [0, 64, 0, 64])

    def test_failed_frame_submission_can_retry_without_overriding_newer_work(self) -> None:
        self.assertTrue(self.result["sameFrameSubmissionDeduplicated"])
        self.assertTrue(self.result["failedSubmissionCanRetry"])
        self.assertTrue(self.result["staleFailureKeepsNewerSubmission"])
        self.assertTrue(self.result["cancelledSubmissionCanRetry"])

    def test_resident_budget_shares_sources_but_counts_each_output(self) -> None:
        self.assertTrue(self.result["residentBudgetDeduplicatesSource"])
        self.assertTrue(self.result["releasedDestinationRestoresBudget"])
        self.assertTrue(self.result["usesDeviceAllocationCost"])

    def test_revision_change_rejects_publication_without_leaking_budget(self) -> None:
        self.assertTrue(self.result["revisionChangeFailsWithoutConsumingBudget"])

    def test_bounded_admission_covers_supported_codecs_and_layout_limits(self) -> None:
        self.assertTrue(self.result["bc1AnimationAccepted"])
        self.assertTrue(self.result["bc2AnimationAccepted"])
        for key in (
            "differentFrameSizesRejected",
            "fractionalFrameRejected",
            "nonFiniteFrameRejected",
            "outOfRangeImageRejected",
            "oversizedOutputRejected",
            "oversizedSourceRejected",
            "seventeenImagesRejected",
        ):
            self.assertTrue(self.result[key], key)

    def test_launch_context_shares_one_sprite_budget_across_surfaces(self) -> None:
        launch = HOST_LAUNCH_SOURCE.read_text(encoding="utf-8")
        host = HOST_SOURCE.read_text(encoding="utf-8")
        view = METAL_VIEW_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "let spriteTextureLoader: SceneMultiImageSpriteTextureLoader",
            launch,
        )
        rebuild = host.split("private func rebuildSurfaces(", maxsplit=1)[1]
        rebuild = rebuild.split("private func teardownSurfaces", maxsplit=1)[0]
        self.assertEqual(
            rebuild.count(
                "spriteTextureLoader: launchContext.spriteTextureLoader"
            ),
            2,
        )
        load = view.split("func loadImageLayers(", maxsplit=1)[1]
        load = load.split("// MARK:", maxsplit=1)[0]
        self.assertNotIn(
            "let spriteTextureLoader = SceneMultiImageSpriteTextureLoader()",
            load,
        )

    def test_bc3_purpose_preserves_independent_green_and_alpha_channels(self) -> None:
        self.assertEqual(self.result["colorPurposePixel"], [0, 64, 0, 64])
        self.assertEqual(self.result["dataPurposePixel"], [0, 255, 0, 64])
        self.assertEqual(
            self.result["dataFirstPurposePixel"], self.result["dataPurposePixel"]
        )
        self.assertEqual(
            self.result["colorSecondPurposePixel"], self.result["colorPurposePixel"]
        )

    def test_loader_cache_is_separate_and_stable_per_texture_purpose(self) -> None:
        self.assertTrue(self.result["sameColorCacheIdentity"])
        self.assertTrue(self.result["sameDataCacheIdentity"])
        self.assertTrue(self.result["differentPurposeIdentity"])
        self.assertTrue(self.result["semanticPurposeCacheStable"])
        self.assertTrue(self.result["semanticPurposeIdentitiesDistinct"])
        self.assertEqual(
            self.result["semanticPurposePixels"],
            {
                "straightAlbedo": [0, 255, 0, 64],
                "preservedChannels": [0, 255, 0, 64],
                "mask": [0, 255, 0, 64],
                "noise": [0, 255, 0, 64],
                "flow": [0, 255, 0, 64],
                "phase": [0, 255, 0, 64],
                "normal": [0, 255, 0, 64],
            },
        )

    def test_preserved_channels_keep_physical_extent_for_mapped_uvs(self) -> None:
        self.assertEqual(self.result["paddedColorSize"], [4, 4])
        self.assertEqual(self.result["paddedDataSize"], [8, 4])


if __name__ == "__main__":
    unittest.main()
