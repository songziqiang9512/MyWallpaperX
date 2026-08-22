#!/usr/bin/env python3

"""Production Metal gate for frame-local unique preserved-channel targets."""

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

private enum FrameLocalBoundary: String, CaseIterable {
    case sameNode = "same-node"
    case multipleWriters = "multiple-writers"
    case command = "command"
    case missingReader = "missing-reader"
}

private func frameLocalGraph(
    format: String,
    boundary: FrameLocalBoundary? = nil
) -> Graph {
    let nodes: [Graph.Node]
    let targets: [Graph.RenderTarget]
    switch boundary {
    case nil:
        nodes = [
            material(0, target: history, read: input),
            material(1, target: output, read: history),
        ]
        targets = [target(history, format: format, unique: true)]
    case .sameNode:
        nodes = [
            material(0, target: history, read: history),
            material(1, target: output, read: history),
        ]
        targets = [target(history, format: format, unique: true)]
    case .multipleWriters:
        nodes = [
            material(0, target: history, read: input),
            material(1, target: history, read: input),
            material(2, target: output, read: history),
        ]
        targets = [target(history, format: format, unique: true)]
    case .command:
        nodes = [
            material(0, target: history, read: input),
            command(1, source: history, target: scratch),
            material(2, target: output, read: scratch),
        ]
        targets = [
            target(history, format: format, unique: true),
            target(scratch, format: format, unique: false),
        ]
    case .missingReader:
        nodes = [
            material(0, target: history, read: input),
            material(1, target: output, read: input),
        ]
        targets = [target(history, format: format, unique: true)]
    }
    return .init(
        layerID: layerID,
        effects: [.init(
            key: effect,
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
        let fixtures: [(String, Bool, Plan.TextureFormat,
                        SceneResolvedMaterialAttachmentKind,
                        SceneTextureContent, MTLPixelFormat)] = [
            ("r8", false, .r8, .scalarRedUnorm,
             .scalarRedUnorm, .r8Unorm),
            ("rg88", true, .rg88, .redGreenUnorm,
             .redGreenUnorm, .rg8Unorm),
            ("r16f", false, .r16f, .scalarRedFloat16,
             .scalarRedFloat16, .r16Float),
            ("rg1616f", true, .rg1616f, .redGreenFloat16,
             .redGreenFloat16, .rg16Float),
        ]
        var results: [String: Bool] = [:]

        for (offset, fixture) in fixtures.enumerated() {
            let (format, pair, planFormat, storage, content, pixelFormat) = fixture
            let raw = frameLocalGraph(format: format)
            let chain = admitted(raw)
            let values = capabilities(raw, pair: pair)
            guard let claim = values.claim(chain),
                  let capability = values.resolve(claim.token, for: chain),
                  let executor = Executor(device: device, capabilities: values),
                  let firstCommand = queue.makeCommandBuffer() else {
                fatalError(
                    "\(format) claim: "
                        + values.reportLines.joined(separator: " | ")
                )
            }
            let targetPlan = plan(raw)
            let logical = targetPlan.logicalTargets.first {
                $0.identity == history
            }
            results["\(format)-plan-is-frame-local-unique"] =
                logical?.format == planFormat
                    && logical?.isUnique == true
                    && logical?.lifetime.firstWriteNodeIndex == 0
                    && logical?.lifetime.firstReadNodeIndex == 1
                    && logical?.lifetime.requiresHistorySeed == false
            results["\(format)-program-storage-is-typed"] =
                capability.material(for: raw.nodes[0])?.attachmentStorage
                    == storage

            let currentLease = lease(
                targetPlan,
                device: device,
                generation: UInt64(100 + offset)
            )
            let firstResult = prepare(
                executor: executor,
                token: claim.token,
                lease: currentLease,
                index: UInt64(100 + offset),
                source: source,
                pipeline: pipeline,
                command: firstCommand
            )
            guard case let .success(first) = firstResult,
                  let firstStage = first.stages.first,
                  let firstPublication = firstStage.frameResources[history],
                  executor.encode(first, commandBuffer: firstCommand),
                  let firstPixel = readback(
                      first.finalTexture,
                      command: firstCommand
                  ) else { fatalError("\(format) first frame") }
            firstCommand.commit()
            firstCommand.waitUntilCompleted()
            results["\(format)-first-frame-executes"] =
                intents(first) == ["material", "material"]
                    && firstStage.transition.nextState
                        .historyLogicalIdentities.isEmpty
                    && firstStage.transition.nextState
                        .historyClosureIdentities.isEmpty
                    && firstStage.persistentResources.isEmpty
                    && firstPublication.publication.candidate.content == content
                    && firstPublication.publication.candidate.pixelFormat
                        == pixelFormat
                    && firstCommand.status == .completed
                    && firstCommand.error == nil
                    && matches(firstPixel.pixel, [0, 0, 255, 255])

            guard let nextCommand = queue.makeCommandBuffer() else {
                fatalError("\(format) next command")
            }
            let nextResult = prepare(
                executor: executor,
                token: claim.token,
                lease: currentLease,
                index: UInt64(200 + offset),
                source: source,
                pipeline: pipeline,
                command: nextCommand,
                previous: firstStage
            )
            guard case let .success(next) = nextResult,
                  let nextStage = next.stages.first,
                  executor.encode(next, commandBuffer: nextCommand),
                  let nextPixel = readback(
                      next.finalTexture,
                      command: nextCommand
                  ) else { fatalError("\(format) next frame") }
            nextCommand.commit()
            nextCommand.waitUntilCompleted()
            results["\(format)-next-frame-stays-frame-local"] =
                intents(next) == ["material", "material"]
                    && nextStage.transition.nextState
                        .historyLogicalIdentities.isEmpty
                    && nextStage.transition.nextState
                        .historyClosureIdentities.isEmpty
                    && nextStage.persistentResources.isEmpty
                    && nextCommand.status == .completed
                    && nextCommand.error == nil
                    && matches(nextPixel.pixel, [0, 0, 255, 255])

            for boundary in FrameLocalBoundary.allCases {
                let rejected = frameLocalGraph(
                    format: format,
                    boundary: boundary
                )
                results["\(format)-\(boundary.rawValue)-rejected"] =
                    capabilities(rejected, pair: pair).claim(
                        admitted(rejected)
                    ) == nil
            }
        }

        let payload: [String: Any] = [
            "metalAvailable": true,
            "results": results,
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
class ScenePreservedChannelFrameLocalUniqueTests(unittest.TestCase):
    def test_unique_write_before_read_is_typed_and_frame_local(self) -> None:
        compilation, completed = compile_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)

        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        self.assertEqual(
            [
                name
                for name, passed in payload["results"].items()
                if not passed
            ],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()
