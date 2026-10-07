"""JPEG orientation reaches embedded TEX extents and actual Metal pixels."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_scene_texture_candidate import HARNESS as CANDIDATE_HARNESS, SWIFT_SOURCES


HARNESS = CANDIDATE_HARNESS.split('@main')[0] + r'''
@main
enum OrientationHarness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
        let loader = SceneTextureLoader()
        let width = 48, height = 32
        let colors: [[UInt8]] = [[240, 10, 10, 255], [10, 240, 10, 255],
                                  [10, 10, 240, 255], [240, 240, 10, 255]]
        let pixels = (0..<height).flatMap { y in
            (0..<width).flatMap { x in colors[(y >= height / 2 ? 2 : 0) + (x >= width / 2 ? 1 : 0)] }
        }
        let image = CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
        var output: [[String: Any]] = []
        for orientation in 0...8 {
            let encoded = NSMutableData()
            let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil)!
            var metadata: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
            if orientation != 0 { metadata[kCGImagePropertyOrientation] = orientation }
            CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { fatalError("fixture encode") }
            let payload = encoded as Data
            let displayWidth = orientation >= 5 ? height : width
            let displayHeight = orientation >= 5 ? width : height
            func container(_ mipWidth: Int) -> SceneTexContainer {
                SceneTexContainer(format: 0, flags: 2,
                    textureWidth: displayWidth, textureHeight: displayHeight,
                    imageWidth: displayWidth, imageHeight: displayHeight,
                    containerVersion: .texb0003, freeImageFormat: 2, isVideoMp4: false,
                    images: [.init(mips: [.init(width: mipWidth, height: displayHeight, data: payload)])],
                    spriteFrames: [])
            }
            guard loader.hasValidTexb3EmbeddedMipChain(container(displayWidth)),
                  !loader.hasValidTexb3EmbeddedMipChain(container(displayWidth + 1)) else {
                fatalError("container dimension proof \(orientation)")
            }
            guard let extent = loader.embeddedImagePixelSize(payload),
                  let decoded = SceneTextureMipUploader.decodeEmbeddedImages([payload]),
                  case let .loaded(texture)? = SceneTextureMipUploader.uploadEmbeddedDataImages(
                    decoded, purpose: .straightAlbedo, device: device) else {
                fatalError("orientation \(orientation) rejected")
            }
            var rgba = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
            texture.getBytes(&rgba, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            let corners = [(1, 1), (3, 1), (1, 3), (3, 3)].map { x, y -> Int in
                let offset = ((y * texture.height / 4) * texture.width + x * texture.width / 4) * 4
                return colors.indices.min { a, b in
                    func distance(_ c: Int) -> Int {
                        (0..<3).reduce(0) { $0 + abs(Int(rgba[offset + $1]) - Int(colors[c][$1])) }
                    }
                    return distance(a) < distance(b)
                }!
            }
            output.append(["orientation": orientation, "width": texture.width,
                "height": texture.height, "extentMatches": extent == CGSize(width: texture.width, height: texture.height),
                "corners": corners])
        }
        guard SceneTextureMipUploader.decodeEmbeddedImages([Data([0xFF, 0xD8, 0xFF])]) == nil,
              loader.embeddedImagePixelSize(Data([0xFF, 0xD8, 0xFF])) == nil else {
            fatalError("truncated payload admitted")
        }
        // A legal single-level TEX above the loose upload limit takes the
        // loader fallback; it must reuse the oriented decode, not raw JPEG.
        let large = CGContext(data: nil, width: 4097, height: 2, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        large.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        large.fill(CGRect(x: 0, y: 0, width: 4097, height: 2))
        let largeJPEG = NSMutableData()
        let destination = CGImageDestinationCreateWithData(largeJPEG, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, large.makeImage()!,
            [kCGImagePropertyOrientation: 6] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { fatalError("large encode") }
        var tex = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { tex.append(contentsOf: $0) }
        }
        for field: UInt32 in [0, 2, 2, 4097, 2, 4097, 0] { append(field) }
        tex.append(Data("TEXB0003\0".utf8))
        for field in [1, 2, 1, 2, 4097, 0, 0, UInt32(largeJPEG.length)] { append(field) }
        tex.append(largeJPEG as Data)
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("large-oriented.tex")
        try tex.write(to: url)
        guard case let .loaded(texture) = loader.load(from: url, purpose: .straightAlbedo, device: device),
              texture.width == 1, texture.height == 4096 else {
            fatalError("large fallback lost display orientation")
        }
        print(String(data: try JSONSerialization.data(withJSONObject: output), encoding: .utf8)!)
    }
}
'''


class EmbeddedImageOrientationTests(unittest.TestCase):
    def test_all_jpeg_orientations_preserve_extent_and_metal_corner_pixels(self):
        with tempfile.TemporaryDirectory(prefix='mwx-embedded-orientation-') as directory:
            root = Path(directory)
            source = root / 'orientation.swift'
            source.write_text(HARNESS)
            binary = root / 'orientation'
            build = subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                *map(str, SWIFT_SOURCES), str(source), '-o', str(binary)],
                capture_output=True, text=True, timeout=120)
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(binary), str(root)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            rows = json.loads(run.stdout.splitlines()[-1])
            expected = [[0, 1, 2, 3], [0, 1, 2, 3], [1, 0, 3, 2],
                        [3, 2, 1, 0], [2, 3, 0, 1], [0, 2, 1, 3],
                        [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]]
            self.assertEqual(len(rows), 9)
            for row, corners in zip(rows, expected):
                with self.subTest(orientation=row['orientation']):
                    self.assertTrue(row['extentMatches'])
                    self.assertEqual(row['corners'], corners)
                    self.assertEqual((row['width'], row['height']),
                                     (32, 48) if row['orientation'] >= 5 else (48, 32))


if __name__ == '__main__':
    unittest.main()
