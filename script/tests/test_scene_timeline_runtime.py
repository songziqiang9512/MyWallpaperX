#!/usr/bin/env python3
"""Timeline 每帧值产出门。

覆盖 host 每帧要做的两件事：把 Timeline definition 并进 property definitions，
以及按绝对 scene time 求出该帧的全部 Timeline 值。

`SceneDynamicSnapshotResolver` 对不在 definitions 里的 target 判 `unknownTarget`
丢弃，对重复 definition 判 `duplicateDefinition` 把该 target 整个丢掉——两条都会
让 Timeline 静默失效，所以这里直接用真实 resolver 走完整条链路来断言。
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
    SOURCE_ROOT / "Format/SceneCompatibilityContext.swift",
    SOURCE_ROOT / "Format/SceneDocument.swift",
    SOURCE_ROOT / "Format/SceneDocument+General.swift",
    SOURCE_ROOT / "Format/SceneDocument+ShaderValue.swift",
    SOURCE_ROOT / "Format/SceneDocument+Timeline.swift",
    SOURCE_ROOT / "Format/SceneDocumentObject.swift",
    SOURCE_ROOT / "Format/SceneObjectDependency.swift",
    SOURCE_ROOT / "Format/SceneDirectionalLightDefinition.swift",
    SOURCE_ROOT / "Format/SceneSpotLightDefinition.swift",
    SOURCE_ROOT / "Text/SceneTextScriptDefinition.swift",
    SOURCE_ROOT / "Format/SceneDocument+NumericParsing.swift",
    SOURCE_ROOT / "Format/ScenePuppetAnimationLayer.swift",
    SOURCE_ROOT / "Format/SceneTimelineAnimation.swift",
    SOURCE_ROOT / "Format/SceneTimelineEvaluator.swift",
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Format/SceneScriptBindingDefinition.swift",
    SOURCE_ROOT / "Format/SceneScriptSourceEvidence.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinition.swift",
    SOURCE_ROOT / "Particles/SceneParticleInitializer.swift",
    SOURCE_ROOT / "Particles/SceneParticleVortex.swift",
    SOURCE_ROOT / "Particles/SceneParticleRemapValue.swift",
    SOURCE_ROOT / "Particles/SceneParticleReduceMovement.swift",
    SOURCE_ROOT / "Particles/SceneParticleCollisionPlane.swift",
    SOURCE_ROOT / "Particles/SceneParticlePositionAroundControlPoint.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+Operator.swift",
    SOURCE_ROOT / "Particles/SceneParticleDefinitionParser+InstanceOverride.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectDefinition.swift",
    SOURCE_ROOT / "RenderGraph/SceneEffectTextureInput.swift",
    SOURCE_ROOT / "Rendering/SceneUtilityLayer.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor+Layer.swift",
    SOURCE_ROOT / "Runtime/SceneRenderDescriptor+AuthoredAssets.swift",
    SOURCE_ROOT / "Text/SceneTextDescriptor.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Properties/SceneSurfaceEvaluationTransaction.swift",
    SOURCE_ROOT / "Properties/SceneTimelineTargetCompiler.swift",
    SOURCE_ROOT / "Properties/SceneTimelineTargetCompiler+Camera.swift",
    SOURCE_ROOT / "Properties/SceneTimelineRuntime.swift",
    SOURCE_ROOT / "Properties/SceneTimelinePlaybackRuntime.swift",
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


SCENE_FIXTURE = {
    "version": 3,
    "objects": [
        {
            "id": 10,
            "name": "Loop alpha",
            "image": "models/user/a.json",
            "size": "100 100",
            "alpha": {
                "value": 0.25,
                "animation": {
                    "c0": [keyframe(0, 0), keyframe(30, 1)],
                    "options": {
                        "fps": 30,
                        "length": 60,
                        "mode": "loop",
                        "wraploop": True,
                    },
                },
            },
        },
        {
            "id": 20,
            "name": "Effect constant",
            "image": "models/user/b.json",
            "size": "100 100",
            "effects": [
                {
                    "file": "effects/pulse/effect.json",
                    "passes": [
                        {
                            "constantshadervalues": {
                                "multiply": {
                                    "value": 1,
                                    "animation": {
                                        "c0": [keyframe(0, 1), keyframe(15, 0)],
                                        "options": {
                                            "fps": 15,
                                            "length": 15,
                                            "mode": "single",
                                        },
                                    },
                                },
                                "neutralVector": {
                                    "value": "0.2 0.4 0.6",
                                    "animation": {
                                        "c0": [keyframe(0, 0.2), keyframe(15, 0.8)],
                                        "c1": [keyframe(0, 0.4), keyframe(15, 0.1)],
                                        "c2": [keyframe(0, 0.6), keyframe(15, 0.3)],
                                        "options": {
                                            "fps": 15,
                                            "length": 15,
                                            "mode": "single",
                                        },
                                    },
                                }
                            }
                        }
                    ],
                }
            ],
        },
        {
            "id": 30,
            "name": "Start paused",
            "image": "models/user/c.json",
            "size": "100 100",
            "alpha": {
                "value": 1,
                "animation": {
                    "c0": [keyframe(0, 1), keyframe(60, 0)],
                    "options": {
                        "fps": 30,
                        "length": 60,
                        "mode": "single",
                        "startpaused": True,
                    },
                },
            },
        },
        {
            "id": 40,
            "name": "Relative angles",
            "image": "models/user/d.json",
            "size": "100 100",
            "angles": {
                "value": "0.5 1.5 2.5",
                "animation": {
                    "c0": [keyframe(0, 0), keyframe(60, 1)],
                    "c1": [keyframe(0, 0), keyframe(60, 2)],
                    "c2": [keyframe(0, 0), keyframe(60, 3)],
                    "options": {"fps": 30, "length": 60, "mode": "loop"},
                    "relative": True,
                },
            },
        },
        {
            "id": 50,
            "name": "Combined camera path",
            "camera": "default",
            "path": "scripts/camera_path.json",
            "queuemode": "sequential",
            "origin": {
                "value": "0 0 500",
                "animation": {
                    "c0": [keyframe(0, -100), keyframe(180, 0)],
                    "c1": [keyframe(0, 682), keyframe(180, 0)],
                    "c2": [keyframe(0, 0), keyframe(180, 0)],
                    "options": {
                        "fps": 30,
                        "length": 180,
                        "mode": "single",
                        "children": [{"key": "zoom"}],
                    },
                    "relative": True,
                },
            },
            "zoom": {
                "value": 1,
                "animation": {
                    "c0": [keyframe(0, 2.4), keyframe(180, 1)],
                    # 故意给 child 一套不同 clock；Combined 必须使用 owner clock。
                    "options": {
                        "fps": 5,
                        "length": 5,
                        "mode": "loop",
                        "parent": {"key": "origin"},
                    },
                },
            },
        },
    ],
}

HARNESS_SOURCE = r'''
import Foundation

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

        // 模拟 host：一个已有的 property definition 与 layer 10 的 alpha 撞 target。
        let sharedTarget = SceneDynamicTarget.layer(layerID: 10, field: .alpha)
        let propertyDefinitions = [
            SceneDynamicTargetDefinition(
                target: sharedTarget, valueType: .scalar, authoredValue: .scalar(0.25)
            ),
        ]
        let merged = SceneTimelineRuntime.mergedDefinitions(
            propertyDefinitions: propertyDefinitions, timelineProgram: program
        )

        var payload: [String: Any] = [
            "definitionCount": merged.count,
            "sharedTargetDefinitionCount": merged.filter { $0.target == sharedTarget }.count,
            "bindingCount": program.bindings.count,
        ]

        // 走真实 resolver：断言 Timeline 值真的落进 snapshot 而不是被丢弃。
        var samples: [String: Any] = [:]
        var transaction = SceneSurfaceEvaluationTransaction()
        for (frameIndex, sample) in [
            ("t0", 0.0), ("half", 1.0), ("closing", 1.5), ("late", 5.0),
            ("lateAgain", 5.0),
        ].enumerated() {
            let (label, seconds) = sample
            let values = SceneTimelineRuntime.values(program: program, sceneTime: seconds)
            let resolution = transaction.evaluate(
                frameIndex: UInt64(frameIndex),
                definitions: merged,
                userValues: [sharedTarget: .scalar(0.25)],
                timelineValues: values
            )
            var entry: [String: Any] = [
                "diagnostics": resolution.diagnostics.map { $0.code.rawValue },
                "generation": resolution.snapshot.generation,
            ]
            for (name, target) in [
                ("layer10Alpha", sharedTarget),
                ("layer30Alpha", SceneDynamicTarget.layer(layerID: 30, field: .alpha)),
                ("constant", SceneDynamicTarget.effectConstant(
                    layerID: 20, effectIndex: 0, passIndex: 0, name: "multiply"
                )),
            ] {
                if let resolved = resolution.snapshot[target],
                   case let .scalar(v) = resolved.value {
                    entry[name] = ["value": v, "source": resolved.source.rawValue]
                }
            }
            let relativeTarget = SceneDynamicTarget.layer(layerID: 40, field: .angles)
            if let resolved = resolution.snapshot[relativeTarget],
               case let .vector3(x, y, z) = resolved.value {
                entry["relativeAngles"] = [
                    "value": [x, y, z], "source": resolved.source.rawValue,
                ]
            }
            let effectVectorTarget = SceneDynamicTarget.effectConstant(
                layerID: 20, effectIndex: 0, passIndex: 0, name: "neutralVector"
            )
            if let resolved = resolution.snapshot[effectVectorTarget],
               case let .vector3(x, y, z) = resolved.value {
                entry["effectVector"] = [
                    "value": [x, y, z], "source": resolved.source.rawValue,
                ]
            }
            if let resolved = resolution.snapshot[.camera(.origin)],
               case let .vector3(x, y, z) = resolved.value {
                entry["cameraOrigin"] = [
                    "value": [x, y, z], "source": resolved.source.rawValue,
                ]
            }
            if let resolved = resolution.snapshot[.camera(.zoom)],
               case let .scalar(value) = resolved.value {
                entry["cameraZoom"] = [
                    "value": value, "source": resolved.source.rawValue,
                ]
            }
            samples[label] = entry
        }
        payload["samples"] = samples

        let pausedTarget = SceneDynamicTarget.layer(layerID: 30, field: .alpha)
        let playback = SceneTimelinePlaybackRuntime(program: program)
        func playbackScalar(_ time: Double, _ target: SceneDynamicTarget) -> Double? {
            guard case let .scalar(value)? = playback.values(sceneTime: time)[target]
            else { return nil }
            return value
        }
        var playbackPayload: [String: Any] = [
            "paused": playbackScalar(5, pausedTarget) ?? -1,
            "autoplay": playbackScalar(1, sharedTarget) ?? -1,
        ]
        _ = playback.apply(
            [.init(target: pausedTarget, command: .play)],
            sceneTime: 5
        )
        playbackPayload["played"] = playbackScalar(6, pausedTarget) ?? -1
        _ = playback.apply(
            [.init(target: pausedTarget, command: .pause)],
            sceneTime: 6
        )
        playbackPayload["held"] = playbackScalar(9, pausedTarget) ?? -1
        _ = playback.apply(
            [.init(target: pausedTarget, command: .stop)],
            sceneTime: 9
        )
        playbackPayload["stopped"] = playbackScalar(10, pausedTarget) ?? -1
        let invalidTarget = SceneDynamicTarget.layer(layerID: 999, field: .alpha)
        let atomic = playback.apply([
            .init(target: pausedTarget, command: .play),
            .init(target: invalidTarget, command: .pause),
        ], sceneTime: 10)
        if case .failure = atomic {
            playbackPayload["atomicRejected"] = true
        } else {
            playbackPayload["atomicRejected"] = false
        }
        playbackPayload["afterRejected"] = playbackScalar(11, pausedTarget) ?? -1
        payload["playback"] = playbackPayload
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        ), as: UTF8.self))
    }
}
'''


class SceneTimelineRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-timeline-runtime-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        scene = directory / "scene.json"
        scene.write_text(json.dumps(SCENE_FIXTURE), encoding="utf-8")
        binary = directory / "scene-timeline-runtime"
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

    def test_shared_target_is_not_duplicated_in_definitions(self) -> None:
        # 七条 binding：既有四条、vector effect constant、camera origin/zoom 原子组。
        self.assertEqual(self.result["bindingCount"], 7)
        # layer10 alpha 两边都声明，合并后只能有一份，否则 resolver 会整个丢弃
        self.assertEqual(self.result["sharedTargetDefinitionCount"], 1)
        # 1 条 property + 6 条 timeline 独有
        self.assertEqual(self.result["definitionCount"], 7)

    def test_resolver_accepts_every_timeline_value(self) -> None:
        for label in ("t0", "half", "closing", "late", "lateAgain"):
            with self.subTest(sample=label):
                self.assertEqual(self.result["samples"][label]["diagnostics"], [])

    def test_timeline_outranks_the_user_property_on_a_shared_target(self) -> None:
        # 同一 target 上 property 给 0.25，Timeline 在 t=1s（第 30 帧）给峰值 1
        entry = self.result["samples"]["half"]["layer10Alpha"]
        self.assertEqual(entry["source"], "timeline")
        self.assertAlmostEqual(entry["value"], 1.0)

    def test_loop_wraps_while_single_holds_its_final_value(self) -> None:
        # layer10 前半周期 0→1，后半周期由 wrap 段 1→0；t=1.5s 位于闭合段中点。
        self.assertAlmostEqual(
            self.result["samples"]["closing"]["layer10Alpha"]["value"], 0.5
        )
        # t=5s 落在第 30 帧，与 t=1s 同相位。
        self.assertAlmostEqual(
            self.result["samples"]["late"]["layer10Alpha"]["value"], 1.0
        )
        # constant 是 1 秒的 single：t=1s 已到末帧，t=5s 仍保持 0
        self.assertAlmostEqual(self.result["samples"]["half"]["constant"]["value"], 0.0)
        self.assertAlmostEqual(self.result["samples"]["late"]["constant"]["value"], 0.0)
        self.assertAlmostEqual(self.result["samples"]["t0"]["constant"]["value"], 1.0)

    def test_start_paused_layer_never_leaves_its_first_frame(self) -> None:
        for label in ("t0", "half", "closing", "late"):
            with self.subTest(sample=label):
                entry = self.result["samples"][label]["layer30Alpha"]
                self.assertAlmostEqual(entry["value"], 1.0)
                # 仍然由 timeline 提供，只是值恒定——不是回落到 authored
                self.assertEqual(entry["source"], "timeline")

    def test_playback_runtime_resumes_pauses_stops_and_rejects_atomically(self) -> None:
        playback = self.result["playback"]
        self.assertAlmostEqual(playback["paused"], 1.0)
        self.assertAlmostEqual(playback["autoplay"], 1.0)
        self.assertAlmostEqual(playback["played"], 0.5)
        self.assertAlmostEqual(playback["held"], 0.5)
        self.assertAlmostEqual(playback["stopped"], 1.0)
        self.assertTrue(playback["atomicRejected"])
        self.assertAlmostEqual(playback["afterRejected"], 1.0)

    def test_relative_transform_adds_lane_values_to_authored_base(self) -> None:
        self.assertEqual(
            self.result["samples"]["t0"]["relativeAngles"]["value"],
            [0.5, 1.5, 2.5],
        )
        self.assertEqual(
            self.result["samples"]["half"]["relativeAngles"]["value"],
            [1.0, 2.5, 4.0],
        )
        self.assertEqual(
            self.result["samples"]["half"]["relativeAngles"]["source"],
            "timeline",
        )

    def test_effect_vector_flows_through_evaluator_and_snapshot(self) -> None:
        self.assertEqual(
            self.result["samples"]["t0"]["effectVector"],
            {"value": [0.2, 0.4, 0.6], "source": "timeline"},
        )
        self.assertEqual(
            self.result["samples"]["half"]["effectVector"],
            {"value": [0.8, 0.1, 0.3], "source": "timeline"},
        )
        self.assertEqual(
            self.result["samples"]["late"]["effectVector"],
            {"value": [0.8, 0.1, 0.3], "source": "timeline"},
        )

    def test_value_change_advances_generation_but_same_value_does_not(self) -> None:
        samples = self.result["samples"]
        self.assertGreater(samples["half"]["generation"], samples["t0"]["generation"])
        self.assertGreater(samples["late"]["generation"], samples["closing"]["generation"])
        self.assertEqual(samples["lateAgain"]["generation"], samples["late"]["generation"])

    def test_combined_camera_members_share_the_owner_clock_and_snapshot(self) -> None:
        self.assertEqual(
            self.result["samples"]["t0"]["cameraOrigin"]["value"],
            [-100, 682, 500],
        )
        self.assertAlmostEqual(
            self.result["samples"]["late"]["cameraOrigin"]["value"][0],
            -1.1481318114443,
        )
        self.assertAlmostEqual(
            self.result["samples"]["late"]["cameraZoom"]["value"],
            1.0160738453602203,
        )
        for key in ("cameraOrigin", "cameraZoom"):
            self.assertEqual(
                self.result["samples"]["late"][key]["source"], "timeline"
            )


if __name__ == "__main__":
    unittest.main()
