#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Text/SceneTextDescriptor.swift",
    SOURCE_ROOT / "Text/SceneTextGeometry.swift",
    SOURCE_ROOT / "Text/SceneTextFontResolver.swift",
]
EMBEDDED_FONT_CANDIDATES = [
    Path("/System/Library/Fonts/Symbol.ttf"),
    Path("/System/Library/Fonts/SFNSMono.ttf"),
    Path("/System/Library/Fonts/HelveticaNeue.ttc"),
]


HARNESS_SOURCE = r'''
import CoreGraphics
import CoreText
import Foundation

// SceneTextDescriptor only needs this parser from the full scene document loader.
enum SceneDocumentLoader {
    static func floatValue(_ raw: Any?) -> Float? {
        let value: Any?
        if let wrapped = raw as? [String: Any] {
            value = wrapped["value"]
        } else {
            value = raw
        }
        if let number = value as? NSNumber { return number.floatValue }
        if let string = value as? String { return Float(string) }
        return nil
    }

    static func floatVector(_ raw: Any?) -> [Float]? {
        let value: Any?
        if let wrapped = raw as? [String: Any] {
            value = wrapped["value"]
        } else {
            value = raw
        }
        if let values = value as? [NSNumber] {
            return values.map(\.floatValue)
        }
        guard let string = value as? String else { return nil }
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ","))
        let values = string.components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .compactMap(Float.init)
        return values.isEmpty ? nil : values
    }
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw HarnessError.missingFontFixture
        }
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-text-font-\(UUID().uuidString)", isDirectory: true)
        let fontsDirectory = cacheDirectory.appendingPathComponent("fonts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fontsDirectory, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let embeddedURL = fontsDirectory.appendingPathComponent("Embedded.ttf")
        try FileManager.default.copyItem(at: fixtureURL, to: embeddedURL)

        let vectorPadding = SceneTextDescriptor.parse([
            "text": "Clock",
            "padding": "32.00000 32.00000",
        ])
        let wrappedPadding = SceneTextDescriptor.parse([
            "text": "Clock",
            "padding": ["value": "82.00000 82.00000"],
        ])
        let wrappedPointSize = SceneTextDescriptor.parse([
            "text": "Clock",
            "pointsize": ["value": 42],
        ])
        let defaultAnchor = SceneTextDescriptor.parse(["text": "Clock"])
        let authoredAnchor = SceneTextDescriptor.parse([
            "text": "00000",
            "anchor": "topright",
        ])
        let wrappedAnchor = SceneTextDescriptor.parse([
            "text": "00000",
            "anchor": ["value": "bottomleft"],
        ])
        let alias = SceneTextFontResolver.resolve(
            path: "fonts/systemfont_arial",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let embedded = SceneTextFontResolver.resolve(
            path: "fonts/Embedded.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let missing = SceneTextFontResolver.resolve(
            path: "fonts/DefinitelyMissing.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let cambriaAlias = SceneTextFontResolver.resolve(
            path: "systemfont_cambria",
            size: 64,
            cacheDirectory: cacheDirectory
        )

        let result: [String: Any] = [
            "point32": SceneTextGeometry.pointSizeInPixels(32),
            "point64": SceneTextGeometry.pointSizeInPixels(64),
            "point300": SceneTextGeometry.pointSizeInPixels(300),
            "pointZero": SceneTextGeometry.pointSizeInPixels(0),
            "expandedSize": SceneTextGeometry.expandedSize(
                authoredSize: [100, 50], padding: 10
            ),
            "vectorPadding": vectorPadding.padding,
            "wrappedPadding": wrappedPadding.padding,
            "wrappedPointSize": SceneTextGeometry.pointSizeInPixels(
                wrappedPointSize.pointSize
            ),
            "defaultAnchor": defaultAnchor.screenAnchor,
            "authoredAnchor": authoredAnchor.screenAnchor,
            "wrappedAnchor": wrappedAnchor.screenAnchor,
            "alias": resolution(alias),
            "embedded": resolution(embedded),
            "missing": resolution(missing),
            "cambriaAlias": resolution(cambriaAlias),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func resolution(
        _ value: SceneTextFontResolver.Resolution
    ) -> [String: Any] {
        [
            "source": String(describing: value.source),
            "diagnostic": value.diagnostic ?? NSNull(),
            "postScriptName": value.postScriptName,
            "fontSize": CTFontGetSize(value.font),
        ]
    }

    enum HarnessError: Error {
        case missingFontFixture
    }
}
'''


class SceneTextRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        missing_sources = [path for path in SWIFT_SOURCES if not path.exists()]
        if missing_sources:
            raise RuntimeError(
                "Scene text production contract is missing: "
                + ", ".join(path.name for path in missing_sources)
            )
        embedded_font = next(
            (path for path in EMBEDDED_FONT_CANDIDATES if path.is_file()), None
        )
        if embedded_font is None:
            raise unittest.SkipTest("no macOS font fixture is available")

        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-text-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-text-rendering"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "CoreText",
                "-framework", "CoreGraphics",
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary), str(embedded_font)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary_directory"):
            cls.temporary_directory.cleanup()

    def test_authored_point_size_uses_we_pixel_scale_and_cap(self) -> None:
        # lib.sceneScript.d.ts 的 ITextLayer.pointsize 是 300 DPI 下的磅值，
        # 换算到像素是 300/72 = 25/6。随包 dino_run 用 Segment7Standard.otf 排 "00000"：
        # pointsize 64 -> 266.667 px 时排版宽正好 780、32 -> 133.333 px 时正好 390，
        # 与两个记分标签的作者 size 780/390 逐位相符。上限 1_024 是纹理边长保护。
        self.assertAlmostEqual(self.result["point32"], 400 / 3, places=4)
        self.assertAlmostEqual(self.result["point64"], 800 / 3, places=4)
        self.assertAlmostEqual(
            self.result["point64"] / self.result["point32"], 2, places=6
        )
        self.assertEqual(self.result["point300"], 1024)
        self.assertEqual(self.result["pointZero"], 1)

    def test_padding_vector_and_wrapped_value_use_first_component(self) -> None:
        self.assertEqual(self.result["vectorPadding"], 32)
        self.assertEqual(self.result["wrappedPadding"], 82)

    def test_wrapped_property_point_size_keeps_we_pixel_scale(self) -> None:
        # 作者值 42 磅 -> 42 * 25/6 = 175 px。
        self.assertEqual(self.result["wrappedPointSize"], 175)

    def test_text_geometry_adds_padding_outside_authored_bounds(self) -> None:
        self.assertEqual(self.result["expandedSize"], [120, 70])

    def test_screen_anchor_defaults_to_none_and_unwraps_property_values(self) -> None:
        # 随包 5 个 text layer 里 3 个显式写 "none"、2 个写 "topright"，缺省必须等价 none。
        self.assertEqual(self.result["defaultAnchor"], "none")
        self.assertEqual(self.result["authoredAnchor"], "topright")
        self.assertEqual(self.result["wrappedAnchor"], "bottomleft")

    def test_system_alias_resolves_without_fallback(self) -> None:
        alias = self.result["alias"]
        self.assertEqual(alias["source"], "systemAlias")
        self.assertIsNone(alias["diagnostic"])
        self.assertIn("Arial", alias["postScriptName"])
        self.assertEqual(alias["fontSize"], 64)

    def test_embedded_font_is_preferred_over_fallback(self) -> None:
        embedded = self.result["embedded"]
        self.assertEqual(embedded["source"], "embedded")
        self.assertIsNone(embedded["diagnostic"])
        self.assertTrue(embedded["postScriptName"])
        self.assertEqual(embedded["fontSize"], 64)

    def test_missing_font_has_observable_deterministic_fallback(self) -> None:
        missing = self.result["missing"]
        self.assertEqual(missing["source"], "fallback")
        self.assertIsNotNone(missing["diagnostic"])
        self.assertTrue(missing["postScriptName"])
        self.assertEqual(missing["fontSize"], 64)

    def test_cambria_alias_never_silently_substitutes(self) -> None:
        cambria = self.result["cambriaAlias"]
        if cambria["source"] == "systemAlias":
            self.assertIsNone(cambria["diagnostic"])
            self.assertIn("Cambria", cambria["postScriptName"])
        else:
            self.assertEqual(cambria["source"], "fallback")
            self.assertEqual(cambria["diagnostic"], "systemAliasUnavailable")
            self.assertIn("TimesNewRoman", cambria["postScriptName"])


if __name__ == "__main__":
    unittest.main()
