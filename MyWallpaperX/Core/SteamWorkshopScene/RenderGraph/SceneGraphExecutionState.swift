import Foundation

/// Pure authored-FBO state reduction for one admitted effect.
/// The layer full-frame pair is validated by `pairStep` but is never allocated,
/// versioned, or published by this persistent state.
nonisolated struct SceneGraphExecutionState: Equatable {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Plan = SceneGraphRenderTargetPlan
    typealias PairStep = SceneLayerFullFramePairPlan.EffectStep
    typealias Identity = Graph.TextureIdentity

    static let maximumNodeCount = 512
    static let maximumLogicalBindingCount = 512

    struct PhysicalToken: Hashable { let rawValue: String }

    struct ResourceDescriptor: Equatable {
        let extent: Plan.PixelExtent
        let format: Plan.TextureFormat
        let isUnique: Bool
        let initialClear: Plan.ClearColor?
    }

    struct Resource: Equatable {
        let token: PhysicalToken
        let descriptor: ResourceDescriptor

        func versioned(_ generation: UInt64 = 0) -> VersionedResource {
            .init(token: token, descriptor: descriptor, contentGeneration: generation)
        }
    }

    struct VersionedResource: Equatable {
        let token: PhysicalToken
        let descriptor: ResourceDescriptor
        let contentGeneration: UInt64
    }

    /// Contains exactly `targetPlan.logicalTargets`; full-frame pair members are
    /// owned by the layer chain allocation and are deliberately absent here.
    struct Allocation: Equatable {
        let generation: UInt64
        let resources: [Identity: Resource]
    }

    enum InitializationReason: Equatable {
        case authoredClear(Plan.ClearColor)
        case transparentHistorySeed
    }

    struct MaterialBinding: Equatable {
        let slot: Int
        let identity: Identity
        let resource: VersionedResource
    }

    struct MaterialTarget: Equatable {
        let identity: Identity
        let resource: VersionedResource
    }

    /// Every resource carried by an intent is an authored framebuffer. Pair
    /// reads/writes are supplied separately by the matching pair-plan node.
    enum Intent: Equatable {
        case initialize(
            identity: Identity,
            resource: VersionedResource,
            reason: InitializationReason
        )
        case material(
            nodeIndex: Int,
            materialOrdinal: Int,
            bindings: [MaterialBinding],
            target: MaterialTarget?
        )
        case copy(
            nodeIndex: Int,
            commandOrdinal: Int,
            source: Identity,
            sourceResource: VersionedResource,
            target: Identity,
            targetResource: VersionedResource
        )
        case swap(
            nodeIndex: Int,
            commandOrdinal: Int,
            source: Identity,
            sourceResource: VersionedResource,
            target: Identity,
            targetResource: VersionedResource
        )
    }

    struct Transaction: Equatable {
        let intents: [Intent]
        let mappingBefore: [Identity: VersionedResource]
        let mappingAfter: [Identity: VersionedResource]
        let allocationGeneration: UInt64
        let effectGeneration: UInt64
        let resetGeneration: UInt64
    }

    /// A candidate is a pure value. Callers commit `nextState` only after all
    /// required rehydration and effect GPU work has completed successfully.
    struct Transition: Equatable {
        let nextState: SceneGraphExecutionState
        let transaction: Transaction
    }

    enum Failure: String, Error {
        case graphBlocked, conditionUnavailable, functionUnavailable
        case composeUnproven, unknownOperation, invalidTopology, ordinalMismatch
        case pairStepMismatch, executionEvidenceCapacityExceeded
        case missingIdentity, descriptorMismatch, physicalAlias
        case readBeforeWrite, readWriteHazard
        case allocationGenerationMismatch, freshAllocationTokenReuse
        case historyRehydrationMismatch, stateMismatch
        case generationRegression, contentGenerationOverflow
    }

    let effectGeneration: UInt64?
    let resetGeneration: UInt64?
    let allocationGeneration: UInt64?
    let authoredResources: [Identity: Resource]
    let logicalMapping: [Identity: VersionedResource]
    let initializedPhysicalTokens: Set<PhysicalToken>
    let historyLogicalIdentities: Set<Identity>
    let historyClosureIdentities: Set<Identity>
    let lastContentGeneration: UInt64
    private let topologySignature: Data?
    private let planSignature: Data?

    static let empty = Self(
        effectGeneration: nil, resetGeneration: nil, allocationGeneration: nil,
        authoredResources: [:], logicalMapping: [:],
        initializedPhysicalTokens: [], historyLogicalIdentities: [],
        historyClosureIdentities: [], lastContentGeneration: 0,
        topologySignature: nil, planSignature: nil
    )

    static func reduce(
        graph: Graph,
        targetPlan: Plan,
        pairStep: PairStep,
        allocation: Allocation,
        effectGeneration: UInt64,
        resetGeneration: UInt64,
        previous: Self = .empty,
        historyRehydration: [PhysicalToken: PhysicalToken] = [:]
    ) -> Result<Transition, Failure> {
        guard graph.nodes.count <= maximumNodeCount,
              targetPlan.logicalTargets.count <= maximumLogicalBindingCount else {
            return .failure(.executionEvidenceCapacityExceeded)
        }
        let operations: [Operation]
        switch compile(graph: graph, targetPlan: targetPlan, pairStep: pairStep) {
        case .failure(let failure): return .failure(failure)
        case .success(let value): operations = value
        }
        switch validateAllocation(graph: graph, plan: targetPlan, allocation: allocation) {
        case .failure(let failure): return .failure(failure)
        case .success: break
        }
        guard generationsDoNotRegress(
            effect: effectGeneration,
            reset: resetGeneration,
            allocation: allocation.generation,
            from: previous
        ) else { return .failure(.generationRegression) }
        guard let signatures = executionSignatures(graph: graph, plan: targetPlan),
              let historyClosure = historyClosure(in: targetPlan) else {
            return .failure(.stateMismatch)
        }

        let reparsed = previous.effectGeneration != effectGeneration
            || previous.allocationGeneration == nil
        let reset = reparsed || previous.resetGeneration != resetGeneration
        let allocationChanged = previous.allocationGeneration != allocation.generation
        let freshAllocation = !reset && allocationChanged
        if allocationChanged,
           freshAllocationReusesToken(previous: previous, allocation: allocation) {
            return .failure(.freshAllocationTokenReuse)
        }
        if previous.allocationGeneration != nil,
           allocationChanged,
           !allocation.resources.isEmpty,
           previous.authoredResources == allocation.resources {
            return .failure(.allocationGenerationMismatch)
        }
        if !reset, !allocationChanged,
           previous.authoredResources != allocation.resources {
            return .failure(.allocationGenerationMismatch)
        }
        if !reparsed, previous.topologySignature != signatures.topology {
            return .failure(.stateMismatch)
        }
        if !reparsed, !allocationChanged,
           previous.planSignature != signatures.complete {
            return .failure(.stateMismatch)
        }

        let history = Set(targetPlan.logicalTargets.compactMap {
            $0.lifetime.requiresHistorySeed ? $0.identity : nil
        })
        guard reset || (
            previous.historyLogicalIdentities == history
                && previous.historyClosureIdentities == historyClosure
        ) else { return .failure(.stateMismatch) }
        guard validHistoryRehydration(
            historyRehydration,
            closure: historyClosure,
            previous: previous,
            allocation: allocation,
            reset: reset,
            freshAllocation: freshAllocation
        ) else { return .failure(.historyRehydrationMismatch) }

        let mapping: [Identity: VersionedResource]
        if reset {
            mapping = allocation.resources.mapValues { $0.versioned() }
        } else if freshAllocation {
            guard let rebased = rebase(
                previous.logicalMapping,
                from: previous.authoredResources,
                to: allocation.resources,
                rehydrating: historyRehydration
            ) else { return .failure(.stateMismatch) }
            mapping = rebased
        } else {
            mapping = previous.logicalMapping
        }
        guard mappingIsPermutation(mapping, of: allocation.resources) else {
            return .failure(.stateMismatch)
        }

        var initialized = reset ? Set<PhysicalToken>()
            : freshAllocation ? Set(historyRehydration.values)
            : previous.initializedPhysicalTokens
        var currentMapping = mapping
        var contentGeneration = previous.lastContentGeneration
        var intents: [Intent] = []
        var readableTokens = initialized

        for target in targetPlan.logicalTargets.sorted(by: targetOrder) {
            guard let current = currentMapping[target.identity] else {
                return .failure(.missingIdentity)
            }
            let reason = target.initialClear.map(InitializationReason.authoredClear)
                ?? (target.lifetime.requiresHistorySeed
                    ? .transparentHistorySeed : nil)
            if let reason, !initialized.contains(current.token) {
                guard let initializedResource = advanced(
                    current,
                    generation: &contentGeneration
                ) else { return .failure(.contentGenerationOverflow) }
                currentMapping[target.identity] = initializedResource
                initialized.insert(initializedResource.token)
                readableTokens.insert(initializedResource.token)
                intents.append(.initialize(
                    identity: target.identity,
                    resource: initializedResource,
                    reason: reason
                ))
            }
        }

        for operation in operations {
            switch operation {
            case .material(let node):
                var bindings: [MaterialBinding] = []
                for binding in node.bindings.sorted(by: {
                    ($0.slot ?? Int.max) < ($1.slot ?? Int.max)
                }) where binding.texture.kind == .framebuffer {
                    guard let slot = binding.slot,
                          let resource = currentMapping[binding.texture] else {
                        return .failure(.missingIdentity)
                    }
                    guard resource.contentGeneration > 0,
                          readableTokens.contains(resource.token) else {
                        return .failure(.readBeforeWrite)
                    }
                    bindings.append(.init(
                        slot: slot,
                        identity: binding.texture,
                        resource: resource
                    ))
                }
                let target: MaterialTarget?
                if let identity = node.target, identity.kind == .framebuffer {
                    guard let current = currentMapping[identity] else {
                        return .failure(.missingIdentity)
                    }
                    guard bindings.allSatisfy({ $0.resource.token != current.token }) else {
                        return .failure(.readWriteHazard)
                    }
                    guard let written = advanced(
                        current,
                        generation: &contentGeneration
                    ) else { return .failure(.contentGenerationOverflow) }
                    currentMapping[identity] = written
                    initialized.insert(written.token)
                    readableTokens.insert(written.token)
                    target = .init(identity: identity, resource: written)
                } else {
                    target = nil
                }
                guard let ordinal = node.materialOrdinal else {
                    return .failure(.ordinalMismatch)
                }
                intents.append(.material(
                    nodeIndex: node.nodeIndex,
                    materialOrdinal: ordinal,
                    bindings: bindings,
                    target: target
                ))
            case .copy(let node, let ordinal):
                guard let source = node.commandSource,
                      let target = node.commandTarget,
                      let sourceResource = currentMapping[source],
                      let currentTarget = currentMapping[target] else {
                    return .failure(.missingIdentity)
                }
                guard sourceResource.contentGeneration > 0,
                      readableTokens.contains(sourceResource.token) else {
                    return .failure(.readBeforeWrite)
                }
                guard let targetResource = advanced(
                    currentTarget,
                    generation: &contentGeneration
                ) else { return .failure(.contentGenerationOverflow) }
                currentMapping[target] = targetResource
                initialized.insert(targetResource.token)
                readableTokens.insert(targetResource.token)
                intents.append(.copy(
                    nodeIndex: node.nodeIndex,
                    commandOrdinal: ordinal,
                    source: source,
                    sourceResource: sourceResource,
                    target: target,
                    targetResource: targetResource
                ))
            case .swap(let node, let ordinal):
                guard let source = node.commandSource,
                      let target = node.commandTarget,
                      let sourceResource = currentMapping[source],
                      let targetResource = currentMapping[target] else {
                    return .failure(.missingIdentity)
                }
                guard sourceResource.contentGeneration > 0,
                      targetResource.contentGeneration > 0,
                      readableTokens.contains(sourceResource.token),
                      readableTokens.contains(targetResource.token) else {
                    return .failure(.readBeforeWrite)
                }
                intents.append(.swap(
                    nodeIndex: node.nodeIndex,
                    commandOrdinal: ordinal,
                    source: source,
                    sourceResource: sourceResource,
                    target: target,
                    targetResource: targetResource
                ))
                currentMapping[source] = targetResource
                currentMapping[target] = sourceResource
            }
        }

        let projection = persistentProjection(
            mapping: currentMapping,
            initialized: initialized,
            historyClosure: historyClosure
        )
        let next = Self(
            effectGeneration: effectGeneration,
            resetGeneration: resetGeneration,
            allocationGeneration: allocation.generation,
            authoredResources: allocation.resources,
            logicalMapping: projection.mapping,
            initializedPhysicalTokens: projection.initialized,
            historyLogicalIdentities: history,
            historyClosureIdentities: historyClosure,
            lastContentGeneration: contentGeneration,
            topologySignature: signatures.topology,
            planSignature: signatures.complete
        )
        return .success(.init(
            nextState: next,
            transaction: .init(
                intents: intents,
                mappingBefore: mapping,
                mappingAfter: currentMapping,
                allocationGeneration: allocation.generation,
                effectGeneration: effectGeneration,
                resetGeneration: resetGeneration
            )
        ))
    }
}
