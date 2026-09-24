"""TEX cache admission accounts decoded payloads across every image."""
import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
from script.tests.test_scene_image_upload_completion import LOADER_SOURCES, SOURCE

class SceneTexCacheBudgetTests(unittest.TestCase):
    def test_decoded_bytes_admission_reuse_and_release(self):
        # 4091 A bytes followed by five B literals in a raw LZ4 block.
        payload = b'\x1fA\x01\x00' + b'\xff' * 15 + b'\xf6\x50BBBBB'
        tex = b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', 0, 0, 32, 32, 32, 32, 0)
        tex += b'TEXB0002\0' + struct.pack('<I', 2)
        for _ in range(2):
            tex += struct.pack('<6I', 2, 32, 32, 1, 4096, len(payload)) + payload
            lower = b'\x1fA\x01\x00' + b'\xff' * 3 + b'\xea\x50BBBBB'
            tex += struct.pack('<5I', 16, 16, 1, 1024, len(lower)) + lower
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
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
''')
            binary = root / 'harness'
            subprocess.run(['swiftc', str(SOURCE), *map(str, LOADER_SOURCES), str(harness), '-o', str(binary)],
                           check=True, capture_output=True, text=True, timeout=120)
            run = subprocess.run([str(binary), str(path), str(animated_path)], check=True, capture_output=True, text=True, timeout=60)
            result = json.loads(run.stdout)
            self.assertEqual(result['animatedDenied'], 0)
            self.assertGreater(result['animatedAdmitted'], 10240)
            self.assertLessEqual(result['animatedAdmitted'], 11264)
            self.assertEqual(result['animatedReleased'], 0)
            for limit in (0, 10239, 10240, 20480):
                with self.subTest(limit=limit):
                    self.assertEqual(result[f'resident{limit}'], 10240 if limit >= 10240 else 0)
                    self.assertEqual(result[f'rejected{limit}'], 0 if limit >= 10240 else 2)
                    self.assertEqual(result[f'released{limit}'], 0)
