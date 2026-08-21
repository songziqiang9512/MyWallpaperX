import CryptoKit
import Foundation

nonisolated struct SceneGraphExecutionEffectIdentity: Hashable, Sendable {
    let layerID, effectIndex: Int
    let descriptorID: String
}

nonisolated enum SceneGraphExecutionNodeKind: String, Hashable, Sendable {
    case material, copy, swap
}

nonisolated enum SceneGraphExecutionNodeDisposition: Hashable, Sendable {
    case executed
    case rejected(reasonCode: String)
}

nonisolated struct SceneGraphExecutionNodeObservation: Hashable, Sendable {
    let nodeIndex: Int
    let kind: SceneGraphExecutionNodeKind
    let materialOrdinal: Int?
    let commandOrdinal: Int?
    let commandSource: String?
    let commandTarget: String?
    let advancesComposePair: Bool
    let disposition: SceneGraphExecutionNodeDisposition
}

nonisolated struct SceneGraphExecutionNodeCounts: Equatable, Sendable {
    let authored, material, copy, swap, compose, rejected: Int
}

nonisolated struct SceneGraphExecutionLogicalBinding: Hashable, Sendable {
    let logicalIdentity: String
    let physicalIdentity: String
    let width: Int?
    let height: Int?
    let format: String?

    init(
        logicalIdentity: String,
        physicalIdentity: String,
        width: Int? = nil,
        height: Int? = nil,
        format: String? = nil
    ) {
        self.logicalIdentity = logicalIdentity
        self.physicalIdentity = physicalIdentity
        self.width = width
        self.height = height
        self.format = format
    }
}

nonisolated enum SceneGraphExecutionComposeSlot: String, Hashable, Sendable {
    case none, primary, secondary
}

nonisolated enum SceneGraphExecutionHistoryState: String, Hashable, Sendable {
    case none, seeded, reused
}

nonisolated enum SceneGraphExecutionResetReason: String, Hashable, Sendable {
    case initial, sceneSwitch = "scene-switch", surfaceStop = "surface-stop"
    case allocationReprepare = "allocation-reprepare"
    case allocationRebind = "allocation-rebind"
    case historyCopyOnWrite = "history-copy-on-write"
    case effectReparse = "effect-reparse"
    case deviceLoss = "device-loss"
    case executorInvalidation = "executor-invalidation"
}

nonisolated enum SceneGraphExecutionGPUCompletionStatus: String, Hashable, Sendable {
    case completed, failed
}

nonisolated enum SceneGraphExecutionOutcome: Hashable, Sendable {
    case succeeded
    case failed(reasonCode: String)
}

nonisolated struct SceneGraphExecutionFinalOutputPublication: Hashable, Sendable {
    let identity, physicalIdentity, publicationIdentity: String
    let publicationGeneration: UInt64
}

nonisolated enum SceneGraphExecutionObservationError: String, Error, Sendable {
    case invalidIdentity, invalidExecutionIdentity, invalidNodeCount, invalidNodeOrder
    case invalidNodeDisposition, invalidCommandIdentity, invalidCompose, invalidOrdinals
    case invalidNodeConservation, invalidLogicalMapping, invalidTargetDescriptors
    case invalidLifecycle, invalidFinalOutput, invalidOutcome
}

