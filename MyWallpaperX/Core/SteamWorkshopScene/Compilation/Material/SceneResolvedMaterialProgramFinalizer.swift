import Foundation
import simd

nonisolated struct SceneResolvedMaterialFrameSnapshot {
    typealias Failure = SceneResolvedMaterialFailure

    fileprivate let textureSnapshot: SceneFrameTextureRegistrySnapshot
    fileprivate let dynamicSnapshot: SceneDynamicSnapshot
    fileprivate let frameInputs: SceneAuthoredShaderFrameInputs

    var frameIndex: UInt64 { frameInputs.frameIndex }

    var audioSpectrum: SceneAuthoredShaderAudioSpectrumInputs {
        frameInputs.audioSpectrum
    }

    var textureRegistrySnapshot: SceneFrameTextureRegistrySnapshot {
        textureSnapshot
    }

    static func validated(
        textureSnapshot: SceneFrameTextureRegistrySnapshot,
        dynamicSnapshot: SceneDynamicSnapshot,
        frameInputs: SceneAuthoredShaderFrameInputs
    ) -> Result<Self, Failure> {
        guard textureSnapshot.frameIndex == dynamicSnapshot.frameIndex,
              dynamicSnapshot.frameIndex == frameInputs.frameIndex else {
            return .failure(.init(
                phase: .invariant,
                code: .frameSnapshotMismatch
            ))
        }
        return .success(.init(
            textureSnapshot: textureSnapshot,
            dynamicSnapshot: dynamicSnapshot,
            frameInputs: frameInputs
        ))
    }

    func finalizationInput(
        template: SceneResolvedMaterialTemplate,
        layerID: Int = 0,
        renderSize: CGSize,
        modelViewProjection: simd_float4x4,
        layerModelMatrix: simd_float4x4,
        effectOutputModelViewProjection: simd_float4x4,
        effectTextureProjectionMatrixInverse: simd_float4x4,
        implicitFramebufferIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity? = nil
    ) -> SceneResolvedMaterialFinalizationInput {
        .init(
            template: template,
            layerID: layerID,
            frameSnapshot: self,
            renderSize: renderSize,
            modelViewProjection: modelViewProjection,
            layerModelMatrix: layerModelMatrix,
            effectOutputModelViewProjection: effectOutputModelViewProjection,
            effectTextureProjectionMatrixInverse: effectTextureProjectionMatrixInverse,
            implicitFramebufferIdentity: implicitFramebufferIdentity
        )
    }

    func replacingTextureSnapshot(
        _ replacement: SceneFrameTextureRegistrySnapshot
    ) -> Self? {
        guard replacement.frameEpoch == textureSnapshot.frameEpoch,
              replacement.frameIndex == textureSnapshot.frameIndex else {
            return nil
        }
        return .init(
            textureSnapshot: replacement,
            dynamicSnapshot: dynamicSnapshot,
            frameInputs: frameInputs
        )
    }

    func overlayingGraphResources(
        _ resources: [
            SceneAuthoredEffectRenderPlan.TextureIdentity: SceneFrameTextureResource
        ]
    ) -> Self? {
        guard let replacement = textureSnapshot.overlayingGraphResources(resources) else {
            return nil
        }
        return replacingTextureSnapshot(replacement)
    }

    func overlayingSceneBackground(
        consumerLayerID: Int,
        resource: SceneFrameTextureResource
    ) -> Self? {
        guard let replacement = textureSnapshot.overlayingSceneBackground(
            consumerLayerID: consumerLayerID,
            resource: resource
        ) else { return nil }
        return replacingTextureSnapshot(replacement)
    }

    func overlayingNamedLayerTarget(
        _ reference: SceneNamedTextureReference,
        resource: SceneFrameTextureResource
    ) -> Self? {
        guard let replacement = textureSnapshot.overlayingNamedLayerTarget(
            reference,
            resource: resource
        ) else { return nil }
        return replacingTextureSnapshot(replacement)
    }

}

