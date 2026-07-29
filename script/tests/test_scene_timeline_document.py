#!/usr/bin/env python3
"""作者 Timeline 进入 SceneDocument 的保真门。

在此之前，宿主属性的 `doubleValue`/`stringValue` 只取 `value`，同级的 `animation`
被静默丢弃。本门确认两条通路都保留了它：

  * layer 级属性（alpha / origin / angles / scale / size / color）→ `SceneObject.timelines`
  * effect constant → `ShaderValue.timeline`

fixture 的时间基与关键帧沿用真实作者数据的形状：`2998757800` 的 loop alpha、
`2134765860` 的三 lane relative angles、`2067939514` 的 startpaused effect constant。
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneDocument.swift",
    SOURCE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SOURCE_ROOT / "Format/SceneDocument+Timeline.swift",
    SOURCE_ROOT / "Format/SceneDocumentObject.swift",
    SOURCE_ROOT / "Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SOURCE_ROOT / "Rendering/SceneUtilityLayer.swift",
]


def keyframe(frame, value):
    return {
        "back": {"enabled": True, "x": -1, "y": 0},
        "frame": frame,
        "front": {"enabled": True, "x": 1, "y": 0},
        "lockangle": True,
        "locklength": True,
        "value": value,
    }


TAU = 6.2831855

SCENE_FIXTURE = {
    "version": 3,
    "objects": [
        {
            "id": 10,
            "name": "Loop alpha",
            "image": "models/user/a.json",
            "size": "100 100",
            "alpha": {
                "value": 1,
                "animation": {
                    "c0": [keyframe(0, 0), keyframe(60, 1)],
                    "options": {"fps": 30, "length": 60, "mode": "loop"},
                },
            },
        },
        {
            "id": 20,
            "name": "Relative mirror angles",
            "image": "models/user/b.json",
            "size": "100 100",
            "angles": {
                "value": "0.00000 0.00000 0.00000",
                "animation": {
                    "c0": [keyframe(0, 0), keyframe(2, 0)],
                    "c1": [keyframe(0, 0), keyframe(2, 0)],
                    "c2": [keyframe(0, 0), keyframe(2, TAU)],
                    "options": {"fps": 4, "length": 2, "mode": "mirror"},
                    "relative": True,
                },
            },
        },
        {
            "id": 30,
            "name": "Effect constant timeline",
            "image": "models/user/c.json",
            "size": "100 100",
            "effects": [
                {
                    "file": "effects/pulse/effect.json",
                    "passes": [
                        {
                            "constantshadervalues": {
                                "multiply": {
                                    "value": 0,
                                    "animation": {
                                        "c0": [keyframe(0, 1), keyframe(15, 0)],
                                        "options": {
                                            "fps": 15,
                                            "length": 15,
                                            "mode": "single",
                                            "startpaused": True,
                                            "wraploop": None,
                                        },
                                    },
                                },
                                # 用户绑定的 constant 不是 Timeline，必须保持 timeline 为空
                                "opacity": {"user": "opacity", "value": 0.75},
                            }
                        }
                    ],
                }
            ],
        },
        {
            "id": 40,
            "name": "No timeline",
            "image": "models/user/d.json",
            "size": "100 100",
            "alpha": 0.5,
        },
        {
            "id": 50,
            "name": "Rejected timeline",
            "image": "models/user/e.json",
            "size": "100 100",
            "alpha": {
                "value": 1,
                "animation": {
                    "c0": [keyframe(0, 0), keyframe(60, 1)],
                    "options": {"fps": 30, "length": 60, "mode": "pingpong"},
                },
            },
        },
    ],
}

HARNESS_SOURCE = r'''
import Foundation

struct SceneParticleInstanceOverride: Codable {}

struct SceneParticleDefinitionParser {
    func parseInstanceOverride(_ raw: Any?) -> SceneParticleInstanceOverride? { nil }
}

struct SceneTextDescriptor: Codable {
    let padding: Float
    init(padding: Float = 0) { self.padding = padding }
    static func parse(_ root: [String: Any]) -> SceneTextDescriptor { .init() }
}

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? {
        authoredSize
    }
}

enum SceneUserPropertyValue {}
enum SceneUserPropertyKind { case sceneTexture }

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

enum HarnessError: Error { case missingFixture }

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        let objects = Dictionary(uniqueKeysWithValues: document.objects.map { ($0.id, $0) })

        var payload: [String: Any] = [:]
        for (id, object) in objects {
            var entry: [String: Any] = [
                "timelineHosts": object.timelines.map { $0.host.rawValue },
                "timelineDiagnostics": object.timelineDiagnostics,
            ]
            entry["timelines"] = object.timelines.map { timeline in
                [
                    "host": timeline.host.rawValue,
                    "mode": timeline.animation.options.mode.rawValue,
                    "fps": timeline.animation.options.fps,
                    "length": timeline.animation.options.length,
                    "durationSeconds": timeline.animation.options.durationSeconds,
                    "startsPaused": timeline.animation.options.startsPaused,
                    "componentCount": timeline.animation.componentCount,
                    "isRelative": timeline.animation.isRelative,
                    "lastValues": timeline.animation.lanes.map { $0.last?.value ?? 0 },
                ]
            }
            var constants: [String: Any] = [:]
            for effect in object.effects {
                for pass in effect.passes {
                    for (name, value) in pass.constantShaderValues {
                        constants[name] = [
                            "valueKind": value.valueKind,
                            "userBinding": value.userBinding ?? "-",
                            "hasTimeline": value.timeline != nil,
                            "mode": value.timeline?.options.mode.rawValue ?? "-",
                            "startsPaused": value.timeline?.options.startsPaused ?? false,
                            "durationSeconds": value.timeline?.options.durationSeconds ?? -1,
                            "diagnostics": value.timelineDiagnostics,
                        ]
                    }
                }
            }
            entry["constants"] = constants
            payload["\(id)"] = entry
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneTimelineDocumentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-timeline-doc-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        scene = directory / "scene.json"
        scene.write_text(json.dumps(SCENE_FIXTURE), encoding="utf-8")
        binary = directory / "scene-timeline-doc"
        compilation = subprocess.run(
            [
                "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary), str(scene)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_layer_alpha_timeline_is_retained(self) -> None:
        entry = self.result["10"]
        self.assertEqual(entry["timelineHosts"], ["alpha"])
        timeline = entry["timelines"][0]
        self.assertEqual(timeline["mode"], "loop")
        self.assertEqual(timeline["fps"], 30)
        self.assertAlmostEqual(timeline["durationSeconds"], 2.0)
        self.assertEqual(timeline["componentCount"], 1)
        self.assertFalse(timeline["isRelative"])

    def test_vector_host_keeps_all_three_lanes_and_relative_flag(self) -> None:
        entry = self.result["20"]
        self.assertEqual(entry["timelineHosts"], ["angles"])
        timeline = entry["timelines"][0]
        self.assertEqual(timeline["mode"], "mirror")
        self.assertEqual(timeline["componentCount"], 3)
        self.assertTrue(timeline["isRelative"])
        self.assertAlmostEqual(timeline["lastValues"][2], TAU)

    def test_effect_constant_timeline_is_retained(self) -> None:
        constants = self.result["30"]["constants"]
        multiply = constants["multiply"]
        self.assertTrue(multiply["hasTimeline"])
        self.assertEqual(multiply["mode"], "single")
        self.assertTrue(multiply["startsPaused"])
        self.assertAlmostEqual(multiply["durationSeconds"], 1.0)
        self.assertEqual(multiply["diagnostics"], [])
        # 该 object 的 layer 级属性没有 animation
        self.assertEqual(self.result["30"]["timelineHosts"], [])

    def test_user_bound_constant_is_not_mistaken_for_a_timeline(self) -> None:
        opacity = self.result["30"]["constants"]["opacity"]
        self.assertEqual(opacity["valueKind"], "binding")
        self.assertEqual(opacity["userBinding"], "opacity")
        self.assertFalse(opacity["hasTimeline"])
        self.assertEqual(opacity["diagnostics"], [])

    def test_plain_scalar_host_produces_no_timeline(self) -> None:
        entry = self.result["40"]
        self.assertEqual(entry["timelineHosts"], [])
        self.assertEqual(entry["timelineDiagnostics"], [])

    def test_rejected_timeline_is_reported_not_silently_dropped(self) -> None:
        entry = self.result["50"]
        self.assertEqual(entry["timelineHosts"], [])
        self.assertEqual(entry["timelineDiagnostics"], ["alpha:unknownMode"])


if __name__ == "__main__":
    unittest.main()
