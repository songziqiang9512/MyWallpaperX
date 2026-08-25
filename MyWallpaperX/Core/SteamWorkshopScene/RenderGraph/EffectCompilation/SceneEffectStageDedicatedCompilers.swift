import Foundation

/// Common typed boundary for dedicated planners that share the authored graph,
/// descriptor, shader-contract and input-role inputs. Exact admission remains
/// in each existing planner; this protocol only owns result classification.
nonisolated protocol SceneEffectStageDedicatedPlanner {
    associatedtype DedicatedPlan

    static var compilerBackend: SceneEffectStageCompilerBackend { get }

    static func plan(
        graph: SceneAuthoredEffectRenderPlan,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        inputRole: SceneAuthoredEffectInputRole
    ) -> DedicatedPlan?

    static func isCandidate(_ input: SceneEffectStageCompileInput) -> Bool
}

nonisolated protocol SceneEffectStageGraphCandidatePlanner:
    SceneEffectStageDedicatedPlanner
{
    static func containsCandidate(graph: SceneAuthoredEffectRenderPlan) -> Bool
}

extension SceneEffectStageDedicatedPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<DedicatedPlan> {
        SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: compilerBackend,
            candidate: { isCandidate(input) },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    shaderContracts: input.shaderContracts,
                    inputRole: input.inputRole
                )
            }
        )
    }
}

extension SceneEffectStageGraphCandidatePlanner {
    nonisolated static func isCandidate(
        _ input: SceneEffectStageCompileInput
    ) -> Bool {
        containsCandidate(graph: input.stageGraph)
    }
}

extension SceneAuthoredStandardBlurPlanner {
    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<SceneEffectStageExecutionPlan> {
        let result = SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: .standardBlur,
            candidate: { containsCandidate(graph: input.stageGraph) },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    inputRole: input.inputRole
                )
            }
        )
        guard case .accepted = result,
              let effect = input.stageGraph.effects.first,
              let terminalNodeIndex = effect.nodeIndices.last else { return result }
        let revocationDetail =
            SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission
                .dedicatedRevocationDetail(
                    graph: input.stageGraph,
                    descriptor: input.descriptor
                )
        let sourceAccepted =
            SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission
                .acceptsDedicatedRevocation(
                    key: .init(
                        effect: effect.key,
                        nodeIndex: terminalNodeIndex
                    ),
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    inputRole: input.inputRole,
                    shaderContracts: input.shaderContracts
                )
        guard sourceAccepted, let revocationDetail else { return result }
        return .rejected(.init(
            backend: .standardBlur,
            phase: .compatibility,
            code: .dedicatedProfileRejected,
            details: [revocationDetail]
        ))
    }
}

extension SceneAuthoredXRayPlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = SceneXRayExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .xRay }
}

