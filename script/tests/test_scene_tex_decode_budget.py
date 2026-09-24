"""Bound TEX payload expansion before allocation, across images and mips."""
import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORMAT = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Format'


def fixture(images):
    data = b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', 0, 0, 1, 1, 1, 1, 0)
    data += b'TEXB0002\0' + struct.pack('<I', len(images))
    for mips in images:
        data += struct.pack('<I', len(mips))
        for code, size, payload in mips:
            data += struct.pack('<5I', 1, 1, code, size, len(payload)) + payload
    return data


class SceneTexDecodeBudgetTests(unittest.TestCase):
    def test_aggregate_bound_and_predecode_rejection(self):
        raw = (0, 999999, b'ABCD')  # uncompressed cost follows stored bytes
        compressed = (1, 4, b'\x40ABCD')
        with tempfile.TemporaryDirectory(prefix='mwx-tex-decode-budget-') as directory:
            root = Path(directory)
            (root / 'mixed.tex').write_bytes(fixture([[raw, compressed], [compressed, raw]]))
            (root / 'oversized.tex').write_bytes(fixture([[(1, 249_000_000, b'\xff')]]))
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
@main enum Harness {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let mixed = try Data(contentsOf: folder.appendingPathComponent("mixed.tex"))
        let oversized = try Data(contentsOf: folder.appendingPathComponent("oversized.tex"))
        let reader = SceneTexContainerReader()
        var result: [String: String] = [:]
        func read(_ data: Data, _ budget: Int) -> String {
            do {
                let container = try reader.read(data: data, maximumDecodedByteCount: budget)
                let bytes = container.images.flatMap(\.mips).map(\.data)
                return bytes.allSatisfy { $0 == Data("ABCD".utf8) } ? "valid:\(bytes.count)" : "wrong-data"
            } catch SceneTexContainerReader.ReadError.decodedDataBudgetExceeded {
                return "budget"
            } catch { return "other-error" }
        }
        for budget in [-1, 0, 4, 8, 12, 15, 16, 17] {
            result["limit\(budget)"] = read(mixed, budget)
        }
        // Malformed compressed bytes must never reach decompression when
        // their declared output already exceeds the remaining budget.
        result["beforeDecode"] = read(oversized, 16)
        result["repeat"] = read(mixed, 16)
        result["default"] = try reader.read(data: mixed).images.count == 2 ? "valid" : "wrong"
        print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}
''')
            binary = root / 'harness'
            subprocess.run(['swiftc', str(FORMAT / 'SceneTexContainer.swift'),
                            str(FORMAT / 'SceneTexDataReader.swift'), str(harness), '-o', str(binary)],
                           check=True, capture_output=True, text=True, timeout=120)
            run = subprocess.run([str(binary), str(root)], check=True,
                                 capture_output=True, text=True, timeout=60)
            result = json.loads(run.stdout)
            for budget in (-1, 0, 4, 8, 12, 15, 16, 17):
                self.assertEqual(result[f'limit{budget}'], 'valid:4' if budget >= 16 else 'budget')
            self.assertEqual(result['beforeDecode'], 'budget')
            self.assertEqual(result['repeat'], 'valid:4')
            self.assertEqual(result['default'], 'valid')
