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
from script.tests.test_scene_image_upload_completion import LOADER_SOURCES, RESAMPLE_SOURCE, SOURCE


def compressed_tex():
    # 4091 A bytes followed by five B literals in a raw LZ4 block.
    payload = b'\x1fA\x01\x00' + b'\xff' * 15 + b'\xf6\x50BBBBB'
    tex = b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', 0, 0, 32, 32, 32, 32, 0)
    tex += b'TEXB0002\0' + struct.pack('<I', 2)
    for _ in range(2):
        tex += struct.pack('<6I', 2, 32, 32, 1, 4096, len(payload)) + payload
        lower = b'\x1fA\x01\x00' + b'\xff' * 3 + b'\xea\x50BBBBB'
        tex += struct.pack('<5I', 16, 16, 1, 1024, len(lower)) + lower
    return tex


class SceneTexCacheBudgetTests(unittest.TestCase):
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
        with tempfile.TemporaryDirectory(prefix='mwx-late-cache-release-') as directory:
            root = Path(directory)
            tex_url, png_url = root / 'owned.tex', root / 'owned.png'
            tex_url.write_bytes(compressed_tex())
            png_url.write_bytes(red_png)
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
        precondition(before == Array(repeating: [UInt8](arrayLiteral: 255, 0, 0, 255), count: 16).flatMap { $0 })
        loader.evictDecodedCaches()
        guard let initial = loader.texContainer(from: tex) else { fatalError("initial TEX parse failed") }
        var result: [String: Any] = ["initialDecoded": decoded.residentBytes]
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
            run = subprocess.run([str(binary), str(tex_url), str(png_url)],
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
                         'sameUploadedTexture', 'uploadedPixelsUnchanged'):
                self.assertIs(result[name], True, name)
            self.assertEqual(result['cachedLoadDecoded'], 0)
            self.assertEqual(result['decodeAttempts'], 1)
