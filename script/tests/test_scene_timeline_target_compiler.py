#!/usr/bin/env python3
"""Timeline target 编译门。

确认作者 Timeline 被编译成正确的 `SceneDynamicTarget` + 值类型 + 作者基值，
并对未定标的形态 fail closed。

target 口径与 `SceneUserPropertyBindings` 一致：`effectIndex` 是 `objects[].effects[]`
的数组下标，`passIndex` 取 pass 自身的 `passIndex`，constant 名原样不小写化。
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
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
    SOURCE_ROOT / "Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SOURCE_ROOT / "Rendering/SceneUtilityLayer.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor+Layer.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor+AuthoredAssets.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Properties/SceneTimelineTargetCompiler.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
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


def animation(lanes, mode="loop", fps=30, length=60, **extra):
    body = {f"c{i}": lane for i, lane in enumerate(lanes)}
    options = {"fps": fps, "length": length, "mode": mode}
    options.update(extra.pop("options", {}))
    body["options"] = options
    body.update(extra)
    return body


SCENE_FIXTURE = {
    "version": 3,
    "objects": [
        {
            "id": 10,
            "name": "Layer alpha",
            "image": "models/user/a.json",
            "size": "100 100",
            "alpha": {
                "value": 0.25,
                "animation": animation([[keyframe(0, 0), keyframe(60, 1)]]),
            },
        },
        {
            "id": 20,
            "name": "Layer angles",
            "image": "models/user/b.json",
            "size": "100 100",
            "angles": {
                "value": "0.5 1.5 2.5",
                "animation": animation(
                    [
                        [keyframe(0, 0), keyframe(60, 1)],
                        [keyframe(0, 0), keyframe(60, 2)],
                        [keyframe(0, 0), keyframe(60, 3)],
                    ],
                    mode="mirror",
                ),
            },
        },
        {
            "id": 30,
            "name": "Effect constant",
            "image": "models/user/c.json",
            "size": "100 100",
            "effects": [
                {"file": "effects/noop/effect.json", "passes": [{}]},
                {
                    "file": "effects/pulse/effect.json",
                    "passes": [
                        {},
                        {
                            "constantshadervalues": {
                                "multiply": {
                                    "value": 0.75,
                                    "animation": animation(
                                        [[keyframe(0, 1), keyframe(15, 0)]],
                                        mode="single",
                                        fps=15,
                                        length=15,
                                    ),
                                }
                            }
                        },
                    ],
                },
            ],
        },
        {
            "id": 40,
            "name": "Relative angles",
            "image": "models/user/d.json",
            "size": "100 100",
            "angles": {
                "value": "0 0 0",
                "animation": animation(
                    [
                        [keyframe(0, 0), keyframe(60, 1)],
                        [keyframe(0, 0), keyframe(60, 1)],
                        [keyframe(0, 0), keyframe(60, 1)],
                    ],
                    relative=True,
                ),
            },
        },
        {
            "id": 41,
            "name": "Relative origin",
            "image": "models/user/origin.json",
            "size": "100 100",
            "origin": {
                "value": "10 20 30",
                "animation": animation(
                    [
                        [keyframe(0, 0), keyframe(60, 1)],
                        [keyframe(0, 0), keyframe(60, 2)],
                        [keyframe(0, 0), keyframe(60, 3)],
                    ],
                    relative=True,
                ),
            },
        },
        {
            "id": 42,
            "name": "Relative scale",
            "image": "models/user/scale.json",
            "size": "100 100",
            "scale": {
                "value": "1 1 1",
                "animation": animation(
                    [
                        [keyframe(0, 0), keyframe(60, 0.2)],
                        [keyframe(0, 0), keyframe(60, 0.2)],
                        [keyframe(0, 0), keyframe(60, 0)],
                    ],
                    relative=True,
                ),
            },
        },
        {
            "id": 50,
            "name": "Component mismatch",
            "image": "models/user/e.json",
            "size": "100 100",
            # angles 是 vector3 target，单 lane 必须拒绝
            "angles": {
                "value": "0 0 0",
                "animation": animation([[keyframe(0, 0), keyframe(60, 1)]]),
            },
        },
        {
            "id": 60,
            "name": "Unsupported hosts",
            "image": "models/user/f.json",
            "size": "100 100",
            "maxwidth": {
                "value": 100,
                "animation": animation([[keyframe(0, 0), keyframe(60, 1)]]),
            },
            "zoom": {
                "value": 1,
                "animation": animation([[keyframe(0, 0), keyframe(60, 1)]]),
            },
        },
        {
            "id": 65,
            "name": "Combined animation group is rejected",
            "image": "models/user/h.json",
            "size": "100 100",
            "alpha": {
                "value": 1,
                "animation": animation(
                    [[keyframe(0, 0), keyframe(60, 1)]],
                    options={"children": [{"key": "zoom"}]},
                ),
            },
        },
        {
            "id": 70,
            "name": "Wrap loop is downgraded not rejected",
            "image": "models/user/g.json",
            "size": "100 100",
            "alpha": {
                "value": 1,
                "animation": animation(
                    [[keyframe(0, 0), keyframe(60, 1)]],
                    options={"wraploop": True},
                ),
            },
        },
        {
            "id": 80,
            "name": "Particle control points",
            "particle": "particles/cp.json",
            "instanceoverride": {
                "controlpoint1": {
                    "value": "10 20 30",
                    "animation": animation(
                        [
                            [keyframe(0, 10), keyframe(30, 40)],
                            [keyframe(0, 20), keyframe(30, 50)],
                            [keyframe(0, 30), keyframe(30, 60)],
                        ]
                    ),
                },
                "controlpointangle1": {
                    "value": "0 0 1",
                    "animation": animation(
                        [
                            [keyframe(0, 0), keyframe(30, 0)],
                            [keyframe(0, 0), keyframe(30, 0)],
                            [keyframe(0, 1), keyframe(30, 2)],
                        ],
                        relative=True,
                    ),
                },
                "controlpoint2": {
                    "value": "1 2 3",
                    "animation": animation([[keyframe(0, 1), keyframe(30, 2)]]),
                },
                "controlpoint3": {
                    "value": "1 2",
                    "animation": animation(
                        [
                            [keyframe(0, 1), keyframe(30, 2)],
                            [keyframe(0, 2), keyframe(30, 3)],
                            [keyframe(0, 3), keyframe(30, 4)],
                        ]
                    ),
                },
                "controlpoint4": {
                    "value": "4 5 6",
                    "user": "conflictingProperty",
                    "animation": animation(
                        [
                            [keyframe(0, 4), keyframe(30, 5)],
                            [keyframe(0, 5), keyframe(30, 6)],
                            [keyframe(0, 6), keyframe(30, 7)],
                        ]
                    ),
                },
            },
        },
    ],
}

HARNESS_SOURCE = r'''
import Foundation

struct SceneTextDescriptor: Codable {
    let padding: Float
    init(padding: Float = 0) { self.padding = padding }
    static func parse(_ root: [String: Any]) -> SceneTextDescriptor { .init() }
}
enum SceneTextGeometry {
    static func expandedSize(authoredSize: [Float]?, padding: Float) -> [Float]? { authoredSize }
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
struct SceneUserPropertyResolution { let root: [String: Any] }
struct SceneUserPropertyDocumentResolver {
    func resolve(
        root: [String: Any],
        catalog: SceneUserPropertyCatalog,
        overrides: [String: SceneUserPropertyValue]
    ) -> SceneUserPropertyResolution { SceneUserPropertyResolution(root: root) }
}
struct ScenePkgExtractionReport { let outputURL: URL? }
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
struct SceneCapabilityProfile { let firstStageRendererGaps: [String] }

struct SceneDiagnosticsReport {
    let project: SceneProject?
    let sceneDocument: SceneDocument?
    let assetCatalog: SceneAssetCatalog?
    let resourceReferences: SceneResourceReferenceIndex?
    let capabilityProfile: SceneCapabilityProfile?
}

enum HarnessError: Error { case missingFixture, descriptorRejected }

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw HarnessError.missingFixture }
        let sceneURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = try SceneDocumentLoader().load(from: sceneURL)
        guard let descriptor = SceneRenderDescriptorBuilder().build(
            project: SceneProject(
                rootURL: sceneURL.deletingLastPathComponent(),
                entryPath: sceneURL.lastPathComponent,
                userProperties: .empty
            ),
            sceneDocument: document,
            assetCatalog: SceneAssetCatalog(
                models: [], materials: [], effectDefinitions: [],
                effectDefinitionDiagnostics: [], shaderReferences: [], textureReferences: []
            ),
            resourceReferences: SceneResourceReferenceIndex(
                missingReferences: [], builtInReferenceCount: 0,
                runtimeProvidedReferenceCount: 0
            ),
            capabilityProfile: SceneCapabilityProfile(firstStageRendererGaps: [])
        ) else {
            throw HarnessError.descriptorRejected
        }
        let program = SceneTimelineTargetCompiler.compile(descriptor: descriptor)
        let payload: [String: Any] = [
            "diagnostics": program.diagnostics,
            "bindings": program.bindings.map { binding in
                [
                    "target": describe(binding.definition.target),
                    "valueType": binding.definition.valueType.rawValue,
                    "authored": describe(binding.definition.authoredValue),
                    "mode": binding.animation.options.mode.rawValue,
                    "componentCount": binding.animation.componentCount,
                    "composition": binding.composition.rawValue,
                ]
            },
        ]
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        ), as: UTF8.self))
    }

    static func describe(_ target: SceneDynamicTarget) -> String {
        switch target {
        case let .layer(layerID, field): "layer:\(layerID):\(field.rawValue)"
        case let .effectConstant(layerID, effectIndex, passIndex, name):
            "constant:\(layerID):\(effectIndex):\(passIndex):\(name)"
        case let .particle(layerID, field):
            switch field {
            case let .controlPoint(index): "particle:\(layerID):controlpoint:\(index)"
            case let .controlPointAngles(index): "particle:\(layerID):angles:\(index)"
            default: "particle:\(layerID):other"
            }
        default: "other"
        }
    }

    static func describe(_ value: SceneDynamicValue) -> String {
        switch value {
        case let .scalar(v): "scalar(\(v))"
        case let .vector3(x, y, z): "vector3(\(x),\(y),\(z))"
        default: "other"
        }
    }
}
'''


class SceneTimelineTargetCompilerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-timeline-target-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        scene = directory / "scene.json"
        scene.write_text(json.dumps(SCENE_FIXTURE), encoding="utf-8")
        binary = directory / "scene-timeline-target"
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

    def binding(self, target):
        matches = [b for b in self.result["bindings"] if b["target"] == target]
        self.assertEqual(len(matches), 1, f"{target} 应当恰好编译出一条: {self.result}")
        return matches[0]

    def targets(self):
        return {b["target"] for b in self.result["bindings"]}

    def test_layer_alpha_compiles_to_scalar_with_authored_base(self) -> None:
        binding = self.binding("layer:10:alpha")
        self.assertEqual(binding["valueType"], "scalar")
        self.assertEqual(binding["authored"], "scalar(0.25)")
        self.assertEqual(binding["mode"], "loop")

    def test_vector_host_compiles_to_vector3_with_authored_base(self) -> None:
        binding = self.binding("layer:20:angles")
        self.assertEqual(binding["valueType"], "vector3")
        self.assertEqual(binding["authored"], "vector3(0.5,1.5,2.5)")
        self.assertEqual(binding["componentCount"], 3)
        self.assertEqual(binding["mode"], "mirror")
        self.assertEqual(binding["composition"], "absolute")

    def test_effect_constant_uses_array_index_and_pass_index(self) -> None:
        # effects[1].passes[1] —— effectIndex 是数组下标，passIndex 取 pass 自身
        binding = self.binding("constant:30:1:1:multiply")
        self.assertEqual(binding["valueType"], "scalar")
        self.assertEqual(binding["authored"], "scalar(0.75)")
        self.assertEqual(binding["mode"], "single")

    def test_relative_layer_transform_uses_additive_composition(self) -> None:
        expected = {
            "layer:40:angles": "vector3(0.0,0.0,0.0)",
            "layer:41:origin": "vector3(10.0,20.0,30.0)",
            "layer:42:scale": "vector3(1.0,1.0,1.0)",
        }
        for target, authored in expected.items():
            with self.subTest(target=target):
                binding = self.binding(target)
                self.assertEqual(binding["authored"], authored)
                self.assertEqual(binding["composition"], "additive")
        self.assertNotIn("layer 40 angles: relativeUnsupported", self.result["diagnostics"])

    def test_component_count_must_match_target_value_type(self) -> None:
        self.assertNotIn("layer:50:angles", self.targets())
        self.assertIn("layer 50 angles: componentMismatch", self.result["diagnostics"])

    def test_hosts_without_a_target_are_reported(self) -> None:
        for host in ("maxwidth", "zoom"):
            with self.subTest(host=host):
                self.assertIn(
                    f"layer 60 {host}: unsupportedHost", self.result["diagnostics"]
                )
        self.assertNotIn("layer:60:maxwidth", self.targets())

    def test_combined_animation_group_is_rejected(self) -> None:
        # 组内成员共享持有方的 clock，独立求值会让两条 lane 逐渐错相
        self.assertNotIn("layer:65:alpha", self.targets())
        self.assertIn(
            "layer 65 alpha: combinedAnimationUnsupported", self.result["diagnostics"]
        )

    def test_wrap_loop_is_downgraded_not_rejected(self) -> None:
        # wraploop 未实现，但不能因此丢掉整条动画
        binding = self.binding("layer:70:alpha")
        self.assertEqual(binding["mode"], "loop")
        self.assertIn("layer 70 alpha: wrapLoopIgnored", self.result["diagnostics"])

    def test_absolute_particle_position_compiles_and_angle_stays_fail_closed(self) -> None:
        binding = self.binding("particle:80:controlpoint:1")
        self.assertEqual(binding["valueType"], "vector3")
        self.assertEqual(binding["authored"], "vector3(10.0,20.0,30.0)")
        self.assertNotIn("particle:80:angles:1", self.targets())
        self.assertIn(
            "layer 80 instanceoverride.controlpointangle1: relativeUnsupported",
            self.result["diagnostics"],
        )

    def test_particle_timeline_rejects_lane_mismatch_and_invalid_authored_vector(self) -> None:
        self.assertNotIn("particle:80:controlpoint:2", self.targets())
        self.assertNotIn("particle:80:controlpoint:3", self.targets())
        self.assertNotIn("particle:80:controlpoint:4", self.targets())
        self.assertIn(
            "layer 80 instanceoverride.controlpoint2: componentMismatch",
            self.result["diagnostics"],
        )
        self.assertIn(
            "layer 80 instanceoverride.controlpoint3: invalidAuthoredValue",
            self.result["diagnostics"],
        )
        self.assertIn(
            "layer 80 instanceoverride.controlpoint4: invalidAuthoredValue",
            self.result["diagnostics"],
        )

    def test_only_expected_targets_are_produced(self) -> None:
        self.assertEqual(
            self.targets(),
            {
                "layer:10:alpha",
                "layer:20:angles",
                "layer:40:angles",
                "layer:41:origin",
                "layer:42:scale",
                "constant:30:1:1:multiply",
                "layer:70:alpha",
                "particle:80:controlpoint:1",
            },
        )


if __name__ == "__main__":
    unittest.main()
