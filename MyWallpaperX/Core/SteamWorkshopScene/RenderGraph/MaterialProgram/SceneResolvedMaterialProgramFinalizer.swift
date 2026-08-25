import Foundation
import simd

nonisolated struct SceneResolvedMaterialFrameSnapshot {
    typealias Failure = SceneResolvedMaterialFailure

    fileprivate let textureSnapshot: SceneFrameTextureRegistrySnapshot
    fileprivate let dynamicSnapshot: SceneDynamicSnapshot
    fileprivate let frameInputs: SceneAuthoredShaderFrameInputs

    var frameIndex: UInt64 { frameInputs.frameIndex }

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
        renderSize: CGSize,
        modelViewProjection: simd_float4x4,
        layerModelMatrix: simd_float4x4,
        effectTextureProjectionMatrixInverse: simd_float4x4,
        implicitFramebufferIdentity: SceneAuthoredEffectRenderPlan.TextureIdentity? = nil
    ) -> SceneResolvedMaterialFinalizationInput {
        .init(
            template: template,
            frameSnapshot: self,
            renderSize: renderSize,
            modelViewProjection: modelViewProjection,
            layerModelMatrix: layerModelMatrix,
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

}

nonisolated struct SceneResolvedMaterialFinalizationInput {
    let template: SceneResolvedMaterialTemplate
    fileprivate let frameSnapshot: SceneResolvedMaterialFrameSnapshot
    let renderSize: CGSize
    let modelViewProjection: simd_float4x4
    let layerModelMatrix: simd_float4x4
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
                guard SceneResolvedMaterialProgramDerivation
                    .hasResolvedColorSampleContract(
                        colorSlots:
                            selection.variant.preservedAlphaRGBColorSlots,
                        textureSlots: texture.slots
                    ) else {
                    throw failure(
                        .color,
                        .colorContractUnproven,
                        details: [
                            "preserved-alpha-rgb-color-slots",
                            selection.variant.preservedAlphaRGBColorSlots
                                .sorted().map(String.init)
                                .joined(separator: ","),
                        ]
                    )
                }
                guard SceneResolvedMaterialProgramDerivation.hasResolvedColorContract(
                    transfer: texture.frontend.colorTransfer,
                    textureSlots: texture.slots
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
            let uniforms = try resolvedUniforms(
                input,
                uniformInputs: uniformInputs,
                variant: selection.variant,
                slots: texture.slots
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
                runtimeLoopBounds: selection.variant.runtimeLoopBounds
            ), frontend: selection.variant.frontendProgram,
                routeDecision: selection.variant.routeDecision) else {
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

    /// Redacted typed atoms for the uncommon frame-time rejection path. The
    /// graph executor adds node/material identity to the enclosing diagnostic.
    private static func colorContractFailureDetails(
        transfer: SceneShaderColorTransfer,
        slots: [Program.TextureSlot?]
    ) -> [String] {
        ["transfer-\(colorTransferToken(transfer))"]
            + slots.compactMap { slot in
                guard let slot else { return nil }
                let publication = slot.resource.publication
                return "slot-\(slot.index)-ref-\(referenceToken(slot.reference))-"
                    + "content-\(contentToken(publication.candidate.content))-"
                    + "purpose-\(String(describing: slot.expectedPurpose))-"
                    + "request-\(requestToken(publication.requestIdentity))-"
                    + "resource-\(resourceToken(publication.candidate.identity))-"
                    + "cg-\(publication.contentGeneration)-"
                    + "rg-\(slot.resource.resourceGeneration)"
            }
    }

    private static func colorTransferToken(_ transfer: SceneShaderColorTransfer) -> String {
        switch transfer {
        case let .passthrough(slot): "passthrough-\(slot)"
        case let .interpolatedColor(slots):
            "interpolated-\(slots.map(String.init).joined(separator: "_"))"
        case let .straightAlphaPreserving(slot): "straight-preserving-\(slot)"
        case let .straightAlpha(slot): "straight-\(slot)"
        case let .straightAlphaUNorm(slot): "straight-unorm-\(slot)"
        case let .independentAlphaSignal(slot): "alpha-signal-\(slot)"
        case let .independentAlphaSignalPreserving(slot):
            "alpha-signal-preserving-\(slot)"
        case let .independentAlphaSignalCompositing(signal, color):
            "alpha-signal-composite-\(signal)-\(color)"
        case .premultipliedAlpha: "premultiplied"
        case .opaque: "opaque"
        case .unresolved: "unresolved"
        }
    }

    private static func referenceToken(_ reference: Template.TextureReference) -> String {
        switch reference {
        case .asset: "asset"
        case .userProperty: "user-property"
        case .provider(.system): "provider-system"
        case .provider(.namedLayerTarget): "provider-named-layer"
        case .provider(.sceneBackground): "provider-scene-background"
        case let .graph(identity): "graph-\(identity.kind.rawValue)"
        }
    }

    private static func contentToken(_ content: SceneTextureContent) -> String {
        switch content {
        case .color(.unresolved): "color-unresolved"
        case let .color(.resolved(value)): "color-\(String(describing: value))"
        case .scalarRedUnorm: "scalar-r-unorm"
        case .redGreenUnorm: "rg-unorm"
        case .scalarRedFloat16: "scalar-r-f16"
        case .redGreenFloat16: "rg-f16"
        case .data: "data"
        }
    }

    private static func requestToken(_ identity: SceneFrameTextureIdentity) -> String {
        switch identity {
        case .layerSource: "layer-source"
        case .namedLayerTarget: "named-layer-target"
        case .sceneBackground: "scene-background"
        case let .graph(identity): "graph-\(identity.kind.rawValue)"
        case .asset: "asset"
        case .userProperty: "user-property"
        case .materialUserProperty: "material-user-property"
        case .system: "system"
        }
    }

    private static func resourceToken(_ identity: SceneTextureResourceIdentity) -> String {
        switch identity {
        case .file: "file"
        case .builtIn: "built-in"
        case .provider(.dynamicText): "provider-dynamic-text"
        case .provider(.graph): "provider-graph"
        case .provider(.mediaThumbnailCurrent): "provider-media-thumbnail"
        case .provider(.namedLayerTarget): "provider-named-layer"
        case .provider(.sceneBackground): "provider-scene-background"
        case .provider(.video): "provider-video"
        }
    }

    private static func resolvedUniforms(
        _ input: SceneResolvedMaterialFinalizationInput,
        uniformInputs: SceneAuthoredShaderUniformInputs,
        variant: SceneResolvedMaterialCompiledVariant,
        slots: [Program.TextureSlot?]
    ) throws -> [Program.ResolvedUniform] {
        try variant.frontendProgram.uniformLayout.fields.map { field in
            let schema = variant.activeUniforms[field.name]
            let keys = Set(schema?.materialKeys ?? [field.name])
            let declarations = input.template.uniformDeclarations.filter {
                keys.contains($0.name)
            }
            if let host = SceneResolvedMaterialUniformEncoder.hostUniform(
                field,
                slots: slots
            ) {
                guard declarations.isEmpty else {
                    throw failure(
                        .uniform,
                        .hostUniformDeclarationConflict,
                        details: [field.name]
                    )
                }
                guard let value = SceneResolvedMaterialUniformEncoder.encodeHost(
                          host,
                          type: field.type,
                          inputs: uniformInputs,
                          slots: slots
                ) else {
                    throw failure(
                        .uniform,
                        .hostUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                return .init(field: field, source: .host(host), encodedValue: value)
            }
            guard let schema else {
                throw failure(
                    .uniform,
                    .activeUniformSchemaMissing,
                    details: [field.name]
                )
            }
            if declarations.isEmpty {
                if let neutral = neutralTextureResolutionUniform(
                    field: field,
                    schema: schema,
                    input: input,
                    variant: variant,
                    slots: slots
                ) {
                    return neutral
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
                return .init(field: field, source: .staticValue, encodedValue: encoded)
            }
            guard declarations.count == 1, let declaration = declarations.first else {
                throw failure(
                    .uniform,
                    .uniformDeclarationConflict,
                    details: [field.name]
                )
            }
            switch declaration.value {
            case let .staticExact(value):
                guard let encoded = SceneResolvedMaterialUniformEncoder.encode(
                    value,
                    as: field.type
                ) else {
                    throw failure(
                        .uniform,
                        .staticUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                return .init(field: field, source: .staticValue, encodedValue: encoded)
            case let .dynamic(dynamic):
                let contributor = try soleValueContributor(dynamic, name: field.name)
                try validateScriptAttachments(
                    dynamic.scriptAttachments,
                    contributor: contributor,
                    name: field.name
                )
                let fallback = dynamic.authoredFallback ?? schema.defaultValue
                guard let resolved = input.dynamicSnapshot[dynamic.target],
                      valid(
                          resolved.source,
                          contributor: contributor,
                          fallback: fallback
                      ),
                      let encoded = encodeDynamicUniform(
                          resolved.value,
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

    private static func neutralTextureResolutionUniform(
        field: SceneAuthoredShaderUniformLayout.Field,
        schema: SceneResolvedMaterialShaderSchema.Uniform,
        input: SceneResolvedMaterialFinalizationInput,
        variant: SceneResolvedMaterialCompiledVariant,
        slots: [Program.TextureSlot?]
    ) -> Program.ResolvedUniform? {
        guard let fact = variant.neutralTextureResolution,
              field.name == fact.resolutionUniformName,
              field.authoredName == fact.resolutionUniformName,
              field.type == .float4,
              field.arrayCount == nil,
              schema.defaultValue == nil,
              schema.materialKeys == [fact.resolutionUniformName],
              input.template.textureSlots.indices.contains(fact.resolutionSlot),
              input.template.textureSlots[fact.resolutionSlot] == nil,
              slots.indices.contains(fact.resolutionSlot),
              slots[fact.resolutionSlot] == nil,
              variant.activeSamplers[fact.resolutionSlot] == nil,
              !variant.frontendProgram.textureBindings.contains(where: {
                  $0.slot == fact.resolutionSlot
              }),
              input.template.textureSlots.indices.contains(
                  fact.coordinateTextureSlot
              ),
              input.template.textureSlots[fact.coordinateTextureSlot] != nil,
              slots.indices.contains(fact.coordinateTextureSlot),
              let source = slots[fact.coordinateTextureSlot],
              source.index == fact.coordinateTextureSlot,
              variant.activeSamplers[fact.coordinateTextureSlot] != nil,
              variant.frontendProgram.textureBindings.filter({
                  $0.slot == fact.coordinateTextureSlot
              }).count == 1,
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
        guard Set(attachments).count == attachments.count,
              attachments.allSatisfy({ attachment in
                  attachment == .mediaThumbnailAnimationRestart
                      && contributor == .timeline
              }) else {
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
              field.type == .float2,
              field.arrayCount == nil,
              declaration.scriptAttachments.isEmpty,
              declaration.authoredBindingKeys == ["user", "value"],
              let fallback = declaration.authoredFallback,
              fallback.valueKind.localizedLowercase == "binding",
              fallback.authoredBindingKeys == ["user", "value"],
              let consumerDefault = schema.defaultValue else {
            return false
        }
        let fallbackComponents = fallback.componentBitPatterns.map {
            Double(bitPattern: $0)
        }
        let fallbackIsScalarOrEqualPair = fallbackComponents.count == 1
            || (fallbackComponents.count == 2
                && fallbackComponents[0] == fallbackComponents[1])
        let defaultComponents = consumerDefault.componentBitPatterns.map {
            Double(bitPattern: $0)
        }
        return fallbackIsScalarOrEqualPair
            && fallbackComponents.allSatisfy(\.isFinite)
            && defaultComponents.count == 2
            && defaultComponents.allSatisfy(\.isFinite)
            && defaultComponents[0] == defaultComponents[1]
    }

    private static func failure(
        _ phase: Failure.Phase, _ code: Failure.Code,
        details: [String] = []
    ) -> Failure {
        .init(phase: phase, code: code, details: details)
    }
}
