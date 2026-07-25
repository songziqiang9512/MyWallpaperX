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
        // 同名 stock 字体在包内存在时必须走包内文件，用来证明解析优先级。
        let shadowedStockURL = fontsDirectory
            .appendingPathComponent("Atami-Regular.otf")
        try FileManager.default.copyItem(at: fixtureURL, to: shadowedStockURL)

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
        let consolasAlias = SceneTextFontResolver.resolve(
            path: "systemfont_consolas",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let sansSerifAlias = SceneTextFontResolver.resolve(
            path: "systemfont_sansserif",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let segoeAlias = SceneTextFontResolver.resolve(
            path: "systemfont_segoe",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let unknownAlias = SceneTextFontResolver.resolve(
            path: "systemfont_notarealalias",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        // 客户端自带字体：包内没有同名文件，必须报 stock 近似而不是 missingBundledFont。
        let stockMono = SceneTextFontResolver.resolve(
            path: "fonts/Segment7Standard.otf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let stockDisplay = SceneTextFontResolver.resolve(
            path: "fonts/Alcubierre.otf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let stockSans = SceneTextFontResolver.resolve(
            path: "fonts/NotoSans-Regular.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let stockEmoji = SceneTextFontResolver.resolve(
            path: "fonts/TwemojiMozilla.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let shadowedStock = SceneTextFontResolver.resolve(
            path: "fonts/Atami-Regular.otf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let traversalStock = SceneTextFontResolver.resolve(
            path: "../Alcubierre.otf",
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
            "consolasAlias": resolution(consolasAlias),
            "sansSerifAlias": resolution(sansSerifAlias),
            "segoeAlias": resolution(segoeAlias),
            "unknownAlias": resolution(unknownAlias),
            "stockMono": resolution(stockMono),
            "stockDisplay": resolution(stockDisplay),
            "stockSans": resolution(stockSans),
            "stockEmoji": resolution(stockEmoji),
            "shadowedStock": resolution(shadowedStock),
            "traversalStock": resolution(traversalStock),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func resolution(
        _ value: SceneTextFontResolver.Resolution
    ) -> [String: Any] {
        let traits = CTFontGetSymbolicTraits(value.font)
        return [
            "source": String(describing: value.source),
            "diagnostic": value.diagnostic ?? NSNull(),
            "postScriptName": value.postScriptName,
            "fontSize": CTFontGetSize(value.font),
            // 形态实测：等宽近似必须真的落在等宽家族上，不能只看名字。
            "monospace": traits.contains(.traitMonoSpace),
            "colorGlyphs": traits.contains(.traitColorGlyphs),
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

    def test_official_alias_table_covers_all_eight_names(self) -> None:
        # 官方安装目录里只存在 8 个 `systemfont_*`（arial/verdana/segoe/sansserif/
        # consolas/comicsans/cambria/calibri，各出现 6~8 次）。表内名字即使本机没装对应
        # 字体，也只能报 systemAliasUnavailable；只有表外名字才是 systemAliasUnknown。
        # 这样别名表是否补全在诊断里可观察，而不是被 Helvetica 的结果掩盖。
        for key in ("alias", "cambriaAlias", "consolasAlias", "sansSerifAlias", "segoeAlias"):
            with self.subTest(alias=key):
                value = self.result[key]
                self.assertIn(value["source"], {"systemAlias", "fallback"})
                self.assertNotEqual(value["diagnostic"], "systemAliasUnknown")
                self.assertTrue(value["postScriptName"])
        unknown = self.result["unknownAlias"]
        self.assertEqual(unknown["source"], "fallback")
        self.assertEqual(unknown["diagnostic"], "systemAliasUnknown")

    def test_consolas_alias_keeps_monospace_advances(self) -> None:
        # `systemfont_consolas` 是本机语料里引用最多的别名（480 次原始引用）。
        # Consolas 在 macOS 缺失，退化到比例字体会让等宽版式错位，
        # 所以 fallback 必须仍然是等宽家族。
        consolas = self.result["consolasAlias"]
        self.assertTrue(consolas["monospace"])
        if consolas["source"] == "systemAlias":
            self.assertIsNone(consolas["diagnostic"])
        else:
            self.assertEqual(consolas["source"], "fallback")
            self.assertEqual(consolas["diagnostic"], "systemAliasUnavailable")
            self.assertNotIn("Helvetica", consolas["postScriptName"])

    def test_generic_sans_serif_alias_is_satisfied_not_degraded(self) -> None:
        # `systemfont_sansserif` 是通用 sans 请求，macOS 的通用 sans 就是 Helvetica，
        # 因此属于别名命中，不应报缺失。
        sans = self.result["sansSerifAlias"]
        self.assertEqual(sans["source"], "systemAlias")
        self.assertIsNone(sans["diagnostic"])

    def test_client_stock_font_reports_approximation_not_missing_package(self) -> None:
        # 官方 `assets/fonts` 下 15 个客户端自带字体；作者写 `fonts/X` 时官方先找包内、
        # 再用自带字体。本项目不搬运字体文件，但必须把这种引用与“包坏了”区分开：
        # 本机语料 244 个去重 text layer 里 41 个属于这一类，此前全部被误报
        # missingBundledFont 并静默变成 Helvetica。
        for key, category in (
            ("stockMono", "mono"),
            ("stockDisplay", "display"),
            ("stockSans", "sans"),
            ("stockEmoji", "emoji"),
        ):
            with self.subTest(stock=key):
                value = self.result[key]
                self.assertEqual(value["source"], "stockApproximation")
                self.assertEqual(
                    value["diagnostic"], f"stockFontApproximated:{category}"
                )
                self.assertTrue(value["postScriptName"])
                self.assertEqual(value["fontSize"], 64)

    def test_stock_categories_preserve_measured_glyph_shape(self) -> None:
        # 类别是对安装目录只读实测出来的：Segment7Standard 是 fixed-pitch，
        # TwemojiMozilla 带 color glyph 表。近似字体必须保住这两个形态特征，
        # 否则时钟字体会错位、emoji 会变豆腐块。
        self.assertTrue(self.result["stockMono"]["monospace"])
        self.assertTrue(self.result["stockEmoji"]["colorGlyphs"])
        self.assertFalse(self.result["stockDisplay"]["monospace"])

    def test_bundled_font_wins_over_same_named_client_stock_font(self) -> None:
        # 解析顺序必须是别名 -> 包内文件 -> 客户端自带 -> 缺失。
        shadowed = self.result["shadowedStock"]
        self.assertEqual(shadowed["source"], "embedded")
        self.assertIsNone(shadowed["diagnostic"])

    def test_stock_name_does_not_bypass_path_traversal_rejection(self) -> None:
        # stock 识别不能给越界路径开后门：安全判定仍然优先。
        traversal = self.result["traversalStock"]
        self.assertEqual(traversal["source"], "fallback")
        self.assertEqual(traversal["diagnostic"], "unsafeFontPath")


if __name__ == "__main__":
    unittest.main()
