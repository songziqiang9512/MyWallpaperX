import Foundation

/// Transfers the current-stock X-Ray scalar cohort only after the shared
/// MaterialProgram proves the same authored values, any typed producers,
/// active shader ABI, and source-derived spatial blend profile. Static values
/// and exact direct user-scalar values share one owner boundary. Frame-driven
/// effect visibility and any broader source/resource shape retain the
/// incumbent.
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

    static func acceptsDedicatedRevocation(
        effectKey: Graph.EffectKey,
        input: SceneEffectStageCompileInput
    ) -> Bool {
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
        else { return false }

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
        else { return false }

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
              exactScalarDeclarationsAreProven(
                  effectKey: effectKey,
                  material: material,
                  template: template,
                  producers: input.userPropertyProducers
              ) else { return false }

        for readiness in textureReadinessVariants(template) {
            let prepared: SceneShaderPreparedProgram
            switch SceneAuthoredShaderPreparation.prepareShaderStages(
                contract: contract,
                combos: template.comboValues,
                inactiveComboProviders: Set(template.inheritedInactiveCombos),
                textureReadiness: readiness
            ) {
            case let .accepted(value): prepared = value
            case .notApplicable, .rejected: return false
            }
            guard activeScalarConsumersAreProven(prepared) else {
                return false
            }
            guard spatialWeightedProfileIsProven(
                effectKey: effectKey,
                effect: effect,
                template: template,
                prepared: prepared,
                textureReadiness: readiness,
                descriptor: input.descriptor
            ) else { return false }
        }
        return true
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
        producers: Set<SceneDynamicUserPropertyProducer>
    ) -> Bool {
        guard template.uniformDeclarations.count == scalarContracts.count else {
            return false
        }
        for contract in scalarContracts {
            guard let authored = material.constants[contract.name],
                  authored.timeline == nil,
                  authored.timelineDiagnostics.isEmpty,
                  authored.scriptSource == nil,
                  let components = authored.components,
                  components.count == 1,
                  let component = components.first,
                  component.isFinite,
                  contract.range.contains(component) else { return false }
            let declarations = template.uniformDeclarations.filter {
                $0.name == contract.name
            }
            guard declarations.count == 1 else { return false }
            let target = SceneDynamicTarget.effectConstant(
                layerID: effectKey.layerID,
                effectIndex: effectKey.effectIndex,
                passIndex: 0,
                name: contract.name
            )
            let targetProducers = producers.filter { $0.target == target }
            if let propertyKey = authored.userBinding {
                let expected = SceneDynamicUserPropertyProducer(
                    propertyKey: propertyKey,
                    target: target,
                    valueType: .scalar
                )
                guard authored.valueKind.localizedLowercase == "binding",
                      authored.userValueKind == .string,
                      authored.bindingKeys == ["user", "value"],
                      !propertyKey.isEmpty,
                      propertyKey == propertyKey.trimmingCharacters(
                          in: .whitespacesAndNewlines
                      ), targetProducers == [expected],
                      case let .dynamic(dynamic) = declarations[0].value,
                      dynamic.target == target,
                      dynamic.valueContributors == [.userProperty(propertyKey)],
                      dynamic.scriptAttachments.isEmpty,
                      dynamic.authoredBindingKeys == ["user", "value"],
                      let fallback = dynamic.authoredFallback,
                      fallback.valueKind.localizedLowercase == "binding",
                      fallback.authoredBindingKeys == ["user", "value"],
                      fallback.componentBitPatterns == [component.bitPattern]
                else { return false }
            } else {
                guard authored.valueKind.localizedLowercase == "number",
                      authored.userValueKind == nil,
                      authored.bindingKeys.isEmpty,
                      targetProducers.isEmpty,
                      case let .staticExact(value) = declarations[0].value,
                      value.valueKind.localizedLowercase == "number",
                      value.authoredBindingKeys.isEmpty,
                      value.componentBitPatterns == [component.bitPattern]
                else { return false }
            }
        }
        return true
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
