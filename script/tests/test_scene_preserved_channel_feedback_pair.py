#!/usr/bin/env python3

"""Production Metal gate for one preserved-channel feedback/swap pair."""

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
private let pressure = Graph.TextureIdentity(
    kind: .framebuffer,
    layerID: layerID,
    effect: effect,
    name: "pressure"
)

private func feedbackPairGraph(
    format: String,
    clear: Bool = true,
    unique: Bool = true,
    commandKind: Graph.NodeKind = .swap,
    postSwapWriter: Bool = false
) -> Graph {
    let clearValue: SceneJSONValue? = clear
        ? .string("0.125 0.25 0 1") : nil
    var nodes = [
        material(0, ordinal: 0, target: second, read: first),
        material(1, ordinal: 1, target: second, read: first),
        material(2, ordinal: 2, target: first, read: second),
        material(3, ordinal: 3, target: output, read: first),
        command(4, kind: commandKind, source: first, target: second),
    ]
    if postSwapWriter {
        nodes.append(material(
            5,
            ordinal: 4,
            target: second,
            read: input
        ))
    }
    return graph(
        targets: [
            rawTarget(
                first,
                format: format,
                unique: unique,
                clear: clearValue
            ),
            rawTarget(
                second,
                format: format,
                unique: unique,
                clear: clearValue
            ),
        ],
        nodes: nodes
    )
}

private func pairCatalog(
    _ graph: Graph,
    consumerOverride: (node: Int, channel: String)? = nil
) -> SceneResolvedMaterialRuntimeCatalog {
    var consumers = Dictionary(
        uniqueKeysWithValues: graph.nodes.compactMap { node in
            node.kind == .material && node.bindings.contains(where: {
                $0.texture == first || $0.texture == second
            }) ? (node.nodeIndex, "rg") : nil
        }
    )
    if let consumerOverride {
        consumers[consumerOverride.node] = consumerOverride.channel
    }
    return catalog(for: graph, scalarConsumerNodes: consumers)
}

private func rejected(
    _ graph: Graph,
    catalog: SceneResolvedMaterialRuntimeCatalog,
    code: String
) -> Bool {
    let chain = admittedGraph(graph)
    let values = capabilities(chain, catalog: catalog)
    return values.claim(chain) == nil
        && values.reportLines.contains {
            $0.contains("rejection: \(code) count=1")
        }
}

