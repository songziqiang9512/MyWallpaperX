import Foundation
import simd

nonisolated struct SceneResolvedMaterialFrameSnapshot {
    typealias Failure = SceneResolvedMaterialFailure

    fileprivate let textureSnapshot: SceneFrameTextureRegistrySnapshot
    fileprivate let dynamicSnapshot: SceneDynamicSnapshot
    fileprivate let frameInputs: SceneAuthoredShaderFrameInputs

    var frameIndex: UInt64 { frameInputs.frameIndex }

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
        _ input: SceneResolvedMaterialFinalizationInput
    ) -> Result<Program, Failure> {
        let cache: SceneResolvedMaterialVariantCache
        switch SceneResolvedMaterialVariantCache.launchValidated(
            template: input.template,
            maximumVariantCount: 8
        ) {
        case let .success(value): cache = value
        case let .failure(error): return .failure(error)
        }
        return finalize(input, variantCache: cache)
    }

    static func finalize(
        _ input: SceneResolvedMaterialFinalizationInput,
        variantCache: SceneResolvedMaterialVariantCache
    ) -> Result<Program, Failure> {
        do {
            guard input.template.renderState.matchesFullscreenOverwrite(
                alphaWriting: .unspecified
            ) else {
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
            guard SceneResolvedMaterialProgramDerivation.hasResolvedColorContract(
                transfer: texture.frontend.colorTransfer,
                textureSlots: texture.slots
            ) else {
                throw failure(.color, .colorContractUnproven)
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
                throw failure(.invariant, .identityInvariant)
            }
            guard let program = Program.assembleCompiled(.init(
                preparedShader: selection.variant.preparedShader,
                textureSlots: texture.slots,
                resolvedUniforms: uniforms,
                renderState: input.template.renderState,
                graphRole: graphRole
            ), frontend: selection.variant.frontendProgram) else {
                throw failure(.invariant, .identityInvariant)
            }
            return .success(program)
        } catch let error as Failure {
            return .failure(error)
        } catch {
            return .failure(failure(.invariant, .identityInvariant))
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
            guard slot.diagnosticSelectionProvenance == .implicitFramebuffer
                    || slot.diagnosticSelectionProvenance == .materialGraphInputAlias else {
                continue
            }
            guard case let .graph(identity) = slot.reference,
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
                      let encoded = SceneResolvedMaterialUniformEncoder.encode(
                          resolved.value,
                          as: field.type
                      ) else {
                    throw failure(
                        .uniform,
                        .dynamicUniformBindingInvalid,
                        details: [field.name]
                    )
                }
                if resolved.source == .authored {
                    guard let fallback,
                          SceneResolvedMaterialUniformEncoder.encode(
                              fallback,
                              as: field.type
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

    private static func failure(
        _ phase: Failure.Phase, _ code: Failure.Code,
        details: [String] = []
    ) -> Failure {
        .init(phase: phase, code: code, details: details)
    }
}
