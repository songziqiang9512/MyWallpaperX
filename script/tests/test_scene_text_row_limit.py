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
TEXT_TEXTURE_LOADER_SOURCE = SOURCE_ROOT / "Text/SceneTextTextureLoader.swift"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneCompatibilityContext.swift",
    SOURCE_ROOT / "Format/SceneDocument.swift",
    SOURCE_ROOT / "Format/SceneDocument+General.swift",
    SOURCE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SOURCE_ROOT / "Format/SceneDocument+Timeline.swift",
    SOURCE_ROOT / "Format/SceneDocumentObject.swift",
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
    SOURCE_ROOT / "Format/SceneDirectionalLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Format/SceneScriptSourceEvidence.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SOURCE_ROOT / "Rendering/SceneUtilityLayer.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Rendering/SceneLayerVisibility.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor+Layer.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor+AuthoredAssets.swift",
    SOURCE_ROOT / "Text/SceneTextDescriptor.swift",
    SOURCE_ROOT / "Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Text/SceneTextGeometry.swift",
    SOURCE_ROOT / "Text/SceneTextFontResolver.swift",
    SOURCE_ROOT / "Text/SceneTextRowLimit.swift",
    SOURCE_ROOT / "Text/SceneTextTextureLoader.swift",
]

# 全部 fixture 自建：字体只用 macOS 系统别名，内容是 A/B 重复串，没有官方 payload。
# pointsize 12 -> 12 * 25/6 = 50 px；Arial 50 px 下 "AAAA BBBB" 约 290 px 宽、行高约 58 px，
# 所以 200x140 的框会折成两行、400x140 的框是一行。
SCENE_FIXTURE = {
    "version": 3,
    "objects": [
        {
            "id": 10,
            "name": "wrap baseline",
            "text": "AAAA BBBB",
            "font": "systemfont_arial",
            "pointsize": 12,
            "color": "1 1 1",
            "size": "200 140",
            "horizontalalign": "left",
            "verticalalign": "top",
        },
        {
            "id": 20,
            "name": "one row",
            "text": "AAAA BBBB",
            "font": "systemfont_arial",
            "pointsize": 12,
            "color": "1 1 1",
            "size": "200 140",
            "horizontalalign": "left",
            "verticalalign": "top",
            "limitrows": True,
            "maxrows": 1,
        },
        {
            "id": 30,
            "name": "one row with ellipsis",
            "text": "AAAA BBBB",
            "font": "systemfont_arial",
            "pointsize": 12,
            "color": "1 1 1",
            "size": "200 140",
            "horizontalalign": "left",
            "verticalalign": "top",
            "limitrows": True,
            "maxrows": 1,
            "limituseellipsis": True,
        },
        {
            "id": 40,
            "name": "hard newlines limited",
            "text": "A\nB\nC",
            "font": "systemfont_arial",
            "pointsize": 12,
            "color": "1 1 1",
            "size": "200 300",
            "horizontalalign": "left",
            "verticalalign": "top",
            "limitrows": True,
            "maxrows": 2,
        },
        {
            "id": 50,
            "name": "hard newlines baseline",
            "text": "A\nB\nC",
            "font": "systemfont_arial",
            "pointsize": 12,
            "color": "1 1 1",
            "size": "200 300",
            "horizontalalign": "left",
            "verticalalign": "top",
        },
        {
            "id": 60,
            "name": "width limit on",
            "text": "AAAA BBBB",
            "font": "systemfont_arial",
            "pointsize": 12,
            "color": "1 1 1",
            "size": "400 140",
            "horizontalalign": "left",
            "verticalalign": "top",
            "limitwidth": True,
            "maxwidth": 100,
        },
        {
            "id": 70,
            "name": "width limit off keeps default maxwidth",
            "text": "AAAA BBBB",
            "font": "systemfont_arial",
            "pointsize": 12,
            "color": "1 1 1",
            "size": "400 140",
            "horizontalalign": "left",
            "verticalalign": "top",
            "limitwidth": False,
            "maxwidth": 100,
        },
        {
            "id": 80,
            "name": "wrapped property forms",
            "text": "AAAA BBBB",
            "font": "systemfont_arial",
            "pointsize": 12,
            "color": "1 1 1",
            "size": "400 140",
            "horizontalalign": "left",
            "verticalalign": "top",
            "limitrows": {"value": True},
            "maxrows": {"value": 1},
            "limitwidth": {"value": True},
            # 真实语料里 maxwidth 会带 animation 包装，取 value。
            "maxwidth": {"animation": {"options": {"fps": 30}}, "value": 100},
            "limituseellipsis": {"value": True},
        },
        {
            "id": 90,
            "name": "padded clock-sized frame",
            "text": "20:06:35",
            "font": "systemfont_arial",
            "pointsize": 13,
            "color": "1 1 1",
            "size": "196 126",
            "padding": 32,
            "horizontalalign": "center",
            "verticalalign": "center",
        },
        {
            "id": 100,
            "name": "padding is total geometry growth",
            "text": "AAAA BBBB",
            "font": "systemfont_arial",
            "pointsize": 12,
            "color": "1 1 1",
            "size": "330 140",
            "padding": 32,
            "horizontalalign": "left",
            "verticalalign": "top",
            "limitrows": True,
            "maxrows": 1,
        },
        {
            "id": 110,
            "name": "large padded clock",
            "text": "12:00:",
            "font": "systemfont_arial",
            "pointsize": 28,
            "color": "1 1 1",
            "size": "411 140",
            "padding": 70,
            "horizontalalign": "center",
            "verticalalign": "center",
        },
        {
            "id": 120,
            "name": "padded date",
            "text": "Thursday, December 25th, 2025",
            "font": "systemfont_arial",
            "pointsize": 14,
            "color": "1 1 1",
            "size": "1216 70",
            "padding": 32,
            "horizontalalign": "center",
            "verticalalign": "center",
        },
    ],
}