nonisolated struct SceneResolvedMaterialFinalizationInput {
    let template: SceneResolvedMaterialTemplate
    /// Consumer layer identity for same-layer composite provenance.
    let layerID: Int
    fileprivate let frameSnapshot: SceneResolvedMaterialFrameSnapshot
    let renderSize: CGSize
    let modelViewProjection: simd_float4x4
    let layerModelMatrix: simd_float4x4
    let effectOutputModelViewProjection: simd_float4x4
    let effectTextureProjectionMatrixInverse: simd_float4x4
    /// Current full-frame graph input for shader samplers that explicitly
    /// declare a `framebuffer` or `previous` material alias without an authored
    /// texture binding.
    let implicitFramebufferIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity?

    var textureSnapshot: SceneFrameTextureRegistrySnapshot {
        frameSnapshot.textureSnapshot
    }

    var dynamicSnapshot: SceneDynamicSnapshot {
        frameSnapshot.dynamicSnapshot
    }

    fileprivate func uniformInputs(
        textureSlots: [SceneResolvedMaterialProgram.TextureSlot?]
    ) -> SceneAuthoredShaderUniformInputs {
        .init(
            frameIndex: frameSnapshot.frameInputs.frameIndex,
            renderSize: renderSize,
            screenSize: frameSnapshot.frameInputs.screenSize,
            modelViewProjection: modelViewProjection,
            layerModelMatrix: layerModelMatrix,
            effectOutputModelViewProjection:
                effectOutputModelViewProjection,
            effectTextureProjectionMatrix:
                effectTextureProjectionMatrixInverse.inverse,
            effectTextureProjectionMatrixInverse: effectTextureProjectionMatrixInverse,
            sceneTime: frameSnapshot.frameInputs.sceneTime,
            dayTime: frameSnapshot.frameInputs.dayTime,
            frameTime: frameSnapshot.frameInputs.frameTime,
            pointerCurrentNDC: frameSnapshot.frameInputs.pointerCurrentNDC,
            pointerPreviousNDC: frameSnapshot.frameInputs.pointerPreviousNDC,
            pointerPrimaryButtonDown:
                frameSnapshot.frameInputs.pointerPrimaryButtonDown,
            parallaxPositionNDC:
                frameSnapshot.frameInputs.parallaxPositionNDC,
            texturePhysicalSizes: Dictionary(
                uniqueKeysWithValues: textureSlots.compactMap { slot in
                    slot.map {
                        ($0.index, $0.resource.publication.candidate.physicalSize)
                    }
                }
            ),
            audioSpectrum: frameSnapshot.frameInputs.audioSpectrum
        )
    }

}

