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
from script.tests.scene.test_scene_image_upload_completion import FAULTS, HEADER, LOADER_SOURCES, RESAMPLE_SOURCE, SOURCE


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
    def test_conditional_atlas_upload_preserves_exact_storage_and_whole_variants(self):
        def png(width, height, rgba):
            def chunk(kind, payload):
                return (struct.pack('>I', len(payload)) + kind + payload
                        + struct.pack('>I', zlib.crc32(kind + payload)))
            row_bytes = width * 4
            scanlines = b''.join(b'\0' + rgba[i:i + row_bytes] for i in range(0, len(rgba), row_bytes))
            return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>2I5B', width, height, 8, 6, 0, 0, 0))
                    + chunk(b'IDAT', zlib.compress(scanlines)) + chunk(b'IEND', b''))

        base_pixel = bytes([8, 32, 72, 255])
        tile = png(2, 2, bytes([200, 100, 50, 128, 91, 92, 93, 0, 40, 50, 60, 255, 90, 110, 120, 255]))
        lower_tile = png(1, 1, bytes([0, 0, 255, 255]))
        tex = b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', 0, 2, 8, 8, 8, 8, 0)
        tex += b'TEXB0004\0' + struct.pack('<3I', 1, 13, 2)
        for variant_id, condition in [(1, 'showOverlay'), (2, 'showBroken')]:
            tex += struct.pack('<3I', 1, variant_id, 0) + json.dumps({'condition': condition}).encode() + b'\0'
        tex += struct.pack('<I', 3)
        payload_bytes = 0
        mip_headers, patch_tables = [], []
        for size, patches in [(8, [(1, 2, 3, 2, 2, tile), (2, 6, 6, 1, 1, lower_tile)]),
                              (4, [(1, 1, 2, 1, 1, lower_tile), (2, 2, 1, 2, 2, lower_tile)]), (2, [])]:
            base = png(size, size, base_pixel * size * size)
            mip_headers.append(len(tex))
            tex += struct.pack('<5I', size, size, 0, 0, len(base)) + base
            tex += struct.pack('<2I', 1, len(patches))
            patch_tables.append(len(tex))
            payload_bytes += len(base)
            for variant_id, x, y, width, height, data in patches:
                tex += struct.pack('<8I', 1, variant_id, x, y, width, height, 13, len(data)) + data
                payload_bytes += len(data)

        with tempfile.TemporaryDirectory(prefix='mwx-conditional-atlas-upload-') as directory:
            root = Path(directory)
            atlas = root / 'atlas.tex'
            atlas.write_bytes(tex)
            mismatched = bytearray(tex)
            # The declared lower mip fits a patch at x=4. Its actual PNG and
            # Metal mip are only 4 pixels wide, so the chain must stay base.
            struct.pack_into('<I', mismatched, mip_headers[1], 5)
            struct.pack_into('<I', mismatched, patch_tables[1] + 8, 4)
            mismatch_atlas = root / 'mismatched-atlas.tex'
            mismatch_atlas.write_bytes(mismatched)
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
import Metal

