import Foundation

/// Transfers the current-stock X-Ray scalar cohort only after the shared
/// MaterialProgram proves the same authored values, any typed producers,
/// active shader ABI, and source-derived spatial blend profile. Static values
/// exact direct user-scalar values, and exact definition-only authored
/// fallbacks share one owner boundary. Frame-driven effect visibility and any
/// broader source/resource shape retain the incumbent.
nonisolated enum SceneEffectStageXRayScalarOwnerAdmission {
    typealias Graph = SceneAuthoredEffectRenderPlan
    typealias Template = SceneResolvedMaterialTemplate

    private struct ScalarContract {
        let name: String
        let range: ClosedRange<Double>
        let stage: SceneShaderContract.StageKind
    }

    private static let scalarContracts = [
        ScalarContract(name: "size", range: 0 ... 1, stage: .vertex),
        ScalarContract(name: "multiply", range: 0 ... 10, stage: .fragment),
    ]

    private enum ScalarOwnerSource: Equatable {
        case staticExact
        case liveProducer
        case authoredFallback
    }

    private struct Admission {
        let startupInactive: Bool
        let scalarOwnerSources: [ScalarOwnerSource]

        var usesAuthoredFallback: Bool {
            scalarOwnerSources.contains(.authoredFallback)
        }
    }

    static func acceptsDedicatedRevocation(
        effectKey: Graph.EffectKey,
        input: SceneEffectStageCompileInput
    ) -> Bool {
        admission(effectKey: effectKey, input: input) != nil
    }

    static func dedicatedRevocationDetail(
        effectKey: Graph.EffectKey,
        input: SceneEffectStageCompileInput
    ) -> String? {
        guard let admission = admission(
            effectKey: effectKey,
            input: input
        ) else { return nil }
        let scalarToken = admission.usesAuthoredFallback
            ? "current-stock-authored-fallback-scalar"
            : "current-stock-scalar"
        let lifecyclePrefix = admission.startupInactive
            ? "startup-inactive-direct-bool-"
            : ""
        return lifecyclePrefix
            + scalarToken
            + "-owner-revoked-to-material-program"
    }

    private static func admission(
        effectKey: Graph.EffectKey,
        input: SceneEffectStageCompileInput
    ) -> Admission? {
        guard input.stageGraph.effects.count == 1,
              input.stageGraph.nodes.count == 1,
              let effect = input.stageGraph.effects.first,
              let node = input.stageGraph.nodes.first,
              effect.key == effectKey,
              node.effect == effectKey,
              node.instancePassIndex == 0,
              let layer = input.descriptor.layers.first(where: {
                  $0.id == effectKey.layerID
              }), input.descriptor.layers.filter({
                  $0.id == effectKey.layerID
              }).count == 1,
              layer.effects.indices.contains(effectKey.effectIndex),
              layer.effects[effectKey.effectIndex].id == effectKey.descriptorID,
              let startupInactive = input.authoredEffectIsStartupInactive(
                for: effectKey
              ),
              !input.hasFrameDrivenEffectVisibilityOwner(for: effectKey),
              (startupInactive
                ? input.supportsStartupInactiveUserPropertyVisibility(
                    for: effectKey
                )
                : input.supportsEffectLocalUserPropertyVisibility(
                    for: effectKey
                ))
        else { return nil }

        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node,
            graph: input.stageGraph,
            descriptor: input.descriptor
        )
        guard resolution.isResolved,
              let material = resolution.node,
              material.userShaderValues.isEmpty,
              Set(material.constants.keys) == Set(scalarContracts.map(\.name)),
              material.combos.keys.allSatisfy({
                  $0 == "BLENDMODE" || $0 == "OPACITYMASK"
              }), material.combos["BLENDMODE", default: 0] == 0,
              (0 ... 1).contains(material.combos["OPACITYMASK", default: 0])
        else { return nil }

        let contracts = input.shaderContracts.filter {
            normalized($0.identity) == normalized(material.shaderPath)
        }
        guard contracts.count == 1,
              let contract = contracts.first,
              case let .success(template) =
                SceneResolvedMaterialTemplateCompiler.compile(
                    material: material,
                    graph: input.stageGraph,
                    shaderContract: contract,
                    inheritedInactiveCombos: []
                ), template.comboValues == material.combos,
              let scalarOwnerSources = exactScalarDeclarationsAreProven(
                  effectKey: effectKey,
                  material: material,
                  template: template,
                  producers: input.userPropertyProducers,
                  definitions: input.propertyDefinitions
              ) else { return nil }

        for readiness in textureReadinessVariants(template) {
            let prepared: SceneShaderPreparedProgram
            switch SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: contract,
                combos: template.comboValues,
                inactiveComboProviders: Set(template.inheritedInactiveCombos),
                textureReadiness: readiness
            ) {
            case let .accepted(value): prepared = value
            case .notApplicable, .rejected: return nil
            }
            guard activeScalarConsumersAreProven(prepared) else {
                return nil
            }
            guard spatialWeightedProfileIsProven(
                effectKey: effectKey,
                effect: effect,
                template: template,
                prepared: prepared,
                textureReadiness: readiness,
                descriptor: input.descriptor
            ) else { return nil }
        }
        return .init(
            startupInactive: startupInactive,
            scalarOwnerSources: scalarOwnerSources
        )
    }

    /// Only OPACITYMASK is readiness-driven in the exact current shader. Keep
    /// explicit authored combo values consistent while still proving the two
    /// resource extremes for every other slot.
    private static func textureReadinessVariants(
        _ template: Template
    ) -> [[Int: Bool]] {
        var unavailable = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
            ($0, false)
        })
        var available = Dictionary(uniqueKeysWithValues: (0 ..< 8).map { slot in
            (
                slot,
                template.textureSlots.indices.contains(slot)
                    && template.textureSlots[slot] != nil
            )
        })
        if let opacityMask = template.comboValues["OPACITYMASK"] {
            unavailable[3] = opacityMask == 1
            available[3] = opacityMask == 1
        }
        return unavailable == available ? [unavailable] : [unavailable, available]
    }

    private static func exactScalarDeclarationsAreProven(
        effectKey: Graph.EffectKey,
        material: SceneResolvedMaterialNode,
        template: Template,
        producers: Set<SceneDynamicUserPropertyProducer>,
        definitions: [SceneDynamicTargetDefinition]
    ) -> [ScalarOwnerSource]? {
        guard template.uniformDeclarations.count == scalarContracts.count else {
            return nil
        }
        var ownerSources: [ScalarOwnerSource] = []
        for contract in scalarContracts {
            guard let authored = material.constants[contract.name],
                  authored.timeline == nil,
                  authored.timelineDiagnostics.isEmpty,
                  authored.scriptSource == nil,
                  let components = authored.components,
                  components.count == 1,
                  let component = components.first,
                  component.isFinite,
                  contract.range.contains(component) else { return nil }
            let declarations = template.uniformDeclarations.filter {
                $0.name == contract.name
            }
            guard declarations.count == 1 else { return nil }
            let target = SceneDynamicTarget.effectConstant(
                layerID: effectKey.layerID,
                effectIndex: effectKey.effectIndex,
                passIndex: 0,
                name: contract.name
            )
            if let propertyKey = authored.userBinding {
                let expected = SceneDynamicUserPropertyProducer(
                    propertyKey: propertyKey,
                    target: target,
                    valueType: .scalar
                )
                let targetProducers = producers.filter { $0.target == target }
                guard authored.valueKind.localizedLowercase == "binding",
                      authored.userValueKind == .string,
                      SceneResolvedMaterialDirectUserBindingContract.matches(
                          authored.bindingKeys
                      ),
                      !propertyKey.isEmpty,
                      propertyKey == propertyKey.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ),
                      case let .dynamic(dynamic) = declarations[0].value,
                      dynamic.target == target,
                      dynamic.valueContributors == [.userProperty(propertyKey)],
                      dynamic.scriptAttachments.isEmpty,
                      let fallback = dynamic.authoredFallback,
                      fallback.valueKind.localizedLowercase == "binding",
                      SceneResolvedMaterialDirectUserBindingContract.matches(
                          dynamic: dynamic,
                          fallback: fallback
                      ),
                      fallback.componentBitPatterns == [component.bitPattern]
                else { return nil }
                if targetProducers == [expected] {
                    ownerSources.append(.liveProducer)
                } else if !producers.contains(where: {
                              $0.propertyKey == propertyKey
                                  || $0.target == target
                          }),
                          SceneEffectStageAuthoredFallbackOwnerPartition
                            .hasExactScalarDefinition(
                                target: target,
                                componentBitPatterns:
                                    fallback.componentBitPatterns,
                                definitions: definitions
                            ) {
                    ownerSources.append(.authoredFallback)
                } else {
                    return nil
                }
            } else {
                guard authored.valueKind.localizedLowercase == "number",
                      authored.userValueKind == nil,
                      authored.bindingKeys.isEmpty,
                      !producers.contains(where: { $0.target == target }),
                      case let .staticExact(value) = declarations[0].value,
                      value.valueKind.localizedLowercase == "number",
                      value.authoredBindingKeys.isEmpty,
                      value.componentBitPatterns == [component.bitPattern]
                else { return nil }
                ownerSources.append(.staticExact)
            }
        }
        return ownerSources.count == scalarContracts.count
            ? ownerSources
            : nil
    }

    private static func activeScalarConsumersAreProven(
        _ prepared: SceneShaderPreparedProgram
    ) -> Bool {
        scalarContracts.allSatisfy { contract in
            guard let uniform = SceneResolvedMaterialShaderSchema.uniqueActiveUniform(
                materialKey: contract.name,
                type: .float,
                stage: contract.stage,
                prepared: prepared
            ) else { return false }
            return uniform.authoredRange == contract.range
        }
    }

    private static func spatialWeightedProfileIsProven(
        effectKey: Graph.EffectKey,
        effect: Graph.Effect,
        template: Template,
        prepared: SceneShaderPreparedProgram,
        textureReadiness: [Int: Bool],
        descriptor: SceneRenderDescriptor
    ) -> Bool {
        let sources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
            vertex: prepared.vertex.source,
            fragment: prepared.fragment.source
        )
        let runtimeLoopBounds = SceneResolvedMaterialRuntimeLoopBoundResolver.resolve(
            template: template,
            prepared: prepared
        )
        guard let resolvedCombos =
                SceneAuthoredShaderPreparation.resolvedIntegerCombos(
                    contract: template.shaderContract,
                    prepared: prepared,
                    combos: template.comboValues,
                    inactiveComboProviders: Set(template.inheritedInactiveCombos),
                    textureReadiness: textureReadiness
                ) else { return false }
        let normalBlendModes = Set(resolvedCombos.compactMap { name, value in
            value == 0 ? name : nil
        })
        guard let fact = SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer.analyze(
            fragmentSource: sources.fragment,
            normalBlendModeIdentifiers: normalBlendModes
        ), let activeNames = SceneAuthoredShaderDeadBindingAnalyzer.activeSamplerNames(
            vertexSource: sources.vertex,
            fragmentSource: sources.fragment,
            runtimeLoopBounds: runtimeLoopBounds
        ), let samplers = try? SceneResolvedMaterialShaderSchema.activeSamplers(
            prepared,
            activeNames: activeNames,
            analysisVertexSource: sources.vertex,
            analysisFragmentSource: sources.fragment,
            normalBlendModeIdentifiers: normalBlendModes
        ) else { return false }

        let sourceTransfer = SceneShaderColorTransfer.straightAlphaPreserving(
            textureSlot: fact.sourceSlot
        )
        let graphInputFacts = SceneResolvedMaterialShaderSchema
            .graphInputSourceSlotFacts(
                template: template,
                samplers: samplers,
                inputIdentity: effect.input,
                sourceColorTransfer: sourceTransfer
            )
        var graphInputSlots = Set(graphInputFacts.keys)
        graphInputSlots.formUnion(template.graphRole.bindings.compactMap {
            samplers[$0.slot] == nil ? nil : $0.slot
        })
        var graphTargetSlots = Set<Int>()
        for (slot, textureSlot) in template.textureSlots.enumerated() {
            guard samplers[slot] != nil,
                  case let .graph(identity)? =
                    textureSlot?.candidates.last?.reference else { continue }
            graphInputSlots.insert(slot)
            if identity.kind == .framebuffer { graphTargetSlots.insert(slot) }
        }
        let activeSlots = Set(samplers.keys)
        let typedAuxiliary = Set(samplers.compactMap { slot, sampler in
            sampler.sourceProvenPurpose == nil ? nil : slot
        })
        guard fact.activeSlots == activeSlots else {
            return false
        }
        guard graphInputSlots == [fact.sourceSlot] else {
            return false
        }
        guard graphTargetSlots.isEmpty else {
            return false
        }
        guard fact.activeSlots.count >= 3 else {
            return false
        }
        guard typedAuxiliary == fact.activeSlots.subtracting([fact.sourceSlot]) else {
            return false
        }
        let externalProviderSlots =
            SceneResolvedMaterialVariantCache.externalProviderTextureSlots(
                in: template,
                activeTextureSlots: activeSlots
            )
        if externalProviderSlots.isEmpty {
            return SceneGenericShaderCapabilityProfile
                .sourceProvenGraphInputSpatialWeightedColorBlend
                .defaultRouteState == .genericOnly
                && SceneGenericShaderCapabilityProfile
                    .sourceProvenGraphInputSpatialWeightedColorBlend
                    .validatedRollbackOwner == .boundedFrontend
        }

        let providerSlots = Set([fact.straightColorSlot])
        guard externalProviderSlots == providerSlots,
              SceneResolvedMaterialVariantCache
                .terminalNamedLayerProviderTextureSlots(
                    in: template,
                    activeTextureSlots: activeSlots
                ) == providerSlots,
              template.textureSlots.indices.contains(fact.straightColorSlot),
              let selected = template.textureSlots[fact.straightColorSlot]?
                .candidates.last,
              case let .provider(.namedLayerTarget(reference)) =
                selected.reference,
              reference.variant == .primary else { return false }

        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: descriptor
        )
        let dependencyPlan = SceneDependencyRenderPlan(
            descriptor: descriptor,
            visibleLayerIDs: visibleLayerIDs,
            verifiedXRayStageKeys: [effectKey]
        )
        let expectedSlot = SceneEffectPassSlot(
            effectID: effectKey.descriptorID,
            passIndex: 0,
            slotIndex: fact.straightColorSlot
        )
        guard let binding =
                dependencyPlan.bindingsByConsumerLayerID[effectKey.layerID],
              binding.kind == .visibleImageGraphOutput,
              binding.consumerLayerID == effectKey.layerID,
              binding.providerLayerID == reference.providerLayerID,
              binding.slot == expectedSlot,
              binding.referenceSlots == [expectedSlot],
              binding.blendMode == 0,
              dependencyPlan.requiredGraphOutputProviderLayerIDs.contains(
                  reference.providerLayerID
              ) else { return false }

        return SceneGenericShaderCapabilityProfile
            .providerBackedGraphInputSpatialWeightedColorBlend
            .defaultRouteState == .genericOnly
            && SceneGenericShaderCapabilityProfile
                .providerBackedGraphInputSpatialWeightedColorBlend
                .validatedRollbackOwner == .boundedFrontend
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

}
