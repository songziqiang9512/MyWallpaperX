import Foundation

nonisolated struct SceneResolvedMaterialFailure: Error, Equatable {
    enum EffectLocalVisualFallback: String, Equatable {
        case optionalTextureUnavailable =
            "material-finalizer-optional-texture-unavailable"
        case optionalTexturePurposeMismatch =
            "material-finalizer-optional-texture-purpose-mismatch"
        case optionalTextureContentMismatch =
            "material-finalizer-optional-texture-content-mismatch"
        case optionalTextureSamplingUnresolved =
            "material-finalizer-optional-texture-sampling-unresolved"
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
    let boundedDetails: [String]

    init(
        phase: Phase,
        code: Code,
        slot: Int? = nil,
        provenance: SceneResolvedMaterialNode.TextureProvenance? = nil,
        effectLocalVisualFallback: EffectLocalVisualFallback? = nil,
        details: [String] = []
    ) {
        self.phase = phase
        self.code = code
        self.slot = slot
        self.provenance = provenance
        self.effectLocalVisualFallback = effectLocalVisualFallback
        boundedDetails = details.prefix(8).map { String($0.prefix(160)) }
    }
}

/// Static authored facts. Runtime texture metadata, readiness, purpose and
/// concrete dynamic values enter only while finalizing one immutable Program.
nonisolated struct SceneResolvedMaterialTemplate {
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
    }

    enum DynamicUniformSource: Hashable {
        case userProperty(String)
        case timeline
        case sceneScript
    }

    enum DynamicUniformScriptAttachment: Hashable {
        case mediaThumbnailAnimationRestart
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
            shaderContract: shaderContract,
            diagnosticProvenance: diagnosticProvenance
        )
    }

    private init(
        textureSlots: [TextureSlot?], combos: [Combo],
        inheritedInactiveCombos: [String],
        uniformDeclarations: [UniformDeclaration], renderState: SceneMaterialRenderState,
        graphRole: GraphRole, shaderContract: SceneShaderContract,
        diagnosticProvenance: DiagnosticProvenance
    ) {
        self.textureSlots = textureSlots
        self.combos = combos
        self.inheritedInactiveCombos = inheritedInactiveCombos
        self.uniformDeclarations = uniformDeclarations
        self.renderState = renderState
        self.graphRole = graphRole
        self.shaderContract = shaderContract
        self.diagnosticProvenance = diagnosticProvenance
    }
}

/// One fully resolved material pass for one immutable resource/dynamic snapshot.
nonisolated struct SceneResolvedMaterialProgram {
    enum OutputStorage: Hashable {
        case color
        case scalarRedUnorm
        case redGreenUnorm
    }

    enum OutputContract: Hashable {
        case color(SceneShaderColorContract)
        case scalarRedUnorm
        case redGreenUnorm
    }

    enum HostUniform: Hashable {
        case renderSize, modelViewProjection, modelViewProjectionInverse
        case layerModelMatrix
        case effectTextureProjectionMatrix
        case effectTextureProjectionMatrixInverse
        case time, dayTime, frameTime
        case pointerPosition, pointerPositionLast, parallaxPosition, screen
        case texelSize(scaleBitPattern: UInt64)
        case textureResolution(slot: Int)
        case audioSpectrumLeft(count: Int)
        case audioSpectrumRight(count: Int)
    }

    enum DynamicSourceKind: Hashable { case userProperty, timeline, sceneScript }

    enum TextureSelectionProvenance: Hashable {
        case authored(SceneResolvedMaterialNode.TextureProvenance)
        case shaderDefault
        case implicitFramebuffer
        case materialGraphInputAlias
    }

    enum UniformSourceSchema: Hashable {
        case host(HostUniform)
        case staticValue
        case dynamic(DynamicSourceKind)
    }

    struct ResolvedUniform {
        enum Source {
            case host(HostUniform)
            case staticValue
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
        let expectedPurpose: SceneTextureLoadPurpose
        let resource: SceneFrameTextureResource
    }

    struct AssemblyInput {
        let preparedShader: SceneShaderPreparedProgram
        let textureSlots: [TextureSlot?]
        let resolvedUniforms: [ResolvedUniform]
        let renderState: SceneMaterialRenderState
        let graphRole: SceneResolvedMaterialTemplate.GraphRole
        let outputStorage: OutputStorage

        init(
            preparedShader: SceneShaderPreparedProgram,
            textureSlots: [TextureSlot?],
            resolvedUniforms: [ResolvedUniform],
            renderState: SceneMaterialRenderState,
            graphRole: SceneResolvedMaterialTemplate.GraphRole,
            outputStorage: OutputStorage = .color
        ) {
            self.preparedShader = preparedShader
            self.textureSlots = textureSlots
            self.resolvedUniforms = resolvedUniforms
            self.renderState = renderState
            self.graphRole = graphRole
            self.outputStorage = outputStorage
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

    static func assemble(_ input: AssemblyInput) -> Self? {
        guard let derived = SceneResolvedMaterialProgramDerivation.derive(input) else {
            return nil
        }
        return Self(input: input, derived: derived)
    }

    static func assembleCompiled(
        _ input: AssemblyInput,
        frontend: SceneAuthoredShaderProgram,
        routeDecision: SceneGenericShaderRouteDecision
    ) -> Self? {
        guard let derived = SceneResolvedMaterialProgramDerivation.deriveCompiled(
            input,
            frontend: frontend
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
    }
}
