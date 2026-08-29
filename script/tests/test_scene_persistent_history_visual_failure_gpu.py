#!/usr/bin/env python3

"""Production GraphExecutor GPU gate for persistent-history visual rollback."""

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
compile_harness = EXECUTOR_FIXTURE["compile_harness"]

FIXTURE_GATE = Path(__file__).with_name(
    "scene_preserved_channel_history_fixture.py"
)
FIXTURE = runpy.run_path(str(FIXTURE_GATE))
HARNESS_SUPPORT = FIXTURE["HARNESS_SUPPORT"]


HARNESS = HARNESS_SUPPORT + r'''


@main
private enum Harness {
    static let failureReason = "material-variant-envelope-uniform-schema"

    static func prepareFrame(
        executor: Executor,
        token: Capabilities.Token,
        lease: SceneGraphRenderTargetLease,
        copies: [ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy] = [],
        index: UInt64,
        source: MTLTexture,
        pipeline: SceneImageLayerPipeline,
        command: MTLCommandBuffer,
        previous: Executor.PreparedStage? = nil
    ) -> Executor.PreparedGraph {
        let result = prepare(
            executor: executor,
            token: token,
            lease: lease,
            copies: copies,
            index: index,
            source: source,
            pipeline: pipeline,
            command: command,
            previous: previous
        )
        guard case let .success(value) = result else {
            fatalError("prepare failed: \(failure(result))")
        }
        return value
    }

    static func encodeAndRead(
        _ value: Executor.PreparedGraph,
        executor: Executor,
        command: MTLCommandBuffer
    ) -> Readback {
        guard executor.encode(value, commandBuffer: command),
              let read = readback(value.finalTexture, command: command) else {
            fatalError("encode/readback failed")
        }
        command.commit()
        command.waitUntilCompleted()
        expect(
            command.status == .completed && command.error == nil,
            "GPU completion"
        )
        return read
    }

    static func sameHistoryPublication(
        _ lhs: Executor.PreparedStage,
        _ rhs: Executor.PreparedStage
    ) -> Bool {
        guard let left = lhs.persistentResources[history],
              let right = rhs.persistentResources[history] else { return false }
        return left.resourceGeneration == right.resourceGeneration
            && left.publication.texture === right.publication.texture
            && left.publication.candidate.generation
                == right.publication.candidate.generation
    }

    static func main() throws {
        setenv(
            "MWX_SCENE_GENERIC_SHADER_PROFILE_ROUTES",
            "ordinary-shader=disable-generic",
            1
        )
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let raw = graph(
            format: "rg1616f",
            clear: .string("0.25 0.5 0.75 1")
        )
        let chain = admitted(raw)
        let validCapabilities = capabilities(raw, pair: true)
        let failedCapabilities = capabilities(
            raw,
            pair: true,
            invalidUniformNode: 0
        )
        guard let validClaim = validCapabilities.claim(chain),
              let failedClaim = failedCapabilities.claim(chain),
              let failedCapability = failedCapabilities.resolve(
                  failedClaim.token,
                  for: chain
              ),
              failedCapability.stages.first?.visualFailureReasonCode
                == failureReason,
              let validExecutor = Executor(
                  device: device,
                  capabilities: validCapabilities
              ),
              let failedExecutor = Executor(
                  device: device,
                  capabilities: failedCapabilities
              ) else { fatalError("capability setup") }

        let source = sourceTexture(device)
        let pipeline = sourcePipeline(device)
        let targetPlan = plan(raw)
        let oldLease = lease(targetPlan, device: device, generation: 70)

        let initialFailedCommand = queue.makeCommandBuffer()!
        let initialFailed = prepareFrame(
            executor: failedExecutor,
            token: failedClaim.token,
            lease: oldLease,
            index: 69,
            source: source,
            pipeline: pipeline,
            command: initialFailedCommand
        )
        guard let initialFailedStage = initialFailed.stages.first else {
            fatalError("initial failed stage")
        }
        expect(
            initialFailedStage.effectLocalFailureReasonCode == failureReason
                && intents(initialFailed).isEmpty,
            "initial typed failure"
        )
        expect(
            initialFailedStage.transition.nextState.logicalMapping.isEmpty,
            "initial history target state discarded"
        )
        let initialFailedRead = encodeAndRead(
            initialFailed,
            executor: failedExecutor,
            command: initialFailedCommand
        )
        expect(
            matches(initialFailedRead.pixel, [0, 0, 255, 255]),
            "initial passthrough"
        )

        let firstCommand = queue.makeCommandBuffer()!
        let first = prepareFrame(
            executor: validExecutor,
            token: validClaim.token,
            lease: oldLease,
            index: 70,
            source: source,
            pipeline: pipeline,
            command: firstCommand,
            previous: initialFailedStage
        )
        guard let firstStage = first.stages.first else {
            fatalError("first stage")
        }
        let firstRead = encodeAndRead(
            first,
            executor: validExecutor,
            command: firstCommand
        )
        expect(
            intents(first) == [
                "initialize", "material", "material", "material",
            ],
            "first recovery seeds history"
        )
        expect(matches(firstRead.pixel, [0, 128, 64, 255]), "first output")

        let failedCommand = queue.makeCommandBuffer()!
        let failed = prepareFrame(
            executor: failedExecutor,
            token: failedClaim.token,
            lease: oldLease,
            index: 71,
            source: source,
            pipeline: pipeline,
            command: failedCommand,
            previous: firstStage
        )
        guard let failedStage = failed.stages.first else {
            fatalError("failed stage")
        }
        expect(
            failedStage.effectLocalFailureReasonCode == failureReason,
            "typed failure"
        )
        expect(intents(failed).isEmpty, "candidate intents discarded")
        expect(
            failedStage.transition.nextState == firstStage.transition.nextState,
            "stable state rollback"
        )
        expect(
            sameHistoryPublication(failedStage, firstStage),
            "stable history publication"
        )
        let failedRead = encodeAndRead(
            failed,
            executor: failedExecutor,
            command: failedCommand
        )
        expect(matches(failedRead.pixel, [0, 0, 255, 255]), "stable passthrough")

        let recoveryCommand = queue.makeCommandBuffer()!
        let recovered = prepareFrame(
            executor: validExecutor,
            token: validClaim.token,
            lease: oldLease,
            index: 72,
            source: source,
            pipeline: pipeline,
            command: recoveryCommand,
            previous: failedStage
        )
        guard let recoveredStage = recovered.stages.first else {
            fatalError("recovered stage")
        }
        expect(
            intents(recovered) == ["material", "material", "material"],
            "stable recovery does not reseed"
        )
        let recoveredRead = encodeAndRead(
            recovered,
            executor: validExecutor,
            command: recoveryCommand
        )
        expect(
            matches(recoveredRead.pixel, [0, 128, 64, 255]),
            "stable recovery output"
        )

        let freshLease = lease(targetPlan, device: device, generation: 71)
        guard let historyCopies = copies(
            stage: recoveredStage,
            oldLease: oldLease,
            newLease: freshLease
        ), historyCopies.count == 1 else { fatalError("fresh history copies") }
        let freshFailedCommand = queue.makeCommandBuffer()!
        let freshFailed = prepareFrame(
            executor: failedExecutor,
            token: failedClaim.token,
            lease: freshLease,
            copies: historyCopies,
            index: 73,
            source: source,
            pipeline: pipeline,
            command: freshFailedCommand,
            previous: recoveredStage
        )
        guard let freshFailedStage = freshFailed.stages.first,
              let freshHistory = freshFailedStage.persistentResources[history],
              let freshResource = freshLease.framebufferAllocation
                .resources[history] else { fatalError("fresh failed stage") }
        expect(
            freshFailedStage.effectLocalFailureReasonCode == failureReason
                && freshFailedStage.historyRehydrateCopyCount == 1,
            "fresh typed failure after rehydrate"
        )
        expect(intents(freshFailed).isEmpty, "fresh candidate intents discarded")
        expect(
            freshFailedStage.transition.transaction.mappingBefore
                == freshFailedStage.transition.transaction.mappingAfter,
            "fresh mapping rollback"
        )
        expect(
            freshHistory.publication.texture
                === freshLease.texturesByToken[freshResource.token],
            "fresh history publication"
        )
        expect(
            freshFailedStage.transition.nextState.lastContentGeneration
                == recoveredStage.transition.nextState.lastContentGeneration,
            "fresh committed generation"
        )
        let freshFailedRead = encodeAndRead(
            freshFailed,
            executor: failedExecutor,
            command: freshFailedCommand
        )
        expect(
            matches(freshFailedRead.pixel, [0, 0, 255, 255]),
            "fresh passthrough"
        )

        let freshRecoveryCommand = queue.makeCommandBuffer()!
        let freshRecovered = prepareFrame(
            executor: validExecutor,
            token: validClaim.token,
            lease: freshLease,
            index: 74,
            source: source,
            pipeline: pipeline,
            command: freshRecoveryCommand,
            previous: freshFailedStage
        )
        expect(
            intents(freshRecovered) == ["material", "material", "material"],
            "fresh recovery does not reseed"
        )
        let freshRecoveredRead = encodeAndRead(
            freshRecovered,
            executor: validExecutor,
            command: freshRecoveryCommand
        )
        expect(
            matches(freshRecoveredRead.pixel, [0, 128, 64, 255]),
            "fresh recovery output"
        )

        let payload: [String: Any] = [
            "metalAvailable": true,
            "failureReason": failureReason,
            "firstFrameRollback": true,
            "stableRollback": true,
            "freshRehydrateRollback": true,
            "recovery": true,
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
class ScenePersistentHistoryVisualFailureGPUTests(unittest.TestCase):
    def test_visual_failure_preserves_committed_history_and_recovers(self) -> None:
        compilation, completed = compile_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            payload,
            {
                "metalAvailable": True,
                "failureReason": "material-variant-envelope-uniform-schema",
                "firstFrameRollback": True,
                "stableRollback": True,
                "freshRehydrateRollback": True,
                "recovery": True,
            },
        )


if __name__ == "__main__":
    unittest.main()