extension SceneAuthoredPulsePlanner: SceneEffectStageGraphCandidatePlanner {
    typealias DedicatedPlan = ScenePulseExecutionPlan
    nonisolated static var compilerBackend: SceneEffectStageCompilerBackend { .pulse }

    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<ScenePulseExecutionPlan> {
        let result = SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: .pulse,
            candidate: { containsCandidate(graph: input.stageGraph) },
            plan: {
                plan(
                    graph: input.stageGraph,
                    descriptor: input.descriptor,
                    shaderContracts: input.shaderContracts,
                    inputRole: input.inputRole
                )
            }
        )
        guard case let .accepted(plan) = result,
              staticRGBProgramOwnerIsProven(
                  plan: plan,
                  input: input
              ) else { return result }
        return .rejected(.init(
            backend: .pulse,
            phase: .compatibility,
            code: .dedicatedProfileRejected,
            details: [
                "static-rgb-preserving-owner-revoked-to-material-program",
            ]
        ))
    }

    /// Revokes static color-only profiles after every readiness shape proves
    /// the same graph-input carrier, typed-data auxiliaries, and exact terminal
    /// RGB/alpha transform. Dynamic, audio, and alpha cohorts retain incumbent.
    private nonisolated static func staticRGBProgramOwnerIsProven(
        plan: ScenePulseExecutionPlan,
        input: SceneEffectStageCompileInput
    ) -> Bool {
        typealias Graph = SceneAuthoredEffectRenderPlan
        let supportedProfiles: [ScenePulseShaderProfile] = [
            .directPhaseSaturateV1,
            .directPhaseMaxClampV1,
        ]
        guard supportedProfiles.contains(plan.shaderProfile),
              plan.bindings.isEmpty,
              plan.audio == nil,
              plan.pulseColor,
              !plan.pulseAlpha,
              input.stageGraph.effects.count == 1,
              input.stageGraph.nodes.count == 1,
              let effect = input.stageGraph.effects.first,
              let node = input.stageGraph.nodes.first,
              node.effect == effect.key else { return false }

        let resolution = SceneAuthoredMaterialResolver.resolve(
            node: node,
            graph: input.stageGraph,
            descriptor: input.descriptor
        )
        guard resolution.isResolved,
              let material = resolution.node else { return false }
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
                ), exactGenericParametersAreProven(
                    plan: plan,
                    material: material,
                    template: template
                ) else { return false }

        let unavailable = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
            ($0, false)
        })
        let available = Dictionary(uniqueKeysWithValues: (0 ..< 8).map { slot in
            (
                slot,
                template.textureSlots.indices.contains(slot)
                    && template.textureSlots[slot] != nil
            )
        })
        for readiness in [unavailable, available] {
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
            let sources = SceneAuthoredShaderBackendCanonicalizer.canonicalize(
                vertex: prepared.vertex.source,
                fragment: prepared.fragment.source
            )
            let transfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: sources.fragment
            )
            guard let fact = SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(
                fragmentSource: sources.fragment
            ), transfer == .straightAlphaPreserving(
                textureSlot: fact.sourceSlot
            ), let activeNames =
                SceneAuthoredShaderDeadBindingAnalyzer.activeSamplerNames(
                    vertexSource: sources.vertex,
                    fragmentSource: sources.fragment
                ), let samplers = try? SceneResolvedMaterialShaderSchema
                    .activeSamplers(prepared, activeNames: activeNames)
            else { return false }

            let graphInputFacts = SceneResolvedMaterialShaderSchema
                .graphInputSourceSlotFacts(
                    template: template,
                    samplers: samplers,
                    inputIdentity: effect.input,
                    sourceColorTransfer: transfer
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
                if identity.kind == Graph.TextureKind.framebuffer {
                    graphTargetSlots.insert(slot)
                }
            }
            let typedAuxiliary = SceneResolvedMaterialVariantCache
                .typedStaticDataAuxiliarySlots(
                    template: template,
                    samplers: samplers,
                    graphInputSlots: graphInputSlots
                )
            guard graphInputSlots == [fact.sourceSlot],
                  graphTargetSlots.isSubset(of: [fact.sourceSlot]),
                  !fact.auxiliarySlots.isEmpty,
                  typedAuxiliary == fact.auxiliarySlots,
                  !SceneResolvedMaterialVariantCache.hasExternalProviderTexture(
                      in: template,
                      activeTextureSlots: Set(samplers.keys)
                  ),
                  SceneGenericShaderCapabilityProfile
                    .sourceProvenGraphInputTypedDataRGBFilter
                    .defaultRouteState == .genericOnly,
                  SceneGenericShaderCapabilityProfile
                    .sourceProvenGraphInputTypedDataRGBFilter
                    .validatedRollbackOwner == .none
            else { return false }
        }
        return true
    }

    /// The retired planner historically accepted case-folded keys while the
    /// generic Program intentionally preserves authored key identity. Limit
    /// owner transfer to the canonical stock spelling and prove the values
    /// carried into the Template are the same values accepted by the plan.
    private nonisolated static func exactGenericParametersAreProven(
        plan: ScenePulseExecutionPlan,
        material: SceneResolvedMaterialNode,
        template: SceneResolvedMaterialTemplate
    ) -> Bool {
        let comboNames = Set([
            "AUDIOPROCESSING", "BLENDMODE", "PULSEALPHA", "PULSECOLOR",
        ])
        guard material.combos.keys.allSatisfy(comboNames.contains),
              template.comboValues == material.combos,
              material.combos["AUDIOPROCESSING", default: 0] == 0,
              material.combos["BLENDMODE", default: defaultBlendMode]
                == plan.blendMode,
              (material.combos["PULSECOLOR", default: 1] == 1)
                == plan.pulseColor,
              (material.combos["PULSEALPHA", default: 0] == 1)
                == plan.pulseAlpha,
              material.userShaderValues.isEmpty
        else { return false }

        let constantNames = Set(Constant.allCases.map(\.rawValue))
        guard material.constants.keys.allSatisfy(constantNames.contains),
              Set(template.uniformDeclarations.map(\.name))
                == Set(material.constants.keys)
        else { return false }
        for constant in Constant.allCases {
            let components = material.constants[constant.rawValue]?.components
                ?? constant.defaultComponents(for: plan.shaderProfile)
            guard components.count
                    == constant.defaultComponents(for: plan.shaderProfile).count,
                  plan.staticOrFallbackValues[constant]
                    == SIMD3(components, fill: 0)
            else { return false }
        }
        return true
    }
}
