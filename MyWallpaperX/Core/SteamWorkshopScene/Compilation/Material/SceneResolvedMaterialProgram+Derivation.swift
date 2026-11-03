import Foundation

nonisolated extension SceneResolvedMaterialProgram {
    /// Validated immutable ABI projection. The existing CompiledVariant owns
    /// this value; live textures, graph roles and uniform bytes never enter it.
    struct PreparedAssembly {
        typealias Failure = SceneResolvedMaterialFailure
        let preparedShader: SceneShaderPreparedProgram
        let frontendProgram: SceneAuthoredShaderProgram
        let renderState: SceneMaterialRenderState
        let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
        let preparedUniformBindings: [SceneResolvedMaterialPreparedUniformBinding]
        let activeUniformIdentities: [ActiveUniformIdentity]
        let activeTextureSlots: [Int]
        let activeTextureSlotSet: Set<Int>
        let textureBindingsBySlot: [SceneAuthoredShaderProgram.TextureBinding?]
        let samplerChannelUses: [Int: SceneAuthoredShaderProgram.TextureBinding.ChannelUse]
        let shaderIdentity: ShaderSemanticIdentity
        let preparedIdentity: ExactPreparedIdentity
        let renderStateIdentity: RenderStateIdentity
        let conditionalGeneratedRGBInputContract:
            SceneResolvedMaterialProgramDerivation.ConditionalGeneratedRGBInputContract?
        let associatedOverOverlaySlot: Int?
        let premultipliedColorInputSlots: Set<Int>

        /// Uniform ownership has already been resolved by preparation. This
        /// factory binds that plan to the frontend ABI once.
        init(
            preparedShader: SceneShaderPreparedProgram,
            frontend: SceneAuthoredShaderProgram,
            renderState: SceneMaterialRenderState,
            runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds,
            preparedUniformBindings: [SceneResolvedMaterialPreparedUniformBinding],
            conditionalGeneratedRGBInputContract:
                SceneResolvedMaterialProgramDerivation.ConditionalGeneratedRGBInputContract?,
            associatedOverOverlaySlot: Int?,
            premultipliedColorInputSlots: Set<Int>
        ) throws {
            guard SceneResolvedMaterialProgramDerivation.validPreparedStages(preparedShader),
                  (0 ..< 31).contains(frontend.uniformBufferIndex),
                  SceneResolvedMaterialProgramDerivation.uniqueAndValid(frontend.uniformLayout) else {
                throw Failure(phase: .frontend, code: .shaderFrontendFailed)
            }
            let slots = frontend.textureBindings.map(\.slot)
            guard slots == slots.sorted() else {
                throw Failure(phase: .invariant, code: .samplerBindingOrderInvalid,
                              details: slots.map(String.init))
            }
            var seen = Set<Int>()
            for binding in frontend.textureBindings {
                let slot = binding.slot
                guard seen.insert(slot).inserted else {
                    throw Failure(phase: .invariant, code: .samplerBindingDuplicateSlot, slot: slot)
                }
                guard (0 ..< 8).contains(slot) else {
                    throw Failure(phase: .invariant, code: .samplerBindingIdentityMismatch,
                                  slot: slot, details: ["slot-out-of-range"])
                }
                guard binding.name == "g_Texture\(slot)" else {
                    throw Failure(phase: .invariant, code: .samplerBindingIdentityMismatch,
                                  slot: slot, details: ["sampler-name-or-slot", binding.name, "g_Texture\(slot)"])
                }
            }
            guard renderState.supportsResolvedMaterialFullscreenOverwrite else {
                throw Failure(phase: .state, code: .renderStateInvalid)
            }
            guard preparedUniformBindings.map(\.field) == frontend.uniformLayout.fields else {
                throw Failure(phase: .uniform, code: .uniformBindingInvalid,
                              details: ["prepared-uniform-layout"])
            }
            activeUniformIdentities = preparedUniformBindings.map { binding in
                let source: UniformSourceSchema
                switch binding.source {
                case let .host(host): source = .host(host)
                case .staticValue, .selfCompositeTextureResolution: source = .staticValue
                case let .neutralMissingTextureResolution(fact):
                    source = .neutralMissingTextureResolution(fact)
                case let .dynamic(dynamic):
                    let kind: DynamicSourceKind = switch dynamic.contributor {
                    case .userProperty: .userProperty
                    case .timeline: .timeline
                    case .sceneScript: .sceneScript
                    }
                    source = .dynamic(kind)
                }
                let field = binding.field
                return .init(fieldName: field.name, fieldType: field.type.rawValue,
                             arrayCount: field.arrayCount, fieldOffset: field.offset,
                             source: source)
            }
            var bindings = Array<SceneAuthoredShaderProgram.TextureBinding?>(
                repeating: nil, count: 8
            )
            for binding in frontend.textureBindings { bindings[binding.slot] = binding }
            self.preparedShader = preparedShader
            frontendProgram = frontend
            self.renderState = renderState
            self.runtimeLoopBounds = runtimeLoopBounds
            self.preparedUniformBindings = preparedUniformBindings
            activeTextureSlots = slots
            activeTextureSlotSet = Set(slots)
            textureBindingsBySlot = bindings
            samplerChannelUses = Dictionary(uniqueKeysWithValues:
                frontend.textureBindings.map { ($0.slot, $0.channelUse) }
            )
            shaderIdentity = SceneResolvedMaterialProgramIdentity.shader(
                frontend, schemaVersion: preparedShader.vertex.frontendSchemaVersion
            )
            preparedIdentity = SceneResolvedMaterialProgramIdentity.prepared(preparedShader)
            renderStateIdentity = SceneResolvedMaterialProgramIdentity.renderState(renderState)
            self.conditionalGeneratedRGBInputContract = conditionalGeneratedRGBInputContract
            self.associatedOverOverlaySlot = associatedOverOverlaySlot
            self.premultipliedColorInputSlots = premultipliedColorInputSlots
        }
    }
}

