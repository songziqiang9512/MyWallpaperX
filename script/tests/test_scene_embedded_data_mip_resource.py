#!/usr/bin/env python3

"""Compiled embedded TEX mips retain their pixels for every 2D upload purpose."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

from script.tests import test_scene_texture_candidate as fixture


REPOSITORY_ROOT = fixture.REPOSITORY_ROOT
SWIFT_SOURCES = fixture.SWIFT_SOURCES
HARNESS = fixture.HARNESS_SUPPORT_SOURCE + r'''
@main
private enum EmbeddedDataMipHarness {
    static func pixels(
        _ texture: MTLTexture, queue: MTLCommandQueue, expected: [[UInt8]], tolerance: Int = 0
    ) -> [String: Any] {
        guard texture.mipmapLevelCount == expected.count,
              let command = queue.makeCommandBuffer(),
              let blit = command.makeBlitCommandEncoder() else {
            return ["status": "gpu-preparation-failed"]
        }
        var reads: [(MTLBuffer, Int)] = []
        for level in expected.indices {
            let width = max(1, texture.width >> level)
            let height = max(1, texture.height >> level)
            let rowBytes = width * 4
            let length = rowBytes * height
            guard let buffer = texture.device.makeBuffer(length: length, options: .storageModeShared)
            else { return ["status": "readback-allocation-failed"] }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: level,
                sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: .init(width: width, height: height, depth: 1),
                to: buffer, destinationOffset: 0, destinationBytesPerRow: rowBytes,
                destinationBytesPerImage: length)
            reads.append((buffer, length))
        }
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        let levelMatches = reads.enumerated().map { level, read in
            let actual = Data(bytes: read.0.contents(), count: read.1)
            return actual.count == expected[level].count && zip(actual, expected[level]).enumerated().allSatisfy {
                abs(Int($0.element.0) - Int($0.element.1)) <= ($0.offset % 4 == 3 ? 0 : tolerance)
            }
        }
        return ["status": "loaded", "gpuCompleted": command.status == .completed && command.error == nil,
            "physical": [texture.width, texture.height], "levels": texture.mipmapLevelCount,
            "levelPixelsMatch": levelMatches]
    }

    static func observe(
        _ url: URL, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        queue: MTLCommandQueue, expected: [[UInt8]], tolerance: Int = 0,
        loader: SceneTextureLoader = SceneTextureLoader()
    ) throws -> [String: Any] {
        switch try loader.loadCandidate(from: url, purpose: purpose, device: device) {
        case let .failed(failure):
            return ["status": "failed", "failure": String(describing: failure)]
        case let .loaded(candidate):
            var facts = pixels(candidate.texture, queue: queue, expected: expected, tolerance: tolerance)
            facts["mapped"] = [Int(candidate.mappedSize.width), Int(candidate.mappedSize.height)]
            facts["identityUV"] = candidate.uvTransform == .identity
            facts["purposeMatches"] = candidate.purpose == purpose
            return facts
        }
    }

    static func image(
        _ bytes: [UInt8], width: Int = 2, height: Int = 2, channels: Int,
        gray: Bool = false, bits: Int = 8, rowBytes: Int? = nil,
        alpha: CGImageAlphaInfo, order: CGBitmapInfo = .byteOrderDefault,
        float: Bool = false, decode: UnsafePointer<CGFloat>? = nil
    ) -> CGImage {
        let info = CGBitmapInfo(rawValue: alpha.rawValue | order.rawValue)
            .union(float ? .floatComponents : [])
        guard let image = CGImage(width: width, height: height,
            bitsPerComponent: bits, bitsPerPixel: channels * bits,
            bytesPerRow: rowBytes ?? width * channels * (bits / 8),
            space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: info, provider: CGDataProvider(data: Data(bytes) as CFData)!,
            decode: decode, shouldInterpolate: false, intent: .defaultIntent) else {
            fatalError("owned packed image could not be constructed")
        }
        return image
    }

    static func packedLayouts(device: MTLDevice, queue: MTLCommandQueue) -> [String: Any] {
        let rgb: [UInt8] = [17,91,203,255, 64,128,200,255, 221,9,73,255, 31,173,89,255]
        let gray: [UInt8] = [17,17,17,255, 91,91,91,255, 203,203,203,255, 64,64,64,255]
        let ga: [UInt8] = [17,17,17,0, 91,91,91,128, 203,203,203,255, 64,64,64,37]
        let rgba: [UInt8] = [17,91,203,0, 64,128,200,128, 221,9,73,255, 31,173,89,37]
        let inputs: [(String, CGImage, [UInt8])] = [
            ("rgb24-strided", image([17,91,203,64,128,200,9,9, 221,9,73,31,173,89,9,9],
                channels: 3, rowBytes: 8, alpha: .none), rgb),
            ("gray8-strided", image([17,91,9,9, 203,64,9,9],
                channels: 1, gray: true, rowBytes: 4, alpha: .none), gray),
            ("gray-alpha-last", image([17,0,91,128,9,9, 203,255,64,37,9,9],
                channels: 2, gray: true, rowBytes: 6, alpha: .last), ga),
            ("gray-alpha-first-little", image([17,0,91,128, 203,255,64,37],
                channels: 2, gray: true, alpha: .first, order: .byteOrder16Little), ga),
            ("gray-padding-last", image([17,9,91,9, 203,9,64,9],
                channels: 2, gray: true, alpha: .noneSkipLast), gray),
            ("rgb-padding-first-little", image([203,91,17,9,200,128,64,9, 73,9,221,9,89,173,31,9],
                channels: 4, alpha: .noneSkipFirst, order: .byteOrder32Little), rgb),
            ("rgba-transparent-strided", image([17,91,203,0,64,128,200,128,9,9,9,9,
                                              221,9,73,255,31,173,89,37,9,9,9,9],
                channels: 4, rowBytes: 12, alpha: .last), rgba),
            ("rgba-first-little", image([203,91,17,0,200,128,64,128, 73,9,221,255,89,173,31,37],
                channels: 4, alpha: .first, order: .byteOrder32Little), rgba),
        ]
        var result: [String: Any] = [:]
        for (name, source, expected) in inputs {
            switch SceneImageTextureUploader.upload(image: source, purpose: .mask,
                maxDimension: 4096, mipmapGeneration: .baseLevelOnly, device: device) {
            case let .loaded(texture):
                result[name] = pixels(texture, queue: queue, expected: [expected])
            default: result[name] = ["status": "failed"]
            }
        }
        let sixteen = image([UInt8](repeating: 127, count: 32), channels: 4, bits: 16,
            alpha: .last, order: .byteOrder16Big)
        let floating = image([UInt8](repeating: 0, count: 64), channels: 4, bits: 32,
            alpha: .last, order: .byteOrder32Little, float: true)
        let premultiplied = image(rgba, channels: 4, alpha: .premultipliedLast)
        let decoded = [CGFloat](repeating: 1, count: 8).withUnsafeBufferPointer {
            image(rgba, channels: 4, alpha: .last, decode: $0.baseAddress)
        }
        let source = inputs[0].1
        result["rejected"] = [
            "data16": SceneImageTextureUploader.rgbaData(image: sixteen,
                width: 2, height: 2, purpose: .mask) == nil,
            "float": SceneImageTextureUploader.rgbaData(image: floating,
                width: 2, height: 2, purpose: .mask) == nil,
            "premultiplied": SceneImageTextureUploader.rgbaData(image: premultiplied,
                width: 2, height: 2, purpose: .mask) == nil,
            "decode": SceneImageTextureUploader.rgbaData(image: decoded,
                width: 2, height: 2, purpose: .mask) == nil,
            "resize": SceneImageTextureUploader.rgbaData(image: source,
                width: 1, height: 1, purpose: .mask) == nil,
        ]
        return result
    }

    static func mixedJPEG(root: URL, device: MTLDevice, queue: MTLCommandQueue) throws -> [String: Any] {
        let sizes = [(16,8), (8,4), (4,2)]
        let components: [[UInt8]] = [[57], [35,83,119], [177,69,23]]
        let colors: [[UInt8]] = [[57,57,57,255], [35,83,119,255], [177,69,23,255]]
        var payloads: [Data] = []
        var expected: [[UInt8]] = []
        for (level, size) in sizes.enumerated() {
            let bytes = Array(repeating: components[level], count: size.0 * size.1).flatMap { $0 }
            let source = image(bytes, width: size.0, height: size.1,
                channels: components[level].count, gray: level == 0, alpha: .none)
            let encoded = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil)
            else { fatalError("JPEG fixture encoder unavailable") }
            CGImageDestinationAddImage(destination, source,
                [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { fatalError("JPEG fixture encoding failed") }
            payloads.append(encoded as Data)
            expected.append(Array(repeating: colors[level], count: size.0 * size.1).flatMap { $0 })
        }
        func tex(_ images: [Data]) -> Data {
            var data = Data("TEXV0005\0TEXI0001\0".utf8)
            func fields(_ values: [UInt32]) {
                for value in values { var word = value.littleEndian; withUnsafeBytes(of: &word) { data.append(contentsOf: $0) } }
            }
            fields([0,2,16,8,16,8,0])
            data.append(Data("TEXB0003\0".utf8))
            fields([1,2,UInt32(images.count)])
            for (level, payload) in images.enumerated() {
                fields([UInt32(sizes[level].0),UInt32(sizes[level].1),0,0,UInt32(payload.count)])
                data.append(payload)
            }
            return data
        }
        let loader = SceneTextureLoader()
        var result: [String: Any] = [:]
        let bad = root.appendingPathComponent("bad-later-jpeg.tex")
        var broken = payloads
        broken[2] = Data([0xFF,0xD8,0xFF,0xD9])
        try tex(broken).write(to: bad)
        if case .failed = try loader.loadCandidate(from: bad, purpose: .mask, device: device) {
            result["badLaterMipRejected"] = true
        } else { result["badLaterMipRejected"] = false }
        for name in ["mixed-gray-rgb.tex", "renamed-payload.tex"] {
            let url = root.appendingPathComponent(name)
            try tex(payloads).write(to: url)
            result[name] = try observe(url, purpose: .mask, device: device, queue: queue,
                expected: expected, tolerance: 3, loader: loader)
        }
        result["decodedColorModels"] = payloads.map {
            SceneImageTextureUploader.decodeSourceImage($0)?.colorSpace?.model == .monochrome
                ? "gray" : "rgb"
        }
        return result
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { print(#"{"available":false}"#); return }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("inputs.json"))) as! [String: Any]
        let raw = manifest["raw"] as! [[NSNumber]]
        let associated = manifest["associated"] as! [[NSNumber]]
        var results: [String: Any] = [:]
        let purposes: [SceneTextureLoadPurpose] = [.premultipliedColor, .straightAlbedo,
            .preservedChannels, .mask, .noise, .flow, .phase, .normal, .depth]
        for name in ["authored-data-mips.tex", "renamed-signal.tex"] {
            for purpose in purposes {
                let bytes = purpose.preservesSourceChannels ? raw : associated
                results[name + ":" + purpose.reportToken] = try observe(
                    root.appendingPathComponent(name), purpose: purpose, device: device,
                    queue: queue, expected: bytes.map { $0.map { UInt8($0.intValue) } })
            }
        }
        var rejected: [String: Bool] = [:]
        for name in ["single-oversized.tex", "bad-mip-table.tex", "bad-mip-payload.tex",
                     "bad-header-mapped.tex"] {
            let outcome = try SceneTextureLoader().loadCandidate(from: root.appendingPathComponent(name),
                purpose: .preservedChannels, device: device)
            if case .failed = outcome { rejected[name] = true }
            else { rejected[name] = false }
        }
        let small = try observe(root.appendingPathComponent("single-small.tex"),
            purpose: .preservedChannels, device: device, queue: queue,
            expected: (manifest["small"] as! [[NSNumber]]).map { $0.map { UInt8($0.intValue) } })
        func observer(_ name: String) -> UInt64 {
            guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "mwx_embedded_header_" + name) else {
                fatalError("header observation symbol missing")
            }
            return unsafeBitCast(symbol, to: (@convention(c) () -> UInt64).self)()
        }
        let reuseLoader = SceneTextureLoader()
        _ = observer("reset")
        let prepared = try reuseLoader.prepareTexSource(from: root.appendingPathComponent("authored-data-mips.tex"))!
        let preparationHeaderReads = observer("count")
        guard case .loaded = try reuseLoader.loadCandidate(from: prepared, purpose: .straightAlbedo, device: device) else {
            fatalError("metadata reuse positive control failed")
        }
        _ = observer("reset")
        for purpose: SceneTextureLoadPurpose in [.straightAlbedo, .premultipliedColor, .preservedChannels] {
            guard case .loaded = try reuseLoader.loadCandidate(from: prepared, purpose: purpose, device: device) else {
                fatalError("prepared purpose reuse failed")
            }
        }
        let reuseHeaderReads = observer("count")
        var encodedChannels: [String: Any] = [:]
        for (name, expected) in [("encoded-gray.png", [UInt8](arrayLiteral: 85,85,85,255)),
                                 ("encoded-gray-alpha.png", [UInt8](arrayLiteral: 85,85,85,0))] {
            let encoded = try Data(contentsOf: root.appendingPathComponent(name))
            switch SceneImageTextureUploader.uploadEncodedPreservedChannels(encoded, device: device) {
            case let .success(texture):
                encodedChannels[name] = pixels(texture, queue: queue, expected: [expected])
            case let .failure(failure):
                encodedChannels[name] = ["status": "failed", "failure": String(describing: failure)]
            }
        }
        let report: [String: Any] = ["available": true, "results": results,
            "rejected": rejected, "singleSmall": small,
            "packedLayouts": packedLayouts(device: device, queue: queue),
            "encodedChannels": encodedChannels,
            "mixedJPEG": try mixedJPEG(root: root, device: device, queue: queue),
            "preparationHeaderReads": preparationHeaderReads, "reuseHeaderReads": reuseHeaderReads]
        let output = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print(String(decoding: output, as: UTF8.self))
    }
}
'''


def _pixels(width: int, height: int, level: int, *, associated: bool = False) -> bytes:
    colors = [([21, 66, 199, 0], [201, 17, 40, 255]),
              ([83, 191, 12, 0], [11, 38, 240, 255]),
              ([50, 2, 145, 0], [13, 234, 91, 255])]
    transparent, opaque = colors[level % len(colors)]
    if associated:
        transparent = [0, 0, 0, 0]
    row = (bytes(transparent + opaque) * ((width + 1) // 2))[:width * 4]
    return row * height


def _png(width: int, height: int, pixels: bytes, *, color_type: int = 6) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    channels = {0: 1, 4: 2, 6: 4}[color_type]
    scanlines = b"".join(b"\0" + pixels[row * width * channels:(row + 1) * width * channels]
                         for row in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


HEADER_OBSERVER = r'''
#include <ImageIO/ImageIO.h>
#include <stdatomic.h>
#include <stdint.h>
static _Atomic uint64_t observed;
uint64_t mwx_embedded_header_reset(void) { return atomic_exchange(&observed, 0); }
uint64_t mwx_embedded_header_count(void) { return atomic_load(&observed); }
static CFDictionaryRef observed_properties(CGImageSourceRef source, size_t index, CFDictionaryRef options) {
    atomic_fetch_add(&observed, 1);
    return CGImageSourceCopyPropertiesAtIndex(source, index, options);
}
__attribute__((used)) static const struct { const void *replacement; const void *original; }
interpose_properties __attribute__((section("__DATA,__interpose"))) = {
    (const void *)observed_properties, (const void *)CGImageSourceCopyPropertiesAtIndex
};
'''


def _tex(mips: list[tuple[int, int, bytes]], *, mapped: tuple[int, int] = (4097, 4)) -> bytes:
    data = (b"TEXV0005\0TEXI0001\0"
            + struct.pack("<7I", 0, 2, 8192, 8, *mapped, 0)
            + b"TEXB0003\0" + struct.pack("<3I", 1, 13, len(mips)))
    for width, height, payload in mips:
        data += struct.pack("<5I", width, height, 0, 0, len(payload)) + payload
    return data


def prepare_inputs(root: Path) -> None:
    sizes = [(4097, 4), (2048, 2), (1024, 1)]
    raw = [_pixels(width, height, level) for level, (width, height) in enumerate(sizes)]
    mips = [(width, height, _png(width, height, raw[level]))
            for level, (width, height) in enumerate(sizes)]
    authored = _tex(mips)
    (root / "authored-data-mips.tex").write_bytes(authored)
    (root / "renamed-signal.tex").write_bytes(authored)
    (root / "single-oversized.tex").write_bytes(_tex(mips[:1]))
    (root / "bad-mip-table.tex").write_bytes(_tex([mips[0], (2047, 2, mips[1][2])]))
    (root / "bad-mip-payload.tex").write_bytes(_tex([mips[0], (2048, 2, mips[2][2])]))
    (root / "bad-header-mapped.tex").write_bytes(_tex(mips, mapped=(8193, 4)))
    small = _pixels(8, 2, 0)
    (root / "single-small.tex").write_bytes(_tex([(8, 2, _png(8, 2, small))], mapped=(8, 2)))
    (root / "encoded-gray.png").write_bytes(_png(1, 1, bytes([85]), color_type=0))
    (root / "encoded-gray-alpha.png").write_bytes(_png(1, 1, bytes([85, 0]), color_type=4))
    (root / "inputs.json").write_text(json.dumps({
        "raw": [list(data) for data in raw],
        "associated": [list(_pixels(width, height, level, associated=True))
                       for level, (width, height) in enumerate(sizes)],
        "small": [list(small)],
    }))


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneEmbeddedDataMipResourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-embedded-data-mips-")
        root = Path(cls.temporary_directory.name)
        cls.addClassCleanup(cls.temporary_directory.cleanup)
        prepare_inputs(root)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS)
        frozen_sources = []
        for source in SWIFT_SOURCES:
            frozen = root / source.name
            shutil.copy2(source, frozen)
            frozen_sources.append(frozen)
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "module-cache")
        observer_source = root / "header-observer.c"
        observer_source.write_text(HEADER_OBSERVER)
        observer = root / "header-observer.dylib"
        observed_build = subprocess.run(["xcrun", "clang", "-dynamiclib", str(observer_source),
            "-framework", "ImageIO", "-o", str(observer)], env=environment, capture_output=True, text=True)
        if observed_build.returncode:
            raise RuntimeError(observed_build.stderr)
        binary = root / "embedded-data-mips"
        compilation = subprocess.run([
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            *(str(path) for path in frozen_sources), str(harness),
            "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
            "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
        ], cwd=REPOSITORY_ROOT, env=environment, capture_output=True, text=True)
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        run_environment = environment.copy()
        run_environment["DYLD_INSERT_LIBRARIES"] = str(observer)
        completed = subprocess.run([str(binary), str(root)], cwd=REPOSITORY_ROOT,
                                   env=run_environment, capture_output=True, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stderr or completed.stdout)
        cls.result = json.loads(completed.stdout)
        if not cls.result["available"]:
            raise unittest.SkipTest("Metal is unavailable")

    def test_all_2d_purposes_preserve_every_compiled_level_and_gpu_pixel(self) -> None:
        self.assertEqual(len(self.result["results"]), 18)
        for identity, facts in self.result["results"].items():
            with self.subTest(identity=identity):
                self.assertEqual(facts["status"], "loaded", facts)
                self.assertTrue(facts["gpuCompleted"], facts)
                self.assertEqual(facts["physical"], [4097, 4], facts)
                self.assertEqual(facts["mapped"], [4097, 4], facts)
                self.assertEqual(facts["levels"], 3, facts)
                self.assertEqual(facts["levelPixelsMatch"], [True, True, True], facts)
                self.assertTrue(facts["identityUV"], facts)
                self.assertTrue(facts["purposeMatches"], facts)

    def test_embedded_metadata_is_captured_once_and_reused_across_purposes(self) -> None:
        self.assertEqual(self.result["preparationHeaderReads"], 3)
        self.assertEqual(self.result["reuseHeaderReads"], 0)

    def test_packed_rgb_gray_alpha_and_padding_preserve_gpu_channels(self) -> None:
        layouts = self.result["packedLayouts"]
        self.assertEqual(set(layouts), {
            "rgb24-strided", "gray8-strided", "gray-alpha-last", "gray-alpha-first-little",
            "gray-padding-last", "rgb-padding-first-little", "rgba-transparent-strided",
            "rgba-first-little", "rejected",
        })
        for name, facts in layouts.items():
            if name == "rejected":
                continue
            with self.subTest(layout=name):
                self.assertEqual(facts["status"], "loaded", facts)
                self.assertTrue(facts["gpuCompleted"], facts)
                self.assertEqual(facts["physical"], [2, 2], facts)
                self.assertEqual(facts["levels"], 1, facts)
                self.assertEqual(facts["levelPixelsMatch"], [True], facts)
        self.assertEqual(layouts["rejected"], {
            "data16": True, "float": True, "premultiplied": True, "decode": True, "resize": True,
        })
        encoded = self.result["encodedChannels"]
        self.assertEqual(set(encoded), {"encoded-gray.png", "encoded-gray-alpha.png"})
        for name, facts in encoded.items():
            with self.subTest(encoded=name):
                self.assertEqual(facts["status"], "loaded", facts)
                self.assertTrue(facts["gpuCompleted"], facts)
                self.assertEqual(facts["physical"], [1, 1], facts)
                self.assertEqual(facts["levels"], 1, facts)
                self.assertEqual(facts["levelPixelsMatch"], [True], facts)

    def test_mixed_gray_and_rgb_jpeg_mips_survive_rename_and_failed_peer(self) -> None:
        mixed = self.result["mixedJPEG"]
        self.assertTrue(mixed["badLaterMipRejected"], mixed)
        self.assertEqual(mixed["decodedColorModels"], ["gray", "rgb", "rgb"], mixed)
        for name in ["mixed-gray-rgb.tex", "renamed-payload.tex"]:
            facts = mixed[name]
            with self.subTest(resource=name):
                self.assertEqual(facts["status"], "loaded", facts)
                self.assertTrue(facts["gpuCompleted"], facts)
                self.assertEqual(facts["physical"], [16, 8], facts)
                self.assertEqual(facts["mapped"], [16, 8], facts)
                self.assertEqual(facts["levels"], 3, facts)
                self.assertEqual(facts["levelPixelsMatch"], [True, True, True], facts)
                self.assertTrue(facts["identityUV"], facts)
                self.assertTrue(facts["purposeMatches"], facts)

    def test_single_level_and_invalid_metadata_keep_existing_boundaries(self) -> None:
        self.assertEqual(self.result["rejected"], {
            "single-oversized.tex": True, "bad-mip-table.tex": True,
            "bad-mip-payload.tex": True, "bad-header-mapped.tex": True,
        })
        small = self.result["singleSmall"]
        self.assertEqual(small["status"], "loaded", small)
        self.assertTrue(small["gpuCompleted"], small)
        self.assertEqual(small["physical"], [8, 2], small)
        self.assertEqual(small["levelPixelsMatch"], [True], small)


if __name__ == "__main__":
    unittest.main()