private func laterScalarBoundaryGraph() -> Graph {
    let clear: SceneJSONValue = .string("0 0 0 0")
    return graph(
        targets: [
            rawTarget(
                first,
                format: "rg1616f",
                unique: true,
                clear: clear
            ),
            rawTarget(
                second,
                format: "rg1616f",
                unique: true,
                clear: clear
            ),
            rawTarget(pressure, format: "r16f", unique: true),
        ],
        nodes: [
            material(0, ordinal: 0, target: second, read: first),
            material(1, ordinal: 1, target: second, read: first),
            material(2, ordinal: 2, target: first, read: second),
            material(3, ordinal: 3, target: pressure, read: input),
            material(4, ordinal: 4, target: pressure, read: input),
            material(5, ordinal: 5, target: output, read: first),
            command(6, kind: .swap, source: first, target: second),
        ]
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

        var results: [String: Bool] = [:]
        var observedPixels: [String: [UInt8]] = [:]
        let graph = feedbackPairGraph(format: "rg88")
        let chain = admittedGraph(graph)
        let values = capabilities(chain, catalog: pairCatalog(graph))
        let claim = values.claim(chain)
        results["unseenRG88PairAdmitted"] = claim != nil

        if let claim,
           let executor = Executor(device: device, capabilities: values),
           let firstBuffer = queue.makeCommandBuffer() {
            let lease = makeLease(
                requirePlan(graph),
                device: device,
                generation: 91
            )
            let firstPreparation = executor.prepare(
                token: claim.token,
                leases: [lease],
                historyRehydrateCopiesByEffect: [:],
                frame: frame(91),
                sourceTexture: makeSource(device),
                sourceUniforms: .neutral(),
                sourcePipeline: makeSourcePipeline(device),
                dedicatedInputs: .init(),
                commandBuffer: firstBuffer,
                previousStates: [:],
                previousGraphResources: [:],
                effectGeneration: 91,
                resetGeneration: 91
            )
            if case let .success(firstPrepared) = firstPreparation,
               firstPrepared.stages.count == 1,
               executor.encode(firstPrepared, commandBuffer: firstBuffer),
               let firstRead = appendReadback(
                   firstPrepared.finalTexture,
                   commandBuffer: firstBuffer
               ) {
                let firstStage = firstPrepared.stages[0]
                firstBuffer.commit()
                firstBuffer.waitUntilCompleted()
                let firstState = firstStage.transition.nextState
                results["firstFrameGPUCompleted"] =
                    firstBuffer.status == .completed && firstBuffer.error == nil
                observedPixels["first"] = firstRead.firstPixel
                results["firstFrameTerminalVisible"] = matches(
                    firstRead.firstPixel,
                    [0, 64, 32, 255]
                ) && matches(firstRead.lastPixel, [0, 64, 32, 255])
                results["terminalSwapPermutesTypedHistory"] =
                    firstState.historyClosureIdentities == Set([first, second])
                    && firstState.logicalMapping[first]?.token
                        == firstState.authoredResources[second]?.token
                    && firstState.logicalMapping[second]?.token
                        == firstState.authoredResources[first]?.token
                    && firstStage.persistentResources[first]?.publication
                        .candidate.content == .redGreenUnorm
                    && firstStage.persistentResources[second]?.publication
                        .candidate.content == .redGreenUnorm
                    && intentKinds(firstPrepared).last == "swap"

                if let nextBuffer = queue.makeCommandBuffer() {
                    let nextPreparation = executor.prepare(
                        token: claim.token,
                        leases: [lease],
                        historyRehydrateCopiesByEffect: [:],
                        frame: frame(92),
                        sourceTexture: makeSource(device),
                        sourceUniforms: .neutral(),
                        sourcePipeline: makeSourcePipeline(device),
                        dedicatedInputs: .init(),
                        commandBuffer: nextBuffer,
                        previousStates: [effect: firstState],
                        previousGraphResources: [
                            effect: firstStage.persistentResources,
                        ],
                        effectGeneration: 91,
                        resetGeneration: 91
                    )
                    if case let .success(nextPrepared) = nextPreparation,
                       nextPrepared.stages.count == 1,
                       executor.encode(nextPrepared, commandBuffer: nextBuffer),
                       let nextRead = appendReadback(
                           nextPrepared.finalTexture,
                           commandBuffer: nextBuffer
                       ) {
                        let nextStage = nextPrepared.stages[0]
                        nextBuffer.commit()
                        nextBuffer.waitUntilCompleted()
                        let nextState = nextStage.transition.nextState
                        results["nextFrameGPUCompleted"] =
                            nextBuffer.status == .completed
                                && nextBuffer.error == nil
                        observedPixels["next"] = nextRead.firstPixel
                        results["nextFrameTerminalVisible"] = matches(
                            nextRead.firstPixel,
                            [0, 64, 32, 255]
                        ) && matches(nextRead.lastPixel, [0, 64, 32, 255])
                        results["nextFrameUsesAndRotatesPreviousMapping"] =
                            nextState.logicalMapping[first]?.token
                                == nextState.authoredResources[first]?.token
                            && nextState.logicalMapping[second]?.token
                                == nextState.authoredResources[second]?.token
                            && intentKinds(nextPrepared).first != "initialize"
                    }
                }
            }
        }

        let missingClear = feedbackPairGraph(format: "rg88", clear: false)
        results["missingClearRejected"] = rejected(
            missingClear,
            catalog: pairCatalog(missingClear),
            code: "rg88-red-green-graph-unproven"
        )
        let nonUnique = feedbackPairGraph(format: "rg88", unique: false)
        results["nonUniquePairRejected"] = rejected(
            nonUnique,
            catalog: pairCatalog(nonUnique),
            code: "rg88-red-green-graph-unproven"
        )
        let copied = feedbackPairGraph(format: "rg88", commandKind: .copy)
        results["copyPairRejected"] = rejected(
            copied,
            catalog: pairCatalog(copied),
            code: "rg88-red-green-graph-unproven"
        )
        let postSwap = feedbackPairGraph(format: "rg88", postSwapWriter: true)
        results["postSwapAccessRejected"] = rejected(
            postSwap,
            catalog: pairCatalog(postSwap),
            code: "rg88-red-green-graph-unproven"
        )
        let whole = feedbackPairGraph(format: "rg88")
        results["wholeChannelConsumerRejected"] = rejected(
            whole,
            catalog: pairCatalog(
                whole,
                consumerOverride: (node: 0, channel: "whole")
            ),
            code: "rg88-red-green-graph-unproven"
        )
        let component = feedbackPairGraph(format: "rg88")
        results["singleComponentConsumerRemainsClosed"] = rejected(
            component,
            catalog: pairCatalog(
                component,
                consumerOverride: (node: 0, channel: "green")
            ),
            code: "rg88-red-green-graph-unproven"
        )

        let scalarBoundary = laterScalarBoundaryGraph()
        let scalarBoundaryCatalog = catalog(
            for: scalarBoundary,
            scalarProducerNodes: [3, 4],
            scalarConsumerNodes: [0: "rg", 1: "rg", 2: "rg", 5: "rg"]
        )
        results["validatedPairReportsLaterScalarTarget"] = rejected(
            scalarBoundary,
            catalog: scalarBoundaryCatalog,
            code: "r16f-scalar-graph-unproven"
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
class ScenePreservedChannelFeedbackPairTests(unittest.TestCase):
    def test_feedback_pair_executes_and_keeps_unsafe_shapes_closed(self) -> None:
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
