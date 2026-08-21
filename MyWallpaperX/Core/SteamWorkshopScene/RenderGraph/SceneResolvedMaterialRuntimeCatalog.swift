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

    let entries: [Key: Entry]
    let assetDemands: Set<SceneAssetTextureIdentity>
    let userPropertyDemands: Set<SceneUserPropertyTextureIdentity>
    let systemProviderDemands: Set<SystemProviderDemand>
    let resourceDemandIssues: Set<ResourceDemandIssue>

    init(
        descriptor: SceneRenderDescriptor,
        admissionCandidates: [AdmissionCandidate],
        shaderContracts: [SceneShaderContract],
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
        for key in records.keys.sorted(by: Self.less) {
            guard compiled[key] == nil,
                  let record = resolvedRecords[key] else { continue }
            let material = record.material
            let contracts = shaderContracts.filter {
                Self.normalized($0.identity) == Self.normalized(material.shaderPath)
            }
            guard contracts.count == 1, let contract = contracts.first else {
                compiled[key] = .failure(Failure(
                    phase: .shaderContract,
                    code: .shaderIdentityMismatch,
                    details: ["matching-contract-count=\(contracts.count)"]
                ))
                continue
            }
            switch SceneResolvedMaterialTemplateCompiler.compile(
                material: material,
                graph: record.graph,
                shaderContract: contract,
                inheritedInactiveCombos:
                    authoredEffectComboNames[key.effect, default: []]
                        .subtracting(material.combos.keys),
                provenSceneScriptValueTargets: provenSceneScriptValueTargets
            ) {
            case let .failure(failure):
                compiled[key] = .failure(failure)
            case let .success(template):
                compiled[key] = .template(template)
                Self.collectResourceDemands(
                    template,
                    key: key,
                    implicitFramebufferIdentity: record.graph.effects.first {
                        $0.key == key.effect
                    }?.input,
                    demands: &demands,
                    userDemands: &userDemands,
                    systemDemands: &systemDemands,
                    issues: &demandIssues
                )
            }
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
        issues: inout Set<ResourceDemandIssue>
    ) {
        var samplers: [Int: Set<SceneResolvedMaterialShaderSchema.Sampler>]
        let textureFormatSlots: Set<Int>
        do {
            textureFormatSlots = try SceneResolvedMaterialTextureResolver
                .launchTextureFormatSlots(template: template)
            samplers = try SceneResolvedMaterialShaderSchema.reachableSamplers(
                template,
                implicitFramebufferIdentity: implicitFramebufferIdentity
            )
            // Non-presence defaults participate before the fixed point. A
            // combo-bearing default is demanded only when a stable prepared
            // variant actually retains that sampler.
            for (slot, sampler) in try SceneResolvedMaterialShaderSchema
                .unconditionalSamplers(template)
                where sampler.readinessCombo == nil {
                samplers[slot, default: []].insert(sampler)
            }
        } catch {
#if DEBUG
            print(
                "MWX resolved material sampler reachability rejection:"
                    + " effect=\(key.effect.effectIndex) node=\(key.nodeIndex)"
                    + " error=\(String(describing: error))"
            )
#endif
            for slot in template.textureSlots.compactMap({ $0 }) {
                for candidate in demandProjection(for: slot).candidates {
                    recordUnproven(
                        candidate.reference,
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
            for candidate in projection.candidates {
                let reference = candidate.reference
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
                    guard let purpose = sampler.purpose(for: reference) else {
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
    ) -> (candidates: [Template.TextureCandidate], reachesDefault: Bool) {
        guard let slot else { return ([], true) }
        var candidates: [Template.TextureCandidate] = []
        for candidate in slot.candidates.reversed() {
            candidates.append(candidate)
            if case .graph = candidate.reference {
                return (candidates, false)
            }
            if case let .provider(provider) = candidate.reference {
                switch provider {
                case .namedLayerTarget, .sceneBackground:
                    return (candidates, false)
                case .system:
                    break
                }
            }
        }
        return (candidates, true)
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
