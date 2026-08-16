import Foundation

nonisolated struct SceneResolvedMaterialFailure: Error, Equatable {
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
        case activeSamplerSchemaInvalid
        case shaderFrontendFailed
        case uniformBindingInvalid
        case staticUniformBindingInvalid
        case hostUniformDeclarationConflict
        case hostUniformBindingInvalid
        case dynamicUniformBindingInvalid
        case colorContractUnproven
        case frameSnapshotMismatch
        case identityInvariant
    }

    let phase: Phase
    let code: Code
    let slot: Int?
    let provenance: SceneResolvedMaterialNode.TextureProvenance?
    let boundedDetails: [String]

    init(
        phase: Phase,
        code: Code,
        slot: Int? = nil,
        provenance: SceneResolvedMaterialNode.TextureProvenance? = nil,
        details: [String] = []
    ) {
        self.phase = phase
        self.code = code
        self.slot = slot
        self.provenance = provenance
        boundedDetails = details.prefix(8).map { String($0.prefix(160)) }
    }
}

/// Static authored facts. Runtime texture metadata, readiness, purpose and
/// concrete dynamic values enter only while finalizing one immutable Program.
nonisolated struct SceneResolvedMaterialTemplate {
    struct UserPropertyRequest: Hashable { let key: String }

    enum KnownProviderRequest: Hashable {
        case system(String)
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
              Set(uniformDeclarations.map(\.name)).count == uniformDeclarations.count,
              uniformDeclarations.allSatisfy({ !$0.name.isEmpty }),
              graphRole.bindings.allSatisfy({ (0 ..< 8).contains($0.slot) }),
              Set(graphRole.bindings.map(\.slot)).count == graphRole.bindings.count
        else { return nil }
        return Self(
            textureSlots: textureSlots,
            combos: combos.sorted { $0.name < $1.name },
            uniformDeclarations: uniformDeclarations.sorted { $0.name < $1.name },
            renderState: renderState,
            graphRole: graphRole,
            shaderContract: shaderContract,
            diagnosticProvenance: diagnosticProvenance
        )
    }

    private init(
        textureSlots: [TextureSlot?], combos: [Combo],
        uniformDeclarations: [UniformDeclaration], renderState: SceneMaterialRenderState,
        graphRole: GraphRole, shaderContract: SceneShaderContract,
        diagnosticProvenance: DiagnosticProvenance
    ) {
        self.textureSlots = textureSlots
        self.combos = combos
        self.uniformDeclarations = uniformDeclarations
        self.renderState = renderState
        self.graphRole = graphRole
        self.shaderContract = shaderContract
        self.diagnosticProvenance = diagnosticProvenance
    }
}

/// One fully resolved material pass for one immutable resource/dynamic snapshot.
nonisolated struct SceneResolvedMaterialProgram {
    enum HostUniform: Hashable {
        case renderSize, modelViewProjection, layerModelMatrix
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
    }

    struct Derived {
        let frontendProgram: SceneAuthoredShaderProgram
        let uniformBytes: Data
        let colorContract: SceneShaderColorContract
        let semanticIdentity: SemanticIdentity
        let exactIdentity: ExactIdentity
    }

    let preparedShader: SceneShaderPreparedProgram
    let frontendProgram: SceneAuthoredShaderProgram
    let textureSlots: [TextureSlot?]
    let resolvedUniforms: [ResolvedUniform]
    let uniformBytes: Data
    let renderState: SceneMaterialRenderState
    let colorContract: SceneShaderColorContract
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
        frontend: SceneAuthoredShaderProgram
    ) -> Self? {
        guard let derived = SceneResolvedMaterialProgramDerivation.deriveCompiled(
            input,
            frontend: frontend
        ) else { return nil }
        return Self(input: input, derived: derived)
    }

    private init(input: AssemblyInput, derived: Derived) {
        preparedShader = input.preparedShader
        frontendProgram = derived.frontendProgram
        textureSlots = input.textureSlots
        resolvedUniforms = input.resolvedUniforms
        uniformBytes = derived.uniformBytes
        renderState = input.renderState
        colorContract = derived.colorContract
        semanticIdentity = derived.semanticIdentity
        exactIdentity = derived.exactIdentity
    }
}
