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
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredMaterialResolver.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredLocalContrastPlanner.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionChain.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectExecutionPlan+Backend.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredPreciseBlurPlanner+Topology.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredStandardBlurPlanner.swift",
]


HARNESS = r'''
import Foundation

struct SceneDocument {
    struct ShaderValue {
        let valueKind: String
        let userBinding: String?
        let components: [Double]?

        init(
            valueKind: String = "vector",
            userBinding: String? = nil,
            components: [Double]?
        ) {
            self.valueKind = valueKind
            self.userBinding = userBinding
            self.components = components
        }
    }
}

struct SceneEffectTextureInput {
    let name: String
}

struct SceneGaussianBlurPlan {
    let horizontalStep: Float
    let verticalStep: Float
    let sampleResolutionScale: Float
    let isPrecise: Bool
}

struct SceneWorkshopShadowExecutionPlan: Equatable, Sendable {
    let alpha: Float
    let color: SIMD3<Float>
    let drawBorder: Float
    let offset: SIMD2<Float>
}

struct SceneOpacityExecutionPlan: Sendable {
    var liveAlphaTarget: SceneDynamicTarget? { nil }

    func resolvedAlpha(in snapshot: SceneDynamicSnapshot) -> Float { 1 }
}

enum SceneAuthoredOpacityPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneOpacityExecutionPlan? {
        nil
    }
}

enum SceneAuthoredWorkshopShadowPlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneWorkshopShadowExecutionPlan? {
        nil
    }
}

struct SceneShakeExecutionPlan {}

enum SceneAuthoredShakePlanner {
    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) -> SceneShakeExecutionPlan? {
        nil
    }
}

struct SceneRenderDescriptor {
    struct EffectDescriptor {
        struct PassDescriptor {
            let passIndex: Int
            let textureSlots: [String?]
            let userTextureInputs: [SceneEffectTextureInput?]
            let combos: [String: Int]
            let constantShaderValues: [String: SceneDocument.ShaderValue]
        }

        let id: String
        let visible: Bool?
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let parentID: Int?
        let visible: Bool?
        let contentKind: String
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let shaderPath: String?
        let textureSlots: [String?]
        let userTextureInputs: [SceneEffectTextureInput?]
        let combos: [String: Int]
        let constantShaderValues: [String: SceneDocument.ShaderValue]
        let blending: String?
        let depthTest: String?
        let depthWrite: String?
        let cullMode: String?
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}

enum SceneLayerVisibility {
    static func visibleLayerIDs(in descriptor: SceneRenderDescriptor) -> Set<Int> {
        let layers = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0) })
        return Set(descriptor.layers.compactMap { layer in
            var current: SceneRenderDescriptor.Layer? = layer
            var visited = Set<Int>()
            while let candidate = current {
                guard candidate.visible != false,
                      visited.insert(candidate.id).inserted else {
                    return nil
                }
                current = candidate.parentID.flatMap { layers[$0] }
            }
            return layer.id
        })
    }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan

    static let layerID = 42

    static func texture(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func effectDescriptor(
        index: Int,
        verticalCombos: [String: Int] = ["VERTICAL": 1, "ENABLEMASK": 1]
    ) -> SceneRenderDescriptor.EffectDescriptor {
        let scale = SceneDocument.ShaderValue(components: [0.75, 0.75])
        return .init(
            id: "42#effect#\(index)",
            visible: true,
            passes: [
                .init(
                    passIndex: 0,
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: [:],
                    constantShaderValues: ["scale": scale]
                ),
                .init(
                    passIndex: 1,
                    textureSlots: [],
                    userTextureInputs: [],
                    combos: verticalCombos,
                    constantShaderValues: ["scale": scale]
                ),
            ]
        )
    }

    static func materials() -> [SceneRenderDescriptor.MaterialPassDescriptor] {
        func material(
            id: String,
            path: String,
            combos: [String: Int]
        ) -> SceneRenderDescriptor.MaterialPassDescriptor {
            .init(
                id: id,
                materialPath: path,
                shaderPath: "effects/blur_precise_gaussian",
                textureSlots: [],
                userTextureInputs: [],
                combos: combos,
                constantShaderValues: [:],
                blending: "normal",
                depthTest: "disabled",
                depthWrite: "disabled",
                cullMode: "nocull"
            )
        }
        return [
            material(id: "materials/precise_x.json#0", path: "materials/precise_x.json", combos: [:]),
            material(
                id: "materials/precise_y.json#0",
                path: "materials/precise_y.json",
                combos: ["VERTICAL": 1, "ENABLEMASK": 1]
            ),
        ]
    }

    static func descriptor(
        visible: Bool = true,
        unsupportedSecond: Bool = false
    ) -> SceneRenderDescriptor {
        let secondCombos = unsupportedSecond
            ? ["VERTICAL": 2, "ENABLEMASK": 1]
            : ["VERTICAL": 1, "ENABLEMASK": 1]
        return .init(
            layers: [
                .init(
                    id: layerID,
                    parentID: nil,
                    visible: visible,
                    contentKind: "text",
                    effects: [
                        effectDescriptor(index: 0),
                        effectDescriptor(index: 1, verticalCombos: secondCombos),
                    ]
                ),
            ],
            materialPasses: materials()
        )
    }

    static func chainGraph(
        discontinuousInput: Bool = false,
        duplicateNodeIndex: Bool = false,
        extraTarget: Bool = false,
        secondDefinitionPath: String = "effects/workshop/blurprecise/effect.json",
        hasBlocker: Bool = false
    ) -> Graph {
        let firstKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 0,
            descriptorID: "42#effect#0"
        )
        let secondKey = Graph.EffectKey(
            layerID: layerID,
            effectIndex: 1,
            descriptorID: "42#effect#1"
        )
        let source = texture(.layerSource)
        let firstOutput = texture(.effectOutput, effect: firstKey)
        let secondInput = discontinuousInput ? source : firstOutput
        let secondOutput = texture(.effectOutput, effect: secondKey)
        let firstTarget = texture(.framebuffer, effect: firstKey, name: "first")
        let secondTarget = texture(.framebuffer, effect: secondKey, name: "second")
        let extra = texture(.framebuffer, effect: secondKey, name: "extra")
        let secondFirstNodeIndex = duplicateNodeIndex ? 1 : 2

        func node(
            index: Int,
            effect: Graph.EffectKey,
            ordinal: Int,
            target: Graph.TextureIdentity,
            bindings: [Graph.Binding]
        ) -> Graph.Node {
            let material = ordinal == 0 ? "materials/precise_x.json" : "materials/precise_y.json"
            return .init(
                nodeIndex: index,
                effect: effect,
                definitionPassIndex: ordinal,
                materialOrdinal: ordinal,
                instancePassIndex: ordinal,
                kind: .material,
                materialPath: material,
                materialPassID: "\(material)#0",
                target: target,
                bindings: bindings,
                commandSource: nil,
                commandTarget: nil,
                compose: nil,
                conditions: nil
            )
        }

        let nodes = [
            node(index: 0, effect: firstKey, ordinal: 0, target: firstTarget, bindings: []),
            node(
                index: 1,
                effect: firstKey,
                ordinal: 1,
                target: firstOutput,
                bindings: [
                    .init(slot: 0, authoredName: "first", texture: firstTarget, conditions: nil),
                    .init(slot: 1, authoredName: "previous", texture: source, conditions: nil),
                ]
            ),
            node(
                index: secondFirstNodeIndex,
                effect: secondKey,
                ordinal: 0,
                target: secondTarget,
                bindings: []
            ),
            node(
                index: 3,
                effect: secondKey,
                ordinal: 1,
                target: secondOutput,
                bindings: [
                    .init(slot: 0, authoredName: "second", texture: secondTarget, conditions: nil),
                    .init(slot: 1, authoredName: "previous", texture: secondInput, conditions: nil),
                ]
            ),
        ]
        let effects = [
            Graph.Effect(
                key: firstKey,
                definitionPath: "effects/workshop/blurprecise/effect.json",
                input: source,
                output: firstOutput,
                nodeIndices: [0, 1]
            ),
            Graph.Effect(
                key: secondKey,
                definitionPath: secondDefinitionPath,
                input: secondInput,
                output: secondOutput,
                nodeIndices: [secondFirstNodeIndex, 3]
            ),
        ]
        var targets = [firstTarget, secondTarget].map {
            Graph.RenderTarget(
                texture: $0,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            )
        }
        if extraTarget {
            targets.append(.init(
                texture: extra,
                extent: .init(kind: .input, first: nil, second: nil),
                format: "rgba_backbuffer",
                declaredUnique: false,
                clear: nil,
                uvs: nil,
                conditions: nil
            ))
        }
        let blockers: [Graph.Blocker] = hasBlocker ? [
            .init(
                effect: secondKey,
                definitionPassIndex: 1,
                reason: .unsupportedCondition,
                detail: "synthetic blocker"
            ),
        ] : []
        return .init(
            layerID: layerID,
            effects: effects,
            renderTargets: targets,
            nodes: nodes,
            finalOutput: secondOutput,
            blockers: blockers
        )
    }

    static func roleName(_ role: SceneAuthoredEffectInputRole) -> String {
        switch role {
        case .layerSource: "layerSource"
        case .priorEffectOutput: "priorEffectOutput"
        }
    }

    static func catalogState(
        descriptor: SceneRenderDescriptor,
        graphs: [Graph]
    ) -> [String: Any] {
        let catalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: descriptor,
            authoredPlans: graphs
        )
        return [
            "chainLayers": catalog.chainsByLayerID.keys.sorted(),
            "singleStageLayers": catalog.plansByLayerID.keys.sorted(),
            "hidden": catalog.hiddenEligibleLayerIDs,
            "legacyBlocked": catalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
        ]
    }

    static func rejected(
        graph: Graph,
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        SceneAuthoredEffectChainPlanner.plan(
            graph: graph,
            descriptor: descriptor,
            shaderContracts: []
        ) == nil
    }

    static func main() throws {
        let validDescriptor = descriptor()
        let validGraph = chainGraph()
        let chain = SceneAuthoredEffectChainPlanner.plan(
            graph: validGraph,
            descriptor: validDescriptor,
            shaderContracts: []
        )!
        let catalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: validDescriptor,
            authoredPlans: [validGraph]
        )
        let firstOutput = validGraph.effects[0].output

        let unsupportedDescriptor = descriptor(unsupportedSecond: true)
        let mixedGraph = chainGraph(
            secondDefinitionPath: "effects/water/effect.json"
        )
        let failureCatalogs: [String: [String: Any]] = [
            "unsupportedSecond": catalogState(
                descriptor: unsupportedDescriptor,
                graphs: [validGraph]
            ),
            "blocker": catalogState(
                descriptor: validDescriptor,
                graphs: [chainGraph(hasBlocker: true)]
            ),
            "discontinuousInput": catalogState(
                descriptor: validDescriptor,
                graphs: [chainGraph(discontinuousInput: true)]
            ),
            "duplicateNode": catalogState(
                descriptor: validDescriptor,
                graphs: [chainGraph(duplicateNodeIndex: true)]
            ),
            "extraTarget": catalogState(
                descriptor: validDescriptor,
                graphs: [chainGraph(extraTarget: true)]
            ),
            "mixedUnsupported": catalogState(
                descriptor: unsupportedDescriptor,
                graphs: [mixedGraph]
            ),
            "multipleCandidates": catalogState(
                descriptor: validDescriptor,
                graphs: [validGraph, validGraph]
            ),
        ]
        let hiddenCatalog = SceneAuthoredEffectExecutionCatalog(
            descriptor: descriptor(visible: false),
            authoredPlans: [validGraph]
        )

        let result: [String: Any] = [
            "success": [
                "effectOrder": chain.stages.map { $0.renderGraph.effects[0].key.effectIndex },
                "nodeIndices": chain.stages.map { $0.renderGraph.nodes.map(\.nodeIndex) },
                "effectNodeIndices": chain.stages.map { $0.renderGraph.effects[0].nodeIndices },
                "inputRoles": chain.stages.map { roleName($0.inputRole) },
                "secondInputIsPriorOutput": chain.stages[1].renderGraph.effects[0].input == firstOutput,
                "secondPreviousBindingIsPriorOutput":
                    chain.stages[1].renderGraph.nodes[1].bindings
                        .first(where: { $0.slot == 1 })?.texture == firstOutput,
                "stageCount": chain.stages.count,
                "materialNodeCount": chain.materialNodeCount,
                "logicalTargetCount": chain.logicalRenderTargetCount,
                "localContrastCount": chain.localContrastCount,
                "liveTargetCount": chain.liveConsumerTargets.count,
                "bothPrecise": chain.stages.allSatisfy { $0.gaussianBlur != nil },
            ],
            "catalog": [
                "chainLayers": catalog.chainsByLayerID.keys.sorted(),
                "singleStageLayers": catalog.plansByLayerID.keys.sorted(),
                "legacyBlocked": catalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
                "liveTargetCount": catalog.liveConsumerTargets.count,
                "reportLines": catalog.reportLines,
            ],
            "directRejections": [
                "unsupportedSecond": rejected(
                    graph: validGraph,
                    descriptor: unsupportedDescriptor
                ),
                "blocker": rejected(
                    graph: chainGraph(hasBlocker: true),
                    descriptor: validDescriptor
                ),
                "discontinuousInput": rejected(
                    graph: chainGraph(discontinuousInput: true),
                    descriptor: validDescriptor
                ),
                "duplicateNode": rejected(
                    graph: chainGraph(duplicateNodeIndex: true),
                    descriptor: validDescriptor
                ),
                "extraTarget": rejected(
                    graph: chainGraph(extraTarget: true),
                    descriptor: validDescriptor
                ),
                "mixedUnsupported": rejected(
                    graph: mixedGraph,
                    descriptor: unsupportedDescriptor
                ),
            ],
            "failureCatalogs": failureCatalogs,
            "hidden": [
                "chainLayers": hiddenCatalog.chainsByLayerID.keys.sorted(),
                "singleStageLayers": hiddenCatalog.plansByLayerID.keys.sorted(),
                "eligible": hiddenCatalog.hiddenEligibleLayerIDs,
                "legacyBlocked": hiddenCatalog.legacyGaussianBlurBlockedLayerIDs.sorted(),
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneAuthoredEffectChainPlannerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-authored-effect-chain-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-authored-effect-chain"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_two_precise_stages_preserve_authored_chain_identity(self) -> None:
        success = self.result["success"]
        self.assertEqual(success["effectOrder"], [0, 1])
        self.assertEqual(success["nodeIndices"], [[0, 1], [2, 3]])
        self.assertEqual(success["effectNodeIndices"], [[0, 1], [2, 3]])
        self.assertEqual(success["inputRoles"], ["layerSource", "priorEffectOutput"])
        self.assertTrue(success["secondInputIsPriorOutput"])
        self.assertTrue(success["secondPreviousBindingIsPriorOutput"])
        self.assertTrue(success["bothPrecise"])
        self.assertEqual(success["stageCount"], 2)
        self.assertEqual(success["materialNodeCount"], 4)
        self.assertEqual(success["logicalTargetCount"], 2)
        self.assertEqual(success["localContrastCount"], 0)
        self.assertEqual(success["liveTargetCount"], 0)

    def test_catalog_reports_chain_counts_without_exposing_single_stage_plan(self) -> None:
        catalog = self.result["catalog"]
        self.assertEqual(catalog["chainLayers"], [42])
        self.assertEqual(catalog["singleStageLayers"], [])
        self.assertEqual(catalog["legacyBlocked"], [])
        self.assertEqual(catalog["liveTargetCount"], 0)
        for line in (
            "authoredEffectGraphPlannedCount: 1",
            "authoredEffectGraphMaterialNodeCount: 4",
            "authoredEffectGraphLogicalRTCount: 2",
            "authoredEffectGraphChainCount: 1",
            "authoredEffectGraphStageCount: 2",
            "authoredEffectGraphLocalContrastCount: 0",
            "authoredEffectGraphWorkshopShadowCount: 0",
        ):
            self.assertIn(line, catalog["reportLines"])

    def test_invalid_second_stage_or_outer_graph_fails_the_whole_chain(self) -> None:
        for name, rejected in self.result["directRejections"].items():
            self.assertTrue(rejected, name)

        for name, catalog in self.result["failureCatalogs"].items():
            self.assertEqual(catalog["chainLayers"], [], name)
            self.assertEqual(catalog["singleStageLayers"], [], name)
            self.assertEqual(catalog["hidden"], [], name)
            self.assertEqual(catalog["legacyBlocked"], [42], name)

    def test_hidden_complete_chain_is_not_runtime_eligible(self) -> None:
        hidden = self.result["hidden"]
        self.assertEqual(hidden["chainLayers"], [])
        self.assertEqual(hidden["singleStageLayers"], [])
        self.assertEqual(hidden["eligible"], [42])
        self.assertEqual(hidden["legacyBlocked"], [])


if __name__ == "__main__":
    unittest.main()
