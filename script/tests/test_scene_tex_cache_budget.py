"""Decoded cache admission, late refill and release preserve uploaded textures.

These native loader tests do not invoke StaticModels or MetalView consumers.
"""
import json
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path
from script.tests.test_scene_image_upload_completion import FAULTS, HEADER, LOADER_SOURCES, RESAMPLE_SOURCE, SOURCE


def compressed_tex(image_count=2):
    # 4091 A bytes followed by five B literals in a raw LZ4 block.
    payload = b'\x1fA\x01\x00' + b'\xff' * 15 + b'\xf6\x50BBBBB'
    tex = b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', 0, 0, 32, 32, 32, 32, 0)
    tex += b'TEXB0002\0' + struct.pack('<I', image_count)
    for _ in range(image_count):
        tex += struct.pack('<6I', 2, 32, 32, 1, 4096, len(payload)) + payload
        lower = b'\x1fA\x01\x00' + b'\xff' * 3 + b'\xea\x50BBBBB'
        tex += struct.pack('<5I', 16, 16, 1, 1024, len(lower)) + lower
    return tex


class SceneTexCacheBudgetTests(unittest.TestCase):
    def test_prepared_tex_request_reuses_denied_payload_and_preserves_failure_boundaries(self):
        scene = SOURCE.parents[2]
        candidate_sources = [scene / 'Resources/Textures' / name for name in (
            'SceneTextureSampling.swift', 'SceneTextureUVTransform.swift',
            'SceneTextureCandidate.swift', 'SceneTextureLoader+Candidate.swift')]
        with tempfile.TemporaryDirectory(prefix='mwx-tex-prepared-request-') as directory:
            root = Path(directory)
            single = bytearray(compressed_tex(image_count=1))
            struct.pack_into('<I', single, 34, 16)
            for name in ('original.tex', 'renamed-resource.tex'):
                (root / name).write_bytes(single)
            animated = bytearray(single)
            struct.pack_into('<I', animated, 22, 4)
            animated += b'TEXS0002\0' + struct.pack('<I', 1)
            animated += struct.pack('<if6f', 0, 0.1, 0, 0, 16, 0, 0, 32)
            (root / 'animated.tex').write_bytes(animated)
            video_payload = struct.pack('>I', 16) + b'ftypisom' + b'\0' * 4
            video = (b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', 0, 2, 2, 2, 2, 2, 0)
                + b'TEXB0001\0' + struct.pack('<5I', 1, 1, 2, 2, len(video_payload)) + video_payload)
            (root / 'video.tex').write_bytes(video)
            (root / 'broken.tex').write_bytes(b'not a TEX')
            header = root / 'faults.h'
            faults = root / 'faults.m'
            header.write_text(HEADER)
            faults.write_text(FAULTS)
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
import Metal
import CoreGraphics
import ImageIO

