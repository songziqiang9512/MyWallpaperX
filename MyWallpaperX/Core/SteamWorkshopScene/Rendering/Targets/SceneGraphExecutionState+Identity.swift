import Foundation

nonisolated private struct SceneGraphExecutionSignatureEnvelope: Encodable {
    let graph: SceneAuthoredEffectRenderPlan
    let plan: SceneGraphExecutionPlanSignature
}

nonisolated private struct SceneGraphExecutionPlanSignature: Encodable {
    struct Extent: Encodable {
        let width: Int
        let height: Int
    }

    struct Lifetime: Encodable {
        let firstWrite: Int
        let lastWrite: Int
        let firstRead: Int?
        let lastRead: Int?
        let requiresHistorySeed: Bool
    }

    struct LogicalTarget: Encodable {
        let identity: SceneAuthoredEffectRenderPlan.TextureIdentity
        let extent: Extent?
        let format: String?
        let addressMode: String?
        let isUnique: Bool?
        let lifetime: Lifetime
        let initialClear: [Double]?
    }

    struct Command: Encodable {
        let nodeIndex: Int
        let kind: String
        let source: SceneAuthoredEffectRenderPlan.TextureIdentity
        let target: SceneAuthoredEffectRenderPlan.TextureIdentity
    }

    let layerID: Int
    let input: SceneAuthoredEffectRenderPlan.TextureIdentity
    let output: SceneAuthoredEffectRenderPlan.TextureIdentity
    let inputRole: String
    let inputExtent: Extent?
    let logicalTargets: [LogicalTarget]
    let commands: [Command]

    init(
        _ plan: SceneGraphRenderTargetPlan,
        includeDescriptors: Bool
    ) {
        layerID = plan.layerID
        input = plan.input
        output = plan.output
        switch plan.inputRole {
        case .layerSource: inputRole = "layerSource"
        case .priorEffectOutput: inputRole = "priorEffectOutput"
        }
        inputExtent = includeDescriptors ? .init(
            width: plan.inputExtent.width,
            height: plan.inputExtent.height
        ) : nil
        logicalTargets = plan.logicalTargets.map { target in
            let clear = target.initialClear.map {
                [$0.red, $0.green, $0.blue, $0.alpha]
            }
            return .init(
                identity: target.identity,
                extent: includeDescriptors ? .init(
                    width: target.extent.width,
                    height: target.extent.height
                ) : nil,
                format: includeDescriptors ? target.format.rawValue : nil,
                addressMode: includeDescriptors ? target.addressMode.rawValue : nil,
                isUnique: includeDescriptors ? target.isUnique : nil,
                lifetime: .init(
                    firstWrite: target.lifetime.firstWriteNodeIndex,
                    lastWrite: target.lifetime.lastWriteNodeIndex,
                    firstRead: target.lifetime.firstReadNodeIndex,
                    lastRead: target.lifetime.lastReadNodeIndex,
                    requiresHistorySeed: target.lifetime.requiresHistorySeed
                ),
                initialClear: includeDescriptors ? clear : nil
            )
        }
        commands = plan.commands.map {
            .init(
                nodeIndex: $0.nodeIndex, kind: $0.kind.rawValue,
                source: $0.source, target: $0.target
            )
        }
    }
}

nonisolated extension SceneGraphExecutionState {
    struct PersistentProjection {
        let mapping: [Identity: VersionedResource]
        let initialized: Set<PhysicalToken>
    }

    struct ExecutionSignatures {
        let topology: Data
        let complete: Data
    }

    static func executionSignatures(
        graph: Graph,
        plan: Plan
    ) -> ExecutionSignatures? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let topology = try? encoder.encode(
            SceneGraphExecutionSignatureEnvelope(
                graph: graph,
                plan: .init(plan, includeDescriptors: false)
            )
        ), let complete = try? encoder.encode(
            SceneGraphExecutionSignatureEnvelope(
                graph: graph,
                plan: .init(plan, includeDescriptors: true)
            )
        ) else { return nil }
        return .init(topology: topology, complete: complete)
    }

    static func generationsDoNotRegress(
        effect: UInt64,
        reset: UInt64,
        allocation: UInt64,
        from previous: Self
    ) -> Bool {
        guard allocation > 0 else { return false }
        if let generation = previous.effectGeneration, effect < generation {
            return false
        }
        if let generation = previous.resetGeneration, reset < generation {
            return false
        }
        let effectAdvanced = previous.effectGeneration.map { effect > $0 } ?? true
        let resetAdvanced = previous.resetGeneration.map { reset > $0 } ?? true
        if !effectAdvanced, !resetAdvanced,
           let generation = previous.allocationGeneration,
           allocation < generation {
            return false
        }
        return true
    }

    static func advanced(
        _ resource: VersionedResource,
        generation: inout UInt64
    ) -> VersionedResource? {
        guard generation < UInt64.max else { return nil }
        generation += 1
        return .init(
            token: resource.token,
            descriptor: resource.descriptor,
            contentGeneration: generation
        )
    }

    static func mappingIsPermutation(
        _ mapping: [Identity: VersionedResource],
        of authored: [Identity: Resource]
    ) -> Bool {
        guard Set(mapping.keys) == Set(authored.keys),
              Set(mapping.values.map(\.token)) == Set(authored.values.map(\.token)) else {
            return false
        }
        var descriptorByToken: [PhysicalToken: ResourceDescriptor] = [:]
        for resource in authored.values {
            guard descriptorByToken.updateValue(
                resource.descriptor,
                forKey: resource.token
            ) == nil else { return false }
        }
        return mapping.values.allSatisfy {
            descriptorByToken[$0.token] == $0.descriptor
        }
    }

    static func rebase(
        _ mapping: [Identity: VersionedResource],
        from oldAuthored: [Identity: Resource],
        to newAuthored: [Identity: Resource],
        rehydrating historyRehydration: [PhysicalToken: PhysicalToken]
    ) -> [Identity: VersionedResource]? {
        var oldSlotByToken: [PhysicalToken: Identity] = [:]
        for (identity, resource) in oldAuthored {
            guard oldSlotByToken.updateValue(identity, forKey: resource.token) == nil else {
                return nil
            }
        }
        var result: [Identity: VersionedResource] = [:]
        for (logical, resource) in mapping {
            guard let authoredSlot = oldSlotByToken[resource.token],
                  let replacement = newAuthored[authoredSlot] else {
                return nil
            }
            let preservesContent = historyRehydration[resource.token]
                == replacement.token
            result[logical] = replacement.versioned(
                preservesContent ? resource.contentGeneration : 0
            )
        }
        return result
    }

    static func persistentProjection(
        mapping: [Identity: VersionedResource],
        initialized: Set<PhysicalToken>,
        historyClosure: Set<Identity>
    ) -> PersistentProjection {
        var projected = mapping
        for (identity, resource) in mapping where !historyClosure.contains(identity) {
            projected[identity] = .init(
                token: resource.token,
                descriptor: resource.descriptor,
                contentGeneration: 0
            )
        }
        let retained = Set<PhysicalToken>(projected.compactMap { identity, resource in
            guard initialized.contains(resource.token) else { return nil }
            if historyClosure.contains(identity) {
                return resource.contentGeneration > 0 ? resource.token : nil
            }
            return resource.descriptor.initialClear == nil ? nil : resource.token
        })
        return .init(mapping: projected, initialized: retained)
    }
}
