"""Native paragraph bounds keep real text ink and static/dynamic agreement.

Only the descriptor DTO and unused parse methods are doubled. The source
owners below provide real Root input, font, layout, raster and Metal allocation.
No App is launched. A host where CoreText fixes the original paragraph issue
must still pass: native failure is observed, never required by font identity.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FONT_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/fonts"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Resources/Assets/SceneResourceIndex.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceView.swift",
    SOURCE_ROOT / "../SteamWorkshopStorage/ScenePlaybackSource.swift",
    SOURCE_ROOT / "Format/ScenePkgReader.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceIdentity.swift",
    SOURCE_ROOT / "Resources/Assets/SceneResourceView+Backing.swift",
    SOURCE_ROOT / "Systems/Text/SceneTextDescriptor.swift",
    SOURCE_ROOT / "Systems/Text/SceneTextFontResolver.swift",
    SOURCE_ROOT / "Systems/Text/SceneTextGeometry.swift",
    SOURCE_ROOT / "Systems/Text/SceneTextRowLimit.swift",
    SOURCE_ROOT / "Systems/Text/SceneTextTextureLoader.swift",
    SOURCE_ROOT / "Resources/Textures/SceneResourceBudget.swift",
]


def fixture_cases():
    base = {"fontPath": "fonts/spincycle_3d_ot.otf", "content": "12:34",
            "color": [1, 1, 1], "pointSize": 119.153, "limitWidth": False,
            "maxWidth": 500, "limitRows": False, "maxRows": 1, "useEllipsis": False}
    variations = [
        ("stock-black", {"color": [0, 0, 0]}),
        ("stock-white", {}),
        ("renamed-embedded-black", {"fontPath": "fonts/owned-renamed-clock.otf", "color": [0, 0, 0]}),
        ("short-clock", {"content": "7:05"}),
        ("renamed-word", {"fontPath": "fonts/owned-renamed-clock.otf", "content": "Hamburg0123"}),
        ("arial-neighbor", {"fontPath": "systemfont_arial", "color": [0, 0, 0]}),
        ("atami-neighbor", {"fontPath": "fonts/Atami-Regular.otf"}),
        ("empty", {"content": ""}),
        ("spaces", {"content": "   "}),
        ("width-limited", {"content": "Hamburg0123 Hamburg0123", "pointSize": 32,
                           "limitWidth": True, "maxWidth": 400}),
        ("last-row", {"content": "12:34 7:05 Hamburg0123", "pointSize": 32,
                      "limitWidth": True, "maxWidth": 400, "limitRows": True}),
        ("last-row-ellipsis", {"content": "12:34 7:05 Hamburg0123", "pointSize": 32,
                               "limitWidth": True, "maxWidth": 400, "limitRows": True,
                               "useEllipsis": True}),
    ]
    return [base | fields | {"id": index + 101, "name": name}
            for index, (name, fields) in enumerate(variations)]


HARNESS = r'''
import CoreGraphics
import CoreText
import CryptoKit
import Darwin
import Foundation
import Metal

enum SceneDocumentLoader {
    static func floatVector(_ raw: Any?) -> [Float]? { fatalError("No parsing in typed fixture") }
    static func floatValue(_ raw: Any?) -> Float? { fatalError("No parsing in typed fixture") }
}
struct SceneRenderDescriptor {
    struct Layer {
        let id: Int
        let contentKind: String
        let name: String?
        let text: String?
        let textStyle: SceneTextDescriptor?
    }
    let layers: [Layer]
}

@main enum NativeBoundsProbe {
    struct Input: Decodable {
        let id: Int
        let name, content, fontPath: String
        let color: [Float]
        let pointSize, maxWidth: Float
        let limitWidth, limitRows, useEllipsis: Bool
        let maxRows: Int
    }

    static func bytes(_ texture: MTLTexture) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&result, bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        return result
    }

    static func statistics(_ raster: SceneTextTextureLoader.RasterizedTexture,
                           pixels: [UInt8]) -> [String: Any] {
        let width = raster.texture.width, height = raster.texture.height
        var count = 0, minX = width, minY = height, maxX = -1, maxY = -1
        var alpha: [UInt8] = []
        alpha.reserveCapacity(width * height)
        for y in 0..<height { for x in 0..<width {
            let coverage = pixels[(y * width + x) * 4 + 3]
            alpha.append(coverage)
            if coverage > 0 {
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        } }
        func digest(_ value: [UInt8]) -> String {
            SHA256.hash(data: Data(value)).map { String(format: "%02x", $0) }.joined()
        }
        return ["size": [width, height], "logicalSize": raster.renderSizeWH,
            "centerOffsetY": raster.centerOffsetY, "alphaPixels": count,
            "inkBounds": [minX, minY, maxX, maxY],
            "pixelSHA256": digest(pixels), "alphaSHA256": digest(alpha)]
    }

    // A no-paragraph CTLine is independent of the product's paragraph policy.
    // Place its measured ink inside a padded bitmap; no wrapping is reimplemented.
    static func independentInk(_ content: String, font: CTFont) -> [String: Any] {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: content, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let hasInkExtent = !bounds.isNull && bounds.width > 0 && bounds.height > 0
        let width = hasInkExtent ? Int(ceil(bounds.width)) + 64 : 64
        let height = hasInkExtent ? Int(ceil(bounds.height)) + 64 : 64
        precondition(width > 0 && height > 0 && width <= 16_384 && height <= 16_384)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { pointer in
            guard let context = CGContext(data: pointer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            else { fatalError("Native positive context unavailable") }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.textMatrix = .identity
            context.textPosition = hasInkExtent
                ? CGPoint(x: 32 - bounds.minX, y: 32 - bounds.minY) : CGPoint(x: 32, y: 32)
            CTLineDraw(line, context)
        }
        let count = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
        return ["alphaPixels": count, "glyphCount": CTLineGetGlyphCount(line), "size": [width, height]]
    }

    // Build the native paragraph directly, independently of LineBounds selection.
    // Actual glyph positions observe the native failure instead of requiring it
    // to occur on every future CoreText version.
    static func nativeParagraphFacts(_ content: String, font: CTFont) -> [String: Any] {
        var alignment = CTTextAlignment.natural
        var wrap = CTLineBreakMode.byWordWrapping
        var bounds = CTLineBoundsOptions.useGlyphPathBounds
        let paragraph = withUnsafePointer(to: &alignment) { ap in
            withUnsafePointer(to: &wrap) { wp in
                withUnsafePointer(to: &bounds) { bp in
                    let settings = [
                        CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: ap),
                        CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: wp),
                        CTParagraphStyleSetting(spec: .lineBoundsOptions, valueSize: MemoryLayout<CTLineBoundsOptions>.size, value: bp)]
                    return CTParagraphStyleCreate(settings, settings.count)
                }
            }
        }
        let text = NSAttributedString(string: content, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph])
        let line = CTLineCreateWithAttributedString(text)
        var representable = true, glyphCount = 0
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            glyphCount += count
            for point in positions {
                representable = representable && Float(point.x).isFinite && Float(point.y).isFinite
            }
        }
        return ["positionsRepresentable": representable, "glyphCount": glyphCount]
    }

    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let resourceView = SceneResourceView(projectRoot: .init(source: .loose, url: directory),
            packageRoot: nil, stockRoot: nil)
        let inputs = try JSONDecoder().decode([Input].self,
            from: Data(contentsOf: directory.appendingPathComponent("fixture.json")))
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("{\"metalAvailable\":false}"); return
        }
        let layers = inputs.map { value in
            let style = SceneTextDescriptor(fontPath: value.fontPath, pointSize: value.pointSize,
                colorRGB: value.color, brightness: 1, horizontalAlignment: "center",
                verticalAlignment: "center", screenAnchor: "none", padding: 32,
                limitRows: value.limitRows, maxRows: value.maxRows, limitWidth: value.limitWidth,
                maxWidth: value.maxWidth, useEllipsis: value.useEllipsis, opaqueBackground: false,
                backgroundColorRGB: [0, 0, 0], backgroundBrightness: 1, outline: nil, dropShadow: nil)
            return SceneRenderDescriptor.Layer(id: value.id, contentKind: "text", name: value.name,
                text: value.content, textStyle: style)
        }
        let loaded = SceneTextTextureLoader.load(descriptor: .init(layers: layers),
            resourceView: resourceView, device: device)
        var result: [String: Any] = [:]
        for (value, layer) in zip(inputs, layers) {
            guard let style = layer.textStyle, let initial = loaded.rasters[layer.id],
                  let dynamic = try SceneTextTextureLoader.makeDynamicTexture(for: layer,
                    content: value.content, fontPath: value.fontPath, pointSize: value.pointSize,
                    colorRGB: value.color, maxWidth: value.maxWidth,
                    resourceView: resourceView, device: device)
            else { fatalError("Missing real raster for \(value.name)") }
            let initialPixels = bytes(initial.texture), dynamicPixels = bytes(dynamic.texture)
            let resolution = try SceneTextFontResolver.resolve(path: value.fontPath,
                size: CGFloat(SceneTextGeometry.pointSizeInPixels(value.pointSize)), resourceView: resourceView)
            let policy = SceneTextRowLimit.lineBounds(text: value.content, font: resolution.font,
                useEllipsis: value.useEllipsis)
            let qualificationText = value.content + (value.useEllipsis ? "…" : "")
            result[value.name] = [
                "initial": statistics(initial, pixels: initialPixels),
                "dynamic": statistics(dynamic, pixels: dynamicPixels),
                "samePixels": initialPixels == dynamicPixels,
                "sameLogicalSize": initial.renderSizeWH == dynamic.renderSizeWH,
                "fontSource": resolution.source, "postScriptName": resolution.postScriptName,
                "policy": policy == .glyphPath ? "glyphPath" : "typographic",
                "nativePositive": independentInk(value.content, font: resolution.font),
                "nativeParagraph": nativeParagraphFacts(qualificationText, font: resolution.font),
                "limitWidth": style.limitWidth, "limitRows": style.limitRows]
        }
        // Observe the real font FD at cancellation checkpoints, without a
        // product hook or resolver double. One open interval is one payload read.
        let observedPaths = Set(["owned-renamed-clock.otf", "alternate.otf", "invalid.otf"].map {
            directory.appendingPathComponent("fonts/" + $0)
                .resolvingSymlinksInPath().standardizedFileURL.path
        })
        var readStarts = 0, wasOpen = false
        func observeRead() {
            let isOpen = (3..<256).contains { descriptor in
                var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                return fcntl(Int32(descriptor), F_GETPATH, &path) == 0
                    && observedPaths.contains(String(cString: path))
            }
            if isOpen && !wasOpen { readStarts += 1 }
            wasOpen = isOpen
        }
        let layer = layers.first { $0.textStyle?.fontPath == "fonts/owned-renamed-clock.otf" }!
        let style = layer.textStyle!
        func render(_ text: String, path: String = "fonts/owned-renamed-clock.otf",
                    size: Float = 32, color: [Float] = [1, 1, 1], width: Float = 500,
                    font: SceneTextFontResolver.Resolution? = nil)
            throws -> SceneTextTextureLoader.RasterizedTexture {
            guard let raster = try SceneTextTextureLoader.makeDynamicTexture(for: layer,
                content: text, fontPath: path, pointSize: size, colorRGB: color,
                maxWidth: width, resourceView: resourceView, preparedFont: font, device: device,
                checkCancellation: observeRead) else { fatalError("font reuse raster failed") }
            return raster
        }
        let initial = try render("12:34")
        let afterInitial = readStarts
        let changed = try render("7:05", color: [0.2, 0.8, 0.3], width: 300, font: initial.sourceFont)
        let afterContent = readStarts
        let resized = try render("12:34", size: 512, font: changed.sourceFont)
        let afterSize = readStarts
        let alternate = try render("12:34", path: "fonts/alternate.otf", font: resized.sourceFont)
        let afterPath = readStarts
        let invalid = try render("12:34", path: "fonts/invalid.otf", font: alternate.sourceFont)
        let afterInvalid = readStarts
        let invalidReused = try render("7:05", path: "fonts/invalid.otf", font: invalid.sourceFont)
        let afterFallbackReuse = readStarts
        let fresh = try render("12:34", size: 512)
        let fontReuse: [String: Any] = [
            "reads": [afterInitial, afterContent, afterSize, afterPath, afterInvalid, afterFallbackReuse],
            "contentUsesSameFont": changed.sourceFont.font === initial.sourceFont.font,
            "sizeUsesOriginalSourceSize": CTFontGetSize(resized.sourceFont.font)
                == CGFloat(SceneTextGeometry.pointSizeInPixels(512)),
            "resizedMatchesFreshPixels": bytes(resized.texture) == bytes(fresh.texture),
            "resizedMatchesFreshGeometry": resized.renderSizeWH == fresh.renderSizeWH,
            "pathChangesTypeface": alternate.sourceFont.postScriptName != initial.sourceFont.postScriptName,
            "invalidFallback": invalid.sourceFont.diagnostic == "invalidBundledFont",
            "fallbackReuse": invalidReused.sourceFont.font === invalid.sourceFont.font,
            "freshAttemptReadsCurrentFont": readStarts == afterFallbackReuse + 1,
            "initialRastersCarrySourceSize": CTFontGetSize(loaded.rasters[layer.id]!.sourceFont.font)
                == CGFloat(SceneTextGeometry.pointSizeInPixels(style.pointSize)),
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: [
            "metalAvailable": true, "cases": result, "messages": loaded.messages, "fontReuse": fontReuse],
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneTextNativeBoundsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        temporary = tempfile.TemporaryDirectory(prefix="mwx-native-text-bounds-")
        cls.addClassCleanup(temporary.cleanup)
        root = Path(temporary.name)
        stock = root / "SceneStockAssets.bundle/assets/fonts"
        embedded = root / "fonts"
        stock.mkdir(parents=True)
        embedded.mkdir()
        for name in ("spincycle_3d_ot.otf", "Atami-Regular.otf"):
            shutil.copy2(FONT_ROOT / name, stock / name)
        shutil.copy2(FONT_ROOT / "spincycle_3d_ot.otf", embedded / "owned-renamed-clock.otf")
        shutil.copy2(FONT_ROOT / "Atami-Regular.otf", embedded / "alternate.otf")
        (embedded / "invalid.otf").write_bytes(b"invalid author font")
        fixture, harness, binary = root / "fixture.json", root / "Harness.swift", root / "probe"
        fixture.write_text(json.dumps(fixture_cases(), sort_keys=True), encoding="utf-8")
        harness.write_text(HARNESS, encoding="utf-8")
        inputs = [*SWIFT_SOURCES, FONT_ROOT / "spincycle_3d_ot.otf", FONT_ROOT / "Atami-Regular.otf",
                  fixture, harness, Path(__file__).resolve()]
        before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        command = ["xcrun", "--sdk", "macosx", "swiftc", *map(str, SWIFT_SOURCES),
                   str(harness), "-module-cache-path", str(root / "module-cache"),
                   "-framework", "Metal", "-framework", "CoreText", "-o", str(binary)]
        identity = {"compileCommand": command, "inputs": before,
                    "renamedFontSHA256": hashlib.sha256((embedded / "owned-renamed-clock.otf").read_bytes()).hexdigest(),
                    "boundary": "one compile/run, real Root/font/raster closure; no App and no official ink parity"}
        try:
            compilation = subprocess.run(command, capture_output=True, text=True, timeout=120)
            (root / "compile.log").write_text(compilation.stdout + compilation.stderr)
            if compilation.returncode:
                raise RuntimeError(compilation.stdout + compilation.stderr)
            completed = subprocess.run([str(binary), str(root)], capture_output=True, text=True, timeout=60)
            (root / "result.json").write_text(completed.stdout)
            (root / "stderr.log").write_text(completed.stderr)
            identity["exit"] = completed.returncode
            identity["binarySHA256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
            if completed.returncode:
                raise RuntimeError(completed.stderr)
            cls.result = json.loads(completed.stdout)
            if not cls.result["metalAvailable"]:
                raise unittest.SkipTest("Metal unavailable")
            after = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
            identity["inputsUnchanged"] = before == after
            if before != after:
                raise RuntimeError("Raster source changed during the standalone probe")
        finally:
            (root / "identity.json").write_text(json.dumps(identity, indent=2))
            if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                saved = Path(destination) / "test_scene_text_native_bounds"
                saved.mkdir(parents=True, exist_ok=True)
                for name in ("fixture.json", "Harness.swift", "compile.log", "result.json", "stderr.log", "identity.json"):
                    if (root / name).exists():
                        shutil.copy2(root / name, saved / name)

    def test_known_text_has_independent_native_ink_and_real_visible_rasters(self):
        for name, row in self.result["cases"].items():
            if name in ("empty", "spaces"):
                continue
            with self.subTest(case=name):
                self.assertGreater(row["nativePositive"]["alphaPixels"], 0, row)
                self.assertGreater(row["initial"]["alphaPixels"], 0, row)
                self.assertGreater(row["dynamic"]["alphaPixels"], 0, row)
                # A fixed OS is not required to reproduce the native sentinel.
                if not row["nativeParagraph"]["positionsRepresentable"]:
                    self.assertEqual(row["policy"], "typographic", row)

    def test_initial_and_same_content_dynamic_pixels_and_geometry_agree(self):
        for name, row in self.result["cases"].items():
            with self.subTest(case=name):
                self.assertTrue(row["samePixels"], row)
                self.assertTrue(row["sameLogicalSize"], row)
                self.assertEqual(row["initial"], row["dynamic"], row)

    def test_same_font_bytes_are_independent_of_resource_spelling_and_ink_color(self):
        cases = self.result["cases"]
        stock, renamed, white = [cases[name] for name in
                                 ("stock-black", "renamed-embedded-black", "stock-white")]
        self.assertEqual(stock["postScriptName"], renamed["postScriptName"])
        self.assertEqual(renamed["fontSource"], "embedded")
        self.assertEqual(stock["initial"], renamed["initial"])
        self.assertEqual(stock["policy"], renamed["policy"])
        self.assertEqual(stock["initial"]["alphaSHA256"], white["initial"]["alphaSHA256"])
        self.assertNotEqual(stock["initial"]["pixelSHA256"], white["initial"]["pixelSHA256"])

    def test_empty_and_whitespace_sources_stay_legal_without_false_fallback(self):
        for name in ("empty", "spaces"):
            with self.subTest(case=name):
                row = self.result["cases"][name]
                self.assertEqual(row["nativePositive"]["alphaPixels"], 0, row)
                self.assertEqual(row["initial"]["alphaPixels"], 0, row)
                self.assertEqual(row["policy"], "glyphPath", row)

    def test_width_and_final_row_paths_are_visible_and_consistent_only(self):
        # These counters do not promote degraded fallback to official ink-fit
        # parity. The existing Arial narrow-ink and ellipsis gates stay separate.
        for name in ("width-limited", "last-row", "last-row-ellipsis"):
            with self.subTest(case=name):
                row = self.result["cases"][name]
                self.assertTrue(row["limitWidth"], row)
                self.assertEqual(row["limitRows"], name != "width-limited", row)
                self.assertGreater(row["initial"]["alphaPixels"], 0, row)
                self.assertTrue(row["samePixels"], row)

    def test_current_raster_reuses_real_source_font_until_path_changes(self):
        facts = self.result["fontReuse"]
        self.assertEqual(facts["reads"], [1, 1, 1, 2, 3, 3], facts)
        for key, value in facts.items():
            if key != "reads":
                self.assertTrue(value, key)


if __name__ == "__main__":
    unittest.main()
