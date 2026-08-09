import Foundation

/// Converts one terminal executor transition into an immutable telemetry atom.
/// A failed candidate is described against the last committed state and never
/// publishes candidate mapping, pair movement, or output.
enum SceneResolvedMaterialGraphObservationBuilder {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias State = SceneGraphExecutionState
    typealias Prepared = SceneResolvedMaterialGraphExecutor.PreparedStage

    enum Failure: Error {
        case invalidGraph
        case invalidProgram
        case invalidFinalPublication
    }

    static func make(
        _ value: Prepared,
        frameIndex: UInt64,
        transactionID: UInt64,
        executionEpoch: UInt64,
        mappingGeneration: UInt64,
        resetReason: SceneGraphExecutionResetReason?,
        committedBaseState: State? = nil,
        terminalEffect: Graph.EffectKey,
        outcome: SceneGraphExecutionOutcome,
        gpu: SceneGraphExecutionGPUCompletionStatus?
    ) throws -> SceneGraphExecutionObservation {
        let transaction = value.transition.transaction
        guard State.maximumNodeCount
                == SceneGraphExecutionObservation.maximumNodeCount,
              State.maximumLogicalBindingCount
                == SceneGraphExecutionObservation.maximumLogicalBindingCount,
              let effect = value.graph.effects.first?.key,
              effect == value.effect,
              effect == value.pairStep.effect,
              value.graph.effects.count == 1 else {
            throw Failure.invalidGraph
        }
        let failedReason: String? = if case let .failed(reason) = outcome {
            reason
        } else {
            nil
        }
        let nodes = try nodeObservations(
            value,
            rejectedReason: failedReason
        )
        guard nodes.count == value.graph.nodes.count,
              !value.programCacheKeys.isEmpty else {
            throw Failure.invalidProgram
        }

        let programSequence = SceneShaderStableDigest.hash(
            Data(value.programCacheKeys.joined(separator: "\n").utf8)
        )
        let failed = failedReason != nil
        let baseMapping = committedBaseState?.logicalMapping ?? [:]
        let mappingBefore = failed ? baseMapping : transaction.mappingBefore
        let mappingAfter = failed ? baseMapping : transaction.mappingAfter
        let allocationGeneration = failed
            ? committedBaseState?.allocationGeneration ?? 0
            : transaction.allocationGeneration
        let effectiveMappingGeneration = failed && committedBaseState == nil
            ? 0 : mappingGeneration
        let final = failed ? nil : try finalPublication(value)

        return try .init(
            identity: .init(
                layerID: effect.layerID,
                effectIndex: effect.effectIndex,
                descriptorID: effect.descriptorID
            ),
            graphIdentity: SceneShaderStableDigest.hash(value.graph),
            programIdentity: value.programCacheKeys.first ?? "commands-only",
            programSequenceIdentity: programSequence,
            transactionIdentity: "r4:\(executionEpoch):\(transactionID):\(effect.effectIndex)",
            frameIndex: frameIndex,
            effectGeneration: transaction.effectGeneration,
            allocationGeneration: allocationGeneration,
            mappingGeneration: effectiveMappingGeneration,
            authoredNodeIndices: value.graph.nodes.map(\.nodeIndex),
            nodes: nodes,
            expectedNodeCounts: counts(nodes),
            logicalMappingBefore: mapping(mappingBefore),
            logicalMappingAfter: mapping(mappingAfter),
            composeSlotBefore: failed ? .none : slot(value.pairStep.inputMember),
            composeSlotAfter: failed ? .none : slot(value.pairStep.outputMember),
            historyState: failed
                ? failedHistoryState(committedBaseState)
                : historyState(value),
            resetReason: failed ? nil : resetReason,
            finalOutput: final,
            compositorConsumed: !failed && value.effect == terminalEffect,
            outcome: outcome,
            gpuCompletionStatus: gpu
        )
    }

    private static func finalPublication(
        _ value: Prepared
    ) throws -> SceneGraphExecutionFinalOutputPublication {
        let resource = value.effectOutputResource
        let transaction = value.transition.transaction
        guard resource.isCompleteGraphResource,
              resource.publication.requestIdentity
                == .graph(value.pairStep.outputIdentity),
              resource.resourceGeneration > 0,
              resource.publication.contentGeneration
                == resource.resourceGeneration,
              case let .provider(.graph(allocationGeneration, physicalToken)) =
                resource.publication.candidate.identity,
              allocationGeneration == transaction.allocationGeneration,
              !physicalToken.isEmpty else {
            throw Failure.invalidFinalPublication
        }
        return .init(
            identity: SceneFrameTextureIdentity.graph(
                value.pairStep.outputIdentity
            ).reportToken,
            physicalIdentity: physicalToken,
            publicationIdentity: publicationIdentity(resource.publication),
            publicationGeneration: resource.resourceGeneration
        )
    }

