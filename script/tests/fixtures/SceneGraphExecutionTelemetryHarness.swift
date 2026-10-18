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
        fullFramePairStorage: SceneGraphExecutionFullFramePairStorage = .owned,
        fullFramePairGeneration: UInt64? = nil,
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
        let successful = if case .succeeded = outcome { true } else { false }
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
            fullFramePairStorage: successful ? fullFramePairStorage : nil,
            fullFramePairGeneration: successful
                ? (fullFramePairGeneration ?? allocationGeneration) : nil,
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
        let rejectedPassthroughNodes = [0, 1].map { index in
            SceneGraphExecutionNodeObservation(
                nodeIndex: index,
                kind: .material,
                materialOrdinal: index,
                commandOrdinal: nil,
                commandSource: nil,
                commandTarget: nil,
                advancesComposePair: false,
                disposition: .rejected(reasonCode: "visual unavailable")
            )
        }
        let rejectedPassthroughSameSlotError = errorCode {
            _ = try observation(
                programIdentity:
                    "visual-failure-passthrough:visual-unavailable",
                frame: 1,
                customNodes: rejectedPassthroughNodes,
                counts: .init(
                    authored: 2, material: 0, copy: 0,
                    swap: 0, compose: 0, rejected: 2
                ),
                mappingAfter: mappingBefore,
                composeSlotBefore: .primary,
                composeSlotAfter: .primary
            )
        }
        let ordinaryRejectedSameSlotError = errorCode {
            _ = try observation(
                frame: 1,
                customNodes: rejectedPassthroughNodes,
                counts: .init(
                    authored: 2, material: 0, copy: 0,
                    swap: 0, compose: 0, rejected: 2
                ),
                mappingAfter: mappingBefore,
                composeSlotBefore: .primary,
                composeSlotAfter: .primary
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
            "rejectedPassthroughSameSlotError":
                rejectedPassthroughSameSlotError,
            "ordinaryRejectedSameSlotError": ordinaryRejectedSameSlotError,
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
