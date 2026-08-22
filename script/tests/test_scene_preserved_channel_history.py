#!/usr/bin/env python3

"""Preserved-channel unique history GPU and lifecycle gate."""

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
    static func main() throws {
        setenv("MWX_SCENE_GENERIC_SHADER_ROUTE", "disable-generic", 1)
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalAvailable\":false}")
            return
        }
        let source = sourceTexture(device)
        let pipeline = sourcePipeline(device)
        let clear = SceneJSONValue.string("0.25 0.5 0.75 1")
        let fixtures: [(String, Bool, SceneJSONValue?, Plan.TextureFormat,
                        SceneResolvedMaterialAttachmentKind,
                        SceneTextureContent, MTLPixelFormat, [UInt8])] = [
            ("r8", false, nil, .r8, .scalarRedUnorm,
             .scalarRedUnorm, .r8Unorm, [0, 0, 0, 255]),
            ("rg88", true, clear, .rg88, .redGreenUnorm,
             .redGreenUnorm, .rg8Unorm, [0, 128, 64, 255]),
            ("r16f", false, nil, .r16f, .scalarRedFloat16,
             .scalarRedFloat16, .r16Float, [0, 0, 0, 255]),
            ("rg1616f", true, clear, .rg1616f, .redGreenFloat16,
             .redGreenFloat16, .rg16Float, [0, 128, 64, 255]),
        ]
        for (offset, fixture) in fixtures.enumerated() {
            let (format, pair, clear, planFormat, storage,
                 content, pixelFormat, expected) = fixture
            let raw = graph(format: format, clear: clear)
            let chain = admitted(raw)
            let values = capabilities(raw, pair: pair)
            guard let claim = values.claim(chain),
                  let capability = values.resolve(claim.token, for: chain),
                  let command = queue.makeCommandBuffer(),
                  let executor = Executor(device: device, capabilities: values)
            else { fatalError("\(format) claim") }
            let targetPlan = plan(raw)
            let historyTarget = targetPlan.logicalTargets.first {
                $0.identity == history
            }
            let scratchTarget = targetPlan.logicalTargets.first {
                $0.identity == scratch
            }
            expect(historyTarget?.format == planFormat, "\(format) format")
            expect(historyTarget?.isUnique == true, "\(format) unique")
            expect(
                historyTarget?.lifetime.requiresHistorySeed == true,
                "\(format) history"
            )
            expect(scratchTarget?.isUnique == false, "\(format) scratch")
            expect(
                capability.material(for: raw.nodes[0])?.attachmentStorage
                    == storage,
                "\(format) program"
            )
            let currentLease = lease(
                targetPlan,
                device: device,
                generation: UInt64(10 + offset)
            )
            let prepared = prepare(
                executor: executor,
                token: claim.token,
                lease: currentLease,
                index: UInt64(10 + offset),
                source: source,
                pipeline: pipeline,
                command: command
            )
            guard case let .success(value) = prepared,
                  let stage = value.stages.first,
                  let publication = stage.persistentResources[history],
                  executor.encode(value, commandBuffer: command),
                  let pixel = readback(value.finalTexture, command: command)
            else { fatalError("\(format) first frame") }
            expect(
                intents(value) == [
                    "initialize", "material", "material", "material",
                ],
                "\(format) initialization"
            )
            expect(
                stage.transition.nextState.historyClosureIdentities
                    == Set([history]),
                "\(format) closure"
            )
            expect(
                publication.publication.candidate.content == content
                    && publication.publication.candidate.purpose
                        == .preservedChannels
                    && publication.publication.candidate.pixelFormat
                        == pixelFormat,
                "\(format) publication"
            )
            command.commit()
            command.waitUntilCompleted()
            expect(
                command.status == .completed && command.error == nil
                    && matches(pixel.pixel, expected),
                "\(format) GPU"
            )
            for boundary in RejectedHistoryBoundary.allCases {
                let rejected = rejectedHistoryGraph(
                    format: format,
                    boundary: boundary
                )
                expect(
                    capabilities(rejected, pair: pair).claim(
                        admitted(rejected)
                    ) == nil,
                    "\(format) \(boundary.rawValue)"
                )
            }
        }

        let raw = graph(format: "rg1616f", clear: clear)
        let chain = admitted(raw)
        let values = capabilities(raw, pair: true)
        guard let claim = values.claim(chain),
              let executor = Executor(device: device, capabilities: values)
        else { fatalError("lifecycle claim") }
        let targetPlan = plan(raw)
        let firstLease = lease(targetPlan, device: device, generation: 30)
        guard let firstCommand = queue.makeCommandBuffer() else {
            fatalError("first command")
        }
        let firstResult = prepare(
            executor: executor,
            token: claim.token,
            lease: firstLease,
            index: 30,
            source: source,
            pipeline: pipeline,
            command: firstCommand
        )
        guard case let .success(first) = firstResult,
              let firstStage = first.stages.first,
              executor.encode(first, commandBuffer: firstCommand),
              let firstPixel = readback(first.finalTexture, command: firstCommand)
        else { fatalError("first frame") }
        firstCommand.commit()
        firstCommand.waitUntilCompleted()
        expect(
            firstCommand.status == .completed
                && matches(firstPixel.pixel, [0, 128, 64, 255]),
            "first visible"
        )

        guard let nextCommand = queue.makeCommandBuffer() else {
            fatalError("next command")
        }
        let nextResult = prepare(
            executor: executor,
            token: claim.token,
            lease: firstLease,
            index: 31,
            source: source,
            pipeline: pipeline,
            command: nextCommand,
            previous: firstStage
        )
        guard case let .success(next) = nextResult,
              let nextStage = next.stages.first,
              executor.encode(next, commandBuffer: nextCommand),
              let nextPixel = readback(next.finalTexture, command: nextCommand)
        else { fatalError("next frame") }
        nextCommand.commit()
        nextCommand.waitUntilCompleted()
        expect(
            intents(next) == ["material", "material", "material"]
                && nextCommand.status == .completed
                && matches(nextPixel.pixel, [0, 128, 64, 255]),
            "next previous-current"
        )

        let secondLease = lease(targetPlan, device: device, generation: 31)
        guard let historyCopies = copies(
            stage: nextStage,
            oldLease: firstLease,
            newLease: secondLease
        ), historyCopies.count == 1 else { fatalError("copies") }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let wrongTexture = device.makeTexture(descriptor: descriptor),
              let wrongCommand = queue.makeCommandBuffer() else {
            fatalError("wrong descriptor setup")
        }
        let correct = historyCopies[0]
        let wrong = ScenePreparedPersistentGraphTargets.HistoryRehydrateCopy(
            sourceToken: correct.sourceToken,
            sourceTexture: correct.sourceTexture,
            targetToken: correct.targetToken,
            targetTexture: wrongTexture
        )
        let wrongResult = prepare(
            executor: executor,
            token: claim.token,
            lease: secondLease,
            copies: [wrong],
            index: 32,
            source: source,
            pipeline: pipeline,
            command: wrongCommand,
            previous: nextStage
        )
        guard let preserved = readback(
            next.finalTexture,
            command: wrongCommand
        ) else { fatalError("previous-current readback") }
        wrongCommand.commit()
        wrongCommand.waitUntilCompleted()
        expect(
            failure(wrongResult) == Executor.Failure.historyRejected.rawValue,
            "wrong descriptor rejection"
        )
        expect(
            matches(preserved.pixel, [0, 128, 64, 255]),
            "wrong descriptor previous-current"
        )

        guard let rehydrateCommand = queue.makeCommandBuffer() else {
            fatalError("rehydrate command")
        }
        let rehydrateResult = prepare(
            executor: executor,
            token: claim.token,
            lease: secondLease,
            copies: historyCopies,
            index: 33,
            source: source,
            pipeline: pipeline,
            command: rehydrateCommand,
            previous: nextStage
        )
        guard case let .success(rehydrated) = rehydrateResult,
              let rehydratedStage = rehydrated.stages.first,
              rehydratedStage.historyRehydrateCopyCount == 1,
              executor.encode(rehydrated, commandBuffer: rehydrateCommand),
              let rehydratedPixel = readback(
                  rehydrated.finalTexture,
                  command: rehydrateCommand
              ) else { fatalError("rehydrate") }
        rehydrateCommand.commit()
        rehydrateCommand.waitUntilCompleted()
        expect(
            rehydrateCommand.status == .completed
                && matches(rehydratedPixel.pixel, [0, 128, 64, 255]),
            "rehydrate visible"
        )

        guard let resetCommand = queue.makeCommandBuffer() else {
            fatalError("reset command")
        }
        let resetResult = prepare(
            executor: executor,
            token: claim.token,
            lease: secondLease,
            index: 34,
            source: source,
            pipeline: pipeline,
            command: resetCommand,
            previous: rehydratedStage,
            reset: 2
        )
        guard case let .success(reset) = resetResult,
              let resetStage = reset.stages.first,
              executor.encode(reset, commandBuffer: resetCommand),
              let resetPixel = readback(reset.finalTexture, command: resetCommand)
        else { fatalError("reset") }
        resetCommand.commit()
        resetCommand.waitUntilCompleted()
        expect(
            resetStage.historyContentDiscarded
                && intents(reset) == [
                    "initialize", "material", "material", "material",
                ]
                && resetCommand.status == .completed
                && matches(resetPixel.pixel, [0, 128, 64, 255]),
            "reset initialization"
        )

        guard let recoveryCommand = queue.makeCommandBuffer() else {
            fatalError("recovery command")
        }
        let recoveryResult = prepare(
            executor: executor,
            token: claim.token,
            lease: secondLease,
            index: 35,
            source: source,
            pipeline: pipeline,
            command: recoveryCommand,
            previous: resetStage,
            reset: 2
        )
        guard case let .success(recovered) = recoveryResult,
              executor.encode(recovered, commandBuffer: recoveryCommand),
              let recoveredPixel = readback(
                  recovered.finalTexture,
                  command: recoveryCommand
              ) else { fatalError("recovery") }
        recoveryCommand.commit()
        recoveryCommand.waitUntilCompleted()
        expect(
            intents(recovered) == ["material", "material", "material"]
                && recoveryCommand.status == .completed
                && matches(recoveredPixel.pixel, [0, 128, 64, 255]),
            "recovery visible"
        )
        let payload: [String: Any] = ["metalAvailable": true, "ok": true]
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(data)
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ScenePreservedChannelHistoryTests(unittest.TestCase):
    def test_unique_read_before_write_history_uses_shared_graph_executor(self) -> None:
        compilation, completed = compile_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertTrue(payload["ok"])


if __name__ == "__main__":
    unittest.main()