HARNESS_SOURCE = r'''
import CoreGraphics
import Foundation
import Metal

struct SceneParticleInstanceOverride: Codable {}

struct SceneParticleDefinitionParser {
    func parseInstanceOverride(_ raw: Any?) -> SceneParticleInstanceOverride? { nil }
}

enum SceneUserPropertyValue {}

enum SceneUserPropertyKind {
    case sceneTexture
}

struct SceneUserPropertyDefinition {
    let key: String
    let kind: SceneUserPropertyKind
}

struct SceneUserPropertyCatalog {
    let definitions: [SceneUserPropertyDefinition]

    static let empty = SceneUserPropertyCatalog(definitions: [])
}

struct SceneUserPropertyResolution {
    let root: [String: Any]
}

struct SceneUserPropertyDocumentResolver {
    func resolve(
        root: [String: Any],
        catalog: SceneUserPropertyCatalog,
        overrides: [String: SceneUserPropertyValue]
    ) -> SceneUserPropertyResolution {
        SceneUserPropertyResolution(root: root)
    }
}

struct ScenePkgExtractionReport {
    let outputURL: URL?
}

struct SceneProject {
    let rootURL: URL
    let entryPath: String
    let userProperties: SceneUserPropertyCatalog

    var entryURL: URL { rootURL.appendingPathComponent(entryPath) }
}

struct SceneMdlPuppetAttachment {
    let name: String
    let sceneBindFrameColumnMajor: [Float]
}

struct SceneAssetCatalog {
    struct ModelAsset {
        let relativePath: String
        let materialPath: String?
        let cropOffsetXY: [Float]?
        let isSolidLayer: Bool
        let puppetPath: String?
        let puppetAttachments: [SceneMdlPuppetAttachment]
    }

    struct MaterialAsset {
        struct Pass {
            let shader: String?
            let textures: [String]
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
            let userShaderValues: [String: String]
            let blending: String?
            let depthTest: String?
            let depthWrite: String?
            let cullMode: String?
            let alphaWriting: String?
        }

        let relativePath: String
        let rawSHA256: String
        let shaderPathIndependentSHA256: String
        let passes: [Pass]
    }

    let models: [ModelAsset]
    let materials: [MaterialAsset]
    let effectDefinitions: [SceneEffectDefinition]
    let effectDefinitionDiagnostics: [SceneEffectDefinitionDiagnostic]
    let shaderReferences: [String]
    let textureReferences: [String]
}

struct SceneResourceReferenceIndex {
    let missingReferences: [String]
    let builtInReferenceCount: Int
    let runtimeProvidedReferenceCount: Int
}

struct SceneCapabilityProfile {
    let firstStageRendererGaps: [String]
}

struct SceneDiagnosticsReport {
    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
    let resourceReferences: SceneResourceReferenceIndex?
    let capabilityProfile: SceneCapabilityProfile?
}

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        let project = SceneProject(
            rootURL: sceneURL.deletingLastPathComponent(),
            entryPath: sceneURL.lastPathComponent,
            userProperties: .empty
        )
        guard let descriptor = SceneRenderDescriptorBuilder().build(
            project: project,
            sceneDocument: document,
            assetCatalog: SceneAssetCatalog(
                models: [],
                materials: [],
                effectDefinitions: [],
                effectDefinitionDiagnostics: [],
                shaderReferences: [],
                textureReferences: []
            ),
            resourceReferences: SceneResourceReferenceIndex(
                missingReferences: [], builtInReferenceCount: 0,
                runtimeProvidedReferenceCount: 0
            ),
            capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: [])
        ) else {
            throw HarnessError.descriptorRejected
        }
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noMetal }
        let cacheDirectory = sceneURL.deletingLastPathComponent()

        let loaded = SceneTextTextureLoader.load(
            descriptor: descriptor,
            cacheDirectory: cacheDirectory,
            device: device
        )
        let layers = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        let ids = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]
        var style: [String: Any] = [:]
        var ink: [String: Any] = [:]
        for id in ids {
            guard let layer = layers[id], let text = layer.textStyle else { continue }
            style["\(id)"] = [
                "limitRows": text.limitRows,
                "maxRows": text.maxRows,
                "limitWidth": text.limitWidth,
                "maxWidth": text.maxWidth,
                "useEllipsis": text.useEllipsis,
            ]
            guard let texture = loaded.textures[id] else { continue }
            ink["\(id)"] = inkStatistics(texture)
        }

        let wrapWidths: [String: Any] = [
            "limitOff": SceneTextRowLimit.wrapWidth(
                contentWidth: 653,
                style: SceneTextDescriptor.parse([
                    "text": "x", "limitwidth": false, "maxwidth": 500,
                ]),
                scale: 1
            ),
            "limitOn": SceneTextRowLimit.wrapWidth(
                contentWidth: 653,
                style: SceneTextDescriptor.parse([
                    "text": "x", "limitwidth": true, "maxwidth": 620,
                ]),
                scale: 1
            ),
            "limitAboveBox": SceneTextRowLimit.wrapWidth(
                contentWidth: 653,
                style: SceneTextDescriptor.parse([
                    "text": "x", "limitwidth": true, "maxwidth": 1942.6299,
                ]),
                scale: 1
            ),
            "limitScaled": SceneTextRowLimit.wrapWidth(
                contentWidth: 653,
                style: SceneTextDescriptor.parse([
                    "text": "x", "limitwidth": true, "maxwidth": 620,
                ]),
                scale: 0.5
            ),
            "limitZero": SceneTextRowLimit.wrapWidth(
                contentWidth: 653,
                style: SceneTextDescriptor.parse([
                    "text": "x", "limitwidth": true, "maxwidth": 0,
                ]),
                scale: 1
            ),
        ]
        let longContent = "AAAA BBBB CCCC DDDD"
        let autoSized = layers[70].flatMap {
            SceneTextTextureLoader.makeDynamicTexture(
                for: $0,
                content: longContent,
                pointSize: $0.textStyle!.pointSize,
                colorRGB: $0.textStyle!.colorRGB,
                cacheDirectory: cacheDirectory,
                device: device
            )
        }
        let widthLimited = layers[60].flatMap {
            SceneTextTextureLoader.makeDynamicTexture(
                for: $0,
                content: longContent,
                pointSize: $0.textStyle!.pointSize,
                colorRGB: $0.textStyle!.colorRGB,
                cacheDirectory: cacheDirectory,
                device: device
            )
        }
        let timelineNarrow = layers[60].flatMap {
            SceneTextTextureLoader.makeDynamicTexture(
                for: $0,
                content: "AAAA BBBB",
                pointSize: $0.textStyle!.pointSize,
                colorRGB: $0.textStyle!.colorRGB,
                maxWidth: 100,
                cacheDirectory: cacheDirectory,
                device: device
            )
        }
        let timelineWide = layers[60].flatMap {
            SceneTextTextureLoader.makeDynamicTexture(
                for: $0,
                content: "AAAA BBBB",
                pointSize: $0.textStyle!.pointSize,
                colorRGB: $0.textStyle!.colorRGB,
                maxWidth: 350,
                cacheDirectory: cacheDirectory,
                device: device
            )
        }

        let result: [String: Any] = [
            "style": style,
            "ink": ink,
            "wrapWidths": wrapWidths,
            "dynamicRenderSizes": [
                "auto": autoSized?.renderSizeWH ?? [],
                "limited": widthLimited?.renderSizeWH ?? [],
            ],
            "timelineWidthInk": [
                "narrow": timelineNarrow.map { inkStatistics($0.texture) } ?? [:],
                "wide": timelineWide.map { inkStatistics($0.texture) } ?? [:],
            ],
            "messages": loaded.messages,
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    /// 逐像素统计不透明覆盖：bitmap 是 premultipliedFirst + byteOrder32Little，
    /// 所以内存里的顺序是 B,G,R,A，alpha 在第 4 字节。
    /// 行区间按纹理行号给出（CGContext 原点在左下，所以行号越大越靠画面上方）。
    private static func inkStatistics(_ texture: MTLTexture) -> [String: Any] {
        let width = texture.width
        let height = texture.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        var count = 0
        var minX = width
        var maxX = -1
        var rows: [Int] = []
        for y in 0 ..< height {
            var rowHasInk = false
            for x in 0 ..< width where pixels[(y * width + x) * 4 + 3] > 0 {
                count += 1
                rowHasInk = true
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
            if rowHasInk { rows.append(y) }
        }
        var ranges: [[Int]] = []
        for row in rows {
            if let last = ranges.last, last[1] + 1 == row {
                ranges[ranges.count - 1][1] = row
            } else {
                ranges.append([row, row])
            }
        }
        return [
            "size": [width, height],
            "count": count,
            "minX": minX,
            "maxX": maxX,
            "rowRanges": ranges,
        ]
    }

    enum HarnessError: Error {
        case missingFixture
        case noMetal
        case descriptorRejected
    }
}
'''


class SceneTextRowLimitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        missing_sources = [path for path in SWIFT_SOURCES if not path.is_file()]
        if missing_sources:
            raise RuntimeError(
                "Scene text row limit production contract is missing: "
                + ", ".join(path.name for path in missing_sources)
            )

        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-scene-text-rows-")
        directory = Path(cls.temporary_directory.name)
        fixture = directory / "scene.json"
        fixture.write_text(json.dumps(SCENE_FIXTURE), encoding="utf-8")
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-text-row-limit"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-framework", "CoreText",
                "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary), str(fixture)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temporary_directory"):
            cls.temporary_directory.cleanup()

    def test_default_loader_has_no_unclaimed_effect_runtime_authority(self) -> None:
        source = TEXT_TEXTURE_LOADER_SOURCE.read_text(encoding="utf-8")
        self.assertIn(
            "effectSummary: (SceneRenderDescriptor.Layer) -> String? = { _ in nil }",
            source,
        )
        self.assertNotIn("SceneEffectRuntimePlanner", source)
        self.assertNotIn("SceneInlineEffectRuntime", source)
        self.assertFalse(
            any("effect runtime" in message for message in self.result["messages"]),
            self.result["messages"],
        )

    def test_limit_fields_default_off_and_parse_wrapped_forms(self) -> None:
        # 官方 ITextLayer 的 limitrows/maxrows/limitwidth/maxwidth 与编辑器的
        # Overflow ellipsis：缺省全部关闭，maxrows 缺省 1，maxwidth 缺省 0。
        self.assertEqual(
            self.result["style"]["10"],
            {
                "limitRows": False,
                "maxRows": 1,
                "limitWidth": False,
                "maxWidth": 0,
                "useEllipsis": False,
            },
        )
        # 语料里 maxwidth 可能带 animation 包装，property 形式必须取 value。
        self.assertEqual(
            self.result["style"]["80"],
            {
                "limitRows": True,
                "maxRows": 1,
                "limitWidth": True,
                "maxWidth": 100,
                "useEllipsis": True,
            },
        )
        self.assertEqual(self.result["style"]["70"]["limitWidth"], False)
        self.assertEqual(self.result["style"]["70"]["maxWidth"], 100)

    def test_wrap_width_only_applies_when_limit_width_is_enabled(self) -> None:
        # 关闭时必须完全忽略 maxwidth，否则 393 个带 500 默认值的 layer 会被压窄。
        self.assertEqual(self.result["wrapWidths"]["limitOff"], 653)
        self.assertEqual(self.result["wrapWidths"]["limitOn"], 620)
        # maxwidth 大于外框时以外框为上界，maxwidth 是像素所以要跟随栅格降采样。
        self.assertEqual(self.result["wrapWidths"]["limitAboveBox"], 653)
        self.assertEqual(self.result["wrapWidths"]["limitScaled"], 310)
        self.assertEqual(self.result["wrapWidths"]["limitZero"], 653)

    def test_max_rows_drops_the_overflowing_rows(self) -> None:
        baseline = self.result["ink"]["10"]
        limited = self.result["ink"]["20"]
        self.assertEqual(len(baseline["rowRanges"]), 2)
        self.assertEqual(len(limited["rowRanges"]), 1)
        self.assertEqual(limited["rowRanges"][0], baseline["rowRanges"][0])
        self.assertLess(limited["count"], baseline["count"])

    def test_max_rows_counts_hard_line_breaks(self) -> None:
        baseline = self.result["ink"]["50"]
        limited = self.result["ink"]["40"]
        self.assertEqual(len(baseline["rowRanges"]), 3)
        self.assertEqual(len(limited["rowRanges"]), 2)
        self.assertEqual(limited["rowRanges"], baseline["rowRanges"][:2])

    def test_overflow_ellipsis_extends_the_kept_row(self) -> None:
        plain = self.result["ink"]["20"]
        ellipsis = self.result["ink"]["30"]
        self.assertEqual(len(ellipsis["rowRanges"]), 1)
        self.assertGreater(ellipsis["maxX"], plain["maxX"])
        self.assertGreater(ellipsis["count"], plain["count"])

    def test_ellipsis_backs_off_characters_to_fit_the_narrowed_wrap(self) -> None:
        # 80 号同时开三个开关且全是 property 包装形式：换行宽度 100 px 装不下
        # "AA…"，末行必须回退到 "A…" 才不越界；同一段文本在不限宽的 30 号里是 "AAAA…"。
        narrow = self.result["ink"]["80"]
        wide = self.result["ink"]["30"]
        self.assertEqual(len(narrow["rowRanges"]), 1)
        self.assertLessEqual(narrow["maxX"], 100)
        self.assertLess(narrow["maxX"], wide["maxX"])
        self.assertLess(narrow["count"], wide["count"])

    def test_width_limit_narrows_the_wrap_and_off_state_keeps_the_full_box(self) -> None:
        limited = self.result["ink"]["60"]
        unlimited = self.result["ink"]["70"]
        self.assertEqual(len(unlimited["rowRanges"]), 1)
        self.assertGreater(len(limited["rowRanges"]), 1)
        self.assertLessEqual(limited["maxX"], 100)
        self.assertGreater(unlimited["maxX"], 100)

    def test_padded_authored_outer_frame_still_rasterizes_visible_text(self) -> None:
        padded = self.result["ink"]["90"]
        self.assertEqual(padded["size"], [196, 126])
        self.assertGreater(padded["count"], 0)
        self.assertGreaterEqual(padded["minX"], 0)
        self.assertLessEqual(padded["maxX"], 195)

    def test_unlimited_width_can_use_the_authored_outer_geometry(self) -> None:
        # limitwidth=false 时 padding 不能把有效作者外框反向变成换行限制。
        padded = self.result["ink"]["100"]
        self.assertEqual(padded["size"], [330, 140])
        self.assertEqual(len(padded["rowRanges"]), 1)
        self.assertGreater(padded["maxX"], 270)

    def test_large_padded_single_line_text_keeps_visible_ink(self) -> None:
        clock = self.result["ink"]["110"]
        date = self.result["ink"]["120"]
        self.assertEqual(clock["size"], [411, 140])
        self.assertEqual(date["size"], [1216, 70])
        self.assertEqual(len(clock["rowRanges"]), 1)
        self.assertEqual(len(date["rowRanges"]), 1)
        self.assertGreater(clock["count"], 0)
        self.assertGreater(date["count"], 0)

    def test_dynamic_text_expands_only_when_width_is_not_authored_limited(self) -> None:
        self.assertGreater(self.result["dynamicRenderSizes"]["auto"][0], 400)
        self.assertEqual(self.result["dynamicRenderSizes"]["limited"], [400, 140])

    def test_dynamic_max_width_rerasterizes_the_wrap_geometry(self) -> None:
        narrow = self.result["timelineWidthInk"]["narrow"]
        wide = self.result["timelineWidthInk"]["wide"]
        self.assertGreater(len(narrow["rowRanges"]), len(wide["rowRanges"]))
        self.assertEqual(len(wide["rowRanges"]), 1)
        self.assertLessEqual(narrow["maxX"], 100)
        self.assertGreater(wide["maxX"], 100)


if __name__ == "__main__":
    unittest.main()
