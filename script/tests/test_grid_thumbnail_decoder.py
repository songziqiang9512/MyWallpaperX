"""Decode real encoded images through the production grid ImageIO boundary."""
from pathlib import Path
import json
import hashlib
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

HARNESS = r'''
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct Checks {
    static func main() {
        var checks: [String: Bool] = [:]
        func expect(_ name: String, _ passed: Bool) { checks[name] = passed }
        func encoded(_ type: String, width: Int = 1920, height: Int = 1080, orientation: Int = 1) -> Data {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 0.5)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let data = NSMutableData()
            let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!,
                [kCGImagePropertyOrientation: orientation] as CFDictionary)
            precondition(CGImageDestinationFinalize(destination))
            return data as Data
        }
        let png = encoded(UTType.png.identifier)
        let jpeg = encoded(UTType.jpeg.identifier)
        for (name, bytes) in [("png", png), ("jpeg", jpeg)] {
            let image = GridThumbnailDecoder.decode(bytes, maxPixelSize: 512)!
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            expect(name + "-sized", cg.width == 512 && cg.height == 288)
            expect(name + "-bounded-pixel-cost", cg.bytesPerRow * cg.height < 1920 * 1080 * 4 / 8)
            expect(name + "-logical-size", image.size == NSSize(width: 512, height: 288))
            let larger = GridThumbnailDecoder.decode(bytes, maxPixelSize: 800)!
                .cgImage(forProposedRect: nil, context: nil, hints: nil)!
            expect(name + "-larger-purpose", larger.width == 800 && larger.height == 450)
        }
        let rotated = GridThumbnailDecoder.decode(encoded(UTType.jpeg.identifier, orientation: 6), maxPixelSize: 512)!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        expect("orientation-applied", rotated.width >= 512 && rotated.height >= 910 &&
            abs(Double(rotated.width) / Double(rotated.height) - 1080.0 / 1920.0) < 0.005)
        let portrait = GridThumbnailDecoder.decode(encoded(UTType.png.identifier, width: 1000, height: 2000), maxPixelSize: 800)!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        expect("portrait-both-display-axes", portrait.width >= 800 && portrait.height >= 450)
        let panorama = GridThumbnailDecoder.decode(encoded(UTType.png.identifier, width: 2000, height: 400), maxPixelSize: 800)!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        expect("panorama-preserves-short-axis", panorama.width == 2000 && panorama.height == 400)
        let transparent = GridThumbnailDecoder.decode(png, maxPixelSize: 256)!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let target = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        target.draw(transparent, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let rgba = target.data!.assumingMemoryBound(to: UInt8.self)
        expect("transparency-preserved", rgba[3] > 120 && rgba[3] < 136)
        expect("bad-image-local-failure", GridThumbnailDecoder.decode(Data([1, 3, 5]), maxPixelSize: 800) == nil)
        expect("empty-local-failure", GridThumbnailDecoder.decode(Data(), maxPixelSize: 800) == nil)
        expect("retina-tier", GridThumbnailDecoder.pixelLimit(width: 300, scale: 2) == 800)
        expect("one-x-tier", GridThumbnailDecoder.pixelLimit(width: 300, scale: 1) == 512)
        expect("nearby-widths-share-tier", GridThumbnailDecoder.pixelLimit(width: 301, scale: 2) == 800)
        expect("invalid-geometry", GridThumbnailDecoder.pixelLimit(width: .nan, scale: 2) == 800)
        expect("empty-geometry", GridThumbnailDecoder.pixelLimit(width: 0, scale: 2) == 800)
        expect("upper-bound", GridThumbnailDecoder.pixelLimit(width: 10000, scale: 2) == 4096)
        print(String(data: try! JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
'''


class GridThumbnailDecoderTests(unittest.TestCase):
    def test_real_images_dimensions_orientation_alpha_and_invalid_neighbors(self):
        with tempfile.TemporaryDirectory(prefix='mwx-grid-image-', dir='/private/tmp') as directory:
            work = Path(directory)
            source = work / 'Checks.swift'
            source.write_text(HARNESS)
            binary = work / 'checks'
            environment = dict(os.environ, HOME=str(work / 'home'), CFFIXED_USER_HOME=str(work / 'home'), TMPDIR=str(work / 'tmp') + '/')
            (work / 'tmp').mkdir()
            production = ROOT / 'MyWallpaperX/Shared/UI/GridThumbnailDecoder.swift'
            inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in (production, source)}
            (work / 'home').mkdir()
            command = ['xcrun', 'swiftc', '-parse-as-library',
                str(production), str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)]
            build = subprocess.run(command,
                capture_output=True, text=True, env=environment, timeout=120)
            if proof := os.environ.get('MWX_GRID_IMAGE_PROOF_DIR'):
                output = Path(proof); output.mkdir(parents=True, exist_ok=True)
                (output / 'build.log').write_text(build.stdout + build.stderr)
                (output / 'inputs.json').write_text(json.dumps({'inputs': inputs, 'command': command}, indent=2) + '\n')
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in (production, source)})
            run = subprocess.run([str(binary)], capture_output=True, text=True, env=environment, timeout=30)
            if proof := os.environ.get('MWX_GRID_IMAGE_PROOF_DIR'):
                output = Path(proof); output.mkdir(parents=True, exist_ok=True)
                (output / 'build.log').write_text(build.stdout + build.stderr)
                (output / 'runtime.stdout').write_text(run.stdout)
                (output / 'runtime.stderr').write_text(run.stderr)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            checks = json.loads(run.stdout)
            for name, passed in checks.items():
                with self.subTest(name=name):
                    self.assertTrue(passed)


if __name__ == '__main__':
    unittest.main()
