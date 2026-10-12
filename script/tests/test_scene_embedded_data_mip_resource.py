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
HARNESS = fixture.HARNESS.split("@main", 1)[0] + r'''
@main
private enum EmbeddedDataMipHarness {
    static func observe(
        _ url: URL, purpose: SceneTextureLoadPurpose, device: MTLDevice,
        queue: MTLCommandQueue, expected: [[UInt8]]
    ) -> [String: Any] {
        let loader = SceneTextureLoader()
        switch loader.loadCandidate(from: url, purpose: purpose, device: device) {
        case let .failed(failure):
            return ["status": "failed", "failure": String(describing: failure)]
        case let .loaded(candidate):
            let texture = candidate.texture
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
                guard let buffer = device.makeBuffer(length: length, options: .storageModeShared)
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
                Data(bytes: read.0.contents(), count: read.1) == Data(expected[level])
            }
            return ["status": "loaded", "gpuCompleted": command.status == .completed && command.error == nil,
                "physical": [texture.width, texture.height],
                "mapped": [Int(candidate.mappedSize.width), Int(candidate.mappedSize.height)],
                "levels": texture.mipmapLevelCount, "levelPixelsMatch": levelMatches,
                "identityUV": candidate.uvTransform == .identity,
                "purposeMatches": candidate.purpose == purpose]
        }
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
                results[name + ":" + purpose.reportToken] = observe(
                    root.appendingPathComponent(name), purpose: purpose, device: device,
                    queue: queue, expected: bytes.map { $0.map { UInt8($0.intValue) } })
            }
        }
        var rejected: [String: Bool] = [:]
        for name in ["single-oversized.tex", "bad-mip-table.tex", "bad-mip-payload.tex",
                     "bad-header-mapped.tex"] {
            let outcome = SceneTextureLoader().loadCandidate(from: root.appendingPathComponent(name),
                purpose: .preservedChannels, device: device)
            if case .failed = outcome { rejected[name] = true }
            else { rejected[name] = false }
        }
        let small = observe(root.appendingPathComponent("single-small.tex"),
            purpose: .preservedChannels, device: device, queue: queue,
            expected: (manifest["small"] as! [[NSNumber]]).map { $0.map { UInt8($0.intValue) } })
        let report: [String: Any] = ["available": true, "results": results,
            "rejected": rejected, "singleSmall": small]
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


def _png(width: int, height: int, pixels: bytes) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    scanlines = b"".join(b"\0" + pixels[row * width * 4:(row + 1) * width * 4]
                         for row in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scanlines)) + chunk(b"IEND", b""))


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
        binary = root / "embedded-data-mips"
        compilation = subprocess.run([
            "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
            *(str(path) for path in frozen_sources), str(harness),
            "-framework", "Metal", "-framework", "CoreGraphics", "-framework", "ImageIO",
            "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
        ], cwd=REPOSITORY_ROOT, env=environment, capture_output=True, text=True)
        if compilation.returncode:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary), str(root)], cwd=REPOSITORY_ROOT,
                                   env=environment, capture_output=True, text=True)
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
