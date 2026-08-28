import Foundation

/// Shared, loss-preserving input for one authored effect stage compiler probe.
/// The chain planner supplies authored identity; standalone planner adapters may
/// omit it while they are being migrated to the shared boundary.
nonisolated struct SceneEffectStageCompileInput {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct DynamicEffectVisibilityOwner: Hashable {
        let layerID: Int
        let effectIndex: Int
    }

    let stageGraph: Graph
    let authoredOrdinal: Int?
    let effectKey: Graph.EffectKey?
    let definitionPath: String?
    let inputRole: SceneAuthoredEffectInputRole
    let descriptor: SceneRenderDescriptor
    let shaderContracts: [SceneShaderContract]
    let userPropertyProducers: Set<SceneDynamicUserPropertyProducer>
    let propertyDefinitions: [SceneDynamicTargetDefinition]
    let timelineDefinitions: Set<SceneDynamicTargetDefinition>
    let activeEffectLocalDirectBoolVisibilityTargets: Set<SceneDynamicTarget>
    let startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget>
    let frameDrivenEffectVisibilityOwners:
        Set<DynamicEffectVisibilityOwner>

    init(
        stageGraph: Graph,
        authoredOrdinal: Int? = nil,
        effectKey: Graph.EffectKey? = nil,
        definitionPath: String? = nil,
        inputRole: SceneAuthoredEffectInputRole,
        descriptor: SceneRenderDescriptor,
        shaderContracts: [SceneShaderContract],
        userPropertyProducers: Set<SceneDynamicUserPropertyProducer> = [],
        propertyDefinitions: [SceneDynamicTargetDefinition] = [],
        timelineDefinitions: Set<SceneDynamicTargetDefinition> = [],
        activeEffectLocalDirectBoolVisibilityTargets: Set<SceneDynamicTarget> = [],
        startupInactiveEffectVisibilityTargets: Set<SceneDynamicTarget> = [],
        frameDrivenEffectVisibilityOwners:
            Set<DynamicEffectVisibilityOwner> = []
    ) {
        self.stageGraph = stageGraph
        self.authoredOrdinal = authoredOrdinal
        self.effectKey = effectKey
        self.definitionPath = definitionPath
        self.inputRole = inputRole
        self.descriptor = descriptor
        self.shaderContracts = shaderContracts
        self.userPropertyProducers = userPropertyProducers
        self.propertyDefinitions = propertyDefinitions
        self.timelineDefinitions = timelineDefinitions
        self.activeEffectLocalDirectBoolVisibilityTargets =
            activeEffectLocalDirectBoolVisibilityTargets
        self.startupInactiveEffectVisibilityTargets =
            startupInactiveEffectVisibilityTargets
        self.frameDrivenEffectVisibilityOwners =
            frameDrivenEffectVisibilityOwners
    }

    func hasFrameDrivenEffectVisibilityOwner(
        for effectKey: Graph.EffectKey
    ) -> Bool {
        frameDrivenEffectVisibilityOwners.contains {
            $0.layerID == effectKey.layerID
        }
    }

    func authoredEffectIsStartupInactive(
        for effectKey: Graph.EffectKey
    ) -> Bool? {
        guard let layer = descriptor.layers.first(where: {
            $0.id == effectKey.layerID
        }), layer.effects.indices.contains(effectKey.effectIndex) else {
            return nil
        }
        let effect = layer.effects[effectKey.effectIndex]
        guard effect.id == effectKey.descriptorID else { return nil }
        return effect.visible == false
    }

    func supportsEffectLocalUserPropertyVisibility(
        for effectKey: Graph.EffectKey
    ) -> Bool {
        let target = SceneDynamicTarget.effectVisibility(
            layerID: effectKey.layerID,
            effectIndex: effectKey.effectIndex
        )
        let producers = userPropertyEffectVisibilityProducers(for: effectKey)
        return producers.isEmpty
            || (producers.count == 1
                && producers.first?.valueType == .bool
                && activeEffectLocalDirectBoolVisibilityTargets.contains(target))
    }

    /// Startup-inactive execution is a distinct lifecycle cohort. Only the
    /// fully validated route-admission target may revoke an incumbent; active
    /// targets stay separate so other dedicated families do not inherit this
    /// broader lifecycle without their own owner proof.
    func supportsStartupInactiveUserPropertyVisibility(
        for effectKey: Graph.EffectKey
    ) -> Bool {
        let target = SceneDynamicTarget.effectVisibility(
            layerID: effectKey.layerID,
            effectIndex: effectKey.effectIndex
        )
        let producers = userPropertyEffectVisibilityProducers(for: effectKey)
        return producers.count == 1
            && producers.first?.valueType == .bool
            && startupInactiveEffectVisibilityTargets.contains(target)
    }

    private func userPropertyEffectVisibilityProducers(
        for effectKey: Graph.EffectKey
    ) -> Set<SceneDynamicUserPropertyProducer> {
        let target = SceneDynamicTarget.effectVisibility(
            layerID: effectKey.layerID,
            effectIndex: effectKey.effectIndex
        )
        return userPropertyProducers.filter { $0.target == target }
    }
}

