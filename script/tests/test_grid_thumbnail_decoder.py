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
        func uncropped(_ bytes: Data, width: Int, height: Int) -> NSImage? {
            GridThumbnailDecoder.decodeInput(.sourceData(bytes), request: .init(width: width, height: height, mode: .fill))?.image
        }
        func composed(_ bytes: Data, request: ThumbnailRequest) -> NSImage? {
            GridThumbnailDecoder.decodeInput(.sourceData(bytes), request: request).flatMap {
                GridThumbnailDecoder.render($0, request: request)
            }?.image
        }
        let png = encoded(UTType.png.identifier)
        let jpeg = encoded(UTType.jpeg.identifier)
        for (name, bytes) in [("png", png), ("jpeg", jpeg)] {
            let image = uncropped(bytes, width: 512, height: 288)!
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            expect(name + "-sized", cg.width == 512 && cg.height == 288)
            expect(name + "-bounded-pixel-cost", cg.bytesPerRow * cg.height < 1920 * 1080 * 4 / 8)
            expect(name + "-logical-size", image.size == NSSize(width: 512, height: 288))
            let larger = uncropped(bytes, width: 800, height: 450)!
                .cgImage(forProposedRect: nil, context: nil, hints: nil)!
            expect(name + "-larger-purpose", larger.width == 800 && larger.height == 450)
        }
        let rotated = uncropped(encoded(UTType.jpeg.identifier, orientation: 6), width: 512, height: 288)!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        expect("orientation-applied", rotated.width >= 512 && rotated.height >= 910 &&
            abs(Double(rotated.width) / Double(rotated.height) - 1080.0 / 1920.0) < 0.005)
        let portrait = uncropped(encoded(UTType.png.identifier, width: 1000, height: 2000), width: 800, height: 450)!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        expect("portrait-both-display-axes", portrait.width >= 800 && portrait.height >= 450)
        let panorama = uncropped(encoded(UTType.png.identifier, width: 2000, height: 400), width: 800, height: 450)!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        expect("panorama-preserves-short-axis", panorama.width == 2000 && panorama.height == 400)
        let transparent = uncropped(png, width: 256, height: 144)!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let target = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        target.draw(transparent, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let rgba = target.data!.assumingMemoryBound(to: UInt8.self)
        expect("transparency-preserved", rgba[3] > 120 && rgba[3] < 136)
        expect("bad-image-local-failure", composed(Data([1, 3, 5]), request: .init(width: 800, height: 450, mode: .fill)) == nil)
        expect("empty-local-failure", composed(Data(), request: .init(width: 800, height: 450, mode: .fill)) == nil)
        expect("retina-tier", GridThumbnailDecoder.pixelLimit(width: 300, scale: 2) == 800)
        expect("one-x-tier", GridThumbnailDecoder.pixelLimit(width: 300, scale: 1) == 512)
        expect("nearby-widths-share-tier", GridThumbnailDecoder.pixelLimit(width: 301, scale: 2) == 800)
        expect("invalid-geometry", GridThumbnailDecoder.pixelLimit(width: .nan, scale: 2) == 800)
        expect("empty-geometry", GridThumbnailDecoder.pixelLimit(width: 0, scale: 2) == 800)
        expect("upper-bound", GridThumbnailDecoder.pixelLimit(width: 10000, scale: 2) == 4096)
        for (label, width, height, orientation) in [("landscape", 1920, 1080, 1), ("portrait", 800, 1600, 1),
            ("panorama", 1600, 400, 1), ("rotated", 1200, 800, 6)] {
            let bytes = encoded(UTType.png.identifier, width: width, height: height, orientation: orientation)
            let square = composed(bytes, request: .init(width: 320, height: 320, mode: .fill))
            let bitmap = square?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { NSBitmapImageRep(cgImage: $0) }
            expect("square-" + label + "-covers-both-axes-in-owned-buffer", bitmap.map {
                $0.pixelsWide == 320 && $0.pixelsHigh == 320 && $0.bytesPerRow <= 320 * 4 + 64
            } == true)
            expect("square-" + label + "-disk-is-usable-input", GridThumbnailDecoder.decodeStoredImage(bytes, request: .init(width: 320, height: 320, mode: .fill)) != nil)
            expect("square-" + label + "-keeps-alpha", bitmap?.colorAt(x: 160, y: 160).map {
                $0.alphaComponent > 0.45 && $0.alphaComponent < 0.55
            } == true)
        }
        let tiny = encoded(UTType.png.identifier, width: 96, height: 64)
        let tinyImage = composed(tiny, request: .init(width: 320, height: 320, mode: .fill))
        expect("square-small-native-source-keeps-real-short-side", tinyImage?.size == NSSize(width: 64, height: 64))
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        try! tiny.write(to: file)
        let tinyMaster = GridThumbnailDecoder.decodeInput(.sourceFile(file), request: .init(width: 32, height: 32, mode: .fill))?.image
        let tinyMasterCG = tinyMaster?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        expect("source-master-floor-never-upscales-native-small-image", tinyMasterCG.map { $0.width == 96 && $0.height == 64 } == true)
        try! png.write(to: file)
        let minimumMaster = GridThumbnailDecoder.decodeInput(.sourceFile(file), request: .init(width: 128, height: 128, mode: .fill))?.image
        let minimumMasterCG = minimumMaster?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        expect("source-master-floor-keeps-legacy-inspector-pixels", minimumMasterCG.map { $0.width == 512 && $0.height == 288 } == true)
        expect("square-small-legacy-disk-is-not-larger-target", GridThumbnailDecoder.decodeStoredImage(tiny, request: .init(width: 320, height: 320, mode: .fill)) == nil)
        expect("square-bad-disk-remains-local-miss", GridThumbnailDecoder.decodeStoredImage(Data([1, 3, 5]), request: .init(width: 320, height: 320, mode: .fill)) == nil)
        let stripes = CGContext(data: nil, width: 1024, height: 320, bitsPerComponent: 8,
            bytesPerRow: 1024 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<1024 {
            stripes.setFillColor((x.isMultiple(of: 2) ? NSColor.red : .blue).cgColor)
            stripes.fill(CGRect(x: x, y: 0, width: 1, height: 320))
        }
        let striped = GridThumbnailDecoder.render(GridThumbnailDecoder.Image(NSImage(cgImage: stripes.makeImage()!, size: .zero), nativeSize: nil)!, request: .init(width: 320, height: 320, mode: .fill))?.image
        let stripedRep = striped?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { NSBitmapImageRep(cgImage: $0) }
        let even = stripedRep?.colorAt(x: 20, y: 160)?.usingColorSpace(.deviceRGB)
        let odd = stripedRep?.colorAt(x: 21, y: 160)?.usingColorSpace(.deviceRGB)
        expect("square-native-pixel-crop-keeps-high-frequency-center-detail", even.map { $0.redComponent > 0.9 && $0.blueComponent < 0.1 } == true
            && odd.map { $0.blueComponent > 0.9 && $0.redComponent < 0.1 } == true)
        expect("square-copy-does-not-retain-wide-row-stride", stripedRep.map { $0.bytesPerRow * $0.pixelsHigh <= (320 * 4 + 64) * 320 } == true)
        let extendedSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let floating = CGContext(data: nil, width: 640, height: 320, bitsPerComponent: 32,
            bytesPerRow: 640 * 16, space: extendedSpace,
            bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        floating.setFillColor(CGColor(colorSpace: extendedSpace, components: [1.25, 0.2, 0.1, 1])!)
        floating.fill(CGRect(x: 0, y: 0, width: 640, height: 320))
        let floatImage = GridThumbnailDecoder.render(GridThumbnailDecoder.Image(NSImage(cgImage: floating.makeImage()!, size: .zero), nativeSize: nil)!, request: .init(width: 160, height: 160, mode: .fill))?.image
        let floatCG = floatImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        expect("square-float-input-keeps-component-depth-and-color-space", floatCG.map {
            $0.width == 160 && $0.height == 160 && $0.bitsPerComponent == 32 && $0.bitmapInfo.contains(.floatComponents)
                && $0.colorSpace?.name == CGColorSpace.extendedLinearSRGB
        } == true)
        let floatReadback = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 32, bytesPerRow: 16, space: extendedSpace,
            bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        if let floatCG { floatReadback.draw(floatCG, in: CGRect(x: 0, y: 0, width: 1, height: 1)) }
        expect("square-float-output-retains-extended-red-value", floatReadback.data!.assumingMemoryBound(to: Float.self)[0] > 1.1)
        let rectangle = ThumbnailRequest(size: CGSize(width: 300, height: 156), scale: 2, mode: .fill)
        expect("request-keeps-real-rectangle-ratio", rectangle == .init(width: 600, height: 312, mode: .fill))
        expect("request-defers-zero-or-invalid-layout", ThumbnailRequest(size: .zero, scale: 2, mode: .fit) == nil
            && ThumbnailRequest(size: CGSize(width: 10, height: 10), scale: .nan, mode: .fill) == nil)
        let bands = CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8, bytesPerRow: 3200,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (x, width, color) in [(0, 200, NSColor.red), (200, 400, .green), (600, 200, .blue)] {
            bands.setFillColor(color.cgColor); bands.fill(CGRect(x: x, y: 0, width: width, height: 400))
        }
        let bandsData = NSMutableData()
        let bandsDestination = CGImageDestinationCreateWithData(bandsData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(bandsDestination, bands.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(bandsDestination))
        func bitmap(_ image: NSImage?) -> NSBitmapImageRep? {
            image?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { NSBitmapImageRep(cgImage: $0) }
        }
        let fit = bitmap(composed(bandsData as Data, request: .init(width: 320, height: 320, mode: .fit)))
        expect("fit-preserves-full-frame-and-aspect", fit?.pixelsWide == 320 && fit?.pixelsHigh == 160
            && (fit?.colorAt(x: 0, y: 80)?.redComponent ?? 0) > 0.9
            && (fit?.colorAt(x: 319, y: 80)?.blueComponent ?? 0) > 0.9)
        let filled = bitmap(composed(bandsData as Data, request: .init(width: 320, height: 320, mode: .fill)))
        expect("fill-crops-center-instead-of-stretching-full-frame", filled?.pixelsWide == 320 && filled?.pixelsHigh == 320
            && (filled?.colorAt(x: 5, y: 160)?.greenComponent ?? 0) > 0.9
            && (filled?.colorAt(x: 314, y: 160)?.greenComponent ?? 0) > 0.9)
        let wide = bitmap(composed(bandsData as Data, request: rectangle!))
        expect("rectangular-fill-keeps-requested-composition", wide?.pixelsWide == 600 && wide?.pixelsHigh == 312
            && (wide?.colorAt(x: 0, y: 156)?.redComponent ?? 0) > 0.9
            && (wide?.colorAt(x: 599, y: 156)?.blueComponent ?? 0) > 0.9)
        try! tiny.write(to: file)
        let squareRequest = ThumbnailRequest(width: 320, height: 320, mode: .fill)
        let fitRequest = ThumbnailRequest(width: 576, height: 576, mode: .fit)
        expect("fit-accepts-one-raster-pixel-rounding", fitRequest.isCovered(by: CGSize(width: 575, height: 324)))
        expect("fit-rejects-two-raster-pixels-short", !fitRequest.isCovered(by: CGSize(width: 574, height: 324)))
        expect("fill-accepts-one-raster-pixel-per-axis", squareRequest.isCovered(by: CGSize(width: 319, height: 319)))
        expect("fill-rejects-two-raster-pixels-short", !squareRequest.isCovered(by: CGSize(width: 318, height: 320)))
        expect("native-cap-accepts-one-raster-pixel-rounding", squareRequest.isCovered(by: CGSize(width: 95, height: 63), nativeSize: CGSize(width: 96, height: 64)))
        expect("native-cap-rejects-two-raster-pixels-short", !squareRequest.isCovered(by: CGSize(width: 94, height: 62), nativeSize: CGSize(width: 96, height: 64)))
        expect("unknown-small-prepared-file-is-not-native-proof", GridThumbnailDecoder.decodeInput(.preparedFile(file, nativeSize: nil), request: squareRequest) == nil)
        let capped = GridThumbnailDecoder.decodeInput(.preparedFile(file, nativeSize: CGSize(width: 96, height: 64)), request: squareRequest)
        expect("real-native-cap-allows-small-prepared-final", capped.flatMap { GridThumbnailDecoder.render($0, request: squareRequest) }?.pixels == CGSize(width: 64, height: 64))
        try! encoded(UTType.jpeg.identifier, width: 575, height: 324).write(to: file)
        let roundedFit = GridThumbnailDecoder.decodeInput(.preparedFile(file, nativeSize: CGSize(width: 1280, height: 720)), request: fitRequest)
        expect("rounded-AV-size-finishes-with-truthful-pixels-and-native-metadata", roundedFit?.pixels == CGSize(width: 575, height: 324)
            && roundedFit?.nativeSize == CGSize(width: 1280, height: 720)
            && roundedFit.flatMap { GridThumbnailDecoder.render($0, request: fitRequest) }?.pixels == CGSize(width: 575, height: 324))
        try! encoded(UTType.jpeg.identifier, width: 574, height: 324).write(to: file)
        expect("two-pixel-short-prepared-JPEG-remains-a-miss", GridThumbnailDecoder.decodeInput(.preparedFile(file, nativeSize: CGSize(width: 1280, height: 720)), request: fitRequest) == nil)
        let legacyMaster = encoded(UTType.jpeg.identifier, width: 400, height: 225)
        try! legacyMaster.write(to: file)
        expect("old-400-master-does-not-prove-native-225-cap", GridThumbnailDecoder.decodeInput(.preparedFile(file, nativeSize: nil), request: squareRequest) == nil
            && GridThumbnailDecoder.decodeInput(.preparedFile(file, nativeSize: CGSize(width: 1280, height: 720)), request: squareRequest) == nil)
        try! tiny.write(to: file)
        var failures = 0
        expect("source-input-records-native-without-failure-stat", GridThumbnailDecoder.decodeInput(.sourceFile(file, onFailure: { failures += 1 }), request: squareRequest)?.nativeSize == CGSize(width: 96, height: 64) && failures == 0)
        try! Data([0, 1, 2]).write(to: file)
        expect("source-failure-hook-runs-only-on-actual-source-failure", GridThumbnailDecoder.decodeInput(.sourceFile(file, onFailure: { failures += 1 }), request: squareRequest) == nil && failures == 1)
        _ = GridThumbnailDecoder.decodeInput(.preparedFile(file, nativeSize: nil), request: squareRequest)
        expect("prepared-cache-miss-does-not-call-source-failure-hook", failures == 1)
        let dataInput = GridThumbnailDecoder.decodeInput(.sourceData(tiny), request: squareRequest)
        expect("encoded-source-records-real-native-cap", dataInput?.nativeSize == CGSize(width: 96, height: 64)
            && dataInput.flatMap { GridThumbnailDecoder.render($0, request: squareRequest) }?.pixels == CGSize(width: 64, height: 64))
        let rotatedData = encoded(UTType.jpeg.identifier, width: 400, height: 200, orientation: 6)
        let rotatedInput = GridThumbnailDecoder.decodeInput(.sourceData(rotatedData), request: fitRequest)
        expect("encoded-source-orientation-keeps-full-fit-frame", rotatedInput?.nativeSize == CGSize(width: 200, height: 400)
            && rotatedInput?.pixels == CGSize(width: 200, height: 400) && rotatedInput?.crop == nil)
        expect("corrupt-encoded-source-is-not-a-ready-image", GridThumbnailDecoder.decodeInput(.sourceData(Data([0, 1, 2])), request: squareRequest) == nil)
        let pdf = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 200)
        let pdfContext = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &box, nil)!
        pdfContext.beginPDFPage(nil)
        pdfContext.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); pdfContext.fill(box)
        pdfContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        pdfContext.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        pdfContext.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        pdfContext.fill(CGRect(x: 300, y: 0, width: 100, height: 200))
        pdfContext.endPDFPage(); pdfContext.closePDF()
        let pdfSource = CGImageSourceCreateWithData(pdf as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary)
        let unconstrainedPDF = GridThumbnailDecoder.decodeInput(.sourceData(pdf as Data), request: nil)
        let fitPDF = GridThumbnailDecoder.decodeInput(.sourceData(pdf as Data),
            request: ThumbnailRequest(width: 800, height: 600, mode: .fit))
        let fillPDF = GridThumbnailDecoder.decodeInput(.sourceData(pdf as Data),
            request: ThumbnailRequest(width: 300, height: 300, mode: .fill))
        expect("unsupported-ImageIO-PDF-remains-a-local-miss", pdfSource != nil
            && unconstrainedPDF == nil && fitPDF == nil && fillPDF == nil)
        let pdfFacts: [String: Any] = ["ImageIOSource": pdfSource != nil,
            "unconstrainedPixels": unconstrainedPDF.map { [Int($0.pixels.width), Int($0.pixels.height)] } ?? [],
            "fitPixels": fitPDF.map { [Int($0.pixels.width), Int($0.pixels.height)] } ?? [],
            "fillPixels": fillPDF.map { [Int($0.pixels.width), Int($0.pixels.height)] } ?? []]
        FileHandle.standardError.write(Data(("PDF decoder comparison: " + String(data: try! JSONSerialization.data(withJSONObject: pdfFacts, options: [.sortedKeys]), encoding: .utf8)! + "\n").utf8))
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
            production = [ROOT / 'MyWallpaperX/Shared/ThumbnailRequest.swift', ROOT / 'MyWallpaperX/Shared/UI/GridThumbnailDecoder.swift']
            inputs = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in (*production, source)}
            (work / 'home').mkdir()
            command = ['xcrun', 'swiftc', '-parse-as-library',
                *map(str, production), str(source), '-module-cache-path', str(work / 'modules'), '-o', str(binary)]
            build = subprocess.run(command,
                capture_output=True, text=True, env=environment, timeout=120)
            if proof := os.environ.get('MWX_GRID_IMAGE_PROOF_DIR'):
                output = Path(proof); output.mkdir(parents=True, exist_ok=True)
                (output / 'build.log').write_text(build.stdout + build.stderr)
                (output / 'inputs.json').write_text(json.dumps({'inputs': inputs, 'command': command}, indent=2) + '\n')
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            self.assertEqual(inputs, {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in (*production, source)})
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
