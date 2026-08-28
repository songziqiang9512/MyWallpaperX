#!/usr/bin/env python3

"""Production Metal gate for an ordered preserved-channel feedback pair."""

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
compile_harness = EXECUTOR_FIXTURE["compile_harness"]
SUPPORT = EXECUTOR_FIXTURE["SUPPORT"]
HARNESS_PREFIX = EXECUTOR_FIXTURE["HARNESS"].split("@main", 1)[0]


HARNESS = HARNESS_PREFIX + r'''
private func orderedScalarFeedbackGraph(
    clear: Bool = true,
    unique: Bool = true,
    firstReadsHistory: Bool = true,
    brokenAlternation: Bool = false,
    oddWriterCount: Bool = false
) -> Graph {
    let clearValue: SceneJSONValue? = clear
        ? .string("0.75 0 0 0") : nil
    var nodes = [
        material(
            0,
            ordinal: 0,
            target: second,
            read: firstReadsHistory ? first : input
        ),
        material(1, ordinal: 1, target: first, read: second),
        material(
            2,
            ordinal: 2,
            target: brokenAlternation ? first : second,
            read: input
        ),
        material(
            3,
            ordinal: 3,
            target: brokenAlternation ? second : first,
            read: second
        ),
    ]
    if oddWriterCount {
        nodes.append(material(
            4,
            ordinal: 4,
            target: second,
            read: first
        ))
    }
    nodes.append(material(
        oddWriterCount ? 5 : 4,
        ordinal: oddWriterCount ? 5 : 4,
        target: output,
        read: first
    ))
    return graph(
        targets: [
            rawTarget(
                first,
                format: "r16f",
                unique: unique,
                clear: clearValue
            ),
            rawTarget(
                second,
                format: "r16f",
                unique: unique,
                clear: clearValue
            ),
        ],
        nodes: nodes
    )
}

private func orderedScalarCatalog(
    _ graph: Graph,
    firstConsumer: String = "whole"
) -> SceneResolvedMaterialRuntimeCatalog {
    var consumers: [Int: String] = [
        0: firstConsumer,
        1: "red",
        3: "red",
        graph.nodes.last!.nodeIndex: "red",
    ]
    if graph.nodes.contains(where: { $0.nodeIndex == 4 && $0.target == second }) {
        consumers[4] = "red"
    }
    return catalog(
        for: graph,
        scalarProducerNodes: [2],
        scalarConsumerNodes: consumers
    )
}

private func rejectedOrderedScalarGraph(
    _ graph: Graph,
    firstConsumer: String = "whole"
) -> Bool {
    let chain = admittedGraph(graph)
    let values = capabilities(
        chain,
        catalog: orderedScalarCatalog(
            graph,
            firstConsumer: firstConsumer
        )
    )
    return values.claim(chain) == nil
        && values.reportLines.contains {
            $0.contains("rejection: r16f-scalar-graph-unproven count=1")
        }
}

private func materialIntentIndices(
    _ prepared: Executor.PreparedGraph
) -> [Int] {
    prepared.stages.flatMap { stage in
        stage.transition.transaction.intents.compactMap { intent in
            if case let .material(nodeIndex, _, _, _) = intent {
                return nodeIndex
            }
            return nil
        }
    }
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

        var results: [String: Bool] = [:]
        var observedPixels: [String: [UInt8]] = [:]
        let graph = orderedScalarFeedbackGraph()
        let chain = admittedGraph(graph)
        let values = capabilities(
            chain,
            catalog: orderedScalarCatalog(graph)
        )
        let claim = values.claim(chain)
        results["unseenR16FOrderedPairAdmitted"] = claim != nil

        if let claim,
           let executor = Executor(device: device, capabilities: values),
           let firstBuffer = queue.makeCommandBuffer() {
            let lease = makeLease(
                requirePlan(graph),
                device: device,
                generation: 101
            )
            let preparation = executor.prepare(
                token: claim.token,
                leases: [lease],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(101),
                sourceTexture: makeSource(device),
                sourceUniforms: .neutral(),
                sourcePipeline: makeSourcePipeline(device),
                frameInputs: .init(),
                commandBuffer: firstBuffer,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 101,
                resetGeneration: 101
            )
            if case let .success(prepared) = preparation,
               prepared.stages.count == 1,
               executor.encode(prepared, commandBuffer: firstBuffer),
               let readback = appendReadback(
                   prepared.finalTexture,
                   commandBuffer: firstBuffer
               ) {
                let stage = prepared.stages[0]
                firstBuffer.commit()
                firstBuffer.waitUntilCompleted()
                let state = stage.transition.nextState
                let mapping = stage.transition.transaction.mappingAfter
                results["firstFrameGPUCompleted"] =
                    firstBuffer.status == .completed && firstBuffer.error == nil
                results["writerOrderPreserved"] =
                    materialIntentIndices(prepared) == [0, 1, 2, 3, 4]
                results["laterWriterReachesTerminal"] = matches(
                    readback.firstPixel,
                    [0, 0, 64, 255]
                ) && matches(readback.lastPixel, [0, 0, 64, 255])
                observedPixels["first"] = readback.firstPixel
                results["historyAndScratchAreDistinct"] =
                    state.historyLogicalIdentities == Set([first])
                    && state.historyClosureIdentities == Set([first])
                    && (state.logicalMapping[first]?.contentGeneration ?? 0) > 0
                    && state.logicalMapping[second]?.contentGeneration == 0
                    && (mapping[first]?.contentGeneration ?? 0)
                        > (mapping[second]?.contentGeneration ?? 0)
                results["publicationsRemainTyped"] =
                    stage.frameResources[first]?.publication
                        .candidate.content == .scalarRedFloat16
                    && stage.frameResources[second]?.publication
                        .candidate.content == .scalarRedFloat16
                    && stage.persistentResources[first]?.publication
                        .candidate.content == .scalarRedFloat16
                    && stage.persistentResources[second] == nil

                if let nextBuffer = queue.makeCommandBuffer() {
                    let nextPreparation = executor.prepare(
                        token: claim.token,
                        leases: [lease],
                        historyRehydrateCopiesByEffect: [:],
                        frame: frame(102),
                        sourceTexture: makeSource(device),
                        sourceUniforms: .neutral(),
                        sourcePipeline: makeSourcePipeline(device),
                        frameInputs: .init(),
                        commandBuffer: nextBuffer,
                        previousStates: [effect: state],
                        previousGraphResources: [
                            effect: stage.persistentResources,
                        ],
                        effectGeneration: 101,
                        resetGeneration: 101
                    )
                    if case let .success(nextPrepared) = nextPreparation,
                       nextPrepared.stages.count == 1,
                       executor.encode(nextPrepared, commandBuffer: nextBuffer),
                       let nextReadback = appendReadback(
                           nextPrepared.finalTexture,
                           commandBuffer: nextBuffer
                       ) {
                        let nextStage = nextPrepared.stages[0]
                        nextBuffer.commit()
                        nextBuffer.waitUntilCompleted()
                        results["nextFrameGPUCompleted"] =
                            nextBuffer.status == .completed
                                && nextBuffer.error == nil
                        results["nextFrameReusesHistoryWithoutInitialize"] =
                            intentKinds(nextPrepared).first != "initialize"
                            && nextStage.transition.nextState
                                .historyLogicalIdentities == Set([first])
                        results["nextFrameTerminalStable"] = matches(
                            nextReadback.firstPixel,
                            [0, 0, 64, 255]
                        ) && matches(
                            nextReadback.lastPixel,
                            [0, 0, 64, 255]
                        )
                        observedPixels["next"] = nextReadback.firstPixel
                    }
                }
            }
        }

        results["missingClearRejected"] = rejectedOrderedScalarGraph(
            orderedScalarFeedbackGraph(clear: false)
        )
        results["nonUniqueRejected"] = rejectedOrderedScalarGraph(
            orderedScalarFeedbackGraph(unique: false)
        )
        results["missingHistoryReadRejected"] = rejectedOrderedScalarGraph(
            orderedScalarFeedbackGraph(firstReadsHistory: false)
        )
        results["brokenAlternationRejected"] = rejectedOrderedScalarGraph(
            orderedScalarFeedbackGraph(brokenAlternation: true)
        )
        results["oddWriterCountRejected"] = rejectedOrderedScalarGraph(
            orderedScalarFeedbackGraph(oddWriterCount: true)
        )
        results["wrongScalarChannelRejected"] = rejectedOrderedScalarGraph(
            orderedScalarFeedbackGraph(),
            firstConsumer: "green"
        )

        let payload: [String: Any] = [
            "metalAvailable": true,
            "observedPixels": observedPixels,
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
class ScenePreservedChannelOrderedFeedbackTests(unittest.TestCase):
    def test_ordered_feedback_executes_and_keeps_unsafe_shapes_closed(self) -> None:
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
