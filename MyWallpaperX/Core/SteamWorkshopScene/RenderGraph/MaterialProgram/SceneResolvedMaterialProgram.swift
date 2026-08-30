import Foundation

nonisolated struct SceneResolvedMaterialFailure: Error, Equatable {
    enum GenericOwnerFailure: String, Equatable {
        /// The generic route owns product output and exposes no shared
        /// rollback for this failure.
        case productOwnerRevoked = "generic-product-owner-revoked"
        /// A migrated profile selected its explicit shared rollback, but that
        /// rollback could not compile. No retained dedicated product owner may
        /// be revived after this point.
        case sharedRollbackExhausted = "generic-shared-rollback-exhausted"
    }

    enum EffectLocalVisualFallback: String, Equatable {
        case optionalTextureUnavailable =
            "material-finalizer-optional-texture-unavailable"
        case optionalTexturePurposeMismatch =
            "material-finalizer-optional-texture-purpose-mismatch"
        case optionalTextureContentMismatch =
            "material-finalizer-optional-texture-content-mismatch"
        case optionalTextureSamplingUnresolved =
            "material-finalizer-optional-texture-sampling-unresolved"
        case systemProviderUnavailable =
            "material-finalizer-system-provider-unavailable"
        case systemProviderPurposeMismatch =
            "material-finalizer-system-provider-purpose-mismatch"
        case systemProviderSamplingUnresolved =
            "material-finalizer-system-provider-sampling-unresolved"
    }

    enum Phase: String, Equatable {
        case graph
        case shaderContract
        case preparation
        case texture
        case uniform
        case state
        case frontend
        case color
        case invariant
    }

    enum Code: String, Equatable {
        case graphNodeInvalid
        case shaderIdentityMismatch
        case shaderContractInvalid
        case shaderSourceGraphMissing
        case textureSlotsInvalid
        case textureReferenceInvalid
        case userTextureUnknown
        case uniformDeclarationInvalid
        case uniformContributorPolicyUnproven
        case uniformScriptAttachmentUnproven
        case renderStateInvalid
        case resourceSnapshotUnresolved
        case textureBindingInvalid
        case animatedFrameMetadataInvalid
        case texturePurposeUnproven
        case textureMetadataIncomplete
        case shaderPreparationFailed
        case samplerBindingOrderInvalid
        case samplerBindingDuplicateSlot
        case samplerBindingIdentityMismatch
        case samplerInternalTargetUnsupported
        case activePassUnsupported
        case samplerVariantSchemaDivergence
        case authoredSamplerSchemaInvalid
        case shaderFrontendFailed
        case genericProductOwnerDeferred
        case uniformBindingInvalid
        case activeUniformSchemaMissing
        case uniformDeclarationConflict
        case staticUniformBindingInvalid
        case hostUniformDeclarationConflict
        case hostUniformBindingInvalid
        case dynamicUniformBindingInvalid
        case colorContractUnproven
        case frameSnapshotMismatch
        case identityInvariant
        case variantSelectionTemplateIdentityInvariant
        case variantSelectionReachabilityIdentityInvariant
        case variantSelectionKeyInvariant
        case variantSelectionUnexpectedFailure
        case finalizerUnexpectedFailure
        case textureReadinessIdentityInvariant
        case textureVariantKeyIdentityInvariant
        case graphRoleIdentityInvariant
        case programAssemblyIdentityInvariant
    }

    let phase: Phase
    let code: Code
    let slot: Int?
    let provenance: SceneResolvedMaterialNode.TextureProvenance?
    /// A typed local-failure hint, never standalone fallback authority.
    /// GraphExecutor must still prove the exact shared capability profile,
    /// optional sampler role, pair topology and previous-current rollback.
    let effectLocalVisualFallback: EffectLocalVisualFallback?
    /// Typed product-owner authority propagated from generic artifact routing.
    /// This is separate from bounded diagnostic strings so owner revocation
    /// cannot be inferred from compiler prose.
    let genericOwnerFailure: GenericOwnerFailure?
    let boundedDetails: [String]

    init(
        phase: Phase,
        code: Code,
        slot: Int? = nil,
        provenance: SceneResolvedMaterialNode.TextureProvenance? = nil,
        effectLocalVisualFallback: EffectLocalVisualFallback? = nil,
        genericOwnerFailure: GenericOwnerFailure? = nil,
        details: [String] = []
    ) {
        self.phase = phase
        self.code = code
        self.slot = slot
        self.provenance = provenance
        self.effectLocalVisualFallback = effectLocalVisualFallback
        self.genericOwnerFailure = genericOwnerFailure
        boundedDetails = details.prefix(8).map { String($0.prefix(160)) }
    }

    func withGenericOwnerFailure(
        _ failure: GenericOwnerFailure?
    ) -> Self {
        guard let failure, genericOwnerFailure == nil else { return self }
        return .init(
            phase: phase,
            code: code,
            slot: slot,
            provenance: provenance,
            effectLocalVisualFallback: effectLocalVisualFallback,
            genericOwnerFailure: failure,
            details: boundedDetails
        )
    }

    var mapsToGenericOwnerRevokedVisualFailure: Bool {
        switch genericOwnerFailure {
        case .productOwnerRevoked?:
            true
        case .sharedRollbackExhausted?:
            code == .shaderFrontendFailed
        case nil:
            false
        }
    }
}