/// Compiler identity is separate from the runtime backend because two ordered
/// compiler probes may intentionally produce the same execution backend.
nonisolated enum SceneEffectStageCompilerBackend: String, CaseIterable, Hashable {
    case standardBlur = "standard-blur"
}

/// Stable failure emitted by one migrated backend compiler. `details` carries
/// existing material/contract/frontend diagnostic codes without changing the
/// public chain rejection reason.
nonisolated struct SceneEffectStageCompilerFailure: Equatable {
    enum Phase: String {
        case graph
        case topology
        case material
        case shaderContract = "shader-contract"
        case shaderPreprocessor = "shader-preprocessor"
        case shaderFrontend = "shader-frontend"
        case textureBinding = "texture-binding"
        case uniformBinding = "uniform-binding"
        case compatibility
        case invariant
    }

    enum Code: String {
        case graphBlocked = "graph-blocked"
        case layerMissing = "layer-missing"
        case unsupportedContentKind = "unsupported-content-kind"
        case invalidMappedSize = "invalid-mapped-size"
        case effectIndexOutOfRange = "effect-index-out-of-range"
        case descriptorIDMismatch = "descriptor-id-mismatch"
        case descriptorDisabled = "descriptor-disabled"
        case nodeCoverageMismatch = "node-coverage-mismatch"
        case inputRoleMismatch = "input-role-mismatch"
        case finalOutputMismatch = "final-output-mismatch"
        case nodeEffectMismatch = "node-effect-mismatch"
        case nodeTargetMismatch = "node-target-mismatch"
        case explicitNodeBindingUnsupported = "explicit-node-binding-unsupported"
        case materialResolutionFailed = "material-resolution-failed"
        case materialTextureSlotUnsupported = "material-texture-slot-unsupported"
        case materialComboUnsupported = "material-combo-unsupported"
        case renderStateInvalid = "render-state-invalid"
        case renderStateNotFullscreenOverwrite = "render-state-not-fullscreen-overwrite"
        case materialDescriptorMissing = "material-descriptor-missing"
        case dynamicUserShaderValueUnsupported = "dynamic-user-shader-value-unsupported"
        case shaderContractMissing = "shader-contract-missing"
        case shaderContractAmbiguous = "shader-contract-ambiguous"
        case shaderSourceKindUnsupported = "shader-source-kind-unsupported"
        case shaderContractDiagnostic = "shader-contract-diagnostic"
        case shaderStageSetUnsupported = "shader-stage-set-unsupported"
        case shaderIncludeUnsupported = "shader-include-unsupported"
        case shaderStageMissing = "shader-stage-missing"
        case shaderSourceGraphMissing = "shader-source-graph-missing"
        case shaderSourceIdentityMismatch = "shader-source-identity-mismatch"
        case shaderVariantInvalid = "shader-variant-invalid"
        case shaderIncludeMissing = "shader-include-missing"
        case shaderIncludeAmbiguous = "shader-include-ambiguous"
        case shaderIncludeCycle = "shader-include-cycle"
        case shaderDirectiveUnsupported = "shader-directive-unsupported"
        case shaderModuleResolutionRejected = "shader-module-resolution-rejected"
        case shaderConditionInvalid = "shader-condition-invalid"
        case shaderPreprocessorBudgetExceeded = "shader-preprocessor-budget-exceeded"
        case shaderPreprocessorDiagnostic = "shader-preprocessor-diagnostic"
        case shaderPreparationInvariant = "shader-preparation-invariant"
        case shaderColorContractUnproven = "shader-color-contract-unproven"
        case shaderFrontendDiagnostic = "shader-frontend-diagnostic"
        case shaderFrontendInvariant = "shader-frontend-invariant"
        case framebufferSlotUnproven = "framebuffer-slot-unproven"
        case materialAnnotationInvalid = "material-annotation-invalid"
        case materialAliasConflict = "material-alias-conflict"
        case materialKeyCollision = "material-key-collision"
        case uniformSourceMissing = "uniform-source-missing"
        case uniformSourceAmbiguous = "uniform-source-ambiguous"
        case dynamicUniformUnsupported = "dynamic-uniform-unsupported"
        case timelineUniformUnsupported = "timeline-uniform-unsupported"
        case uniformConstantInvalid = "uniform-constant-invalid"
        case uniformBindingInvariant = "uniform-binding-invariant"
        case dedicatedProfileRejected = "dedicated-profile-rejected"
        case stageProgramInvariant = "stage-program-invariant"
    }

    let backend: SceneEffectStageCompilerBackend
    let phase: Phase
    let code: Code
    let details: [String]

    init(
        backend: SceneEffectStageCompilerBackend,
        phase: Phase,
        code: Code,
        details: [String] = []
    ) {
        self.backend = backend
        self.phase = phase
        self.code = code
        self.details = details
    }
}

