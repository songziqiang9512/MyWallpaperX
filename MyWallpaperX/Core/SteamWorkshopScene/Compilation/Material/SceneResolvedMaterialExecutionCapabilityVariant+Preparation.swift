import Foundation
import QuartzCore

private func normalBlendIdentifiers(
    _ combos: [String: Int]
) -> Set<String> {
    Set(combos.compactMap { name, value in value == 0 ? name : nil })
}

nonisolated extension SceneResolvedMaterialVariantCache {
    static func prepareVariantSources(
        template: Template,
        variantKey: SceneResolvedMaterialVariantKey,
        readinessMask: UInt8,
        readiness: [Int: Bool],
        implicitFramebufferIdentity: Graph.TextureIdentity?,
        outputIsRGBA8Unorm: Bool
    ) throws -> (
        prepared: SceneShaderPreparedProgram,
        variantAnalysisKey: String?,
        cachedAnalysis: SceneResolvedMaterialVariantAnalysisCache.Record?,
        compilerSources: SceneAuthoredShaderBackendCanonicalizer.Pair,
        compatibilityTargetAdmissionPending: Bool,
        analysisStart: Double,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds,
        resolvedIntegerCombos: [String: Int],
        activeSamplerNames: Set<String>,
        sourceActiveSamplers: [Int: SceneResolvedMaterialShaderSchema.Sampler]
    ) {
        let profileStart = CACurrentMediaTime()
        let prepared: SceneShaderPreparedProgram
        switch SceneAuthoredShaderPreparation.prepareShaderStages(
            contract: template.shaderContract,
            compatibilityTarget: template.compatibilityTarget,
            combos: template.comboValues,
            inactiveComboProviders: Set(template.inheritedInactiveCombos),
            textureReadiness: readiness,
            textureFormats: variantKey.resolvedTextureFormats
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
        SceneResolvedMaterialVariantCompileProfile.add(
            prepare: (CACurrentMediaTime() - profileStart) * 1000
        )
        let variantAnalysisKey = SceneResolvedMaterialVariantAnalysisCache
            .keyDigest(
                contractIdentity: template.shaderContract.identity,
                contractCanonicalSHA256: template.shaderContract
                    .canonicalSHA256,
                textureSlotShapes: template.textureSlots.map { slot in
                    slot.map {
                        "\($0.index):"
                            + $0.candidates.map { candidate in
                                switch candidate.reference {
                                case .asset: "a"
                                case .userProperty: "u"
                                case .provider: "p"
                                case .graph: "g"
                                }
                            }.joined(separator: ",")
                    }
                },
                combos: template.comboValues,
                inheritedInactiveCombos: Set(
                    template.inheritedInactiveCombos
                ),
                uniformDeclarations: template.uniformDeclarations,
                compatibilityTarget: template.compatibilityTarget,
                implicitFramebufferIdentity: implicitFramebufferIdentity,
                readinessMask: readinessMask,
                resolvedTextureFormats: variantKey.resolvedTextureFormats,
                outputIsRGBA8Unorm: outputIsRGBA8Unorm
            )
        let cachedAnalysis = variantAnalysisKey.flatMap {
            SceneResolvedMaterialVariantAnalysisCache.load(keySHA256: $0)
        }
        let canonicalizeStart = CACurrentMediaTime()
        let compatibilityTargetAdmissionPending = prepared.all.allSatisfy {
            $0.compatibilityTarget == .windowsDX11ShaderModel4
        } && prepared.all.contains {
            !$0.compatibilityMacroDependencies.isEmpty
        }
        let compilerSources: SceneAuthoredShaderBackendCanonicalizer.Pair
        if let cachedAnalysis, !cachedAnalysis.canonicalVertex.isEmpty,
           !cachedAnalysis.canonicalFragment.isEmpty {
            compilerSources = SceneAuthoredShaderBackendCanonicalizer.Pair(
                vertex: cachedAnalysis.canonicalVertex,
                fragment: cachedAnalysis.canonicalFragment
            )
        } else {
            compilerSources = SceneAuthoredShaderBackendCanonicalizer
                .canonicalize(
                    vertex: prepared.vertex.source,
                    fragment: prepared.fragment.source
                )
        }
        SceneResolvedMaterialVariantCompileProfile.add(
            canonicalize: (CACurrentMediaTime() - canonicalizeStart) * 1000
        )
        let analysisStart = CACurrentMediaTime()
        let runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
        if let cachedAnalysis {
            runtimeLoopBounds = cachedAnalysis.runtimeLoopBounds
        } else {
            runtimeLoopBounds = SceneResolvedMaterialRuntimeLoopBoundResolver
                .resolve(
                    template: template,
                    prepared: prepared
                )
        }
        let resolvedIntegerCombos: [String: Int]
        let activeSamplerNames: Set<String>
        let sourceActiveSamplers: [
            Int: SceneResolvedMaterialShaderSchema.Sampler
        ]
        if let cachedAnalysis {
            resolvedIntegerCombos = cachedAnalysis.resolvedIntegerCombos
            activeSamplerNames = cachedAnalysis.activeSamplerNames
            sourceActiveSamplers = cachedAnalysis.sourceActiveSamplers
        } else {
            activeSamplerNames = SceneAuthoredShaderDeadBindingAnalyzer
                .activeSamplerNamesForSchema(
                    vertexSource: compilerSources.vertex,
                    fragmentSource: compilerSources.fragment,
                    runtimeLoopBounds: runtimeLoopBounds
                ) ?? []
            guard let resolved =
                    SceneAuthoredShaderPreparation.resolvedIntegerCombos(
                        contract: template.shaderContract,
                        prepared: prepared,
                        combos: template.comboValues,
                        inactiveComboProviders: Set(
                            template.inheritedInactiveCombos
                        ),
                        textureReadiness: readiness,
                        textureFormats: variantKey.resolvedTextureFormats
                    ) else {
                throw failure(.shaderPreparationFailed, phase: .preparation)
            }
            resolvedIntegerCombos = resolved
            do {
                // Source-proven texture typing reads the prepared source:
                // the canonical pair is a derived compiler input shape, and
                // feeding it here would weld backend lowering details into
                // the semantics layer. Cached analyses keep their stored
                // descriptors instead of recomputing (fail-closed).
                sourceActiveSamplers = try SceneResolvedMaterialShaderSchema
                    .activeSamplers(
                        prepared,
                        activeNames: Set(activeSamplerNames),
                        normalBlendModeIdentifiers: normalBlendIdentifiers(
                            resolvedIntegerCombos
                        )
                    )
            } catch {
                throw failure(.authoredSamplerSchemaInvalid)
            }
        }
        return (
            prepared,
            variantAnalysisKey,
            cachedAnalysis,
            compilerSources,
            compatibilityTargetAdmissionPending,
            analysisStart,
            runtimeLoopBounds,
            resolvedIntegerCombos,
            activeSamplerNames,
            sourceActiveSamplers
        )
    }
}