nonisolated struct SceneGraphExecutionObservation: Sendable {
    // These mirror SceneGraphExecutionState. The observation builder verifies
    // the equality before it can authorize a committed graph tail.
    static let maximumNodeCount = 512, maximumLogicalBindingCount = 512

    let runtimeInstanceIdentity: String
    let identity: SceneGraphExecutionEffectIdentity
    let graphIdentity, programIdentity, programSequenceIdentity: String
    let transactionIdentity: String
    let frameIndex: UInt64
    let effectGeneration, allocationGeneration, mappingGeneration: UInt64
    let authoredNodeIndices: [Int]
    let nodeCounts: SceneGraphExecutionNodeCounts
    let materialOrdinalCount, commandOrdinalCount: Int
    let nodeSequenceSHA256: String
    let logicalMappingBeforeSHA256, logicalMappingAfterSHA256: String
    let targetDescriptorsSHA256, targetDescriptorCounts: String?
    let inputWidth, inputHeight: Int
    let historyRehydrateCopyCount: Int
    let historyContentDiscarded: Bool
    let composeSlotBefore, composeSlotAfter: SceneGraphExecutionComposeSlot
    let historyState: SceneGraphExecutionHistoryState
    let resetReason: SceneGraphExecutionResetReason?
    let finalOutput: SceneGraphExecutionFinalOutputPublication?
    let compositorConsumed: Bool
    let outcome: SceneGraphExecutionOutcome
    let gpuCompletionStatus: SceneGraphExecutionGPUCompletionStatus?

    init(
        runtimeInstanceIdentity: String,
        identity: SceneGraphExecutionEffectIdentity,
        graphIdentity: String,
        programIdentity: String,
        programSequenceIdentity: String,
        transactionIdentity: String,
        frameIndex: UInt64,
        effectGeneration: UInt64,
        allocationGeneration: UInt64,
        mappingGeneration: UInt64,
        authoredNodeIndices: [Int],
        nodes: [SceneGraphExecutionNodeObservation],
        expectedNodeCounts: SceneGraphExecutionNodeCounts,
        logicalMappingBefore: [SceneGraphExecutionLogicalBinding],
        logicalMappingAfter: [SceneGraphExecutionLogicalBinding],
        inputWidth: Int,
        inputHeight: Int,
        historyRehydrateCopyCount: Int,
        historyContentDiscarded: Bool,
        composeSlotBefore: SceneGraphExecutionComposeSlot,
        composeSlotAfter: SceneGraphExecutionComposeSlot,
        historyState: SceneGraphExecutionHistoryState,
        resetReason: SceneGraphExecutionResetReason? = nil,
        finalOutput: SceneGraphExecutionFinalOutputPublication?,
        compositorConsumed: Bool,
        outcome: SceneGraphExecutionOutcome,
        gpuCompletionStatus: SceneGraphExecutionGPUCompletionStatus? = nil
    ) throws {
        guard Self.hasText(runtimeInstanceIdentity),
              identity.layerID >= 0,
              identity.effectIndex >= 0,
              Self.hasText(identity.descriptorID) else {
            throw SceneGraphExecutionObservationError.invalidIdentity
        }
        guard Self.hasText(graphIdentity),
              Self.hasText(programIdentity),
              Self.hasText(programSequenceIdentity),
              Self.hasText(transactionIdentity) else {
            throw SceneGraphExecutionObservationError.invalidExecutionIdentity
        }
        guard !nodes.isEmpty, nodes.count <= Self.maximumNodeCount else {
            throw SceneGraphExecutionObservationError.invalidNodeCount
        }

        let ordinalCounts = try Self.validateNodes(nodes, authoredNodeIndices: authoredNodeIndices)
        let derivedCounts = Self.deriveCounts(nodes)
        guard expectedNodeCounts == derivedCounts,
              expectedNodeCounts.authored
                == expectedNodeCounts.material + expectedNodeCounts.copy
                + expectedNodeCounts.swap + expectedNodeCounts.rejected,
              expectedNodeCounts.compose <= expectedNodeCounts.material else {
            throw SceneGraphExecutionObservationError.invalidNodeConservation
        }
        let mappingEvidence = try Self.validateMappingTransition(
            before: logicalMappingBefore,
            after: logicalMappingAfter,
            nodes: nodes
        )
        guard inputWidth > 0, inputHeight > 0,
              historyRehydrateCopyCount >= 0,
              !(historyContentDiscarded && historyRehydrateCopyCount > 0),
              resetReason != .historyCopyOnWrite || (
                  historyState == .reused
                    && historyRehydrateCopyCount > 0
                    && !historyContentDiscarded
              ),
              resetReason != .allocationRebind || (
                  historyRehydrateCopyCount == 0 && !historyContentDiscarded
              ) else {
            throw SceneGraphExecutionObservationError.invalidLifecycle
        }
        try Self.validateComposeTransition(
            count: expectedNodeCounts.compose,
            before: composeSlotBefore,
            after: composeSlotAfter,
            outcome: outcome
        )
        if let finalOutput {
            guard Self.hasText(finalOutput.identity),
                  Self.hasText(finalOutput.physicalIdentity),
                  Self.hasText(finalOutput.publicationIdentity),
                  finalOutput.publicationGeneration > 0 else {
                throw SceneGraphExecutionObservationError.invalidFinalOutput
            }
        }
        guard !compositorConsumed || finalOutput != nil else {
            throw SceneGraphExecutionObservationError.invalidFinalOutput
        }

        switch outcome {
        case .succeeded:
            let visualFailurePassthrough =
                expectedNodeCounts.authored > 0
                && expectedNodeCounts.rejected == expectedNodeCounts.authored
                && expectedNodeCounts.material == 0
                && expectedNodeCounts.copy == 0
                && expectedNodeCounts.swap == 0
                && expectedNodeCounts.compose == 0
                && programIdentity.hasPrefix("visual-failure-passthrough:")
            guard (expectedNodeCounts.rejected == 0
                    || visualFailurePassthrough),
                  finalOutput != nil,
                  gpuCompletionStatus == .completed else {
                throw SceneGraphExecutionObservationError.invalidOutcome
            }
        case let .failed(reasonCode):
            guard Self.hasText(reasonCode),
                  expectedNodeCounts.rejected == expectedNodeCounts.authored,
                  finalOutput == nil,
                  !compositorConsumed,
                  gpuCompletionStatus != .completed else {
                throw SceneGraphExecutionObservationError.invalidOutcome
            }
        }

        self.runtimeInstanceIdentity = runtimeInstanceIdentity
        self.identity = identity
        self.graphIdentity = graphIdentity
        self.programIdentity = programIdentity
        self.programSequenceIdentity = programSequenceIdentity
        self.transactionIdentity = transactionIdentity
        self.frameIndex = frameIndex
        self.effectGeneration = effectGeneration
        self.allocationGeneration = allocationGeneration
        self.mappingGeneration = mappingGeneration
        self.authoredNodeIndices = authoredNodeIndices
        self.nodeCounts = expectedNodeCounts
        materialOrdinalCount = ordinalCounts.material
        commandOrdinalCount = ordinalCounts.command
        nodeSequenceSHA256 = Self.sequenceSHA256(nodes)
        logicalMappingBeforeSHA256 = mappingEvidence.before
        logicalMappingAfterSHA256 = mappingEvidence.after
        targetDescriptorsSHA256 = mappingEvidence.targetDescriptorsSHA256
        targetDescriptorCounts = mappingEvidence.targetDescriptorCounts
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.historyRehydrateCopyCount = historyRehydrateCopyCount
        self.historyContentDiscarded = historyContentDiscarded
        self.composeSlotBefore = composeSlotBefore
        self.composeSlotAfter = composeSlotAfter
        self.historyState = historyState
        self.resetReason = resetReason
        self.finalOutput = finalOutput
        self.compositorConsumed = compositorConsumed
        self.outcome = outcome
        self.gpuCompletionStatus = gpuCompletionStatus
    }

    private static func validateNodes(
        _ nodes: [SceneGraphExecutionNodeObservation],
        authoredNodeIndices: [Int]
    ) throws -> (material: Int, command: Int) {
        guard nodes.map(\.nodeIndex) == authoredNodeIndices,
              authoredNodeIndices.allSatisfy({ $0 >= 0 }),
              zip(authoredNodeIndices, authoredNodeIndices.dropFirst())
                .allSatisfy({ $0 < $1 }) else {
            throw SceneGraphExecutionObservationError.invalidNodeOrder
        }
        var materialOrdinals: [Int] = []
        var commandOrdinals: [Int] = []
        for node in nodes {
            if case let .rejected(reasonCode) = node.disposition,
               !hasText(reasonCode) {
                throw SceneGraphExecutionObservationError.invalidNodeDisposition
            }
            guard !node.advancesComposePair || node.kind == .material else {
                throw SceneGraphExecutionObservationError.invalidCompose
            }
            if node.kind == .material {
                guard let ordinal = node.materialOrdinal,
                      ordinal >= 0,
                      node.commandOrdinal == nil,
                      node.commandSource == nil,
                      node.commandTarget == nil else {
                    throw SceneGraphExecutionObservationError.invalidOrdinals
                }
                materialOrdinals.append(ordinal)
            } else {
                guard let ordinal = node.commandOrdinal,
                      ordinal >= 0,
                      node.materialOrdinal == nil else {
                    throw SceneGraphExecutionObservationError.invalidOrdinals
                }
                guard let source = node.commandSource,
                      let target = node.commandTarget,
                      hasText(source), hasText(target), source != target else {
                    throw SceneGraphExecutionObservationError.invalidCommandIdentity
                }
                commandOrdinals.append(ordinal)
            }
        }
        guard zip(materialOrdinals, materialOrdinals.dropFirst())
                .allSatisfy({ $0 < $1 }),
              commandOrdinals == Array(0..<commandOrdinals.count) else {
            throw SceneGraphExecutionObservationError.invalidOrdinals
        }
        return (materialOrdinals.count, commandOrdinals.count)
    }

    private static func deriveCounts(
        _ nodes: [SceneGraphExecutionNodeObservation]
    ) -> SceneGraphExecutionNodeCounts {
        var material = 0
        var copy = 0
        var swap = 0
        var compose = 0
        var rejected = 0
        for node in nodes {
            if case .rejected = node.disposition {
                rejected += 1
                continue
            }
            switch node.kind {
            case .material:
                material += 1
                if node.advancesComposePair { compose += 1 }
            case .copy: copy += 1
            case .swap: swap += 1
            }
        }
        return .init(
            authored: nodes.count,
            material: material,
            copy: copy,
            swap: swap,
            compose: compose,
            rejected: rejected
        )
    }

    private static func sequenceSHA256(
        _ nodes: [SceneGraphExecutionNodeObservation]
    ) -> String {
        digest(nodes.map(\.canonicalLine).joined(separator: "\n"))
    }

    private static func validateMappingTransition(
        before: [SceneGraphExecutionLogicalBinding],
        after: [SceneGraphExecutionLogicalBinding],
        nodes: [SceneGraphExecutionNodeObservation]
    ) throws -> (
        before: String,
        after: String,
        targetDescriptorsSHA256: String?,
        targetDescriptorCounts: String?
    ) {
        guard before.count <= maximumLogicalBindingCount,
              before.count == after.count else {
            throw SceneGraphExecutionObservationError.invalidLogicalMapping
        }
        let beforeMap = try validatedMapping(before)
        let afterMap = try validatedMapping(after)
        guard Set(beforeMap.keys) == Set(afterMap.keys),
              Set(beforeMap.values) == Set(afterMap.values) else {
            throw SceneGraphExecutionObservationError.invalidLogicalMapping
        }
        var replay = beforeMap
        for node in nodes where node.kind != .material {
            guard let source = node.commandSource,
                  let target = node.commandTarget else {
                throw SceneGraphExecutionObservationError.invalidLogicalMapping
            }
            if case .rejected = node.disposition { continue }
            guard let sourceValue = replay[source],
                  let targetValue = replay[target] else {
                throw SceneGraphExecutionObservationError.invalidLogicalMapping
            }
            if node.kind == .swap {
                replay[source] = targetValue
                replay[target] = sourceValue
            }
        }
        guard replay == afterMap else {
            throw SceneGraphExecutionObservationError.invalidLogicalMapping
        }
        let beforeDescriptors = try validatedTargetDescriptors(before)
        let afterDescriptors = try validatedTargetDescriptors(after)
        guard beforeDescriptors == afterDescriptors else {
            throw SceneGraphExecutionObservationError.invalidTargetDescriptors
        }
        let descriptorLines = beforeDescriptors.values.sorted()
        let descriptorCounts = Dictionary(grouping: beforeDescriptors.values) {
            $0.extentAndFormat
        }.map { key, values in
            "\(key):\(values.count)"
        }.sorted().joined(separator: ",")
        return (
            mappingSHA256(before),
            mappingSHA256(after),
            descriptorLines.isEmpty
                ? nil : digest(descriptorLines.map(\.canonicalLine).joined(separator: "\n")),
            descriptorCounts.isEmpty ? nil : descriptorCounts
        )
    }

    private struct TargetDescriptorEvidence: Equatable, Comparable {
        let logicalIdentity: String
        let width, height: Int
        let format: String

        var extentAndFormat: String { "\(width)x\(height)/\(format)" }
        var canonicalLine: String {
            "logical=\(SceneGraphExecutionLogToken.encode(logicalIdentity))"
                + "|extent=\(width)x\(height)|format="
                + SceneGraphExecutionLogToken.encode(format)
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.canonicalLine < rhs.canonicalLine
        }
    }

    private static func validatedTargetDescriptors(
        _ bindings: [SceneGraphExecutionLogicalBinding]
    ) throws -> [String: TargetDescriptorEvidence] {
        let carriesDescriptors = bindings.contains {
            $0.width != nil || $0.height != nil || $0.format != nil
        }
        guard carriesDescriptors else { return [:] }
        guard bindings.allSatisfy({ binding in
            guard let width = binding.width,
                  let height = binding.height,
                  let format = binding.format else { return false }
            return width > 0 && height > 0 && hasText(format)
        }) else {
            throw SceneGraphExecutionObservationError.invalidTargetDescriptors
        }
        let descriptors = Dictionary(
            bindings.map { binding in
                (
                    binding.logicalIdentity,
                    TargetDescriptorEvidence(
                        logicalIdentity: binding.logicalIdentity,
                        width: binding.width!,
                        height: binding.height!,
                        format: binding.format!
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard descriptors.count == bindings.count else {
            throw SceneGraphExecutionObservationError.invalidTargetDescriptors
        }
        return descriptors
    }

    private static func validatedMapping(
        _ bindings: [SceneGraphExecutionLogicalBinding]
    ) throws -> [String: String] {
        guard bindings.allSatisfy({
            hasText($0.logicalIdentity) && hasText($0.physicalIdentity)
        }) else {
            throw SceneGraphExecutionObservationError.invalidLogicalMapping
        }
        let mapping = Dictionary(
            bindings.map { ($0.logicalIdentity, $0.physicalIdentity) },
            uniquingKeysWith: { first, _ in first }
        )
        guard mapping.count == bindings.count,
              Set(mapping.values).count == mapping.count else {
            throw SceneGraphExecutionObservationError.invalidLogicalMapping
        }
        return mapping
    }

    private static func mappingSHA256(
        _ bindings: [SceneGraphExecutionLogicalBinding]
    ) -> String {
        digest(bindings.map(\.canonicalLine).sorted().joined(separator: "\n"))
    }

    private static func validateComposeTransition(
        count: Int,
        before: SceneGraphExecutionComposeSlot,
        after: SceneGraphExecutionComposeSlot,
        outcome: SceneGraphExecutionOutcome
    ) throws {
        if case .failed = outcome {
            guard count == 0, before == .none, after == .none else {
                throw SceneGraphExecutionObservationError.invalidCompose
            }
            return
        }
        guard before != .none,
              after != .none,
              (count.isMultiple(of: 2) ? before != after : before == after) else {
            throw SceneGraphExecutionObservationError.invalidCompose
        }
    }

    private static func hasText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func digest(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
