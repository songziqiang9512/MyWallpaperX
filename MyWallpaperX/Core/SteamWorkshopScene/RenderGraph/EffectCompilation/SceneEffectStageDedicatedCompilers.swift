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
              !input.hasFrameDrivenEffectVisibilityOwner(for: effect.key),
              let startupInactive = input.authoredEffectIsStartupInactive(
                for: effect.key
              ),
              (startupInactive
                ? input.supportsStartupInactiveUserPropertyVisibility(for: effect.key)
                : input.supportsEffectLocalUserPropertyVisibility(for: effect.key)),
              let terminalNodeIndex = effect.nodeIndices.last else { return result }
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
                    shaderContracts: input.shaderContracts,
                    userPropertyProducers: input.userPropertyProducers,
                    propertyDefinitions: input.propertyDefinitions,
                    timelineDefinitions: input.timelineDefinitions
                )
        guard sourceAccepted,
              let baseRevocationDetail =
                SceneResolvedMaterialUnitPreviousBlurredCompositeOwnerAdmission
                    .dedicatedRevocationDetail(
                        graph: input.stageGraph,
                        descriptor: input.descriptor,
                        userPropertyProducers: input.userPropertyProducers,
                        propertyDefinitions: input.propertyDefinitions
                    ) else { return result }
        let revocationDetail = startupInactive
            ? "startup-inactive-direct-bool-\(baseRevocationDetail)"
            : baseRevocationDetail
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

    nonisolated static func compile(
        _ input: SceneEffectStageCompileInput
    ) -> SceneEffectStageBackendCompileResult<SceneXRayExecutionPlan> {
        let result = SceneEffectStageDedicatedCompilerAdapter.compile(
            backend: .xRay,
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
              SceneEffectStageXRayScalarOwnerAdmission
                .acceptsDedicatedRevocation(
                    effectKey: plan.effectKey,
                    input: input
                ) else { return result }
        let detail = input.authoredEffectIsStartupInactive(for: plan.effectKey) == true
            ? "startup-inactive-direct-bool-current-stock-scalar-owner-revoked-to-material-program"
            : "current-stock-scalar-owner-revoked-to-material-program"
        return .rejected(.init(
            backend: .xRay,
            phase: .compatibility,
            code: .dedicatedProfileRejected,
            details: [detail]
        ))
    }
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
        guard case let .accepted(plan) = result else { return result }
        let detail: String
        if colorOnlyRGBProgramOwnerIsProven(plan: plan, input: input) {
            if !plan.bindings.isEmpty {
                detail = "typed-user-property-rgb-owner-revoked-to-material-program"
            } else if plan.audio == nil {
                detail = "static-rgb-preserving-owner-revoked-to-material-program"
            } else {
                detail = "audio-color-only-rgb-owner-revoked-to-material-program"
            }
        } else if scalarAlphaProgramOwnerIsProven(plan: plan, input: input) {
            if !plan.bindings.isEmpty {
                if plan.audio != nil {
                    detail = "audio-typed-user-property-rgb-alpha-owner-revoked-to-material-program"
                } else {
                    detail = plan.pulseColor
                        ? "typed-user-property-rgb-alpha-owner-revoked-to-material-program"
                        : "typed-user-property-alpha-only-owner-revoked-to-material-program"
                }
            } else if plan.pulseColor {
                detail = plan.audio == nil
                    ? "static-rgb-alpha-owner-revoked-to-material-program"
                    : "audio-rgb-alpha-owner-revoked-to-material-program"
            } else {
                detail = plan.audio == nil
                    ? "static-alpha-only-owner-revoked-to-material-program"
                    : "audio-alpha-only-owner-revoked-to-material-program"
            }
        } else {
            return result
        }
        return .rejected(.init(
            backend: .pulse,
            phase: .compatibility,
            code: .dedicatedProfileRejected,
            details: [detail]
        ))
    }

    /// Revokes color-only profiles after every readiness shape proves the same
    /// graph-input carrier, typed-data auxiliaries, and exact terminal RGB/alpha
    /// transform. SceneScript/Timeline, audio-bound, and alpha-writing cohorts
    /// retain incumbent.
    private nonisolated static func colorOnlyRGBProgramOwnerIsProven(
        plan: ScenePulseExecutionPlan,
        input: SceneEffectStageCompileInput
    ) -> Bool {
        typealias Graph = SceneAuthoredEffectRenderPlan
        let supportedProfiles: [ScenePulseShaderProfile] = [
            .stock2842,
            .directPhaseSaturateV1,
            .directPhaseMaxClampV1,
        ]
        let bindingCohortIsProven = plan.bindings.isEmpty
            || directBindingCohortIsProven(
                plan: plan, input: input, alphaWriting: false
            )
        guard supportedProfiles.contains(plan.shaderProfile),
              bindingCohortIsProven,
              plan.audio == nil || plan.shaderProfile == .stock2842,
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
        var preparedVariants: [SceneShaderPreparedProgram] = []
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
                  graphTargetSlots.isEmpty,
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
            preparedVariants.append(prepared)
        }
        if !plan.bindings.isEmpty {
            guard directUserPropertyOwnerDisposition(
                plan: plan,
                preparedVariants: preparedVariants
            ) == .revokeDedicatedOwner else { return false }
        }
        return true
    }

    /// Revokes canonical alpha-writing Pulse shapes only after source analysis
    /// proves either preserved RGB or an RGB blend driven by the same scalar.
    /// Direct non-relational user-property bindings share the same exact
    /// producer, consumer ABI, and authored-range proof as color-only Pulse.
    /// Stock audio may additionally carry active tint bindings when it has no
    /// optional mask. SceneScript/Timeline, provider, and unsupported historical
    /// combined forms retain incumbent.
    /// Stock combined RGB/alpha may carry one source-proven typed opacity mask
    /// after the alpha write. The straight-RGB/scalar-alpha path also admits an
    /// exact source-proven non-audio historical max-clamp shape, with or without
    /// that post-alpha mask.
    private nonisolated static func scalarAlphaProgramOwnerIsProven(
        plan: ScenePulseExecutionPlan,
        input: SceneEffectStageCompileInput
    ) -> Bool {
        typealias Graph = SceneAuthoredEffectRenderPlan
        let supportedProfiles: [ScenePulseShaderProfile] = plan.pulseColor
            ? [.stock2842]
            : [.stock2842, .directPhaseSaturateV1, .directPhaseMaxClampV1]
        let bindingCohortIsProven = plan.bindings.isEmpty
            || directBindingCohortIsProven(
                plan: plan, input: input, alphaWriting: true
            )
        guard supportedProfiles.contains(plan.shaderProfile),
              bindingCohortIsProven,
              plan.audio == nil || plan.shaderProfile == .stock2842,
              plan.pulseAlpha,
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
            let sourceShape: (
                sourceSlot: Int,
                scalarAuxiliarySlots: Set<Int>,
                auxiliarySlots: Set<Int>,
                maskSlot: Int?,
                profile: SceneGenericShaderCapabilityProfile
            )
            if plan.pulseColor {
                guard let fact = SceneAuthoredShaderColorTransferAnalyzer
                        .rgbBlendScalarAlphaFact(
                            fragmentSource: sources.fragment
                        ), transfer == .straightAlpha(
                            textureSlot: fact.sourceSlot
                        ) else { return false }
                sourceShape = (
                    fact.sourceSlot,
                    fact.scalarAuxiliarySlots,
                    fact.auxiliarySlots,
                    fact.maskSlot,
                    .sourceProvenGraphInputRGBBlendScalarAlpha
                )
            } else {
                guard let fact = SceneAuthoredShaderColorTransferAnalyzer
                        .straightRGBScalarAlphaFact(
                            fragmentSource: sources.fragment
                        ), transfer == .straightAlpha(
                            textureSlot: fact.sourceSlot
                        ) else { return false }
                sourceShape = (
                    fact.sourceSlot,
                    fact.scalarAuxiliarySlots,
                    fact.auxiliarySlots,
                    fact.maskSlot,
                    .sourceProvenGraphInputStraightRGBScalarAlpha
                )
            }
            guard let activeNames =
                    SceneAuthoredShaderDeadBindingAnalyzer.activeSamplerNames(
                        vertexSource: sources.vertex,
                        fragmentSource: sources.fragment
                    ),
                  let samplers = try? SceneResolvedMaterialShaderSchema
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
            let activeMaskSlots = Set(samplers.compactMap { slot, sampler in
                sampler.mode == .opacityMask ? slot : nil
            })
            let sourceMaskSlots = sourceShape.maskSlot.map { Set([$0]) } ?? []
            let auxiliaryShapeIsProven: Bool
            if plan.audio == nil {
                auxiliaryShapeIsProven =
                    !sourceShape.scalarAuxiliarySlots.isEmpty
            } else {
                auxiliaryShapeIsProven = plan.shaderProfile == .stock2842
                    && sourceShape.scalarAuxiliarySlots.isEmpty
            }
            guard graphInputSlots == [sourceShape.sourceSlot],
                  graphTargetSlots.isEmpty,
                  auxiliaryShapeIsProven,
                  activeMaskSlots == sourceMaskSlots,
                  Set(samplers.keys)
                    == sourceShape.auxiliarySlots.union([sourceShape.sourceSlot]),
                  typedAuxiliary == sourceShape.auxiliarySlots,
                  !SceneResolvedMaterialVariantCache.hasExternalProviderTexture(
                      in: template,
                      activeTextureSlots: Set(samplers.keys)
                  ),
                  sourceShape.profile.defaultRouteState == .genericOnly,
                  sourceShape.profile.validatedRollbackOwner == .none
            else { return false }
            guard activeUserPropertyConsumersAreProven(
                plan: plan,
                prepared: prepared
            ) else { return false }
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
              material.combos["AUDIOPROCESSING", default: 0]
                == (plan.audio?.channel.rawValue ?? 0),
              material.combos["BLENDMODE", default: defaultBlendMode]
                == plan.blendMode,
              (material.combos["PULSECOLOR", default: 1] == 1)
                == plan.pulseColor,
              (material.combos["PULSEALPHA", default: 0] == 1)
                == plan.pulseAlpha,
              material.userShaderValues.isEmpty,
              exactUserPropertyBindingsAreProven(
                  plan: plan,
                  template: template
              ),
              let audio = audioParameters(
                  combos: material.combos,
                  constants: material.constants,
                  profile: plan.shaderProfile
              ),
              audio.parameters == plan.audio
        else { return false }

        var constantNames = Set(Constant.allCases.map(\.rawValue))
        if plan.audio != nil {
            constantNames.formUnion(SceneAudioResponseAdmission.constantKeys)
        }
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

    /// The old planner accepts only direct `{user,value}` wrappers and keeps
    /// their exact authored fallback. Revoke it only when the shared Template
    /// publishes the same target, sole producer, wrapper identity, and value.
    private nonisolated static func exactUserPropertyBindingsAreProven(
        plan: ScenePulseExecutionPlan,
        template: SceneResolvedMaterialTemplate
    ) -> Bool {
        let dynamicNames = Set(template.uniformDeclarations.compactMap {
            declaration -> String? in
            guard case .dynamic = declaration.value else { return nil }
            return declaration.name
        })
        guard dynamicNames == Set(plan.bindings.keys.map(\.rawValue)) else {
            return false
        }
        return plan.bindings.allSatisfy { constant, binding in
            let declarations = template.uniformDeclarations.filter {
                $0.name == constant.rawValue
            }
            guard declarations.count == 1,
                  case let .dynamic(dynamic) = declarations[0].value,
                  dynamic.target == binding.dynamicTarget,
                  dynamic.valueContributors == [
                      .userProperty(binding.propertyKey),
                  ],
                  dynamic.scriptAttachments.isEmpty,
                  dynamic.authoredBindingKeys == ["user", "value"],
                  let fallback = dynamic.authoredFallback,
                  fallback.valueKind.localizedLowercase == "binding",
                  fallback.authoredBindingKeys == ["user", "value"] else {
                return false
            }
            let actual = fallback.componentBitPatterns.map {
                Double(bitPattern: $0)
            }
            guard let expected = plan.staticOrFallbackValues[constant] else {
                return false
            }
            switch constant.valueType {
            case .scalar:
                return actual == [expected.x]
            case .vector2:
                return actual == [expected.x, expected.y]
            case .vector3:
                return actual == [expected.x, expected.y, expected.z]
            default:
                return false
            }
        }
    }

    /// A wrapper is not enough to transfer execution authority: every bound
    /// value must also have the exact active stage set and scalar/vector ABI in
    /// every prepared readiness variant.
    private nonisolated static func activeUserPropertyConsumersAreProven(
        plan: ScenePulseExecutionPlan,
        prepared: SceneShaderPreparedProgram
    ) -> Bool {
        plan.bindings.keys.allSatisfy { constant in
            let type: SceneAuthoredShaderValueType
            switch constant.valueType {
            case .scalar: type = .float
            case .vector2: type = .float2
            case .vector3: type = .float3
            default: return false
            }
            let stages: [SceneShaderContract.StageKind]
            switch constant {
            case .speed, .amount:
                stages = [.vertex, .fragment]
            case .phase:
                switch plan.shaderProfile {
                case .stock2842:
                    stages = [.vertex, .fragment]
                case .directPhaseSaturateV1, .directPhaseMaxClampV1:
                    stages = [.fragment]
                }
            case .noiseSpeed, .noiseAmount, .power, .tintLow, .tintHigh:
                stages = [.fragment]
            case .bounds:
                return false
            }
            guard let uniforms = SceneResolvedMaterialShaderSchema.exactActiveUniforms(
                materialKey: constant.rawValue,
                type: type,
                stages: stages,
                prepared: prepared
            ), let fallback = plan.staticOrFallbackValues[constant]
            else { return false }
            let fallbackComponents: [Double]
            switch constant.valueType {
            case .scalar: fallbackComponents = [fallback.x]
            case .vector2: fallbackComponents = [fallback.x, fallback.y]
            case .vector3: fallbackComponents = [fallback.x, fallback.y, fallback.z]
            default: return false
            }
            return zip(stages, uniforms).allSatisfy { stage, uniform in
                let expectedRange = constant.authoredRange(
                    for: plan.shaderProfile,
                    stage: stage
                )
                return uniform.authoredRange == expectedRange
                    && fallbackComponents.allSatisfy {
                        $0.isFinite && expectedRange.contains($0)
                    }
            }
        }
    }

    nonisolated enum DirectUserPropertyOwnerDisposition: String {
        case retainIncumbent = "retain-incumbent"
        case revokeDedicatedOwner = "revoke-dedicated-owner"
    }

    /// Final owner decision shared by the production compiler and executable
    /// partition tests. Both unavailable and available readiness variants must
    /// preserve the exact consumer set before the incumbent can be revoked.
    nonisolated static func directUserPropertyOwnerDisposition(
        plan: ScenePulseExecutionPlan,
        preparedVariants: [SceneShaderPreparedProgram]
    ) -> DirectUserPropertyOwnerDisposition {
        guard !plan.bindings.isEmpty,
              preparedVariants.count == 2,
              preparedVariants.allSatisfy({
                  activeUserPropertyConsumersAreProven(
                      plan: plan,
                      prepared: $0
                  )
              }) else {
            return .retainIncumbent
        }
        return .revokeDedicatedOwner
    }

    /// Non-audio direct values share the stage-indexed Program schema. Audio
    /// keeps timing in the host snapshot and only exposes stock, mask-free tint.
    private nonisolated static func directBindingCohortIsProven(
        plan: ScenePulseExecutionPlan,
        input: SceneEffectStageCompileInput,
        alphaWriting: Bool
    ) -> Bool {
        guard !plan.bindings.isEmpty else { return false }
        let shapeIsProven: Bool
        if plan.audio == nil {
            shapeIsProven = directNonRelationalBindingsAreProven(plan)
                && (alphaWriting
                    ? plan.pulseAlpha
                    : plan.pulseColor && !plan.pulseAlpha)
        } else {
            shapeIsProven = alphaWriting
                && plan.pulseAlpha
                && plan.shaderProfile == .stock2842
                && plan.pulseColor
                && plan.maskTexturePath == nil
                && plan.bindings.keys.allSatisfy {
                    $0 == .tintLow || $0 == .tintHigh
                }
        }
        return shapeIsProven
            && exactUserPropertyProducersAreProven(plan: plan, input: input)
    }

    private nonisolated static func directNonRelationalBindingsAreProven(
        _ plan: ScenePulseExecutionPlan
    ) -> Bool {
        guard !plan.bindings.isEmpty else { return false }
        let supported: Set<ScenePulseExecutionPlan.Constant> = [
            .speed, .phase, .amount,
            .noiseSpeed, .noiseAmount, .power, .tintLow, .tintHigh,
        ]
        return plan.bindings.keys.allSatisfy(supported.contains)
    }

    /// Owner revocation is launch-scoped: the property binding compiler must
    /// publish the exact key, target, and scalar/vector type consumed by the
    /// Program. A missing or differently typed producer retains the incumbent,
    /// which preserves the authored fallback instead of claiming a bad route.
    private nonisolated static func exactUserPropertyProducersAreProven(
        plan: ScenePulseExecutionPlan,
        input: SceneEffectStageCompileInput
    ) -> Bool {
        plan.bindings.allSatisfy { constant, binding in
            let expected = SceneDynamicUserPropertyProducer(
                propertyKey: binding.propertyKey,
                target: binding.dynamicTarget,
                valueType: constant.valueType
            )
            return input.userPropertyProducers.filter {
                $0.target == binding.dynamicTarget
            } == [expected]
        }
    }
}