nonisolated struct SceneEffectStageCompilerProbe {
    enum Outcome {
        case notApplicable
        case rejected(SceneEffectStageCompilerFailure)
    }

    let backend: SceneEffectStageCompilerBackend
    let outcome: Outcome
}

nonisolated enum SceneEffectStageBackendCompileResult<Plan> {
    case notApplicable
    case rejected(SceneEffectStageCompilerFailure)
    case accepted(Plan)

    var acceptedPlan: Plan? {
        guard case .accepted(let plan) = self else { return nil }
        return plan
    }

    nonisolated func mapAccepted<MappedPlan>(
        _ transform: (Plan) -> MappedPlan
    ) -> SceneEffectStageBackendCompileResult<MappedPlan> {
        switch self {
        case .notApplicable:
            return .notApplicable
        case .rejected(let failure):
            return .rejected(failure)
        case .accepted(let plan):
            return .accepted(transform(plan))
        }
    }
}

/// Converts each dedicated planner's existing fail-closed Optional boundary
/// into the shared typed result without running the planner twice. Candidate
/// matching remains owned by that same planner family and is evaluated only
/// after the exact planner declined the stage.
nonisolated enum SceneEffectStageDedicatedCompilerAdapter {
    nonisolated static func compile<Plan>(
        backend: SceneEffectStageCompilerBackend,
        candidate: () -> Bool,
        plan: () -> Plan?
    ) -> SceneEffectStageBackendCompileResult<Plan> {
        if let accepted = plan() {
            return .accepted(accepted)
        }
        guard candidate() else {
            return .notApplicable
        }
        return .rejected(.init(
            backend: backend,
            phase: .compatibility,
            code: .dedicatedProfileRejected
        ))
    }
}
