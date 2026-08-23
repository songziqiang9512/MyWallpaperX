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
            SceneResolvedMaterialRuntimeBridge.DedicatedFrameInputs(
                dependencyEffect: .init(
                    frameEpoch: 60,
                    namedReference: namedReference,
                    reservedMaterialResource: $0
                )
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

        func runExternalFailure(
            capabilities: Capabilities,
            claim: Capabilities.ClaimedLayer?,
            capability: Capabilities.LayerCapability?,
            reason: String,
            injectedPreparedKey: String?,
            leaseGeneration: UInt64
        ) -> ExternalFailureRun {
            guard let claim, let capability, let externalDependencyInput,
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
                dedicatedInputs: externalDependencyInput,
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
                dedicatedInputs: externalDependencyInput,
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
                dedicatedInputs: externalDependencyInput,
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
            "externalRuntimeFailureLocalizesAndContinues":
                externalRuntimeFailure.prepared
                    && externalRuntimeFailure.encoded
                    && externalRuntimeFailure.gpu
                    && externalRuntimeFailure.previousCurrent
                    && externalRuntimeFailure.suffix
                    && externalRuntimeFailure.providerPreserved,
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
    '''                "externalLaunchFailure":
                    externalLaunchFailure.failureCode,
                "externalRuntimeFailure":
                    externalRuntimeFailure.failureCode,
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
            "externalRuntimeFailureLocalizesAndContinues",
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
            payload["failureCodes"]["externalLaunchFailureWithStaleProvider"],
            "graph-publication-rejected",
        )


if __name__ == "__main__":
    unittest.main()
