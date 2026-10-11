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
    def test_large_video_bytes_still_obey_budget_range_and_compression_limits(self):
        payload_size = 257_625_236
        mp4 = b'\0\0\0\x14ftypisom' + bytes(8)
        with tempfile.TemporaryDirectory(prefix='mwx-large-video-budget-') as directory:
            root = Path(directory)
            for name, code, decoded in [('large', 0, 0), ('compressed-stored', 1, 4)]:
                header = bytearray(fixture([[(code, decoded, b'')]]))
                struct.pack_into('<i', header, len(header) - 4, payload_size)
                with (root / f'{name}.tex').open('wb') as stream:
                    stream.write(header + mp4)
                    stream.seek(len(header) + payload_size - 1)
                    stream.write(b'Z')
            truncated = bytearray(fixture([[(0, 0, mp4)]]))
            struct.pack_into('<i', truncated, len(truncated) - len(mp4) - 4, payload_size)
            negative = bytearray(fixture([[(0, 0, mp4)]]))
            struct.pack_into('<i', negative, len(negative) - len(mp4) - 4, -1)
            cases = {
                'truncated': bytes(truncated),
                'negative': bytes(negative),
                'compressed-decoded': fixture([[(1, payload_size, mp4)]]),
                'compressed-signature': fixture([[(1, 4, mp4)]]),
                'unknown-compression': fixture([[(2, 0, mp4)]]),
                # Bytes outside the declared mip cannot contribute to its signature.
                'cross-boundary': fixture([[(0, 0, b'abcd')]]) + b'ftypisom',
                'short-signature': fixture([[(0, 0, mp4[:8])]]) + mp4[8:],
                # A properly compressed small video keeps the existing decode path.
                'small-compressed': fixture([[(1, len(mp4), b'\xf0\x05' + mp4)]]),
            }
            for name, data in cases.items():
                (root / f'{name}.tex').write_bytes(data)
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
@main enum Harness {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let size = Int(CommandLine.arguments[2])!
        let reader = SceneTexContainerReader()
        func read(_ name: String, budget: Int) throws -> String {
            let data = try Data(contentsOf: root.appendingPathComponent(name + ".tex"),
                                options: .mappedIfSafe)
            do {
                let payload = try reader.read(data: data, maximumDecodedByteCount: budget).mips[0].data
                let kind = SceneTexContainer.isVideoPayload(payload) ? "video" : "raw"
                return "\(kind):\(payload.count):\(payload.last ?? 0)"
            } catch SceneTexContainerReader.ReadError.decodedDataBudgetExceeded {
                return "budget"
            } catch SceneTexContainerReader.ReadError.invalidMipTable {
                return "invalid-mip"
            } catch SceneTexContainerReader.ReadError.unsupportedCompression {
                return "unsupported"
            } catch SceneTexContainerReader.ReadError.decompressionFailed {
                return "decompression"
            } catch { return "other-error:\(error)" }
        }
        var results = [String: String]()
        results["exact"] = try read("large", budget: size)
        results["oneShort"] = try read("large", budget: size - 1)
        results["zero"] = try read("large", budget: 0)
        for name in ["compressed-stored", "truncated", "negative", "compressed-decoded",
                     "compressed-signature", "unknown-compression", "cross-boundary",
                     "short-signature", "small-compressed"] {
            results[name] = try read(name, budget: size)
        }
        print(String(decoding: try JSONEncoder().encode(results), as: UTF8.self))
    }
}
''')
            binary = root / 'harness'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(FORMAT / 'SceneTexContainer.swift'), str(FORMAT / 'SceneTexDataReader.swift'),
                str(harness), '-o', str(binary)], check=True, capture_output=True, timeout=120)
            run = subprocess.run([str(binary), str(root), str(payload_size)], check=True,
                                 capture_output=True, text=True, timeout=60)
            self.assertEqual(json.loads(run.stdout), {
                'exact': f'video:{payload_size}:90', 'oneShort': 'budget', 'zero': 'budget',
                'compressed-stored': 'invalid-mip', 'truncated': 'invalid-mip',
                'negative': 'invalid-mip', 'compressed-decoded': 'invalid-mip',
                'compressed-signature': 'decompression', 'unknown-compression': 'unsupported',
                'cross-boundary': 'raw:4:100', 'short-signature': 'raw:8:112',
                'small-compressed': f'video:{len(mp4)}:0',
            })

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
