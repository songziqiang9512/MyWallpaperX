#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RUNTIME_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Runtime"
SWIFT_SOURCES = [
    RUNTIME_ROOT / "SceneGraphExecutionObservation.swift",
    RUNTIME_ROOT / "SceneGraphExecutionTelemetry.swift",
]

HARNESS = r'''
import Foundation

nonisolated final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@main
enum Harness {
    static let mainIdentity = SceneGraphExecutionEffectIdentity(
        layerID: 7,
        effectIndex: 2,
        descriptorID: "Graph A%=中"
    )

    static let mappingBefore = [
        SceneGraphExecutionLogicalBinding(
            logicalIdentity: "history-a", physicalIdentity: "texture-0"
        ),
        SceneGraphExecutionLogicalBinding(
            logicalIdentity: "history-b", physicalIdentity: "texture-1"
        ),
        SceneGraphExecutionLogicalBinding(
            logicalIdentity: "effect output/% 中", physicalIdentity: "texture-output"
        ),
    ]
    static let mappingAfter = [
        SceneGraphExecutionLogicalBinding(
            logicalIdentity: "history-a", physicalIdentity: "texture-1"
        ),
        SceneGraphExecutionLogicalBinding(
            logicalIdentity: "history-b", physicalIdentity: "texture-0"
        ),
        SceneGraphExecutionLogicalBinding(
            logicalIdentity: "effect output/% 中", physicalIdentity: "texture-output"
        ),
    ]

    static func described(
        _ bindings: [SceneGraphExecutionLogicalBinding],
        width: Int = 4,
        height: Int = 2
    ) -> [SceneGraphExecutionLogicalBinding] {
        bindings.map {
            .init(
                logicalIdentity: $0.logicalIdentity,
                physicalIdentity: $0.physicalIdentity,
                width: width,
                height: height,
                format: "rgbaBackbuffer"
            )
        }
    }

    static func nodes() -> [SceneGraphExecutionNodeObservation] {
        [
            .init(
                nodeIndex: 0,
                kind: .material,
                materialOrdinal: 0,
                commandOrdinal: nil,
                commandSource: nil,
                commandTarget: nil,
                advancesComposePair: false,
                disposition: .executed
            ),
            .init(
                nodeIndex: 1,
                kind: .copy,
                materialOrdinal: nil,
                commandOrdinal: 0,
                commandSource: "history-a",
                commandTarget: "history-b",
                advancesComposePair: false,
                disposition: .executed
            ),
            .init(
                nodeIndex: 2,
                kind: .swap,
                materialOrdinal: nil,
                commandOrdinal: 1,
                commandSource: "history-a",
                commandTarget: "history-b",
                advancesComposePair: false,
                disposition: .executed
            ),
            .init(
                nodeIndex: 3,
                kind: .material,
                materialOrdinal: 1,
                commandOrdinal: nil,
                commandSource: nil,
                commandTarget: nil,
                advancesComposePair: true,
                disposition: .executed
            ),
        ]
    }

    static let successCounts = SceneGraphExecutionNodeCounts(
        authored: 4,
        material: 2,
        copy: 1,
        swap: 1,
        compose: 1,
        rejected: 0
    )

    static func observation(
        identity: SceneGraphExecutionEffectIdentity = mainIdentity,
        graphIdentity: String = "graph identity",
        programIdentity: String = "program identity",
        programSequenceIdentity: String = "program sequence identity",
        transactionIdentity: String? = nil,
        frame: UInt64,
        effectGeneration: UInt64 = 1,
        allocationGeneration: UInt64 = 1,
        mappingGeneration: UInt64 = 1,
        customNodes: [SceneGraphExecutionNodeObservation]? = nil,
        authoredNodeIndices: [Int]? = nil,
        counts: SceneGraphExecutionNodeCounts? = nil,
        mappingBefore customBefore: [SceneGraphExecutionLogicalBinding]? = nil,
        mappingAfter customAfter: [SceneGraphExecutionLogicalBinding]? = nil,
        inputWidth: Int = 2_048,
        inputHeight: Int = 1_152,
        historyRehydrateCopyCount: Int = 0,
        historyContentDiscarded: Bool = false,
        composeSlotBefore: SceneGraphExecutionComposeSlot = .primary,
        composeSlotAfter: SceneGraphExecutionComposeSlot = .primary,
        history: SceneGraphExecutionHistoryState = .reused,
        reset: SceneGraphExecutionResetReason? = nil,
        publishOutput: Bool = true,
        outputIdentity: String = "effect output/% 中",
        physicalIdentity: String? = nil,
        publicationIdentity: String? = nil,
        consumed: Bool = false,
        outcome: SceneGraphExecutionOutcome = .succeeded,
        gpu: SceneGraphExecutionGPUCompletionStatus? = .completed
    ) throws -> SceneGraphExecutionObservation {
        let selectedNodes = customNodes ?? nodes()
        let selectedCounts = counts ?? successCounts
        let transaction = transactionIdentity ?? "tx-\(effectGeneration)-\(frame)"
        let selectedAfter = customAfter ?? mappingAfter
        let mappedOutput = selectedAfter.first(where: {
            $0.logicalIdentity == outputIdentity
        })?.physicalIdentity ?? "missing-physical-output"
        return try .init(
            runtimeInstanceIdentity: "runtime-fixture",
            identity: identity,
            graphIdentity: graphIdentity,
            programIdentity: programIdentity,
            programSequenceIdentity: programSequenceIdentity,
            transactionIdentity: transaction,
            frameIndex: frame,
            effectGeneration: effectGeneration,
            allocationGeneration: allocationGeneration,
            mappingGeneration: mappingGeneration,
            authoredNodeIndices: authoredNodeIndices ?? selectedNodes.map(\.nodeIndex),
            nodes: selectedNodes,
            expectedNodeCounts: selectedCounts,
            logicalMappingBefore: customBefore ?? mappingBefore,
            logicalMappingAfter: selectedAfter,
            inputWidth: inputWidth,
            inputHeight: inputHeight,
            historyRehydrateCopyCount: historyRehydrateCopyCount,
            historyContentDiscarded: historyContentDiscarded,
            composeSlotBefore: composeSlotBefore,
            composeSlotAfter: composeSlotAfter,
            historyState: history,
            resetReason: reset,
            finalOutput: publishOutput ? .init(
                identity: outputIdentity,
                physicalIdentity: physicalIdentity ?? mappedOutput,
                publicationIdentity: publicationIdentity ?? "pub-\(effectGeneration)-\(frame)",
                publicationGeneration: effectGeneration
            ) : nil,
            compositorConsumed: consumed,
            outcome: outcome,
            gpuCompletionStatus: gpu
        )
    }

    static func rejectedObservation(
        reason: String = "binding missing",
        publishOutput: Bool = false
    ) throws -> SceneGraphExecutionObservation {
        let rejectedNode = SceneGraphExecutionNodeObservation(
            nodeIndex: 0,
            kind: .material,
            materialOrdinal: 0,
            commandOrdinal: nil,
            commandSource: nil,
            commandTarget: nil,
            advancesComposePair: false,
            disposition: .rejected(reasonCode: reason)
        )
        let mapping = [SceneGraphExecutionLogicalBinding(
            logicalIdentity: "input", physicalIdentity: "texture"
        )]
        return try observation(
            identity: .init(layerID: 8, effectIndex: 1, descriptorID: "failure"),
            graphIdentity: "failure graph",
            programIdentity: "failure program",
            programSequenceIdentity: "failure sequence",
            transactionIdentity: "failure transaction",
            frame: 30,
            effectGeneration: 4,
            allocationGeneration: 9,
            mappingGeneration: 3,
            customNodes: [rejectedNode],
            counts: .init(
                authored: 1, material: 0, copy: 0,
                swap: 0, compose: 0, rejected: 1
            ),
            mappingBefore: mapping,
            mappingAfter: mapping,
            composeSlotBefore: .none,
            composeSlotAfter: .none,
            history: .none,
            publishOutput: publishOutput,
            outputIdentity: "input",
            publicationIdentity: "partial-publication",
            outcome: .failed(reasonCode: reason),
            gpu: nil
        )
    }

    static func rejectedNodes(
        reason: String
    ) -> [SceneGraphExecutionNodeObservation] {
        nodes().map { node in
            .init(
                nodeIndex: node.nodeIndex,
                kind: node.kind,
                materialOrdinal: node.materialOrdinal,
                commandOrdinal: node.commandOrdinal,
                commandSource: node.commandSource,
                commandTarget: node.commandTarget,
                advancesComposePair: node.advancesComposePair,
                disposition: .rejected(reasonCode: reason)
            )
        }
    }

    static func commandNode(
        kind: SceneGraphExecutionNodeKind,
        disposition: SceneGraphExecutionNodeDisposition = .executed,
        source: String = "history-a",
        target: String = "history-b"
    ) -> SceneGraphExecutionNodeObservation {
        .init(
            nodeIndex: 0,
            kind: kind,
            materialOrdinal: nil,
            commandOrdinal: 0,
            commandSource: source,
            commandTarget: target,
            advancesComposePair: false,
            disposition: disposition
        )
    }

    static func reindexedNodes(
        _ indices: [Int]
    ) -> [SceneGraphExecutionNodeObservation] {
        zip(nodes(), indices).map { pair in
            let node = pair.0
            return .init(
                nodeIndex: pair.1,
                kind: node.kind,
                materialOrdinal: node.materialOrdinal,
                commandOrdinal: node.commandOrdinal,
                commandSource: node.commandSource,
                commandTarget: node.commandTarget,
                advancesComposePair: node.advancesComposePair,
                disposition: node.disposition
            )
        }
    }

    static func errorCode(_ operation: () throws -> Void) -> String {
        do {
            try operation()
            return "none"
        } catch let error as SceneGraphExecutionObservationError {
            return error.rawValue
        } catch {
            return "unexpected"
        }
    }

    static func main() throws {
        let collector = LogCollector()
        let telemetry = SceneGraphExecutionTelemetry { collector.append($0) }
        let first = try observation(frame: 10, history: .seeded, reset: .initial)
        let next = try observation(frame: 12)
        let third = try observation(frame: 13)
        let consumed = try observation(frame: 13, consumed: true)
        let gpuCompleted = try observation(frame: 14, gpu: .completed)
        let gpuFailureNodes = rejectedNodes(reason: "gpu command failed")
        let gpuFailed = try observation(
            frame: 15,
            customNodes: gpuFailureNodes,
            counts: .init(
                authored: 4, material: 0, copy: 0,
                swap: 0, compose: 0, rejected: 4
            ),
            mappingAfter: mappingBefore,
            composeSlotBefore: .none,
            composeSlotAfter: .none,
            publishOutput: false,
            outcome: .failed(reasonCode: "gpu command failed"),
            gpu: .failed
        )
        let resized = try observation(
            frame: 20,
            allocationGeneration: 2,
            mappingGeneration: 2,
            inputWidth: 962,
            inputHeight: 542,
            reset: .allocationReprepare
        )
        let clearReset = try observation(frame: 21)
        let reparsed = try observation(
            frame: 22,
            effectGeneration: 2,
            allocationGeneration: 3,
            mappingGeneration: 2,
            reset: .effectReparse
        )
        let lifecycleResults = [
            telemetry.record(first), telemetry.record(first),
            telemetry.record(next), telemetry.record(third),
            telemetry.record(consumed), telemetry.record(gpuCompleted),
            telemetry.record(gpuCompleted), telemetry.record(gpuFailed),
            telemetry.record(gpuFailed), telemetry.record(resized),
            telemetry.record(resized), telemetry.record(clearReset),
            telemetry.record(reparsed), telemetry.record(reparsed),
        ]

        let failureCollector = LogCollector()
        let failureTelemetry = SceneGraphExecutionTelemetry {
            failureCollector.append($0)
        }
        let validFailure = try rejectedObservation()
        let failureResults = [
            failureTelemetry.record(validFailure),
            failureTelemetry.record(validFailure),
        ]

        let programCollector = LogCollector()
        let programTelemetry = SceneGraphExecutionTelemetry {
            programCollector.append($0)
        }
        let programA = try observation(
            identity: .init(layerID: 40, effectIndex: 0, descriptorID: "program-key"),
            programIdentity: "program-a",
            transactionIdentity: "program-a-tx",
            frame: 1
        )
        let programB = try observation(
            identity: .init(layerID: 40, effectIndex: 0, descriptorID: "program-key"),
            programIdentity: "program-b",
            transactionIdentity: "program-b-tx",
            frame: 2
        )
        let programResults = [
            programTelemetry.record(programA),
            programTelemetry.record(programB),
        ]

        let consumeCollector = LogCollector()
        let consumeTelemetry = SceneGraphExecutionTelemetry {
            consumeCollector.append($0)
        }
        let consume = try observation(
            identity: .init(layerID: 50, effectIndex: 0, descriptorID: "consume"),
            transactionIdentity: "consume-transaction",
            frame: 1,
            publicationIdentity: "consume-publication",
            consumed: true
        )
        let consumeResults = [
            consumeTelemetry.record(consume),
            consumeTelemetry.record(consume),
            consumeTelemetry.record(consume),
        ]

        let publicationCollector = LogCollector()
        let publicationTelemetry = SceneGraphExecutionTelemetry {
            publicationCollector.append($0)
        }
        let publicationA = try observation(
            identity: .init(layerID: 51, effectIndex: 0, descriptorID: "publication"),
            transactionIdentity: "shared-transaction",
            frame: 1,
            publicationIdentity: "publication-a"
        )
        let publicationB = try observation(
            identity: .init(layerID: 51, effectIndex: 0, descriptorID: "publication"),
            transactionIdentity: "shared-transaction",
            frame: 1,
            publicationIdentity: "publication-b"
        )
        let publicationResults = [
            publicationTelemetry.record(publicationA),
            publicationTelemetry.record(publicationB),
            publicationTelemetry.record(publicationB),
        ]

        let signatureCollector = LogCollector()
        let signatureTelemetry = SceneGraphExecutionTelemetry {
            signatureCollector.append($0)
        }
        let mappingSubject = SceneGraphExecutionEffectIdentity(
            layerID: 52, effectIndex: 0, descriptorID: "mapping-drift"
        )
        let mappingBase = try observation(
            identity: mappingSubject,
            transactionIdentity: "mapping-transaction",
            frame: 1,
            publicationIdentity: "mapping-publication"
        )
        let mappingDrift = try observation(
            identity: mappingSubject,
            transactionIdentity: "mapping-transaction",
            frame: 1,
            mappingBefore: mappingAfter,
            mappingAfter: mappingBefore,
            publicationIdentity: "mapping-publication",
            consumed: true
        )
        let allocationGenerationSubject = SceneGraphExecutionEffectIdentity(
            layerID: 53, effectIndex: 0,
            descriptorID: "allocation-generation-drift"
        )
        let allocationGenerationBase = try observation(
            identity: allocationGenerationSubject,
            transactionIdentity: "allocation-generation-transaction",
            frame: 1,
            publicationIdentity: "allocation-generation-publication"
        )
        let allocationGenerationDrift = try observation(
            identity: allocationGenerationSubject,
            transactionIdentity: "allocation-generation-transaction",
            frame: 1,
            allocationGeneration: 2,
            publicationIdentity: "allocation-generation-publication",
            consumed: true
        )
        let mappingGenerationSubject = SceneGraphExecutionEffectIdentity(
            layerID: 54, effectIndex: 0,
            descriptorID: "mapping-generation-drift"
        )
        let mappingGenerationBase = try observation(
            identity: mappingGenerationSubject,
            transactionIdentity: "mapping-generation-transaction",
            frame: 1,
            publicationIdentity: "mapping-generation-publication"
        )
        let mappingGenerationDrift = try observation(
            identity: mappingGenerationSubject,
            transactionIdentity: "mapping-generation-transaction",
            frame: 1,
            mappingGeneration: 2,
            publicationIdentity: "mapping-generation-publication",
            consumed: true
        )
        let signatureResults = [
            signatureTelemetry.record(mappingBase),
            signatureTelemetry.record(mappingDrift),
            signatureTelemetry.record(mappingDrift),
            signatureTelemetry.record(allocationGenerationBase),
            signatureTelemetry.record(allocationGenerationDrift),
            signatureTelemetry.record(allocationGenerationDrift),
            signatureTelemetry.record(mappingGenerationBase),
            signatureTelemetry.record(mappingGenerationDrift),
            signatureTelemetry.record(mappingGenerationDrift),
        ]

        let concurrentCollector = LogCollector()
        let concurrentTelemetry = SceneGraphExecutionTelemetry {
            concurrentCollector.append($0)
        }
        let concurrent = try observation(
            identity: .init(layerID: 60, effectIndex: 0, descriptorID: "concurrent"),
            transactionIdentity: "concurrent-tx",
            frame: 1
        )
        DispatchQueue.concurrentPerform(iterations: 128) { _ in
            concurrentTelemetry.record(concurrent)
        }

        let boundedCollector = LogCollector()
        let boundedTelemetry = SceneGraphExecutionTelemetry(
            maximumTrackedSubjects: 1,
            logSink: { boundedCollector.append($0) }
        )
        let boundedFirst = try observation(
            identity: .init(layerID: 70, effectIndex: 0, descriptorID: "first"),
            transactionIdentity: "bounded-first",
            frame: 1
        )
        let boundedSecond = try observation(
            identity: .init(layerID: 71, effectIndex: 0, descriptorID: "second"),
            transactionIdentity: "bounded-second",
            frame: 1
        )
        let boundedResults = [
            boundedTelemetry.record(boundedFirst),
            boundedTelemetry.record(boundedSecond),
            boundedTelemetry.record(boundedSecond),
        ]

        let transactionCapacityCollector = LogCollector()
        let transactionCapacityTelemetry = SceneGraphExecutionTelemetry {
            transactionCapacityCollector.append($0)
        }
        let transactionCapacityIdentity = SceneGraphExecutionEffectIdentity(
            layerID: 72,
            effectIndex: 0,
            descriptorID: "transaction-capacity"
        )
        var transactionCapacityResults: [Bool] = []
        for frame in 1...66 {
            let value = try observation(
                identity: transactionCapacityIdentity,
                transactionIdentity: "capacity-\(frame)",
                frame: UInt64(frame)
            )
            transactionCapacityResults.append(
                transactionCapacityTelemetry.record(value)
            )
        }

        let copyNode = commandNode(kind: .copy)
        let copyCounts = SceneGraphExecutionNodeCounts(
            authored: 1, material: 0, copy: 1,
            swap: 0, compose: 0, rejected: 0
        )
        let swapNode = commandNode(kind: .swap)
        let swapCounts = SceneGraphExecutionNodeCounts(
            authored: 1, material: 0, copy: 0,
            swap: 1, compose: 0, rejected: 0
        )
        let rejectedSwap = commandNode(
            kind: .swap,
            disposition: .rejected(reasonCode: "command rejected")
        )
        let rejectedSwapCounts = SceneGraphExecutionNodeCounts(
            authored: 1, material: 0, copy: 0,
            swap: 0, compose: 0, rejected: 1
        )
        let rejectedSwapValid = try observation(
            frame: 80,
            customNodes: [rejectedSwap],
            counts: rejectedSwapCounts,
            mappingBefore: mappingBefore,
            mappingAfter: mappingBefore,
            composeSlotBefore: .none,
            composeSlotAfter: .none,
            publishOutput: false,
            outcome: .failed(reasonCode: "command rejected"),
            gpu: nil
        )
        let shiftedIndices = [5, 6, 7, 8]
        let shifted = try observation(
            frame: 81,
            customNodes: reindexedNodes(shiftedIndices),
            authoredNodeIndices: shiftedIndices
        )
        let sparseIndices = [5, 7, 9, 11]
        let sparse = try observation(
            frame: 82,
            customNodes: reindexedNodes(sparseIndices),
            authoredNodeIndices: sparseIndices
        )

        let conservationError = errorCode {
            _ = try observation(
                frame: 1,
                counts: .init(
                    authored: 5, material: 2, copy: 1,
                    swap: 1, compose: 1, rejected: 0
                )
            )
        }
        let authorityMismatchError = errorCode {
            _ = try observation(
                frame: 1,
                authoredNodeIndices: [0, 1, 4, 5]
            )
        }
        let descendingAuthorityError = errorCode {
            let descendingIndices = [1, 0, 2, 3]
            _ = try observation(
                frame: 1,
                customNodes: reindexedNodes(descendingIndices),
                authoredNodeIndices: descendingIndices
            )
        }
        let ordinalError = errorCode {
            var invalid = nodes()
            invalid[2] = .init(
                nodeIndex: 2,
                kind: .swap,
                materialOrdinal: nil,
                commandOrdinal: 2,
                commandSource: "history-a",
                commandTarget: "history-b",
                advancesComposePair: false,
                disposition: .executed
            )
            _ = try observation(frame: 1, customNodes: invalid)
        }
        var prunedOrdinalNodes = nodes()
        prunedOrdinalNodes[0] = .init(
            nodeIndex: 0, kind: .material,
            materialOrdinal: 1, commandOrdinal: nil,
            commandSource: nil, commandTarget: nil,
            advancesComposePair: false, disposition: .executed
        )
        prunedOrdinalNodes[3] = .init(
            nodeIndex: 3, kind: .material,
            materialOrdinal: 3, commandOrdinal: nil,
            commandSource: nil, commandTarget: nil,
            advancesComposePair: true, disposition: .executed
        )
        let prunedOrdinalObservation = try observation(
            frame: 2,
            customNodes: prunedOrdinalNodes
        )
        let descendingMaterialOrdinalError = errorCode {
            var invalid = prunedOrdinalNodes
            invalid[3] = .init(
                nodeIndex: 3, kind: .material,
                materialOrdinal: 1, commandOrdinal: nil,
                commandSource: nil, commandTarget: nil,
                advancesComposePair: true, disposition: .executed
            )
            _ = try observation(frame: 3, customNodes: invalid)
        }
        let negativeMaterialOrdinalError = errorCode {
            var invalid = prunedOrdinalNodes
            invalid[0] = .init(
                nodeIndex: 0, kind: .material,
                materialOrdinal: -1, commandOrdinal: nil,
                commandSource: nil, commandTarget: nil,
                advancesComposePair: false, disposition: .executed
            )
            _ = try observation(frame: 4, customNodes: invalid)
        }
        let composeTransitionError = errorCode {
            _ = try observation(
                frame: 1,
                composeSlotBefore: .primary,
                composeSlotAfter: .secondary
            )
        }
        let copyAdvanceError = errorCode {
            _ = try observation(
                frame: 1,
                customNodes: [copyNode],
                counts: copyCounts,
                mappingBefore: mappingBefore,
                mappingAfter: mappingAfter,
                composeSlotBefore: .primary,
                composeSlotAfter: .secondary
            )
        }
        let swapNoAdvanceError = errorCode {
            _ = try observation(
                frame: 1,
                customNodes: [swapNode],
                counts: swapCounts,
                mappingBefore: mappingBefore,
                mappingAfter: mappingBefore,
                composeSlotBefore: .primary,
                composeSlotAfter: .secondary
            )
        }
        let rejectedSwapAdvanceError = errorCode {
            _ = try observation(
                frame: 1,
                customNodes: [rejectedSwap],
                counts: rejectedSwapCounts,
                mappingBefore: mappingBefore,
                mappingAfter: mappingAfter,
                composeSlotBefore: .none,
                composeSlotAfter: .none,
                publishOutput: false,
                outcome: .failed(reasonCode: "command rejected"),
                gpu: nil
            )
        }
        let physicalAliasError = errorCode {
            let alias = [
                SceneGraphExecutionLogicalBinding(
                    logicalIdentity: "history-a", physicalIdentity: "texture-0"
                ),
                SceneGraphExecutionLogicalBinding(
                    logicalIdentity: "history-b", physicalIdentity: "texture-0"
                ),
            ]
            _ = try observation(
                frame: 1,
                mappingBefore: alias,
                mappingAfter: alias
            )
        }
        let emptyMappingError = errorCode {
            let zeroFBONode = SceneGraphExecutionNodeObservation(
                nodeIndex: 0,
                kind: .material,
                materialOrdinal: 0,
                commandOrdinal: nil,
                commandSource: nil,
                commandTarget: nil,
                advancesComposePair: false,
                disposition: .executed
            )
            _ = try observation(
                frame: 1,
                customNodes: [zeroFBONode],
                counts: .init(
                    authored: 1, material: 1, copy: 0,
                    swap: 0, compose: 0, rejected: 0
                ),
                mappingBefore: [],
                mappingAfter: [],
                composeSlotBefore: .primary,
                composeSlotAfter: .secondary
            )
        }
        let sameCommandIdentityError = errorCode {
            let invalid = commandNode(
                kind: .copy,
                source: "history-a",
                target: "history-a"
            )
            _ = try observation(
                frame: 1,
                customNodes: [invalid],
                counts: copyCounts,
                composeSlotBefore: .primary,
                composeSlotAfter: .secondary
            )
        }
        let finalOutputMappingError = errorCode {
            _ = try observation(frame: 1, outputIdentity: "missing-output")
        }
        let wrongPhysicalOutputError = errorCode {
            _ = try observation(frame: 1, physicalIdentity: "texture-0")
        }
        let publicationGenerationError = errorCode {
            _ = try observation(frame: 1, effectGeneration: 0)
        }
        let successGPUFailedError = errorCode {
            _ = try observation(frame: 1, gpu: .failed)
        }
        let successMissingGPUError = errorCode {
            _ = try observation(frame: 1, gpu: nil)
        }
        let failureGPUCompletedError = errorCode {
            _ = try observation(
                frame: 1,
                customNodes: [rejectedSwap],
                counts: rejectedSwapCounts,
                mappingAfter: mappingBefore,
                composeSlotBefore: .none,
                composeSlotAfter: .none,
                publishOutput: false,
                outcome: .failed(reasonCode: "failed"),
                gpu: .completed
            )
        }
        let partialOutputError = errorCode {
            _ = try rejectedObservation(publishOutput: true)
        }
        let whitespaceErrors = [
            errorCode { _ = try observation(
                identity: .init(layerID: 1, effectIndex: 1, descriptorID: " \n"),
                frame: 1
            ) },
            errorCode { _ = try observation(graphIdentity: "  ", frame: 1) },
            errorCode { _ = try observation(transactionIdentity: "\t", frame: 1) },
            errorCode { _ = try observation(
                frame: 1, physicalIdentity: " \n"
            ) },
            errorCode { _ = try observation(
                frame: 1, publicationIdentity: " \n"
            ) },
            errorCode { _ = try rejectedObservation(reason: " \t") },
            errorCode { _ = try observation(
                frame: 1,
                customNodes: gpuFailureNodes,
                counts: .init(
                    authored: 4, material: 0, copy: 0,
                    swap: 0, compose: 0, rejected: 4
                ),
                mappingAfter: mappingBefore,
                composeSlotBefore: .none,
                composeSlotAfter: .none,
                publishOutput: false,
                outcome: .failed(reasonCode: " \n"),
                gpu: nil
            ) },
            errorCode { _ = try observation(
                frame: 1,
                mappingBefore: [.init(
                    logicalIdentity: "history-a", physicalIdentity: "  "
                )]
            ) },
            errorCode {
                let invalid = commandNode(kind: .copy, source: " \t")
                _ = try observation(
                    frame: 1,
                    customNodes: [invalid],
                    counts: copyCounts,
                    composeSlotBefore: .none,
                    composeSlotAfter: .none
                )
            },
        ]

        let hashA = try observation(frame: 90)
        let hashB = try observation(
            frame: 99,
            effectGeneration: 7,
            allocationGeneration: 8,
            mappingGeneration: 9,
            mappingBefore: Array(mappingBefore.reversed()),
            mappingAfter: Array(mappingAfter.reversed())
        )
        let describedMapping = try observation(
            frame: 100,
            mappingBefore: described(mappingBefore),
            mappingAfter: described(mappingAfter)
        )
        let descriptorTransitionError = errorCode {
            _ = try observation(
                frame: 101,
                mappingBefore: described(mappingBefore),
                mappingAfter: described(mappingAfter, width: 2, height: 2)
            )
        }
        let partialDescriptorError = errorCode {
            var partialBefore = described(mappingBefore)
            var partialAfter = described(mappingAfter)
            partialBefore[0] = mappingBefore[0]
            partialAfter[0] = mappingAfter[0]
            _ = try observation(
                frame: 102,
                mappingBefore: partialBefore,
                mappingAfter: partialAfter
            )
        }
        let copyOnWriteWithoutCopiesError = errorCode {
            _ = try observation(
                frame: 103,
                allocationGeneration: 2,
                mappingGeneration: 2,
                reset: .historyCopyOnWrite
            )
        }
        let copyAndDiscardError = errorCode {
            _ = try observation(
                frame: 104,
                allocationGeneration: 2,
                mappingGeneration: 2,
                historyRehydrateCopyCount: 2,
                historyContentDiscarded: true,
                reset: .allocationReprepare
            )
        }

        let payload: [String: Any] = [
            "logs": collector.snapshot(),
            "lifecycleResults": lifecycleResults,
            "failureLogs": failureCollector.snapshot(),
            "failureResults": failureResults,
            "programLogs": programCollector.snapshot(),
            "programResults": programResults,
            "consumeLogs": consumeCollector.snapshot(),
            "consumeResults": consumeResults,
            "publicationLogs": publicationCollector.snapshot(),
            "publicationResults": publicationResults,
            "signatureLogs": signatureCollector.snapshot(),
            "signatureResults": signatureResults,
            "concurrentLogs": concurrentCollector.snapshot(),
            "boundedLogs": boundedCollector.snapshot(),
            "boundedResults": boundedResults,
            "transactionCapacityLogs": transactionCapacityCollector.snapshot(),
            "transactionCapacityResults": transactionCapacityResults,
            "rejectedSwapHashBefore": rejectedSwapValid.logicalMappingBeforeSHA256,
            "rejectedSwapHashAfter": rejectedSwapValid.logicalMappingAfterSHA256,
            "conservationError": conservationError,
            "shiftedIndices": shifted.authoredNodeIndices,
            "sparseIndices": sparse.authoredNodeIndices,
            "authorityMismatchError": authorityMismatchError,
            "descendingAuthorityError": descendingAuthorityError,
            "ordinalError": ordinalError,
            "prunedMaterialOrdinalCount":
                prunedOrdinalObservation.materialOrdinalCount,
            "descendingMaterialOrdinalError": descendingMaterialOrdinalError,
            "negativeMaterialOrdinalError": negativeMaterialOrdinalError,
            "composeTransitionError": composeTransitionError,
            "copyAdvanceError": copyAdvanceError,
            "swapNoAdvanceError": swapNoAdvanceError,
            "rejectedSwapAdvanceError": rejectedSwapAdvanceError,
            "physicalAliasError": physicalAliasError,
            "emptyMappingError": emptyMappingError,
            "sameCommandIdentityError": sameCommandIdentityError,
            "finalOutputMappingError": finalOutputMappingError,
            "wrongPhysicalOutputError": wrongPhysicalOutputError,
            "publicationGenerationError": publicationGenerationError,
            "successGPUFailedError": successGPUFailedError,
            "successMissingGPUError": successMissingGPUError,
            "failureGPUCompletedError": failureGPUCompletedError,
            "partialOutputError": partialOutputError,
            "whitespaceErrors": whitespaceErrors,
            "nodeHashA": hashA.nodeSequenceSHA256,
            "nodeHashB": hashB.nodeSequenceSHA256,
            "mappingBeforeHashA": hashA.logicalMappingBeforeSHA256,
            "mappingBeforeHashB": hashB.logicalMappingBeforeSHA256,
            "mappingAfterHashA": hashA.logicalMappingAfterSHA256,
            "mappingAfterHashB": hashB.logicalMappingAfterSHA256,
            "targetDescriptorsHash": describedMapping.targetDescriptorsSHA256 ?? "",
            "targetDescriptorCounts": describedMapping.targetDescriptorCounts ?? "",
            "descriptorTransitionError": descriptorTransitionError,
            "partialDescriptorError": partialDescriptorError,
            "copyOnWriteWithoutCopiesError": copyOnWriteWithoutCopiesError,
            "copyAndDiscardError": copyAndDiscardError,
            "canonicalLine": hashA.canonicalLine,
            "encodedToken": SceneGraphExecutionLogToken.encode("A %=中\n"),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneGraphExecutionTelemetryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-graph-execution-telemetry-"
        )
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = directory / "scene-graph-execution-telemetry-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(directory / "swift-cache")
        compilation = subprocess.run(
            [
                "swiftc",
                "-swift-version", "6",
                "-default-isolation", "MainActor",
                "-strict-concurrency=complete",
                "-warnings-as-errors",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness), "-o", str(binary),
            ],
            capture_output=True,
            text=True,
            env=environment,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        cls.logs = cls.result["logs"]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_node_and_ordinal_conservation_are_exact(self) -> None:
        first = self._line(
            self.logs,
            frame="10",
            trigger="first-frame+reset+first-success+gpu-completed",
        )
        self.assertEqual(self._field(first, "authoredNodes"), "4")
        self.assertEqual(self._field(first, "materialNodes"), "2")
        self.assertEqual(self._field(first, "copyNodes"), "1")
        self.assertEqual(self._field(first, "swapNodes"), "1")
        self.assertEqual(self._field(first, "composeNodes"), "1")
        self.assertEqual(self._field(first, "rejectedNodes"), "0")
        self.assertEqual(self._field(first, "materialOrdinals"), "2")
        self.assertEqual(self._field(first, "commandOrdinals"), "2")
        self.assertEqual(self._field(first, "composeSlotBefore"), "primary")
        self.assertEqual(self._field(first, "composeSlotAfter"), "primary")
        self.assertEqual(self.result["conservationError"], "invalidNodeConservation")
        self.assertEqual(self.result["ordinalError"], "invalidOrdinals")
        self.assertEqual(self.result["prunedMaterialOrdinalCount"], 2)
        self.assertEqual(
            self.result["descendingMaterialOrdinalError"],
            "invalidOrdinals",
        )
        self.assertEqual(
            self.result["negativeMaterialOrdinalError"],
            "invalidOrdinals",
        )

    def test_node_indices_exactly_match_authoritative_stage_sequence(self) -> None:
        self.assertEqual(self.result["shiftedIndices"], [5, 6, 7, 8])
        self.assertEqual(self.result["sparseIndices"], [5, 7, 9, 11])
        self.assertEqual(self.result["authorityMismatchError"], "invalidNodeOrder")
        self.assertEqual(self.result["descendingAuthorityError"], "invalidNodeOrder")

    def test_copy_swap_and_rejected_command_mapping_replay_is_exact(self) -> None:
        self.assertEqual(self.result["copyAdvanceError"], "invalidLogicalMapping")
        self.assertEqual(self.result["swapNoAdvanceError"], "invalidLogicalMapping")
        self.assertEqual(
            self.result["rejectedSwapAdvanceError"],
            "invalidLogicalMapping",
        )
        self.assertEqual(
            self.result["rejectedSwapHashBefore"],
            self.result["rejectedSwapHashAfter"],
        )

    def test_zero_fbo_mapping_is_valid_but_physical_alias_is_not(self) -> None:
        self.assertEqual(self.result["emptyMappingError"], "none")
        self.assertEqual(self.result["physicalAliasError"], "invalidLogicalMapping")
        self.assertEqual(
            self.result["sameCommandIdentityError"],
            "invalidCommandIdentity",
        )

    def test_pair_output_is_independent_from_fbo_mapping_and_has_generation(self) -> None:
        self.assertEqual(self.result["finalOutputMappingError"], "none")
        self.assertEqual(self.result["wrongPhysicalOutputError"], "none")
        self.assertEqual(self.result["publicationGenerationError"], "invalidFinalOutput")

    def test_gpu_completion_and_outcome_are_bidirectionally_consistent(self) -> None:
        self.assertEqual(self.result["successGPUFailedError"], "invalidOutcome")
        self.assertEqual(self.result["successMissingGPUError"], "invalidOutcome")
        self.assertEqual(self.result["failureGPUCompletedError"], "invalidOutcome")
        completed = [
            line
            for line in self.logs
            if self._field(line, "gpuCompletion") == "completed"
        ]
        failed = self._line(self.logs, gpuCompletion="failed")
        self.assertTrue(completed)
        self.assertTrue(all(self._field(line, "outcome") == "succeeded" for line in completed))
        self.assertEqual(self._field(failed, "outcome"), "failed")
        self.assertEqual(self._field(failed, "finalOutput"), "-")
        self.assertEqual(self._field(failed, "publication"), "-")
        self.assertEqual(self._field(failed, "compositorConsumed"), "false")
        self.assertEqual(self._field(failed, "rejectedNodes"), "4")
        self.assertEqual(self._field(failed, "materialNodes"), "0")
        self.assertEqual(self._field(failed, "copyNodes"), "0")
        self.assertEqual(self._field(failed, "swapNodes"), "0")
        self.assertEqual(self._field(failed, "composeNodes"), "0")
        self.assertEqual(
            self._field(failed, "mappingBeforeSHA256"),
            self._field(failed, "mappingAfterSHA256"),
        )
        self.assertEqual(self._field(failed, "composeSlotBefore"), "none")
        self.assertEqual(self._field(failed, "composeSlotAfter"), "none")

    def test_program_generation_subject_key_rebuilds_first_and_sticky_evidence(self) -> None:
        reparsed = self._line(self.logs, frame="22")
        self.assertEqual(
            self._field(reparsed, "trigger"),
            "first-frame+reset+first-success+gpu-completed",
        )
        self.assertEqual(self.result["programResults"], [True, True])
        self.assertEqual(len(self.result["programLogs"]), 2)
        self.assertEqual(
            {self._field(line, "trigger") for line in self.result["programLogs"]},
            {"first-frame+first-success+gpu-completed"},
        )

    def test_first_and_next_active_frames_and_sticky_facts_are_bounded(self) -> None:
        self.assertEqual(
            self.result["lifecycleResults"],
            [
                True, False, True, False, True, False, False,
                True, False, True, False, False, True, False,
            ],
        )
        self.assertEqual(self._field(self._line(self.logs, trigger="next-frame"), "frame"), "12")
        generation_one = [line for line in self.logs if self._field(line, "effectGeneration") == "1"]
        self.assertEqual(
            sum("first-success" in self._field(line, "trigger") for line in generation_one),
            1,
        )
        self.assertEqual(
            sum("first-failure" in self._field(line, "trigger") for line in generation_one),
            1,
        )

    def test_failure_never_publishes_partial_output(self) -> None:
        self.assertEqual(self.result["failureResults"], [True, False])
        self.assertEqual(self.result["partialOutputError"], "invalidOutcome")
        failure = self._line(self.result["failureLogs"], outcome="failed")
        self.assertEqual(self._field(failure, "finalOutput"), "-")
        self.assertEqual(self._field(failure, "publication"), "-")
        self.assertEqual(self._field(failure, "publicationGeneration"), "-")
        self.assertEqual(self._field(failure, "compositorConsumed"), "false")
        self.assertEqual(self._field(failure, "gpuCompletion"), "-")

    def test_duplicate_transaction_consume_is_diagnosed_once(self) -> None:
        self.assertEqual(self.result["consumeResults"], [True, False, False])
        logs = self.result["consumeLogs"]
        self.assertEqual(len(logs), 2)
        normal = self._line(
            logs,
            trigger="first-frame+first-success+compositor-consume+gpu-completed",
        )
        diagnostic = self._line(logs, diagnostic="duplicate-compositor-consume")
        self.assertEqual(self._field(normal, "transaction"), "consume-transaction")
        self.assertEqual(self._field(diagnostic, "transaction"), "consume-transaction")

    def test_publication_identity_conflict_is_diagnosed_once(self) -> None:
        self.assertEqual(self.result["publicationResults"], [True, False, False])
        logs = self.result["publicationLogs"]
        self.assertEqual(len(logs), 2)
        self._line(logs, diagnostic="transaction-publication-conflict")

    def test_transaction_mapping_and_generation_drift_are_diagnosed_once(self) -> None:
        self.assertEqual(
            self.result["signatureResults"],
            [
                True, False, False,
                True, False, False,
                True, False, False,
            ],
        )
        diagnostics = [
            line for line in self.result["signatureLogs"]
            if " diagnostic=transaction-signature-conflict " in f" {line} "
        ]
        self.assertEqual(len(diagnostics), 3)
        self._line(diagnostics, descriptor="mapping-drift")
        self._line(diagnostics, descriptor="allocation-generation-drift")
        self._line(diagnostics, descriptor="mapping-generation-drift")

    def test_saturation_emits_one_bounded_diagnostic(self) -> None:
        self.assertEqual(self.result["boundedResults"], [True, False, False])
        logs = self.result["boundedLogs"]
        self.assertEqual(len(logs), 2)
        self._line(logs, diagnostic="subject-capacity-saturated")

    def test_transaction_history_rolls_without_normal_playback_diagnostic(self) -> None:
        results = self.result["transactionCapacityResults"]
        self.assertEqual(len(results), 66)
        self.assertEqual(sum(results), 2)
        logs = self.result["transactionCapacityLogs"]
        self.assertEqual(len(logs), 2)
        self.assertFalse(any(" diagnostic=" in f" {line} " for line in logs))

    def test_concurrent_duplicates_remain_bounded_without_order_claim(self) -> None:
        logs = self.result["concurrentLogs"]
        self.assertEqual(len(logs), 1)
        self.assertEqual(self._field(logs[0], "descriptor"), "concurrent")

    def test_all_identities_and_reasons_reject_whitespace_only(self) -> None:
        self.assertEqual(
            self.result["whitespaceErrors"],
            [
                "invalidIdentity",
                "invalidExecutionIdentity",
                "invalidExecutionIdentity",
                "invalidFinalOutput",
                "invalidFinalOutput",
                "invalidNodeDisposition",
                "invalidOutcome",
                "invalidLogicalMapping",
                "invalidCommandIdentity",
            ],
        )

    def test_node_and_mapping_hashes_are_stable(self) -> None:
        expected_nodes = hashlib.sha256("\n".join(self._node_lines()).encode()).hexdigest()
        before = hashlib.sha256("\n".join(sorted(self._mapping_before())).encode()).hexdigest()
        after = hashlib.sha256("\n".join(sorted(self._mapping_after())).encode()).hexdigest()
        self.assertEqual(self.result["nodeHashA"], expected_nodes)
        self.assertEqual(self.result["nodeHashB"], expected_nodes)
        self.assertEqual(self.result["mappingBeforeHashA"], before)
        self.assertEqual(self.result["mappingBeforeHashB"], before)
        self.assertEqual(self.result["mappingAfterHashA"], after)
        self.assertEqual(self.result["mappingAfterHashB"], after)
        self.assertTrue(self.result["canonicalLine"].startswith(
            "graph-execution|runtime=runtime-fixture|frame=90|"
        ))

    def test_target_descriptors_are_complete_stable_and_transition_safe(self) -> None:
        lines = sorted(
            f"logical={logical}|extent=4x2|format=rgbaBackbuffer"
            for logical in (
                "history-a",
                "history-b",
                "effect%20output/%25%20%E4%B8%AD",
            )
        )
        expected = hashlib.sha256("\n".join(lines).encode()).hexdigest()
        self.assertEqual(self.result["targetDescriptorsHash"], expected)
        self.assertEqual(
            self.result["targetDescriptorCounts"],
            "4x2/rgbaBackbuffer:3",
        )
        self.assertEqual(
            self.result["descriptorTransitionError"],
            "invalidTargetDescriptors",
        )
        self.assertEqual(
            self.result["partialDescriptorError"],
            "invalidTargetDescriptors",
        )

    def test_lifecycle_fields_reject_inconsistent_copy_on_write(self) -> None:
        self.assertEqual(
            self.result["copyOnWriteWithoutCopiesError"],
            "invalidLifecycle",
        )
        self.assertEqual(self.result["copyAndDiscardError"], "invalidLifecycle")
        resized = self._line(self.logs, frame="20")
        self.assertEqual(self._field(resized, "inputWidth"), "962")
        self.assertEqual(self._field(resized, "inputHeight"), "542")
        self.assertEqual(self._field(resized, "historyRehydrateCopyCount"), "0")
        self.assertEqual(self._field(resized, "historyContentDiscarded"), "false")

    def test_log_schema_tokens_and_transaction_publication_are_stable(self) -> None:
        self.assertEqual(self.result["encodedToken"], "A%20%25%3D%E4%B8%AD%0A")
        first = self._line(self.logs, frame="10")
        self.assertRegex(
            first,
            re.compile(
                r"^MWX DEBUG SCENE: schema=1 axis=graph-execution "
                r"runtime=runtime-fixture frame=10 "
                r"trigger=first-frame\+reset\+first-success\+gpu-completed "
                r"layer=7 effect=2 descriptor=Graph%20A%25%3D%E4%B8%AD "
            ),
        )
        self.assertEqual(self._field(first, "transaction"), "tx-1-10")
        self.assertEqual(self._field(first, "physicalIdentity"), "texture-output")
        self.assertEqual(self._field(first, "publication"), "pub-1-10")

    @staticmethod
    def _field(line: str, name: str) -> str:
        match = re.search(rf"(?:^| ){re.escape(name)}=([^ ]+)", line)
        if match is None:
            raise AssertionError(f"missing {name}= in {line!r}")
        return match.group(1)

    @classmethod
    def _line(cls, lines: list[str], **fields: str) -> str:
        matches = []
        for line in lines:
            try:
                is_match = all(
                    cls._field(line, name) == value
                    for name, value in fields.items()
                )
            except AssertionError:
                continue
            if is_match:
                matches.append(line)
        if len(matches) != 1:
            raise AssertionError(f"expected one line for {fields!r}, got {matches!r}")
        return matches[0]

    @staticmethod
    def _node_lines() -> list[str]:
        return [
            "node=0|kind=material|materialOrdinal=0|commandOrdinal=-|"
            "commandSource=-|commandTarget=-|compose=false|disposition=executed|reason=-",
            "node=1|kind=copy|materialOrdinal=-|commandOrdinal=0|"
            "commandSource=history-a|commandTarget=history-b|compose=false|"
            "disposition=executed|reason=-",
            "node=2|kind=swap|materialOrdinal=-|commandOrdinal=1|"
            "commandSource=history-a|commandTarget=history-b|compose=false|"
            "disposition=executed|reason=-",
            "node=3|kind=material|materialOrdinal=1|commandOrdinal=-|"
            "commandSource=-|commandTarget=-|compose=true|disposition=executed|reason=-",
        ]

    @staticmethod
    def _mapping_before() -> list[str]:
        return [
            "logical=history-a|physical=texture-0",
            "logical=history-b|physical=texture-1",
            "logical=effect%20output/%25%20%E4%B8%AD|physical=texture-output",
        ]

    @staticmethod
    def _mapping_after() -> list[str]:
        return [
            "logical=history-a|physical=texture-1",
            "logical=history-b|physical=texture-0",
            "logical=effect%20output/%25%20%E4%B8%AD|physical=texture-output",
        ]


if __name__ == "__main__":
    unittest.main()