/// The only assembly boundary from runtime facts to an executable material
/// program. Every identity is projected from validated facts here; callers do
/// not provide cache keys, color claims, or partially packed uniform buffers.
nonisolated enum SceneResolvedMaterialProgramDerivation {
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate

    static func derive(
        _ input: Program.FrameAssemblyInput,
        prepared: Program.PreparedAssembly
    ) -> Program.Derived? {
        let frontend = prepared.frontendProgram
        guard acceptsGraphRole(
                  transfer: frontend.colorTransfer,
                  outputStorage: input.outputStorage,
                  role: input.graphRole,
                  colorBoundary: frontend.colorBoundary,
                  textureSlots: input.textureSlots
              ),
              let textures = resolveTextures(
                  input.textureSlots,
                  prepared: prepared
              ),
              let uniforms = resolveUniforms(
                  input.resolvedUniforms,
                  prepared: prepared
              ),
              let graphRole = SceneResolvedMaterialProgramIdentity.graphRole(
                  input.graphRole,
                  textureSlots: input.textureSlots,
                  activeTextureSlots: prepared.activeTextureSlotSet
              ),
              let output = resolveOutputContract(
                  outputStorage: input.outputStorage,
                  frontend: frontend,
                  textureSlots: input.textureSlots,
                  conditionalGeneratedRGBInputContract:
                    prepared.conditionalGeneratedRGBInputContract,
                  associatedOverOverlaySlot: prepared.associatedOverOverlaySlot,
                  premultipliedColorInputSlots:
                    prepared.premultipliedColorInputSlots
              ) else {
            return nil
        }

        let outputIdentity = output.identity
        let semantic = Program.SemanticIdentity(
            shader: prepared.shaderIdentity,
            textureSlots: textures.semantic,
            activeUniforms: prepared.activeUniformIdentities,
            renderState: prepared.renderStateIdentity,
            outputContract: outputIdentity,
            graphRole: graphRole,
            runtimeLoopBounds: prepared.runtimeLoopBounds
        )
        let exact = Program.ExactIdentity(
            semanticIdentity: semantic,
            prepared: prepared.preparedIdentity,
            textureSlots: textures.exact,
            uniformBytes: uniforms.bytes,
            dynamicUniforms: uniforms.dynamic
        )
        return Program.Derived(
            preparedAssembly: prepared,
            uniformBytes: uniforms.bytes,
            outputContract: output.contract,
            semanticIdentity: semantic,
            exactIdentity: exact
        )
    }

    private struct OutputProjection {
        let contract: Program.OutputContract
        let identity: Program.OutputContractIdentity
    }

    private static func resolveOutputContract(
        outputStorage: Program.OutputStorage,
        frontend: SceneAuthoredShaderProgram,
        textureSlots: [Program.TextureSlot?],
        conditionalGeneratedRGBInputContract:
            ConditionalGeneratedRGBInputContract?,
        associatedOverOverlaySlot: Int? = nil,
        premultipliedColorInputSlots: Set<Int> = []
    ) -> OutputProjection? {
        switch outputStorage {
        case .color:
            guard let color = resolveColor(
                transfer: frontend.colorTransfer,
                textureSlots: textureSlots,
                conditionalGeneratedRGBInputContract:
                    conditionalGeneratedRGBInputContract,
                associatedOverOverlaySlot: associatedOverOverlaySlot,
                premultipliedColorInputSlots:
                    premultipliedColorInputSlots,
                colorBoundary: frontend.colorBoundary
            ) else { return nil }
            let identity = Program.ColorContractIdentity(
                framebufferInput: SceneResolvedMaterialProgramIdentity.color(
                    color.framebufferInput
                ),
                fragmentOutput: SceneResolvedMaterialProgramIdentity.color(
                    color.fragmentOutput
                )
            )
            return .init(
                contract: .color(.init(
                    framebufferInput: .resolved(color.framebufferInput),
                    fragmentOutput: .resolved(color.fragmentOutput)
                )),
                identity: .color(identity)
            )
        case .scalarRedUnorm:
            guard frontend.fragmentOutputChannelUse == .redDefined else {
                return nil
            }
            return .init(
                contract: .scalarRedUnorm,
                identity: .scalarRedUnorm
            )
        case .redGreenUnorm:
            guard frontend.fragmentOutputChannelUse == .redDefined else {
                return nil
            }
            return .init(
                contract: .redGreenUnorm,
                identity: .redGreenUnorm
            )
        case .scalarRedFloat16:
            guard frontend.fragmentOutputChannelUse == .redDefined else {
                return nil
            }
            return .init(
                contract: .scalarRedFloat16,
                identity: .scalarRedFloat16
            )
        case .redGreenFloat16:
            guard frontend.fragmentOutputChannelUse == .redDefined else {
                return nil
            }
            return .init(
                contract: .redGreenFloat16,
                identity: .redGreenFloat16
            )
        case .preservedRGBAUnorm:
            guard frontend.fragmentOutputChannelUse == .redDefined else {
                return nil
            }
            return .init(
                contract: .preservedRGBAUnorm,
                identity: .preservedRGBAUnorm
            )
        }
    }

    private static func acceptsGraphRole(
        transfer: SceneShaderColorTransfer,
        outputStorage: Program.OutputStorage,
        role: Template.GraphRole,
        colorBoundary: SceneShaderColorBoundary?,
        textureSlots: [Program.TextureSlot?]
    ) -> Bool {
        guard outputStorage == .color, colorBoundary == nil else { return true }
        guard case let .straightAlphaUNorm(slot) = transfer else { return true }
        guard role.effectInput == .layerSource,
              role.effectOutput == .effectOutput,
              role.nodeTarget == .effectOutput,
              textureSlots.indices.contains(slot),
              let texture = textureSlots[slot],
              case let .graph(identity) = texture.reference,
              identity.kind == .layerSource else { return false }
        return role.bindings.isEmpty
            || (role.bindings.count == 1 && role.bindings.contains {
                $0.slot == slot && $0.texture == .layerSource
            })
    }

    private struct TextureProjection {
        let semantic: [Program.TextureSemanticIdentity?]
        let exact: [Program.ExactTextureIdentity?]
    }

    private struct UniformProjection {
        let bytes: Data
        let dynamic: [Program.ExactDynamicUniformIdentity]
    }

    static func validPreparedStages(
        _ prepared: SceneShaderPreparedProgram
    ) -> Bool {
        let currentSchema = SceneShaderVariantEnvironment.frontendSchemaVersion
        return prepared.vertex.stage == .vertex
            && prepared.fragment.stage == .fragment
            && prepared.vertex.frontendSchemaVersion == currentSchema
            && prepared.fragment.frontendSchemaVersion == currentSchema
            && prepared.vertex.sourceDialect == .wallpaperEngineGLSLLike
            && prepared.fragment.sourceDialect == .wallpaperEngineGLSLLike
            && prepared.vertex.backend == .mwxMetal
            && prepared.fragment.backend == .mwxMetal
            && !prepared.cacheKey.isEmpty
            && digestFields(prepared.vertex).allSatisfy { !$0.isEmpty }
            && digestFields(prepared.fragment).allSatisfy { !$0.isEmpty }
    }

    private static func digestFields(
        _ source: SceneShaderPreparedSource
    ) -> [String] {
        [
            source.dependencySHA256,
            source.moduleDependencySHA256,
            source.variantSHA256,
            source.preparedSHA256,
        ]
    }

    static func uniqueAndValid(
        _ layout: SceneAuthoredShaderUniformLayout
    ) -> Bool {
        guard layout.byteSize >= 0,
              layout.byteSize <= 4_096,
              layout.byteSize.isMultiple(of: 16),
              Set(layout.fields.map(\.name)).count == layout.fields.count else {
            return false
        }
        var end = 0
        for field in layout.fields {
            guard !field.name.isEmpty,
                  field.offset >= end,
                  field.offset.isMultiple(of: field.type.alignment),
                  field.arrayCount.map({ (1 ... 64).contains($0) }) ?? true,
                  field.offset <= layout.byteSize - field.storageByteSize else {
                return false
            }
            end = field.offset + field.storageByteSize
        }
        return end <= layout.byteSize
    }

    private static func resolveTextures(
        _ slots: [Program.TextureSlot?],
        prepared: Program.PreparedAssembly
    ) -> TextureProjection? {
        guard slots.count == 8 else { return nil }
        let activeSlots = prepared.activeTextureSlots
        guard slots.enumerated().compactMap({ index, slot in
                  slot == nil ? nil : index
              }) == activeSlots else {
            return nil
        }

        var semantic = Array<Program.TextureSemanticIdentity?>(
            repeating: nil,
            count: 8
        )
        var exact = Array<Program.ExactTextureIdentity?>(
            repeating: nil,
            count: 8
        )
        var deviceRegistryID: UInt64?
        for index in activeSlots {
            guard let slot = slots[index],
                  let frontendBinding = prepared.textureBindingsBySlot[index],
                  slot.index == index,
                  SceneResolvedMaterialProgramIdentity.registryIdentity(
                      slot.registryIdentity,
                      matches: slot.reference,
                      purpose: slot.expectedPurpose
                  ),
                  slot.resource.publication.requestIdentity == slot.registryIdentity,
                  slot.expectedPurpose == slot.resource.publication.candidate.purpose,
                  slot.resource.publication.isComplete,
                  slot.resource.publication.candidate.sampling
                      .isResolvedForMaterialProgram,
                  SceneTextureSlotBinding(
                      slotIndex: index,
                      candidate: slot.resource.publication.candidate
                  ) != nil,
                  slot.resource.publication.candidate
                      .materialProgramUVTransform() != nil,
                  graphInputSourceFactMatches(slot),
                  let referenceKind = SceneResolvedMaterialProgramIdentity
                      .textureReferenceKind(slot.reference),
                  let content = SceneResolvedMaterialProgramIdentity.textureContent(
                      slot.resource.publication.candidate.content
                  ) else {
                return nil
            }
            let candidate = slot.resource.publication.candidate
            if candidate.content == .scalarRedUnorm
                || candidate.content == .scalarRedFloat16,
               ![.redOnly, .wholeVector].contains(frontendBinding.channelUse) {
                return nil
            }
            if candidate.content == .redGreenUnorm
                || candidate.content == .redGreenFloat16,
               ![.redOnly, .greenOnly, .redGreenOnly, .wholeVector]
                .contains(frontendBinding.channelUse) {
                return nil
            }
            let exactIdentity = SceneResolvedMaterialProgramIdentity.exactTexture(slot)
            guard deviceRegistryID == nil || deviceRegistryID == exactIdentity.deviceRegistryID else {
                return nil
            }
            deviceRegistryID = exactIdentity.deviceRegistryID
            semantic[index] = .init(
                slot: index,
                referenceKind: referenceKind,
                graphInputSource: slot.graphInputSourceFact,
                purpose: slot.expectedPurpose,
                content: content,
                sampling: candidate.sampling
            )
            exact[index] = exactIdentity
        }
        return TextureProjection(
            semantic: semantic,
            exact: exact
        )
    }

    private static func graphInputSourceFactMatches(
        _ slot: Program.TextureSlot
    ) -> Bool {
        guard let fact = slot.graphInputSourceFact else {
            if case .dormantUnresolvedMaterialGraphInput =
                slot.diagnosticSelectionProvenance {
                return false
            }
            return true
        }
        guard slot.index == fact.slot,
              slot.diagnosticSelectionProvenance == fact.selectionProvenance,
              case let .graph(identity) = slot.reference else { return false }
        return identity == fact.inputIdentity
    }

    private static func resolveUniforms(
        _ resolved: [Program.ResolvedUniform],
        prepared: Program.PreparedAssembly
    ) -> UniformProjection? {
        let bindings = prepared.preparedUniformBindings
        guard resolved.count == bindings.count else { return nil }
        var bytes = Data(count: prepared.frontendProgram.uniformLayout.byteSize)
        var dynamic: [Program.ExactDynamicUniformIdentity] = []
        for (binding, value) in zip(bindings, resolved) {
            let field = binding.field
            guard value.encodedValue.count == field.storageByteSize else { return nil }
            bytes.replaceSubrange(
                field.offset ..< field.offset + field.storageByteSize,
                with: value.encodedValue
            )
            if case let .dynamic(prepared) = binding.source {
                guard let resolvedSource = value.resolvedSource else { return nil }
                dynamic.append(.init(
                    target: prepared.declaration.target,
                    declaredSource: prepared.contributor,
                    resolvedSource: resolvedSource,
                    scriptAttachments: prepared.declaration.scriptAttachments
                ))
            }
        }
        return UniformProjection(bytes: bytes, dynamic: dynamic)
    }
}