/// Static authored facts. Runtime texture metadata, readiness, purpose and
/// concrete dynamic values enter only while finalizing one immutable Program.
nonisolated struct SceneResolvedMaterialTemplate {
    typealias Graph = SceneAuthoredEffectRenderPlan

    struct EffectContext: Hashable {
        let key: Graph.EffectKey
        let input: Graph.TextureIdentity
    }

    struct UserPropertyRequest: Hashable { let key: String }

    enum KnownProviderRequest: Hashable {
        case system(String)
        case namedLayerTarget(SceneNamedTextureReference)
        case sceneBackground(consumerLayerID: Int)
    }

    enum TextureReference: Hashable {
        case asset(SceneVFSAssetPath)
        case userProperty(UserPropertyRequest)
        case provider(KnownProviderRequest)
        case graph(SceneAuthoredEffectRenderPlan.TextureIdentity)
    }

    struct TextureCandidate: Hashable {
        let reference: TextureReference
        let provenance: SceneResolvedMaterialNode.TextureProvenance
    }

    struct TextureSlot: Hashable {
        let index: Int
        /// Resolver precedence from low to high. The last candidate is the
        /// selected override; earlier entries are provenance, not load fallback.
        let candidates: [TextureCandidate]
    }

    struct Combo: Hashable { let name: String; let value: Int }

    struct StaticUniformValue: Hashable {
        let valueKind: String
        let componentBitPatterns: [UInt64]
        let authoredBindingKeys: [String]
        /// True only when the original authored token parsed in full as one
        /// finite scalar. Lowered components alone cannot prove that malformed
        /// trailing tokens were not discarded.
        let authoredScalarProjectionProven: Bool

        init(
            valueKind: String,
            componentBitPatterns: [UInt64],
            authoredBindingKeys: [String],
            authoredScalarProjectionProven: Bool = false
        ) {
            self.valueKind = valueKind
            self.componentBitPatterns = componentBitPatterns
            self.authoredBindingKeys = authoredBindingKeys
            self.authoredScalarProjectionProven =
                authoredScalarProjectionProven
        }
    }

    enum DynamicUniformSource: Hashable {
        case userProperty(String)
        case timeline
        case sceneScript
    }

    enum DynamicUniformScriptAttachment: Hashable {
        case unproven
    }

    struct DynamicUniform: Hashable {
        let target: SceneDynamicTarget
        /// Proven value producers stay separate from SceneScript attachments.
        /// An unproven attachment may still produce a value and must fail closed.
        let valueContributors: [DynamicUniformSource]
        let scriptAttachments: [DynamicUniformScriptAttachment]
        let authoredFallback: StaticUniformValue?
        let authoredBindingKeys: [String]
    }

    enum UniformValue: Hashable {
        case staticExact(StaticUniformValue)
        case dynamic(DynamicUniform)
    }

    struct UniformDeclaration: Hashable {
        let name: String
        let value: UniformValue
    }

    enum GraphTextureRole: String, Hashable {
        case layerSource
        case effectOutput
        case framebuffer
    }

    struct GraphBindingRole: Hashable {
        let slot: Int
        let texture: GraphTextureRole
    }

    struct GraphRole: Hashable {
        let effectInput: GraphTextureRole
        let effectOutput: GraphTextureRole
        let nodeTarget: GraphTextureRole
        let bindings: [GraphBindingRole]
    }

    struct DiagnosticProvenance: Equatable {
        struct TextureSource: Equatable {
            let slot: Int
            let candidateIndex: Int
            let provenance: SceneResolvedMaterialNode.TextureProvenance
            let authoredValue: String
        }
        struct UniformSource: Equatable {
            let name: String
            let rawValue: String?
            let authoredBindingKeys: [String]
        }
        let nodeIndex: Int
        let authoredShaderPath: String
        let contractIdentity: String
        let contractCanonicalSHA256: String
        let textureSources: [TextureSource]
        let uniformSources: [UniformSource]
    }

    /// Always eight entries; authored holes remain nil.
    let textureSlots: [TextureSlot?]
    let combos: [Combo]
    let inheritedInactiveCombos: [String]
    let uniformDeclarations: [UniformDeclaration]
    let renderState: SceneMaterialRenderState
    let graphRole: GraphRole
    /// Temporary owner-transfer gate: only a whole static/no-mask/KERNEL0
    /// compound with a validated incumbent may authorize its generic finalizer.
    let unitPreviousBlurredCompositeGenericOwnerEligible: Bool
    /// Exact authored effect ingress retained for source-derived graph-input
    /// facts. GraphTextureRole alone deliberately cannot distinguish another
    /// layer, a named target, or a non-contiguous effect output.
    let effectContext: EffectContext?
    let shaderContract: SceneShaderContract
    let diagnosticProvenance: DiagnosticProvenance

    var comboValues: [String: Int] {
        combos.reduce(into: [:]) { $0[$1.name] = $1.value }
    }

    static func validated(
        textureSlots: [TextureSlot?],
        combos: [Combo],
        inheritedInactiveCombos: Set<String> = [],
        uniformDeclarations: [UniformDeclaration],
        renderState: SceneMaterialRenderState,
        graphRole: GraphRole,
        unitPreviousBlurredCompositeGenericOwnerEligible: Bool = false,
        effectContext: EffectContext? = nil,
        shaderContract: SceneShaderContract,
        diagnosticProvenance: DiagnosticProvenance
    ) -> Self? {
        guard textureSlots.count == 8,
              textureSlots.enumerated().allSatisfy({ index, slot in
                  slot.map { $0.index == index && !$0.candidates.isEmpty } ?? true
              }),
              Set(combos.map(\.name)).count == combos.count,
              combos.allSatisfy({ !$0.name.isEmpty }),
              inheritedInactiveCombos.allSatisfy({ !$0.isEmpty }),
              inheritedInactiveCombos.isDisjoint(with: combos.map(\.name)),
              Set(uniformDeclarations.map(\.name)).count == uniformDeclarations.count,
              uniformDeclarations.allSatisfy({ !$0.name.isEmpty }),
              graphRole.bindings.allSatisfy({ (0 ..< 8).contains($0.slot) }),
              Set(graphRole.bindings.map(\.slot)).count == graphRole.bindings.count
        else { return nil }
        return Self(
            textureSlots: textureSlots,
            combos: combos.sorted { $0.name < $1.name },
            inheritedInactiveCombos: inheritedInactiveCombos.sorted(),
            uniformDeclarations: uniformDeclarations.sorted { $0.name < $1.name },
            renderState: renderState,
            graphRole: graphRole,
            unitPreviousBlurredCompositeGenericOwnerEligible:
                unitPreviousBlurredCompositeGenericOwnerEligible,
            effectContext: effectContext,
            shaderContract: shaderContract,
            diagnosticProvenance: diagnosticProvenance
        )
    }

    private init(
        textureSlots: [TextureSlot?], combos: [Combo],
        inheritedInactiveCombos: [String],
        uniformDeclarations: [UniformDeclaration], renderState: SceneMaterialRenderState,
        graphRole: GraphRole,
        unitPreviousBlurredCompositeGenericOwnerEligible: Bool,
        effectContext: EffectContext?,
        shaderContract: SceneShaderContract,
        diagnosticProvenance: DiagnosticProvenance
    ) {
        self.textureSlots = textureSlots
        self.combos = combos
        self.inheritedInactiveCombos = inheritedInactiveCombos
        self.uniformDeclarations = uniformDeclarations
        self.renderState = renderState
        self.graphRole = graphRole
        self.unitPreviousBlurredCompositeGenericOwnerEligible =
            unitPreviousBlurredCompositeGenericOwnerEligible
        self.effectContext = effectContext
        self.shaderContract = shaderContract
        self.diagnosticProvenance = diagnosticProvenance
    }
}

