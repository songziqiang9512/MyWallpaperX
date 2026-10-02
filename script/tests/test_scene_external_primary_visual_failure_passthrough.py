#!/usr/bin/env python3

"""Production Metal gate for external-primary consumer visual fallback."""

from __future__ import annotations

import json
from pathlib import Path
import runpy
import shutil
import unittest


EXECUTOR_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_executor.py"
)
EXECUTOR_FIXTURE = runpy.run_path(str(EXECUTOR_GATE))
SUPPORT = EXECUTOR_FIXTURE["SUPPORT"]
BASE_HARNESS = EXECUTOR_FIXTURE["HARNESS"]
compile_harness = EXECUTOR_FIXTURE["compile_harness"]


def replace_once(source: str, marker: str, replacement: str) -> str:
    if source.count(marker) != 1:
        raise RuntimeError(f"expected one harness marker: {marker!r}")
    return source.replace(marker, replacement, 1)


BASE_HARNESS = replace_once(
    BASE_HARNESS,
    "private func dormantGraphInputChainGraph() -> Graph {\n",
    r'''private let externalIndependentFramebuffer = Graph.TextureIdentity(
    kind: .framebuffer,
    layerID: layerID,
    effect: chainedFirstEffect,
    name: "external-independent-first"
)

private func externalIndependentFramebufferGraph() -> Graph {
    let nodes = [
        material(
            0,
            ordinal: 0,
            target: externalIndependentFramebuffer,
            read: input,
            owner: chainedFirstEffect
        ),
        material(
            1,
            ordinal: 1,
            target: chainedFirstOutput,
            read: externalIndependentFramebuffer,
            owner: chainedFirstEffect
        ),
        material(
            2,
            ordinal: 0,
            target: chainedSecondOutput,
            read: chainedFirstOutput,
            owner: chainedSecondEffect
        ),
        material(
            3,
            ordinal: 0,
            target: chainedFinalOutput,
            read: chainedSecondOutput,
            owner: chainedThirdEffect
        ),
    ]
    return .init(
        layerID: layerID,
        effects: [
            .init(
                key: chainedFirstEffect,
                definitionPath: "effects/external-independent-first/effect.json",
                input: input,
                output: chainedFirstOutput,
                nodeIndices: [0, 1]
            ),
            .init(
                key: chainedSecondEffect,
                definitionPath: "effects/external-dependent-second/effect.json",
                input: chainedFirstOutput,
                output: chainedSecondOutput,
                nodeIndices: [2]
            ),
            .init(
                key: chainedThirdEffect,
                definitionPath: "effects/external-suffix-third/effect.json",
                input: chainedSecondOutput,
                output: chainedFinalOutput,
                nodeIndices: [3]
            ),
        ],
        renderTargets: [rawTarget(externalIndependentFramebuffer)],
        nodes: nodes,
        finalOutput: chainedFinalOutput,
        blockers: []
    )
}

private func externalIndependentFramebufferLayerGraph(
    _ graph: Graph
) -> AdmittedLayerGraph {
    let stages = graph.effects.enumerated().map { index, effect in
        let stageTargets = graph.renderTargets.filter {
            $0.texture.effect == effect.key
        }
        let stageGraph = Graph(
            layerID: graph.layerID,
            effects: [effect],
            renderTargets: stageTargets,
            nodes: graph.nodes.filter { $0.effect == effect.key },
            finalOutput: effect.output,
            blockers: []
        )
        let inputRole: SceneAuthoredEffectInputRole = index == 0
            ? .layerSource : .priorEffectOutput
        return SceneEffectStageProgram(
            effectKey: effect.key,
            inputRole: inputRole,
            stageGraph: stageGraph,
            executionPlan: executionPlan(
                for: stageGraph,
                inputRole: inputRole
            )
        )
    }
    return .init(
        layerID: graph.layerID,
        renderGraph: graph,
        stagePrograms: stages
    )
}

private func dormantGraphInputChainGraph() -> Graph {
''',
)