@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("SKIP"); return }
        let cache = SceneTextureDecodeCacheBudget(maximumBytes: 64 * 1024)
        let loader = SceneTextureLoader(decodeCacheBudget: cache)
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let prepared = try loader.prepareTexSource(from: url)!
        let accounted = cache.residentBytes == Int(CommandLine.arguments[2])
        func load(_ ids: Set<UInt32>, purpose: SceneTextureLoadPurpose = .premultipliedColor,
                  source: SceneTextureLoader.PreparedTexSource? = nil) -> MTLTexture {
            guard case let .loaded(texture) = loader.loadConditionalAtlas(
                from: source ?? prepared, selectedIDs: ids, purpose: purpose, device: device
            ) else { fatalError("no conditional atlas texture") }
            return texture
        }
        func pixel(_ texture: MTLTexture, _ x: Int, _ y: Int, _ level: Int = 0) -> [UInt8] {
            var rgba = [UInt8](repeating: 0, count: 4)
            texture.getBytes(&rgba, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: level)
            return rgba
        }
        let base = load([]), selected = load([1, 2]), invalid = load([2]), preserved = load([1], purpose: .preservedChannels)
        let mismatch = try loader.prepareTexSource(from: URL(fileURLWithPath: CommandLine.arguments[3]))!
        let mismatchedBase = load([1], source: mismatch)
        let original: [UInt8] = [8, 32, 72, 255]
        guard case let .loaded(ordinary) = try loader.load(from: url, purpose: .premultipliedColor, device: device) else {
            fatalError("no ordinary atlas texture")
        }
        let records: [String: Bool] = [
            "payloadBudget": accounted && prepared.container?.conditionalVariants.map(\.id) == [1, 2],
            "baseChain": [base, selected, invalid, preserved, ordinary].allSatisfy {
                $0.width == 8 && $0.height == 8 && $0.mipmapLevelCount == 3 && pixel($0, 1, 1, 2) == original
            },
            "storedCoordinates": pixel(selected, 2, 3) == [100, 50, 25, 128]
                && pixel(selected, 2, 4) == [40, 50, 60, 255] && pixel(selected, 2, 2) == original
                && pixel(selected, 1, 2, 1) == [0, 0, 255, 255],
            "clearOverwrite": pixel(selected, 3, 3) == [0, 0, 0, 0]
                && pixel(preserved, 3, 3) == [91, 92, 93, 0],
            "rawDataPurpose": pixel(preserved, 2, 3) == [200, 100, 50, 128],
            "badLaterMipDropsOnlyItsVariant": pixel(selected, 6, 6) == original
                && pixel(invalid, 6, 6) == original && pixel(invalid, 2, 3) == original,
            "mismatchedMipMetadataKeepsBase": mismatch.container?.conditionalVariants.count == 2
                && mismatchedBase.mipmapLevelCount == 3 && pixel(mismatchedBase, 2, 3) == original
                && pixel(mismatchedBase, 3, 2, 1) == original,
            "ordinaryAndEmptySelectionAreIndependent": [base, ordinary].allSatisfy {
                $0 !== selected && pixel($0, 2, 3) == original && pixel($0, 1, 2, 1) == original
            }
        ]
        print(String(decoding: try JSONEncoder().encode(records), as: UTF8.self))
    }
}
''')
            binary = root / 'harness'
            compiled = subprocess.run(['swiftc', str(SOURCE), str(RESAMPLE_SOURCE), *map(str, LOADER_SOURCES),
                                       str(harness), '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            run = subprocess.run([str(binary), str(atlas), str(payload_bytes), str(mismatch_atlas)],
                                 capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            if run.stdout.strip() == 'SKIP':
                self.skipTest('requires actual Metal device')
            self.assertEqual([key for key, passed in json.loads(run.stdout).items() if not passed], [])

    def test_prepared_tex_request_reuses_denied_payload_and_preserves_failure_boundaries(self):
        scene = SOURCE.parents[2]
        candidate_sources = [scene / 'Resources/Textures' / name for name in (
            'SceneTextureSampling.swift', 'SceneTextureUVTransform.swift',
            'SceneTextureCandidate.swift', 'SceneTextureLoader+Candidate.swift', 'SceneOrdinaryImageMipSelection.swift')]
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

enum TextureMetadataProbe { static var calls = 0 }

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
        let prepared = (try loader.prepareTexSource(from: url))!
        results["oneDeniedParse"] = budget.rejectionCount == 1 && budget.residentBytes == 0
        results["nonVideoDoesNotReparse"] = (try loader.videoSourceDeclaration(from: prepared)) == nil && budget.rejectionCount == 1
        MWXSetUploadFault(device, 5)
        if case .failed(.textureAllocationFailed) = (try loader.loadCandidate(from: prepared, purpose: .preservedChannels, device: device)) {
            results["transientAllocationRefused"] = true
        }
        MWXSetUploadFault(device, 0)
        let data = candidate((try loader.loadCandidate(from: prepared, purpose: .preservedChannels, device: device)))
        let color = candidate((try loader.loadCandidate(from: prepared, purpose: .premultipliedColor, device: device)))
        results["samePreparedRetryWithoutReparse"] = budget.rejectionCount == 1 && pixel(data.texture) == [65, 65, 65, 65]
        results["purposeSeparated"] = data.texture !== color.texture && data.content == .data &&
            color.content == .color(.resolved(.premultipliedAlpha)) && pixel(color.texture) == [17, 17, 17, 65]
        results["geometryAndSampler"] = data.physicalSize == CGSize(width: 32, height: 32) &&
            data.mappedSize == CGSize(width: 16, height: 32) && data.sampling.rawFlags == 0 &&
            data.axisAlignedMappedUVScale(expectedPurpose: .preservedChannels) == SIMD2(0.5, 1)
        if case .failed(.decodeFailed) = (try loader.loadCandidate(from: prepared, purpose: .lookupTable, device: device)) {
            results["twoDimensionalLookupRefused"] = true
        }
        loader.evictDecodedCaches()
        results["deniedCacheReleased"] = budget.residentBytes == 0
        if case let .loaded(cached) = (try loader.load(from: url, purpose: .preservedChannels, device: device)) {
            results["ordinaryWarmLoadDoesNotReparse"] = cached === data.texture && budget.rejectionCount == 1
        }
        let repeated = candidate((try loader.loadCandidate(from: prepared, purpose: .preservedChannels, device: device)))
        results["publishedTextureSurvivesEviction"] = repeated.texture === data.texture && budget.rejectionCount == 1
        let renamed = (try loader.prepareTexSource(from: root.appendingPathComponent("renamed-resource.tex")))!
        let renamedCandidate = candidate((try loader.loadCandidate(from: renamed, purpose: .preservedChannels, device: device)))
        results["renamedSourceSamePixelsDistinctIdentity"] = pixel(renamedCandidate.texture) == pixel(data.texture) &&
            renamedCandidate.identity != data.identity && renamedCandidate.texture !== data.texture && budget.rejectionCount == 2
        let animated = (try loader.prepareTexSource(from: root.appendingPathComponent("animated.tex")))!
        if case let .loaded(atlas) = (try loader.loadAnimatedMaterialCandidate(from: animated, purpose: .preservedChannels, device: device)) {
            results["animatedPreparedWithoutReparse"] = atlas.frames.count == 1 && atlas.frames[0].xAxis == SIMD2(0.5, 0) &&
                pixel(atlas.candidate.texture) == [65, 65, 65, 65] && budget.rejectionCount == 3
            if let frame = atlas.frames.first,
               case let .loaded(still) = try loader.loadCandidate(from: animated, purpose: .preservedChannels, device: device) {
                results["constantSpriteCandidateReusesPreparedAtlas"] = still.texture === atlas.candidate.texture
                    && still.isSpriteSheet && still.uvTransform.origin == frame.origin
                    && still.uvTransform.xAxis == frame.xAxis && still.uvTransform.yAxis == frame.yAxis
                    && budget.rejectionCount == 3
            }
        }
        let video = (try loader.prepareTexSource(from: root.appendingPathComponent("video.tex")))!
        let declaration = (try loader.videoSourceDeclaration(from: video))
        results["videoPreparedWithoutReparse"] = declaration?.source == video.source && declaration?.payload == video.container?.mips.first?.data &&
            declaration?.isWebM == false && budget.rejectionCount == 4
        if case .failed(.texContainsVideoPayload) = (try loader.loadCandidate(from: video, purpose: .preservedChannels, device: device)) {
            results["videoOrdinaryCandidateRefused"] = true
        }
        let badBudget = SceneTextureDecodeCacheBudget(maximumBytes: 0)
        let badLoader = SceneTextureLoader(decodeCacheBudget: badBudget)
        let bad = (try badLoader.prepareTexSource(from: root.appendingPathComponent("broken.tex")))!
        if case .failed(.decodeFailed) = (try badLoader.loadCandidate(from: bad, purpose: .preservedChannels, device: device)) {
            results["badFormatRemainsLocal"] = bad.container == nil && badBudget.rejectionCount == 0 && badBudget.residentBytes == 0
        }
        let previousRevision = prepared.source
        try Data(contentsOf: url).write(to: url, options: .atomic)
        let capturedCandidate = candidate(try loader.loadCandidate(from: prepared, purpose: .preservedChannels, device: device))
        let currentRevision = try loader.sourceKey(for: url)
        results["completedPreparedSurvivesLaterAuthorWrite"] = capturedCandidate.texture === data.texture
            && currentRevision != previousRevision && budget.rejectionCount == 4
        let previousVideoRevision = video.source
        let videoURL = root.appendingPathComponent("video.tex")
        try Data(contentsOf: videoURL).write(to: videoURL, options: .atomic)
        let capturedVideo = try loader.videoSourceDeclaration(from: video)
        let currentVideoRevision = try loader.sourceKey(for: video.input)
        results["completedVideoDeclarationSurvivesLaterAuthorWrite"] = capturedVideo?.payload == declaration?.payload
            && currentVideoRevision != previousVideoRevision
        let current = (try loader.prepareTexSource(from: url))!
        let currentCandidate = candidate((try loader.loadCandidate(from: current, purpose: .preservedChannels, device: device)))
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
        let opaquePrepared = (try loader.prepareTexSource(from: jpegURL))!
        let opaque = candidate((try loader.loadCandidate(from: opaquePrepared, purpose: .premultipliedColor, device: device)))
        results["opaqueMetadataPreserved"] = opaque.content == .color(.resolved(.opaque)) && opaque.physicalSize == opaque.mappedSize

        let directURL = root.appendingPathComponent("direct-renamed.jpg")
        try (jpeg as Data).write(to: directURL)
        let directBudget = SceneTextureDecodeCacheBudget(maximumBytes: 0)
        let directLoader = SceneTextureLoader(decodeCacheBudget: directBudget)
        let directPrepared = try directLoader.prepareDirectImageSource(from: directURL)!
        let directNatural = try directLoader.preparedNaturalImageSize(from: directPrepared)
        results["directHeaderIsLazy"] = directNatural == CGSize(width: 2, height: 2) && directLoader.directImageDecodeAttemptCount == 0
        results["directDeniedRetentionKeepsCurrentRequest"] = !directPrepared.admitForPreparation() && directBudget.residentBytes == 0
        let directColor = candidate(try directLoader.loadCandidate(from: directPrepared, purpose: .premultipliedColor, device: device))
        let directData = candidate(try directLoader.loadCandidate(from: directPrepared, purpose: .preservedChannels, device: device))
        results["directPreparedReusesOneDecodeForPurposes"] = directLoader.directImageDecodeAttemptCount == 1 &&
            directColor.texture !== directData.texture && directColor.identity == directData.identity &&
            directColor.content == .color(.resolved(.opaque)) && directData.content == .data && directBudget.residentBytes == 0
        results["decodedDirectCannotReenterMetadataQueue"] = !directPrepared.admitForPreparation()
        directLoader.evictDecodedCaches()
        let warmDirect = try directLoader.prepareDirectImageSource(from: directURL)!
        let warmColor = candidate(try directLoader.loadCandidate(from: warmDirect, purpose: .premultipliedColor, device: device))
        let warmNatural = try directLoader.preparedNaturalImageSize(from: warmDirect)
        results["directPublishedCacheSurvivesDecodedEviction"] = warmColor.texture === directColor.texture &&
            warmColor.content == directColor.content && directLoader.directImageDecodeAttemptCount == 1 &&
            warmNatural == directNatural
        let cachedDirectBudget = SceneTextureDecodeCacheBudget(maximumBytes: 1024 * 1024)
        let cachedDirectLoader = SceneTextureLoader(decodeCacheBudget: cachedDirectBudget)
        _ = try cachedDirectLoader.loadCandidate(from: directURL, purpose: .premultipliedColor, device: device)
        let residentBefore = cachedDirectBudget.residentBytes
        let cachedDirect = try cachedDirectLoader.prepareDirectImageSource(from: directURL)!
        results["directCachedImageNotChargedTwice"] = residentBefore > 0 && cachedDirect.admitForPreparation() &&
            cachedDirectBudget.residentBytes == residentBefore
        _ = try cachedDirectLoader.loadCandidate(from: cachedDirect, purpose: .preservedChannels, device: device)
        results["directCachedPreparedReusesDecode"] = cachedDirectLoader.directImageDecodeAttemptCount == 1 &&
            cachedDirectBudget.residentBytes == residentBefore

        let volumeBytes = Data(repeating: 80, count: 2 * 4 * 4)
        let volumeImage = CGImage(width: 2, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: CGDataProvider(data: volumeBytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let png = NSMutableData()
        let pngDestination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(pngDestination, volumeImage, nil); precondition(CGImageDestinationFinalize(pngDestination))
        let volumeURL = root.appendingPathComponent("volume.tex")
        try embedded(png as Data, width: 2, height: 2, depth: 2, format: 13).write(to: volumeURL)
        let volume = (try loader.prepareTexSource(from: volumeURL))!
        let volumeDeclaration = try loader.videoSourceDeclaration(from: volume)
        results["volumeDeclarationRefused"] = volume.container?.isVolume == true && volumeDeclaration == nil
        if case .failed(.decodeFailed) = (try loader.loadCandidate(from: volume, purpose: .premultipliedColor, device: device)) {
            results["volumeColorPurposeRefused"] = true
        }
        if case let .loaded(texture) = (try loader.load(from: volume.input, source: volume.source, purpose: .lookupTable,
            device: device, preparedTexSource: volume)) {
            results["volumeLookupRemainsThreeDimensional"] = texture.textureType == .type3D && texture.depth == 2
        }
        if case .failed(.decodeFailed) = (try loader.loadCandidate(from: volume, purpose: .lookupTable, device: device)) {
            results["volumeTypedTwoDimensionalCandidateRefused"] = true
        }
        results["temporaryResultsNotChargedAsPersistentCache"] = budget.residentBytes == 0
        MWXSetUploadFault(device, 0)
        do {
            _ = try loader.load(from: renamed.input, source: prepared.source, purpose: .preservedChannels,
                device: device, preparedTexSource: prepared)
            results["preparedInputMismatchIsHard"] = false
        } catch SceneResourceView.ReadError.invalidHandle { results["preparedInputMismatchIsHard"] = true }
        do {
            _ = try loader.load(from: prepared.input, source: current.source, purpose: .preservedChannels,
                device: device, preparedTexSource: prepared)
            results["preparedExpectedKeyMismatchIsHard"] = false
        } catch SceneResourceView.ReadError.sourceChanged { results["preparedExpectedKeyMismatchIsHard"] = true }
        try (jpeg as Data).write(to: directURL, options: .atomic)
        do {
            _ = try directLoader.loadCandidate(from: warmDirect, purpose: .noise, device: device)
            results["scalarFactsCannotLabelNewlyReadBytesWithOldKey"] = false
        } catch SceneResourceView.ReadError.sourceChanged { results["scalarFactsCannotLabelNewlyReadBytesWithOldKey"] = true }
        let queryLoader = SceneTextureLoader()
        TextureMetadataProbe.calls = 0
        _ = try queryLoader.loadCandidate(from: url, purpose: .preservedChannels, device: device)
        results["coldCandidateQueriesIdentityOnce"] = TextureMetadataProbe.calls == 1
        TextureMetadataProbe.calls = 0
        _ = try queryLoader.loadCandidate(from: url, purpose: .preservedChannels, device: device)
        results["warmCandidateQueriesIdentityOnce"] = TextureMetadataProbe.calls == 1
        TextureMetadataProbe.calls = 0
        let cohort = try queryLoader.loadDirectImageCandidates(from: directURL,
            purposes: [.premultipliedColor, .preservedChannels], device: device)
        results["directCohortQueriesIdentityOnce"] = TextureMetadataProbe.calls == 1 && cohort.count == 2
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
''')
            subprocess.run(['clang', '-c', str(faults), '-o', str(root / 'faults.o')],
                           check=True, capture_output=True, text=True, timeout=120)
            binary = root / 'harness'
            loader_source = next(path for path in LOADER_SOURCES if path.name == 'SceneTextureLoader.swift')
            counted_loader = root / loader_source.name
            counted_loader.write_text(loader_source.read_text().replace(
                'static func currentSourceKey(for input: Input, checkCancellation: (() throws -> Void)? = nil) throws -> SourceKey? {',
                'static func currentSourceKey(for input: Input, checkCancellation: (() throws -> Void)? = nil) throws -> SourceKey? {\n        TextureMetadataProbe.calls += 1', 1))
            loader_sources = [counted_loader if path == loader_source else path for path in LOADER_SOURCES]
            compiled = subprocess.run(['swiftc', '-import-objc-header', str(header), str(SOURCE), str(RESAMPLE_SOURCE),
                                       *map(str, loader_sources), *map(str, candidate_sources), str(harness),
                                       str(root / 'faults.o'), '-o', str(binary)],
                                      capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            run = subprocess.run([str(binary), str(root)], check=True, capture_output=True, text=True, timeout=60)
            if run.stdout.strip() == 'SKIP':
                self.skipTest('requires actual Metal device')
            result = json.loads(run.stdout)
            expected = ('oneDeniedParse', 'nonVideoDoesNotReparse', 'transientAllocationRefused',
                'samePreparedRetryWithoutReparse', 'purposeSeparated', 'geometryAndSampler',
                'twoDimensionalLookupRefused', 'deniedCacheReleased', 'ordinaryWarmLoadDoesNotReparse', 'publishedTextureSurvivesEviction',
                'renamedSourceSamePixelsDistinctIdentity', 'animatedPreparedWithoutReparse',
                'constantSpriteCandidateReusesPreparedAtlas', 'videoPreparedWithoutReparse', 'videoOrdinaryCandidateRefused',
                'directHeaderIsLazy', 'directDeniedRetentionKeepsCurrentRequest', 'directPreparedReusesOneDecodeForPurposes',
                'decodedDirectCannotReenterMetadataQueue', 'directPublishedCacheSurvivesDecodedEviction',
                'directCachedImageNotChargedTwice', 'directCachedPreparedReusesDecode',
                'badFormatRemainsLocal', 'completedPreparedSurvivesLaterAuthorWrite', 'completedVideoDeclarationSurvivesLaterAuthorWrite',
                'currentRevisionLoadsIndependently', 'opaqueMetadataPreserved', 'volumeDeclarationRefused',
                'volumeColorPurposeRefused', 'volumeLookupRemainsThreeDimensional',
                'volumeTypedTwoDimensionalCandidateRefused', 'temporaryResultsNotChargedAsPersistentCache',
                'preparedInputMismatchIsHard', 'preparedExpectedKeyMismatchIsHard',
                'scalarFactsCannotLabelNewlyReadBytesWithOldKey', 'coldCandidateQueriesIdentityOnce',
                'warmCandidateQueriesIdentityOnce', 'directCohortQueriesIdentityOnce')
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
                    guard let container = (try loader.texContainer(from: url)) else { fatalError("parse failed") }
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
            let tightContainer = try tightLoader.texContainer(from: animatedURL)
            let roomyContainer = try roomyLoader.texContainer(from: animatedURL)
            precondition(tightContainer?.spriteFrames.count == 1)
            precondition(roomyContainer?.spriteFrames.count == 1)
            results["animatedDenied"] = tight.residentBytes
            results["animatedAdmitted"] = roomy.residentBytes
            withExtendedLifetime((tightLoader, roomyLoader)) {}
        }
        results["animatedReleased"] = roomy.residentBytes
        let lateBudget = SceneTextureDecodeCacheBudget(maximumBytes: 10240)
        let lateLoader = SceneTextureLoader(decodeCacheBudget: lateBudget)
        guard let first = (try lateLoader.texContainer(from: url)) else { fatalError("initial parse failed") }
        results["initialParseResident"] = lateBudget.residentBytes
        lateLoader.evictDecodedCaches()
        results["initialEvictionResident"] = lateBudget.residentBytes
        guard let late = (try lateLoader.texContainer(from: url)) else { fatalError("late parse failed") }
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
              case let .loaded(firstTexture) = (try loader.load(from: png, device: device))
        else { fatalError("initial real resource preparation failed") }
        let before = pixels(firstTexture)
        let pngSource = (try loader.sourceKey(for: png))!
        let nativePNG = (try loader.preparedNaturalImageSize(from: png, source: pngSource))
        let zeroBudget = SceneTextureDecodeCacheBudget(maximumBytes: 0)
        let zeroLoader = SceneTextureLoader(decodeCacheBudget: zeroBudget)
        guard case .loaded = (try zeroLoader.load(from: png, device: device)) else { fatalError("uncached PNG failed") }
        let zeroNativePNG = (try zeroLoader.preparedNaturalImageSize(from: png, source: (try zeroLoader.sourceKey(for: png))!))
        guard case let .loaded(wideTexture) = (try zeroLoader.load(from: wide, device: device)) else {
            fatalError("normalized PNG failed")
        }
        let wideNativePNG = (try zeroLoader.preparedNaturalImageSize(from: wide, source: (try zeroLoader.sourceKey(for: wide))!))
        precondition(before == Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 16).flatMap { $0 })
        loader.evictDecodedCaches()
        guard let initial = (try loader.texContainer(from: tex)) else { fatalError("initial TEX parse failed") }
        var result: [String: Any] = ["initialDecoded": decoded.residentBytes,
            "nativePNGMetadata": nativePNG?.width == 4 && nativePNG?.height == 4,
            "zeroBudgetNativePNGMetadata": zeroNativePNG?.width == 4 && zeroNativePNG?.height == 4 &&
                zeroBudget.residentBytes == 0 && zeroLoader.directImageDecodeAttemptCount == 2,
            "normalizedPNGNativeMetadata": wideNativePNG?.width == 4097 && wideNativePNG?.height == 2 &&
                wideTexture.width == 4096 && wideTexture.height == 1,
            "nativePNGMetadataRefetchedAfterEviction": (try loader.preparedNaturalImageSize(from: png, source: pngSource)) == nativePNG &&
                loader.directImageDecodeAttemptCount == 1,
            "nativeTEXMetadata": (try loader.preparedNaturalImageSize(from: tex, source: (try loader.sourceKey(for: tex))!))?.width == 32]
        loader.evictDecodedCaches()
        result["firstEvictionDecoded"] = decoded.residentBytes
        guard let late = (try loader.texContainer(from: tex)) else { fatalError("late TEX parse failed") }
        result["lateContentSame"] = initial.images.map { $0.mips.map(\.data) } == late.images.map { $0.mips.map(\.data) }
        result["lateDecoded"] = decoded.residentBytes
        result["allocationRejectedWhileLateDecoded"] = device.makeSceneBuffer(
            length: requestLength, options: options, budget: budget) == nil
        result["rejectionsBeforeEviction"] = budget.snapshot.rejectionCount
        loader.evictDecodedCaches()
        result["secondEvictionDecoded"] = decoded.residentBytes
        result["secondEvictionTotal"] = budget.snapshot.residentBytes
        guard let restored = device.makeSceneBuffer(length: requestLength, options: options, budget: budget),
              case let .loaded(cachedTexture) = (try loader.load(from: png, device: device))
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

    def test_raw_tex_shares_immutable_mips_without_sharing_converted_rgba(self):
        def fixture(format_code, pixel):
            tex = b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', format_code, 0, 16, 16, 16, 16, 0)
            tex += b'TEXB0001\0' + struct.pack('<2I', 1, 2)
            for extent, value in ((16, pixel), (8, pixel[::-1])):
                data = bytes(value) * (extent * extent)
                tex += struct.pack('<3I', extent, extent, len(data)) + data
            return tex

        with tempfile.TemporaryDirectory(prefix='mwx-raw-texture-reuse-') as directory:
            root = Path(directory)
            for name, format_code, pixel in (('renamed-rg', 8, [53, 197]), ('revised-rg', 8, [91, 23]),
                                             ('r', 9, [139]), ('rgba', 0, [200, 100, 50, 128])):
                (root / f'{name}.tex').write_bytes(fixture(format_code, pixel))
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
import Metal

