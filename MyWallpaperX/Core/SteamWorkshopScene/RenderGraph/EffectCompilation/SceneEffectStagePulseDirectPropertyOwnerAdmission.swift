import Foundation

/// Classifies Pulse direct-property ownership without creating another
/// property state. Live values and definition-only authored fallbacks both
/// remain inputs to the shared Template/Program path, but a stage may not mix
/// the two sources while retiring its dedicated candidate.
nonisolated enum SceneEffectStagePulseDirectPropertyOwnerAdmission {
    typealias Constant = ScenePulseExecutionPlan.Constant

    enum OwnerSource: Equatable {
        case liveProducer
        case authoredFallback
    }

    enum OwnerDisposition: String {
        case retainIncumbent = "retain-incumbent"
        case revokeDedicatedOwner = "revoke-dedicated-owner"
    }

    static func ownerSource(
        plan: ScenePulseExecutionPlan,
        input: SceneEffectStageCompileInput
    ) -> OwnerSource? {
        guard !plan.bindings.isEmpty else { return nil }
        var sources: [OwnerSource] = []
        for (constant, binding) in plan.bindings {
            let expected = SceneDynamicUserPropertyProducer(
                propertyKey: binding.propertyKey,
                target: binding.dynamicTarget,
                valueType: constant.valueType
            )
            let targetProducers = input.userPropertyProducers.filter {
                $0.target == binding.dynamicTarget
            }
            if targetProducers == [expected] {
                sources.append(.liveProducer)
                continue
            }
            guard !input.userPropertyProducers.contains(where: {
                      $0.propertyKey == binding.propertyKey
                          || $0.target == binding.dynamicTarget
                  }),
                  let fallback = plan.staticOrFallbackValues[constant],
                  SceneEffectStageAuthoredFallbackOwnerPartition
                    .hasExactNumericDefinition(
                        target: binding.dynamicTarget,
                        valueType: constant.valueType,
                        componentBitPatterns: componentBitPatterns(
                            fallback,
                            valueType: constant.valueType
                        ),
                        definitions: input.propertyDefinitions
                    ) else { return nil }
            sources.append(.authoredFallback)
        }
        guard sources.count == plan.bindings.count,
              let first = sources.first,
              sources.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// Existing live cohorts retain their proven scalar/vector stage sets.
    /// Definition-only transfer is deliberately narrower: exact stock,
    /// non-audio, color-only, mask-free, fragment-only scalar/vector3 inputs.
    static func bindingCohortIsProven(
        plan: ScenePulseExecutionPlan,
        input: SceneEffectStageCompileInput,
        alphaWriting: Bool
    ) -> Bool {
        guard let source = ownerSource(plan: plan, input: input) else {
            return false
        }
        switch source {
        case .liveProducer:
            if plan.audio == nil {
                return directNonRelationalBindingsAreProven(plan)
                    && (alphaWriting
                        ? plan.pulseAlpha
                        : plan.pulseColor && !plan.pulseAlpha)
            }
            return alphaWriting
                && plan.pulseAlpha
                && plan.shaderProfile == .stock2842
                && plan.pulseColor
                && plan.maskTexturePath == nil
                && plan.bindings.keys.allSatisfy {
                    $0 == .tintLow || $0 == .tintHigh
                }
        case .authoredFallback:
            return plan.shaderProfile == .stock2842
                && plan.audio == nil
                && !alphaWriting
                && plan.pulseColor
                && !plan.pulseAlpha
                && plan.maskTexturePath == nil
                && plan.bindings.keys.allSatisfy(fragmentFallbackConstants.contains)
        }
    }

    static func authoredFallbackRevocationDetail(
        plan: ScenePulseExecutionPlan,
        input: SceneEffectStageCompileInput
    ) -> String? {
        guard bindingCohortIsProven(
            plan: plan,
            input: input,
            alphaWriting: false
        ), ownerSource(plan: plan, input: input) == .authoredFallback else {
            return nil
        }
        let valueTypes = Set(plan.bindings.keys.map(\.valueType))
        if valueTypes == [.scalar] {
            return "authored-fallback-fragment-scalar-owner-revoked-to-material-program"
        }
        if valueTypes == [.vector3] {
            return "authored-fallback-fragment-vector3-owner-revoked-to-material-program"
        }
        if valueTypes == [.scalar, .vector3] {
            return "authored-fallback-fragment-scalar-vector3-owner-revoked-to-material-program"
        }
        return nil
    }

    /// Both texture-readiness variants must preserve exact active consumers,
    /// type, stage set, author domain, and safe fallback before owner transfer.
    static func ownerDisposition(
        plan: ScenePulseExecutionPlan,
        preparedVariants: [SceneShaderPreparedProgram]
    ) -> OwnerDisposition {
        guard !plan.bindings.isEmpty,
              preparedVariants.count == 2,
              preparedVariants.allSatisfy({
                  activeConsumersAreProven(plan: plan, prepared: $0)
              }) else { return .retainIncumbent }
        return .revokeDedicatedOwner
    }

    static func activeConsumersAreProven(
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
                case .stock2842: stages = [.vertex, .fragment]
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
            let components = componentValues(
                fallback,
                valueType: constant.valueType
            )
            return zip(stages, uniforms).allSatisfy { stage, uniform in
                let range = constant.authoredRange(
                    for: plan.shaderProfile,
                    stage: stage
                )
                return uniform.authoredRange == range
                    && components.allSatisfy {
                        $0.isFinite && range.contains($0)
                    }
            }
        }
    }

    private static func directNonRelationalBindingsAreProven(
        _ plan: ScenePulseExecutionPlan
    ) -> Bool {
        plan.bindings.keys.allSatisfy(liveDirectConstants.contains)
    }

    private static func componentValues(
        _ value: SIMD3<Double>,
        valueType: SceneDynamicValueType
    ) -> [Double] {
        switch valueType {
        case .scalar: [value.x]
        case .vector2: [value.x, value.y]
        case .vector3: [value.x, value.y, value.z]
        case .bool, .vector4, .string: []
        }
    }

    private static func componentBitPatterns(
        _ value: SIMD3<Double>,
        valueType: SceneDynamicValueType
    ) -> [UInt64] {
        componentValues(value, valueType: valueType).map(\.bitPattern)
    }

    private static let fragmentFallbackConstants: Set<Constant> = [
        .noiseSpeed, .noiseAmount, .power, .tintLow, .tintHigh,
    ]
    private static let liveDirectConstants: Set<Constant> = [
        .speed, .phase, .amount,
        .noiseSpeed, .noiseAmount, .power, .tintLow, .tintHigh,
    ]
}
