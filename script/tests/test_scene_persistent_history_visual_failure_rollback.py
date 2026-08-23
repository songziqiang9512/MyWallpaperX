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
STATE_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/GraphTargets/SceneGraphExecutionState.swift"
)
EXECUTOR_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor.swift"
)
VISUAL_FAILURE_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialGraphExecutor+VisualFailurePassthrough.swift"
)
CAPABILITY_SOURCE = (
    SCENE_ROOT
    / "RenderGraph/EffectExecution/SceneResolvedMaterialExecutionCapability+ProgramFirstStages.swift"
)
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/AuthoredGraph/SceneAuthoredEffectRenderPlan.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Clear.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneGraphRenderTargetPlan+Extent.swift",
    SCENE_ROOT / "RenderGraph/GraphTargets/SceneLayerFullFramePairPlan.swift",
    STATE_SOURCE,
    SCENE_ROOT
    / "RenderGraph/GraphTargets/SceneGraphExecutionState+Validation.swift",
    SCENE_ROOT
    / "RenderGraph/GraphTargets/SceneGraphExecutionState+Identity.swift",
]


HARNESS = r'''
import Foundation

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
    typealias Plan = SceneGraphRenderTargetPlan
    typealias Pair = SceneLayerFullFramePairPlan
    typealias State = SceneGraphExecutionState

    static let layerID = 51
    static let key = Graph.EffectKey(
        layerID: layerID, effectIndex: 0, descriptorID: "history-fixture"
    )
    static let input = identity(.layerSource)
    static let output = identity(.effectOutput, effect: key)
    static let q1 = identity(.framebuffer, effect: key, name: "q1")
    static let q2 = identity(.framebuffer, effect: key, name: "q2")
    static let scratch = identity(.framebuffer, effect: key, name: "scratch")

    static func identity(
        _ kind: Graph.TextureKind,
        effect: Graph.EffectKey? = nil,
        name: String? = nil
    ) -> Graph.TextureIdentity {
        .init(kind: kind, layerID: layerID, effect: effect, name: name)
    }

    static func target(
        _ identity: Graph.TextureIdentity,
        unique: Bool
    ) -> Graph.RenderTarget {
        .init(
            texture: identity,
            extent: .init(width: 64, height: 64, fit: nil, scale: nil),
            format: "rgba_backbuffer",
            declaredUnique: unique,
            clear: nil,
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
        reads: [Graph.TextureIdentity]
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
            materialOrdinal: ordinal,
            instancePassIndex: ordinal,
            kind: .material,
            materialPath: "materials/history.json",
            materialPassID: "history#\(ordinal)",
            target: target,
            bindings: reads.enumerated().map {
                binding($0.element, slot: $0.offset)
            },
            commandSource: nil,
            commandTarget: nil,
            compose: nil,
            conditions: nil
        )
    }

    static func swap(
        _ nodeIndex: Int,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity
    ) -> Graph.Node {
        .init(
            nodeIndex: nodeIndex,
            effect: key,
            definitionPassIndex: nodeIndex,
            materialOrdinal: nil,
            instancePassIndex: nil,
            kind: .swap,
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
        nodes: [Graph.Node]
    ) -> Graph {
        .init(
            layerID: layerID,
            effects: [.init(
                key: key,
                definitionPath: "effects/history/effect.json",
                input: input,
                output: output,
                nodeIndices: nodes.map(\.nodeIndex)
            )],
            renderTargets: targets,
            nodes: nodes,
            finalOutput: output,
            blockers: []
        )
    }

    static func plan(_ graph: Graph) -> Plan {
        guard case .success(let value) = Plan.make(
            graph: graph,
            inputRole: .layerSource,
            inputWidth: 64,
            inputHeight: 64
        ) else { fatalError("target plan rejected") }
        return value
    }

    static func pair(_ graph: Graph) -> Pair.EffectStep {
        guard case .success(let value) = Pair.make(
            conditionPrunedGraphs: [graph]
        ), let effect = value.effects.first else {
            fatalError("pair plan rejected")
        }
        return effect
    }

    static func allocation(
        _ plan: Plan,
        generation: UInt64,
        prefix: String
    ) -> State.Allocation {
        .init(
            generation: generation,
            resources: Dictionary(uniqueKeysWithValues:
                plan.logicalTargets.map { target in
                    (target.identity, State.Resource(
                        token: .init(
                            rawValue: "\(prefix)-\(target.identity.name ?? "fbo")"
                        ),
                        descriptor: .init(
                            extent: target.extent,
                            format: target.format,
                            addressMode: target.addressMode,
                            isUnique: target.isUnique,
                            initialClear: target.initialClear
                        )
                    ))
                }
            )
        )
    }

    static func reduce(
        graph: Graph,
        plan: Plan,
        allocation: State.Allocation,
        previous: State = .empty,
        historyRehydration: [State.PhysicalToken: State.PhysicalToken] = [:]
    ) -> State.Transition {
        let result = State.reduce(
            graph: graph,
            targetPlan: plan,
            pairStep: pair(graph),
            allocation: allocation,
            effectGeneration: 1,
            resetGeneration: 1,
            previous: previous,
            historyRehydration: historyRehydration
        )
        switch result {
        case .success(let value): return value
        case .failure(let failure):
            fatalError("state reduction rejected: \(failure.rawValue)")
        }
    }

    static func generations(
        _ mapping: [Graph.TextureIdentity: State.VersionedResource]
    ) -> [String: UInt64] {
        Dictionary(uniqueKeysWithValues: mapping.map {
            ($0.key.name ?? "missing", $0.value.contentGeneration)
        })
    }

    static func tokens(
        _ mapping: [Graph.TextureIdentity: State.VersionedResource]
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: mapping.map {
            ($0.key.name ?? "missing", $0.value.token.rawValue)
        })
    }

    static func initializedCount(_ intents: [State.Intent]) -> Int {
        intents.filter {
            if case .initialize = $0 { return true }
            return false
        }.count
    }

    static func main() throws {
        let historyGraph = graph(
            targets: [
                target(q1, unique: true),
                target(q2, unique: true),
                target(scratch, unique: false),
            ],
            nodes: [
                material(0, ordinal: 0, target: q2, reads: [q1, input]),
                swap(1, source: q1, target: q2),
                material(2, ordinal: 1, target: scratch, reads: [q1]),
                material(3, ordinal: 2, target: output, reads: [scratch]),
            ]
        )
        let historyPlan = plan(historyGraph)
        let oldAllocation = allocation(
            historyPlan, generation: 1, prefix: "old"
        )

        let firstCandidate = reduce(
            graph: historyGraph,
            plan: historyPlan,
            allocation: oldAllocation
        )
        guard let firstRollback = State.discardingUncommittedVisualFailure(
            firstCandidate,
            previous: .empty
        ) else { fatalError("first-frame rollback rejected") }
        let retry = reduce(
            graph: historyGraph,
            plan: historyPlan,
            allocation: oldAllocation,
            previous: firstRollback.nextState
        )

        let firstSuccess = firstCandidate.nextState
        let stableCandidate = reduce(
            graph: historyGraph,
            plan: historyPlan,
            allocation: oldAllocation,
            previous: firstSuccess
        )
        guard let stableRollback = State.discardingUncommittedVisualFailure(
            stableCandidate,
            previous: firstSuccess
        ) else { fatalError("stable rollback rejected") }

        let freshAllocation = allocation(
            historyPlan, generation: 2, prefix: "fresh"
        )
        let rehydration = Dictionary(uniqueKeysWithValues: [q1, q2].map {
            identity in
            (
                oldAllocation.resources[identity]!.token,
                freshAllocation.resources[identity]!.token
            )
        })
        let freshCandidate = reduce(
            graph: historyGraph,
            plan: historyPlan,
            allocation: freshAllocation,
            previous: firstSuccess,
            historyRehydration: rehydration
        )
        guard let freshRollback = State.discardingUncommittedVisualFailure(
            freshCandidate,
            previous: firstSuccess
        ) else { fatalError("fresh-allocation rollback rejected") }

        let missing = freshCandidate.transaction.mappingBefore.keys.first!
        var malformedMapping = freshCandidate.transaction.mappingBefore
        malformedMapping.removeValue(forKey: missing)
        let malformed = State.Transition(
            nextState: freshCandidate.nextState,
            transaction: .init(
                intents: freshCandidate.transaction.intents,
                mappingBefore: malformedMapping,
                mappingAfter: freshCandidate.transaction.mappingAfter,
                allocationGeneration:
                    freshCandidate.transaction.allocationGeneration,
                effectGeneration: freshCandidate.transaction.effectGeneration,
                resetGeneration: freshCandidate.transaction.resetGeneration
            )
        )

        let local = identity(.framebuffer, effect: key, name: "local")
        let localGraph = graph(
            targets: [target(local, unique: false)],
            nodes: [
                material(0, ordinal: 0, target: local, reads: [input]),
                material(1, ordinal: 1, target: output, reads: [local]),
            ]
        )
        let localPlan = plan(localGraph)
        let localCandidate = reduce(
            graph: localGraph,
            plan: localPlan,
            allocation: allocation(localPlan, generation: 7, prefix: "local")
        )
        guard let localRollback = State.discardingUncommittedVisualFailure(
            localCandidate,
            previous: .empty
        ) else { fatalError("frame-local rollback rejected") }

        let payload: [String: Any] = [
            "firstRollbackIntents": firstRollback.transaction.intents.count,
            "firstRollbackStateIsEmpty":
                firstRollback.nextState.logicalMapping.isEmpty,
            "retryInitializationCount": initializedCount(
                retry.transaction.intents
            ),
            "stableRollbackMatchesPrevious":
                stableRollback.nextState == firstSuccess,
            "stableRollbackMappingIsAtomic":
                stableRollback.transaction.mappingBefore
                    == stableRollback.transaction.mappingAfter,
            "stablePreviousLastGeneration": firstSuccess.lastContentGeneration,
            "stableCandidateLastGeneration":
                stableCandidate.nextState.lastContentGeneration,
            "stableRollbackLastGeneration":
                stableRollback.nextState.lastContentGeneration,
            "freshRollbackTokens": tokens(
                freshRollback.nextState.logicalMapping
            ),
            "freshMappingBeforeTokens": tokens(
                freshCandidate.transaction.mappingBefore
            ),
            "freshRollbackGenerations": generations(
                freshRollback.nextState.logicalMapping
            ),
            "freshMappingBeforeGenerations": generations(
                freshCandidate.transaction.mappingBefore
            ),
            "freshRollbackLastGeneration":
                freshRollback.nextState.lastContentGeneration,
            "malformedRollbackRejected":
                State.discardingUncommittedVisualFailure(
                    malformed,
                    previous: firstSuccess
                ) == nil,
            "localRollbackHasNoPersistentState":
                localRollback.nextState.logicalMapping.isEmpty
                    && localRollback.transaction.mappingAfter.isEmpty,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ScenePersistentHistoryVisualFailureRollbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory()
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        executable = root / "history-rollback"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "swiftc",
                "-D",
                "SCENE_GRAPH_TESTING",
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(executable),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(compilation.stderr)
        completed = subprocess.run(
            [str(executable)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_first_frame_failure_retries_history_seed(self) -> None:
        self.assertEqual(self.result["firstRollbackIntents"], 0)
        self.assertTrue(self.result["firstRollbackStateIsEmpty"])
        self.assertEqual(self.result["retryInitializationCount"], 1)

    def test_stable_failure_keeps_only_previous_committed_state(self) -> None:
        self.assertTrue(self.result["stableRollbackMatchesPrevious"])
        self.assertTrue(self.result["stableRollbackMappingIsAtomic"])
        self.assertGreater(
            self.result["stableCandidateLastGeneration"],
            self.result["stablePreviousLastGeneration"],
        )
        self.assertEqual(
            self.result["stableRollbackLastGeneration"],
            self.result["stablePreviousLastGeneration"],
        )

    def test_fresh_allocation_keeps_only_rehydrated_history(self) -> None:
        self.assertEqual(
            self.result["freshRollbackTokens"],
            self.result["freshMappingBeforeTokens"],
        )
        self.assertEqual(
            self.result["freshRollbackGenerations"],
            self.result["freshMappingBeforeGenerations"],
        )
        self.assertEqual(
            self.result["freshRollbackLastGeneration"],
            self.result["stablePreviousLastGeneration"],
        )

    def test_integrity_mismatch_is_hard_and_frame_local_behavior_is_retained(
        self,
    ) -> None:
        self.assertTrue(self.result["malformedRollbackRejected"])
        self.assertTrue(self.result["localRollbackHasNoPersistentState"])

    def test_product_route_uses_previous_state_and_separates_dependencies(
        self,
    ) -> None:
        executor = EXECUTOR_SOURCE.read_text(encoding="utf-8")
        visual = VISUAL_FAILURE_SOURCE.read_text(encoding="utf-8")
        capability = CAPABILITY_SOURCE.read_text(encoding="utf-8")
        self.assertIn("previous: previous", executor)
        self.assertIn(
            "preEncodeVisualFailureGraphTopologyIsSupported",
            visual,
        )
        self.assertIn(
            "transition.nextState.historyClosureIdentities.isEmpty",
            visual,
        )
        self.assertIn("preEncodeVisualFailureGraphMayPassthrough", capability)


if __name__ == "__main__":
    unittest.main()