nonisolated enum SceneResolvedMaterialProgramFinalizer {
    typealias Failure = SceneResolvedMaterialFailure
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate
    typealias PreparedUniformBinding =
        SceneResolvedMaterialPreparedUniformBinding

    /// Compiles the complete uniform ownership table for one shader variant.
    /// Frame finalization must never rediscover whether a field is host,
    /// authored-static, dynamic, or texture metadata.
    static func prepareUniformBindings(
        template: Template,
        fields: [SceneAuthoredShaderUniformLayout.Field],
        activeUniforms: [String: SceneResolvedMaterialShaderSchema.Uniform],
        activeTextureSlots: Set<Int>,
        neutralTextureResolution:
            SceneAuthoredShaderNeutralTextureResolutionFact?
    ) throws -> [PreparedUniformBinding] {
        try fields.map { field in
            let schema = activeUniforms[field.name]
            let keys = Set(schema?.materialKeys ?? [field.name])
            let declarations = template.uniformDeclarations.filter {
                keys.contains($0.name)
            }
            if let host = SceneResolvedMaterialUniformEncoder.hostUniform(
                field,
                activeTextureSlots: activeTextureSlots
            ) {
                guard declarations.isEmpty else {
                    throw failure(
                        .uniform,
                        .hostUniformDeclarationConflict,
                        details: [field.name]
                    )
                }
                return .init(field: field, source: .host(host))
            }
            guard let schema else {
                throw failure(
                    .uniform,
                    .activeUniformSchemaMissing,
                    details: [field.name]
                )
            }
            if declarations.isEmpty {
                if let fact = preparedNeutralTextureResolution(
                    field: field,
                    schema: schema,
                    template: template,
                    activeTextureSlots: activeTextureSlots,
                    fact: neutralTextureResolution
                ) {
                    return .init(
                        field: field,
                        source: .neutralMissingTextureResolution(fact)
                    )
                }
                if let source = preparedSelfCompositeTextureResolution(
                    field: field,
                    schema: schema,
                    template: template,
                    activeTextureSlots: activeTextureSlots
                ) {
                    return .init(field: field, source: source)
                }
                guard let fallback = schema.defaultValue,
                      let encoded = SceneResolvedMaterialUniformEncoder.encode(
                          fallback,
                          as: field.type
                      ) else {
                    throw failure(
                        .uniform,
                        .staticUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                return .init(field: field, source: .staticValue(encoded))
            }
            guard declarations.count == 1,
                  let declaration = declarations.first else {
                throw failure(
                    .uniform,
                    .uniformDeclarationConflict,
                    details: [field.name]
                )
            }
            switch declaration.value {
            case let .staticExact(value):
                guard let encoded = SceneResolvedMaterialUniformProjection
                        .encodeAuthoredStatic(
                            value,
                            schema: schema,
                            field: field
                        ) else {
                    throw failure(
                        .uniform,
                        .staticUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                return .init(field: field, source: .staticValue(encoded))
            case let .dynamic(dynamic):
                let contributor = try soleValueContributor(
                    dynamic,
                    name: field.name
                )
                try validateScriptAttachments(
                    dynamic.scriptAttachments,
                    contributor: contributor,
                    name: field.name
                )
                return .init(
                    field: field,
                    source: .dynamic(.init(
                        declaration: dynamic,
                        contributor: contributor,
                        fallback: dynamic.authoredFallback
                            ?? schema.defaultValue,
                        schema: schema
                    ))
                )
            }
        }
    }

    static func finalize(
        _ input: SceneResolvedMaterialFinalizationInput,
        variantCache: SceneResolvedMaterialVariantCache,
        outputStorage: SceneResolvedMaterialProgram.OutputStorage = .color
    ) -> Result<Program, Failure> {
        do {
            guard input.template.renderState.supportsResolvedMaterialFullscreenOverwrite else {
                throw failure(.state, .renderStateInvalid)
            }
            let selection: SceneResolvedMaterialVariantCache.Selection
            switch variantCache.resolveSelection(input) {
            case let .success(value): selection = value
            case let .failure(error): throw error
            }
            let texture = try SceneResolvedMaterialTextureResolver.resolve(
                input,
                variant: selection.variant,
                reachableSamplers: selection.reachableSamplers
            )
            switch outputStorage {
            case .color:
                if let failure = colorSampleFailure(
                    variant: selection.variant,
                    textureSlots: texture.slots
                ) { throw failure }
                guard SceneResolvedMaterialProgramDerivation.hasResolvedColorContract(
                    transfer: texture.frontend.colorTransfer,
                    textureSlots: texture.slots,
                    conditionalGeneratedRGBInputContract:
                        selection.variant.conditionalGeneratedRGBInputContract,
                    associatedOverOverlaySlot:
                        selection.variant.associatedOverOverlaySlot,
                    premultipliedColorInputSlots:
                        selection.variant.premultipliedColorInputSlots
                ) else {
                    throw failure(
                        .color,
                        .colorContractUnproven,
                        details: colorContractFailureDetails(
                            transfer: texture.frontend.colorTransfer,
                            slots: texture.slots
                        )
                    )
                }
            case .scalarRedUnorm, .scalarRedFloat16:
                guard texture.frontend.fragmentOutputChannelUse == .redDefined else {
                    throw failure(.color, .colorContractUnproven)
                }
            case .redGreenUnorm, .redGreenFloat16:
                guard texture.frontend.fragmentOutputChannelUse == .redDefined else {
                    throw failure(.color, .colorContractUnproven)
                }
            case .preservedRGBAUnorm:
                guard texture.frontend.fragmentOutputChannelUse == .redDefined else {
                    throw failure(.color, .colorContractUnproven)
                }
            }
            let uniformInputs = input.uniformInputs(textureSlots: texture.slots)
            let sameSlotMappedCoordinateFacts =
                appliedSameSlotMappedCoordinateFacts(
                    variant: selection.variant,
                    slots: texture.slots
                )
            let uniforms = try resolvedUniforms(
                input,
                uniformInputs: uniformInputs,
                variant: selection.variant,
                slots: texture.slots,
                sameSlotMappedCoordinateFacts:
                    sameSlotMappedCoordinateFacts
            )
            guard let graphRole = effectiveGraphRole(
                input.template.graphRole,
                slots: texture.slots
            ) else {
                throw failure(.invariant, .graphRoleIdentityInvariant)
            }
            guard let program = Program.assembleCompiled(.init(
                preparedShader: selection.variant.preparedShader,
                textureSlots: texture.slots,
                resolvedUniforms: uniforms,
                renderState: input.template.renderState,
                graphRole: graphRole,
                outputStorage: outputStorage,
                runtimeLoopBounds: selection.variant.runtimeLoopBounds,
                sameSlotMappedCoordinateFacts:
                    sameSlotMappedCoordinateFacts
            ), frontend: selection.variant.frontendProgram,
                routeDecision: selection.variant.routeDecision,
                conditionalGeneratedRGBInputContract:
                    selection.variant.conditionalGeneratedRGBInputContract,
                associatedOverOverlaySlot:
                    selection.variant.associatedOverOverlaySlot,
                premultipliedColorInputSlots:
                    selection.variant.premultipliedColorInputSlots
            ) else {
                throw failure(.invariant, .programAssemblyIdentityInvariant)
            }
            return .success(program)
        } catch let error as Failure {
            return .failure(error)
        } catch {
            return .failure(failure(.invariant, .finalizerUnexpectedFailure))
        }
    }

    private static func effectiveGraphRole(
        _ authored: Template.GraphRole,
        slots: [Program.TextureSlot?]
    ) -> Template.GraphRole? {
        var bindings = authored.bindings
        var bindingBySlot: [Int: Template.GraphBindingRole] = [:]
        for binding in bindings {
            guard bindingBySlot.updateValue(
                binding,
                forKey: binding.slot
            ) == nil else { return nil }
        }
        for slot in slots.compactMap({ $0 }) {
            guard let fact = slot.graphInputSourceFact else {
                continue
            }
            guard case let .graph(identity) = slot.reference,
                  identity == fact.inputIdentity,
                  slot.index == fact.slot,
                  slot.diagnosticSelectionProvenance
                    == fact.selectionProvenance,
                  let texture = Template.GraphTextureRole(
                      rawValue: identity.kind.rawValue
                  ) else { return nil }
            let binding = Template.GraphBindingRole(
                slot: slot.index,
                texture: texture
            )
            if let existing = bindingBySlot[slot.index] {
                guard existing == binding else { return nil }
            } else {
                bindingBySlot[slot.index] = binding
                bindings.append(binding)
            }
        }
        return .init(
            effectInput: authored.effectInput,
            effectOutput: authored.effectOutput,
            nodeTarget: authored.nodeTarget,
            bindings: bindings.sorted { $0.slot < $1.slot }
        )
    }

    private static func resolvedUniforms(
        _ input: SceneResolvedMaterialFinalizationInput,
        uniformInputs: SceneAuthoredShaderUniformInputs,
        variant: SceneResolvedMaterialCompiledVariant,
        slots: [Program.TextureSlot?],
        sameSlotMappedCoordinateFacts:
            Set<SceneAuthoredShaderSameSlotMappedCoordinateFact>
    ) throws -> [Program.ResolvedUniform] {
        let fields = variant.frontendProgram.uniformLayout.fields
        guard variant.preparedUniformBindings.count == fields.count,
              zip(fields, variant.preparedUniformBindings).allSatisfy({
                  $0 == $1.field
              }) else {
            throw failure(
                .invariant,
                .programAssemblyIdentityInvariant,
                details: ["prepared-uniform-binding-layout-mismatch"]
            )
        }
        return try variant.preparedUniformBindings.map { binding in
            let field = binding.field
            switch binding.source {
            case let .host(host):
                guard let value = SceneResolvedMaterialUniformEncoder.encodeHost(
                          host,
                          type: field.type,
                          inputs: uniformInputs,
                          slots: slots,
                          sameSlotMappedCoordinateFacts:
                              sameSlotMappedCoordinateFacts
                ) else {
                    throw failure(
                        .uniform,
                        .hostUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                return .init(
                    field: field,
                    source: .host(host),
                    encodedValue: value
                )
            case let .staticValue(encoded):
                guard encoded.count == field.storageByteSize else {
                    throw failure(
                        .invariant,
                        .programAssemblyIdentityInvariant,
                        details: [field.name, "prepared-static-byte-count"]
                    )
                }
                return .init(
                    field: field,
                    source: .staticValue,
                    encodedValue: encoded
                )
            case let .neutralMissingTextureResolution(fact):
                guard let neutral = neutralTextureResolutionUniform(
                    field: field,
                    slots: slots,
                    fact: fact
                ) else {
                    throw failure(
                        .uniform,
                        .staticUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                return neutral
            case let .selfCompositeTextureResolution(
                slot,
                providerLayerID
            ):
                guard let selfComposite = selfCompositeTextureResolutionUniform(
                    field: field,
                    input: input,
                    slot: slot,
                    providerLayerID: providerLayerID
                ) else {
                    throw failure(
                        .uniform,
                        .staticUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                return selfComposite
            case let .dynamic(prepared):
                let dynamic = prepared.declaration
                let contributor = prepared.contributor
                let fallback = prepared.fallback
                let schema = prepared.schema
                guard let resolved = input.dynamicSnapshot[dynamic.target],
                      valid(
                          resolved.source,
                          contributor: contributor,
                          fallback: fallback
                      ) else {
                    throw failure(
                        .uniform,
                        .dynamicUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                let liveEncoded = encodeDynamicUniform(
                    resolved.value,
                    contributor: contributor,
                    declaration: dynamic,
                    schema: schema,
                    field: field
                )
                guard let encoded = directUserPropertyRangedValue(
                    liveEncoded,
                    liveValue: resolved.value,
                    authoredValue: input.dynamicSnapshot.authoredValue(
                        for: dynamic.target
                    ),
                    userPropertyNumericRange:
                        input.dynamicSnapshot.userPropertyNumericRange(
                            for: dynamic.target
                        ),
                    fallback,
                    source: resolved.source,
                    contributor: contributor,
                    declaration: dynamic,
                    schema: schema,
                    field: field
                ) else {
                    throw failure(
                        .uniform,
                        .dynamicUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                if resolved.source == .authored {
                    guard let fallback,
                          encodeDynamicFallback(
                              fallback,
                              contributor: contributor,
                              declaration: dynamic,
                              schema: schema,
                              field: field
                          ) == encoded else {
                        throw failure(
                            .uniform,
                            .dynamicUniformBindingInvalid,
                            details: [field.name]
                        )
                    }
                }
                return .init(
                    field: field,
                    source: .dynamic(
                        declared: contributor,
                        target: dynamic.target,
                        resolvedSource: resolved.source,
                        scriptAttachments: dynamic.scriptAttachments
                    ),
                    encodedValue: encoded
                )
            }
        }
    }

    /// A same-layer composite slot may exist purely as metadata for host
    /// uniforms (e.g. `g_Texture0Resolution`) without any authored sampler.
    /// The layer's graph owns that reference and captures the base composite
    /// at the execution render size, so the resolution uniform encodes that
    /// size directly instead of inventing a texture identity.
    private static func selfCompositeTextureResolutionUniform(
        field: SceneAuthoredShaderUniformLayout.Field,
        input: SceneResolvedMaterialFinalizationInput,
        slot: Int,
        providerLayerID: Int
    ) -> Program.ResolvedUniform? {
        guard providerLayerID == input.layerID,
              let encoded = SceneResolvedMaterialUniformEncoder.encodeComponents(
                  [
                      input.renderSize.width,
                      input.renderSize.height,
                      input.renderSize.width,
                      input.renderSize.height,
                  ],
                  as: field.type
              )
        else { return nil }
        return .init(
            field: field,
            source: .selfCompositeTextureResolution(slot: slot),
            encodedValue: encoded
        )
    }

    private static func neutralTextureResolutionUniform(
        field: SceneAuthoredShaderUniformLayout.Field,
        slots: [Program.TextureSlot?],
        fact: SceneAuthoredShaderNeutralTextureResolutionFact
    ) -> Program.ResolvedUniform? {
        guard slots.indices.contains(fact.resolutionSlot),
              slots[fact.resolutionSlot] == nil,
              slots.indices.contains(fact.coordinateTextureSlot),
              let source = slots[fact.coordinateTextureSlot],
              source.index == fact.coordinateTextureSlot,
              source.resource.publication.requestIdentity == source.registryIdentity,
              source.expectedPurpose
                  == source.resource.publication.candidate.purpose,
              source.resource.publication.isComplete,
              source.resource.publication.candidate.axisAlignedMappedUVScale(
                  expectedPurpose: source.expectedPurpose
              ) == SIMD2<Float>(1, 1),
              let encoded = SceneResolvedMaterialUniformEncoder.encodeComponents(
                  [1, 1, 1, 1],
                  as: field.type
              )
        else { return nil }
        return .init(
            field: field,
            source: .neutralMissingTextureResolution(fact),
            encodedValue: encoded
        )
    }

    private static func preparedSelfCompositeTextureResolution(
        field: SceneAuthoredShaderUniformLayout.Field,
        schema: SceneResolvedMaterialShaderSchema.Uniform,
        template: Template,
        activeTextureSlots: Set<Int>
    ) -> PreparedUniformBinding.Source? {
        guard field.type == .float4,
              field.arrayCount == nil,
              field.authoredName == field.name,
              field.name.hasPrefix("g_Texture"),
              field.name.hasSuffix("Resolution"),
              schema.defaultValue == nil,
              schema.materialKeys == [field.name],
              let slot = Int(field.name.dropFirst("g_Texture".count)
                  .dropLast("Resolution".count)),
              (0 ..< 8).contains(slot),
              !activeTextureSlots.contains(slot),
              template.textureSlots.indices.contains(slot),
              let templateSlot = template.textureSlots[slot],
              let terminal = templateSlot.candidates.last,
              case let .provider(.namedLayerTarget(reference)) =
                  terminal.reference,
              reference.variant == .primary else { return nil }
        return .selfCompositeTextureResolution(
            slot: slot,
            providerLayerID: reference.providerLayerID
        )
    }

    private static func preparedNeutralTextureResolution(
        field: SceneAuthoredShaderUniformLayout.Field,
        schema: SceneResolvedMaterialShaderSchema.Uniform,
        template: Template,
        activeTextureSlots: Set<Int>,
        fact: SceneAuthoredShaderNeutralTextureResolutionFact?
    ) -> SceneAuthoredShaderNeutralTextureResolutionFact? {
        guard let fact,
              field.name == fact.resolutionUniformName,
              field.authoredName == fact.resolutionUniformName,
              field.type == .float4,
              field.arrayCount == nil,
              schema.defaultValue == nil,
              schema.materialKeys == [fact.resolutionUniformName],
              template.textureSlots.indices.contains(fact.resolutionSlot),
              template.textureSlots[fact.resolutionSlot] == nil,
              !activeTextureSlots.contains(fact.resolutionSlot),
              template.textureSlots.indices.contains(
                  fact.coordinateTextureSlot
              ),
              template.textureSlots[fact.coordinateTextureSlot] != nil
        else { return nil }
        return fact
    }

    private static func soleValueContributor(
        _ dynamic: Template.DynamicUniform,
        name: String
    ) throws -> Template.DynamicUniformSource {
        guard dynamic.valueContributors.count == 1,
              let contributor = dynamic.valueContributors.first else {
            throw failure(
                .uniform,
                .uniformContributorPolicyUnproven,
                details: [name]
            )
        }
        return contributor
    }

    private static func validateScriptAttachments(
        _ attachments: [Template.DynamicUniformScriptAttachment],
        contributor: Template.DynamicUniformSource,
        name: String
    ) throws {
        guard attachments.isEmpty else {
            throw failure(.uniform, .uniformScriptAttachmentUnproven, details: [name])
        }
    }

    private static func valid(
        _ source: SceneDynamicSource,
        contributor: Template.DynamicUniformSource,
        fallback: Template.StaticUniformValue?
    ) -> Bool {
        if source == .authored { return fallback != nil }
        return switch (contributor, source) {
        case (.userProperty, .userProperty), (.timeline, .timeline),
             (.sceneScript, .sceneScript): true
        default: false
        }
    }

    private static func value(
        _ value: SceneDynamicValue,
        isWithin range: ClosedRange<Double>?
    ) -> Bool {
        guard let range else { return true }
        let components: [Double]
        switch value {
        case let .scalar(x): components = [x]
        case let .vector2(x, y): components = [x, y]
        case let .vector3(x, y, z): components = [x, y, z]
        case let .vector4(x, y, z, w): components = [x, y, z, w]
        case .bool, .string: return false
        }
        return components.allSatisfy { $0.isFinite && range.contains($0) }
    }

    private static func directUserPropertyRangedValue(
        _ liveEncoded: Data?,
        liveValue: SceneDynamicValue,
        authoredValue: SceneDynamicValue?,
        userPropertyNumericRange: ClosedRange<Double>?,
        _ fallback: Template.StaticUniformValue?,
        source: SceneDynamicSource,
        contributor: Template.DynamicUniformSource,
        declaration: Template.DynamicUniform,
        schema: SceneResolvedMaterialShaderSchema.Uniform,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Data? {
        guard let liveEncoded else { return nil }
        guard source == .userProperty,
              case .userProperty = contributor,
              [.float, .float2, .float3].contains(field.type),
              field.arrayCount == nil,
              declaration.scriptAttachments.isEmpty,
              let fallback,
              fallback.valueKind.localizedLowercase == "binding",
              SceneResolvedMaterialDirectUserBindingContract.matches(
                  dynamic: declaration,
                  fallback: fallback
              ),
              let range = schema.authoredRange else {
            return liveEncoded
        }
        if value(liveValue, isWithin: range) { return liveEncoded }
        if field.type == .float,
           let userPropertyNumericRange,
           value(liveValue, isWithin: userPropertyNumericRange) {
            // A direct user property owns its authored UI domain. Shader
            // range annotations describe the unbound material editor value
            // and may intentionally exclude a UI sentinel such as zero.
            return liveEncoded
        }
        guard let authoredValue,
              let authoredEncoded = encodeDynamicUniform(
            authoredValue,
            contributor: contributor,
            declaration: declaration,
            schema: schema,
            field: field
        ) else { return nil }
        if value(authoredValue, isWithin: range) { return authoredEncoded }

        // A direct property wrapper may author an equal-lane float2 sentinel
        // outside shader editor metadata (for example zero to disable blur).
        // Preserve only an exact fallback projection; arbitrary live values
        // and every other ABI/source shape stay range-gated.
        guard scalarSplatEligible(
                  contributor: contributor, declaration: declaration,
                  schema: schema, field: field
              ), let fallbackEncoded = encodeDynamicFallback(
                  fallback, contributor: contributor,
                  declaration: declaration, schema: schema, field: field
              ), authoredEncoded == fallbackEncoded else { return nil }
        return authoredEncoded
    }

    /// Slider properties are scalar producers. A float2 shader consumer with
    /// an equal-lane typed default may explicitly bind that scalar through the
    /// direct user/value wrapper. Keep the producer scalar and perform only
    /// that isotropic consumer projection; all other lane/type/source shapes
    /// retain the existing exact encoder failure.
    private static func encodeDynamicUniform(
        _ value: SceneDynamicValue,
        contributor: Template.DynamicUniformSource,
        declaration: Template.DynamicUniform,
        schema: SceneResolvedMaterialShaderSchema.Uniform,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Data? {
        if let exact = SceneResolvedMaterialUniformEncoder.encode(
            value,
            as: field.type
        ) {
            return exact
        }
        guard case let .scalar(component) = value,
              component.isFinite,
              scalarSplatEligible(
                  contributor: contributor,
                  declaration: declaration,
                  schema: schema,
                  field: field
              ) else {
            return nil
        }
        return SceneResolvedMaterialUniformEncoder.encodeComponents(
            [component, component],
            as: field.type
        )
    }

    private static func encodeDynamicFallback(
        _ fallback: Template.StaticUniformValue,
        contributor: Template.DynamicUniformSource,
        declaration: Template.DynamicUniform,
        schema: SceneResolvedMaterialShaderSchema.Uniform,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Data? {
        if let exact = SceneResolvedMaterialUniformEncoder.encode(
            fallback,
            as: field.type
        ) {
            return exact
        }
        let components = fallback.componentBitPatterns.map {
            Double(bitPattern: $0)
        }
        guard components.count == 1,
              let component = components.first,
              component.isFinite,
              scalarSplatEligible(
                  contributor: contributor,
                  declaration: declaration,
                  schema: schema,
                  field: field
              ) else {
            return nil
        }
        return SceneResolvedMaterialUniformEncoder.encodeComponents(
            [component, component],
            as: field.type
        )
    }

    private static func scalarSplatEligible(
        contributor: Template.DynamicUniformSource,
        declaration: Template.DynamicUniform,
        schema: SceneResolvedMaterialShaderSchema.Uniform,
        field: SceneAuthoredShaderUniformLayout.Field
    ) -> Bool {
        guard case .userProperty = contributor,
              declaration.scriptAttachments.isEmpty,
              let fallback = declaration.authoredFallback,
              fallback.valueKind.localizedLowercase == "binding",
              SceneResolvedMaterialDirectUserBindingContract.matches(
                  dynamic: declaration,
                  fallback: fallback
              ),
              SceneResolvedMaterialUniformProjection.isIsotropicFloat2Consumer(
                  schema: schema,
                  field: field
              ) else {
            return false
        }
        let fallbackComponents = fallback.componentBitPatterns.map {
            Double(bitPattern: $0)
        }
        let fallbackIsScalarOrEqualPair = fallbackComponents.count == 1
            || (fallbackComponents.count == 2
                && fallbackComponents[0] == fallbackComponents[1])
        return fallbackIsScalarOrEqualPair
            && fallbackComponents.allSatisfy(\.isFinite)
    }

    static func failure(
        _ phase: Failure.Phase, _ code: Failure.Code,
        details: [String] = []
    ) -> Failure {
        .init(phase: phase, code: code, details: details)
    }
}
