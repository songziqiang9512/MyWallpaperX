#!/usr/bin/env python3
"""Layer 顶层 SceneScript 声明的无损解析门。"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
DOCUMENT_SOURCES = [
    SOURCE_ROOT / "Format/SceneDocument.swift",
    SOURCE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SOURCE_ROOT / "Format/SceneDocument+Timeline.swift",
    SOURCE_ROOT / "Format/SceneDocumentObject.swift",
    SOURCE_ROOT / "Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SOURCE_ROOT / "Rendering/SceneUtilityLayer.swift",
]
LAYER_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor+Layer.swift",
]


RAW_SOURCE = "\nexport function update(value) {\n  return value;\n}\n"
SCENE_FIXTURE = {
    "version": 3,
    "objects": [
        {
            "id": 10,
            "name": "Top-level bindings",
            "image": "models/user/a.json",
            "alpha": {
                "script": "alpha-source",
                "value": None,
            },
            "customHost": {
                "script": RAW_SOURCE,
                "scriptproperties": {
                    "enabled": True,
                    "gain": 1.25,
                    "label": "main",
                    "bins": [0, 0.5, None],
                    "nested": {"mode": "peak", "enabled": False},
                },
            },
            "text": {
                "script": "text-source",
                "scriptproperties": {},
                "value": "fallback text",
            },
            "visible": {
                "script": "visible-source",
                "scriptproperties": {"threshold": 3},
                "value": True,
            },
            "notAScript": {"script": 42, "value": "ignored"},
            "effects": [
                {
                    "file": "effects/example/effect.json",
                    "passes": [
                        {
                            "constantshadervalues": {
                                "nestedScript": {
                                    "script": "must-not-be-promoted",
                                    "value": 1,
                                }
                            }
                        }
                    ],
                }
            ],
        },
        {
            "id": 20,
            "name": "Nested script only",
            "image": "models/user/b.json",
            "instanceoverride": {
                "nested": {
                    "script": "particle-script",
                    "scriptproperties": {"channel": 1},
                }
            },
        },
    ],
}


DOCUMENT_HARNESS = r'''
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

struct ObjectPayload: Codable {
    let id: Int
    let hasInlineScript: Bool
    let bindings: [SceneScriptBindingDefinition]
}

enum HarnessError: Error { case missingFixture }

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        let payload = document.objects.map {
            ObjectPayload(
                id: $0.id,
                hasInlineScript: $0.hasInlineScript,
                bindings: $0.scriptBindings
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: try encoder.encode(payload), as: UTF8.self))
    }
}
'''


LAYER_COMPATIBILITY_HARNESS = r'''
import Foundation

struct SceneRenderDescriptor {}
struct SceneParticleInstanceOverride: Codable {}
struct SceneUtilityLayer: Codable {}
struct ScenePuppetAnimationLayer: Codable {}
struct SceneTextDescriptor: Codable { let padding: Float }
struct SceneTextScriptDefinition: Codable {}

struct SceneDocument {
    struct SceneObjectTimeline: Codable {}
}

enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? {
        authoredSize
    }
}

extension SceneRenderDescriptor {
    struct EffectDescriptor: Codable {}
}

@main
enum Harness {
    static func main() throws {
        let oldCache = """
        {
          "id": 1,
          "layerIndex": 0,
          "contentKind": "image",
          "dependencyLayerIDs": [],
          "childLayerIDs": [],
          "puppetAnimationLayers": [],
          "disablesParallaxPropagation": false,
          "timelines": [],
          "timelineDiagnostics": [],
          "hasInlineScript": false,
          "effects": [],
          "effectFiles": [],
          "texturePaths": []
        }
        """
        let layer = try JSONDecoder().decode(
            SceneRenderDescriptor.Layer.self,
            from: Data(oldCache.utf8)
        )
        print(layer.scriptBindings == nil ? "nil" : "present")
    }
}
'''


def compile_swift(sources: list[Path], harness: Path, binary: Path) -> None:
    completed = subprocess.run(
        [
            "swiftc",
            *(str(source) for source in sources),
            str(harness),
            "-o",
            str(binary),
        ],
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr)


class SceneScriptBindingParserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-script-binding-"
        )
        directory = Path(cls.temporary_directory.name)

        scene = directory / "scene.json"
        scene.write_text(json.dumps(SCENE_FIXTURE), encoding="utf-8")
        document_harness = directory / "DocumentHarness.swift"
        document_harness.write_text(DOCUMENT_HARNESS, encoding="utf-8")
        document_binary = directory / "scene-script-binding"
        compile_swift(DOCUMENT_SOURCES, document_harness, document_binary)
        completed = subprocess.run(
            [str(document_binary), str(scene)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.objects = {
            entry["id"]: entry for entry in json.loads(completed.stdout)
        }

        compatibility_harness = directory / "CompatibilityHarness.swift"
        compatibility_harness.write_text(
            LAYER_COMPATIBILITY_HARNESS,
            encoding="utf-8",
        )
        compatibility_binary = directory / "scene-script-binding-cache"
        compile_swift(LAYER_SOURCES, compatibility_harness, compatibility_binary)
        compatibility = subprocess.run(
            [str(compatibility_binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.compatibility_result = compatibility.stdout.strip()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_top_level_hosts_are_retained_in_stable_order(self) -> None:
        bindings = self.objects[10]["bindings"]
        self.assertEqual(
            [binding["host"] for binding in bindings],
            ["alpha", "customHost", "text", "visible"],
        )

    def test_source_properties_and_authored_fallback_are_lossless(self) -> None:
        bindings = {
            binding["host"]: binding for binding in self.objects[10]["bindings"]
        }
        self.assertEqual(bindings["customHost"]["source"], RAW_SOURCE)
        self.assertEqual(
            bindings["customHost"]["properties"],
            {
                "enabled": True,
                "gain": 1.25,
                "label": "main",
                "bins": [0, 0.5, None],
                "nested": {"mode": "peak", "enabled": False},
            },
        )
        self.assertNotIn("authoredValue", bindings["customHost"])
        self.assertEqual(bindings["alpha"]["properties"], {})
        self.assertIsNone(bindings["alpha"]["authoredValue"])
        self.assertEqual(bindings["text"]["authoredValue"], "fallback text")
        self.assertTrue(bindings["visible"]["authoredValue"])

    def test_nested_scripts_are_not_promoted_to_layer_property_bindings(self) -> None:
        self.assertTrue(self.objects[20]["hasInlineScript"])
        self.assertEqual(self.objects[20]["bindings"], [])
        sources = [
            binding["source"] for binding in self.objects[10]["bindings"]
        ]
        self.assertNotIn("must-not-be-promoted", sources)

    def test_descriptor_layer_decodes_old_cache_without_new_key(self) -> None:
        self.assertEqual(self.compatibility_result, "nil")


if __name__ == "__main__":
    unittest.main()