/// Classifies the authored shape of a direct user-property value wrapper.
/// Unknown keys remain loss-preserving metadata; keys with producer semantics
/// stay fail-closed until their producer is modeled by the shared Program.
nonisolated enum SceneResolvedMaterialDirectUserBindingContract {
    typealias Template = SceneResolvedMaterialTemplate

    private static let requiredKeys: Set<String> = ["user", "value"]
    private static let producerKeys: Set<String> = [
        "animation", "script", "scriptproperties",
    ]

    static func matches(_ keys: [String]) -> Bool {
        let keySet = Set(keys)
        return keySet.count == keys.count
            && requiredKeys.isSubset(of: keySet)
            && keySet.isDisjoint(with: producerKeys)
    }

    static func matches(
        dynamic: Template.DynamicUniform,
        fallback: Template.StaticUniformValue
    ) -> Bool {
        dynamic.authoredBindingKeys == fallback.authoredBindingKeys
            && matches(dynamic.authoredBindingKeys)
            && matches(fallback.authoredBindingKeys)
    }
}

/// One fully resolved material pass for one immutable resource/dynamic snapshot.
nonisolated struct SceneResolvedMaterialProgram {
    enum OutputStorage: Hashable {
        case color
        case scalarRedUnorm
        case redGreenUnorm
        case scalarRedFloat16
        case redGreenFloat16
        case preservedRGBAUnorm
    }

    enum OutputContract: Hashable {
        case color(SceneShaderColorContract)
        case scalarRedUnorm
        case redGreenUnorm
        case scalarRedFloat16
        case redGreenFloat16
        case preservedRGBAUnorm
    }

    enum HostUniform: Hashable {
        case renderSize, modelViewProjection, modelViewProjectionInverse
        case layerModelMatrix
        case effectTextureProjectionMatrix
        case effectTextureProjectionMatrixInverse
        case time, dayTime, frameTime
        case pointerPosition, pointerPositionLast, pointerState
        case parallaxPosition, screen
        case texelSize(scaleBitPattern: UInt64)
        case textureResolution(slot: Int)
        case textureTransform(
            slot: Int,
            component: SceneMaterialTextureTransformABI.Component
        )
        case audioSpectrumLeft(count: Int)
        case audioSpectrumRight(count: Int)
    }

    enum DynamicSourceKind: Hashable { case userProperty, timeline, sceneScript }

    enum TextureSelectionProvenance: Hashable {
        case authored(SceneResolvedMaterialNode.TextureProvenance)
        case shaderDefault
        case implicitFramebuffer
        case materialGraphInputAlias
        case dormantUnresolvedMaterialGraphInput
    }

    enum UniformSourceSchema: Hashable {
        case host(HostUniform)
        case staticValue
        case dynamic(DynamicSourceKind)
        case neutralMissingTextureResolution(
            SceneAuthoredShaderNeutralTextureResolutionFact
        )
    }

    struct ResolvedUniform {
        enum Source {
            case host(HostUniform)
            case staticValue
            case neutralMissingTextureResolution(
                SceneAuthoredShaderNeutralTextureResolutionFact
            )
            case dynamic(
                declared: SceneResolvedMaterialTemplate.DynamicUniformSource,
                target: SceneDynamicTarget,
                resolvedSource: SceneDynamicSource,
                scriptAttachments: [
                    SceneResolvedMaterialTemplate.DynamicUniformScriptAttachment
                ]
            )
        }
        let field: SceneAuthoredShaderUniformLayout.Field
        let source: Source
        let encodedValue: Data
    }

    struct TextureSlot {
        let index: Int
        let reference: SceneResolvedMaterialTemplate.TextureReference
        let registryIdentity: SceneFrameTextureIdentity
        /// Audit-only origin. Cache identities intentionally describe the
        /// selected executable atom rather than how that atom was selected.
        let diagnosticSelectionProvenance: TextureSelectionProvenance
        let graphInputSourceFact:
            SceneResolvedMaterialGraphInputSourceSlotFact?
        let expectedPurpose: SceneTextureLoadPurpose
        let resource: SceneFrameTextureResource

        init(
            index: Int,
            reference: SceneResolvedMaterialTemplate.TextureReference,
            registryIdentity: SceneFrameTextureIdentity,
            diagnosticSelectionProvenance: TextureSelectionProvenance,
            graphInputSourceFact:
                SceneResolvedMaterialGraphInputSourceSlotFact? = nil,
            expectedPurpose: SceneTextureLoadPurpose,
            resource: SceneFrameTextureResource
        ) {
            self.index = index
            self.reference = reference
            self.registryIdentity = registryIdentity
            self.diagnosticSelectionProvenance = diagnosticSelectionProvenance
            self.graphInputSourceFact = graphInputSourceFact
            self.expectedPurpose = expectedPurpose
            self.resource = resource
        }
    }

    struct AssemblyInput {
        let preparedShader: SceneShaderPreparedProgram
        let textureSlots: [TextureSlot?]
        let resolvedUniforms: [ResolvedUniform]
        let renderState: SceneMaterialRenderState
        let graphRole: SceneResolvedMaterialTemplate.GraphRole
        let outputStorage: OutputStorage
        let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds

        init(
            preparedShader: SceneShaderPreparedProgram,
            textureSlots: [TextureSlot?],
            resolvedUniforms: [ResolvedUniform],
            renderState: SceneMaterialRenderState,
            graphRole: SceneResolvedMaterialTemplate.GraphRole,
            outputStorage: OutputStorage = .color,
            runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds = .none
        ) {
            self.preparedShader = preparedShader
            self.textureSlots = textureSlots
            self.resolvedUniforms = resolvedUniforms
            self.renderState = renderState
            self.graphRole = graphRole
            self.outputStorage = outputStorage
            self.runtimeLoopBounds = runtimeLoopBounds
        }
    }

    struct Derived {
        let frontendProgram: SceneAuthoredShaderProgram
        let uniformBytes: Data
        let outputContract: OutputContract
        let semanticIdentity: SemanticIdentity
        let exactIdentity: ExactIdentity
    }

    let preparedShader: SceneShaderPreparedProgram
    let routeDecision: SceneGenericShaderRouteDecision?
    let frontendProgram: SceneAuthoredShaderProgram
    let textureSlots: [TextureSlot?]
    let resolvedUniforms: [ResolvedUniform]
    let uniformBytes: Data
    let renderState: SceneMaterialRenderState
    let outputContract: OutputContract
    let semanticIdentity: SemanticIdentity
    let exactIdentity: ExactIdentity
    let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds

    static func assemble(_ input: AssemblyInput) -> Self? {
        guard let derived = SceneResolvedMaterialProgramDerivation.derive(input) else {
            return nil
        }
        return Self(input: input, derived: derived)
    }

    static func assembleCompiled(
        _ input: AssemblyInput,
        frontend: SceneAuthoredShaderProgram,
        routeDecision: SceneGenericShaderRouteDecision,
        conditionalGeneratedRGBInputContract:
            SceneResolvedMaterialProgramDerivation
                .ConditionalGeneratedRGBInputContract?
    ) -> Self? {
        guard let derived = SceneResolvedMaterialProgramDerivation.deriveCompiled(
            input,
            frontend: frontend,
            conditionalGeneratedRGBInputContract:
                conditionalGeneratedRGBInputContract
        ) else { return nil }
        return Self(
            input: input,
            derived: derived,
            routeDecision: routeDecision
        )
    }

    private init(input: AssemblyInput, derived: Derived) {
        preparedShader = input.preparedShader
        routeDecision = nil
        frontendProgram = derived.frontendProgram
        textureSlots = input.textureSlots
        resolvedUniforms = input.resolvedUniforms
        uniformBytes = derived.uniformBytes
        renderState = input.renderState
        outputContract = derived.outputContract
        semanticIdentity = derived.semanticIdentity
        exactIdentity = derived.exactIdentity
        runtimeLoopBounds = input.runtimeLoopBounds
    }

    private init(
        input: AssemblyInput,
        derived: Derived,
        routeDecision: SceneGenericShaderRouteDecision
    ) {
        preparedShader = input.preparedShader
        self.routeDecision = routeDecision
        frontendProgram = derived.frontendProgram
        textureSlots = input.textureSlots
        resolvedUniforms = input.resolvedUniforms
        uniformBytes = derived.uniformBytes
        renderState = input.renderState
        outputContract = derived.outputContract
        semanticIdentity = derived.semanticIdentity
        exactIdentity = derived.exactIdentity
        runtimeLoopBounds = input.runtimeLoopBounds
    }
}

/// One typed source fact for an active sampler that consumes the exact
/// renderer-owned ingress of its authored effect. This is classification only:
/// frame publication, purpose, generation, sampling and target safety remain
/// owned by the normal texture resolver and GraphExecutor gates.
nonisolated struct SceneResolvedMaterialGraphInputSourceSlotFact: Hashable {
    typealias Graph = SceneAuthoredEffectRenderPlan

    enum Provenance: String, Hashable {
        case explicitMaterialAlias
        case implicitMissingAlias
        case dormantUnresolvedMaterialAlias
    }

    let slot: Int
    let inputIdentity: Graph.TextureIdentity
    let provenance: Provenance
    let selectionProvenance:
        SceneResolvedMaterialProgram.TextureSelectionProvenance

    var diagnosticIdentity: String {
        let effect = inputIdentity.effect.map {
            "\($0.layerID):\($0.effectIndex):\($0.descriptorID)"
        } ?? "-"
        return [
            "slot\(slot)", provenance.rawValue, inputIdentity.kind.rawValue,
            String(inputIdentity.layerID), effect, inputIdentity.name ?? "-",
        ].joined(separator: ":")
    }
}
