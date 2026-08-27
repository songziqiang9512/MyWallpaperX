import Foundation

/// Scene-lifetime catalog of executable material nodes. Templates and resource
/// demands are compiled only after graph condition/function admission succeeds.
nonisolated struct SceneResolvedMaterialRuntimeCatalog {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate
    typealias Failure = SceneResolvedMaterialFailure
    typealias AdmissionCandidate =
        SceneResolvedMaterialExecutionCapabilityAdmission.Candidate

    struct Key: Hashable {
        let effect: Graph.EffectKey
        let nodeIndex: Int

        var reportToken: String {
            "\(effect.layerID):\(effect.effectIndex):"
                + "\(effect.descriptorID.utf8.count)#\(effect.descriptorID):\(nodeIndex)"
        }
    }

    enum Entry {
        case template(Template)
        case failure(Failure)
    }

    struct ResourceDemandIssue: Hashable {
        enum Code: String {
            case samplerSchemaUnavailable = "sampler-schema-unavailable"
            case purposeUnproven = "texture-purpose-unproven"
        }

        enum Reference: Hashable {
            case asset(SceneVFSAssetPath)
            case userProperty(String)
            case system(String)

            var kind: String {
                switch self {
                case .asset: "asset"
                case .userProperty: "user-property"
                case .system: "system"
                }
            }

            var reportValue: String {
                switch self {
                case let .asset(path): "asset:\(path.value)"
                case let .userProperty(key): "user-property:\(key)"
                case let .system(name): "system:\(name)"
                }
            }
        }

        let key: Key
        let slot: Int
        let reference: Reference
        let code: Code
    }

    struct SystemProviderDemand: Hashable {
        let name: String
        let purpose: SceneTextureLoadPurpose
    }

    /// Resource-demand reachability is a shader/template property, not a
    /// material-node identity property. Authored graphs commonly instantiate
    /// the same material many times; analyzing every node separately turns
    /// launch into repeated preprocessing of identical shader variants.
    private enum ResourceDemandReferenceKind: Hashable {
        case asset
        case userProperty
        case provider
        case graph
    }

    private struct ResourceDemandTextureSlotShape: Hashable {
        let index: Int
        let references: [ResourceDemandReferenceKind]
    }

    private struct ResourceDemandAnalysisKey: Hashable {
        let shaderIdentity: String
        let shaderCanonicalSHA256: String
        let textureSlots: [ResourceDemandTextureSlotShape?]
        let combos: [Template.Combo]
        let inheritedInactiveCombos: [String]
        let uniformDeclarations: [Template.UniformDeclaration]
        let hasImplicitFramebuffer: Bool

        init(
            template: Template,
            implicitFramebufferIdentity: Graph.TextureIdentity?
        ) {
            shaderIdentity = template.shaderContract.identity
            shaderCanonicalSHA256 = template.shaderContract.canonicalSHA256
            textureSlots = template.textureSlots.map { slot in
                slot.map {
                    ResourceDemandTextureSlotShape(
                        index: $0.index,
                        references: $0.candidates.map { candidate in
                            switch candidate.reference {
                            case .asset: .asset
                            case .userProperty: .userProperty
                            case .provider: .provider
                            case .graph: .graph
                            }
                        }
                    )
                }
            }
            combos = template.combos
            inheritedInactiveCombos = template.inheritedInactiveCombos
            uniformDeclarations = template.uniformDeclarations
            hasImplicitFramebuffer = implicitFramebufferIdentity != nil
        }
    }

    private enum ResourceDemandAnalysis {
        case ready(
            textureFormatSlots: Set<Int>,
            samplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>]
        )
        case failed(String)
    }

    private final class ResourceDemandAnalysisCache: @unchecked Sendable {
        private enum Entry {
            case preparing
            case ready(ResourceDemandAnalysis)
        }

        private let condition = NSCondition()
        private var entries: [ResourceDemandAnalysisKey: Entry] = [:]

        func result(
            for key: ResourceDemandAnalysisKey,
            prepare: () -> ResourceDemandAnalysis
        ) -> ResourceDemandAnalysis {
            condition.lock()
            while true {
                switch entries[key] {
                case let .ready(result):
                    condition.unlock()
                    return result
                case .preparing:
                    condition.wait()
                case nil:
                    entries[key] = .preparing
                    condition.unlock()
                    let result = prepare()
                    condition.lock()
                    entries[key] = .ready(result)
                    condition.broadcast()
                    condition.unlock()
                    return result
                }
            }
        }
    }

    private struct CompilationOutcome {
        let key: Key
        let entry: Entry
        let assetDemands: Set<SceneAssetTextureIdentity>
        let userPropertyDemands: Set<SceneUserPropertyTextureIdentity>
        let systemProviderDemands: Set<SystemProviderDemand>
        let issues: Set<ResourceDemandIssue>
    }

    let entries: [Key: Entry]
    let assetDemands: Set<SceneAssetTextureIdentity>
    let userPropertyDemands: Set<SceneUserPropertyTextureIdentity>
    let systemProviderDemands: Set<SystemProviderDemand>
    let resourceDemandIssues: Set<ResourceDemandIssue>

    init(
        descriptor: SceneRenderDescriptor,
        admissionCandidates: [AdmissionCandidate],
        shaderContracts: [SceneShaderContract],
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer>,
        provenSceneScriptValueTargets: Set<SceneDynamicTarget> = []
    ) {
        var records: [Key: [(graph: Graph, node: Graph.Node)]] = [:]
        for candidate in admissionCandidates {
            guard case let .success(admitted) = candidate.result else { continue }
            for product in admitted.products {
                for node in product.graph.nodes where node.kind == .material {
                    records[
                        Key(effect: node.effect, nodeIndex: node.nodeIndex),
                        default: []
                    ].append((product.graph, node))
                }
            }
        }

        var compiled: [Key: Entry] = [:]
        var demands: Set<SceneAssetTextureIdentity> = []
        var userDemands: Set<SceneUserPropertyTextureIdentity> = []
        var systemDemands: Set<SystemProviderDemand> = []
        var demandIssues: Set<ResourceDemandIssue> = []
        var resolvedRecords: [Key: (
            graph: Graph,
            material: SceneResolvedMaterialNode
        )] = [:]
        var authoredEffectComboNames: [Graph.EffectKey: Set<String>] = [:]
        for key in records.keys.sorted(by: Self.less) {
            guard let matches = records[key], matches.count == 1,
                  let record = matches.first else {
                compiled[key] = .failure(Failure(
                    phase: .graph,
                    code: .graphNodeInvalid,
                    details: ["duplicate-material-key", "count=\(records[key]?.count ?? 0)"]
                ))
                continue
            }
            let resolution = SceneAuthoredMaterialResolver.resolve(
                node: record.node,
                graph: record.graph,
                descriptor: descriptor
            )
            guard let material = resolution.node else {
                compiled[key] = .failure(Failure(
                    phase: .graph,
                    code: .graphNodeInvalid,
                    details: resolution.issues
                ))
                continue
            }
            authoredEffectComboNames[key.effect, default: []]
                .formUnion(material.combos.keys)
            guard resolution.issues.isEmpty else {
                compiled[key] = .failure(Failure(
                    phase: .graph,
                    code: .graphNodeInvalid,
                    details: resolution.issues
                ))
                continue
            }
            resolvedRecords[key] = (record.graph, material)
        }
        let pendingKeys = records.keys.sorted(by: Self.less).filter {
            compiled[$0] == nil && resolvedRecords[$0] != nil
        }
        let outcomesLock = NSLock()
        var outcomes = Array<CompilationOutcome?>(
            repeating: nil,
            count: pendingKeys.count
        )
        let resourceDemandAnalyses = ResourceDemandAnalysisCache()
        DispatchQueue.concurrentPerform(iterations: pendingKeys.count) { index in
            let key = pendingKeys[index]
            guard let record = resolvedRecords[key] else { return }
            let material = record.material
            let contracts = shaderContracts.filter {
                Self.normalized($0.identity) == Self.normalized(material.shaderPath)
            }
            let outcome: CompilationOutcome
            guard contracts.count == 1, let contract = contracts.first else {
                outcome = .init(
                    key: key,
                    entry: .failure(Failure(
                        phase: .shaderContract,
                        code: .shaderIdentityMismatch,
                        details: ["matching-contract-count=\(contracts.count)"]
                    )),
                    assetDemands: [],
                    userPropertyDemands: [],
                    systemProviderDemands: [],
                    issues: []
                )
                outcomesLock.withLock { outcomes[index] = outcome }
                return
            }
            switch SceneResolvedMaterialTemplateCompiler.compile(
                material: material,
                graph: record.graph,
                shaderContract: contract,
                inheritedInactiveCombos:
                    authoredEffectComboNames[key.effect, default: []]
                        .subtracting(material.combos.keys),
                unitPreviousBlurredCompositeGenericOwnerEligible:
                    SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission.accepts(
                        key: key,
                        graph: record.graph,
                        descriptor: descriptor,
                        userPropertyProducers: userPropertyProducers
                    ),
                provenSceneScriptValueTargets: provenSceneScriptValueTargets
            ) {
            case let .failure(failure):
                outcome = .init(
                    key: key,
                    entry: .failure(failure),
                    assetDemands: [],
                    userPropertyDemands: [],
                    systemProviderDemands: [],
                    issues: []
                )
            case let .success(template):
                var localDemands: Set<SceneAssetTextureIdentity> = []
                var localUserDemands: Set<SceneUserPropertyTextureIdentity> = []
                var localSystemDemands: Set<SystemProviderDemand> = []
                var localIssues: Set<ResourceDemandIssue> = []
                Self.collectResourceDemands(
                    template,
                    key: key,
                    implicitFramebufferIdentity: record.graph.effects.first {
                        $0.key == key.effect
                    }?.input,
                    demands: &localDemands,
                    userDemands: &localUserDemands,
                    systemDemands: &localSystemDemands,
                    issues: &localIssues,
                    analyses: resourceDemandAnalyses
                )
                outcome = .init(
                    key: key,
                    entry: .template(template),
                    assetDemands: localDemands,
                    userPropertyDemands: localUserDemands,
                    systemProviderDemands: localSystemDemands,
                    issues: localIssues
                )
            }
            outcomesLock.withLock { outcomes[index] = outcome }
        }
        for outcome in outcomes.compactMap({ $0 }) {
            compiled[outcome.key] = outcome.entry
            demands.formUnion(outcome.assetDemands)
            userDemands.formUnion(outcome.userPropertyDemands)
            systemDemands.formUnion(outcome.systemProviderDemands)
            demandIssues.formUnion(outcome.issues)
        }
        entries = compiled
        assetDemands = demands
        userPropertyDemands = userDemands
        systemProviderDemands = systemDemands
        resourceDemandIssues = demandIssues
    }

    func entry(for node: Graph.Node) -> Entry? {
        entries[Key(effect: node.effect, nodeIndex: node.nodeIndex)]
    }

    private static func collectResourceDemands(
        _ template: Template,
        key: Key,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        demands: inout Set<SceneAssetTextureIdentity>,
        userDemands: inout Set<SceneUserPropertyTextureIdentity>,
        systemDemands: inout Set<SystemProviderDemand>,
        issues: inout Set<ResourceDemandIssue>,
        analyses: ResourceDemandAnalysisCache
    ) {
        let analysisKey = ResourceDemandAnalysisKey(
            template: template,
            implicitFramebufferIdentity: implicitFramebufferIdentity
        )
        let analysis = analyses.result(for: analysisKey) {
            do {
                let textureFormatSlots = try SceneResolvedMaterialTextureResolver
                    .launchTextureFormatSlots(template: template)
                var samplers = try SceneResolvedMaterialShaderSchema.reachableSamplers(
                    template,
                    implicitFramebufferIdentity: implicitFramebufferIdentity
                )
                // Non-presence defaults participate before the fixed point. A
                // combo-bearing default is demanded only when a stable prepared
                // variant actually retains that sampler.
                for (slot, sampler) in try SceneResolvedMaterialShaderSchema
                    .unconditionalSamplers(template)
                    where sampler.readinessCombo == nil && samplers[slot] == nil {
                    samplers[slot, default: []].insert(sampler)
                }
                return .ready(
                    textureFormatSlots: textureFormatSlots,
                    samplers: samplers
                )
            } catch {
                return .failed(String(describing: error))
            }
        }
        let textureFormatSlots: Set<Int>
        let samplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>]
        switch analysis {
        case let .ready(formatSlots, reachable):
            textureFormatSlots = formatSlots
            samplers = reachable
        case let .failed(errorDescription):
#if DEBUG
            print(
                "MWX resolved material sampler reachability rejection:"
                    + " effect=\(key.effect.effectIndex) node=\(key.nodeIndex)"
                    + " error=\(errorDescription)"
            )
#endif
            for slot in template.textureSlots.compactMap({ $0 }) {
                for projected in demandProjection(for: slot).candidates {
                    recordUnproven(
                        projected.candidate.reference,
                        key: key,
                        slot: slot.index,
                        code: .samplerSchemaUnavailable,
                        sampler: nil,
                        issues: &issues
                    )
                }
            }
            return
        }
        for slotIndex in 0 ..< 8 {
            let projection = demandProjection(
                for: template.textureSlots[slotIndex]
            )
            for projected in projection.candidates {
                guard let textureSlot = projection.slot else { continue }
                let reference = projected.candidate.reference
                guard let slotSamplers = samplers[slotIndex], !slotSamplers.isEmpty else {
                    recordUnproven(
                        reference,
                        key: key,
                        slot: slotIndex,
                        code: .purposeUnproven,
                        sampler: nil,
                        issues: &issues
                    )
                    continue
                }
                for sampler in slotSamplers {
                    guard let purpose = SceneResolvedMaterialTextureSlotPurpose
                        .fact(
                            in: textureSlot,
                            candidateOrdinal: projected.ordinal,
                            sampler: sampler
                        )?.purpose else {
                        recordUnproven(
                            reference,
                            key: key,
                            slot: slotIndex,
                            code: .purposeUnproven,
                            sampler: sampler,
                            issues: &issues
                        )
                        continue
                    }
                    switch reference {
                    case let .asset(path):
                        demands.insert(.init(path: path, purpose: purpose))
                    case let .userProperty(request):
                        if let identity = SceneUserPropertyTextureIdentity(
                            propertyKey: request.key,
                            purpose: purpose
                        ) {
                            userDemands.insert(identity)
                        }
                    case let .provider(request):
                        if case let .system(name) = request {
                            systemDemands.insert(.init(name: name, purpose: purpose))
                        }
                    case .graph:
                        break
                    }
                }
            }
            guard projection.reachesDefault else { continue }
            for sampler in samplers[slotIndex] ?? [] {
                if sampler.readinessCombo != nil {
                    guard !textureFormatSlots.contains(slotIndex),
                          SceneResolvedMaterialTextureResolver
                            .presenceIndependentDefault(
                                template: template,
                                sampler: sampler,
                                slot: slotIndex
                            ) != nil else {
                        continue
                    }
                }
                guard case let .asset(path)? = sampler.defaultTexture else { continue }
                let reference = Template.TextureReference.asset(path)
                guard let purpose = sampler.purpose(for: reference) else {
                    Self.diagnoseUnproven(
                        .asset(path), key: key, slot: sampler.slot,
                        code: .purposeUnproven, sampler: sampler
                    )
                    issues.insert(.init(
                        key: key, slot: sampler.slot,
                        reference: .asset(path), code: .purposeUnproven
                    ))
                    continue
                }
                demands.insert(.init(path: path, purpose: purpose))
            }
        }
    }

    private static func demandProjection(
        for slot: Template.TextureSlot?
    ) -> (
        slot: Template.TextureSlot?,
        candidates: [(ordinal: Int, candidate: Template.TextureCandidate)],
        reachesDefault: Bool
    ) {
        guard let slot else { return (nil, [], true) }
        var candidates: [(
            ordinal: Int,
            candidate: Template.TextureCandidate
        )] = []
        for ordinal in slot.candidates.indices.reversed() {
            let candidate = slot.candidates[ordinal]
            candidates.append((ordinal, candidate))
            if case .graph = candidate.reference {
                return (slot, candidates, false)
            }
            if case let .provider(provider) = candidate.reference {
                switch provider {
                case .namedLayerTarget, .sceneBackground:
                    return (slot, candidates, false)
                case .system:
                    break
                }
            }
        }
        return (slot, candidates, true)
    }

    private static func recordUnproven(
        _ reference: Template.TextureReference,
        key: Key,
        slot: Int,
        code: ResourceDemandIssue.Code,
        sampler: SceneResolvedMaterialShaderSchema.Sampler?,
        issues: inout Set<ResourceDemandIssue>
    ) {
        let unresolved: ResourceDemandIssue.Reference
        switch reference {
        case let .asset(path):
            unresolved = .asset(path)
        case let .userProperty(request):
            unresolved = .userProperty(request.key)
        case let .provider(request):
            guard case let .system(name) = request else { return }
            unresolved = .system(name)
        case .graph:
            return
        }
        diagnoseUnproven(
            unresolved, key: key, slot: slot, code: code, sampler: sampler
        )
        issues.insert(.init(key: key, slot: slot, reference: unresolved, code: code))
    }

    private static func diagnoseUnproven(
        _ reference: ResourceDemandIssue.Reference,
        key: Key,
        slot: Int,
        code: ResourceDemandIssue.Code,
        sampler: SceneResolvedMaterialShaderSchema.Sampler?
    ) {
#if DEBUG
        let samplerName = sampler?.name ?? "<missing>"
        let samplerMode = sampler.map { String(describing: $0.mode) } ?? "<missing>"
        let materialKey = sampler?.materialKey ?? "<none>"
        let defaultTexture = sampler.map { sampler in
            switch sampler.defaultTexture {
            case let .asset(path): "asset:\(path.value)"
            case let .internalTarget(name): "internal:\(name)"
            case nil: "<none>"
            }
        } ?? "<missing>"
        print(
            "MWX resolved material resource demand rejection:"
                + " effect=\(key.effect.effectIndex) node=\(key.nodeIndex)"
                + " slot=\(slot) reference=\(reference.reportValue)"
                + " reason=\(code.rawValue)"
                + " sampler=\(samplerName) mode=\(samplerMode)"
                + " material=\(materialKey) default=\(defaultTexture)"
        )
#endif
    }

    private static func less(_ lhs: Key, _ rhs: Key) -> Bool {
        lhs.reportToken < rhs.reportToken
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
