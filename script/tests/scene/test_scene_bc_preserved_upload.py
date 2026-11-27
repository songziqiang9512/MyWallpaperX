#!/usr/bin/env python3
"""Native BC sampling, purpose separation and authored mip preservation."""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.scene.test_scene_texture_candidate import HARNESS_SUPPORT_SOURCE, SWIFT_SOURCES

HARNESS = HARNESS_SUPPORT_SOURCE + r'''
@main enum Harness {
    private static var readback: SceneTextureSamplingReadback!

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noDevice }
        readback = try SceneTextureSamplingReadback(device: device)
        if CommandLine.arguments.contains("--measure") {
            let result = try measureUploads(device: device)
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result))
            return
        }
        var result: [String: Any] = [:]
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
        result["paddedMappedPixel"] = try readback.pixel(paddedData, x: 1)
        result["paddedHiddenRGB"] = try readback.pixel(paddedData, x: 7)
        let renamedURL = directory.appendingPathComponent("renamed-resource.tex")
        try Data(contentsOf: paddedURL).write(to: renamedURL)
        let renamed = try loaded(SceneTextureLoader().loadDataTexture(from: renamedURL, device: device))
        result["renamedHiddenRGB"] = try readback.pixel(renamed, x: 7)

        result["nativeCodecs"] = try codecProbes(device: device)
        result["mixedSelectors"] = try mixedSelectorProbes(device: device)
        result["authoredTails"] = try authoredTailProbes(directory: directory, device: device)
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result))
    }

    static func authoredTailProbes(directory: URL, device: MTLDevice) throws -> [String: Any] {
        let loader = SceneTextureLoader()
        let dimensions: [(UInt32, UInt32)] = [(4098, 14), (2049, 7), (1024, 3), (512, 1)]
        var results: [String: Any] = [:]
        for (format, native) in [(UInt32(7), MTLPixelFormat.bc1_rgba), (6, .bc2_rgba), (4, .bc3_rgba)] {
            func fixture(mappedWidth: UInt32 = 4098, mappedHeight: UInt32 = 14,
                         corruptPrefix: Bool = false) -> Data {
                var data = Data("TEXV0005\0TEXI0001\0".utf8)
                func append(_ value: UInt32) {
                    var little = value.littleEndian
                    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
                }
                for value in [format, 2, 4098, 14, mappedWidth, mappedHeight, 0] { append(value) }
                data.append(Data("TEXB0002\0".utf8))
                append(1)
                append(UInt32(dimensions.count))
                for (index, size) in dimensions.enumerated() {
                    let (width, height) = size
                    let blocks = Int((width + 3) / 4 * ((height + 3) / 4))
                    let rgb = index % 2 == 0 ? UInt8(0xe0) : UInt8(0x1f)
                    let high = index % 2 == 0 ? UInt8(0x07) : UInt8(0)
                    var block = Data([rgb, high, rgb, high, 0, 0, 0, 0])
                    if format == 6 { block = Data(repeating: UInt8(index * 17), count: 8) + block }
                    if format == 4 {
                        block = Data([UInt8(index * 53), 0, 0, 0, 0, 0, 0, 0]) + block
                    }
                    var bytes = Data(capacity: blocks * block.count)
                    let blocksPerRow = Int((width + 3) / 4)
                    var edgeBlock = block
                    edgeBlock.replaceSubrange((block.count - 8)..<(block.count - 4), with: [0, 0xf8, 0, 0xf8])
                    for blockIndex in 0..<blocks {
                        let isHiddenEdge = index == 1 && mappedWidth == 4094
                            && blockIndex % blocksPerRow == blocksPerRow - 1
                        bytes.append(isHiddenEdge ? edgeBlock : block)
                    }
                    if corruptPrefix && index == 0 { bytes.removeLast() }
                    for value in [width, height, 0, 0, UInt32(bytes.count)] { append(value) }
                    data.append(bytes)
                }
                return data
            }
            func open(_ name: String, _ bytes: Data) throws -> SceneTextureLoader.PreparedTexSource {
                let url = directory.appendingPathComponent("\(format)-\(name).tex")
                try bytes.write(to: url)
                guard let prepared = try loader.prepareTexSource(from: url) else { throw HarnessError.load }
                return prepared
            }
            func candidate(_ source: SceneTextureLoader.PreparedTexSource,
                _ selection: SceneOrdinaryImageMipSelection?, purpose: SceneTextureLoadPurpose = .straightAlbedo
            ) throws -> SceneTextureCandidate {
                guard case let .loaded(candidate) = try loader.loadCandidate(from: source, purpose: purpose,
                    device: device, mipSelection: selection) else { throw HarnessError.load }
                return candidate
            }
            let source = try open("authored", fixture())
            let autoSelection = SceneOrdinaryImageMipSelection.minimumExtent(SIMD2(1000, 3))
            let auto = try candidate(source, autoSelection)
            let performance = try candidate(source, .maximumLongEdge(2048))
            let full = try candidate(source, nil)
            let mask = try candidate(source, autoSelection, purpose: .mask)
            let padded = try candidate(open("padded", fixture(mappedWidth: 4097)), autoSelection)
            let performanceSelection = SceneOrdinaryImageMipSelection.maximumLongEdge(2048)
            let oddWidth = try candidate(open("odd-width", fixture(mappedWidth: 4097)), performanceSelection)
            let oddHeight = try candidate(open("odd-height", fixture(mappedWidth: 4094, mappedHeight: 13)),
                performanceSelection)
            let exactSource = try open("padded-exact", fixture(mappedWidth: 4094, mappedHeight: 12))
            let exactTail = try candidate(exactSource, performanceSelection)
            let exactFull = try candidate(exactSource, nil)
            let exactAuto = try candidate(exactSource, autoSelection)
            let exactMask = try candidate(exactSource, performanceSelection, purpose: .mask)
            let exactWarmTail = try candidate(exactSource, performanceSelection)
            let exactRenamed = try candidate(open("padded-exact-renamed", fixture(mappedWidth: 4094, mappedHeight: 12)),
                performanceSelection)
            let logicalEdge = SIMD2<Float>(0.9999, 0.5)
            let originalUV = logicalEdge * SIMD2(exactFull.uvTransform.xAxis.x, exactFull.uvTransform.yAxis.y)
            let tailUV = logicalEdge * SIMD2(exactTail.uvTransform.xAxis.x, exactTail.uvTransform.yAxis.y)
            let sourceEdge = try readback.sample(exactFull.texture, uv: originalUV, mip: 1)
            let tailEdge = try readback.sample(exactTail.texture, uv: tailUV)
            let hiddenTail = try readback.sample(exactTail.texture, uv: logicalEdge)
            let renamed = try candidate(open("renamed", fixture()), autoSelection)
            let malformed = try open("malformed", fixture(corruptPrefix: true))
            let rejected = try loader.loadCandidate(from: malformed, purpose: .straightAlbedo,
                device: device, mipSelection: autoSelection)
            var everyAuthorLevelMatches = true
            for selected in [auto, performance, renamed] {
                for level in 0..<selected.texture.mipmapLevelCount {
                    let x = max(1, selected.texture.width >> level) - 1
                    let y = max(1, selected.texture.height >> level) - 1
                    let original = try readback.pixel(full.texture, level: level + selected.authoredBaseMip, x: x, y: y)
                    let result = try readback.pixel(selected.texture, level: level, x: x, y: y)
                    everyAuthorLevelMatches = everyAuthorLevelMatches && result == original
                }
            }
            let invalidPrefixRejected: Bool
            if case .failed = rejected { invalidPrefixRejected = true } else { invalidPrefixRejected = false }
            results[String(format)] = [
                "bases": [full, auto, performance, mask, padded, renamed].map(\.authoredBaseMip),
                "sizes": [full, auto, performance].map { [$0.texture.width, $0.texture.height] },
                "levels": [full, auto, performance].map { $0.texture.mipmapLevelCount },
                "nativeFormat": [full, auto, performance, mask, padded, renamed].allSatisfy { $0.texture.pixelFormat == native },
                "straightAlpha": auto.content == full.content && auto.content == .color(.resolved(.straightAlpha)),
                "sampledLevelsMatch": everyAuthorLevelMatches,
                "baseRanges": auto.originalMappedSize == full.mappedSize && performance.originalMappedSize == full.mappedSize,
                "memoryReduces": auto.texture.allocatedSize < full.texture.allocatedSize
                    && auto.texture.allocatedSize < performance.texture.allocatedSize
                    && performance.texture.allocatedSize < full.texture.allocatedSize,
                "cacheKeepsBase": try candidate(source, autoSelection).texture === auto.texture && auto.texture !== full.texture,
                "invalidPrefixRejected": invalidPrefixRejected,
                "paddedBases": [exactFull, exactTail, exactAuto, exactMask, oddWidth, oddHeight, exactRenamed].map(\.authoredBaseMip),
                "paddedMappedSize": [Int(exactTail.mappedSize.width), Int(exactTail.mappedSize.height)],
                "paddedKeepsMapping": exactTail.uvTransform == exactFull.uvTransform
                    && exactTail.originalMappedSize == exactFull.mappedSize
                    && exactRenamed.uvTransform == exactTail.uvTransform && exactTail.content == exactFull.content,
                "paddedPhysicalSavings": exactTail.texture.pixelFormat == native
                    && exactTail.texture.width == 2049 && exactTail.texture.height == 7
                    && exactTail.texture.allocatedSize < exactFull.texture.allocatedSize,
                "paddedKeepsMappedEdge": sourceEdge == tailEdge && hiddenTail != tailEdge,
                "paddedCacheKeepsBase": exactAuto.texture === exactFull.texture
                    && exactTail.texture !== exactFull.texture
                    && exactWarmTail.texture === exactTail.texture,
            ]
        }
        return results
    }

    static func codecProbes(device: MTLDevice) throws -> [String: Any] {
        var results: [String: Any] = [:]
        for (format, pixelFormat, alpha) in [
            (UInt32(7), MTLPixelFormat.bc1_rgba, UInt8(255)),
            (UInt32(6), MTLPixelFormat.bc2_rgba, UInt8(68)),
            (UInt32(4), MTLPixelFormat.bc3_rgba, UInt8(64)),
        ] {
            func block(_ color: UInt16) -> Data {
                let colorBytes = Data([UInt8(color & 255), UInt8(color >> 8),
                    UInt8(color & 255), UInt8(color >> 8), 0, 0, 0, 0])
                if format == 7 { return colorBytes }
                let alphaBytes = format == 6 ? Data(repeating: 0x44, count: 8)
                    : Data([alpha, alpha, 0, 0, 0, 0, 0, 0])
                return alphaBytes + colorBytes
            }
            let mips = [
                SceneTexContainer.Mip(width: 8, height: 4, data: block(0x07e0) + block(0x07e0)),
                SceneTexContainer.Mip(width: 4, height: 2, data: block(0xf800)),
            ]
            func container(_ images: [SceneTexContainer.Image]) -> SceneTexContainer {
                .init(format: format, flags: 2, textureWidth: 8, textureHeight: 4,
                    imageWidth: 6, imageHeight: 3, containerVersion: .texb0002,
                    freeImageFormat: -1, isVideoMp4: false, images: images, spriteFrames: [])
            }
            let authored = container([.init(mips: mips)])
            var purposeResults: [String: Any] = [:]
            for (name, purpose) in [
                ("straightAlbedo", SceneTextureLoadPurpose.straightAlbedo),
                ("preservedChannels", .preservedChannels), ("mask", .mask),
                ("noise", .noise), ("flow", .flow), ("phase", .phase),
                ("normal", .normal), ("depth", .depth),
            ] {
                let texture = try loaded(SceneCompressedTextureUploader.upload(
                    container: authored, pixelFormat: pixelFormat, purpose: purpose, device: device))
                let expectedFormat: MTLPixelFormat = device.supportsBCTextureCompression
                    ? pixelFormat : .rgba8Unorm
                purposeResults[name] = [
                    "formatPreserved": texture.pixelFormat == expectedFormat,
                    "size": [texture.width, texture.height],
                    "mips": texture.mipmapLevelCount,
                    "base": try readFirstPixel(texture: texture, device: device),
                    "tail": try readFirstPixel(texture: texture, level: 1, device: device),
                ]
            }
            let pma = try loaded(SceneCompressedTextureUploader.upload(
                container: authored, pixelFormat: pixelFormat, purpose: .premultipliedColor, device: device))
            let lut = try loaded(SceneCompressedTextureUploader.upload(
                container: authored, pixelFormat: pixelFormat, purpose: .lookupTable, device: device))
            let broken = SceneTexContainer.Image(mips: [mips[0],
                .init(width: 4, height: 2, data: Data(mips[1].data.dropLast()))])
            let failure = SceneCompressedTextureUploader.upload(container: container([broken]),
                pixelFormat: pixelFormat, purpose: .straightAlbedo, device: device)
            let rejected: Bool
            if case .decodeFailed = failure { rejected = true } else { rejected = false }
            // A genuine two-slice payload must not be published as a 2D source.
            // This does not declare BC volume support in the direct uploader.
            let volume = SceneTexContainer(format: format, flags: 2,
                textureWidth: 8, textureHeight: 4, textureDepth: 2,
                imageWidth: 8, imageHeight: 4, containerVersion: .texb0002,
                freeImageFormat: -1, isVideoMp4: false,
                images: [.init(mips: [.init(width: 8, height: 4, depth: 2,
                    data: mips[0].data + mips[0].data)])], spriteFrames: [])
            let volumeOutcome = SceneCompressedTextureUploader.upload(container: volume,
                pixelFormat: pixelFormat, purpose: .straightAlbedo, device: device)
            let volumeRejected: Bool
            if case .decodeFailed = volumeOutcome { volumeRejected = true } else { volumeRejected = false }
            let multiImage = try loaded(SceneCompressedTextureUploader.upload(
                container: container([.init(mips: mips), .init(mips: mips)]),
                pixelFormat: pixelFormat, purpose: .premultipliedColor, device: device))
            let completeMips = mips + [
                .init(width: 2, height: 1, data: block(0x001f)),
                .init(width: 1, height: 1, data: block(0x001f)),
            ]
            func cropped(_ authored: [SceneTexContainer.Mip]) -> SceneTexContainer {
                .init(format: format, flags: 2, textureWidth: 8, textureHeight: 4,
                    imageWidth: 2, imageHeight: 1, containerVersion: .texb0002,
                    freeImageFormat: -1, isVideoMp4: false,
                    images: [.init(mips: authored)], spriteFrames: [])
            }
            func rejectsCropped(_ authored: [SceneTexContainer.Mip],
                          purpose: SceneTextureLoadPurpose) -> Bool {
                if case .decodeFailed = SceneCompressedTextureUploader.upload(
                    container: cropped(authored), pixelFormat: pixelFormat,
                    purpose: purpose, device: device) { return true }
                return false
            }
            var unusedBadTail = completeMips
            unusedBadTail[3] = .init(width: 1, height: 1,
                data: Data(completeMips[3].data.dropLast()))
            let croppedColor = try loaded(SceneCompressedTextureUploader.upload(
                container: cropped(unusedBadTail), pixelFormat: pixelFormat,
                purpose: .premultipliedColor, device: device))
            var usedBadMip = completeMips
            usedBadMip[1] = .init(width: 4, height: 2,
                data: Data(completeMips[1].data.dropLast()))
            var usedBadDimensions = completeMips
            usedBadDimensions[1] = .init(width: 3, height: 2, data: block(0xf800))
            var fullChainPurposes: [String: Any] = [:]
            for (name, purpose) in [
                ("straightAlbedo", SceneTextureLoadPurpose.straightAlbedo),
                ("preservedChannels", .preservedChannels), ("mask", .mask),
                ("noise", .noise), ("flow", .flow), ("phase", .phase),
                ("normal", .normal), ("depth", .depth), ("lookupTable", .lookupTable),
            ] {
                let texture = try loaded(SceneCompressedTextureUploader.upload(
                    container: cropped(completeMips), pixelFormat: pixelFormat,
                    purpose: purpose, device: device))
                fullChainPurposes[name] = ["size": [texture.width, texture.height],
                    "mips": texture.mipmapLevelCount,
                    "tail": try readFirstPixel(texture: texture, level: 3, device: device),
                    "badTailRejected": rejectsCropped(unusedBadTail, purpose: purpose)]
            }
            results[String(format)] = ["purposes": purposeResults,
                "pmaRGBA": pma.pixelFormat == .rgba8Unorm,
                "pmaPixel": try readFirstPixel(texture: pma, device: device),
                "lutKeepsPriorRGBA": lut.pixelFormat == .rgba8Unorm,
                "volumeCannotPublish2D": volume.isVolume && volumeRejected,
                "multiImagePMA": try readFirstPixel(texture: multiImage, device: device),
                "corruptTailRejected": rejected,
                "croppedColor": ["size": [croppedColor.width, croppedColor.height],
                    "mips": croppedColor.mipmapLevelCount,
                    "pixels": try (0..<croppedColor.mipmapLevelCount).map {
                        try readFirstPixel(texture: croppedColor, level: $0, device: device)
                    },
                    "usedBadMipRejected": rejectsCropped(usedBadMip, purpose: .premultipliedColor),
                    "usedBadDimensionsRejected": rejectsCropped(usedBadDimensions, purpose: .premultipliedColor)],
                "fullCroppedPurposes": fullChainPurposes]
        }
        let punchThrough = SceneTexContainer(format: 7, flags: 2,
            textureWidth: 4, textureHeight: 4, imageWidth: 4, imageHeight: 4,
            containerVersion: .texb0002, freeImageFormat: -1, isVideoMp4: false,
            images: [.init(mips: [.init(width: 4, height: 4,
                data: Data([0, 0, 255, 255, 255, 255, 255, 255]))])], spriteFrames: [])
        let transparent = try loaded(SceneCompressedTextureUploader.upload(
            container: punchThrough, pixelFormat: .bc1_rgba, purpose: .mask, device: device))
        results["bc1PunchThrough"] = try readFirstPixel(texture: transparent, device: device)
        return results
    }

    /// The existing CPU decoder supplies the reference; the fixture only authors
    /// endpoints and selector bytes. Sampling uses the single shared MSL owner.
    static func mixedSelectorProbes(device: MTLDevice) throws -> [String: Any] {
        var results: [String: Any] = [:]
        for (name, format, pixelFormat, alphaBytes, colorBytes) in [
            ("bc1FourColor", UInt32(7), MTLPixelFormat.bc1_rgba, Data(),
                Data([0x1f, 0xf8, 0xe0, 0x07, 0xe4, 0x1b, 0x72, 0x8d])),
            ("bc1PunchThrough", UInt32(7), MTLPixelFormat.bc1_rgba, Data(),
                Data([0xe0, 0x07, 0x1f, 0xf8, 0xe4, 0x1b, 0x72, 0x8d])),
            ("bc2AlphaNibbles", UInt32(6), MTLPixelFormat.bc2_rgba,
                Data([0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]),
                Data([0x1f, 0xf8, 0xe0, 0x07, 0xe4, 0x1b, 0x72, 0x8d])),
            ("bc3AlphaInterpolation", UInt32(4), MTLPixelFormat.bc3_rgba,
                Data([203, 19, 0x88, 0xc6, 0xfa, 0x88, 0xc6, 0xfa]),
                Data([0x1f, 0xf8, 0xe0, 0x07, 0xe4, 0x1b, 0x72, 0x8d])),
            ("bc3AlphaZeroAndOne", UInt32(4), MTLPixelFormat.bc3_rgba,
                Data([19, 203, 0x88, 0xc6, 0xfa, 0x88, 0xc6, 0xfa]),
                Data([0x1f, 0xf8, 0xe0, 0x07, 0xe4, 0x1b, 0x72, 0x8d])),
        ] {
            let block = alphaBytes + colorBytes
            let bytes = block + block
            guard let decoded = SceneBCTextureDecoder.decode(blockData: bytes,
                storedWidth: 8, storedHeight: 4, imageWidth: 8, imageHeight: 4,
                format: SceneBCTextureDecoder.Format(texFormat: format)!) else { throw HarnessError.load }
            func container(format: UInt32, data: Data) -> SceneTexContainer {
                .init(format: format, flags: 2, textureWidth: 8, textureHeight: 4,
                    imageWidth: 6, imageHeight: 3, containerVersion: .texb0002,
                    freeImageFormat: -1, isVideoMp4: false,
                    images: [.init(mips: [.init(width: 8, height: 4, data: data)])], spriteFrames: [])
            }
            let texture = try loaded(SceneCompressedTextureUploader.upload(
                container: container(format: format, data: bytes), pixelFormat: pixelFormat,
                purpose: .mask, device: device))
            let reference = try loaded(SceneTextureMipUploader.uploadRaw(
                container: container(format: 0, data: decoded.rgba), pixelFormat: .rgba8Unorm,
                bytesPerPixel: 4, device: device))
            let expected = [UInt8](decoded.rgba)
            var nearestDelta = 0
            for y in 0..<4 {
                for x in 0..<8 {
                    let actual = try readback.pixel(texture, x: x, y: y)
                    for channel in 0..<4 {
                        nearestDelta = max(nearestDelta,
                            abs(Int(actual[channel]) - Int(expected[(y * 8 + x) * 4 + channel])))
                    }
                }
            }
            var linearDelta = 0
            for uv in [SIMD2<Float>(0.5, 0.375), SIMD2(0.375, 0.5), SIMD2(0.875, 0.375)] {
                let actual = try readback.sample(texture, uv: uv, linear: true)
                let prior = try readback.sample(reference, uv: uv, linear: true)
                for channel in 0..<4 {
                    linearDelta = max(linearDelta, abs(Int(actual[channel]) - Int(prior[channel])))
                }
            }
            results[name] = ["nearestMaxUNormDelta": nearestDelta, "linearMaxUNormDelta": linearDelta]
        }
        return results
    }

    /// Self-authored constant blocks match the neutral size/mip metadata only.
    /// Fixture construction and sampler preparation stay outside upload timing.
    static func measureUploads(device: MTLDevice) throws -> [String: Any] {
        var results: [[String: Any]] = []
        for (format, pixelFormat, width, height, levels) in [
            (UInt32(7), MTLPixelFormat.bc1_rgba, 2048, 1024, 4),
            (UInt32(6), MTLPixelFormat.bc2_rgba, 512, 512, 4),
            (UInt32(4), MTLPixelFormat.bc3_rgba, 3840, 2176, 5),
        ] {
            let color = Data([0xe0, 0x07, 0xe0, 0x07, 0, 0, 0, 0])
            let block = format == 7 ? color :
                (format == 6 ? Data(repeating: 0x44, count: 8)
                    : Data([64, 64, 0, 0, 0, 0, 0, 0])) + color
            let mips = (0..<levels).map { level -> SceneTexContainer.Mip in
                let w = max(1, width >> level), h = max(1, height >> level)
                var bytes = Data(count: ((w + 3) / 4) * ((h + 3) / 4) * block.count)
                bytes.withUnsafeMutableBytes { destination in
                    block.withUnsafeBytes { source in
                        for offset in stride(from: 0, to: destination.count, by: block.count) {
                            destination.baseAddress!.advanced(by: offset)
                                .copyMemory(from: source.baseAddress!, byteCount: block.count)
                        }
                    }
                }
                return .init(width: w, height: h, data: bytes)
            }
            let container = SceneTexContainer(format: format, flags: 2,
                textureWidth: width, textureHeight: height,
                imageWidth: width, imageHeight: height, containerVersion: .texb0002,
                freeImageFormat: -1, isVideoMp4: false,
                images: [.init(mips: mips)], spriteFrames: [])
            for (name, purpose) in [("straightAlbedo", SceneTextureLoadPurpose.straightAlbedo),
                                    ("premultipliedColor", .premultipliedColor)] {
                let before = device.currentAllocatedSize
                let begin = DispatchTime.now().uptimeNanoseconds
                let texture = try loaded(SceneCompressedTextureUploader.upload(
                    container: container, pixelFormat: pixelFormat, purpose: purpose, device: device))
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000
                let after = device.currentAllocatedSize
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: texture.pixelFormat, width: texture.width, height: texture.height,
                    mipmapped: false)
                descriptor.mipmapLevelCount = texture.mipmapLevelCount
                descriptor.storageMode = .shared
                descriptor.usage = .shaderRead
                results.append(["sourceFormat": format, "purpose": name,
                    "width": width, "height": height, "mips": texture.mipmapLevelCount,
                    "pixelFormat": texture.pixelFormat.rawValue, "uploadWallMS": elapsed,
                    "allocatedSize": texture.allocatedSize,
                    "heapRequirementBytes": device.heapTextureSizeAndAlign(descriptor: descriptor).size,
                    "deviceAllocatedBefore": before, "deviceAllocatedAfterUpload": after,
                    "samples": try (0..<texture.mipmapLevelCount).map {
                        try readFirstPixel(texture: texture, level: $0, device: device)
                    }])
                withExtendedLifetime(texture) {}
            }
        }
        return ["device": device.name, "supportsBC": device.supportsBCTextureCompression,
            "mode": "own upload microprobe; no scene/App/product acceptance", "uploads": results]
    }

    static func readFirstPixel(texture: MTLTexture, level: Int = 0, device: MTLDevice) throws -> [UInt8] {
        try readback.pixel(texture, level: level)
    }

    static func loaded(_ outcome: SceneTextureLoadOutcome) throws -> MTLTexture {
        guard case let .loaded(texture) = outcome else { throw HarnessError.load }
        return texture
    }

    enum HarnessError: Error { case noDevice, load }
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
        let hiddenRed = Data([0, 0, 0, 0, 0, 0, 0, 0,
            0x00, 0xf8, 0x00, 0xf8, 0, 0, 0, 0])
        for index in 0..<blockCount { data.append(index == 0 ? block : hiddenRed) }
        return data
    }

}
'''


class SceneBCPreservedUploadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory(prefix="mwx-bc-preserved-")
        root = Path(cls._tmp.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        frozen_sources = []
        for source in SWIFT_SOURCES:
            frozen = root / source.name
            shutil.copy2(source, frozen)
            frozen_sources.append(frozen)
        binary = root / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, frozen_sources), str(harness),
             "-module-cache-path", str(root / "module-cache"), "-o", str(binary)],
            capture_output=True, text=True, timeout=180,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")
        execution = subprocess.run([str(binary)], capture_output=True, text=True, timeout=90)
        if execution.returncode != 0:
            raise AssertionError(f"harness run failed:\n{execution.stderr}")
        cls.result = json.loads(execution.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

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
        self.assertEqual(self.result["paddedMappedPixel"], [0, 255, 0, 64])
        self.assertEqual(self.result["paddedHiddenRGB"], [255, 0, 0, 0])
        self.assertEqual(self.result["renamedHiddenRGB"], self.result["paddedHiddenRGB"])

    def test_native_single_image_preserves_every_purpose_and_authored_mip(self) -> None:
        for code, alpha in (("7", 255), ("6", 68), ("4", 64)):
            with self.subTest(format=code):
                values = self.result["nativeCodecs"][code]
                for purpose, record in values["purposes"].items():
                    with self.subTest(purpose=purpose):
                        self.assertEqual(record, {"formatPreserved": True, "size": [8, 4],
                            "mips": 2, "base": [0, 255, 0, alpha], "tail": [255, 0, 0, alpha]})
                self.assertTrue(values["pmaRGBA"])
                self.assertEqual(values["pmaPixel"], [0, alpha, 0, alpha])
                self.assertTrue(values["lutKeepsPriorRGBA"])
                self.assertTrue(values["volumeCannotPublish2D"])
                for actual, expected in zip(values["multiImagePMA"], [0, alpha, 0, alpha], strict=True):
                    self.assertLessEqual(abs(actual - expected), 1)
                self.assertTrue(values["corruptTailRejected"])
        self.assertEqual(self.result["nativeCodecs"]["bc1PunchThrough"], [0, 0, 0, 0])

    def test_mixed_color_alpha_selectors_match_cpu_reference_through_real_sampling(self) -> None:
        self.assertEqual(set(self.result["mixedSelectors"]), {
            "bc1FourColor", "bc1PunchThrough", "bc2AlphaNibbles",
            "bc3AlphaInterpolation", "bc3AlphaZeroAndOne"})
        for name, value in self.result["mixedSelectors"].items():
            with self.subTest(block=name):
                # BC interpolation has a normalized hardware rounding boundary;
                # linear sampling adds a final RGBA8 write quantization boundary.
                self.assertLessEqual(value["nearestMaxUNormDelta"], 1)
                self.assertLessEqual(value["linearMaxUNormDelta"], 2)

    def test_native_straight_color_rebases_author_blocks_on_the_original_upload_path(self) -> None:
        self.assertEqual(set(self.result["authoredTails"]), {"4", "6", "7"})
        for fmt, result in self.result["authoredTails"].items():
            with self.subTest(format=fmt):
                self.assertEqual(result["bases"], [0, 2, 1, 0, 0, 2])
                self.assertEqual(result["sizes"], [[4098, 14], [1024, 3], [2049, 7]])
                self.assertEqual(result["levels"], [4, 2, 3])
                self.assertEqual(result["paddedBases"], [0, 1, 0, 0, 0, 0, 1])
                self.assertEqual(result["paddedMappedSize"], [2047, 6])
                for key in ("nativeFormat", "straightAlpha", "sampledLevelsMatch", "baseRanges",
                            "memoryReduces", "cacheKeepsBase", "invalidPrefixRejected",
                            "paddedKeepsMapping", "paddedPhysicalSavings", "paddedKeepsMappedEdge",
                            "paddedCacheKeepsBase"):
                    self.assertTrue(result[key], result)

    def test_cropped_color_decodes_only_used_levels_and_preserves_data_chains(self) -> None:
        for code, alpha in (("7", 255), ("6", 68), ("4", 64)):
            with self.subTest(format=code):
                values = self.result["nativeCodecs"][code]
                self.assertEqual(values["croppedColor"], {"size": [2, 1], "mips": 2,
                    "pixels": [[0, alpha, 0, alpha], [alpha, 0, 0, alpha]],
                    "usedBadMipRejected": True, "usedBadDimensionsRejected": True})
                self.assertEqual(set(values["fullCroppedPurposes"]), {
                    "straightAlbedo", "preservedChannels", "mask", "noise", "flow",
                    "phase", "normal", "depth", "lookupTable"})
                for purpose, record in values["fullCroppedPurposes"].items():
                    with self.subTest(purpose=purpose):
                        self.assertEqual(record, {"size": [8, 4], "mips": 4,
                            "tail": [0, 0, 255, alpha], "badTailRejected": True})
