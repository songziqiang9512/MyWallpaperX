#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneGraphConditionAdmission.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneGraphAdmissionCompiler.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
]


HARNESS = r'''
import Foundation

struct SceneRenderDescriptor {
    struct PassDescriptor {
        let passIndex: Int
        let combos: [String: Int]
    }

    struct EffectDescriptor {
        let id: String
        let passes: [PassDescriptor]
    }

    struct Layer {
        let id: Int
        let effects: [EffectDescriptor]
    }

    struct MaterialPassDescriptor {
        let id: String
        let materialPath: String
        let combos: [String: Int]
    }

    let layers: [Layer]
    let materialPasses: [MaterialPassDescriptor]
}

struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    var supportsUnifiedFullFrameComposeStage: Bool { false }
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Product = SceneGraphAdmissionProduct

    static let layerID = 100
    static let key = Graph.EffectKey(
        layerID: layerID,
        effectIndex: 0,
        descriptorID: "conditional-fbo-command-contract"
    )
    static let source = SceneAuthoredEffectInputValidator.layerSource(
        layerID: layerID
    )
    static let output = Graph.TextureIdentity(
        kind: .effectOutput,
        layerID: layerID,
        effect: key,
        name: nil
    )

    static func framebuffer(_ name: String) -> Graph.TextureIdentity {
        .init(kind: .framebuffer, layerID: layerID, effect: key, name: name)
    }

    static let branch = framebuffer("branch")
    static let a = framebuffer("a")
    static let b = framebuffer("b")

    static func branchCondition() -> SceneJSONValue {
        .array([.object(["BRANCH": .number(1)])])
    }

    static func target(
        _ identity: Graph.TextureIdentity,
        conditions: SceneJSONValue? = nil
    ) -> Graph.RenderTarget {
        .init(
            texture: identity,
            extent: .init(width: nil, height: nil, fit: nil, scale: 2),
            format: "rgba8888",
            declaredUnique: true,
            clear: .array([.number(0), .number(0), .number(0), .number(0)]),
            uvs: nil,
            conditions: conditions
        )
    }

    static func binding(
        slot: Int,
        texture: Graph.TextureIdentity,
        conditions: SceneJSONValue? = nil
    ) -> Graph.Binding {
        .init(
            slot: slot,
            authoredName: texture.name ?? "previous",
            texture: texture,
            conditions: conditions
        )
    }

    static func material(
        nodeIndex: Int,
        definitionPassIndex: Int,
        ordinal: Int,
        target: Graph.TextureIdentity,
        bindings: [Graph.Binding] = [],
        conditions: SceneJSONValue? = nil
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: definitionPassIndex,
            materialOrdinal: ordinal,
            instancePassIndex: ordinal,
            kind: .material,
            materialPath: "materials/\(ordinal).json",
            materialPassID: "material-\(ordinal)",
            target: target,
            bindings: bindings,
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: conditions
        )
    }

    static func command(
        nodeIndex: Int,
        definitionPassIndex: Int,
        kind: Graph.NodeKind,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: definitionPassIndex,
            materialOrdinal: nil,
            instancePassIndex: nil,
            kind: kind,
            materialPath: nil,
            materialPassID: nil,
            target: nil,
            bindings: [],
            commandSource: source,
            commandTarget: target,
            compose: nil,
            conditions: nil
        )
    }

    static func graph(
        consumerBindingIsConditional: Bool = true
    ) -> Graph {
        let condition = branchCondition()
        let nodes = [
            material(
                nodeIndex: 10,
                definitionPassIndex: 0,
                ordinal: 0,
                target: branch,
                conditions: condition
            ),
            material(
                nodeIndex: 20,
                definitionPassIndex: 1,
                ordinal: 1,
                target: a,
                bindings: [binding(
                    slot: 0,
                    texture: branch,
                    conditions: consumerBindingIsConditional ? condition : nil
                )]
            ),
            command(
                nodeIndex: 30,
                definitionPassIndex: 2,
                kind: .copy,
                source: a,
                target: b
            ),
            material(
                nodeIndex: 40,
                definitionPassIndex: 3,
                ordinal: 2,
                target: a
            ),
            command(
                nodeIndex: 50,
                definitionPassIndex: 4,
                kind: .swap,
                source: a,
                target: b
            ),
            material(
                nodeIndex: 60,
                definitionPassIndex: 5,
                ordinal: 3,
                target: output,
                bindings: [binding(slot: 0, texture: a)]
            ),
        ]
        return .init(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/contract/effect.json",
                input: source,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: [
                target(branch, conditions: condition),
                target(a),
                target(b),
            ],
            nodes: nodes,
            finalOutput: output,
            blockers: [.init(
                effect: key,
                definitionPassIndex: nil,
                reason: .unsupportedCondition,
                detail: Graph.BlockerReason.unsupportedCondition.rawValue
            )]
        )
    }

    static func descriptor(_ values: [Int]) -> SceneRenderDescriptor {
        precondition(values.count == 4)
        return .init(
            layers: [.init(
                id: layerID,
                effects: [.init(
                    id: key.descriptorID,
                    passes: values.enumerated().map {
                        .init(
                            passIndex: $0.offset,
                            combos: ["BRANCH": $0.element]
                        )
                    }
                )]
            )],
            materialPasses: values.enumerated().map {
                .init(
                    id: "material-\($0.offset)",
                    materialPath: "materials/\($0.offset).json",
                    combos: ["BRANCH": $0.element]
                )
            }
        )
    }

    static func compile(
        _ graph: Graph,
        values: [Int]
    ) -> Result<Product, SceneGraphAdmissionFailure> {
        SceneGraphAdmissionCompiler.compile(
            graph: graph,
            descriptor: descriptor(values),
            functions: nil
        )
    }

    static func requireProduct(
        _ result: Result<Product, SceneGraphAdmissionFailure>
    ) -> Product {
        guard case .success(let product) = result else {
            fatalError("expected admitted graph")
        }
        return product
    }

    static func failureCode(
        _ result: Result<Product, SceneGraphAdmissionFailure>
    ) -> String {
        switch result {
        case .success: return "success"
        case .failure(let failure): return failure.code.rawValue
        }
    }

    static func targetPlan(_ graph: Graph) -> SceneGraphRenderTargetPlan {
        guard case .success(let plan) = SceneGraphRenderTargetPlan.make(
            graph: graph,
            inputRole: .layerSource,
            inputWidth: 1920,
            inputHeight: 1080
        ) else {
            fatalError("condition-pruned graph must reach target planning")
        }
        return plan
    }

    static func planEvidence(_ product: Product) -> [String: Any] {
        let plan = targetPlan(product.graph)
        return [
            "nodes": product.graph.nodes.map(\.nodeIndex),
            "materialOrdinals": product.graph.nodes.compactMap(\.materialOrdinal),
            "targets": plan.logicalTargets.compactMap { $0.identity.name },
            "targetExtents": plan.logicalTargets.map {
                "\($0.extent.width)x\($0.extent.height)"
            },
            "commands": plan.commands.map {
                [
                    "nodeIndex": $0.nodeIndex,
                    "kind": $0.kind.rawValue,
                    "source": $0.source.name!,
                    "target": $0.target.name!,
                ] as [String: Any]
            },
            "consumerBindings": product.graph.nodes.first {
                $0.nodeIndex == 20
            }!.bindings.compactMap { $0.texture.name },
            "conditionFieldsCleared": product.graph.renderTargets.allSatisfy {
                $0.conditions == nil
            } && product.graph.nodes.allSatisfy {
                $0.conditions == nil && $0.bindings.allSatisfy {
                    $0.conditions == nil
                }
            },
        ]
    }

    static func main() throws {
        let raw = graph()
        let trueProduct = requireProduct(compile(raw, values: [1, 1, 1, 1]))
        let falseProduct = requireProduct(compile(raw, values: [0, 0, 0, 0]))
        let branchBinding = raw.nodes.first { $0.nodeIndex == 20 }!.bindings[0]
        let rawConditionalSiteCount = raw.renderTargets.filter {
            $0.conditions != nil
        }.count + raw.nodes.filter {
            $0.conditions != nil
        }.count + raw.nodes.flatMap(\.bindings).filter {
            $0.conditions != nil
        }.count

        let report: [String: Any] = [
            "raw": [
                "nodes": raw.nodes.count,
                "targets": raw.renderTargets.count,
                "conditionalSites": rawConditionalSiteCount,
                "sameCondition": raw.renderTargets[0].conditions == raw.nodes[0].conditions
                    && raw.nodes[0].conditions == branchBinding.conditions,
                "blockers": raw.blockers.map { $0.reason.rawValue },
            ],
            "true": planEvidence(trueProduct),
            "false": planEvidence(falseProduct),
            "snapshot": [
                "trueValue": trueProduct.conditionSnapshot.value(for: "BRANCH")!,
                "trueProviderCount": trueProduct.conditionSnapshot.bindings[0].providers.count,
                "falseValue": falseProduct.conditionSnapshot.value(for: "BRANCH")!,
                "falseProviderCount": falseProduct.conditionSnapshot.bindings[0].providers.count,
            ],
            "danglingBinding": failureCode(compile(
                graph(consumerBindingIsConditional: false),
                values: [0, 0, 0, 0]
            )),
            "providerConflict": failureCode(compile(
                raw,
                values: [1, 0, 1, 1]
            )),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneGraphConditionalFBOCommandContractTests(unittest.TestCase):
    def test_condition_prunes_one_target_producer_and_binding_before_commands(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="scene-conditional-fbo-command-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            executable = root / "conditional_fbo_command_contract"
            harness.write_text(HARNESS, encoding="utf-8")
            env = os.environ.copy()
            env["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-module-cache")
            env["SWIFT_MODULECACHE_PATH"] = str(root / "swift-module-cache")
            build = subprocess.run(
                [
                    "xcrun",
                    "swiftc",
                    "-parse-as-library",
                    *map(str, SWIFT_SOURCES),
                    str(harness),
                    "-o",
                    str(executable),
                ],
                cwd=REPOSITORY_ROOT,
                env=env,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            completed = subprocess.run(
                [str(executable)],
                cwd=REPOSITORY_ROOT,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )

        report = json.loads(completed.stdout)
        expected_commands = [
            {"nodeIndex": 30, "kind": "copy", "source": "a", "target": "b"},
            {"nodeIndex": 50, "kind": "swap", "source": "a", "target": "b"},
        ]
        self.assertEqual(
            report["raw"],
            {
                "nodes": 6,
                "targets": 3,
                "conditionalSites": 3,
                "sameCondition": True,
                "blockers": ["unsupportedCondition"],
            },
        )
        self.assertEqual(
            report["true"],
            {
                "nodes": [10, 20, 30, 40, 50, 60],
                "materialOrdinals": [0, 1, 2, 3],
                "targets": ["branch", "a", "b"],
                "targetExtents": ["960x540", "960x540", "960x540"],
                "commands": expected_commands,
                "consumerBindings": ["branch"],
                "conditionFieldsCleared": True,
            },
        )
        self.assertEqual(
            report["false"],
            {
                "nodes": [20, 30, 40, 50, 60],
                "materialOrdinals": [1, 2, 3],
                "targets": ["a", "b"],
                "targetExtents": ["960x540", "960x540"],
                "commands": expected_commands,
                "consumerBindings": [],
                "conditionFieldsCleared": True,
            },
        )
        self.assertEqual(
            report["snapshot"],
            {
                "trueValue": 1,
                "trueProviderCount": 4,
                "falseValue": 0,
                "falseProviderCount": 4,
            },
        )
        self.assertEqual(report["danglingBinding"], "prunedResourceReferenced")
        self.assertEqual(report["providerConflict"], "conflictingComboProviders")


if __name__ == "__main__":
    unittest.main()
