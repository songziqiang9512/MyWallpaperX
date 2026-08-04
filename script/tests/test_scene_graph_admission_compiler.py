#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphConditionAdmission.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphAdmissionCompiler.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Clear.swift",
    SOURCE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Extent.swift",
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

struct SceneCursorRippleExecutionPlan {
    let effectKey: SceneAuthoredEffectRenderPlan.EffectKey
}

struct SceneAuthoredEffectExecutionPlan {
    let layerID: Int
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole
    let cursorRipple: SceneCursorRippleExecutionPlan?
}

@main
enum Harness {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Product = SceneGraphAdmissionProduct

    static let layerID = 42
    static let key = Graph.EffectKey(
        layerID: layerID,
        effectIndex: 0,
        descriptorID: "fluid-instance"
    )
    static let source = Graph.TextureIdentity(
        kind: .layerSource,
        layerID: layerID,
        effect: nil,
        name: nil
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

    static func condition(
        _ name: String,
        _ value: Double
    ) -> SceneJSONValue {
        .array([.object([name: .number(value)])])
    }

    static func comparisonCondition() -> SceneJSONValue {
        .array([
            .object([
                "MODE": .number(1),
                "QUALITY": .object(["value": .number(2), "op": .string("ge")]),
            ]),
            .object(["QUALITY": .object(["value": .number(1), "op": .string("gt")])]),
            .object(["QUALITY": .object(["value": .number(2), "op": .string("le")])]),
            .object(["QUALITY": .object(["value": .number(3), "op": .string("lt")])]),
        ])
    }

    static func target(
        _ identity: Graph.TextureIdentity,
        conditions: SceneJSONValue? = nil,
        clear: SceneJSONValue? = .array([.number(0), .number(0), .number(0), .number(0)])
    ) -> Graph.RenderTarget {
        .init(
            texture: identity,
            extent: .init(width: nil, height: nil, fit: nil, scale: nil),
            format: "rgba_backbuffer",
            declaredUnique: true,
            clear: clear,
            uvs: nil,
            conditions: conditions
        )
    }

    static func binding(
        _ texture: Graph.TextureIdentity,
        conditions: SceneJSONValue? = nil
    ) -> Graph.Binding {
        .init(
            slot: 0,
            authoredName: texture.name ?? "previous",
            texture: texture,
            conditions: conditions
        )
    }

    static func material(
        nodeIndex: Int,
        ordinal: Int,
        target: Graph.TextureIdentity,
        bindings: [Graph.Binding] = [],
        compose: SceneJSONValue? = nil,
        conditions: SceneJSONValue? = nil,
        hasInstancePass: Bool = true
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
            materialOrdinal: ordinal,
            instancePassIndex: hasInstancePass ? ordinal : nil,
            kind: .material,
            materialPath: "materials/\(ordinal).json",
            materialPassID: "material-\(ordinal)",
            target: target,
            bindings: bindings,
            commandSource: nil,
            commandTarget: nil,
            compose: compose,
            conditions: conditions
        )
    }

