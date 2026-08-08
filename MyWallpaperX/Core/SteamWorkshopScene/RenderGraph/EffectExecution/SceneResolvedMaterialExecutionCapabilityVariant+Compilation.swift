import Foundation

/// Immutable shader/frontend/schema facts for one texture-readiness variant.
/// Concrete resources and uniform values are bound by each frame snapshot.
nonisolated struct SceneResolvedMaterialCompiledVariant {
    typealias Sampler = SceneResolvedMaterialShaderSchema.Sampler
    typealias Uniform = SceneResolvedMaterialShaderSchema.Uniform

    let readinessMask: UInt8
    let preparedShader: SceneShaderPreparedProgram
    let frontendProgram: SceneAuthoredShaderProgram
    let activeSamplers: [Int: Sampler]
    let activeUniforms: [String: Uniform]

    fileprivate init(
        readinessMask: UInt8,
        preparedShader: SceneShaderPreparedProgram,
        frontendProgram: SceneAuthoredShaderProgram,
        activeSamplers: [Int: Sampler],
        activeUniforms: [String: Uniform]
    ) {
        self.readinessMask = readinessMask
        self.preparedShader = preparedShader
        self.frontendProgram = frontendProgram
        self.activeSamplers = activeSamplers
        self.activeUniforms = activeUniforms
    }
}

extension SceneResolvedMaterialVariantCache {
    static func compile(
        template: Template,
        readinessMask: UInt8,
        onFrontendCompilation: () -> Void
    ) throws -> Variant {
        let readiness = Dictionary(uniqueKeysWithValues: (0 ..< 8).map {
            ($0, readinessMask & (1 << UInt8($0)) != 0)
        })
        let prepared: SceneShaderPreparedProgram
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: template.shaderContract,
            combos: template.comboValues,
            textureReadiness: readiness
        ) {
        case let .accepted(value): prepared = value
        case let .rejected(rejection):
            throw failure(
                .shaderPreparationFailed,
                phase: .preparation,
                details: [rejection.phase.rawValue, rejection.code.rawValue]
                    + rejection.details
            )
        case .notApplicable:
            throw failure(.identityInvariant, phase: .invariant)
        }
        onFrontendCompilation()
        let frontendOutput = SceneAuthoredShaderFrontend.compile(
            vertexSource: prepared.vertex.source,
            fragmentSource: prepared.fragment.source
        )
        guard frontendOutput.diagnostics.isEmpty,
              let frontend = frontendOutput.program,
              SceneResolvedMaterialProgramDerivation.validPreparedStages(prepared),
              SceneResolvedMaterialProgramDerivation.uniqueAndValid(
                  frontend.uniformLayout
              ) else {
            throw failure(
                .shaderFrontendFailed,
                phase: .frontend,
                details: SceneResolvedMaterialExecutionCapabilityDiagnostics
                    .frontendFailure(template: template, output: frontendOutput)
            )
        }
        let samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
        do {
            samplers = try SceneResolvedMaterialShaderSchema.activeSamplers(prepared)
        } catch {
            throw failure(.activeSamplerSchemaInvalid)
        }
        let bindings = frontend.textureBindings
        guard !hasInternalDefault(samplers),
              bindings.map(\.slot) == bindings.map(\.slot).sorted(),
              Set(bindings.map(\.slot)).count == bindings.count,
              bindings.allSatisfy({ binding in
                  (0 ..< 8).contains(binding.slot)
                      && samplers[binding.slot]?.name == binding.name
              }), !declaresActivePass(prepared) else {
            throw failure(.activeSamplerSchemaInvalid)
        }
        let activeSlots = Set(bindings.map(\.slot))
        let nonHost = frontend.uniformLayout.fields.filter {
            SceneResolvedMaterialUniformEncoder.hostUniform(
                $0,
                activeTextureSlots: activeSlots
            ) == nil
        }
        let uniforms: [String: SceneResolvedMaterialShaderSchema.Uniform]
        do {
            uniforms = try SceneResolvedMaterialShaderSchema.activeUniforms(
                nonHost,
                prepared: prepared
            )
        } catch {
            throw failure(.uniformBindingInvalid, phase: .uniform)
        }
        return .init(
            readinessMask: readinessMask,
            preparedShader: prepared,
            frontendProgram: frontend,
            activeSamplers: samplers,
            activeUniforms: uniforms
        )
    }

    private static func hasInternalDefault(
        _ samplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) -> Bool {
        samplers.values.contains {
            if case .internalTarget? = $0.defaultTexture { return true }
            return false
        }
    }

    private static func declaresActivePass(
        _ prepared: SceneShaderPreparedProgram
    ) -> Bool {
        prepared.all.contains { source in
            source.activeAnnotations.contains { annotation in
                annotation.annotation.marker?.caseInsensitiveCompare("[PASS]")
                    == .orderedSame
            }
        }
    }
}
