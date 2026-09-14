import Foundation

/// Pure-value routing for the layer-scoped two-member full-frame pair.
/// Condition and function admission happen before this planner; explicit
/// framebuffer resources remain owned by the authored render graph.
nonisolated struct SceneLayerFullFramePairPlan: Equatable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum Member: Int, CaseIterable, Hashable {
        case zero = 0
        case one = 1

        var opposite: Self { self == .zero ? .one : .zero }
    }

    enum NodeKind: String, Equatable {
        case material
        case copy
        case swap
    }

    enum Failure: String, Error {
        case emptyChain = "empty-chain"
        case graphBlocked = "graph-blocked"
        case invalidLayer = "invalid-layer"
        case invalidEffectGraph = "invalid-effect-graph"
        case noncontiguousChain = "noncontiguous-chain"
        case conditionNotPruned = "condition-not-pruned"
        case invalidNodeOrder = "invalid-node-order"
        case invalidNodeShape = "invalid-node-shape"
        case invalidCompose = "invalid-compose"
        case invalidFullFrameAccess = "invalid-full-frame-access"
        case missingEffectOutput = "missing-effect-output"
        case unwrittenBoundaryOutput = "unwritten-boundary-output"
        case transitionOverflow = "transition-overflow"
        case terminalMemberInvariant = "terminal-member-invariant"
    }

    struct NodeStep: Equatable {
        let nodeIndex: Int
        let definitionPassIndex: Int
        let kind: NodeKind
        let currentMemberBeforeNode: Member
        let fullFrameReadMember: Member?
        let fullFrameWriteMember: Member?
        let rotatesAfterNode: Bool
        let currentMemberAfterNode: Member
    }

    struct EffectStep: Equatable {
        let effect: Graph.EffectKey
        let inputIdentity: Graph.TextureIdentity
        let outputIdentity: Graph.TextureIdentity
        let inputMember: Member
        let outputMember: Member
        let composeTransitionCount: Int
        let fullFrameOutputWriteCount: Int
        let nodes: [NodeStep]
    }

    static let reservedMembers: [Member] = [.zero, .one]
    static let fixedTerminalMember: Member = .zero

    let layerID: Int
    let baseCaptureIdentity: Graph.TextureIdentity
    let baseCaptureMember: Member
    let transitionCount: Int
    let effects: [EffectStep]
    let terminalMember: Member
    let terminalOutputIdentity: Graph.TextureIdentity

    static func make(
        conditionPrunedGraphs graphs: [Graph]
    ) -> Result<Self, Failure> {
        guard let first = graphs.first else { return .failure(.emptyChain) }
        let layerID = first.layerID
        let base = SceneAuthoredEffectInputValidator.layerSource(layerID: layerID)
        var validated: [ValidatedEffect] = []
        var previousOutput: Graph.TextureIdentity?
        var previousEffectIndex: Int?
        var composeCount = 0

        for graph in graphs {
            switch validate(
                graph,
                layerID: layerID,
                expectedInput: previousOutput ?? base,
                previousEffectIndex: previousEffectIndex
            ) {
            case let .success(effect):
                let (next, overflow) = composeCount.addingReportingOverflow(
                    effect.composeTransitionCount
                )
                guard !overflow else { return .failure(.transitionOverflow) }
                composeCount = next
                validated.append(effect)
                previousOutput = effect.outputIdentity
                previousEffectIndex = effect.key.effectIndex
            case let .failure(failure):
                return .failure(failure)
            }
        }

        let (transitionCount, overflow) = graphs.count.addingReportingOverflow(
            composeCount
        )
        guard !overflow else { return .failure(.transitionOverflow) }
        var current: Member = transitionCount.isMultiple(of: 2) ? .zero : .one
        let baseMember = current
        var effectSteps: [EffectStep] = []
        var observedTransitions = 0

        for effect in validated {
            let inputMember = current
            var nodes: [NodeStep] = []
            var lastOutputMember: Member?
            for node in effect.nodes {
                let before = current
                let read = node.readsFullFrame ? current : nil
                let write = node.writesFullFrame ? current.opposite : nil
                if let write { lastOutputMember = write }
                if node.compose {
                    guard let write else { return .failure(.invalidCompose) }
                    current = write
                    observedTransitions += 1
                }
                nodes.append(.init(
                    nodeIndex: node.nodeIndex,
                    definitionPassIndex: node.definitionPassIndex,
                    kind: node.kind,
                    currentMemberBeforeNode: before,
                    fullFrameReadMember: read,
                    fullFrameWriteMember: write,
                    rotatesAfterNode: node.compose,
                    currentMemberAfterNode: current
                ))
            }
            let outputMember = current.opposite
            guard lastOutputMember == outputMember else {
                return .failure(.unwrittenBoundaryOutput)
            }
            current = outputMember
            observedTransitions += 1
            effectSteps.append(.init(
                effect: effect.key,
                inputIdentity: effect.inputIdentity,
                outputIdentity: effect.outputIdentity,
                inputMember: inputMember,
                outputMember: outputMember,
                composeTransitionCount: effect.composeTransitionCount,
                fullFrameOutputWriteCount: effect.fullFrameOutputWriteCount,
                nodes: nodes
            ))
        }

        guard current == .zero, observedTransitions == transitionCount,
              let terminalOutput = validated.last?.outputIdentity else {
            return .failure(.terminalMemberInvariant)
        }
        return .success(.init(
            layerID: layerID,
            baseCaptureIdentity: base,
            baseCaptureMember: baseMember,
            transitionCount: transitionCount,
            effects: effectSteps,
            terminalMember: current,
            terminalOutputIdentity: terminalOutput
        ))
    }

    private struct ValidatedNode {
        let nodeIndex: Int
        let definitionPassIndex: Int
        let kind: NodeKind
        let readsFullFrame: Bool
        let writesFullFrame: Bool
        let compose: Bool
    }

    private struct ValidatedEffect {
        let key: Graph.EffectKey
        let inputIdentity: Graph.TextureIdentity
        let outputIdentity: Graph.TextureIdentity
        let composeTransitionCount: Int
        let fullFrameOutputWriteCount: Int
        let nodes: [ValidatedNode]
    }

    private static func validate(
        _ graph: Graph,
        layerID: Int,
        expectedInput: Graph.TextureIdentity,
        previousEffectIndex: Int?
    ) -> Result<ValidatedEffect, Failure> {
        guard graph.blockers.isEmpty else { return .failure(.graphBlocked) }
        guard graph.layerID == layerID else { return .failure(.invalidLayer) }
        guard graph.effects.count == 1, let effect = graph.effects.first,
              effect.key.layerID == layerID, effect.key.effectIndex >= 0,
              !effect.key.descriptorID.isEmpty else {
            return .failure(.invalidEffectGraph)
        }
        guard effect.input == expectedInput else {
            return .failure(.noncontiguousChain)
        }
        if let previousEffectIndex,
           effect.key.effectIndex <= previousEffectIndex {
            return .failure(.noncontiguousChain)
        }
        let expectedOutput = Graph.TextureIdentity(
            kind: .effectOutput,
            layerID: layerID,
            effect: effect.key,
            name: nil
        )
        guard effect.output == expectedOutput, graph.finalOutput == expectedOutput,
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              graph.nodes.allSatisfy({ $0.effect == effect.key }) else {
            return .failure(.invalidEffectGraph)
        }
        guard graph.renderTargets.allSatisfy({ $0.conditions == nil }),
              graph.nodes.allSatisfy({ node in
                  node.conditions == nil
                      && node.bindings.allSatisfy { $0.conditions == nil }
              }) else { return .failure(.conditionNotPruned) }
        guard strictlyOrdered(graph.nodes.map(\.nodeIndex)),
              strictlyOrdered(graph.nodes.map(\.definitionPassIndex)),
              graph.nodes.allSatisfy({
                  $0.nodeIndex >= 0 && $0.definitionPassIndex >= 0
              }) else {
            return .failure(.invalidNodeOrder)
        }

        let framebufferIdentities = Set(graph.renderTargets.map(\.texture))
        guard framebufferIdentities.count == graph.renderTargets.count,
              framebufferIdentities.allSatisfy({ identity in
                  identity.kind == .framebuffer && identity.layerID == layerID
                      && identity.effect == effect.key
                      && identity.name?.isEmpty == false
              }) else { return .failure(.invalidEffectGraph) }

        var nodes: [ValidatedNode] = []
        var composeCount = 0
        var outputWriteCount = 0
        var outputComposeFlags: [Bool] = []
        var hasBoundaryWrite = false
        var previousMaterialOrdinal: Int?
        for node in graph.nodes {
            switch validateNode(
                node,
                effect: effect,
                framebuffers: framebufferIdentities
            ) {
            case let .success(validatedNode):
                if validatedNode.kind == .material {
                    guard let ordinal = node.materialOrdinal,
                          previousMaterialOrdinal.map({ ordinal > $0 }) ?? true else {
                        return .failure(.invalidNodeOrder)
                    }
                    previousMaterialOrdinal = ordinal
                }
                if validatedNode.writesFullFrame {
                    outputWriteCount += 1
                    outputComposeFlags.append(validatedNode.compose)
                    hasBoundaryWrite = true
                }
                if validatedNode.compose {
                    composeCount += 1
                    hasBoundaryWrite = false
                }
                nodes.append(validatedNode)
            case let .failure(failure):
                return .failure(failure)
            }
        }
        guard outputWriteCount > 0 else { return .failure(.missingEffectOutput) }
        guard hasBoundaryWrite,
              outputComposeFlags.last == false,
              outputComposeFlags.dropLast().allSatisfy({ $0 }) else {
            return .failure(.unwrittenBoundaryOutput)
        }
        return .success(.init(
            key: effect.key,
            inputIdentity: effect.input,
            outputIdentity: effect.output,
            composeTransitionCount: composeCount,
            fullFrameOutputWriteCount: outputWriteCount,
            nodes: nodes
        ))
    }

    private static func validateNode(
        _ node: Graph.Node,
        effect: Graph.Effect,
        framebuffers: Set<Graph.TextureIdentity>
    ) -> Result<ValidatedNode, Failure> {
        switch node.kind {
        case .material:
            guard node.commandSource == nil, node.commandTarget == nil,
                  let target = node.target else {
                return .failure(.invalidNodeShape)
            }
            let compose: Bool
            switch node.compose {
            case nil, .some(.bool(false)): compose = false
            case .some(.bool(true)): compose = true
            default: return .failure(.invalidCompose)
            }
            let writesFullFrame: Bool
            switch target.kind {
            case .effectOutput:
                guard target == effect.output else {
                    return .failure(.invalidFullFrameAccess)
                }
                writesFullFrame = true
            case .framebuffer:
                guard framebuffers.contains(target) else {
                    return .failure(.invalidNodeShape)
                }
                writesFullFrame = false
            case .layerSource, .unresolved:
                return .failure(.invalidFullFrameAccess)
            }
            guard !compose || writesFullFrame else {
                return .failure(.invalidCompose)
            }
            var readsFullFrame = false
            for binding in node.bindings {
                switch binding.texture.kind {
                case .layerSource, .effectOutput:
                    guard binding.texture == effect.input else {
                        return .failure(.invalidFullFrameAccess)
                    }
                    readsFullFrame = true
                case .framebuffer:
                    guard framebuffers.contains(binding.texture) else {
                        return .failure(.invalidNodeShape)
                    }
                case .unresolved:
                    return .failure(.invalidFullFrameAccess)
                }
            }
            return .success(.init(
                nodeIndex: node.nodeIndex,
                definitionPassIndex: node.definitionPassIndex,
                kind: .material,
                readsFullFrame: readsFullFrame,
                writesFullFrame: writesFullFrame,
                compose: compose
            ))
        case .copy, .swap:
            guard node.compose == nil, node.materialOrdinal == nil,
                  node.instancePassIndex == nil, node.materialPath == nil,
                  node.materialPassID == nil, node.target == nil,
                  node.bindings.isEmpty,
                  let source = node.commandSource,
                  let target = node.commandTarget,
                  source != target,
                  framebuffers.contains(source), framebuffers.contains(target) else {
                return .failure(node.compose == nil
                    ? .invalidNodeShape : .invalidCompose)
            }
            let kind: NodeKind
            switch node.kind {
            case .copy: kind = .copy
            case .swap: kind = .swap
            case .material, .unknownCommand:
                return .failure(.invalidNodeShape)
            }
            return .success(.init(
                nodeIndex: node.nodeIndex,
                definitionPassIndex: node.definitionPassIndex,
                kind: kind,
                readsFullFrame: false,
                writesFullFrame: false,
                compose: false
            ))
        case .unknownCommand:
            return .failure(.invalidNodeShape)
        }
    }

    private static func strictlyOrdered(_ values: [Int]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy(<)
    }
}
