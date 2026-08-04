#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STATE_SOURCES = [
    SCENE_ROOT / "RenderGraph/SceneGraphExecutionState.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphExecutionState+Validation.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphExecutionState+Identity.swift",
]
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Clear.swift",
    SCENE_ROOT / "RenderGraph/SceneGraphRenderTargetPlan+Extent.swift",
    SCENE_ROOT / "RenderGraph/SceneLayerFullFramePairPlan.swift",
    *STATE_SOURCES,
]


HARNESS = r'''
import Foundation

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
    typealias Plan = SceneGraphRenderTargetPlan
    typealias Pair = SceneLayerFullFramePairPlan
    typealias State = SceneGraphExecutionState

    static let layerID = 10
    static let key = Graph.EffectKey(
        layerID: layerID, effectIndex: 0, descriptorID: "effect-0"
    )
    static let input = identity(.layerSource)
    static let output = identity(.effectOutput, effect: key)
    static let fixedExtent = Graph.TargetExtent(
        width: 100, height: 50, fit: nil, scale: nil
    )
    static let dynamicExtent = Graph.TargetExtent(
        width: nil, height: nil, fit: nil, scale: nil
    )

    static func identity(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func rawTarget(
        _ identity: Graph.TextureIdentity,
        unique: Bool = false,
        extent: Graph.TargetExtent = fixedExtent,
        clear: SceneJSONValue? = nil
    ) -> Graph.RenderTarget {
        .init(
            texture: identity,
            extent: extent,
            format: "rgba_backbuffer",
            declaredUnique: unique,
            clear: clear,
            uvs: nil,
            conditions: nil
        )
    }

    static func binding(
        _ identity: Graph.TextureIdentity,
        slot: Int
    ) -> Graph.Binding {
        .init(
            slot: slot,
            authoredName: identity.name ?? "previous",
            texture: identity,
            conditions: nil
        )
    }

    static func material(
        _ nodeIndex: Int,
        ordinal: Int,
        target: Graph.TextureIdentity,
        reads: [Graph.TextureIdentity],
        compose: SceneJSONValue? = nil
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
            materialOrdinal: ordinal,
            instancePassIndex: ordinal,
            kind: .material,
            materialPath: "materials/test.json",
            materialPassID: "test#\(ordinal)",
            target: target,
            bindings: reads.enumerated().map { binding($0.element, slot: $0.offset) },
            commandSource: nil,
            commandTarget: nil,
            compose: compose,
            conditions: nil
        )
    }

    static func command(
        _ nodeIndex: Int,
        kind: Graph.NodeKind,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
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
        targets: [Graph.RenderTarget],
        nodes: [Graph.Node],
        blockers: [Graph.Blocker] = []
    ) -> Graph {
        let effect = Graph.Effect(
            key: key,
            definitionPath: "effects/test/effect.json",
            input: input,
            output: output,
            nodeIndices: nodes.map(\.nodeIndex)
        )
        return .init(
            layerID: layerID,
            effects: [effect],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: blockers
        )
    }

    static func requirePlan(
        _ graph: Graph,
        width: Int = 100,
        height: Int = 50
    ) -> Plan {
        guard case .success(let plan) = Plan.make(
            graph: graph,
            inputRole: .layerSource,
            inputWidth: width,
            inputHeight: height
        ) else { fatalError("expected target plan") }
        return plan
    }

    static func requirePair(_ graph: Graph) -> Pair.EffectStep {
        guard case .success(let plan) = Pair.make(conditionPrunedGraphs: [graph]),
              let step = plan.effects.first else {
            fatalError("expected pair step")
        }
        return step
    }

    static func allocation(
        plan: Plan,
        generation: UInt64,
        prefix: String,
        tokenOverrides: [Graph.TextureIdentity: String] = [:]
    ) -> State.Allocation {
        let resources = Dictionary(uniqueKeysWithValues: plan.logicalTargets.map {
            logical in
            let token = tokenOverrides[logical.identity]
                ?? "\(prefix)-\(logical.identity.name ?? "fbo")"
            return (logical.identity, State.Resource(
                token: .init(rawValue: token),
                descriptor: .init(
                    extent: logical.extent,
                    format: logical.format,
                    isUnique: logical.isUnique,
                    initialClear: logical.initialClear
                )
            ))
        })
        return .init(generation: generation, resources: resources)
    }

    static func require(
        _ result: Result<State.Transition, State.Failure>,
        line: UInt = #line
    ) -> State.Transition {
        guard case .success(let value) = result else {
            let failure: String
            if case .failure(let reason) = result {
                failure = reason.rawValue
            } else {
                failure = "unknown"
            }
            fatalError("expected transition at \(line): \(failure)")
        }
        return value
    }

    static func failure(
        graph: Graph,
        plan: Plan,
        pair: Pair.EffectStep,
        allocation: State.Allocation,
        effectGeneration: UInt64 = 1,
        resetGeneration: UInt64 = 1,
        previous: State = .empty,
        historyRehydration: [State.PhysicalToken: State.PhysicalToken] = [:]
    ) -> String {
        switch State.reduce(
            graph: graph,
            targetPlan: plan,
            pairStep: pair,
            allocation: allocation,
            effectGeneration: effectGeneration,
            resetGeneration: resetGeneration,
            previous: previous,
            historyRehydration: historyRehydration
        ) {
        case .success: return "success"
        case .failure(let reason): return reason.rawValue
        }
    }

    static func kinds(_ intents: [State.Intent]) -> [String] {
        intents.map {
            switch $0 {
            case .initialize: return "initialize"
            case .material: return "material"
            case .copy: return "copy"
            case .swap: return "swap"
            }
        }
    }

    static func token(
        _ mapping: [Graph.TextureIdentity: State.VersionedResource],
        _ identity: Graph.TextureIdentity
    ) -> String {
        mapping[identity]?.token.rawValue ?? "missing"
    }

    static func generation(
        _ mapping: [Graph.TextureIdentity: State.VersionedResource],
        _ identity: Graph.TextureIdentity
    ) -> UInt64 {
        mapping[identity]?.contentGeneration ?? 0
    }

    static func initializationTokens(_ intents: [State.Intent]) -> [String] {
        intents.compactMap {
            guard case .initialize(_, let resource, _) = $0 else { return nil }
            return resource.token.rawValue
        }
    }

    static func materialShapes(_ intents: [State.Intent]) -> [[String]] {
        intents.compactMap {
            guard case .material(_, _, let bindings, let target) = $0 else {
                return nil
            }
            return [
                bindings.map { $0.identity.name ?? "pair" }.joined(separator: ","),
                target?.identity.name ?? "pair",
            ]
        }
    }

    static func materialOrdinals(_ intents: [State.Intent]) -> [Int] {
        intents.compactMap {
            guard case .material(_, let ordinal, _, _) = $0 else { return nil }
            return ordinal
        }
    }

    static func main() throws {
        let q1 = identity(.framebuffer, effect: key, name: "q1")
        let q2 = identity(.framebuffer, effect: key, name: "q2")

        // Full-frame-only effects must produce no persistent resource mapping.
        let ordinaryGraph = graph(
            targets: [],
            nodes: [material(0, ordinal: 0, target: output, reads: [input])]
        )
        let ordinaryPlan = requirePlan(ordinaryGraph)
        let ordinaryPair = requirePair(ordinaryGraph)
        let ordinaryAllocation = allocation(
            plan: ordinaryPlan, generation: 1, prefix: "ordinary"
        )
        let ordinary = require(State.reduce(
            graph: ordinaryGraph,
            targetPlan: ordinaryPlan,
            pairStep: ordinaryPair,
            allocation: ordinaryAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let ordinaryReprepared = require(State.reduce(
            graph: ordinaryGraph,
            targetPlan: ordinaryPlan,
            pairStep: ordinaryPair,
            allocation: allocation(
                plan: ordinaryPlan, generation: 2, prefix: "ordinary-reprepared"
            ),
            effectGeneration: 1,
            resetGeneration: 1,
            previous: ordinary.nextState
        ))
        // Admission removes condition-false passes without renumbering their
        // authored material ordinals, which still select instance overlays.
        let prunedOrdinalGraph = graph(
            targets: [],
            nodes: [material(7, ordinal: 2, target: output, reads: [input])]
        )
        let prunedOrdinalPlan = requirePlan(prunedOrdinalGraph)
        let prunedOrdinal = require(State.reduce(
            graph: prunedOrdinalGraph,
            targetPlan: prunedOrdinalPlan,
            pairStep: requirePair(prunedOrdinalGraph),
            allocation: allocation(
                plan: prunedOrdinalPlan, generation: 1, prefix: "pruned-ordinal"
            ),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let endpointDescriptor = State.ResourceDescriptor(
            extent: ordinaryPlan.inputExtent,
            format: .rgbaBackbuffer,
            isUnique: false,
            initialClear: nil
        )
        let endpointAllocation = State.Allocation(
            generation: 1,
            resources: [
                input: .init(
                    token: .init(rawValue: "forbidden-input"),
                    descriptor: endpointDescriptor
                ),
                output: .init(
                    token: .init(rawValue: "forbidden-output"),
                    descriptor: endpointDescriptor
                ),
            ]
        )

        // Compose is routing-only state, including multiple rotations.
        let singleComposeGraph = graph(
            targets: [],
            nodes: [
                material(
                    0, ordinal: 0, target: output, reads: [input],
                    compose: .bool(true)
                ),
                material(1, ordinal: 1, target: output, reads: [input]),
            ]
        )
        let singleComposePlan = requirePlan(singleComposeGraph)
        let singleComposePair = requirePair(singleComposeGraph)
        let singleCompose = require(State.reduce(
            graph: singleComposeGraph,
            targetPlan: singleComposePlan,
            pairStep: singleComposePair,
            allocation: allocation(
                plan: singleComposePlan, generation: 1, prefix: "single-compose"
            ),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let multipleComposeGraph = graph(
            targets: [],
            nodes: [
                material(
                    0, ordinal: 0, target: output, reads: [input],
                    compose: .bool(true)
                ),
                material(
                    1, ordinal: 1, target: output, reads: [input],
                    compose: .bool(true)
                ),
                material(2, ordinal: 2, target: output, reads: [input]),
            ]
        )
        let multipleComposePlan = requirePlan(multipleComposeGraph)
        let multipleComposePair = requirePair(multipleComposeGraph)
        let multipleCompose = require(State.reduce(
            graph: multipleComposeGraph,
            targetPlan: multipleComposePlan,
            pairStep: multipleComposePair,
            allocation: allocation(
                plan: multipleComposePlan, generation: 1, prefix: "multi-compose"
            ),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let originalPairNode = singleComposePair.nodes[0]
        let mismatchedPairNode = Pair.NodeStep(
            nodeIndex: originalPairNode.nodeIndex,
            definitionPassIndex: originalPairNode.definitionPassIndex,
            kind: originalPairNode.kind,
            currentMemberBeforeNode: originalPairNode.currentMemberBeforeNode,
            fullFrameReadMember: originalPairNode.fullFrameReadMember,
            fullFrameWriteMember: originalPairNode.fullFrameWriteMember,
            rotatesAfterNode: false,
            currentMemberAfterNode: originalPairNode.currentMemberBeforeNode
        )
        let mismatchedPair = Pair.EffectStep(
            effect: singleComposePair.effect,
            inputIdentity: singleComposePair.inputIdentity,
            outputIdentity: singleComposePair.outputIdentity,
            inputMember: singleComposePair.inputMember,
            outputMember: singleComposePair.outputMember,
            composeTransitionCount: singleComposePair.composeTransitionCount,
            fullFrameOutputWriteCount: singleComposePair.fullFrameOutputWriteCount,
            nodes: [mismatchedPairNode] + singleComposePair.nodes.dropFirst()
        )

        // Persistent authored FBO copy/swap mapping survives across frames.
        let swapGraph = graph(
            targets: [rawTarget(q1), rawTarget(q2)],
            nodes: [
                material(0, ordinal: 0, target: q1, reads: [input]),
                material(1, ordinal: 1, target: q2, reads: [input]),
                command(2, kind: .swap, source: q1, target: q2),
                material(3, ordinal: 2, target: output, reads: [q1]),
            ]
        )
        let swapPlan = requirePlan(swapGraph)
        let swapPair = requirePair(swapGraph)
        let swapAllocation = allocation(
            plan: swapPlan, generation: 1, prefix: "swap"
        )
        let swap1 = require(State.reduce(
            graph: swapGraph,
            targetPlan: swapPlan,
            pairStep: swapPair,
            allocation: swapAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let unchangedFBOsWithFreshGenerationFailure = failure(
            graph: swapGraph,
            plan: swapPlan,
            pair: swapPair,
            allocation: .init(
                generation: 2,
                resources: swapAllocation.resources
            ),
            previous: swap1.nextState
        )
        let swap2 = require(State.reduce(
            graph: swapGraph,
            targetPlan: swapPlan,
            pairStep: swapPair,
            allocation: swapAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: swap1.nextState
        ))
        let resetSwap = require(State.reduce(
            graph: swapGraph,
            targetPlan: swapPlan,
            pairStep: swapPair,
            allocation: swapAllocation,
            effectGeneration: 1,
            resetGeneration: 2,
            previous: swap1.nextState
        ))
        let reparsedSwap = require(State.reduce(
            graph: swapGraph,
            targetPlan: swapPlan,
            pairStep: swapPair,
            allocation: swapAllocation,
            effectGeneration: 2,
            resetGeneration: 1,
            previous: swap1.nextState
        ))

        let copyGraph = graph(
            targets: [rawTarget(q1), rawTarget(q2)],
            nodes: [
                material(0, ordinal: 0, target: q1, reads: [input]),
                command(1, kind: .copy, source: q1, target: q2),
                material(2, ordinal: 1, target: output, reads: [q2]),
            ]
        )
        let copyPlan = requirePlan(copyGraph)
        let copied = require(State.reduce(
            graph: copyGraph,
            targetPlan: copyPlan,
            pairStep: requirePair(copyGraph),
            allocation: allocation(plan: copyPlan, generation: 1, prefix: "copy"),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let zeroClear = SceneJSONValue.array(Array(
            repeating: SceneJSONValue.number(0), count: 4
        ))
        let clearGraph = graph(
            targets: [rawTarget(q1, clear: zeroClear)],
            nodes: [
                material(0, ordinal: 0, target: q1, reads: [input]),
                material(1, ordinal: 1, target: output, reads: [q1]),
            ]
        )
        let clearPlan = requirePlan(clearGraph)
        let clearPair = requirePair(clearGraph)
        let clearAllocation = allocation(
            plan: clearPlan, generation: 1, prefix: "clear"
        )
        let clear1 = require(State.reduce(
            graph: clearGraph,
            targetPlan: clearPlan,
            pairStep: clearPair,
            allocation: clearAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let clear2 = require(State.reduce(
            graph: clearGraph,
            targetPlan: clearPlan,
            pairStep: clearPair,
            allocation: clearAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: clear1.nextState
        ))
        let clearReset = require(State.reduce(
            graph: clearGraph,
            targetPlan: clearPlan,
            pairStep: clearPair,
            allocation: clearAllocation,
            effectGeneration: 1,
            resetGeneration: 2,
            previous: clear1.nextState
        ))
        let clearFresh = require(State.reduce(
            graph: clearGraph,
            targetPlan: clearPlan,
            pairStep: clearPair,
            allocation: allocation(
                plan: clearPlan, generation: 2, prefix: "clear-fresh"
            ),
            effectGeneration: 1,
            resetGeneration: 1,
            previous: clear1.nextState
        ))

        // A descriptor resize gets a disjoint allocation and keeps the swap
        // permutation, while its content versions restart from zero.
        let resizeGraph = graph(
            targets: [
                rawTarget(q1, extent: dynamicExtent),
                rawTarget(q2, extent: dynamicExtent),
            ],
            nodes: swapGraph.nodes
        )
        let resizeSmallPlan = requirePlan(resizeGraph)
        let resizeLargePlan = requirePlan(resizeGraph, width: 200, height: 100)
        let resizePair = requirePair(resizeGraph)
        let resizeSmall = require(State.reduce(
            graph: resizeGraph,
            targetPlan: resizeSmallPlan,
            pairStep: resizePair,
            allocation: allocation(
                plan: resizeSmallPlan, generation: 1, prefix: "resize-small"
            ),
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let resizeLarge = require(State.reduce(
            graph: resizeGraph,
            targetPlan: resizeLargePlan,
            pairStep: resizePair,
            allocation: allocation(
                plan: resizeLargePlan, generation: 2, prefix: "resize-large"
            ),
            effectGeneration: 1,
            resetGeneration: 1,
            previous: resizeSmall.nextState
        ))

        // q1 is the direct history identity; q1/q2 form its swap closure.
        let historyGraph = graph(
            targets: [
                rawTarget(q1, unique: true),
                rawTarget(q2, unique: true),
            ],
            nodes: [
                material(0, ordinal: 0, target: q2, reads: [q1, input]),
                command(1, kind: .swap, source: q1, target: q2),
                material(2, ordinal: 1, target: output, reads: [q1]),
            ]
        )
        let historyPlan = requirePlan(historyGraph)
        let historyPair = requirePair(historyGraph)
        let historyAllocation = allocation(
            plan: historyPlan, generation: 1, prefix: "history-old"
        )
        let history1 = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: historyAllocation,
            effectGeneration: 1,
            resetGeneration: 1
        ))
        let oldSelected = history1.nextState.logicalMapping[q1]!
        let freshHistoryAllocation = allocation(
            plan: historyPlan, generation: 2, prefix: "history-new"
        )
        let expectedNewToken = freshHistoryAllocation.resources[q2]!.token
        let rehydration = [oldSelected.token: expectedNewToken]
        let rehydrated = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: freshHistoryAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: history1.nextState,
            historyRehydration: rehydration
        ))
        let rehydratedAgain = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: freshHistoryAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: history1.nextState,
            historyRehydration: rehydration
        ))
        let missingRehydration = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: freshHistoryAllocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: history1.nextState
        ))
        let wrongTarget = freshHistoryAllocation.resources[q1]!.token
        let invalidRehydration = failure(
            graph: historyGraph,
            plan: historyPlan,
            pair: historyPair,
            allocation: freshHistoryAllocation,
            previous: history1.nextState,
            historyRehydration: [oldSelected.token: wrongTarget]
        )
        let outsideRehydration = failure(
            graph: historyGraph,
            plan: historyPlan,
            pair: historyPair,
            allocation: freshHistoryAllocation,
            previous: history1.nextState,
            historyRehydration: [
                .init(rawValue: "not-in-history-closure"): expectedNewToken
            ]
        )
        let reusedTokenAllocation = allocation(
            plan: historyPlan,
            generation: 3,
            prefix: "history-reuse",
            tokenOverrides: [q1: historyAllocation.resources[q1]!.token.rawValue]
        )
        let reusedTokenFailure = failure(
            graph: historyGraph,
            plan: historyPlan,
            pair: historyPair,
            allocation: reusedTokenAllocation,
            previous: history1.nextState
        )
        let historyReset = require(State.reduce(
            graph: historyGraph,
            targetPlan: historyPlan,
            pairStep: historyPair,
            allocation: historyAllocation,
            effectGeneration: 1,
            resetGeneration: 2,
            previous: history1.nextState
        ))

        // State validation still rejects FBO hazards and malformed allocation.
        let aliasAllocation = allocation(
            plan: swapPlan,
            generation: 1,
            prefix: "alias",
            tokenOverrides: [q1: "same", q2: "same"]
        )
        let hazardGraph = graph(
            targets: [rawTarget(q1, unique: true)],
            nodes: [
                material(0, ordinal: 0, target: q1, reads: [q1, input]),
                material(1, ordinal: 1, target: output, reads: [q1]),
            ]
        )
        let hazardPlan = requirePlan(hazardGraph)
        let hazardFailure = failure(
            graph: hazardGraph,
            plan: hazardPlan,
            pair: requirePair(hazardGraph),
            allocation: allocation(
                plan: hazardPlan, generation: 1, prefix: "hazard"
            )
        )
        let noSeedTargets = historyPlan.logicalTargets.map { target in
            Plan.LogicalTarget(
                identity: target.identity,
                extent: target.extent,
                format: target.format,
                isUnique: target.isUnique,
                lifetime: .init(
                    firstWriteNodeIndex: target.lifetime.firstWriteNodeIndex,
                    lastWriteNodeIndex: target.lifetime.lastWriteNodeIndex,
                    firstReadNodeIndex: target.lifetime.firstReadNodeIndex,
                    lastReadNodeIndex: target.lifetime.lastReadNodeIndex,
                    requiresHistorySeed: false
                ),
                initialClear: nil
            )
        }
        let noSeedPlan = Plan.testingPlan(
            layerID: layerID,
            input: input,
            output: output,
            inputRole: .layerSource,
            inputExtent: historyPlan.inputExtent,
            logicalTargets: noSeedTargets,
            commands: historyPlan.commands
        )
        let readBeforeWriteFailure = failure(
            graph: historyGraph,
            plan: noSeedPlan,
            pair: historyPair,
            allocation: allocation(
                plan: noSeedPlan, generation: 1, prefix: "no-seed"
            )
        )

        let excessiveNodesGraph = graph(
            targets: [],
            nodes: Array(repeating: ordinaryGraph.nodes[0], count: 513)
        )
        let excessiveNodeFailure = failure(
            graph: excessiveNodesGraph,
            plan: ordinaryPlan,
            pair: ordinaryPair,
            allocation: ordinaryAllocation
        )
        let excessiveTargets = (0 ..< 513).map { index in
            Plan.LogicalTarget(
                identity: identity(
                    .framebuffer, effect: key, name: "overflow-\(index)"
                ),
                extent: ordinaryPlan.inputExtent,
                format: .rgbaBackbuffer,
                isUnique: false,
                lifetime: .init(
                    firstWriteNodeIndex: 0,
                    lastWriteNodeIndex: 0,
                    firstReadNodeIndex: nil,
                    lastReadNodeIndex: nil
                ),
                initialClear: nil
            )
        }
        let excessivePlan = Plan.testingPlan(
            layerID: layerID,
            input: input,
            output: output,
            inputRole: .layerSource,
            inputExtent: ordinaryPlan.inputExtent,
            logicalTargets: excessiveTargets
        )
        let excessiveLogicalFailure = failure(
            graph: ordinaryGraph,
            plan: excessivePlan,
            pair: ordinaryPair,
            allocation: ordinaryAllocation
        )

        let result: [String: Any] = [
            "ordinaryKinds": kinds(ordinary.transaction.intents),
            "ordinaryMappings": [
                ordinary.transaction.mappingBefore.count,
                ordinary.transaction.mappingAfter.count,
            ],
            "ordinaryRepreparedGeneration": ordinaryReprepared.nextState
                .allocationGeneration ?? 0,
            "ordinaryRepreparedMappings": [
                ordinaryReprepared.transaction.mappingBefore.count,
                ordinaryReprepared.transaction.mappingAfter.count,
            ],
            "ordinaryRepreparedKinds": kinds(
                ordinaryReprepared.transaction.intents
            ),
            "ordinaryMaterialShapes": materialShapes(ordinary.transaction.intents),
            "prunedMaterialOrdinals": materialOrdinals(
                prunedOrdinal.transaction.intents
            ),
            "endpointAllocationFailure": failure(
                graph: ordinaryGraph,
                plan: ordinaryPlan,
                pair: ordinaryPair,
                allocation: endpointAllocation
            ),
            "singleComposeKinds": kinds(singleCompose.transaction.intents),
            "singleComposeMappingCount": singleCompose.nextState.logicalMapping.count,
            "multipleComposeKinds": kinds(multipleCompose.transaction.intents),
            "multipleComposeMappingCount": multipleCompose.nextState.logicalMapping.count,
            "pairMismatchFailure": failure(
                graph: singleComposeGraph,
                plan: singleComposePlan,
                pair: mismatchedPair,
                allocation: allocation(
                    plan: singleComposePlan, generation: 1, prefix: "bad-pair"
                )
            ),
            "swapKinds": kinds(swap1.transaction.intents),
            "swapAfter1": [
                token(swap1.transaction.mappingAfter, q1),
                token(swap1.transaction.mappingAfter, q2),
            ],
            "swapBefore2": [
                token(swap2.transaction.mappingBefore, q1),
                token(swap2.transaction.mappingBefore, q2),
            ],
            "swapAfter2": [
                token(swap2.transaction.mappingAfter, q1),
                token(swap2.transaction.mappingAfter, q2),
            ],
            "swapTransactionGenerations": [
                generation(swap1.transaction.mappingAfter, q1),
                generation(swap1.transaction.mappingAfter, q2),
            ],
            "swapCommittedGenerations": [
                generation(swap1.nextState.logicalMapping, q1),
                generation(swap1.nextState.logicalMapping, q2),
            ],
            "swapCommittedInitialized": swap1.nextState
                .initializedPhysicalTokens.count,
            "unchangedFBOsWithFreshGenerationFailure":
                unchangedFBOsWithFreshGenerationFailure,
            "copyKinds": kinds(copied.transaction.intents),
            "clearInitializations": [
                initializationTokens(clear1.transaction.intents),
                initializationTokens(clear2.transaction.intents),
                initializationTokens(clearReset.transaction.intents),
                initializationTokens(clearFresh.transaction.intents),
            ],
            "clearCommittedGeneration": generation(
                clear1.nextState.logicalMapping, q1
            ),
            "clearCommittedInitialized": clear1.nextState
                .initializedPhysicalTokens.count,
            "resetMappingBefore": [
                token(resetSwap.transaction.mappingBefore, q1),
                token(resetSwap.transaction.mappingBefore, q2),
            ],
            "reparseMappingBefore": [
                token(reparsedSwap.transaction.mappingBefore, q1),
                token(reparsedSwap.transaction.mappingBefore, q2),
            ],
            "resizeExtents": resizeLargePlan.logicalTargets.map {
                "\($0.extent.width)x\($0.extent.height)"
            },
            "resizeMappingBefore": [
                token(resizeLarge.transaction.mappingBefore, q1),
                token(resizeLarge.transaction.mappingBefore, q2),
            ],
            "historyDirectCount": history1.nextState.historyLogicalIdentities.count,
            "historyClosureCount": history1.nextState.historyClosureIdentities.count,
            "historyCommittedGenerations": [
                generation(history1.nextState.logicalMapping, q1),
                generation(history1.nextState.logicalMapping, q2),
            ],
            "historyFirstInitializations": initializationTokens(
                history1.transaction.intents
            ),
            "rehydratedInitializations": initializationTokens(
                rehydrated.transaction.intents
            ),
            "rehydratedGenerationBefore": generation(
                rehydrated.transaction.mappingBefore, q1
            ),
            "rehydratedExpectedGeneration": oldSelected.contentGeneration,
            "missingRehydrationInitializations": initializationTokens(
                missingRehydration.transaction.intents
            ),
            "invalidRehydration": invalidRehydration,
            "outsideRehydration": outsideRehydration,
            "reusedTokenFailure": reusedTokenFailure,
            "pureCandidateEqual": rehydrated == rehydratedAgain,
            "previousStateUnchanged": history1.nextState.logicalMapping[q1]
                == oldSelected,
            "historyResetInitializations": initializationTokens(
                historyReset.transaction.intents
            ),
            "aliasFailure": failure(
                graph: swapGraph,
                plan: swapPlan,
                pair: swapPair,
                allocation: aliasAllocation
            ),
            "hazardFailure": hazardFailure,
            "readBeforeWriteFailure": readBeforeWriteFailure,
            "excessiveNodeFailure": excessiveNodeFailure,
            "excessiveLogicalFailure": excessiveLogicalFailure,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneGraphExecutionStateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-graph-state-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scene-graph-state"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-D",
                "SCENE_GRAPH_TESTING",
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], capture_output=True, text=True
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_pair_endpoints_never_enter_persistent_state(self) -> None:
        self.assertEqual(self.result["ordinaryKinds"], ["material"])
        self.assertEqual(self.result["ordinaryMappings"], [0, 0])
        self.assertEqual(self.result["ordinaryMaterialShapes"], [["", "pair"]])
        self.assertEqual(self.result["prunedMaterialOrdinals"], [2])
        self.assertEqual(self.result["endpointAllocationFailure"], "missingIdentity")

    def test_pair_only_allocation_generation_can_reprepare(self) -> None:
        self.assertEqual(self.result["ordinaryRepreparedGeneration"], 2)
        self.assertEqual(self.result["ordinaryRepreparedMappings"], [0, 0])
        self.assertEqual(self.result["ordinaryRepreparedKinds"], ["material"])

    def test_single_and_multiple_compose_are_pair_validated_only(self) -> None:
        self.assertEqual(self.result["singleComposeKinds"], ["material", "material"])
        self.assertEqual(self.result["singleComposeMappingCount"], 0)
        self.assertEqual(
            self.result["multipleComposeKinds"],
            ["material", "material", "material"],
        )
        self.assertEqual(self.result["multipleComposeMappingCount"], 0)
        self.assertEqual(self.result["pairMismatchFailure"], "pairStepMismatch")

    def test_copy_and_swap_keep_only_fbo_state(self) -> None:
        self.assertEqual(
            self.result["swapKinds"],
            ["material", "material", "swap", "material"],
        )
        self.assertEqual(self.result["swapAfter1"], ["swap-q2", "swap-q1"])
        self.assertEqual(self.result["swapBefore2"], self.result["swapAfter1"])
        self.assertEqual(self.result["swapAfter2"], ["swap-q1", "swap-q2"])
        self.assertEqual(self.result["copyKinds"], ["material", "copy", "material"])
        self.assertEqual(
            self.result["unchangedFBOsWithFreshGenerationFailure"],
            "freshAllocationTokenReuse",
        )

    def test_tail_keeps_only_non_history_initialization_state(self) -> None:
        self.assertTrue(all(
            generation > 0
            for generation in self.result["swapTransactionGenerations"]
        ))
        self.assertEqual(self.result["swapCommittedGenerations"], [0, 0])
        self.assertEqual(self.result["swapCommittedInitialized"], 0)
        self.assertEqual(
            self.result["clearInitializations"],
            [["clear-q1"], [], ["clear-q1"], ["clear-fresh-q1"]],
        )
        self.assertEqual(self.result["clearCommittedGeneration"], 0)
        self.assertEqual(self.result["clearCommittedInitialized"], 1)

    def test_reset_reparse_and_resize_keep_the_fbo_contract(self) -> None:
        expected = ["swap-q1", "swap-q2"]
        self.assertEqual(self.result["resetMappingBefore"], expected)
        self.assertEqual(self.result["reparseMappingBefore"], expected)
        self.assertEqual(self.result["resizeExtents"], ["200x100", "200x100"])
        self.assertEqual(
            self.result["resizeMappingBefore"],
            ["resize-large-q2", "resize-large-q1"],
        )

    def test_history_rehydration_is_explicit_and_closure_bounded(self) -> None:
        self.assertEqual(self.result["historyDirectCount"], 1)
        self.assertEqual(self.result["historyClosureCount"], 2)
        self.assertTrue(all(
            generation > 0
            for generation in self.result["historyCommittedGenerations"]
        ))
        self.assertEqual(self.result["historyFirstInitializations"], ["history-old-q1"])
        self.assertEqual(self.result["rehydratedInitializations"], [])
        self.assertEqual(
            self.result["rehydratedGenerationBefore"],
            self.result["rehydratedExpectedGeneration"],
        )
        self.assertEqual(
            self.result["missingRehydrationInitializations"],
            ["history-new-q2"],
        )
        self.assertEqual(
            self.result["invalidRehydration"], "historyRehydrationMismatch"
        )
        self.assertEqual(
            self.result["outsideRehydration"], "historyRehydrationMismatch"
        )
        self.assertEqual(
            self.result["reusedTokenFailure"], "freshAllocationTokenReuse"
        )

    def test_transition_is_a_pre_gpu_pure_candidate(self) -> None:
        self.assertTrue(self.result["pureCandidateEqual"])
        self.assertTrue(self.result["previousStateUnchanged"])
        self.assertEqual(self.result["historyResetInitializations"], ["history-old-q1"])

    def test_fbo_hazards_capacity_and_aliases_remain_fail_closed(self) -> None:
        self.assertEqual(self.result["aliasFailure"], "physicalAlias")
        self.assertEqual(self.result["hazardFailure"], "readWriteHazard")
        self.assertEqual(self.result["readBeforeWriteFailure"], "readBeforeWrite")
        self.assertEqual(
            self.result["excessiveNodeFailure"],
            "executionEvidenceCapacityExceeded",
        )
        self.assertEqual(
            self.result["excessiveLogicalFailure"],
            "executionEvidenceCapacityExceeded",
        )

    def test_removed_stage_endpoint_apis_do_not_return(self) -> None:
        source = "\n".join(path.read_text(encoding="utf-8") for path in STATE_SOURCES)
        self.assertNotIn("case captureInput", source)
        self.assertNotIn("FinalOutputPublication", source)
        self.assertNotIn("preservedHistoryTokens", source)


if __name__ == "__main__":
    unittest.main()
