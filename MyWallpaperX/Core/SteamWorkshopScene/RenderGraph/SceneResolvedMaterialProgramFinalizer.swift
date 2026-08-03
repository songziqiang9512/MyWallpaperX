import Foundation
import simd

nonisolated struct SceneResolvedMaterialFrameSnapshot {
    typealias Failure = SceneResolvedMaterialFailure

    fileprivate let textureSnapshot: SceneFrameTextureRegistrySnapshot
    fileprivate let dynamicSnapshot: SceneDynamicSnapshot
    fileprivate let frameInputs: SceneAuthoredShaderFrameInputs

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
        modelViewProjection: simd_float4x4
    ) -> SceneResolvedMaterialFinalizationInput {
        .init(
            template: template,
            frameSnapshot: self,
            renderSize: renderSize,
            modelViewProjection: modelViewProjection
        )
    }
}

nonisolated struct SceneResolvedMaterialFinalizationInput {
    let template: SceneResolvedMaterialTemplate
    fileprivate let frameSnapshot: SceneResolvedMaterialFrameSnapshot
    let renderSize: CGSize
    let modelViewProjection: simd_float4x4

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
            sceneTime: frameSnapshot.frameInputs.sceneTime,
            dayTime: frameSnapshot.frameInputs.dayTime,
            frameTime: frameSnapshot.frameInputs.frameTime,
            pointerCurrentNDC: frameSnapshot.frameInputs.pointerCurrentNDC,
            pointerPreviousNDC: frameSnapshot.frameInputs.pointerPreviousNDC,
            texturePhysicalSizes: Dictionary(
                uniqueKeysWithValues: textureSlots.compactMap { slot in
                    slot.map {
                        ($0.index, $0.resource.publication.candidate.physicalSize)
                    }
                }
            )
        )
    }

    fileprivate init(
        template: SceneResolvedMaterialTemplate,
        frameSnapshot: SceneResolvedMaterialFrameSnapshot,
        renderSize: CGSize,
        modelViewProjection: simd_float4x4
    ) {
        self.template = template
        self.frameSnapshot = frameSnapshot
        self.renderSize = renderSize
        self.modelViewProjection = modelViewProjection
    }
}

nonisolated enum SceneResolvedMaterialProgramFinalizer {
    typealias Failure = SceneResolvedMaterialFailure
    typealias Program = SceneResolvedMaterialProgram
    typealias Template = SceneResolvedMaterialTemplate

    static func finalize(
        _ input: SceneResolvedMaterialFinalizationInput
    ) -> Result<Program, Failure> {
        do {
            guard input.template.renderState.matchesFullscreenOverwrite(
                alphaWriting: .unspecified
            ) else {
                throw failure(.state, .renderStateInvalid)
            }
            let texture = try SceneResolvedMaterialTextureResolver.resolve(input)
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
                prepared: texture.prepared,
                frontend: texture.frontend,
                slots: texture.slots
            )
            guard let program = Program.assemble(.init(
                preparedShader: texture.prepared,
                textureSlots: texture.slots,
                resolvedUniforms: uniforms,
                renderState: input.template.renderState,
                graphRole: input.template.graphRole
            )) else {
                throw failure(.invariant, .identityInvariant)
            }
            return .success(program)
        } catch let error as Failure {
            return .failure(error)
        } catch {
            return .failure(failure(.invariant, .identityInvariant))
        }
    }

    private static func resolvedUniforms(
        _ input: SceneResolvedMaterialFinalizationInput,
        uniformInputs: SceneAuthoredShaderUniformInputs,
        prepared: SceneShaderPreparedProgram,
        frontend: SceneAuthoredShaderProgram,
        slots: [Program.TextureSlot?]
    ) throws -> [Program.ResolvedUniform] {
        let nonHostFields = frontend.uniformLayout.fields.filter {
            SceneResolvedMaterialUniformEncoder.hostUniform($0, slots: slots) == nil
        }
        let schemas: [String: SceneResolvedMaterialShaderSchema.Uniform]
        do {
            schemas = try SceneResolvedMaterialShaderSchema.activeUniforms(
                nonHostFields,
                prepared: prepared
            )
        } catch {
            throw failure(.uniform, .uniformBindingInvalid)
        }
        return try frontend.uniformLayout.fields.map { field in
            let schema = schemas[field.name]
            let keys = Set(schema?.materialKeys ?? [field.name])
            let declarations = input.template.uniformDeclarations.filter {
                keys.contains($0.name)
            }
            if let host = SceneResolvedMaterialUniformEncoder.hostUniform(
                field,
                slots: slots
            ) {
                guard declarations.isEmpty,
                      let value = SceneResolvedMaterialUniformEncoder.encodeHost(
                          host,
                          type: field.type,
                          inputs: uniformInputs,
                          slots: slots
                      ) else {
                    throw failure(.uniform, .uniformBindingInvalid, details: [field.name])
                }
                return .init(field: field, source: .host(host), encodedValue: value)
            }
            guard let schema else {
                throw failure(.uniform, .uniformBindingInvalid, details: [field.name])
            }
            if declarations.isEmpty {
                guard let fallback = schema.defaultValue,
                      let encoded = SceneResolvedMaterialUniformEncoder.encode(
                          fallback,
                          as: field.type
                      ) else {
                    throw failure(.uniform, .uniformBindingInvalid, details: [field.name])
                }
                return .init(field: field, source: .staticValue, encodedValue: encoded)
            }
            guard declarations.count == 1, let declaration = declarations.first else {
                throw failure(.uniform, .uniformBindingInvalid, details: [field.name])
            }
            switch declaration.value {
            case let .staticExact(value):
                guard let encoded = SceneResolvedMaterialUniformEncoder.encode(
                    value,
                    as: field.type
                ) else {
                    throw failure(.uniform, .uniformBindingInvalid, details: [field.name])
                }
                return .init(field: field, source: .staticValue, encodedValue: encoded)
            case let .dynamic(dynamic):
                let contributor = try soleValueContributor(dynamic, name: field.name)
                try validateControlAttachments(
                    dynamic.controlAttachments,
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
                    throw failure(.uniform, .uniformBindingInvalid, details: [field.name])
                }
                if resolved.source == .authored {
                    guard let fallback,
                          SceneResolvedMaterialUniformEncoder.encode(
                              fallback,
                              as: field.type
                          ) == encoded else {
                        throw failure(.uniform, .uniformBindingInvalid, details: [field.name])
                    }
                }
                return .init(
                    field: field,
                    source: .dynamic(
                        declared: contributor,
                        target: dynamic.target,
                        resolvedSource: resolved.source,
                        controlAttachments: dynamic.controlAttachments
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

    private static func validateControlAttachments(
        _ controls: [Template.DynamicUniformControlAttachment],
        contributor: Template.DynamicUniformSource,
        name: String
    ) throws {
        guard Set(controls).count == controls.count,
              controls.allSatisfy({ control in
                  control == .mediaThumbnailAnimationRestart
                      && contributor == .timeline
              }) else {
            throw failure(.uniform, .uniformControlUnproven, details: [name])
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
        _ phase: Failure.Phase,
        _ code: Failure.Code,
        details: [String] = []
    ) -> Failure {
        .init(phase: phase, code: code, details: details)
    }
}
