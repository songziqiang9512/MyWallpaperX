import Foundation
import QuartzCore

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

    struct SourceMaterialKey: Hashable {
        let layerID: Int
        let modelPath: String
        let materialPath: String
        let passIndex: Int

        var reportToken: String {
            "source:\(layerID):\(modelPath):\(materialPath):\(passIndex)"
        }
    }

    enum DemandOwner: Hashable {
        case effect(Key)
        case sourceMaterial(SourceMaterialKey)

        var reportToken: String {
            switch self {
            case let .effect(key): key.reportToken
            case let .sourceMaterial(key): key.reportToken
            }
        }
    }

    struct SourceMaterialEntry {
        let key: SourceMaterialKey
        let entry: Entry
        var sharedModelPath: String? = nil
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

        let owner: DemandOwner
        var key: Key? {
            guard case let .effect(key) = owner else { return nil }
            return key
        }
        let slot: Int
        let reference: Reference
        let code: Code
    }

    typealias SystemProviderDemand = SceneSystemProviderTextureIdentity



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
        private var entries: [SceneMaterialDemandAnalysisPersistentCache
            .ResourceDemandAnalysisKey: Entry] = [:]

        func result(
            for key: SceneMaterialDemandAnalysisPersistentCache
                .ResourceDemandAnalysisKey,
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
    let sourceMaterialEntries: [Int: SourceMaterialEntry]
    let sourceMaterialTargetFormat: SceneGraphRenderTargetPlan.TextureFormat
    let assetDemands: Set<SceneAssetTextureIdentity>
    let userPropertyDemands: Set<SceneUserPropertyTextureIdentity>
    let systemProviderDemands: Set<SystemProviderDemand>
    let resourceDemandIssues: Set<ResourceDemandIssue>

    init(
        descriptor: SceneRenderDescriptor,
        admissionCandidates: [AdmissionCandidate],
        shaderContracts: [SceneShaderContract],
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer>,
        propertyDefinitions: [SceneDynamicTargetDefinition] = [],
        timelineDefinitions: Set<SceneDynamicTargetDefinition> = [],
        provenSceneScriptValueTargets: Set<SceneDynamicTarget> = [],
        materialInstancesByLayerID: [Int: SceneDocument.SceneLayerMaterialInstance] = [:],
        loweredSourceMaterialModelPaths: Set<String> = [],
        provenSourceMaterialBindings: [SceneBaseMaterialColorModulationCompiler.Binding] = []
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
        let resolveStart = CACurrentMediaTime()
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
        let resolveMs = (CACurrentMediaTime() - resolveStart) * 1000
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
                previousBlurredCompositeGenericOwnerEligible:
                    SceneResolvedMaterialPreviousBlurredCompositeOwnerAdmission.accepts(
                        key: key,
                        graph: record.graph,
                        descriptor: descriptor,
                        userPropertyProducers: userPropertyProducers,
                        propertyDefinitions: propertyDefinitions,
                        timelineDefinitions: timelineDefinitions
                    ),
                provenSceneScriptValueTargets: provenSceneScriptValueTargets,
                compatibilityTarget: .windowsDX11ShaderModel4
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
                    owner: .effect(key),
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
        NSLog(
            "MWX LAUNCH-STAGE: catalog-detail materials=%d resolveMs=%.0f compileMs=%.0f",
            records.count,
            resolveMs,
            (CACurrentMediaTime() - resolveStart) * 1000 - resolveMs
        )
        sourceMaterialTargetFormat = descriptor.colorTargetFormat
        sourceMaterialEntries = Self.compileSourceMaterials(
            descriptor: descriptor, shaderContracts: shaderContracts,
            instances: materialInstancesByLayerID,
            loweredModelPaths: loweredSourceMaterialModelPaths,
            provenBindings: provenSourceMaterialBindings,
            sceneScriptTargets: provenSceneScriptValueTargets,
            userPropertyProducers: userPropertyProducers,
            demands: &demands, userDemands: &userDemands,
            systemDemands: &systemDemands, issues: &demandIssues,
            analyses: resourceDemandAnalyses
        )
        entries = compiled
        assetDemands = demands
        userPropertyDemands = userDemands
        systemProviderDemands = systemDemands
        resourceDemandIssues = demandIssues
    }

    func entry(for node: Graph.Node) -> Entry? {
        entries[Key(effect: node.effect, nodeIndex: node.nodeIndex)]
    }

    private static func compileSourceMaterials(
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        instances: [Int: SceneDocument.SceneLayerMaterialInstance],
        loweredModelPaths: Set<String>,
        provenBindings: [SceneBaseMaterialColorModulationCompiler.Binding],
        sceneScriptTargets: Set<SceneDynamicTarget>,
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer>,
        demands: inout Set<SceneAssetTextureIdentity>,
        userDemands: inout Set<SceneUserPropertyTextureIdentity>,
        systemDemands: inout Set<SystemProviderDemand>,
        issues: inout Set<ResourceDemandIssue>,
        analyses: ResourceDemandAnalysisCache
    ) -> [Int: SourceMaterialEntry] {
        let links = Dictionary(grouping: descriptor.modelMaterialLinks) { normalized($0.modelPath) }
        let passes = Dictionary(grouping: descriptor.materialPasses) { normalized($0.materialPath) }
        let fullBindings = provenBindings.filter { !$0.canLowerToCompositor }
        var result: [Int: SourceMaterialEntry] = [:]
        for layer in descriptor.layers where layer.contentKind == "image" {
            guard let modelPath = layer.imagePath,
                  !loweredModelPaths.contains(normalized(modelPath)),
                  let matchingLinks = links[normalized(modelPath)],
                  matchingLinks.count == 1,
                  let materialPath = matchingLinks.first?.materialPath,
                  let materialPasses = passes[normalized(materialPath)],
                  materialPasses.contains(where: { pass in
                      pass.shaderPath.map { !SceneBuiltinShaderIdentity.isImage($0) } ?? true
                  }) else { continue }
            let proof = fullBindings.first { normalized($0.modelPath) == normalized(modelPath)
                && normalized($0.materialPath) == normalized(materialPath) }
            if let proof, proof.sourceLayerID != layer.id { continue }
            let key = SourceMaterialKey(layerID: layer.id, modelPath: modelPath,
                materialPath: materialPath, passIndex: materialPasses.first?.passIndex ?? 0)
            func reject(_ detail: String) -> SourceMaterialEntry {
                .init(key: key, entry: .failure(.init(phase: .graph,
                    code: .graphNodeInvalid, details: ["source-material-" + detail])))
            }
            guard materialPasses.count == 1, let pass = materialPasses.first,
                  pass.passIndex == 0, layer.puppetMeshPath == nil,
                  layer.staticModelPath == nil, layer.usesPerspective != true else {
                result[layer.id] = reject("shape-unsupported"); continue
            }
            // The existing slot-0 provider owner must not replace a completed
            // shader source. Admit those producers only with a full-slot plan.
            guard instances[layer.id] == nil, layer.staticBaseTexturePath == nil,
                  pass.userTextureInputs.allSatisfy({ $0 == nil }),
                  pass.userShaderValues.isEmpty,
                  pass.constantShaderValues.allSatisfy({ name, value in
                      sourceUniformIsAdmitted(name: name, value: value, proof: proof,
                          sceneScriptTargets: sceneScriptTargets, userPropertyProducers: userPropertyProducers)
                  }) else {
                result[layer.id] = reject("dynamic-declaration-unsupported"); continue
            }
            let resolution = SceneAuthoredMaterialResolver.resolveSourceMaterial(
                material: pass)
            guard let material = resolution.node, resolution.issues.isEmpty else {
                result[layer.id] = reject("resolution:" + resolution.issues.joined(separator: ";")); continue
            }
            guard let state = sourceEvaluationState(material.renderState, provenInterface: proof != nil) else {
                result[layer.id] = reject("render-state-unsupported"); continue
            }
            let contracts = shaderContracts.filter {
                normalized($0.identity) == normalized(material.shaderPath)
            }
            guard contracts.count == 1, let contract = contracts.first else {
                result[layer.id] = reject("shader-contract-count=\(contracts.count)"); continue
            }
            switch SceneResolvedMaterialTemplateCompiler.compileSourceMaterial(
                material: material, layerID: layer.id, materialPath: materialPath,
                passIndex: pass.passIndex, shaderContract: contract, renderState: state,
                provenSceneScriptValueTargets: sceneScriptTargets
            ) {
            case let .failure(failure):
                result[layer.id] = .init(key: key, entry: .failure(failure))
            case let .success(template):
                guard template.textureSlots.compactMap({ $0 }).allSatisfy({ slot in
                    slot.candidates.allSatisfy { candidate in
                        if case .asset = candidate.reference { return true }
                        return false
                    }
                }) else {
                    result[layer.id] = reject("provider-unsupported"); continue
                }
                collectResourceDemands(template, owner: .sourceMaterial(key),
                    implicitFramebufferIdentity: nil, demands: &demands,
                    userDemands: &userDemands, systemDemands: &systemDemands,
                    issues: &issues, analyses: analyses)
                result[layer.id] = .init(key: key, entry: .template(template),
                    sharedModelPath: proof.map { normalized($0.modelPath) })
            }
        }
        return result
    }

    /// Only the interface-proven color/Alpha inputs may borrow the existing
    /// typed producers. Unknown dynamic fields keep the original rejection.
    private static func sourceUniformIsAdmitted(
        name: String, value: SceneDocument.ShaderValue,
        proof: SceneBaseMaterialColorModulationCompiler.Binding?,
        sceneScriptTargets: Set<SceneDynamicTarget>,
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer>
    ) -> Bool {
        guard value.timeline == nil, value.timelineDiagnostics.isEmpty else { return false }
        if value.bindingKeys.isEmpty { return true }
        guard let proof else { return false }
        let target = SceneDynamicTarget.materialConstant(layerID: proof.sourceLayerID,
            passIndex: 0, name: name, materialPath: proof.materialPath)
        func hasUserProducer(_ key: String, _ type: SceneDynamicValueType) -> Bool {
            let matches = userPropertyProducers.filter { $0.target == target }
            return matches.count == 1 && matches.first?.propertyKey == key
                && matches.first?.valueType == type
        }
        if name == proof.colorKey {
            guard value.scriptSource == proof.scriptSource,
                  value.userBinding == proof.colorUserPropertyKey else { return false }
            var keys = ["value"]
            if proof.scriptSource != nil {
                keys.append("script")
                guard sceneScriptTargets.contains(target) else { return false }
            }
            if value.scriptProperties != nil { keys.append("scriptproperties") }
            if let key = proof.colorUserPropertyKey {
                keys.append("user")
                guard hasUserProducer(key, .vector3) else { return false }
            }
            return value.bindingKeys.sorted() == keys.sorted()
        }
        guard name == proof.alphaKey, let key = proof.alphaUserPropertyKey,
              value.bindingKeys.sorted() == ["user", "value"],
              value.userBinding == key, value.scriptSource == nil,
              value.scriptProperties == nil else { return false }
        return hasUserProducer(key, .scalar)
    }

    /// Evaluation writes raw material output into a transparent source target;
    /// final layer blending is still owned by the compositor. Preserve raw
    /// declarations and reject conflicting explicit states instead of claiming
    /// that omitted authored blending/culling has a proven backend default.
    private static func sourceEvaluationState(
        _ raw: SceneResolvedMaterialNode.RenderState,
        provenInterface: Bool
    ) -> SceneMaterialRenderState? {
        func allows(_ value: String?, _ expected: String) -> Bool {
            value == nil || value?.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == expected
        }
        let provenRawOverwrite = provenInterface && allows(raw.blending, "translucent")
            && allows(raw.alphaWriting, "default")
        guard (allows(raw.blending, "normal") || provenRawOverwrite), allows(raw.depthTest, "disabled"),
              allows(raw.depthWrite, "disabled"), allows(raw.cullMode, "nocull"),
              raw.alphaWriting == nil || allows(raw.alphaWriting, "enabled") || provenRawOverwrite else { return nil }
        return .init(rawValues: .init(blending: raw.blending, depthTest: raw.depthTest,
            depthWrite: raw.depthWrite, cullMode: raw.cullMode, alphaWriting: raw.alphaWriting),
            blending: .normal, depthTest: .disabled, depthWrite: .disabled,
            cullMode: .noCull, alphaWriting: raw.alphaWriting == nil ? .unspecified : .enabled)
    }

    private static func collectResourceDemands(
        _ template: Template,
        owner: DemandOwner,
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        demands: inout Set<SceneAssetTextureIdentity>,
        userDemands: inout Set<SceneUserPropertyTextureIdentity>,
        systemDemands: inout Set<SystemProviderDemand>,
        issues: inout Set<ResourceDemandIssue>,
        analyses: ResourceDemandAnalysisCache
    ) {
        let analysisKey = SceneMaterialDemandAnalysisPersistentCache
            .ResourceDemandAnalysisKey(
            template: template,
            implicitFramebufferIdentity: implicitFramebufferIdentity
        )
        let analysis = analyses.result(for: analysisKey) {
            if let persisted = SceneMaterialDemandAnalysisPersistentCache
                .load(key: analysisKey) {
                return .ready(
                    textureFormatSlots: persisted.textureFormatSlots,
                    samplers: persisted.samplers
                )
            }
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
                SceneMaterialDemandAnalysisPersistentCache.store(
                    textureFormatSlots: textureFormatSlots,
                    samplers: samplers,
                    key: analysisKey
                )
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
                    + " owner=\(owner.reportToken)"
                    + " error=\(errorDescription)"
            )
#endif
            for slot in template.textureSlots.compactMap({ $0 }) {
                for projected in demandProjection(for: slot).candidates {
                    recordUnproven(
                        projected.candidate.reference,
                        owner: owner,
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
                        owner: owner,
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
                            owner: owner,
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
                        .asset(path), owner: owner, slot: sampler.slot,
                        code: .purposeUnproven, sampler: sampler
                    )
                    issues.insert(.init(
                        owner: owner, slot: sampler.slot,
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
                case .namedLayerTarget, .sceneBackground, .sceneEnvironment:
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
        owner: DemandOwner,
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
            unresolved, owner: owner, slot: slot, code: code, sampler: sampler
        )
        issues.insert(.init(owner: owner, slot: slot, reference: unresolved, code: code))
    }

    private static func diagnoseUnproven(
        _ reference: ResourceDemandIssue.Reference,
        owner: DemandOwner,
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
            case let .internalTarget(name): "internal:\(name.authoredName)"
            case nil: "<none>"
            }
        } ?? "<missing>"
        print(
            "MWX resolved material resource demand rejection:"
                + " owner=\(owner.reportToken)"
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