@main enum Harness {
    static func pixel(_ texture: MTLTexture, level: Int, channels: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: channels)
        texture.getBytes(&bytes, bytesPerRow: channels,
            from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: level)
        return bytes
    }

    static func texture(_ outcome: SceneTextureLoadOutcome) -> MTLTexture? {
        if case let .loaded(texture) = outcome { return texture }
        return nil
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("SKIP"); return }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        func url(_ name: String) -> URL { root.appendingPathComponent(name + ".tex") }
        let budget = SceneResourceBudget.shared
        let decoded = SceneTextureDecodeCacheBudget(maximumBytes: 4_096)
        let loader = SceneTextureLoader(decodeCacheBudget: decoded)
        let rg = url("renamed-rg")
        var result: [String: Bool] = [:]
        let before = budget.snapshot.residentBytes
        let first = try texture(loader.load(from: rg, purpose: .premultipliedColor, device: device))!
        let firstSource = try loader.sourceKey(for: rg)!
        loader.evictDecodedCaches()
        let rawCharge = budget.snapshot.residentBytes - before
        let filler = budget.maximumBytes - budget.snapshot.residentBytes - (rawCharge - 1)
        precondition(rawCharge > 0 && filler >= 0 && budget.reserve(filler, kind: .gpu))
        let tight = try loader.load(from: rg, purpose: .normal, device: device)
        if case .textureAllocationFailed = tight { result["tightWouldLoseNormal"] = true }
        result["tightShares"] = texture(tight) === first
        budget.release(filler, kind: .gpu)
        loader.evictDecodedCaches()
        let normal = try texture(loader.load(from: rg, purpose: .normal, device: device))!
        result["singleCharge"] = normal === first && budget.snapshot.residentBytes == before + rawCharge
        result["mipsAndFormat"] = normal.pixelFormat == .rg8Unorm && normal.mipmapLevelCount == 2
            && normal.width == 16 && normal.height == 16
            && pixel(normal, level: 0, channels: 2) == [53, 197]
            && pixel(normal, level: 1, channels: 2) == [197, 53]
        result["warmSkipsDecodeAfterEviction"] = decoded.residentBytes == 0

        let r = url("r")
        let dataFirst = try texture(loader.load(from: r, purpose: .mask, device: device))!
        loader.evictDecodedCaches()
        let colorSecond = try texture(loader.load(from: r, purpose: .premultipliedColor, device: device))!
        result["reverseR8"] = dataFirst === colorSecond && colorSecond.pixelFormat == .r8Unorm
            && pixel(colorSecond, level: 1, channels: 1) == [139]

        let rgba = url("rgba")
        let rgbaColor = try texture(loader.load(from: rgba, purpose: .premultipliedColor, device: device))!
        let rgbaData = try texture(loader.load(from: rgba, purpose: .normal, device: device))!
        result["rgbaStaysSeparate"] = rgbaColor !== rgbaData && pixel(rgbaColor, level: 0, channels: 4) == [100, 50, 25, 128]
            && pixel(rgbaData, level: 0, channels: 4) == [200, 100, 50, 128]

        let removed = loader.evictTextures(containedIn: [first])
        let reloaded = try texture(loader.load(from: rg, purpose: .normal, device: device))!
        let recached = try texture(loader.load(from: rg, purpose: .premultipliedColor, device: device))
        result["evictOnePhysicalEntry"] = removed == 1 && reloaded !== first && recached === reloaded
        try Data(contentsOf: url("revised-rg")).write(to: rg, options: .atomic)
        do { _ = try loader.load(from: rg, source: firstSource, purpose: .normal, device: device) }
        catch SceneResourceView.ReadError.sourceChanged { result["staleRevisionRejected"] = true }
        let revised = try texture(loader.load(from: rg, purpose: .premultipliedColor, device: device))!
        result["revisionReplacesStorage"] = revised !== reloaded && pixel(revised, level: 0, channels: 2) == [91, 23]
            && pixel(reloaded, level: 0, channels: 2) == [53, 197]
        print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
    }
}
''')
            binary = root / 'harness'
            build = subprocess.run(['swiftc', str(SOURCE), str(RESAMPLE_SOURCE), *map(str, LOADER_SOURCES),
                                    str(harness), '-module-cache-path', str(root / 'modules'), '-o', str(binary)],
                                   capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary), str(root)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            if run.stdout.strip() == 'SKIP':
                self.skipTest('requires actual Metal device')
            result = json.loads(run.stdout)
            for key in ('tightShares', 'singleCharge', 'mipsAndFormat', 'warmSkipsDecodeAfterEviction', 'reverseR8',
                        'rgbaStaysSeparate', 'evictOnePhysicalEntry', 'staleRevisionRejected', 'revisionReplacesStorage'):
                with self.subTest(key=key):
                    self.assertTrue(result[key], result)
            self.assertNotIn('tightWouldLoseNormal', result)