    private static func nodeObservations(
        _ value: Prepared,
        rejectedReason: String?
    ) throws -> [SceneGraphExecutionNodeObservation] {
        let pairIndices = value.pairStep.nodes.map(\.nodeIndex)
        let graphIndices = value.graph.nodes.map(\.nodeIndex)
        guard Set(pairIndices).count == pairIndices.count,
              Set(graphIndices).count == graphIndices.count,
              pairIndices == graphIndices else { throw Failure.invalidGraph }
        let pairNodes = Dictionary(uniqueKeysWithValues:
            value.pairStep.nodes.map { ($0.nodeIndex, $0) })
        let graphNodes = Dictionary(uniqueKeysWithValues:
            value.graph.nodes.map { ($0.nodeIndex, $0) })
        let disposition: SceneGraphExecutionNodeDisposition = rejectedReason.map {
            .rejected(reasonCode: $0)
        } ?? .executed
        var visited = Set<Int>()
        var nodes: [SceneGraphExecutionNodeObservation] = []
        for intent in value.transition.transaction.intents {
            switch intent {
            case let .material(node, ordinal, _, _):
                guard let pair = pairNodes[node], let graph = graphNodes[node],
                      visited.insert(node).inserted,
                      pair.kind == .material, graph.kind == .material,
                      graph.materialOrdinal == ordinal else {
                    throw Failure.invalidGraph
                }
                nodes.append(.init(
                    nodeIndex: node, kind: .material,
                    materialOrdinal: ordinal, commandOrdinal: nil,
                    commandSource: nil, commandTarget: nil,
                    advancesComposePair: rejectedReason == nil
                        && pair.rotatesAfterNode,
                    disposition: disposition
                ))
            case let .copy(node, ordinal, source, _, target, _):
                guard let pair = pairNodes[node], let graph = graphNodes[node],
                      visited.insert(node).inserted,
                      pair.kind == .copy, graph.kind == .copy,
                      graph.commandSource == source,
                      graph.commandTarget == target else {
                    throw Failure.invalidGraph
                }
                nodes.append(commandObservation(
                    node: node, ordinal: ordinal, kind: .copy,
                    source: source, target: target, disposition: disposition
                ))
            case let .swap(node, ordinal, source, _, target, _):
                guard let pair = pairNodes[node], let graph = graphNodes[node],
                      visited.insert(node).inserted,
                      pair.kind == .swap, graph.kind == .swap,
                      graph.commandSource == source,
                      graph.commandTarget == target else {
                    throw Failure.invalidGraph
                }
                nodes.append(commandObservation(
                    node: node, ordinal: ordinal, kind: .swap,
                    source: source, target: target, disposition: disposition
                ))
            case .initialize:
                continue
            }
        }
        nodes.sort { $0.nodeIndex < $1.nodeIndex }
        guard nodes.map(\.nodeIndex) == graphIndices,
              visited == Set(graphIndices) else {
            throw Failure.invalidGraph
        }
        return nodes
    }

    private static func commandObservation(
        node: Int,
        ordinal: Int,
        kind: SceneGraphExecutionNodeKind,
        source: Graph.TextureIdentity,
        target: Graph.TextureIdentity,
        disposition: SceneGraphExecutionNodeDisposition
    ) -> SceneGraphExecutionNodeObservation {
        .init(
            nodeIndex: node, kind: kind,
            materialOrdinal: nil, commandOrdinal: ordinal,
            commandSource: SceneFrameTextureIdentity.graph(source).reportToken,
            commandTarget: SceneFrameTextureIdentity.graph(target).reportToken,
            advancesComposePair: false, disposition: disposition
        )
    }

    private static func counts(
        _ nodes: [SceneGraphExecutionNodeObservation]
    ) -> SceneGraphExecutionNodeCounts {
        let executed = nodes.filter {
            if case .executed = $0.disposition { return true }
            return false
        }
        return .init(
            authored: nodes.count,
            material: executed.filter { $0.kind == .material }.count,
            copy: executed.filter { $0.kind == .copy }.count,
            swap: executed.filter { $0.kind == .swap }.count,
            compose: executed.filter(\.advancesComposePair).count,
            rejected: nodes.count - executed.count
        )
    }

    private static func failedHistoryState(
        _ committedBaseState: State?
    ) -> SceneGraphExecutionHistoryState {
        guard let committedBaseState else { return .none }
        return committedBaseState.historyLogicalIdentities.isEmpty
            ? .none : .reused
    }

    private static func historyState(
        _ value: Prepared
    ) -> SceneGraphExecutionHistoryState {
        let history = value.transition.nextState.historyLogicalIdentities
        if history.isEmpty { return .none }
        let seeded = value.transition.transaction.intents.contains { intent in
            guard case let .initialize(identity, _, _) = intent else { return false }
            return history.contains(identity)
        }
        return seeded ? .seeded : .reused
    }

    private static func mapping(
        _ values: [Graph.TextureIdentity: State.VersionedResource]
    ) -> [SceneGraphExecutionLogicalBinding] {
        values.map {
            .init(
                logicalIdentity: SceneFrameTextureIdentity.graph($0.key).reportToken,
                physicalIdentity: $0.value.token.rawValue
            )
        }
    }

    private static func slot(
        _ member: SceneLayerFullFramePairPlan.Member
    ) -> SceneGraphExecutionComposeSlot {
        member == .zero ? .primary : .secondary
    }

    private static func publicationIdentity(
        _ publication: SceneTextureProviderPublication
    ) -> String {
        switch publication.candidate.identity {
        case let .provider(identity): return identity.reportToken
        case let .file(path): return "file:\(path)"
        case let .builtIn(name): return "built-in:\(name)"
        }
    }
}
