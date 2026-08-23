import Foundation

/// The only assembly boundary from runtime facts to an executable material
/// program. Every identity is projected from validated facts here; callers do
/// not provide cache keys, color claims, or partially packed uniform buffers.
nonisolated enum SceneResolvedMaterialProgramDerivation {
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate

    static func derive(_ input: Program.AssemblyInput) -> Program.Derived? {
        guard let frontend = compileFrontend(input.preparedShader) else { return nil }
        return derive(input, frontend: frontend)
    }

    static func deriveCompiled(
        _ input: Program.AssemblyInput,
        frontend: SceneAuthoredShaderProgram
    ) -> Program.Derived? {
        guard validPreparedStages(input.preparedShader),
              uniqueAndValid(frontend.uniformLayout) else { return nil }
        return derive(input, frontend: frontend)
    }

    private static func derive(
        _ input: Program.AssemblyInput,
        frontend: SceneAuthoredShaderProgram
    ) -> Program.Derived? {
        guard validPreparedStages(input.preparedShader),
              acceptsGraphRole(
                  transfer: frontend.colorTransfer,
                  outputStorage: input.outputStorage,
                  role: input.graphRole,
                  textureSlots: input.textureSlots
              ),
              input.renderState.supportsResolvedMaterialFullscreenOverwrite,
              let textures = resolveTextures(
                  input.textureSlots,
                  frontend: frontend
              ),
              SceneMaterialTextureTransformABI.validates(
                  layout: frontend.uniformLayout,
                  activeSlots: Set(textures.activeSlots)
              ),
              let uniforms = resolveUniforms(
                  input.resolvedUniforms,
                  layout: frontend.uniformLayout,
                  activeTextureSlots: Set(textures.activeSlots)
              ),
              let graphRole = SceneResolvedMaterialProgramIdentity.graphRole(
                  input.graphRole,
                  textureSlots: input.textureSlots,
                  activeTextureSlots: Set(textures.activeSlots)
              ),
              let output = resolveOutputContract(
                  outputStorage: input.outputStorage,
                  frontend: frontend,
                  textureSlots: input.textureSlots
              ) else {
            return nil
        }

        let renderState = SceneResolvedMaterialProgramIdentity.renderState(
            input.renderState
        )
        let shader = SceneResolvedMaterialProgramIdentity.shader(
            frontend,
            schemaVersion: input.preparedShader.vertex.frontendSchemaVersion
        )
        let outputIdentity = output.identity
        let semantic = Program.SemanticIdentity(
            shader: shader,
            textureSlots: textures.semantic,
            activeUniforms: uniforms.semantic,
            renderState: renderState,
            outputContract: outputIdentity,
            graphRole: graphRole
        )
        let exact = Program.ExactIdentity(
            semanticIdentity: semantic,
            prepared: SceneResolvedMaterialProgramIdentity.prepared(
                input.preparedShader
            ),
            textureSlots: textures.exact,
            uniformBytes: uniforms.bytes,
            dynamicUniforms: uniforms.dynamic
        )
        return Program.Derived(
            frontendProgram: frontend,
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
        textureSlots: [Program.TextureSlot?]
    ) -> OutputProjection? {
        switch outputStorage {
        case .color:
            guard let color = resolveColor(
                transfer: frontend.colorTransfer,
                textureSlots: textureSlots
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
        textureSlots: [Program.TextureSlot?]
    ) -> Bool {
        guard outputStorage == .color else { return true }
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
        let activeSlots: [Int]
        let semantic: [Program.TextureSemanticIdentity?]
        let exact: [Program.ExactTextureIdentity?]
    }

    private struct UniformProjection {
        let bytes: Data
        let semantic: [Program.ActiveUniformIdentity]
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

    private static func compileFrontend(
        _ prepared: SceneShaderPreparedProgram
    ) -> SceneAuthoredShaderProgram? {
        let output = SceneAuthoredShaderFrontend.compile(
            vertexSource: prepared.vertex.source,
            fragmentSource: prepared.fragment.source
        )
        guard output.diagnostics.isEmpty,
              let program = output.program,
              uniqueAndValid(program.uniformLayout) else {
            return nil
        }
        return program
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
        frontend: SceneAuthoredShaderProgram
    ) -> TextureProjection? {
        guard slots.count == 8 else { return nil }
        let activeSlots = frontend.textureBindings.map(\.slot)
        guard activeSlots == activeSlots.sorted(),
              Set(activeSlots).count == activeSlots.count,
              activeSlots.allSatisfy({ (0 ..< 8).contains($0) }),
              slots.enumerated().compactMap({ index, slot in
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
        let frontendBindings = Dictionary(uniqueKeysWithValues:
            frontend.textureBindings.map { ($0.slot, $0) }
        )
        var deviceRegistryID: UInt64?
        for index in activeSlots {
            guard let slot = slots[index],
                  let frontendBinding = frontendBindings[index],
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
                purpose: slot.expectedPurpose,
                content: content,
                sampling: candidate.sampling
            )
            exact[index] = exactIdentity
        }
        return TextureProjection(
            activeSlots: activeSlots,
            semantic: semantic,
            exact: exact
        )
    }

    private static func resolveUniforms(
        _ resolved: [Program.ResolvedUniform],
        layout: SceneAuthoredShaderUniformLayout,
        activeTextureSlots: Set<Int>
    ) -> UniformProjection? {
        guard resolved.count == layout.fields.count else { return nil }
        var bytes = Data(count: layout.byteSize)
        var semantic: [Program.ActiveUniformIdentity] = []
        var dynamic: [Program.ExactDynamicUniformIdentity] = []
        for (field, value) in zip(layout.fields, resolved) {
            guard value.field == field,
                  value.encodedValue.count == field.storageByteSize,
                  let source = uniformSourceIdentity(
                      value.source,
                      field: field,
                      activeTextureSlots: activeTextureSlots
                  ) else {
                return nil
            }
            bytes.replaceSubrange(
                field.offset ..< field.offset + field.storageByteSize,
                with: value.encodedValue
            )
            semantic.append(.init(
                fieldName: field.name,
                fieldType: field.type.rawValue,
                arrayCount: field.arrayCount,
                fieldOffset: field.offset,
                source: source
            ))
            if case let .dynamic(
                declared,
                target,
                resolvedSource,
                scriptAttachments
            ) = value.source {
                dynamic.append(.init(
                    target: target,
                    declaredSource: declared,
                    resolvedSource: resolvedSource,
                    scriptAttachments: scriptAttachments
                ))
            }
        }
        return UniformProjection(
            bytes: bytes,
            semantic: semantic,
            dynamic: dynamic
        )
    }

    private static func uniformSourceIdentity(
        _ source: Program.ResolvedUniform.Source,
        field: SceneAuthoredShaderUniformLayout.Field,
        activeTextureSlots: Set<Int>
    ) -> Program.UniformSourceSchema? {
        let expectedHost = SceneResolvedMaterialHostUniformSchema.resolve(
            field,
            activeTextureSlots: activeTextureSlots
        )
        switch source {
        case let .host(host):
            guard host == expectedHost else { return nil }
            return .host(host)
        case .staticValue:
            guard expectedHost == nil else { return nil }
            return .staticValue
        case let .neutralMissingTextureResolution(fact):
            guard expectedHost == nil,
                  field.name == fact.resolutionUniformName,
                  field.authoredName == fact.resolutionUniformName,
                  field.type == .float4,
                  field.arrayCount == nil,
                  !activeTextureSlots.contains(fact.resolutionSlot),
                  activeTextureSlots.contains(fact.coordinateTextureSlot)
            else { return nil }
            return .neutralMissingTextureResolution(fact)
        case let .dynamic(declared, _, resolved, _):
            guard expectedHost == nil,
                  let kind = dynamicKind(declared, resolved: resolved) else {
                return nil
            }
            return .dynamic(kind)
        }
    }

    private static func dynamicKind(
        _ declared: Template.DynamicUniformSource,
        resolved: SceneDynamicSource
    ) -> Program.DynamicSourceKind? {
        if resolved == .authored {
            return switch declared {
            case .userProperty: .userProperty
            case .timeline: .timeline
            case .sceneScript: .sceneScript
            }
        }
        switch (declared, resolved) {
        case (.userProperty, .userProperty): return .userProperty
        case (.timeline, .timeline): return .timeline
        case (.sceneScript, .sceneScript): return .sceneScript
        default: return nil
        }
    }

}
