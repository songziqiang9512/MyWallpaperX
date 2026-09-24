"""A decodable embedded PNG cannot override a rejected TEX container."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_image_upload_completion import LOADER_SOURCES, SOURCE


HARNESS = r'''
import Foundation
import CoreGraphics
import ImageIO
import Metal

@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("SKIP"); return }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let rgba = Data(repeating: 255, count: 8 * 8 * 4)
        let image = CGImage(width: 8, height: 8, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: rgba as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
        let encoded = NSMutableData()
        let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        let png = encoded as Data
        func container(mipCount: UInt32 = 1, flags: UInt32 = 2, format: UInt32 = 0,
                       texb3: Bool = false, freeFormat: UInt32 = 13,
                       mipWidth: UInt32 = 8, lowerWidth: UInt32? = nil) -> Data {
            var data = Data("TEXV0005\0TEXI0001\0".utf8)
            func append(_ value: UInt32) {
                var little = value.littleEndian
                withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
            }
            for value: UInt32 in [format, flags, 8, 8, 8, 8, 0] { append(value) }
            data.append(Data((texb3 ? "TEXB0003\0" : "TEXB0001\0").utf8))
            append(1)
            if texb3 { append(freeFormat) }
            append(mipCount)
            append(mipWidth)
            append(8)
            if texb3 { append(0); append(UInt32(png.count)) }
            append(UInt32(png.count))
            data.append(png)
            if let lowerWidth {
                for value: UInt32 in [lowerWidth, 4, 0, UInt32(png.count), UInt32(png.count)] {
                    append(value)
                }
                data.append(png)
            }
            return data
        }
        var results: [String: String] = [:]
        for (name, bytes) in [
            ("valid", container()),
            ("valid-texb3", container(texb3: true)),
            ("texb3-size-mismatch", container(texb3: true, mipWidth: 7)),
            ("texb3-format-mismatch", container(texb3: true, freeFormat: 2)),
            ("texb3-unknown-format", container(texb3: true, freeFormat: 99)),
            ("texb3-lower-size-mismatch", container(mipCount: 2, texb3: true, lowerWidth: 4)),
            ("missing-mip", container(mipCount: 2)),
            ("missing-sprite-table", container(flags: 4)),
            ("invalid-header", Data("invalid TEX header ".utf8) + png),
            ("unsupported-format", container(format: UInt32.max))
        ] {
            let url = folder.appendingPathComponent(name + ".tex")
            try bytes.write(to: url)
            switch SceneTextureLoader().load(from: url, device: device) {
            case let .loaded(texture):
                var pixel = [UInt8](repeating: 0, count: 4)
                texture.getBytes(&pixel, bytesPerRow: 4,
                    from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
                results[name] = "loaded:\(texture.mipmapLevelCount):\(pixel)"
            case .decodeFailed: results[name] = "rejected"
            case .unsupportedTexFormat: results[name] = "unsupported"
            default: results[name] = "unexpected"
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
'''


class SceneTexParseAuthorityTests(unittest.TestCase):
    def test_embedded_payload_requires_valid_supported_container(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-tex-authority-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(HARNESS)
            binary = root / "harness"
            subprocess.run(["swiftc", str(SOURCE), *map(str, LOADER_SOURCES),
                            str(harness), "-o", str(binary)],
                           check=True, capture_output=True, text=True, timeout=120)
            result = subprocess.run([str(binary), str(root)], check=True,
                                    capture_output=True, text=True, timeout=60)
            if result.stdout.strip() == "SKIP":
                self.skipTest("Metal unavailable")
            self.assertEqual(json.loads(result.stdout), {
                "valid": "loaded:1:[255, 255, 255, 255]",
                "valid-texb3": "loaded:1:[255, 255, 255, 255]",
                "texb3-size-mismatch": "rejected",
                "texb3-format-mismatch": "rejected",
                "texb3-unknown-format": "rejected",
                "texb3-lower-size-mismatch": "rejected",
                "missing-mip": "rejected",
                "missing-sprite-table": "rejected",
                "invalid-header": "rejected",
                "unsupported-format": "unsupported",
            })
