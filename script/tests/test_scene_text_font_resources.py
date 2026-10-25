"""Real font bytes, literal Root selection and initial raster reuse; no App."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_text_native_bounds import SWIFT_SOURCES as RASTER_SOURCES
from script.tests.scene_pkg_fixture import make_package


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FONT_ROOT = ROOT / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/fonts"
SOURCES = [SCENE / path for path in (
    "../SteamWorkshopStorage/ScenePlaybackSource.swift",
    "Format/ScenePkgReader.swift",
    "Resources/Assets/SceneResourceIdentity.swift",
    "Resources/Assets/SceneResourceView+Backing.swift",
    "Resources/Assets/SceneResourceIndex.swift",
    "Resources/Assets/SceneResourceView.swift",
    "Systems/Text/SceneTextFontResolver.swift",
)]

HARNESS = r'''
import CoreGraphics
import CoreText
import CryptoKit
import Darwin
import Foundation

@main enum FontResources {
    enum Stop: Error { case originalCancellation }

    static func opened(_ url: URL) -> Bool {
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        for descriptor in 3..<256 {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if fcntl(Int32(descriptor), F_GETPATH, &buffer) == 0,
               URL(fileURLWithPath: String(cString: buffer))
                .resolvingSymlinksInPath().standardizedFileURL.path == target { return true }
        }
        return false
    }

    static func ink(_ font: CTFont) -> [String: Any] {
        let width = 400, height = 100
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let text = NSAttributedString(string: "12:34", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            ])
            context.textPosition = CGPoint(x: 10, y: 25)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        return ["alphaPixels": alpha.filter { $0 > 0 }.count,
            "alphaSHA256": SHA256.hash(data: Data(alpha)).map { String(format: "%02x", $0) }.joined()]
    }

    static func result(_ path: String?, root: SceneResourceView.Root?,
                       packageRoot: SceneResourceView.Root? = nil) throws -> [String: Any] {
        let view = root.map { SceneResourceView(projectRoot: $0, packageRoot: packageRoot, stockRoot: nil) }
        let font = try SceneTextFontResolver.resolve(path: path, size: 32, resourceView: view)
        return ["source": font.source, "diagnostic": font.diagnostic ?? "",
            "postScriptName": font.postScriptName, "ink": ink(font.font)]
    }

    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let authorURL = directory.appendingPathComponent("author", isDirectory: true)
        let root = SceneResourceView.Root(source: .package, url: authorURL)
        let view = SceneResourceView(projectRoot: root, packageRoot: nil, stockRoot: nil)
        let badRoot = SceneResourceView.Root(source: .package,
            url: directory.appendingPathComponent("bad", isDirectory: true))
        var cases: [String: Any] = [:]
        for (name, path) in [
            ("renamed", "fonts/owned-clock.otf"),
            ("backslash", "fonts\\owned-clock.otf"),
            ("dot", "./fonts/owned-clock.otf"),
            ("hidden", ".hidden/clock.otf"),
            ("stock", "fonts/spincycle_3d_ot.otf"),
            ("missing", "fonts/absent.otf"),
            ("parentComponent", "fonts/sub/../owned-clock.otf"),
            ("emptyComponent", "fonts//owned-clock.otf"),
            ("invalidAbsolute", "/fonts/owned-clock.otf"),
            ("alias", "systemfont_arial"),
            ("unknownAlias", "systemfont_owned_unknown")
        ] { cases[name] = try result(path, root: root) }
        cases["default"] = try result(nil, root: root)
        cases["selectedBad"] = try result("fonts/spincycle_3d_ot.otf", root: badRoot)
        cases["noAuthorRoot"] = try result("fonts/spincycle_3d_ot.otf", root: nil)

        let link = directory.appendingPathComponent("author-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: authorURL)
        let captured = SceneResourceView.Root(source: .package, url: link)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link,
            withDestinationURL: directory.appendingPathComponent("other", isDirectory: true))
        var retargetRejected = false
        do { _ = try result("fonts/owned-clock.otf", root: captured) }
        catch SceneResourceView.ReadError.sourceChanged { retargetRejected = true }

        let mutable = authorURL.appendingPathComponent("fonts/mutable.otf")
        let original = try Data(contentsOf: mutable)
        let replacement = try Data(contentsOf: directory.appendingPathComponent("replacement.otf"))
        var replacedWhileOpen = false, changedRejected = false
        do {
            _ = try SceneTextFontResolver.resolve(path: "fonts/mutable.otf", size: 32,
                resourceView: view, checkCancellation: {
                    if !replacedWhileOpen, opened(mutable) {
                        replacedWhileOpen = true
                        try replacement.write(to: mutable, options: .atomic)
                    }
                })
        } catch SceneResourceView.ReadError.sourceChanged { changedRejected = true }
        try original.write(to: mutable, options: .atomic)
        cases["recovered"] = try result("fonts/mutable.otf", root: root)

        var cancellationReachedOpenFD = false, originalCancellationPreserved = false
        do {
            _ = try SceneTextFontResolver.resolve(path: "fonts/mutable.otf", size: 32,
                resourceView: view, checkCancellation: {
                    if opened(mutable) {
                        cancellationReachedOpenFD = true
                        throw Stop.originalCancellation
                    }
                })
        } catch Stop.originalCancellation { originalCancellationPreserved = true }

        let escaping = authorURL.appendingPathComponent("fonts/escape.otf")
        try FileManager.default.createSymbolicLink(at: escaping,
            withDestinationURL: directory.appendingPathComponent("replacement.otf"))
        var escapeRejected = false
        do { _ = try result("fonts/escape.otf", root: root) }
        catch SceneResourceView.ReadError.symlinkEscape { escapeRejected = true }
        var parentEscapeRejected = false
        do { _ = try result("../replacement.otf", root: root) }
        catch SceneResourceView.ReadError.symlinkEscape { parentEscapeRejected = true }
        let looseRoot = SceneResourceView.Root(source: .loose,
            url: directory.appendingPathComponent("other", isDirectory: true))
        let completeView = SceneResourceView(projectRoot: looseRoot, packageRoot: root, stockRoot: nil)
        let packageFont = try SceneTextFontResolver.resolve(path: "fonts/owned-clock.otf", size: 32,
            resourceView: completeView)
        let looseFont = try SceneTextFontResolver.resolve(path: "fonts/loose-only.otf", size: 32,
            resourceView: completeView)
        let badView = SceneResourceView(projectRoot: looseRoot, packageRoot: badRoot, stockRoot: nil)
        let selectedBad = try SceneTextFontResolver.resolve(path: "fonts/spincycle_3d_ot.otf", size: 32,
            resourceView: badView)
        let looseOnlyView = SceneResourceView(projectRoot: looseRoot, packageRoot: nil, stockRoot: nil)
        let looseOnly = try SceneTextFontResolver.resolve(path: "fonts/loose-only.otf", size: 32,
            resourceView: looseOnlyView)
        let mountedPackage = try SceneResourceView.Root.package(openedPackage:
            ScenePkgReader().openPackage(packageURL: directory.appendingPathComponent("font-selection.pkg")))
        cases["alternate"] = try result("fonts/loose-only.otf", root: looseRoot)
        for (name, path) in [
            ("virtualBareDirectoryLoose", "fonts/loose-only.otf"),
            ("virtualExplicitDirectorySlash", "fonts/loose-only.otf/"),
            ("virtualExplicitDirectoryDot", "fonts/loose-only.otf/."),
            ("virtualSelectedBad", "fonts/spincycle_3d_ot.otf"),
            ("virtualInvalidRangeLoose", "fonts/range-fallback.otf")
        ] { cases[name] = try result(path, root: looseRoot, packageRoot: mountedPackage) }
        let packageExpectedName = (cases["renamed"] as! [String: Any])["postScriptName"] as! String
        let output: [String: Any] = ["cases": cases,
            "retargetRejected": retargetRejected, "replacedWhileOpen": replacedWhileOpen,
            "changedRejected": changedRejected, "cancellationReachedOpenFD": cancellationReachedOpenFD,
            "originalCancellationPreserved": originalCancellationPreserved,
            "escapeRejected": escapeRejected, "parentEscapeRejected": parentEscapeRejected,
            "packagePrecedesLoose": packageFont.postScriptName == packageExpectedName,
            "looseMissingPackageFallback": looseFont.source == "embedded"
                && looseFont.postScriptName == looseOnly.postScriptName,
            "looseOnlyAuthorFont": looseOnly.source == "embedded",
            "badSelectedDoesNotFallThrough": selectedBad.source == "fallback"
                && selectedBad.diagnostic == "invalidBundledFont"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneTextFontResourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-font-resources-")
        cls.addClassCleanup(cls.temporary.cleanup)
        directory = Path(cls.temporary.name)
        for path in ("author/fonts/sub", "author/.hidden", "bad/fonts", "other/fonts",
                     "SceneStockAssets.bundle/assets/fonts"):
            (directory / path).mkdir(parents=True)
        font = FONT_ROOT / "spincycle_3d_ot.otf"
        alternate = FONT_ROOT / "Atami-Regular.otf"
        for path in ("author/fonts/owned-clock.otf", "author/fonts/mutable.otf",
                     "author/.hidden/clock.otf", "SceneStockAssets.bundle/assets/fonts/spincycle_3d_ot.otf"):
            shutil.copy2(font, directory / path)
        shutil.copy2(alternate, directory / "replacement.otf")
        shutil.copy2(alternate, directory / "other/fonts/owned-clock.otf")
        shutil.copy2(alternate, directory / "other/fonts/loose-only.otf")
        shutil.copy2(alternate, directory / "other/fonts/spincycle_3d_ot.otf")
        shutil.copy2(alternate, directory / "other/fonts/range-fallback.otf")
        (directory / "bad/fonts/spincycle_3d_ot.otf").write_bytes(b"invalid selected font")
        invalid_range_path = "fonts/range-fallback.otf"
        package_bytes = bytearray(make_package([
            (invalid_range_path, b"unreadable range"),
            ("fonts/loose-only.otf/child.bin", b"directory child"),
            ("fonts/spincycle_3d_ot.otf", b"invalid selected package font"),
        ]))
        # The first record is structurally complete, but cannot refer to any
        # payload byte. Other entries must retain their ordinary selection.
        range_word = 4 + int.from_bytes(package_bytes[:4], "little") + 4 + 4 + len(invalid_range_path.encode())
        package_bytes[range_word:range_word + 8] = len(package_bytes).to_bytes(4, "little") + (1).to_bytes(4, "little")
        package = directory / "font-selection.pkg"
        package.write_bytes(package_bytes)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS)
        binary = directory / "font-resources"
        inputs = [*SOURCES, Path(__file__), Path(__file__).with_name("scene_pkg_fixture.py"),
                  harness, font, alternate, package]
        identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
        command = ["xcrun", "--sdk", "macosx", "swiftc", *map(str, SOURCES), str(harness),
                   "-framework", "CoreText", "-framework", "CoreGraphics",
                   "-module-cache-path", str(directory / "module-cache"), "-o", str(binary)]
        try:
            compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
            (directory / "compile.log").write_text(compiled.stdout + compiled.stderr)
            if compiled.returncode:
                raise RuntimeError(compiled.stderr)
            completed = subprocess.run([str(binary), str(directory)], capture_output=True, text=True, timeout=30)
            (directory / "result.json").write_text(completed.stdout)
            (directory / "stderr.log").write_text(completed.stderr)
            if completed.returncode:
                raise RuntimeError(completed.stderr)
            cls.result = json.loads(completed.stdout)
            if identity != {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}:
                raise RuntimeError("font source changed during the probe")
        finally:
            (directory / "identity.json").write_text(json.dumps({"inputs": identity,
                "command": command, "boundary": "real Root/font/CoreText output; no Metal or App"}, indent=2))
            if destination := os.environ.get("MWX_SCENE_INTEGRATION_EVIDENCE"):
                saved = Path(destination) / "test_scene_text_font_resources"
                saved.mkdir(parents=True, exist_ok=True)
                for name in ("Harness.swift", "font-selection.pkg", "compile.log", "result.json", "stderr.log", "identity.json"):
                    if (directory / name).exists():
                        shutil.copy2(directory / name, saved / name)

    def test_literal_embedded_and_same_bytes_stock_keep_real_font_ink(self):
        cases = self.result["cases"]
        reference = cases["renamed"]
        self.assertEqual(reference["source"], "embedded")
        self.assertGreater(reference["ink"]["alphaPixels"], 0)
        for name in ("backslash", "dot", "parentComponent", "emptyComponent", "hidden", "stock",
                     "recovered", "noAuthorRoot"):
            with self.subTest(case=name):
                self.assertEqual(cases[name]["postScriptName"], reference["postScriptName"])
                self.assertEqual(cases[name]["ink"], reference["ink"])
        self.assertEqual(cases["stock"]["source"], "stockSubstituted")

    def test_absent_and_selected_invalid_fonts_keep_distinct_local_fallbacks(self):
        cases = self.result["cases"]
        self.assertEqual(cases["selectedBad"]["diagnostic"], "invalidBundledFont")
        self.assertEqual(cases["selectedBad"]["source"], "fallback")
        self.assertEqual(cases["selectedBad"]["postScriptName"], cases["default"]["postScriptName"])
        self.assertEqual(cases["missing"]["diagnostic"], "missingBundledFont")
        self.assertEqual(cases["invalidAbsolute"]["diagnostic"], "unsafeFontPath")
        self.assertEqual(cases["unknownAlias"]["diagnostic"], "systemAliasUnknown")
        self.assertIn(cases["alias"]["source"], ("systemAlias", "fallback"))

    def test_actual_opened_source_change_root_retarget_and_cancel_do_not_become_fallback(self):
        for field in ("retargetRejected", "replacedWhileOpen", "changedRejected",
                      "cancellationReachedOpenFD", "originalCancellationPreserved", "escapeRejected",
                      "parentEscapeRejected"):
            self.assertTrue(self.result[field], field)

    def test_complete_source_view_keeps_author_priority_and_loose_fonts(self):
        for field in ("packagePrecedesLoose", "looseMissingPackageFallback", "looseOnlyAuthorFont",
                      "badSelectedDoesNotFallThrough"):
            self.assertTrue(self.result[field], field)

    def test_virtual_package_bare_directory_and_skipped_invalid_range_keep_loose_font_ink(self):
        cases = self.result["cases"]
        reference = cases["alternate"]
        self.assertEqual(reference["source"], "embedded")
        self.assertNotEqual(reference["postScriptName"], cases["renamed"]["postScriptName"])
        self.assertGreater(reference["ink"]["alphaPixels"], 0)
        for name in ("virtualBareDirectoryLoose", "virtualInvalidRangeLoose"):
            with self.subTest(case=name):
                self.assertEqual(cases[name]["source"], "embedded")
                self.assertEqual(cases[name]["diagnostic"], "")
                self.assertEqual(cases[name]["postScriptName"], reference["postScriptName"])
                self.assertEqual(cases[name]["ink"], reference["ink"])

    def test_virtual_package_explicit_directory_and_bad_font_do_not_change_source(self):
        cases = self.result["cases"]
        for name in ("virtualExplicitDirectorySlash", "virtualExplicitDirectoryDot", "virtualSelectedBad"):
            with self.subTest(case=name):
                self.assertEqual(cases[name]["source"], "fallback")
                self.assertEqual(cases[name]["diagnostic"], "invalidBundledFont")
                self.assertEqual(cases[name]["postScriptName"], cases["default"]["postScriptName"])
                self.assertEqual(cases[name]["ink"], cases["default"]["ink"])


class SceneInitialTextFontReuseTests(unittest.TestCase):
    def test_initial_layers_reuse_only_successful_rasters_without_losing_font_size_or_fallback(self):
        harness = r'''
import CoreGraphics
import CoreText
import Darwin
import Foundation
import Metal
enum SceneDocumentLoader {
    static func floatVector(_ raw: Any?) -> [Float]? { fatalError("typed fixture") }
    static func floatValue(_ raw: Any?) -> Float? { fatalError("typed fixture") }
}
struct SceneRenderDescriptor {
    struct Layer {
        let id: Int; let contentKind: String; let name: String?
        let text: String?; let textStyle: SceneTextDescriptor?
    }
    let layers: [Layer]
}
@main enum InitialFontReuse {
    static func pixels(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        return bytes
    }
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { print("no-metal"); return }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let view = SceneResourceView(projectRoot: .init(source: .loose, url: root),
            packageRoot: nil, stockRoot: nil)
        let names = Set(["shared.otf", "other.otf", "invalid.otf", "after-failure.otf"])
        var openNames = Set<String>(), reads: [String: Int] = [:]
        func observeReads() {
            var current = Set<String>()
            for descriptor in 3..<256 {
                var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                if fcntl(Int32(descriptor), F_GETPATH, &path) == 0 {
                    let url = URL(fileURLWithPath: String(cString: path))
                    if names.contains(url.lastPathComponent), url.path.hasPrefix(root.path + "/") {
                        current.insert(url.lastPathComponent)
                    }
                }
            }
            for name in current.subtracting(openNames) { reads[name, default: 0] += 1 }
            openNames = current
        }
        func layer(_ id: Int, path: String, size: Float = 20, padding: Float = 4,
                   text: String = "Hamburg 0123") -> SceneRenderDescriptor.Layer {
            let style = SceneTextDescriptor(fontPath: path, pointSize: size, colorRGB: [1, 1, 1],
                brightness: 1, horizontalAlignment: "left", verticalAlignment: "top", screenAnchor: "none",
                padding: padding, limitRows: false, maxRows: 1, limitWidth: false, maxWidth: 0,
                useEllipsis: false, opaqueBackground: false, backgroundColorRGB: [0, 0, 0],
                backgroundBrightness: 1, outline: nil, dropShadow: nil)
            return .init(id: id, contentKind: "text", name: "renamed-layer-\(id)", text: text, textStyle: style)
        }
        let layers = [layer(1, path: "fonts/shared.otf", size: 12),
            layer(2, path: "fonts/shared.otf", size: 512, text: String(repeating: "Hamburg0123 ", count: 40)),
            layer(3, path: "fonts/shared.otf", size: 28),
            layer(4, path: "fonts/other.otf"),
            layer(5, path: "fonts/invalid.otf"), layer(6, path: "fonts/invalid.otf", size: 31),
            layer(7, path: "fonts/after-failure.otf", padding: .infinity),
            layer(8, path: "fonts/after-failure.otf", size: 23)]
        let loaded = SceneTextTextureLoader.load(descriptor: .init(layers: layers), resourceView: view,
            device: device, recordsDiagnostics: false, checkCancellation: observeReads)
        precondition(loaded.rasters.count == 7 && loaded.rasters[7] == nil && loaded.rasters[8] != nil,
            "a failed layout must not publish a font or block the next layer")
        precondition(reads == ["shared.otf": 1, "other.otf": 1, "invalid.otf": 1, "after-failure.otf": 2],
            "only successful same-path initial rasters may supply the font: \(reads)")
        for layer in layers where layer.id != 7 {
            let raster = loaded.rasters[layer.id]!
            let style = layer.textStyle!
            precondition(CTFontGetSize(raster.sourceFont.font)
                == CGFloat(SceneTextGeometry.pointSizeInPixels(style.pointSize)),
                "reused font must be resized to this layer's authored source size")
            let fresh = SceneTextTextureLoader.load(descriptor: .init(layers: [layer]), resourceView: view,
                device: device, recordsDiagnostics: false).rasters[layer.id]!
            precondition(fresh.renderSizeWH == raster.renderSizeWH
                && fresh.centerOffsetY == raster.centerOffsetY
                && pixels(fresh.texture) == pixels(raster.texture),
                "initial reuse must preserve independently loaded geometry and pixels")
        }
        let large = loaded.rasters[2]!
        precondition(large.renderSizeWH[0] > Float(large.texture.width)
            || large.renderSizeWH[1] > Float(large.texture.height), "fixture must exercise raster downsampling")
        precondition(loaded.rasters[1]!.sourceFont.postScriptName != loaded.rasters[4]!.sourceFont.postScriptName,
            "a distinct author path must resolve its own font")
        for id in [5, 6] {
            let font = loaded.rasters[id]!.sourceFont
            precondition(font.source == "fallback" && font.diagnostic == "invalidBundledFont"
                && font.requestedPath == "fonts/invalid.otf", "author fallback must keep its original cause and path")
        }
        // Reuse ends with this load's published rasters; a later load resolves
        // the file again, rather than inheriting a process-wide font decision.
        let before = reads["shared.otf"]!
        _ = SceneTextTextureLoader.load(descriptor: .init(layers: [layers[0]]), resourceView: view,
            device: device, recordsDiagnostics: false, checkCancellation: observeReads)
        precondition(reads["shared.otf"] == before + 1)
        print("initial-font-raster-reuse-pass")
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='mwx-initial-font-reuse-') as raw:
            work = Path(raw)
            fonts = work / 'fonts'; fonts.mkdir()
            for name in ['shared.otf', 'after-failure.otf']:
                shutil.copy2(FONT_ROOT / 'spincycle_3d_ot.otf', fonts / name)
            shutil.copy2(FONT_ROOT / 'Atami-Regular.otf', fonts / 'other.otf')
            (fonts / 'invalid.otf').write_bytes(b'invalid author font')
            source = work / 'Harness.swift'; source.write_text(harness)
            binary = work / 'initial-font-reuse'
            compiled = subprocess.run(['xcrun', 'swiftc', *map(str, RASTER_SOURCES), str(source),
                '-module-cache-path', str(work / 'modules'), '-framework', 'Metal', '-framework', 'CoreText',
                '-o', str(binary)], capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            run = subprocess.run([str(binary), str(work)], capture_output=True, text=True, timeout=60)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            if 'no-metal' in run.stdout:
                self.skipTest('Metal unavailable')
            self.assertIn('initial-font-raster-reuse-pass', run.stdout)
