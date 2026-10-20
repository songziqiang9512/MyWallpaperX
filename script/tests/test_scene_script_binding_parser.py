#!/usr/bin/env python3
"""Layer 顶层 SceneScript 声明的无损解析门。"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from .scene_vector_vm_test_support import compile_vector_harness


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FIXTURES = Path(__file__).with_name("fixtures")
DOCUMENT_SOURCES = [
    SOURCE_ROOT / "Systems/Properties/SceneUserProperty.swift",
    SOURCE_ROOT / "Systems/Properties/SceneUserPropertyBindings.swift",
    SOURCE_ROOT / "Systems/Properties/SceneUserPropertyResolver.swift",
    SOURCE_ROOT / "Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    SOURCE_ROOT / "Format/SceneCompatibilityContext.swift",
    SOURCE_ROOT / "Format/SceneDocument.swift",
    SOURCE_ROOT / "Format/SceneDocument+General.swift",
    SOURCE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SOURCE_ROOT / "Format/SceneDocument+Timeline.swift",
    SOURCE_ROOT / "Format/SceneDocumentObject.swift",
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
    SOURCE_ROOT / "Format/SceneDirectionalLightDefinition.swift",
    SOURCE_ROOT / "Format/ScenePointLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Format/SceneScriptSourceEvidence.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneEffectTextureInput.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Composition/SceneUtilityLayer.swift",
]
LAYER_SOURCES = [
    SOURCE_ROOT / "Runtime/Frame/SceneMaterialRenderState.swift",
    SOURCE_ROOT / "Rendering/Composition/SceneUtilityLayer.swift",
    SOURCE_ROOT / "Systems/Properties/SceneUserProperty.swift",
    SOURCE_ROOT / "Systems/Properties/SceneUserPropertyBindings.swift",
    SOURCE_ROOT / "Systems/Properties/SceneScriptDynamicProviderHostContract.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Format/SceneDirectionalLightDefinition.swift",
    SOURCE_ROOT / "Format/ScenePointLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Properties/SceneDynamicSnapshot.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime/Frame/SceneRenderDescriptor+Layer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Rendering/Geometry/SceneLayerVisibility.swift",
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
                "rate": {
                    "script": "fixture-particle-rate",
                    "scriptproperties": {
                        "frequency": 1,
                        "smoothing": 8,
                    },
                    "value": 2.5,
                },
                "nested": {
                    "script": "particle-script",
                    "scriptproperties": {"channel": 1},
                }
            },
        },
        {
            "id": 30,
            "name": "Static display wrappers",
            "image": "models/user/c.json",
            "visible": {"value": True},
            "alpha": {"value": 0.5},
            "origin": {
                "script": "non-display-script",
                "value": "0 0 0",
            },
        },
    ],
}

GENERIC_SCENE_FIXTURE = {
    "version": 3,
    "script": "fixture-scene-root",
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
            "angles": {
                "script": "fixture-invalid-properties",
                "scriptproperties": "not-an-object",
                "value": "0 0 0",
            },
            "scale": {
                "script": "fixture-conflicting-source",
                "user": "fixture-scale",
                "value": "1 1 1",
            },
            "size": {
                "script": 42,
                "value": "1920 1080",
            },
            "instanceoverride": {
                "rate": {
                    "script": "fixture-particle-rate",
                    "scriptproperties": {
                        "frequency": 1,
                        "smoothing": 8,
                    },
                    "value": 2.5,
                },
                "nested": {
                    "script": "fixture-nested-unsupported-owner",
                    "value": 1,
                }
            },
        },
        {
            "id": 110,
            "script": "fixture-object-root",
            "visible": {
                "script": "fixture-object-visible",
                "value": True,
            },
            "effects": [
                {
                    "id": 111,
                    "script": "fixture-effect-root",
                    "visible": {
                        "script": "fixture-effect-visible",
                        "value": True,
                    },
                    "passes": [
                        {
                            "id": 112,
                            "script": "fixture-pass-root",
                            "metadata": {
                                "items": [
                                    {
                                        "script": "fixture-duplicate-nested",
                                        "value": 1,
                                    },
                                    {
                                        "script": "fixture-duplicate-nested",
                                        "value": 2,
                                    },
                                ]
                            },
                            "constantshadervalues": {
                                "a": {
                                    "script": "fixture-constant-a",
                                    "user": None,
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
            "text": {
                "script": "fixture-user-text",
                "user": "fixture-text",
                "value": "authored text",
            },
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
    let displayScriptFields: [String]
    let bindings: [SceneScriptBindingDefinition]
    let textScript: SceneTextScriptDefinition?
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
                displayScriptFields: $0.displayScriptOwnership.fields,
                bindings: $0.scriptBindings,
                textScript: $0.textScript
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: try encoder.encode(payload), as: UTF8.self))
    }
}
'''

GENERIC_DOCUMENT_HARNESS = (FIXTURES / "SceneScriptBindingGenericDocumentHarness.swift").read_text(encoding="utf-8")


LAYER_COMPATIBILITY_HARNESS = (FIXTURES / "SceneScriptBindingLayerCompatibilityHarness.swift").read_text(encoding="utf-8")


ALPHA_PROJECTION_HARNESS = r'''
import Foundation

// The shared fixture supplies the real scalar projection and Puppet bridge.
enum HarnessError: Error { case missingFixture }

@main
enum AlphaProjectionHarness {
    static func targetPayload(_ target: SceneDynamicTarget) -> [String: Any] {
        switch target {
        case let .layer(layerID, field):
            return ["kind": "layer", "layerID": layerID, "field": field.rawValue]
        case let .particle(layerID, field):
            return [
                "kind": "particle", "layerID": layerID,
                "field": String(describing: field),
            ]
        case let .text(layerID, field):
            return ["kind": "text", "layerID": layerID, "field": field.rawValue]
        case let .effectConstant(layerID, effectIndex, passIndex, name):
            return [
                "kind": "effectConstant", "layerID": layerID,
                "effectIndex": effectIndex, "passIndex": passIndex, "name": name,
            ]
        case let .effectVisibility(layerID, effectIndex):
            return [
                "kind": "effectVisibility", "layerID": layerID,
                "effectIndex": effectIndex,
            ]
        case let .materialConstant(layerID, passIndex, name, materialPath):
            return [
                "kind": "materialConstant", "layerID": layerID,
                "passIndex": passIndex, "name": name,
                "materialPath": materialPath,
            ]
        case let .scene(field):
            return ["kind": "scene", "field": field.rawValue]
        case let .camera(field):
            return ["kind": "camera", "field": field.rawValue]
        case let .scriptInstanceProperty(layerID, path):
            return [
                "kind": "scriptInstanceProperty", "layerID": layerID,
                "path": path,
            ]
        }
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw HarnessError.missingFixture
        }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: sceneURL)
        )
        guard let documentRoot = root as? [String: Any] else {
            throw HarnessError.missingFixture
        }
        let parseResult = SceneScriptBindingIRParser.parse(document: documentRoot)
        let descriptor = SceneRenderDescriptor(layers: [
            .init(id: 10, layerIndex: 0, name: nil, visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 0.5, effects: []),
            .init(id: 20, layerIndex: 1, name: nil, visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: []),
            .init(id: 30, layerIndex: 2, name: nil, visible: true,
                originXYZ: [0, 0, 0], scaleXYZ: [1, 1, 1], alpha: 1, effects: []),
        ])
        let targets = SceneScriptScalarProgram.projectedTargets(
            descriptor: descriptor,
            scriptBindings: parseResult.bindings
        )
        let payloads = targets
            .map { (description: String(describing: $0), payload: targetPayload($0)) }
            .sorted { $0.description < $1.description }
            .map(\.payload)
        let alphaValueType = parseResult.bindings
            .first { $0.targetKey == "alpha" }?.valueType.rawValue
        let payload: [String: Any] = [
            "bindingCount": parseResult.bindings.count,
            "alphaBindingValueType": alphaValueType ?? "missing",
            "targets": payloads,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


def compile_swift(sources: list[Path], harness: Path, binary: Path) -> None:
    completed = subprocess.run(
        [
            "swiftc",
            "-module-cache-path", str(binary.parent / "module-cache"),
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
        output_root = REPOSITORY_ROOT / ".artifacts/tmp/animation-rate-source-329-20261020/tests"
        output_root.mkdir(parents=True, exist_ok=True)
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-script-binding-", dir=output_root
        )
        cls.addClassCleanup(cls.temporary_directory.cleanup)
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
        cls.generic_binary = generic_binary
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
        cls.visibility_result = json.loads(compatibility.stdout)

        alpha_projection_binary = compile_vector_harness(
            directory, ALPHA_PROJECTION_HARNESS, "scene-alpha-projection"
        )
        alpha_projection_completed = subprocess.run(
            ["/usr/bin/env", str(alpha_projection_binary), str(scene)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.alpha_projection = json.loads(alpha_projection_completed.stdout)

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
        self.assertEqual(self.objects[10]["textScript"]["source"], "text-source")
        self.assertEqual(self.objects[10]["textScript"]["properties"], {})

    def test_nested_scripts_are_not_promoted_to_layer_property_bindings(self) -> None:
        self.assertTrue(self.objects[20]["hasInlineScript"])
        self.assertEqual(self.objects[20]["bindings"], [])
        sources = [
            binding["source"] for binding in self.objects[10]["bindings"]
        ]
        self.assertNotIn("must-not-be-promoted", sources)

    def test_only_display_field_scripts_own_visibility_and_alpha(self) -> None:
        self.assertEqual(
            self.objects[10]["displayScriptFields"],
            ["visible", "alpha"],
        )
        self.assertEqual(self.objects[20]["displayScriptFields"], [])
        self.assertEqual(self.objects[30]["displayScriptFields"], [])

    def test_boolean_visibility_retains_outer_user_as_typed_input(self) -> None:
        fixture = {"version": 3, "objects": [{
            "id": 71, "image": "models/user/example.json",
            "visible": {"script": RAW_SOURCE, "user": "enabled", "value": True},
            "alpha": {"script": RAW_SOURCE, "user": "alpha", "value": 1},
        }]}
        path = Path(self.temporary_directory.name) / "visibility-user.json"
        path.write_text(json.dumps(fixture), encoding="utf-8")
        result = json.loads(subprocess.run(
            [str(self.generic_binary), str(path)], check=True,
            capture_output=True, text=True,
        ).stdout)
        self.assertEqual(len(result["bindings"]), 1)
        self.assertEqual(result["bindings"][0]["targetKey"], "visible")
        self.assertEqual(result["bindings"][0]["wrapperKeys"], ["script", "user", "value"])

    def test_conditional_visibility_preserves_script_and_property_inputs(self) -> None:
        def wrapper(user, value=True):
            return {"script": RAW_SOURCE, "user": user, "value": value,
                    "scriptproperties": {"enabled": {"user": "tips", "value": False}}}

        fixture = {"objects": [
            {"id": 71, "image": "models/user/example.json", "visible": wrapper(
                {"name": "layout", "condition": "alternate"})},
            {"id": 72, "image": "models/user/example.json", "visible": wrapper(
                {"name": "layout", "condition": ["invalid"]})},
            {"id": 73, "image": "models/user/example.json", "visible": wrapper(
                {"name": "layout", "condition": "alternate", "extra": True})},
            {"id": 74, "image": "models/user/example.json", "alpha": wrapper(
                {"name": "layout", "condition": "alternate"}, 0.5)},
        ]}
        path = Path(self.temporary_directory.name) / "conditional-visibility.json"
        path.write_text(json.dumps(fixture), encoding="utf-8")
        result = json.loads(subprocess.run(
            [str(self.generic_binary), str(path)], check=True,
            capture_output=True, text=True,
        ).stdout)
        self.assertEqual(len(result["bindings"]), 1)
        binding = result["bindings"][0]
        self.assertEqual(binding["objectID"], 71)
        self.assertEqual(binding["userPropertyKey"], "layout")
        self.assertEqual(binding["source"], RAW_SOURCE)
        self.assertEqual(binding["authoredValue"], True)
        self.assertEqual(binding["properties"], {
            "enabled": {"user": "tips", "value": False},
        })

    def test_document_ir_preserves_all_verified_target_shapes(self) -> None:
        bindings = self.generic["bindings"]
        self.assertEqual(len(bindings), 15)
        owner_counts = {}
        for binding in bindings:
            owner_counts[binding["ownerKind"]] = (
                owner_counts.get(binding["ownerKind"], 0) + 1
            )
        self.assertEqual(
            owner_counts,
            {"scene": 1, "object": 4, "effect": 1, "pass": 9},
        )
        self.assertEqual(
            bindings[0]["targetPath"],
            ["general", "bloomstrength"],
        )
        self.assertEqual(bindings[0]["ownerKind"], "scene")
        self.assertNotIn("objectID", bindings[0])

        particle_rate = next(
            binding
            for binding in bindings
            if binding["source"] == "fixture-particle-rate"
        )
        self.assertEqual(
            particle_rate["targetPath"],
            ["objects", "[0]", "instanceoverride", "rate"],
        )
        self.assertEqual(particle_rate["ownerKind"], "object")
        self.assertEqual(particle_rate["objectID"], 100)
        self.assertEqual(particle_rate["properties"], {
            "frequency": 1,
            "smoothing": 8,
        })
        self.assertEqual(particle_rate["authoredValue"], 2.5)

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
        explicit_null = next(
            binding
            for binding in bindings
            if binding["source"] == "fixture-constant-a"
        )
        self.assertEqual(
            explicit_null["wrapperKeys"],
            ["script", "user", "value"],
        )
        text_owner = next(
            binding
            for binding in bindings
            if binding["source"] == "fixture-user-text"
        )
        self.assertEqual(text_owner["ownerKind"], "object")
        self.assertEqual(text_owner["objectID"], 120)
        self.assertEqual(text_owner["targetPath"], ["objects", "[2]", "text"])
        self.assertEqual(
            text_owner["wrapperKeys"], ["script", "user", "value"]
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
            bindings["fixture-object-origin"]["wrapperKeys"],
            ["script", "value"],
        )
        self.assertEqual(
            bindings["fixture-constant-b"]["wrapperKeys"],
            ["script", "scriptproperties", "value"],
        )
        self.assertEqual(
            bindings["fixture-constant-b"]["authoredValue"],
            "1 0 0",
        )
        self.assertEqual(
            bindings["fixture-constant-c"]["authoredValue"],
            "1.00000 0.00000 0.00000",
        )
        self.assertTrue(self.generic["legacyWrapperKeysMissing"])

    def test_source_evidence_is_retained_before_binding_admission(self) -> None:
        all_evidence = self.generic["sourceEvidence"]
        evidence = {
            entry["source"]: entry for entry in all_evidence
        }
        self.assertEqual(len(all_evidence), 24)
        self.assertEqual(len(evidence), 23)

        particle_rate = evidence["fixture-particle-rate"]
        self.assertEqual(particle_rate["ownerKind"], "object")
        self.assertEqual(
            particle_rate["targetPath"],
            ["objects", "[0]", "instanceoverride", "rate"],
        )

        scene_root = evidence["fixture-scene-root"]
        self.assertEqual(scene_root["ownerKind"], "scene")
        self.assertEqual(scene_root["targetPath"], [])
        self.assertEqual(scene_root["targetKey"], "")

        object_root = evidence["fixture-object-root"]
        self.assertEqual(object_root["ownerKind"], "object")
        self.assertEqual(object_root["objectIndex"], 1)
        self.assertEqual(object_root["objectID"], 110)
        self.assertEqual(object_root["targetPath"], ["objects", "[1]"])

        effect_root = evidence["fixture-effect-root"]
        self.assertEqual(effect_root["ownerKind"], "effect")
        self.assertEqual(effect_root["effectIndex"], 0)
        self.assertEqual(effect_root["effectID"], 111)
        self.assertEqual(
            effect_root["targetPath"],
            ["objects", "[1]", "effects", "[0]"],
        )

        pass_root = evidence["fixture-pass-root"]
        self.assertEqual(pass_root["ownerKind"], "pass")
        self.assertEqual(pass_root["passIndex"], 0)
        self.assertEqual(pass_root["passID"], 112)
        self.assertEqual(
            pass_root["targetPath"],
            ["objects", "[1]", "effects", "[0]", "passes", "[0]"],
        )

        duplicates = [
            entry
            for entry in all_evidence
            if entry["source"] == "fixture-duplicate-nested"
        ]
        self.assertEqual(len(duplicates), 2)
        self.assertEqual(
            [entry["targetPath"] for entry in duplicates],
            [
                [
                    "objects", "[1]", "effects", "[0]", "passes", "[0]",
                    "metadata", "items", "[0]",
                ],
                [
                    "objects", "[1]", "effects", "[0]", "passes", "[0]",
                    "metadata", "items", "[1]",
                ],
            ],
        )

        valid = evidence["fixture-object-origin"]
        self.assertEqual(valid["ownerKind"], "object")
        self.assertEqual(valid["objectIndex"], 0)
        self.assertEqual(valid["objectID"], 100)
        self.assertEqual(valid["targetPath"], ["objects", "[0]", "origin"])
        self.assertEqual(valid["targetKey"], "origin")
        self.assertEqual(valid["wrapperKeys"], ["script", "value"])

        conflicting = evidence["fixture-conflicting-source"]
        self.assertEqual(conflicting["ownerKind"], "object")
        self.assertEqual(conflicting["objectIndex"], 0)
        self.assertEqual(conflicting["objectID"], 100)
        self.assertEqual(
            conflicting["targetPath"], ["objects", "[0]", "scale"]
        )
        self.assertEqual(conflicting["targetKey"], "scale")
        self.assertEqual(
            conflicting["wrapperKeys"],
            ["script", "user", "value"],
        )
        invalid_properties = evidence["fixture-invalid-properties"]
        self.assertEqual(invalid_properties["targetKey"], "angles")
        self.assertEqual(
            invalid_properties["wrapperKeys"],
            ["script", "scriptproperties", "value"],
        )
        self.assertFalse(
            any(entry["targetKey"] == "size" for entry in evidence.values())
        )
        nested = evidence["fixture-nested-unsupported-owner"]
        self.assertEqual(nested["ownerKind"], "object")
        self.assertEqual(nested["objectIndex"], 0)
        self.assertEqual(nested["objectID"], 100)
        self.assertEqual(
            nested["targetPath"],
            ["objects", "[0]", "instanceoverride", "nested"],
        )
        self.assertNotIn(
            "fixture-nested-unsupported-owner",
            {entry["source"] for entry in self.generic["bindings"]},
        )

        self.assertEqual(self.generic["invalidAuthoredBindingCount"], 0)
        self.assertEqual(
            self.generic["invalidAuthoredDiagnostics"],
            [
                {
                    "code": "invalidAuthoredValue",
                    "targetPath": ["objects", "[0]", "origin"],
                }
            ],
        )
        self.assertEqual(
            self.generic["invalidAuthoredSourceEvidence"],
            [
                {
                    "source": "fixture-invalid-authored",
                    "ownerKind": "object",
                    "objectIndex": 0,
                    "objectID": 999,
                    "targetPath": ["objects", "[0]", "origin"],
                    "targetKey": "origin",
                    "wrapperKeys": ["script", "value"],
                }
            ],
        )

    def test_conflicting_and_nested_sources_fail_closed_without_misattachment(self) -> None:
        sources = {
            binding["source"] for binding in self.generic["bindings"]
        }
        self.assertNotIn("fixture-conflicting-source", sources)
        self.assertNotIn("fixture-invalid-properties", sources)
        self.assertNotIn("fixture-nested-unsupported-owner", sources)
        self.assertEqual(
            self.generic["diagnostics"],
            [
                {
                    "code": "invalidProperties",
                    "targetPath": ["objects", "[0]", "angles"],
                },
                {
                    "code": "conflictingSources",
                    "targetPath": ["objects", "[0]", "scale"],
                },
                {
                    "code": "invalidSource",
                    "targetPath": ["objects", "[0]", "size"],
                },
            ],
        )

    def test_mixed_structural_arrays_do_not_hide_source_evidence(self) -> None:
        evidence = {
            entry["source"]: entry
            for entry in self.generic["mixedArraySourceEvidence"]
        }
        self.assertEqual(set(evidence), {
            "fixture-mixed-object",
            "fixture-mixed-effect",
            "fixture-mixed-pass",
            "fixture-valid-after-mixed",
        })
        self.assertEqual(evidence["fixture-mixed-object"]["ownerKind"], "scene")
        self.assertEqual(
            evidence["fixture-mixed-object"]["targetPath"],
            ["objects", "[0]", "[1]"],
        )
        self.assertEqual(evidence["fixture-mixed-effect"]["ownerKind"], "object")
        self.assertEqual(evidence["fixture-mixed-effect"]["objectIndex"], 1)
        self.assertEqual(
            evidence["fixture-mixed-effect"]["targetPath"],
            ["objects", "[1]", "effects", "[0]", "[1]"],
        )
        self.assertEqual(evidence["fixture-mixed-pass"]["ownerKind"], "effect")
        self.assertEqual(evidence["fixture-mixed-pass"]["effectIndex"], 1)
        self.assertEqual(
            evidence["fixture-mixed-pass"]["targetPath"],
            [
                "objects", "[1]", "effects", "[1]", "passes", "[0]", "[1]",
            ],
        )
        valid = evidence["fixture-valid-after-mixed"]
        self.assertEqual(valid["ownerKind"], "pass")
        self.assertEqual(valid["passIndex"], 1)
        self.assertEqual(valid["passID"], 702)
        self.assertEqual(
            valid["targetPath"],
            [
                "objects", "[1]", "effects", "[1]", "passes", "[1]",
                "metadata",
            ],
        )

    def test_descriptor_layer_decodes_old_cache_without_new_key(self) -> None:
        self.assertTrue(self.visibility_result["oldScriptBindingsMissing"])
        self.assertTrue(self.visibility_result["oldDisplayOwnershipMissing"])

    def test_visible_scripts_keep_previous_current_while_alpha_stays_suppressed(self) -> None:
        self.assertEqual(self.visibility_result["visibleLayerIDs"], [1, 2, 3])
        self.assertEqual(
            self.visibility_result["reportLines"],
            [
                "scene layer display-state: layer=2 fields=visible "
                "disposition=previous-current reason=awaiting-scenescript-publication",
                "scene layer display-state: layer=4 fields=alpha "
                "disposition=suppressed reason=unproven-inline-scenescript-alpha",
            ],
        )

    def test_null_valued_alpha_wrapper_stays_unprojected_and_yields_to_fallback(self) -> None:
        targets = self.alpha_projection["targets"]
        # value:null 的 alpha wrapper（SCENE_FIXTURE objects[0].alpha）在
        # 标量投影层不产出 `.layer(10, .alpha)` 绑定目标：无有限数值种子的
        # 包装不会被准入。它的压制解除由 fallback 认领集合的补集负责，
        # 而不是由准入放宽负责。
        self.assertNotIn(
            {"field": "alpha", "kind": "layer", "layerID": 10},
            targets,
        )
        # 上下文钉死：IR 层仍无损保留该 wrapper（valueType=null），证明
        # 本断言拒绝的是投影准入，不是解析丢弃。
        self.assertEqual(self.alpha_projection["alphaBindingValueType"], "null")


if __name__ == "__main__":
    unittest.main()
