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
    SOURCE_ROOT / "Format/SceneCompatibilityContext.swift",
    SOURCE_ROOT / "Format/SceneDocument.swift",
    SOURCE_ROOT / "Format/SceneDocument+General.swift",
    SOURCE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SOURCE_ROOT / "Format/SceneDocument+Timeline.swift",
    SOURCE_ROOT / "Format/SceneDocumentObject.swift",
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
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
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
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

GENERIC_SCENE_FIXTURE = {
    "version": 3,
    "general": {
        "bloomstrength": {
            "script": "fixture-scene-general",
            "value": 1.1200000047683716,
        }
    },
    "objects": [
        {
            "id": 100,
            "origin": {
                "script": "fixture-object-origin",
                "value": "206.33000 57.95600 0.00000",
            },
            "scale": {
                "script": "fixture-conflicting-source",
                "user": "fixture-scale",
                "value": "1 1 1",
            },
            "instanceoverride": {
                "nested": {
                    "script": "fixture-nested-unsupported-owner",
                    "value": 1,
                }
            },
        },
        {
            "id": 110,
            "visible": {
                "script": "fixture-object-visible",
                "value": True,
            },
            "effects": [
                {
                    "id": 111,
                    "visible": {
                        "script": "fixture-effect-visible",
                        "value": True,
                    },
                    "passes": [
                        {
                            "id": 112,
                            "constantshadervalues": {
                                "a": {
                                    "script": "fixture-constant-a",
                                    "value": 0,
                                },
                                "b": {
                                    "script": "fixture-constant-b",
                                    "scriptproperties": {
                                        "enabled": True,
                                        "weights": [0, 0.5, None],
                                    },
                                    "value": "1 0 0",
                                },
                                "c": {
                                    "script": "fixture-constant-c",
                                    "value": "1.00000 0.00000 0.00000",
                                },
                                "userOnly": {
                                    "user": "fixture-user",
                                    "value": 1,
                                },
                                "bare": 2,
                            },
                        }
                    ],
                }
            ],
        },
        {
            "id": 120,
            "effects": [
                {
                    "passes": [
                        {
                            "constantshadervalues": {
                                key: {
                                    "script": f"fixture-constant-{key}",
                                    "value": index,
                                }
                                for index, key in enumerate(("d", "e", "f"), start=3)
                            }
                        }
                    ]
                }
            ],
        },
        {
            "id": 130,
            "effects": [
                {
                    "passes": [
                        {
                            "constantshadervalues": {
                                key: {
                                    "script": f"fixture-constant-{key}",
                                    "value": index,
                                }
                                for index, key in enumerate(("g", "h", "i"), start=6)
                            }
                        }
                    ]
                }
            ],
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

GENERIC_DOCUMENT_HARNESS = r'''
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

struct BindingPayload: Encodable {
    let source: String
    let ownerKind: String
    let objectIndex: Int?
    let objectID: Int?
    let effectIndex: Int?
    let effectID: Int?
    let passIndex: Int?
    let passID: Int?
    let targetPath: [String]
    let targetKey: String
    let properties: [String: SceneJSONValue]
    let authoredValue: SceneJSONValue?
    let valueType: String

    init(_ binding: SceneScriptBindingIR) {
        source = binding.source
        ownerKind = binding.owner.kind.rawValue
        objectIndex = binding.owner.objectIndex
        objectID = binding.owner.objectID
        effectIndex = binding.owner.effectIndex
        effectID = binding.owner.effectID
        passIndex = binding.owner.passIndex
        passID = binding.owner.passID
        targetPath = binding.targetPath.map {
            switch $0 {
            case let .key(key): key
            case let .index(index): "[\(index)]"
            }
        }
        targetKey = binding.targetKey
        properties = binding.properties
        authoredValue = binding.authoredValue
        valueType = binding.valueType.rawValue
    }
}

struct DiagnosticPayload: Encodable {
    let code: String
    let targetPath: [String]

    init(_ diagnostic: SceneScriptBindingDiagnostic) {
        code = diagnostic.code.rawValue
        targetPath = diagnostic.targetPath.map {
            switch $0 {
            case let .key(key): key
            case let .index(index): "[\(index)]"
            }
        }
    }
}

struct Payload: Encodable {
    let bindings: [BindingPayload]
    let diagnostics: [DiagnosticPayload]
}

enum HarnessError: Error { case missingFixture }

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        let payload = Payload(
            bindings: document.scriptBindings.map(BindingPayload.init),
            diagnostics: document.scriptBindingDiagnostics.map(DiagnosticPayload.init)
        )
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
    struct Scene2DCameraPathDefinition: Codable {}
    struct SceneObjectTimeline: Codable {}
    struct SceneParticleTimeline: Codable {}
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
          "authoredDependencies": [],
          "childLayerIDs": [],
          "puppetAnimationLayers": [],
          "disablesParallaxPropagation": false,
          "timelines": [],
          "timelineDiagnostics": [],
          "particleTimelines": [],
          "particleTimelineDiagnostics": [],
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

        generic_scene = directory / "generic-scene.json"
        generic_scene.write_text(
            json.dumps(GENERIC_SCENE_FIXTURE),
            encoding="utf-8",
        )
        generic_harness = directory / "GenericDocumentHarness.swift"
        generic_harness.write_text(
            GENERIC_DOCUMENT_HARNESS,
            encoding="utf-8",
        )
        generic_binary = directory / "scene-script-binding-generic"
        compile_swift(DOCUMENT_SOURCES, generic_harness, generic_binary)
        generic_completed = subprocess.run(
            [str(generic_binary), str(generic_scene)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.generic = json.loads(generic_completed.stdout)

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

    def test_document_ir_preserves_all_thirteen_verified_target_shapes(self) -> None:
        bindings = self.generic["bindings"]
        self.assertEqual(len(bindings), 13)
        owner_counts = {}
        for binding in bindings:
            owner_counts[binding["ownerKind"]] = (
                owner_counts.get(binding["ownerKind"], 0) + 1
            )
        self.assertEqual(
            owner_counts,
            {"scene": 1, "object": 2, "effect": 1, "pass": 9},
        )
        self.assertEqual(
            bindings[0]["targetPath"],
            ["general", "bloomstrength"],
        )
        self.assertEqual(bindings[0]["ownerKind"], "scene")
        self.assertNotIn("objectID", bindings[0])

        effect = next(
            binding
            for binding in bindings
            if binding["source"] == "fixture-effect-visible"
        )
        self.assertEqual(
            effect["targetPath"],
            ["objects", "[1]", "effects", "[0]", "visible"],
        )
        self.assertEqual(effect["objectID"], 110)
        self.assertEqual(effect["effectID"], 111)

        constant = next(
            binding
            for binding in bindings
            if binding["source"] == "fixture-constant-b"
        )
        self.assertEqual(
            constant["targetPath"],
            [
                "objects",
                "[1]",
                "effects",
                "[0]",
                "passes",
                "[0]",
                "constantshadervalues",
                "b",
            ],
        )
        self.assertEqual(constant["targetKey"], "b")
        self.assertEqual(constant["passID"], 112)
        self.assertEqual(
            constant["properties"],
            {"enabled": True, "weights": [0, 0.5, None]},
        )

    def test_authored_json_value_type_is_retained_without_vector_guessing(self) -> None:
        bindings = {
            binding["source"]: binding for binding in self.generic["bindings"]
        }
        self.assertEqual(
            bindings["fixture-scene-general"]["valueType"],
            "number",
        )
        self.assertAlmostEqual(
            bindings["fixture-scene-general"]["authoredValue"],
            1.1200000047683716,
        )
        self.assertEqual(
            bindings["fixture-object-visible"]["valueType"],
            "boolean",
        )
        self.assertEqual(
            bindings["fixture-object-origin"]["valueType"],
            "string",
        )
        self.assertEqual(
            bindings["fixture-constant-b"]["authoredValue"],
            "1 0 0",
        )
        self.assertEqual(
            bindings["fixture-constant-c"]["authoredValue"],
            "1.00000 0.00000 0.00000",
        )

    def test_conflicting_and_nested_sources_fail_closed_without_misattachment(self) -> None:
        sources = {
            binding["source"] for binding in self.generic["bindings"]
        }
        self.assertNotIn("fixture-conflicting-source", sources)
        self.assertNotIn("fixture-nested-unsupported-owner", sources)
        self.assertEqual(
            self.generic["diagnostics"],
            [
                {
                    "code": "conflictingSources",
                    "targetPath": ["objects", "[0]", "scale"],
                }
            ],
        )

    def test_descriptor_layer_decodes_old_cache_without_new_key(self) -> None:
        self.assertEqual(self.compatibility_result, "nil")


if __name__ == "__main__":
    unittest.main()