@main enum Harness {
    static func candidate(_ outcome: SceneTextureCandidateLoadOutcome) -> SceneTextureCandidate {
        guard case let .loaded(value) = outcome else { fatalError("expected candidate") }
        return value
    }
    static func pixel(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&bytes, bytesPerRow: 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        return bytes
    }
    static func append(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    static func embedded(_ payload: Data, width: Int, height: Int, depth: Int = 1, format: UInt32) -> Data {
        var tex = Data("TEXV0005\0TEXI0001\0".utf8)
        let fields: [UInt32] = depth == 1
            ? [0, 2, UInt32(width), UInt32(height), UInt32(width), UInt32(height), 0]
            : [0, 2, UInt32(width), UInt32(height), UInt32(width * depth), UInt32(height), UInt32(depth), 0]
        for field in fields { append(field, to: &tex) }
        tex.append(Data((depth == 1 ? "TEXB0003\0" : "TEXB0004\0").utf8))
        append(1, to: &tex)
        append(format, to: &tex)
        if depth > 1 { append(0, to: &tex) }
        append(1, to: &tex)
        append(UInt32(width), to: &tex); append(UInt32(height), to: &tex)
        if depth > 1 { append(UInt32(depth), to: &tex) }
        for field in [UInt32(0), UInt32(payload.count), UInt32(payload.count)] { append(field, to: &tex) }
        tex.append(payload)
        return tex
    }
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("SKIP"); return }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let budget = SceneTextureDecodeCacheBudget(maximumBytes: 0)
        let loader = SceneTextureLoader(decodeCacheBudget: budget)
        var results: [String: Bool] = [:]
        let url = root.appendingPathComponent("original.tex")
        let prepared = loader.prepareTexSource(from: url)!
        results["oneDeniedParse"] = budget.rejectionCount == 1 && budget.residentBytes == 0
        results["nonVideoDoesNotReparse"] = loader.videoSourceDeclaration(from: prepared) == nil && budget.rejectionCount == 1
        MWXSetUploadFault(device, 5)
        if case .failed(.textureAllocationFailed) = loader.loadCandidate(from: prepared, purpose: .preservedChannels, device: device) {
            results["transientAllocationRefused"] = true
        }
        MWXSetUploadFault(device, 0)
        let data = candidate(loader.loadCandidate(from: prepared, purpose: .preservedChannels, device: device))
        let color = candidate(loader.loadCandidate(from: prepared, purpose: .premultipliedColor, device: device))
        results["samePreparedRetryWithoutReparse"] = budget.rejectionCount == 1 && pixel(data.texture) == [65, 65, 65, 65]
        results["purposeSeparated"] = data.texture !== color.texture && data.content == .data &&
            color.content == .color(.resolved(.premultipliedAlpha)) && pixel(color.texture) == [17, 17, 17, 65]
        results["geometryAndSampler"] = data.physicalSize == CGSize(width: 32, height: 32) &&
            data.mappedSize == CGSize(width: 16, height: 32) && data.sampling.rawFlags == 0 &&
            data.axisAlignedMappedUVScale(expectedPurpose: .preservedChannels) == SIMD2(0.5, 1)
        if case .failed(.decodeFailed) = loader.loadCandidate(from: prepared, purpose: .lookupTable, device: device) {
            results["twoDimensionalLookupRefused"] = true
        }
        loader.evictDecodedCaches()
        results["deniedCacheReleased"] = budget.residentBytes == 0
        if case let .loaded(cached) = loader.load(from: url, purpose: .preservedChannels, device: device) {
            results["ordinaryWarmLoadDoesNotReparse"] = cached === data.texture && budget.rejectionCount == 1
        }
        let repeated = candidate(loader.loadCandidate(from: prepared, purpose: .preservedChannels, device: device))
        results["publishedTextureSurvivesEviction"] = repeated.texture === data.texture && budget.rejectionCount == 1
        let renamed = loader.prepareTexSource(from: root.appendingPathComponent("renamed-resource.tex"))!
        let renamedCandidate = candidate(loader.loadCandidate(from: renamed, purpose: .preservedChannels, device: device))
        results["renamedSourceSamePixelsDistinctIdentity"] = pixel(renamedCandidate.texture) == pixel(data.texture) &&
            renamedCandidate.identity != data.identity && renamedCandidate.texture !== data.texture && budget.rejectionCount == 2
        let animated = loader.prepareTexSource(from: root.appendingPathComponent("animated.tex"))!
        if case let .loaded(atlas) = loader.loadAnimatedMaterialCandidate(from: animated, purpose: .preservedChannels, device: device) {
            results["animatedPreparedWithoutReparse"] = atlas.frames.count == 1 && atlas.frames[0].xAxis == SIMD2(0.5, 0) &&
                pixel(atlas.candidate.texture) == [65, 65, 65, 65] && budget.rejectionCount == 3
        }
        if case .failed(.decodeFailed) = loader.loadCandidate(from: animated, purpose: .preservedChannels, device: device) {
            results["animatedOrdinaryCandidateRefused"] = true
        }
        let video = loader.prepareTexSource(from: root.appendingPathComponent("video.tex"))!
        let declaration = loader.videoSourceDeclaration(from: video)
        results["videoPreparedWithoutReparse"] = declaration?.source == video.source && declaration?.payload == video.container?.mips.first?.data &&
            declaration?.isWebM == false && budget.rejectionCount == 4
        if case .failed(.texContainsVideoPayload) = loader.loadCandidate(from: video, purpose: .preservedChannels, device: device) {
            results["videoOrdinaryCandidateRefused"] = true
        }
        let badBudget = SceneTextureDecodeCacheBudget(maximumBytes: 0)
        let badLoader = SceneTextureLoader(decodeCacheBudget: badBudget)
        let bad = badLoader.prepareTexSource(from: root.appendingPathComponent("broken.tex"))!
        if case .failed(.decodeFailed) = badLoader.loadCandidate(from: bad, purpose: .preservedChannels, device: device) {
            results["badFormatRemainsLocal"] = bad.container == nil && badBudget.rejectionCount == 0 && badBudget.residentBytes == 0
        }
        let previousRevision = prepared.source
        try Data(contentsOf: url).write(to: url, options: .atomic)
        if case .failed(.decodeFailed) = loader.loadCandidate(from: prepared, purpose: .preservedChannels, device: device) {
            results["stalePreparedRefusedBeforeCachedTexture"] = loader.sourceKey(for: url) != previousRevision && budget.rejectionCount == 4
        }
        let previousVideoRevision = video.source
        try Data(contentsOf: video.url).write(to: video.url, options: .atomic)
        results["staleVideoDeclarationRefused"] = loader.sourceKey(for: video.url) != previousVideoRevision &&
            loader.videoSourceDeclaration(from: video) == nil
        let current = loader.prepareTexSource(from: url)!
        let currentCandidate = candidate(loader.loadCandidate(from: current, purpose: .preservedChannels, device: device))
        results["currentRevisionLoadsIndependently"] = currentCandidate.generation != data.generation &&
            currentCandidate.texture !== data.texture && pixel(currentCandidate.texture) == pixel(data.texture) && budget.rejectionCount == 5

