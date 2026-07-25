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
STOCK_FONT_BUNDLE = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneStockFonts.bundle"
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
        // 同名 stock 字体在壁纸包内存在时必须走包内文件，用来证明解析优先级。
        let shadowedStockURL = fontsDirectory
            .appendingPathComponent("summer85.ttf")
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
        // 客户端自带字体：壁纸包内没有同名文件，许可允许再分发的走 app 包内真实字形，
        // 其余只能按实测类别近似。
        let bundledStockMono = SceneTextFontResolver.resolve(
            path: "fonts/Segment7Standard.otf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let bundledStockRoboto = SceneTextFontResolver.resolve(
            path: "fonts/RobotoMono-Regular.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let bundledStockSans = SceneTextFontResolver.resolve(
            path: "fonts/NotoSans-Regular.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let bundledStockEmoji = SceneTextFontResolver.resolve(
            path: "fonts/TwemojiMozilla.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let bundledStockDisplay = SceneTextFontResolver.resolve(
            path: "fonts/8bitOperatorPlus8-Regular.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let bundledStockBlackout = SceneTextFontResolver.resolve(
            path: "fonts/Blackout 2 AM.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let substitutedStockDisplay = SceneTextFontResolver.resolve(
            path: "fonts/Atami-Regular.otf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let substitutedStockOutline = SceneTextFontResolver.resolve(
            path: "fonts/spincycle_3d_ot.otf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let substitutedStockMono = SceneTextFontResolver.resolve(
            path: "fonts/CursedTimerUlil-Aznm.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let shadowedStock = SceneTextFontResolver.resolve(
            path: "fonts/summer85.ttf",
            size: 64,
            cacheDirectory: cacheDirectory
        )
        let traversalStock = SceneTextFontResolver.resolve(
            path: "../Alcubierre.otf",
            size: 64,
            cacheDirectory: cacheDirectory
        )

        // 全部 15 个客户端自带字体都必须拿到真实字体文件。用一个没有任何同名壁纸包文件的
        // 干净 cache，免得上面的 shadow fixture 让 summer85 走成 embedded。
        let pristineCache = FileManager.default.temporaryDirectory
            .appendingPathComponent("mwx-text-stock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: pristineCache, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: pristineCache) }
        var allStock: [String: Any] = [:]
        for reference in [
            "fonts/8bitOperatorPlus8-Regular.ttf",
            "fonts/Alcubierre.otf",
            "fonts/Atami-Regular.otf",
            "fonts/Blackout 2 AM.ttf",
            "fonts/CursedTimerUlil-Aznm.ttf",
            "fonts/kust.ttf",
            "fonts/Lazer84.ttf",
            "fonts/Monofur-PK7og.ttf",
            "fonts/NotoSans-Regular.ttf",
            "fonts/opensticks.ttf",
            "fonts/RobotoMono-Regular.ttf",
            "fonts/Segment7Standard.otf",
            "fonts/spincycle_3d_ot.otf",
            "fonts/summer85.ttf",
            "fonts/TwemojiMozilla.ttf",
        ] {
            allStock[reference] = resolution(
                SceneTextFontResolver.resolve(
                    path: reference,
                    size: 64,
                    cacheDirectory: pristineCache
                )
            )
        }

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
            "bundledStockMono": resolution(bundledStockMono),
            "bundledStockRoboto": resolution(bundledStockRoboto),
            "bundledStockSans": resolution(bundledStockSans),
            "bundledStockEmoji": resolution(bundledStockEmoji),
            "bundledStockDisplay": resolution(bundledStockDisplay),
            "bundledStockBlackout": resolution(bundledStockBlackout),
            "substitutedStockDisplay": resolution(substitutedStockDisplay),
            "substitutedStockOutline": resolution(substitutedStockOutline),
            "substitutedStockMono": resolution(substitutedStockMono),
            "shadowedStock": resolution(shadowedStock),
            "traversalStock": resolution(traversalStock),
            "allStock": allStock,
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
        # 命令行可执行文件的 Bundle.main.resourceURL 就是它所在目录，把随包字体放在
        # binary 旁边即可走生产同一条加载路径，不需要给生产代码开测试专用注入口。
        if not STOCK_FONT_BUNDLE.is_dir():
            raise RuntimeError(
                f"随包 stock 字体缺失：{STOCK_FONT_BUNDLE.relative_to(REPOSITORY_ROOT)}"
            )
        shutil.copytree(STOCK_FONT_BUNDLE, directory / STOCK_FONT_BUNDLE.name)
        completed = subprocess.run(
            [str(cls.binary), str(embedded_font)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

        # 同一个 binary 换到没有字体 bundle 的目录：作者引用必须仍然拿到可用字体，
        # 并且诊断要说明是包体缺文件，而不是把它和“本来只有类别近似”混成一种。
        stripped_directory = directory / "without-stock-fonts"
        stripped_directory.mkdir()
        stripped_binary = stripped_directory / cls.binary.name
        shutil.copy2(cls.binary, stripped_binary)
        stripped = subprocess.run(
            [str(stripped_binary), str(embedded_font)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result_without_stock_fonts = json.loads(stripped.stdout)

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

    def test_licensed_client_stock_fonts_render_real_glyphs_from_app_bundle(self) -> None:
        # 官方 `assets/fonts` 下 15 个客户端自带字体；作者写 `fonts/X` 时官方先找壁纸包内、
        # 再用客户端自带。其中 8 个的许可允许再分发（OFL/Apache/CC-BY/freeware），随 app
        # 打进 SceneStockFonts.bundle，必须命中原版字形而不是本机家族近似：PostScript 名
        # 不能是近似目标（Helvetica/Menlo/Apple Color Emoji）。
        # `Blackout 2 AM` 的内嵌 copyright 写 All rights reserved，但 The League of
        # Moveable Type 以 OFL 发布的同名文件与客户端那份 SHA-256 逐字节相同，因此算原版。
        for key, post_script in (
            ("bundledStockMono", "Segment7Standard"),
            ("bundledStockRoboto", "RobotoMono-Regular"),
            ("bundledStockSans", "NotoSans-Regular"),
            ("bundledStockEmoji", "TwemojiMozilla"),
            ("bundledStockDisplay", "8-bitOperatorPlus8-Regular"),
            ("bundledStockBlackout", "Blackout2AM"),
        ):
            with self.subTest(stock=key):
                value = self.result[key]
                self.assertEqual(value["source"], "stockBundled")
                self.assertIsNone(value["diagnostic"])
                self.assertEqual(value["postScriptName"], post_script)
                self.assertEqual(value["fontSize"], 64)

    def test_unredistributable_stock_font_uses_licensed_lookalike_not_generic_family(self) -> None:
        # 另外 7 个字体禁止再分发（Atami 的 EULA 明确写不得重新打包分发），原文件不搬运。
        # 但作者引用它们时必须拿到外形接近的真实字体，而不是掉到 Helvetica/Menlo 通用家族：
        # 替代字体是把原版与候选逐个并排渲染 "Hamburg 0123" 比对后选的。
        # 语料里 Atami 是引用最多的 stock 字体（17 个去重 layer）。
        for key, post_script, category in (
            ("substitutedStockDisplay", "Poppins-Medium", "display"),
            ("substitutedStockOutline", "BungeeShade-Regular", "display"),
            ("substitutedStockMono", "Segment7Standard", "mono"),
        ):
            with self.subTest(stock=key):
                value = self.result[key]
                self.assertEqual(value["source"], "stockSubstituted")
                # 替代不是官方字形，诊断必须一直可见，否则报告会把近似读成等价。
                self.assertEqual(
                    value["diagnostic"], f"stockFontSubstituted:{category}"
                )
                self.assertEqual(value["postScriptName"], post_script)
                self.assertEqual(value["fontSize"], 64)

    def test_stock_fonts_preserve_measured_glyph_shape(self) -> None:
        # 类别是对安装目录只读实测出来的：Segment7Standard/RobotoMono/CursedTimer 是等宽，
        # TwemojiMozilla 带 color glyph 表，8-bit Operator+ 与 Atami 是比例 display。
        # 无论走原版还是替代，这些形态特征都必须保住，
        # 否则时钟字体会错位、emoji 会变豆腐块。
        for key in ("bundledStockMono", "bundledStockRoboto", "substitutedStockMono"):
            with self.subTest(monospace=key):
                self.assertTrue(self.result[key]["monospace"])
        self.assertTrue(self.result["bundledStockEmoji"]["colorGlyphs"])
        for key in ("bundledStockDisplay", "substitutedStockDisplay"):
            with self.subTest(proportional=key):
                self.assertFalse(self.result[key]["monospace"])

    def test_every_client_stock_reference_gets_a_real_font_file(self) -> None:
        # 官方客户端 `assets/fonts` 的 15 个名字一个都不能掉回 Helvetica/Menlo 这类
        # 通用家族：8 个许可允许再分发的搬原版，7 个禁止再分发的换成外形接近的自由字体。
        # 这条门禁锁住这个划分，任何一个名字漏配随包文件都会失败。
        all_stock = self.result["allStock"]
        self.assertEqual(len(all_stock), 15)
        for reference, value in sorted(all_stock.items()):
            with self.subTest(reference=reference):
                self.assertIn(value["source"], {"stockBundled", "stockSubstituted"})
                self.assertEqual(value["fontSize"], 64)
        sources = [value["source"] for value in all_stock.values()]
        self.assertEqual(sources.count("stockBundled"), 8)
        self.assertEqual(sources.count("stockSubstituted"), 7)

    def test_stock_font_bundle_ships_a_license_for_every_font(self) -> None:
        # OFL / Apache 2.0 / CC-BY / monofur 的 freeware 条款都要求随附许可与署名；
        # 少一份文本，这个 bundle 的再分发本身就失去授权。
        fonts = sorted(path.name for path in (STOCK_FONT_BUNDLE / "Fonts").iterdir())
        licenses = sorted(path.name for path in (STOCK_FONT_BUNDLE / "Licenses").iterdir())
        self.assertEqual(len(fonts), 13)
        self.assertTrue((STOCK_FONT_BUNDLE / "NOTICE.md").is_file())
        notice = (STOCK_FONT_BUNDLE / "NOTICE.md").read_text(encoding="utf-8")
        for name in fonts:
            with self.subTest(font=name):
                # 每个字体文件都要在 NOTICE 里有署名条目。
                self.assertIn(name, notice)
        for name in licenses:
            with self.subTest(license=name):
                self.assertIn(name, notice)

    def test_missing_stock_font_bundle_degrades_without_failing_render(self) -> None:
        # 15 个 stock 字体都有随包文件，所以类别近似只在 app 包缺失或损坏时才会出现。
        # 这是运维问题，诊断要与正常命中区分开，同时仍然必须给出可用字体。
        stripped = self.result_without_stock_fonts
        for key, category in (
            ("bundledStockMono", "mono"),
            ("bundledStockEmoji", "emoji"),
            ("bundledStockDisplay", "display"),
            ("substitutedStockDisplay", "display"),
            ("substitutedStockMono", "mono"),
        ):
            with self.subTest(stock=key):
                value = stripped[key]
                self.assertEqual(value["source"], "stockApproximation")
                self.assertEqual(
                    value["diagnostic"], f"stockFontFileUnavailable:{category}"
                )
                self.assertTrue(value["postScriptName"])
        self.assertTrue(stripped["bundledStockMono"]["monospace"])
        self.assertTrue(stripped["bundledStockEmoji"]["colorGlyphs"])
        # 壁纸包自带字体不经过 app 包，缺 bundle 也不能影响它。
        self.assertEqual(stripped["embedded"]["source"], "embedded")

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