HARNESS = replace_once(
    BASE_HARNESS,
    "        let pixelGraph = chainedGraph()\n",
    r'''        let externalFailureGraph = chainedGraph()
        let externalFailureChain = orderedLayerGraph(externalFailureGraph)
        let externalFailureBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: layerID,
            providerLayerID: namedReference.providerLayerID,
            slot: .init(
                effectID: chainedSecondEffect.descriptorID,
                passIndex: 0,
                slotIndex: 1
            ),
            blendMode: 0,
            kind: .resolvedMaterial
        )
        let externalReadyCapabilities = capabilities(
            externalFailureChain,
            catalog: catalog(
                for: externalFailureGraph,
                namedProvidersByNode: [1: namedReference]
            ),
            namedProvider: namedReference,
            dependencyBinding: externalFailureBinding
        )
        let externalLaunchFailureCapabilities = capabilities(
            externalFailureChain,
            catalog: catalog(
                for: externalFailureGraph,
                samplerSchemaInvalidNodes: [1],
                namedProvidersByNode: [1: namedReference]
            ),
            namedProvider: namedReference,
            dependencyBinding: externalFailureBinding
        )
        let externalReadyClaim = externalReadyCapabilities.claim(
            externalFailureChain
        )
        let externalReadyCapability = externalReadyClaim.flatMap {
            externalReadyCapabilities.resolve(
                $0.token,
                for: externalFailureChain
            )
        }
        let externalLaunchFailureClaim = externalLaunchFailureCapabilities
            .claim(externalFailureChain)
        let externalLaunchFailureCapability = externalLaunchFailureClaim.flatMap {
            externalLaunchFailureCapabilities.resolve(
                $0.token,
                for: externalFailureChain
            )
        }
        let externalDependencyInput = providerResource.map {
            SceneResolvedMaterialRuntimeBridge.FrameInputs(
                dependencyEffects: [.init(
                    frameEpoch: 60,
                    texture: providerTexture,
                    namedReference: namedReference,
                    reservedMaterialResource: $0
                )]
            )
        }

        struct ExternalFailureRun {
            var prepared = false
            var encoded = false
            var gpu = false
            var previousCurrent = false
            var suffix = false
            var providerPreserved = false
            var failureCode = "setup"
        }

        let independentFramebufferGraph =
            externalIndependentFramebufferGraph()
        let independentFramebufferChain =
            externalIndependentFramebufferLayerGraph(
                independentFramebufferGraph
            )
        let independentFramebufferBinding = SceneDependencyRenderPlan.Binding(
            consumerLayerID: layerID,
            providerLayerID: namedReference.providerLayerID,
            slot: .init(
                effectID: chainedSecondEffect.descriptorID,
                passIndex: 0,
                slotIndex: 1
            ),
            blendMode: 0,
            kind: .resolvedMaterial
        )
        let independentFramebufferCapabilities = capabilities(
            independentFramebufferChain,
            catalog: catalog(
                for: independentFramebufferGraph,
                // Use an explicitly invalid author sampler declaration;
                // an RT default can become supported and is not a failure oracle.
                samplerSchemaInvalidNodes: [0],
                namedProvidersByNode: [2: namedReference]
            ),
            namedProvider: namedReference,
            dependencyBinding: independentFramebufferBinding
        )
        let independentFramebufferClaim = independentFramebufferCapabilities
            .claim(independentFramebufferChain)
        let independentFramebufferCapability = independentFramebufferClaim
            .flatMap {
                independentFramebufferCapabilities.resolve(
                    $0.token,
                    for: independentFramebufferChain
                )
            }
        let independentFramebufferCapabilityAvailable =
            independentFramebufferCapability != nil
        let independentFramebufferOwnership: Bool = {
            guard let capability = independentFramebufferCapability,
                  case .externalPrimary = capability.dependencyOwnership else {
                return false
            }
            return true
        }()
        let independentFramebufferFirstFailure: Bool = {
            guard let stages = independentFramebufferCapability?.stages,
                  stages.count == 3,
                  case .visualFailurePassthrough = stages[0]
            else { return false }
            return true
        }()
        let independentFramebufferDependencyResolved: Bool = {
            guard let stages = independentFramebufferCapability?.stages,
                  stages.count == 3,
                  case .resolved = stages[1] else { return false }
            return true
        }()
        let independentFramebufferSuffixResolved: Bool = {
            guard let stages = independentFramebufferCapability?.stages,
                  stages.count == 3,
                  case .resolved = stages[2] else { return false }
            return true
        }()
        let independentFramebufferLocalized =
            independentFramebufferCapabilityAvailable
            && independentFramebufferOwnership
            && independentFramebufferFirstFailure
            && independentFramebufferDependencyResolved
            && independentFramebufferSuffixResolved

        func runExternalFailure(
            capabilities: Capabilities,
            claim: Capabilities.ClaimedLayer?,
            capability: Capabilities.LayerCapability?,
            reason: String,
            injectedPreparedKey: String?,
            leaseGeneration: UInt64,
            frameInputs: SceneResolvedMaterialRuntimeBridge.FrameInputs? = nil
        ) -> ExternalFailureRun {
            guard let claim, let capability,
                  let selectedFrameInputs = frameInputs ?? externalDependencyInput,
                  case .externalPrimary = capability.dependencyOwnership,
                  let leases = makeChainedLeases(
                      capability,
                      device: device,
                      generation: leaseGeneration
                  ), let executor = Executor(
                      device: device,
                      capabilities: capabilities
                  ), let command = queue.makeCommandBuffer() else {
                return .init()
            }
            if let injectedPreparedKey {
                executor.materialEncoder.installTestingPreparationFailure(
                    .libraryCompilationRejected(diagnostic: "external-fixture"),
                    preparedKey: injectedPreparedKey
                )
            }
            let result = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(60),
                sourceTexture: makeSource(device, width: 2, height: 2),
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                frameInputs: selectedFrameInputs,
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 1,
                resetGeneration: 1
            )
            guard case let .success(prepared) = result,
                  prepared.stages.count == 3,
                  prepared.stages[1].effectLocalFailureReasonCode == reason,
                  prepared.stages[1].programCacheKeys == [
                      "visual-failure-passthrough:" + reason
                  ] else {
                return .init(failureCode: failureCode(result))
            }
            var readbacks: [Readback] = []
            let encoded = executor.encode(
                prepared,
                commandBuffer: command,
                stageBoundaryObserver: { _, stage, buffer in
                    guard let readback = appendReadback(
                        stage.effectOutputResource.publication.texture,
                        commandBuffer: buffer
                    ) else { return false }
                    readbacks.append(readback)
                    return true
                }
            )
            guard encoded,
                  let providerReadback = appendReadback(
                      providerTexture,
                      commandBuffer: command
                  ) else {
                return .init(prepared: true, encoded: encoded)
            }
            command.commit()
            command.waitUntilCompleted()
            let completed = command.status == .completed && command.error == nil
            return .init(
                prepared: true,
                encoded: encoded,
                gpu: completed,
                previousCurrent: completed && readbacks.count == 3
                    && matches(readbacks[0].firstPixel, [255, 0, 0, 255])
                    && matches(readbacks[1].firstPixel, [255, 0, 0, 255]),
                suffix: completed && readbacks.count == 3
                    && matches(readbacks[2].firstPixel, [0, 255, 0, 255]),
                providerPreserved: completed
                    && matches(providerReadback.firstPixel, [0, 255, 0, 255]),
                failureCode: "success"
            )
        }

        var externalRuntimePreparedKey: String?
        if let claim = externalReadyClaim,
           let capability = externalReadyCapability,
           let externalDependencyInput,
           let leases = makeChainedLeases(
                capability,
                device: device,
                generation: 63
           ), let executor = Executor(
                device: device,
                capabilities: externalReadyCapabilities
           ), let command = queue.makeCommandBuffer() {
            let probe = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(60),
                sourceTexture: makeSource(device, width: 2, height: 2),
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                frameInputs: externalDependencyInput,
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 1,
                resetGeneration: 1
            )
            if case let .success(prepared) = probe,
               prepared.stages.count == 3 {
                externalRuntimePreparedKey = prepared.stages[1]
                    .programCacheKeys.first
            }
        }

        let externalLaunchFailure = runExternalFailure(
            capabilities: externalLaunchFailureCapabilities,
            claim: externalLaunchFailureClaim,
            capability: externalLaunchFailureCapability,
            reason: "material-variant-envelope-sampler-schema",
            injectedPreparedKey: nil,
            leaseGeneration: 64
        )
        let externalRuntimeFailure = runExternalFailure(
            capabilities: externalReadyCapabilities,
            claim: externalReadyClaim,
            capability: externalReadyCapability,
            reason: "material-pass-preparation-library-compilation",
            injectedPreparedKey: externalRuntimePreparedKey,
            leaseGeneration: 65
        )
        let externalProviderUnavailable = runExternalFailure(
            capabilities: externalReadyCapabilities,
            claim: externalReadyClaim,
            capability: externalReadyCapability,
            reason: "external-primary-provider-source-unavailable",
            injectedPreparedKey: nil,
            leaseGeneration: 67,
            frameInputs: .init(
                dependencyUnavailability: .providerSourceUnavailable
            )
        )
        // A missing optional source must not turn a graph with persistent
        // history or authored clears into a successful passthrough. Establish
        // executable ready controls first, then reuse their committed state.
        func protectedGraphRejectsUnavailable(_ selectedGraph: Graph) -> String {
            let chain = admittedGraph(selectedGraph)
            let binding = SceneDependencyRenderPlan.Binding(
                consumerLayerID: layerID,
                providerLayerID: namedReference.providerLayerID,
                slot: .init(effectID: effect.descriptorID, passIndex: 0, slotIndex: 1),
                blendMode: 0,
                kind: .resolvedMaterial
            )
            let selectedCapabilities = capabilities(
                chain,
                catalog: catalog(for: selectedGraph, namedProvidersByNode: [0: namedReference]),
                namedProvider: namedReference,
                dependencyBinding: binding
            )
            guard let claim = selectedCapabilities.claim(chain),
                  let capability = selectedCapabilities.resolve(claim.token, for: chain),
                  let executor = Executor(device: device, capabilities: selectedCapabilities),
                  let readyInputs = externalDependencyInput,
                  let readyCommand = queue.makeCommandBuffer() else { return "setup-rejected:" + selectedCapabilities.reportLines.joined(separator: " | ") }
            let leases = [makeLease(requireR4Plan(selectedGraph), device: device, generation: 71)]
            let readyResult = executor.prepare(
                token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
                frame: frame(60), sourceTexture: makeSource(device, width: 2, height: 2),
                sourceUniforms: .neutral(), sourcePipeline: sourcePipeline,
                frameInputs: readyInputs, commandBuffer: readyCommand,
                previousStates: [:], previousGraphResources: [:],
                effectGeneration: 1, resetGeneration: 1
            )
            guard case let .success(ready) = readyResult,
                  ready.stages.count == 1,
                  ready.stages[0].effectLocalFailureReasonCode == nil,
                  executor.encode(ready, commandBuffer: readyCommand),
                  let beforeReadback = appendReadback(ready.finalTexture, commandBuffer: readyCommand)
            else { return "ready-" + failureCode(readyResult) }
            readyCommand.commit()
            readyCommand.waitUntilCompleted()
            guard readyCommand.status == .completed, readyCommand.error == nil,
                  let unavailableCommand = queue.makeCommandBuffer() else { return "ready-gpu-failed" }
            let committed = ready.stages[0]
            let unavailable = executor.prepare(
                token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
                frame: frame(61), sourceTexture: makeSource(device, width: 2, height: 2),
                sourceUniforms: .neutral(), sourcePipeline: sourcePipeline,
                frameInputs: .init(dependencyUnavailability: .providerSourceUnavailable),
                commandBuffer: unavailableCommand,
                previousStates: [effect: committed.transition.nextState],
                previousGraphResources: [effect: committed.persistentResources],
                effectGeneration: 1, resetGeneration: 1
            )
            guard case .failure = unavailable else { return "unsafe-passthrough-accepted" }
            // Even submitting this rejected preparation may not alter the
            // previously committed output. No encode call receives a success.
            guard let afterReadback = appendReadback(ready.finalTexture, commandBuffer: unavailableCommand)
            else { return "rejected-readback-setup" }
            unavailableCommand.commit()
            unavailableCommand.waitUntilCompleted()
            guard unavailableCommand.status == .completed, unavailableCommand.error == nil,
                  beforeReadback.firstPixel == afterReadback.firstPixel,
                  beforeReadback.lastPixel == afterReadback.lastPixel,
                  let recoveryCommand = queue.makeCommandBuffer(),
                  let recoveryResource = SceneFrameTextureResource.reservedNamedLayerTarget(
                      reference: namedReference, frameEpoch: 62, texture: providerTexture
                  ) else { return "rejected-mutated-output" }
            let recovery = executor.prepare(
                token: claim.token, leases: leases, historyRehydrateCopiesByEffect: [:],
                frame: frame(62), sourceTexture: makeSource(device, width: 2, height: 2),
                sourceUniforms: .neutral(), sourcePipeline: sourcePipeline,
                frameInputs: .init(dependencyEffects: [.init(
                    frameEpoch: 62, texture: providerTexture, namedReference: namedReference,
                    reservedMaterialResource: recoveryResource
                )]), commandBuffer: recoveryCommand,
                previousStates: [effect: committed.transition.nextState],
                previousGraphResources: [effect: committed.persistentResources],
                effectGeneration: 1, resetGeneration: 1
            )
            guard case let .success(recovered) = recovery,
                  recovered.stages[0].effectLocalFailureReasonCode == nil,
                  executor.encode(recovered, commandBuffer: recoveryCommand)
            else { return "recovery-" + failureCode(recovery) }
            recoveryCommand.commit()
            recoveryCommand.waitUntilCompleted()
            guard recoveryCommand.status == .completed, recoveryCommand.error == nil
            else { return "recovery-gpu-failed" }
            return "ready-rejected-preserved-recovered"
        }
        let unavailableHistoryResult = protectedGraphRejectsUnavailable(historyGraph(fixedSize: false))
        let unavailableClearResult = protectedGraphRejectsUnavailable(graph(
            targets: [rawTarget(first, clear: .string("1 0 0 0"))],
            nodes: [
                material(0, ordinal: 0, target: first, read: input),
                material(1, ordinal: 1, target: output, read: first),
            ]
        ))
        let externalLaunchStaleResource =
            SceneFrameTextureResource.reservedNamedLayerTarget(
                reference: namedReference,
                frameEpoch: 59,
                texture: providerTexture
            )
        let externalLaunchFailureWithStaleProvider =
            rejectedCrossLayerPreparation(
                device: device,
                queue: queue,
                sourcePipeline: sourcePipeline,
                admittedGraph: externalFailureChain,
                capabilities: externalLaunchFailureCapabilities,
                dependency: .init(
                    frameEpoch: 59,
                    texture: providerTexture,
                    namedReference: namedReference,
                    reservedMaterialResource: externalLaunchStaleResource
                )
            )

        var externalRecovery = false
        var externalRecoveryMiddlePixel: [UInt8] = []
        if let claim = externalReadyClaim,
           let capability = externalReadyCapability,
           let externalDependencyInput,
           let leases = makeChainedLeases(
                capability,
                device: device,
                generation: 66
           ), let executor = Executor(
                device: device,
                capabilities: externalReadyCapabilities
           ), let command = queue.makeCommandBuffer() {
            let result = executor.prepare(
                token: claim.token,
                leases: leases,
                historyRehydrateCopiesByEffect: [:],
                frame: frame(60),
                sourceTexture: makeSource(device, width: 2, height: 2),
                sourceUniforms: .neutral(),
                sourcePipeline: sourcePipeline,
                frameInputs: externalDependencyInput,
                commandBuffer: command,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 1,
                resetGeneration: 1
            )
            if case let .success(prepared) = result,
               prepared.stages.count == 3,
               prepared.stages[1].effectLocalFailureReasonCode == nil {
                var middle: Readback?
                if executor.encode(
                    prepared,
                    commandBuffer: command,
                    stageBoundaryObserver: { index, stage, buffer in
                        if index == 1 {
                            middle = appendReadback(
                                stage.effectOutputResource.publication.texture,
                                commandBuffer: buffer
                            )
                        }
                        return true
                    }
                ) {
                    command.commit()
                    command.waitUntilCompleted()
                    externalRecoveryMiddlePixel = middle?.firstPixel ?? []
                    externalRecovery = command.status == .completed
                        && command.error == nil
                        && middle.map {
                            matches($0.firstPixel, [128, 128, 0, 255])
                        } == true
                }
            }
        }

        let pixelGraph = chainedGraph()
''',
)
HARNESS = replace_once(
    HARNESS,
    '            "crossLayerExactOwnershipClaimed": {\n',
    '''            "externalLaunchFailureLocalizesAndContinues":
                externalLaunchFailure.prepared
                    && externalLaunchFailure.encoded
                    && externalLaunchFailure.gpu
                    && externalLaunchFailure.previousCurrent
                    && externalLaunchFailure.suffix
                    && externalLaunchFailure.providerPreserved,
            "independentFramebufferFailureDoesNotRevokeDependencyStage":
                independentFramebufferLocalized,
            "independentFramebufferCapabilityAvailable":
                independentFramebufferCapabilityAvailable,
            "independentFramebufferOwnership":
                independentFramebufferOwnership,
            "independentFramebufferFirstFailure":
                independentFramebufferFirstFailure,
            "independentFramebufferDependencyResolved":
                independentFramebufferDependencyResolved,
            "independentFramebufferSuffixResolved":
                independentFramebufferSuffixResolved,
            "externalRuntimeFailureLocalizesAndContinues":
                externalRuntimeFailure.prepared
                    && externalRuntimeFailure.encoded
                    && externalRuntimeFailure.gpu
                    && externalRuntimeFailure.previousCurrent
                    && externalRuntimeFailure.suffix
                    && externalRuntimeFailure.providerPreserved,
            "externalProviderSourceUnavailableLocalizesAndContinues":
                externalProviderUnavailable.prepared
                    && externalProviderUnavailable.encoded
                    && externalProviderUnavailable.gpu
                    && externalProviderUnavailable.previousCurrent
                    && externalProviderUnavailable.suffix
                    && externalProviderUnavailable.providerPreserved,
            "externalLaunchFailureCannotMaskStaleProvider":
                externalLaunchFailureWithStaleProvider.failureCode
                    == Executor.Failure.graphPublicationRejected.rawValue
                    && externalLaunchFailureWithStaleProvider
                        .previousCurrentPreserved
                    && externalLaunchFailureWithStaleProvider
                        .safeSuffixCompleted,
            "externalConsumerRecovers": externalRecovery,
            "crossLayerExactOwnershipClaimed": {
''',
)
HARNESS = replace_once(
    HARNESS,
    '                "crossLayer": crossLayerFailure,\n',
    '''                "unavailableHistoryResult": unavailableHistoryResult,
                "unavailableClearResult": unavailableClearResult,
                "externalLaunchFailure":
                    externalLaunchFailure.failureCode,
                "externalRuntimeFailure":
                    externalRuntimeFailure.failureCode,
                "externalProviderUnavailable":
                    externalProviderUnavailable.failureCode,
                "externalLaunchFailureWithStaleProvider":
                    externalLaunchFailureWithStaleProvider.failureCode,
                "crossLayer": crossLayerFailure,
''',
)
HARNESS = replace_once(
    HARNESS,
    '            "crossLayerPixel": crossLayerPixel,\n',
    '''            "externalRecoveryMiddlePixel":
                externalRecoveryMiddlePixel,
            "crossLayerPixel": crossLayerPixel,
''',
)


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ExternalPrimaryVisualFailurePassthroughTests(unittest.TestCase):
    def test_unavailable_source_preserves_history_and_clear_boundary(self) -> None:
        compilation, completed = compile_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        for key in ("unavailableHistoryResult", "unavailableClearResult"):
            self.assertEqual(payload["failureCodes"][key], "ready-rejected-preserved-recovered", (key, payload["failureCodes"][key]))
        for key in ("externalProviderSourceUnavailableLocalizesAndContinues", "externalLaunchFailureCannotMaskStaleProvider", "externalConsumerRecovers"):
            self.assertTrue(payload["results"][key], (key, payload))

    def test_consumer_failure_preserves_provider_and_continues_suffix(self) -> None:
        compilation, completed = compile_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)

        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        for key in (
            "externalLaunchFailureLocalizesAndContinues",
            "independentFramebufferFailureDoesNotRevokeDependencyStage",
            "externalRuntimeFailureLocalizesAndContinues",
            "externalProviderSourceUnavailableLocalizesAndContinues",
            "externalLaunchFailureCannotMaskStaleProvider",
            "externalConsumerRecovers",
            "crossLayerMissingProviderRejectedAtomically",
            "crossLayerWrongProviderRejectedAtomically",
            "crossLayerSecondaryRejectedAtomically",
            "crossLayerStaleEpochRejectedAtomically",
        ):
            self.assertTrue(payload["results"][key], (key, payload))
        self.assertEqual(payload["failureCodes"]["externalLaunchFailure"], "success")
        self.assertEqual(payload["failureCodes"]["externalRuntimeFailure"], "success")
        self.assertEqual(
            payload["failureCodes"]["externalProviderUnavailable"],
            "success",
        )
        self.assertEqual(
            payload["failureCodes"]["externalLaunchFailureWithStaleProvider"],
            "graph-publication-rejected",
        )


if __name__ == "__main__":
    unittest.main()