        let pixels = Data([80, 120, 160, 255, 80, 120, 160, 255, 80, 120, 160, 255, 80, 120, 160, 255])
        let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: pixels as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let jpeg = NSMutableData()
        let jpegDestination = CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(jpegDestination, image, nil); precondition(CGImageDestinationFinalize(jpegDestination))
        let jpegURL = root.appendingPathComponent("opaque-renamed.tex")
        try embedded(jpeg as Data, width: 2, height: 2, format: 2).write(to: jpegURL)
        let opaquePrepared = loader.prepareTexSource(from: jpegURL)!
        let opaque = candidate(loader.loadCandidate(from: opaquePrepared, purpose: .premultipliedColor, device: device))
        results["opaqueMetadataPreserved"] = opaque.content == .color(.resolved(.opaque)) && opaque.physicalSize == opaque.mappedSize

        let volumeBytes = Data(repeating: 80, count: 2 * 4 * 4)
        let volumeImage = CGImage(width: 2, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: CGDataProvider(data: volumeBytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let png = NSMutableData()
        let pngDestination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(pngDestination, volumeImage, nil); precondition(CGImageDestinationFinalize(pngDestination))
        let volumeURL = root.appendingPathComponent("volume.tex")
        try embedded(png as Data, width: 2, height: 2, depth: 2, format: 13).write(to: volumeURL)
        let volume = loader.prepareTexSource(from: volumeURL)!
        results["volumeDeclarationRefused"] = volume.container?.isVolume == true && loader.videoSourceDeclaration(from: volume) == nil
        if case .failed(.decodeFailed) = loader.loadCandidate(from: volume, purpose: .premultipliedColor, device: device) {
            results["volumeColorPurposeRefused"] = true
        }
        if case let .loaded(texture) = loader.load(from: volume.url, source: volume.source, purpose: .lookupTable,
            device: device, preparedTexSource: volume) {
            results["volumeLookupRemainsThreeDimensional"] = texture.textureType == .type3D && texture.depth == 2
        }
        if case .failed(.decodeFailed) = loader.loadCandidate(from: volume, purpose: .lookupTable, device: device) {
            results["volumeTypedTwoDimensionalCandidateRefused"] = true
        }
        results["temporaryResultsNotChargedAsPersistentCache"] = budget.residentBytes == 0
        MWXSetUploadFault(device, 0)
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
''')
            subprocess.run(['clang', '-c', str(faults), '-o', str(root / 'faults.o')],
                           check=True, capture_output=True, text=True, timeout=120)
            binary = root / 'harness'
            subprocess.run(['swiftc', '-import-objc-header', str(header), str(SOURCE), str(RESAMPLE_SOURCE),
                            *map(str, LOADER_SOURCES), *map(str, candidate_sources), str(harness),
                            str(root / 'faults.o'), '-o', str(binary)],
                           check=True, capture_output=True, text=True, timeout=120)
            run = subprocess.run([str(binary), str(root)], check=True, capture_output=True, text=True, timeout=60)
            if run.stdout.strip() == 'SKIP':
                self.skipTest('requires actual Metal device')
            result = json.loads(run.stdout)
            expected = ('oneDeniedParse', 'nonVideoDoesNotReparse', 'transientAllocationRefused',
                'samePreparedRetryWithoutReparse', 'purposeSeparated', 'geometryAndSampler',
                'twoDimensionalLookupRefused', 'deniedCacheReleased', 'ordinaryWarmLoadDoesNotReparse', 'publishedTextureSurvivesEviction',
                'renamedSourceSamePixelsDistinctIdentity', 'animatedPreparedWithoutReparse',
                'animatedOrdinaryCandidateRefused', 'videoPreparedWithoutReparse', 'videoOrdinaryCandidateRefused',
                'badFormatRemainsLocal', 'stalePreparedRefusedBeforeCachedTexture', 'staleVideoDeclarationRefused',
                'currentRevisionLoadsIndependently', 'opaqueMetadataPreserved', 'volumeDeclarationRefused',
                'volumeColorPurposeRefused', 'volumeLookupRemainsThreeDimensional',
                'volumeTypedTwoDimensionalCandidateRefused', 'temporaryResultsNotChargedAsPersistentCache')
            self.assertEqual(set(result), set(expected))
            for name in expected:
                self.assertIs(result[name], True, name)

    def test_decoded_bytes_admission_reuse_and_release(self):
        tex = compressed_tex()
        with tempfile.TemporaryDirectory(prefix='mwx-tex-cache-budget-') as directory:
            root = Path(directory)
            path = root / 'compressed.tex'
            path.write_bytes(tex)
            animated = bytearray(tex)
            struct.pack_into('<I', animated, 22, 4)
            animated += b'TEXS0002\0' + struct.pack('<I', 1)
            animated += struct.pack('<if6f', 1, 0.1, 0, 0, 32, 0, 0, 32)
            animated_path = root / 'animated.tex'
            animated_path.write_bytes(animated)
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
@main enum Harness {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        var results: [String: Int] = [:]
        for limit in [0, 10239, 10240, 20480] {
            let budget = SceneTextureDecodeCacheBudget(maximumBytes: limit)
            do {
                let loader = SceneTextureLoader(decodeCacheBudget: budget)
                for _ in 0..<2 {
                    guard let container = loader.texContainer(from: url) else { fatalError("parse failed") }
                    precondition(container.images.count == 2)
                    for image in container.images {
                        precondition(image.mips.count == 2)
                        precondition(image.mips[1].data == Data(repeating: 65, count: 1019) + Data(repeating: 66, count: 5))
                        precondition(image.mips[0].data == Data(repeating: 65, count: 4091) + Data(repeating: 66, count: 5))
                    }
                }
                results["resident\(limit)"] = budget.residentBytes
                results["rejected\(limit)"] = budget.rejectionCount
                withExtendedLifetime(loader) {}
            }
            results["released\(limit)"] = budget.residentBytes
        }
        let animatedURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let tight = SceneTextureDecodeCacheBudget(maximumBytes: 10240)
        let roomy = SceneTextureDecodeCacheBudget(maximumBytes: 11264)
        do {
            let tightLoader = SceneTextureLoader(decodeCacheBudget: tight)
            let roomyLoader = SceneTextureLoader(decodeCacheBudget: roomy)
            precondition(tightLoader.texContainer(from: animatedURL)?.spriteFrames.count == 1)
            precondition(roomyLoader.texContainer(from: animatedURL)?.spriteFrames.count == 1)
            results["animatedDenied"] = tight.residentBytes
            results["animatedAdmitted"] = roomy.residentBytes
            withExtendedLifetime((tightLoader, roomyLoader)) {}
        }
        results["animatedReleased"] = roomy.residentBytes
        let lateBudget = SceneTextureDecodeCacheBudget(maximumBytes: 10240)
        let lateLoader = SceneTextureLoader(decodeCacheBudget: lateBudget)
        guard let first = lateLoader.texContainer(from: url) else { fatalError("initial parse failed") }
        results["initialParseResident"] = lateBudget.residentBytes
        lateLoader.evictDecodedCaches()
        results["initialEvictionResident"] = lateBudget.residentBytes
        guard let late = lateLoader.texContainer(from: url) else { fatalError("late parse failed") }
        precondition(first.images.map { $0.mips.map(\.data) } == late.images.map { $0.mips.map(\.data) })
        results["lateParseResident"] = lateBudget.residentBytes
        lateLoader.evictDecodedCaches()
        results["lateEvictionResident"] = lateBudget.residentBytes
        withExtendedLifetime(lateLoader) {}
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
''')
            binary = root / 'harness'
            subprocess.run(['swiftc', str(SOURCE), str(RESAMPLE_SOURCE), *map(str, LOADER_SOURCES), str(harness), '-o', str(binary)],
                           check=True, capture_output=True, text=True, timeout=120)
            run = subprocess.run([str(binary), str(path), str(animated_path)], check=True, capture_output=True, text=True, timeout=60)
            result = json.loads(run.stdout)
            self.assertEqual(result['animatedDenied'], 0)
            self.assertGreater(result['animatedAdmitted'], 10240)
            self.assertLessEqual(result['animatedAdmitted'], 11264)
            self.assertEqual(result['animatedReleased'], 0)
            self.assertEqual(result['initialParseResident'], 10240)
            self.assertEqual(result['initialEvictionResident'], 0)
            self.assertEqual(result['lateParseResident'], 10240)
            self.assertEqual(result['lateEvictionResident'], 0)
            for limit in (0, 10239, 10240, 20480):
                with self.subTest(limit=limit):
                    self.assertEqual(result[f'resident{limit}'], 10240 if limit >= 10240 else 0)
                    self.assertEqual(result[f'rejected{limit}'], 0 if limit >= 10240 else 2)
                    self.assertEqual(result[f'released{limit}'], 0)

    def test_late_eviction_restores_allocation_and_keeps_uploaded_texture(self):
        def png_chunk(kind, payload):
            return (struct.pack('>I', len(payload)) + kind + payload
                    + struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff))
        red_png = (b'\x89PNG\r\n\x1a\n'
            + png_chunk(b'IHDR', struct.pack('>IIBBBBB', 4, 4, 8, 6, 0, 0, 0))
            + png_chunk(b'IDAT', zlib.compress((b'\0' + b'\xff\0\0\xff' * 4) * 4))
            + png_chunk(b'IEND', b''))
        wide_png = (b'\x89PNG\r\n\x1a\n'
            + png_chunk(b'IHDR', struct.pack('>IIBBBBB', 4097, 2, 8, 6, 0, 0, 0))
            + png_chunk(b'IDAT', zlib.compress((b'\0' + b'\xff\0\0\xff' * 4097) * 2))
            + png_chunk(b'IEND', b''))
        with tempfile.TemporaryDirectory(prefix='mwx-late-cache-release-') as directory:
            root = Path(directory)
            tex_url, png_url = root / 'owned.tex', root / 'owned.png'
            wide_url = root / 'wide.png'
            tex_url.write_bytes(compressed_tex())
            png_url.write_bytes(red_png)
            wide_url.write_bytes(wide_png)
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
import Metal
@main enum Harness {
    static func pixels(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        return bytes
    }
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("SKIP"); return }
        let tex = URL(fileURLWithPath: CommandLine.arguments[1])
        let png = URL(fileURLWithPath: CommandLine.arguments[2])
        let wide = URL(fileURLWithPath: CommandLine.arguments[3])
        let options: MTLResourceOptions = .storageModeShared
        let anchorLength = 65536, requestLength = 8192, decodedCost = 10240
        let anchorCost = device.heapBufferSizeAndAlign(length: anchorLength, options: options).size
        let requestCost = device.heapBufferSizeAndAlign(length: requestLength, options: options).size
        let budget = SceneResourceBudget(maximumBytes: anchorCost + decodedCost + requestCost - 1)
        let decoded = SceneTextureDecodeCacheBudget(maximumBytes: decodedCost, resourceBudget: budget)
        let loader = SceneTextureLoader(decodeCacheBudget: decoded)
        guard let anchor = device.makeSceneBuffer(length: anchorLength, options: options, budget: budget),
              case let .loaded(firstTexture) = loader.load(from: png, device: device)
        else { fatalError("initial real resource preparation failed") }
        let before = pixels(firstTexture)
        let pngSource = loader.sourceKey(for: png)!
        let nativePNG = loader.preparedNaturalImageSize(from: png, source: pngSource)
        let zeroBudget = SceneTextureDecodeCacheBudget(maximumBytes: 0)
        let zeroLoader = SceneTextureLoader(decodeCacheBudget: zeroBudget)
        guard case .loaded = zeroLoader.load(from: png, device: device) else { fatalError("uncached PNG failed") }
        let zeroNativePNG = zeroLoader.preparedNaturalImageSize(from: png, source: zeroLoader.sourceKey(for: png)!)
        guard case let .loaded(wideTexture) = zeroLoader.load(from: wide, device: device) else {
            fatalError("normalized PNG failed")
        }
        let wideNativePNG = zeroLoader.preparedNaturalImageSize(from: wide, source: zeroLoader.sourceKey(for: wide)!)
        precondition(before == Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 16).flatMap { $0 })
        loader.evictDecodedCaches()
        guard let initial = loader.texContainer(from: tex) else { fatalError("initial TEX parse failed") }
        var result: [String: Any] = ["initialDecoded": decoded.residentBytes,
            "nativePNGMetadata": nativePNG?.width == 4 && nativePNG?.height == 4,
            "zeroBudgetNativePNGMetadata": zeroNativePNG?.width == 4 && zeroNativePNG?.height == 4 &&
                zeroBudget.residentBytes == 0 && zeroLoader.directImageDecodeAttemptCount == 2,
            "normalizedPNGNativeMetadata": wideNativePNG?.width == 4097 && wideNativePNG?.height == 2 &&
                wideTexture.width == 4096 && wideTexture.height == 1,
            "nativePNGMetadataRefetchedAfterEviction": loader.preparedNaturalImageSize(from: png, source: pngSource) == nativePNG &&
                loader.directImageDecodeAttemptCount == 1,
            "nativeTEXMetadata": loader.preparedNaturalImageSize(from: tex, source: loader.sourceKey(for: tex)!)?.width == 32]
        loader.evictDecodedCaches()
        result["firstEvictionDecoded"] = decoded.residentBytes
        guard let late = loader.texContainer(from: tex) else { fatalError("late TEX parse failed") }
        result["lateContentSame"] = initial.images.map { $0.mips.map(\.data) } == late.images.map { $0.mips.map(\.data) }
        result["lateDecoded"] = decoded.residentBytes
        result["allocationRejectedWhileLateDecoded"] = device.makeSceneBuffer(
            length: requestLength, options: options, budget: budget) == nil
        result["rejectionsBeforeEviction"] = budget.snapshot.rejectionCount
        loader.evictDecodedCaches()
        result["secondEvictionDecoded"] = decoded.residentBytes
        result["secondEvictionTotal"] = budget.snapshot.residentBytes
        guard let restored = device.makeSceneBuffer(length: requestLength, options: options, budget: budget),
              case let .loaded(cachedTexture) = loader.load(from: png, device: device)
        else { fatalError("allocation or uploaded cache did not survive eviction") }
        result["restoredBufferLength"] = restored.length
        result["restoredResident"] = budget.snapshot.residentBytes
        result["expectedAnchorResident"] = anchorCost
        result["expectedRestoredResident"] = anchorCost + requestCost
        result["sameUploadedTexture"] = firstTexture === cachedTexture
        result["uploadedPixelsUnchanged"] = pixels(cachedTexture) == before
        result["cachedLoadDecoded"] = decoded.residentBytes
        result["decodeAttempts"] = loader.directImageDecodeAttemptCount
        withExtendedLifetime((loader, anchor, restored, firstTexture, cachedTexture)) {}
        print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}
