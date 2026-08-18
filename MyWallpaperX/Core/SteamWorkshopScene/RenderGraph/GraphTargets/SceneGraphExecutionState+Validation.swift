import Foundation

nonisolated private struct SceneGraphObservedLifetime {
    var firstWrite: Int?
    var lastWrite: Int?
    var firstRead: Int?
    var lastRead: Int?
}

nonisolated extension SceneGraphExecutionState {
    enum Operation {
        case material(Graph.Node)
        case copy(Graph.Node, ordinal: Int)
        case swap(Graph.Node, ordinal: Int)
    }

    static func compile(
        graph: Graph,
        targetPlan: Plan,
        pairStep: PairStep
    ) -> Result<[Operation], Failure> {
        if let blocker = graph.blockers.first {
            switch blocker.reason {
            case .unsupportedCondition: return .failure(.conditionUnavailable)
            case .unsupportedFunctions: return .failure(.functionUnavailable)
            case .unsupportedCompose: return .failure(.composeUnproven)
            case .unknownCommand: return .failure(.unknownOperation)
            default: return .failure(.graphBlocked)
            }
        }
        guard graph.effects.count == 1,
              let effect = graph.effects.first,
              graph.layerID == targetPlan.layerID,
              effect.input == targetPlan.input,
              effect.output == targetPlan.output,
              graph.finalOutput == targetPlan.output,
              pairStep.effect == effect.key,
              pairStep.inputIdentity == effect.input,
              pairStep.outputIdentity == effect.output,
              SceneAuthoredEffectInputValidator.accepts(
                  targetPlan.input,
                  layerID: targetPlan.layerID,
                  role: targetPlan.inputRole
              ),
              effect.nodeIndices == graph.nodes.map(\.nodeIndex),
              graph.nodes.allSatisfy({ $0.effect == effect.key }),
              graph.nodes.count == pairStep.nodes.count else {
            return .failure(.invalidTopology)
        }
        guard graph.renderTargets.allSatisfy({ $0.conditions == nil }),
              graph.nodes.allSatisfy({ node in
                  node.conditions == nil
                      && node.bindings.allSatisfy { $0.conditions == nil }
              }) else { return .failure(.conditionUnavailable) }

        let framebuffers = Set(targetPlan.logicalTargets.map(\.identity))
        var previousMaterialOrdinal: Int?
        var commandOrdinal = 0
        var composeCount = 0
        var outputWriteCount = 0
        var lastOutputWrite: SceneLayerFullFramePairPlan.Member?
        var current = pairStep.inputMember
        var operations: [Operation] = []

        for (node, pairNode) in zip(graph.nodes, pairStep.nodes) {
            guard pairNode.nodeIndex == node.nodeIndex,
                  pairNode.definitionPassIndex == node.definitionPassIndex,
                  pairNode.currentMemberBeforeNode == current else {
                return .failure(.pairStepMismatch)
            }
            switch node.kind {
            case .material:
                guard pairNode.kind == .material,
                      let materialOrdinal = node.materialOrdinal,
                      materialOrdinal >= 0,
                      previousMaterialOrdinal.map({ materialOrdinal > $0 }) ?? true,
                      let target = node.target,
                      node.commandSource == nil,
                      node.commandTarget == nil else {
                    return .failure(.ordinalMismatch)
                }
                let slots = node.bindings.compactMap(\.slot)
                guard slots.count == node.bindings.count,
                      slots.allSatisfy({ (0 ... 7).contains($0) }),
                      Set(slots).count == slots.count else {
                    return .failure(.descriptorMismatch)
                }
                let compose: Bool
                switch node.compose {
                case nil, .some(.bool(false)): compose = false
                case .some(.bool(true)): compose = true
                default: return .failure(.composeUnproven)
                }
                var readsFullFrame = false
                for binding in node.bindings {
                    switch binding.texture.kind {
                    case .framebuffer:
                        guard framebuffers.contains(binding.texture) else {
                            return .failure(.missingIdentity)
                        }
                    case .layerSource, .effectOutput:
                        guard binding.texture == effect.input else {
                            return .failure(.invalidTopology)
                        }
                        readsFullFrame = true
                    case .unresolved:
                        return .failure(.missingIdentity)
                    }
                }
                let writesFullFrame: Bool
                switch target.kind {
                case .framebuffer:
                    guard framebuffers.contains(target), !compose else {
                        return .failure(.composeUnproven)
                    }
                    writesFullFrame = false
                case .effectOutput:
                    guard target == effect.output else {
                        return .failure(.invalidTopology)
                    }
                    writesFullFrame = true
                case .layerSource, .unresolved:
                    return .failure(.invalidTopology)
                }
                guard !compose || writesFullFrame else {
                    return .failure(.composeUnproven)
                }
                let expectedRead = readsFullFrame ? current : nil
                let expectedWrite = writesFullFrame ? current.opposite : nil
                let expectedAfter = compose ? expectedWrite : current
                guard pairNode.fullFrameReadMember == expectedRead,
                      pairNode.fullFrameWriteMember == expectedWrite,
                      pairNode.rotatesAfterNode == compose,
                      pairNode.currentMemberAfterNode == expectedAfter,
                      let next = expectedAfter else {
                    return .failure(.pairStepMismatch)
                }
                if writesFullFrame {
                    outputWriteCount += 1
                    lastOutputWrite = expectedWrite
                }
                if compose { composeCount += 1 }
                current = next
                operations.append(.material(node))
                previousMaterialOrdinal = materialOrdinal

            case .copy, .swap:
                let expectedKind: SceneLayerFullFramePairPlan.NodeKind =
                    node.kind == .copy ? .copy : .swap
                guard pairNode.kind == expectedKind,
                      pairNode.fullFrameReadMember == nil,
                      pairNode.fullFrameWriteMember == nil,
                      !pairNode.rotatesAfterNode,
                      pairNode.currentMemberAfterNode == current,
                      node.compose == nil || node.compose == .bool(false),
                      node.materialOrdinal == nil,
                      node.target == nil,
                      node.bindings.isEmpty,
                      let source = node.commandSource,
                      let target = node.commandTarget,
                      source != target,
                      source.kind == .framebuffer,
                      target.kind == .framebuffer,
                      framebuffers.contains(source),
                      framebuffers.contains(target),
                      targetPlan.commands.indices.contains(commandOrdinal) else {
                    return .failure(.pairStepMismatch)
                }
                let planned = targetPlan.commands[commandOrdinal]
                let commandKind: Plan.CommandKind = node.kind == .copy ? .copy : .swap
                guard planned.nodeIndex == node.nodeIndex,
                      planned.kind == commandKind,
                      planned.source == source,
                      planned.target == target else {
                    return .failure(.descriptorMismatch)
                }
                operations.append(node.kind == .copy
                    ? .copy(node, ordinal: commandOrdinal)
                    : .swap(node, ordinal: commandOrdinal))
                commandOrdinal += 1

            case .unknownCommand:
                return .failure(.unknownOperation)
            }
        }
        guard commandOrdinal == targetPlan.commands.count else {
            return .failure(.descriptorMismatch)
        }
        guard outputWriteCount == pairStep.fullFrameOutputWriteCount,
              composeCount == pairStep.composeTransitionCount,
              outputWriteCount > 0,
              lastOutputWrite == pairStep.outputMember,
              pairStep.outputMember == current.opposite else {
            return .failure(.pairStepMismatch)
        }
        return .success(operations)
    }

    static func validateAllocation(
        graph: Graph,
        plan: Plan,
        allocation: Allocation,
        materialFunctionTargets: Set<Identity> = []
    ) -> Result<Void, Failure> {
        let required = Set(plan.logicalTargets.map(\.identity))
        guard required.count == plan.logicalTargets.count,
              required.allSatisfy({ $0.kind == .framebuffer }),
              !required.contains(plan.input),
              !required.contains(plan.output),
              Set(allocation.resources.keys) == required else {
            return .failure(.missingIdentity)
        }
        var expected: [Identity: ResourceDescriptor] = [:]
        for logical in plan.logicalTargets {
            expected[logical.identity] = .init(
                extent: logical.extent,
                format: logical.format,
                addressMode: logical.addressMode,
                isUnique: logical.isUnique,
                initialClear: logical.initialClear
            )
        }
        guard plan.matchesSourceDeclarations(in: graph),
              allocation.resources.allSatisfy({
                  expected[$0.key] == $0.value.descriptor
              }),
              lifetimesMatch(
                  graph: graph,
                  plan: plan,
                  materialFunctionTargets: materialFunctionTargets
              ) else {
            return .failure(.descriptorMismatch)
        }
        for command in plan.commands {
            guard command.source != command.target,
                  let source = expected[command.source],
                  let target = expected[command.target],
                  source.extent == target.extent,
                  source.format == target.format else {
                return .failure(.descriptorMismatch)
            }
            if command.kind == .swap, source != target {
                return .failure(.descriptorMismatch)
            }
        }
        let tokens = allocation.resources.values.map(\.token)
        guard tokens.allSatisfy({
            !$0.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return .failure(.missingIdentity) }
        guard Set(tokens).count == tokens.count else {
            return .failure(.physicalAlias)
        }
        return .success(())
    }

    static func lifetimesMatch(
        graph: Graph,
        plan: Plan,
        materialFunctionTargets: Set<Identity> = []
    ) -> Bool {
        var observed = Dictionary(uniqueKeysWithValues: plan.logicalTargets.map {
            ($0.identity, SceneGraphObservedLifetime())
        })
        func recordRead(_ identity: Identity, at index: Int) {
            guard var value = observed[identity] else { return }
            value.firstRead = value.firstRead ?? index
            value.lastRead = index
            observed[identity] = value
        }
        func recordWrite(_ identity: Identity, at index: Int) {
            guard var value = observed[identity] else { return }
            value.firstWrite = value.firstWrite ?? index
            value.lastWrite = index
            observed[identity] = value
        }
        guard materialFunctionTargets.allSatisfy({ observed[$0] != nil }) else {
            return false
        }
        if let firstNodeIndex = graph.nodes.first?.nodeIndex {
            materialFunctionTargets.forEach {
                recordWrite($0, at: firstNodeIndex)
            }
        }
        for node in graph.nodes {
            switch node.kind {
            case .material:
                node.bindings.forEach { recordRead($0.texture, at: node.nodeIndex) }
                if let target = node.target { recordWrite(target, at: node.nodeIndex) }
            case .copy:
                if let source = node.commandSource { recordRead(source, at: node.nodeIndex) }
                if let target = node.commandTarget { recordWrite(target, at: node.nodeIndex) }
            case .swap:
                if let source = node.commandSource {
                    recordRead(source, at: node.nodeIndex)
                    recordWrite(source, at: node.nodeIndex)
                }
                if let target = node.commandTarget {
                    recordRead(target, at: node.nodeIndex)
                    recordWrite(target, at: node.nodeIndex)
                }
            case .unknownCommand: return false
            }
        }
        return plan.logicalTargets.allSatisfy { target in
            guard let value = observed[target.identity],
                  let firstWrite = value.firstWrite,
                  let lastWrite = value.lastWrite else { return false }
            let canRequireHistory = value.firstRead.map { $0 <= firstWrite } ?? false
            return target.lifetime.firstWriteNodeIndex == firstWrite
                && target.lifetime.lastWriteNodeIndex == lastWrite
                && target.lifetime.firstReadNodeIndex == value.firstRead
                && target.lifetime.lastReadNodeIndex == value.lastRead
                && (!target.lifetime.requiresHistorySeed || canRequireHistory)
        }
    }

    static func historyClosure(in plan: Plan) -> Set<Identity>? {
        let identities = plan.logicalTargets.map(\.identity)
        var permutation = Dictionary(uniqueKeysWithValues: identities.map { ($0, $0) })
        for command in plan.commands where command.kind == .swap {
            guard let source = permutation[command.source],
                  let target = permutation[command.target] else { return nil }
            permutation[command.source] = target
            permutation[command.target] = source
        }
        var result = Set<Identity>()
        for target in plan.logicalTargets where target.lifetime.requiresHistorySeed {
            var identity = target.identity
            while result.insert(identity).inserted {
                guard let next = permutation[identity] else { return nil }
                identity = next
            }
        }
        return result
    }

    static func validHistoryRehydration(
        _ values: [PhysicalToken: PhysicalToken],
        closure: Set<Identity>,
        previous: Self,
        allocation: Allocation,
        reset: Bool,
        freshAllocation: Bool
    ) -> Bool {
        guard !values.isEmpty else { return true }
        guard freshAllocation, !reset,
              Set(values.values).count == values.count else { return false }
        let allowedSources = Set(closure.compactMap {
            previous.authoredResources[$0]?.token
        })
        let oldSlotByToken = Dictionary(uniqueKeysWithValues:
            previous.authoredResources.map { ($0.value.token, $0.key) }
        )
        for (source, target) in values {
            guard source != target,
                  allowedSources.contains(source),
                  let slot = oldSlotByToken[source],
                  let old = previous.authoredResources[slot],
                  let replacement = allocation.resources[slot],
                  replacement.token == target,
                  replacement.descriptor == old.descriptor,
                  previous.initializedPhysicalTokens.contains(source),
                  previous.logicalMapping.values.contains(where: {
                      $0.token == source && $0.contentGeneration > 0
                  }) else { return false }
        }
        return true
    }

    static func freshAllocationReusesToken(
        previous: Self,
        allocation: Allocation
    ) -> Bool {
        !Set(previous.authoredResources.values.map(\.token)).isDisjoint(
            with: Set(allocation.resources.values.map(\.token))
        )
    }

    static func targetOrder(_ lhs: Plan.LogicalTarget, _ rhs: Plan.LogicalTarget) -> Bool {
        identityOrder(lhs.identity) < identityOrder(rhs.identity)
    }

    static func identityOrder(_ value: Identity) -> String {
        "\(value.layerID):\(value.effect?.effectIndex ?? -1):"
            + "\(value.effect?.descriptorID ?? ""):\(value.kind.rawValue):\(value.name ?? "")"
    }
}