    static func command(
        nodeIndex: Int,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity,
        compose: SceneJSONValue?
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
            materialOrdinal: nil,
            instancePassIndex: nil,
            kind: .copy,
            materialPath: nil,
            materialPassID: nil,
            target: nil,
            bindings: [],
            commandSource: source,
            commandTarget: target,
            compose: compose,
            conditions: nil
        )
    }

    static func blocker(_ reason: Graph.BlockerReason) -> Graph.Blocker {
        .init(effect: key, definitionPassIndex: nil, reason: reason, detail: reason.rawValue)
    }

    static func graph(
        targets: [Graph.RenderTarget],
        nodes: [Graph.Node],
        blockers: [Graph.BlockerReason] = []
    ) -> Graph {
        .init(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/fluid/effect.json",
                input: source,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: blockers.map(blocker)
        )
    }

    static func descriptor(
        materialCombos: [[String: Int]],
        instanceCombos: [[String: Int]]? = nil,
        instancePassIndices: [Int]? = nil
    ) -> SceneRenderDescriptor {
        let instance = instanceCombos ?? Array(
            repeating: [:],
            count: materialCombos.count
        )
        precondition(instance.isEmpty || instance.count == materialCombos.count)
        precondition(instancePassIndices == nil || instancePassIndices!.count == instance.count)
        return .init(
            layers: [.init(
                id: layerID,
                effects: [.init(
                    id: key.descriptorID,
                    passes: instance.enumerated().map {
                        .init(
                            passIndex: instancePassIndices?[$0.offset] ?? $0.offset,
                            combos: $0.element
                        )
                    }
                )]
            )],
            materialPasses: materialCombos.enumerated().map {
                .init(
                    id: "material-\($0.offset)",
                    materialPath: "materials/\($0.offset).json",
                    combos: $0.element
                )
            }
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

    static func compile(
        _ graph: Graph,
        _ descriptor: SceneRenderDescriptor,
        functions: SceneJSONValue? = nil,
        zeroKeys: Set<String>? = nil
    ) -> Result<Product, SceneGraphAdmissionFailure> {
        guard let zeroKeys else {
            return SceneGraphAdmissionCompiler.compile(
                graph: graph,
                descriptor: descriptor,
                functions: functions
            )
        }
        return SceneGraphAdmissionCompiler.compile(
            graph: graph,
            descriptor: descriptor,
            functions: functions,
            schemaEvidence: .init(keysProvenZeroWhenMissing: zeroKeys)
        )
    }

    static func fluidGraph(lighting: Double) -> Graph {
        let normal = framebuffer("normal")
        let velocity = framebuffer("velocity")
        return graph(
            targets: [
                target(normal, conditions: condition("LIGHTING", lighting)),
                target(velocity),
            ],
            nodes: [
                material(
                    nodeIndex: 10,
                    ordinal: 0,
                    target: normal,
                    conditions: condition("LIGHTING", lighting)
                ),
                material(nodeIndex: 11, ordinal: 1, target: velocity),
                material(
                    nodeIndex: 12,
                    ordinal: 2,
                    target: output,
                    bindings: [
                        binding(normal, conditions: condition("LIGHTING", lighting)),
                        binding(velocity),
                    ]
                ),
            ],
            blockers: [.unsupportedCondition]
        )
    }

    static func renderTargetPlan(_ graph: Graph) -> SceneGraphRenderTargetPlan {
        let execution = SceneAuthoredEffectExecutionPlan(
            layerID: layerID,
            materialNodeCount: graph.nodes.filter { $0.kind == .material }.count,
            logicalRenderTargetCount: graph.renderTargets.count,
            inputRole: .layerSource,
            cursorRipple: nil
        )
        guard case .success(let plan) = SceneGraphRenderTargetPlan.make(
            executionPlan: execution,
            graph: graph,
            inputWidth: 1920,
            inputHeight: 1080
        ) else { fatalError("admitted graph must reach RT planning") }
        return plan
    }

    static func fluidEvidence() -> [String: Any] {
        let enabledDescriptor = descriptor(
            materialCombos: [
                ["LIGHTING": 1],
                ["LIGHTING": 1],
                ["LIGHTING": 0],
            ],
            instanceCombos: [
                [:],
                [:],
                ["LIGHTING": 1],
            ]
        )
        let enabled = requireProduct(compile(
            fluidGraph(lighting: 1),
            enabledDescriptor
        ))
        let lighting = enabled.conditionSnapshot.bindings.first {
            $0.name == "LIGHTING"
        }!
        let enabledPlan = renderTargetPlan(enabled.graph)

        let disabledDescriptor = descriptor(materialCombos: [
            ["LIGHTING": 0],
            ["LIGHTING": 0],
            ["LIGHTING": 0],
        ])
        let disabled = requireProduct(compile(
            fluidGraph(lighting: 1),
            disabledDescriptor
        ))
        let disabledPlan = renderTargetPlan(disabled.graph)

        let conflict = failureCode(compile(
            fluidGraph(lighting: 1),
            descriptor(materialCombos: [
                ["LIGHTING": 0],
                ["LIGHTING": 1],
                ["LIGHTING": 0],
            ])
        ))

        return [
            "enabledTargets": enabledPlan.logicalTargets.map { $0.identity.name! },
            "enabledNodes": enabled.graph.nodes.map(\.nodeIndex),
            "enabledOrdinals": enabled.graph.nodes.compactMap(\.materialOrdinal),
            "snapshotValue": lighting.value,
            "snapshotProviderCount": lighting.providers.count,
            "snapshotLastSource": lighting.providers.last!.source.rawValue,
            "disabledTargets": disabledPlan.logicalTargets.map { $0.identity.name! },
            "disabledNodes": disabled.graph.nodes.map(\.nodeIndex),
            "disabledOrdinals": disabled.graph.nodes.compactMap(\.materialOrdinal),
            "disabledBindings": disabled.graph.nodes.last!.bindings.compactMap { $0.texture.name },
            "conflict": conflict,
        ]
    }

    static func conditionEvidence() -> [String: Any] {
        let missingGraph = graph(
            targets: [],
            nodes: [material(
                nodeIndex: 30,
                ordinal: 0,
                target: output,
                conditions: condition("OPTIONAL", 0)
            )],
            blockers: [.unsupportedCondition]
        )
        let missingDescriptor = descriptor(materialCombos: [[:]])
        let unresolved = failureCode(compile(missingGraph, missingDescriptor))
        let provenZero = requireProduct(compile(
            missingGraph,
            missingDescriptor,
            zeroKeys: ["OPTIONAL"]
        ))

        let comparatorGraph = graph(
            targets: [],
            nodes: [material(
                nodeIndex: 31,
                ordinal: 0,
                target: output,
                conditions: comparisonCondition()
            )],
            blockers: [.unsupportedCondition]
        )
        let comparator = failureCode(compile(
            comparatorGraph,
            descriptor(materialCombos: [["MODE": 1, "QUALITY": 2]])
        ))
        let optionalTarget = framebuffer("and-pruned")
        let andGraph = graph(
            targets: [target(
                optionalTarget,
                conditions: .array([
                    .object(["MODE": .number(1)]),
                    .object([
                        "QUALITY": .object([
                            "value": .number(2),
                            "op": .string("gt"),
                        ]),
                    ]),
                ])
            )],
            nodes: [material(nodeIndex: 39, ordinal: 0, target: output)],
            blockers: [.unsupportedCondition]
        )
        let andPruned = requireProduct(compile(
            andGraph,
            descriptor(materialCombos: [["MODE": 1, "QUALITY": 2]])
        ))

        let malformedGraph = graph(
            targets: [],
            nodes: [material(
                nodeIndex: 32,
                ordinal: 0,
                target: output,
                conditions: .bool(true)
            )],
            blockers: [.unsupportedCondition]
        )
        let badOperatorGraph = graph(
            targets: [],
            nodes: [material(
                nodeIndex: 33,
                ordinal: 0,
                target: output,
                conditions: .array([.object([
                    "MODE": .object(["value": .number(1), "op": .string("ne")]),
                ])])
            )],
            blockers: [.unsupportedCondition]
        )
        let hostGraph = graph(
            targets: [],
            nodes: [material(
                nodeIndex: 34,
                ordinal: 0,
                target: output,
                conditions: condition("GLSL", 1)
            )],
            blockers: [.unsupportedCondition]
        )
        let materialOnlyGraph = graph(
            targets: [],
            nodes: [material(
                nodeIndex: 35,
                ordinal: 0,
                target: output,
                conditions: condition("MODE", 1),
                hasInstancePass: false
            )],
            blockers: [.unsupportedCondition]
        )
        let materialOnly = requireProduct(compile(
            materialOnlyGraph,
            descriptor(
                materialCombos: [["MODE": 1]],
                instanceCombos: []
            )
        ))
        let passMismatchGraph = graph(
            targets: [],
            nodes: [material(nodeIndex: 36, ordinal: 0, target: output)]
        )
        let kernel = framebuffer("kernel")
        let perPassVariantGraph = graph(
            targets: [target(kernel)],
            nodes: [
                material(nodeIndex: 37, ordinal: 0, target: kernel),
                material(nodeIndex: 38, ordinal: 1, target: output),
            ]
        )
        let perPassVariant = requireProduct(compile(
            perPassVariantGraph,
            descriptor(materialCombos: [["KERNEL": 0], ["KERNEL": 1]])
        ))

        return [
            "unresolved": unresolved,
            "zeroAdmitted": provenZero.graph.nodes.count,
            "implicitZero": provenZero.conditionSnapshot.implicitZeroKeys,
            "comparators": comparator,
            "andPruned": andPruned.graph.renderTargets.count,
            "malformed": failureCode(compile(
                malformedGraph,
                descriptor(materialCombos: [["MODE": 1]])
            )),
            "badOperator": failureCode(compile(
                badOperatorGraph,
                descriptor(materialCombos: [["MODE": 1]])
            )),
            "reservedHost": failureCode(compile(
                hostGraph,
                descriptor(materialCombos: [["GLSL": 1]])
            )),
            "materialOnly": materialOnly.conditionSnapshot.bindings.first!.providers.first!.source.rawValue,
            "instanceMismatch": failureCode(compile(
                passMismatchGraph,
                descriptor(
                    materialCombos: [[:]],
                    instancePassIndices: [7]
                )
            )),
            "unreferencedConflict": perPassVariant.graph.nodes.count,
            "unreferencedSnapshot": perPassVariant.conditionSnapshot.bindings.count,
        ]
    }

    static func composeEvidence() -> [String: Any] {
        let nodes = [
            material(
                nodeIndex: 40,
                ordinal: 0,
                target: output,
                compose: .bool(true),
                conditions: condition("ACTIVE", 1)
            ),
            material(nodeIndex: 41, ordinal: 1, target: output),
        ]
        let raw = graph(
            targets: [],
            nodes: nodes,
            blockers: [.unsupportedCondition, .unsupportedCompose, .multipleEffectOutputs]
        )
        let admitted = requireProduct(compile(
            raw,
            descriptor(materialCombos: [["ACTIVE": 1], ["ACTIVE": 1]])
        ))
        let repeatCompile = requireProduct(compile(
            raw,
            descriptor(materialCombos: [["ACTIVE": 1], ["ACTIVE": 1]])
        ))
        let pruned = requireProduct(compile(
            raw,
            descriptor(materialCombos: [["ACTIVE": 0], ["ACTIVE": 0]])
        ))

        let malformed = graph(
            targets: [],
            nodes: [
                material(
                    nodeIndex: 42,
                    ordinal: 0,
                    target: output,
                    compose: .string("true")
                ),
            ],
            blockers: [.unsupportedCompose]
        )
        let noTransition = graph(
            targets: [],
            nodes: [
                material(nodeIndex: 43, ordinal: 0, target: output),
                material(nodeIndex: 44, ordinal: 1, target: output),
            ],
            blockers: [.multipleEffectOutputs]
        )
        let singleCompose = graph(
            targets: [],
            nodes: [material(
                nodeIndex: 47,
                ordinal: 0,
                target: output,
                compose: .bool(true)
            )],
            blockers: [.unsupportedCompose]
        )
        let unmarkedMiddle = graph(
            targets: [],
            nodes: [
                material(
                    nodeIndex: 48,
                    ordinal: 0,
                    target: output,
                    compose: .bool(true)
                ),
                material(nodeIndex: 49, ordinal: 1, target: output),
                material(nodeIndex: 50, ordinal: 2, target: output),
            ],
            blockers: [.unsupportedCompose, .multipleEffectOutputs]
        )
        let a = framebuffer("a")
        let b = framebuffer("b")
        let commandCompose = graph(
            targets: [target(a), target(b)],
            nodes: [
                command(nodeIndex: 45, source: a, target: b, compose: .bool(true)),
                material(nodeIndex: 46, ordinal: 0, target: output),
            ],
            blockers: [.unsupportedCompose]
        )

        return [
            "count": admitted.composeTransitions.count,
            "indices": admitted.composeTransitions.nodeIndices,
            "stableDigest": admitted.composeTransitions.digest
                == repeatCompile.composeTransitions.digest,
            "digestLength": admitted.composeTransitions.digest.count,
            "admittedBlockers": admitted.graph.blockers.count,
            "prunedCount": pruned.composeTransitions.count,
            "prunedNodes": pruned.graph.nodes.map(\.nodeIndex),
            "malformed": failureCode(compile(
                malformed,
                descriptor(materialCombos: [[:]])
            )),
            "multipleWithoutCompose": failureCode(compile(
                noTransition,
                descriptor(materialCombos: [[:], [:]])
            )),
            "singleCompose": failureCode(compile(
                singleCompose,
                descriptor(materialCombos: [[:]])
            )),
            "unmarkedMiddle": failureCode(compile(
                unmarkedMiddle,
                descriptor(materialCombos: [[:], [:], [:]])
            )),
            "commandCompose": failureCode(compile(
                commandCompose,
                descriptor(materialCombos: [[:]])
            )),
        ]
    }

    static func functionEvidence() -> [String: Any] {
        let a = framebuffer("a")
        let b = framebuffer("b")
        let raw = graph(
            targets: [target(a), target(b)],
            nodes: [material(nodeIndex: 50, ordinal: 0, target: output)],
            blockers: [.unsupportedFunctions]
        )
        let functions = SceneJSONValue.object([
            "zReset": .object([
                "action": .string("clear"),
                "fbos": .array([.string("b"), .string("a"), .string("b")]),
            ]),
            "aReset": .object([
                "action": .string("clear"),
                "fbos": .array([.string("a")]),
            ]),
        ])
        let admitted = requireProduct(compile(
            raw,
            descriptor(materialCombos: [[:]]),
            functions: functions
        ))
        let reset = admitted.clearFunctions.function(named: "zReset")!
        let unknown = SceneJSONValue.object([
            "reset": .object([
                "action": .string("clear"),
                "fbos": .array([.string("missing")]),
            ]),
        ])
        let malformed = SceneJSONValue.object([
            "reset": .object([
                "action": .string("clear"),
                "fbos": .array([]),
            ]),
        ])

        return [
            "names": admitted.clearFunctions.functions.map(\.name),
            "orderedTargets": reset.targets.map { $0.name! },
            "unknown": failureCode(compile(
                raw,
                descriptor(materialCombos: [[:]]),
                functions: unknown
            )),
            "malformed": failureCode(compile(
                raw,
                descriptor(materialCombos: [[:]]),
                functions: malformed
            )),
            "missingPayload": failureCode(compile(
                raw,
                descriptor(materialCombos: [[:]])
            )),
        ]
    }

    static func main() throws {
        let report: [String: Any] = [
            "fluid": fluidEvidence(),
            "conditions": conditionEvidence(),
            "compose": composeEvidence(),
            "functions": functionEvidence(),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneGraphAdmissionCompilerTests(unittest.TestCase):
    def test_condition_function_and_compose_admission(self) -> None:
        with tempfile.TemporaryDirectory(prefix="scene-graph-admission-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            executable = root / "scene_graph_admission"
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
        self.assertEqual(
            report["fluid"],
            {
                "enabledTargets": ["normal", "velocity"],
                "enabledNodes": [10, 11, 12],
                "enabledOrdinals": [0, 1, 2],
                "snapshotValue": 1,
                "snapshotProviderCount": 3,
                "snapshotLastSource": "instance",
                "disabledTargets": ["velocity"],
                "disabledNodes": [11, 12],
                "disabledOrdinals": [1, 2],
                "disabledBindings": ["velocity"],
                "conflict": "conflictingComboProviders",
            },
        )
        self.assertEqual(
            report["conditions"],
            {
                "unresolved": "unresolvedConditionProvider",
                "zeroAdmitted": 1,
                "implicitZero": ["OPTIONAL"],
                "comparators": "success",
                "andPruned": 0,
                "malformed": "invalidCondition",
                "badOperator": "invalidCondition",
                "reservedHost": "reservedHostCombo",
                "materialOnly": "material",
                "instanceMismatch": "descriptorMismatch",
                "unreferencedConflict": 2,
                "unreferencedSnapshot": 0,
            },
        )
        self.assertEqual(
            report["compose"],
            {
                "count": 1,
                "indices": [40],
                "stableDigest": True,
                "digestLength": 64,
                "admittedBlockers": 0,
                "prunedCount": 0,
                "prunedNodes": [41],
                "malformed": "invalidCompose",
                "multipleWithoutCompose": "graphBlocked",
                "singleCompose": "graphBlocked",
                "unmarkedMiddle": "graphBlocked",
                "commandCompose": "invalidCompose",
            },
        )
        self.assertEqual(
            report["functions"],
            {
                "names": ["aReset", "zReset"],
                "orderedTargets": ["b", "a", "b"],
                "unknown": "unknownFunctionTarget",
                "malformed": "invalidFunctionRegistry",
                "missingPayload": "invalidFunctionRegistry",
            },
        )


if __name__ == "__main__":
    unittest.main()