''')
            binary = root / 'harness'
            subprocess.run(['swiftc', str(SOURCE), str(RESAMPLE_SOURCE), *map(str, LOADER_SOURCES),
                            str(harness), '-o', str(binary)],
                           check=True, capture_output=True, text=True, timeout=120)
            run = subprocess.run([str(binary), str(tex_url), str(png_url), str(wide_url)],
                                 check=True, capture_output=True, text=True, timeout=60)
            if run.stdout.strip() == 'SKIP':
                self.skipTest('requires actual Metal device')
            result = json.loads(run.stdout)
            self.assertEqual(result['initialDecoded'], 10240)
            self.assertEqual(result['firstEvictionDecoded'], 0)
            self.assertEqual(result['lateDecoded'], 10240)
            self.assertEqual(result['secondEvictionDecoded'], 0)
            self.assertEqual(result['rejectionsBeforeEviction'], 1)
            self.assertEqual(result['secondEvictionTotal'], result['expectedAnchorResident'])
            self.assertEqual(result['restoredResident'], result['expectedRestoredResident'])
            self.assertGreaterEqual(result['restoredBufferLength'], 8192)
            for name in ('lateContentSame', 'allocationRejectedWhileLateDecoded',
                         'sameUploadedTexture', 'uploadedPixelsUnchanged', 'nativePNGMetadata',
                         'zeroBudgetNativePNGMetadata', 'nativePNGMetadataRefetchedAfterEviction', 'nativeTEXMetadata'):
                self.assertIs(result[name], True, name)
            self.assertIs(result['normalizedPNGNativeMetadata'], True)
            self.assertEqual(result['cachedLoadDecoded'], 0)
            self.assertEqual(result['decodeAttempts'], 1)
