import Foundation

nonisolated final class SceneGraphExecutionTelemetry: @unchecked Sendable {
    typealias LogSink = @Sendable (String) -> Void

    private static let maximumTransactionsPerSubject = 64

    private enum Trigger: String {
        case firstFrame = "first-frame", nextFrame = "next-frame", reset
        case firstSuccess = "first-success", firstFailure = "first-failure"
        case compositorConsume = "compositor-consume"
        case gpuCompleted = "gpu-completed", gpuFailed = "gpu-failed"

        var order: Int {
            switch self {
            case .firstFrame: 0
            case .nextFrame: 1
            case .reset: 2
            case .firstSuccess: 3
            case .firstFailure: 4
            case .compositorConsume: 5
            case .gpuCompleted: 6
            case .gpuFailed: 7
            }
        }
    }

    private enum Reduction {
        case emit([Trigger])
        case diagnostic(String)
        case none
    }

    private struct SubjectKey: Hashable {
        let effect: SceneGraphExecutionEffectIdentity
        let graphIdentity: String
        let programIdentity: String
        let programSequenceIdentity: String
        let effectGeneration: UInt64
        init(_ observation: SceneGraphExecutionObservation) {
            effect = observation.identity
            graphIdentity = observation.graphIdentity
            programIdentity = observation.programIdentity
            programSequenceIdentity = observation.programSequenceIdentity
            effectGeneration = observation.effectGeneration
        }
    }

    private struct ResetSignature: Equatable {
        let reason: SceneGraphExecutionResetReason
        let allocationGeneration: UInt64
        let mappingGeneration: UInt64
    }

    private struct TransactionSignature: Equatable {
        let frameIndex, allocationGeneration, mappingGeneration: UInt64
        let nodeSequence, mappingBefore, mappingAfter: String
        let targetDescriptors: String?
        let composeBefore, composeAfter: SceneGraphExecutionComposeSlot
        let history: SceneGraphExecutionHistoryState
        let reset: SceneGraphExecutionResetReason?
        let outcome: SceneGraphExecutionOutcome
        let publication: SceneGraphExecutionFinalOutputPublication?
        let gpuCompletion: SceneGraphExecutionGPUCompletionStatus?
        init(_ value: SceneGraphExecutionObservation) {
            frameIndex = value.frameIndex
            allocationGeneration = value.allocationGeneration
            mappingGeneration = value.mappingGeneration
            nodeSequence = value.nodeSequenceSHA256
            mappingBefore = value.logicalMappingBeforeSHA256
            mappingAfter = value.logicalMappingAfterSHA256
            targetDescriptors = value.targetDescriptorsSHA256
            composeBefore = value.composeSlotBefore
            composeAfter = value.composeSlotAfter
            history = value.historyState
            reset = value.resetReason
            outcome = value.outcome
            publication = value.finalOutput
            gpuCompletion = value.gpuCompletionStatus
        }
    }

    private struct TransactionRecord {
        let identity: String
        let signature: TransactionSignature
        var consumed: Bool
        var duplicateConsumeDiagnosed = false
        var conflictDiagnosed = false
    }

    private struct SubjectState {
        let firstFrame: UInt64
        var nextFrameRecorded = false
        var resetIsActive = false
        var lastReset: ResetSignature?
        var recordedSuccess = false
        var recordedFailure = false
        var recordedCompositorConsume = false
        var gpuStatuses: Set<SceneGraphExecutionGPUCompletionStatus> = []
        var transactions: [TransactionRecord] = []
    }

    private let lock = NSLock()
    private let maximumTrackedSubjects: Int
    private let logSink: LogSink
    private var states: [SubjectKey: SubjectState] = [:]
    private var saturationDiagnosed = false
    init(
        maximumTrackedSubjects: Int = 4_096,
        logSink: @escaping LogSink = { NSLog("%@", $0) }
    ) {
        precondition(maximumTrackedSubjects > 0)
        self.maximumTrackedSubjects = maximumTrackedSubjects
        self.logSink = logSink
    }

    @discardableResult
    func record(_ observation: SceneGraphExecutionObservation) -> Bool {
        let reduction = withLock { reduce(observation) }
        switch reduction {
        case let .emit(triggers):
            emit(observation, triggers: triggers)
            return true
        case let .diagnostic(reason):
            emitDiagnostic(observation, reason: reason)
            return false
        case .none:
            return false
        }
    }

    private func reduce(_ observation: SceneGraphExecutionObservation) -> Reduction {
        let key = SubjectKey(observation)
        var triggers: [Trigger] = []
        var state: SubjectState
        let isNewSubject: Bool
        if let current = states[key] {
            state = current
            isNewSubject = false
        } else {
            guard states.count < maximumTrackedSubjects else {
                guard !saturationDiagnosed else { return .none }
                saturationDiagnosed = true
                return .diagnostic("subject-capacity-saturated")
            }
            state = SubjectState(firstFrame: observation.frameIndex)
            isNewSubject = true
            triggers.append(.firstFrame)
        }

        if let diagnostic = reduceTransaction(
            observation,
            state: &state,
            triggers: &triggers
        ) {
            states[key] = state
            return diagnostic
        }
        if !isNewSubject,
           !state.nextFrameRecorded,
           observation.frameIndex > state.firstFrame {
            state.nextFrameRecorded = true
            triggers.append(.nextFrame)
        }
        reduceReset(observation, state: &state, triggers: &triggers)
        reduceStickyFacts(observation, state: &state, triggers: &triggers)
        states[key] = state
        triggers.sort { $0.order < $1.order }
        return triggers.isEmpty ? .none : .emit(triggers)
    }

    private func reduceTransaction(
        _ observation: SceneGraphExecutionObservation,
        state: inout SubjectState,
        triggers: inout [Trigger]
    ) -> Reduction? {
        let signature = TransactionSignature(observation)
        let index: Int
        if let existing = state.transactions.firstIndex(where: {
            $0.identity == observation.transactionIdentity
        }) {
            index = existing
            let transaction = state.transactions[index]
            if transaction.signature != signature {
                guard !transaction.conflictDiagnosed else { return Reduction.none }
                state.transactions[index].conflictDiagnosed = true
                return .diagnostic(
                    transaction.signature.publication != signature.publication
                        ? "transaction-publication-conflict"
                        : "transaction-signature-conflict"
                )
            }
        } else {
            if state.transactions.count == Self.maximumTransactionsPerSubject {
                // Transactions are terminal observations with monotonically
                // increasing runtime identities. Retain a bounded recent window
                // for duplicate/conflict detection without treating normal frame
                // progress as saturation or growing telemetry state forever.
                state.transactions.removeFirst()
            }
            state.transactions.append(.init(
                identity: observation.transactionIdentity,
                signature: signature,
                consumed: false
            ))
            index = state.transactions.index(before: state.transactions.endIndex)
        }

        guard observation.compositorConsumed else { return nil }
        if state.transactions[index].consumed {
            guard !state.transactions[index].duplicateConsumeDiagnosed else {
                return Reduction.none
            }
            state.transactions[index].duplicateConsumeDiagnosed = true
            return .diagnostic("duplicate-compositor-consume")
        }
        state.transactions[index].consumed = true
        if !state.recordedCompositorConsume {
            state.recordedCompositorConsume = true
            triggers.append(.compositorConsume)
        }
        return nil
    }

    private func reduceReset(
        _ observation: SceneGraphExecutionObservation,
        state: inout SubjectState,
        triggers: inout [Trigger]
    ) {
        guard let reason = observation.resetReason else {
            state.resetIsActive = false
            return
        }
        let signature = ResetSignature(
            reason: reason,
            allocationGeneration: observation.allocationGeneration,
            mappingGeneration: observation.mappingGeneration
        )
        if !state.resetIsActive || state.lastReset != signature {
            triggers.append(.reset)
        }
        state.resetIsActive = true
        state.lastReset = signature
    }

    private func reduceStickyFacts(
        _ observation: SceneGraphExecutionObservation,
        state: inout SubjectState,
        triggers: inout [Trigger]
    ) {
        switch observation.outcome {
        case .succeeded where !state.recordedSuccess:
            state.recordedSuccess = true
            triggers.append(.firstSuccess)
        case .failed where !state.recordedFailure:
            state.recordedFailure = true
            triggers.append(.firstFailure)
        default:
            break
        }
        if let status = observation.gpuCompletionStatus,
           state.gpuStatuses.insert(status).inserted {
            triggers.append(status == .completed ? .gpuCompleted : .gpuFailed)
        }
    }

    private func emit(
        _ observation: SceneGraphExecutionObservation,
        triggers: [Trigger]
    ) {
        var fields = observation.logFields
        fields.insert(
            "trigger=\(triggers.map(\.rawValue).joined(separator: "+"))",
            at: 1
        )
        logSink(
            "MWX DEBUG SCENE: schema=1 axis=graph-execution "
                + fields.joined(separator: " ")
        )
    }

    private func emitDiagnostic(
        _ observation: SceneGraphExecutionObservation,
        reason: String
    ) {
        var fields = observation.logFields
        fields.insert("diagnostic=\(reason)", at: 1)
        logSink(
            "MWX DEBUG SCENE: schema=1 axis=graph-execution "
                + fields.joined(separator: " ")
        )
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

nonisolated extension SceneGraphExecutionNodeDisposition {
    var details: (value: String, reason: String?) {
        switch self {
        case .executed: ("executed", nil)
        case let .rejected(reasonCode): ("rejected", reasonCode)
        }
    }
}

nonisolated extension SceneGraphExecutionOutcome {
    var details: (value: String, reason: String?) {
        switch self {
        case .succeeded: ("succeeded", nil)
        case let .failed(reasonCode): ("failed", reasonCode)
        }
    }
}

nonisolated extension SceneGraphExecutionNodeObservation {
    var canonicalLine: String {
        [
            "node=\(nodeIndex)",
            "kind=\(kind.rawValue)",
            "materialOrdinal=\(materialOrdinal.map(String.init) ?? "-")",
            "commandOrdinal=\(commandOrdinal.map(String.init) ?? "-")",
            "commandSource=\(SceneGraphExecutionLogToken.encode(commandSource))",
            "commandTarget=\(SceneGraphExecutionLogToken.encode(commandTarget))",
            "compose=\(advancesComposePair)",
            "disposition=\(disposition.details.value)",
            "reason=\(SceneGraphExecutionLogToken.encode(disposition.details.reason))",
        ].joined(separator: "|")
    }
}

nonisolated extension SceneGraphExecutionLogicalBinding {
    var canonicalLine: String {
        "logical=\(SceneGraphExecutionLogToken.encode(logicalIdentity))"
            + "|physical=\(SceneGraphExecutionLogToken.encode(physicalIdentity))"
    }
}

nonisolated extension SceneGraphExecutionObservation {
    var logFields: [String] {
        [
            "frame=\(frameIndex)",
            "layer=\(identity.layerID)",
            "effect=\(identity.effectIndex)",
            "descriptor=\(SceneGraphExecutionLogToken.encode(identity.descriptorID))",
            "graph=\(SceneGraphExecutionLogToken.encode(graphIdentity))",
            "program=\(SceneGraphExecutionLogToken.encode(programIdentity))",
            "programSequence=\(SceneGraphExecutionLogToken.encode(programSequenceIdentity))",
            "transaction=\(SceneGraphExecutionLogToken.encode(transactionIdentity))",
            "effectGeneration=\(effectGeneration)",
            "allocationGeneration=\(allocationGeneration)",
            "mappingGeneration=\(mappingGeneration)",
            "authoredNodes=\(nodeCounts.authored)",
            "materialNodes=\(nodeCounts.material)",
            "copyNodes=\(nodeCounts.copy)",
            "swapNodes=\(nodeCounts.swap)",
            "composeNodes=\(nodeCounts.compose)",
            "rejectedNodes=\(nodeCounts.rejected)",
            "materialOrdinals=\(materialOrdinalCount)",
            "commandOrdinals=\(commandOrdinalCount)",
            "nodeSequenceSHA256=\(nodeSequenceSHA256)",
            "mappingBeforeSHA256=\(logicalMappingBeforeSHA256)",
            "mappingAfterSHA256=\(logicalMappingAfterSHA256)",
            "targetDescriptorsSHA256=\(targetDescriptorsSHA256 ?? "-")",
            "targetDescriptorCounts=\(SceneGraphExecutionLogToken.encode(targetDescriptorCounts))",
            "composeSlotBefore=\(composeSlotBefore.rawValue)",
            "composeSlotAfter=\(composeSlotAfter.rawValue)",
            "history=\(historyState.rawValue)",
            "reset=\(resetReason?.rawValue ?? "-")",
            "finalOutput=\(SceneGraphExecutionLogToken.encode(finalOutput?.identity))",
            "physicalIdentity=\(SceneGraphExecutionLogToken.encode(finalOutput?.physicalIdentity))",
            "publication=\(SceneGraphExecutionLogToken.encode(finalOutput?.publicationIdentity))",
            "publicationGeneration=\(finalOutput.map { String($0.publicationGeneration) } ?? "-")",
            "compositorConsumed=\(compositorConsumed)",
            "outcome=\(outcome.details.value)",
            "failure=\(SceneGraphExecutionLogToken.encode(outcome.details.reason))",
            "gpuCompletion=\(gpuCompletionStatus?.rawValue ?? "-")",
        ]
    }

    var canonicalLine: String {
        (["graph-execution"] + logFields).joined(separator: "|")
    }
}

nonisolated enum SceneGraphExecutionLogToken {
    static func encode(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value.utf8.map { byte in
            let isAllowed = (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || [43, 45, 46, 47, 58, 95].contains(byte)
            return isAllowed
                ? String(UnicodeScalar(byte))
                : String(format: "%%%02X", byte)
        }.joined()
    }
}
